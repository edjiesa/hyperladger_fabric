# Application Context & Thesis Design Details

Dokumen `context.md` ini disiapkan sebagai *technical memo* dan pengingat filosofis yang mendasari keputusan arsitektur (*Architecture Decision Records / ADR*) di dalam ekosistem *hybrid blockchain-database* proyek ini.

---

## 1. Problem Statement (Pernyataan Masalah)

Sistem basis data operasional (PostgreSQL, MySQL, dsb.) secara _native_ rentan terhadap manipulasi tingkat lanjut oleh akun Superadmin — baik melalui _Privilege Escalation_ maupun eksekusi _under-the-table DML_ yang tidak terekam. Di sisi lain, sebuah sistem murni _Blockchain_ terlalu berbiaya tinggi dan tidak efisien jika digunakan untuk menyimpan data relasional dengan _throughput_ tinggi.

**Solusi yang Dipilih — Sistem Hibrida:**
- Data utama (transaksi operasional) disimpan **Off-chain** di Relational Database (PostgreSQL).
- Validasi integritas data (Audit Log) disimpan secara permanen dan _tamper-proof_ **On-chain** di Hyperledger Fabric Ledger.

---

## 2. Arsitektur Komponen Terpilih

### Hyperledger Fabric (HLF)
Framework *permissioned blockchain* dipilih ketimbang blockchain publik (seperti Ethereum) karena:
- Fokus pada tata kelola B2B (*Business-to-Business*).
- Identitas digital berbasis **Fabric CA** (X.509 Certificate) yang dapat dikelola secara terpusat.
- Biaya transaksi nol (tidak ada token/gas fee).
- Kontrol penuh atas siapa yang dapat membaca dan menulis data (*channel policy*).

### pgAudit (PostgreSQL Audit Extension)
Ketimbang membangun logika *logging manual* dari level aplikasi (yang rentan terhadap bug atau bypass), `pgAudit` **hidup langsung di dalam runtime database itu sendiri**. Setiap perubahan data yang melewati mesin PostgreSQL — terlepas dari *frontend gateway* mana pun yang mengirimnya — akan terekam oleh kernel DB.

### Consensus Raft (etcdraft)
Desain menggunakan **3-node Raft Ordering Service**:
- Menghindari *Solo Orderer* (deprecated sejak Fabric v2.0).
- Menghindari Kafka/Zookeeper (overhead RAM terlalu besar untuk lingkungan tesis).
- Raft dengan 3 node dapat mentolerasi kegagalan 1 node (*fault tolerance = (n-1)/2*).
- Footprint memori saat idle: **~2 GB RAM** untuk seluruh Ordering Service.

---

## 3. Topologi & Skematis (Resource Constraint 16GB RAM)

Untuk tesis akademis yang membutuhkan bukti desentralisasi (minimal 2 Organisasi terpisah):

| Komponen | Jumlah | Alasan |
|---|---|---|
| Fabric CA | 3 | 1 per entitas (Org1, Org2, Orderer) |
| Orderer | 3 | Raft minimal untuk fault tolerance (n=1) |
| Peer | 1 per Org | Meminimalkan footprint memori (~100MB/peer) |
| CouchDB | 1 per Peer | State database JSON untuk rich query |
| CLI | 1 | Admin tooling di dalam jaringan |

**Catatan Memori**: Konfigurasi ini didesain agar total footprint saat idle tidak melebihi **~8 GB RAM**, menyisakan ruang untuk OS dan aplikasi lain di laptop 16GB.

---

## 4. Middleware: Sinkronisasi Asinkron (Asynchronous Bridge)

Middleware Node.js **tidak menggunakan Two-Phase Commit (2PC)** karena:
- Jika setiap INSERT di Postgres harus menunggu `ledger.commit()` selesai, latensi database akan meningkat secara eksponensial.
- Kegagalan pada Fabric tidak boleh menghentikan operasi database utama.

**Paradigma yang Diterapkan — *Asynchronous Fire-and-Forget Tailing Log*:**
1. Aplikasi melakukan INSERT ke PostgreSQL dengan latensi rendah.
2. `pgAudit` mencatat perubahan secara atomik ke `csvlog` di disk.
3. Middleware Node.js secara independen *mengekor* (tail) log terbaru.
4. Setiap entri log di-*endorse* dan di-*commit* ke Hyperledger Fabric secara asinkron.

Pendekatan ini konsisten dengan prinsip *Eventual Consistency* pada arsitektur *Microservices*.

---

## 5. Operational Stability & Maintenance

### A. Nuclear Cleanup — Solusi Volume Persistence di WSL2

**Masalah**: Dalam pengembangan di lingkungan Windows/WSL2, Docker Compose sering membuat volume dengan **prefix yang tidak konsisten**. Selain itu, image Fabric memiliki directive `VOLUME` yang membuat **anonymous volumes** yang menyimpan stale state (cert lama), menyebabkan error **"malformed creator"**.

**Solusi yang diimplementasikan di `network.sh`**:
```bash
# 1. Hapus semua named volume matching pola
VOLS=$(docker volume ls -q | grep -E '(orderer|peer|couchdb|pgdata|wallet|audit|postgres|explorer)\.(example\.com|instance)')
VOLS2=$(docker volume ls -q | grep -E '^(compose_|fabric-network_|fabric_)(orderer|peer|couch|explorer|postgres|audit)')
ALL_VOLS="${VOLS} ${VOLS2}"
if [ -n "$(echo "${ALL_VOLS}" | tr -d ' ')" ]; then
    docker volume rm ${ALL_VOLS} 2>/dev/null || true
fi

# 2. Hapus Anonymous/Dangling volumes (Kritikal!)
docker volume prune -f 2>/dev/null || true
```

### B. Isolated MSP Mounts & Dynamic Keys

**Masalah**: Bind mount ke `/etc/hyperledger/fabric/` sering ter-override oleh anonymous volume internal peer. Juga, Fabric CA men-generate private key dengan nama hash dinamis yang menyulitkan konfigurasi statis.

**Solusi**:
1. **Isolated Path**: Peer me-mount MSP dan TLS ke `/mnt/msp` dan `/mnt/tls` (di luar `/etc/hyperledger/fabric/`) untuk menghindari konflik.
2. **Statisasi Key**: `network.sh` secara otomatis menyalin key dinamis menjadi `priv_sk` untuk kemudahan pembacaan oleh Hyperledger Explorer.

### C. Internal Networking (Orderer Endpoints)

**Masalah**: Discovery Service mengembalikan endpoint Orderer yang terdaftar di `configtx.yaml`. Jika port eksternal yang didaftarkan, komponen internal (Explorer) gagal terhubung.

**Solusi**: `OrdererEndpoints` di `configtx.yaml` disetel ke internal port **7050**.

### D. Urutan Deploy yang Benar

Urutan ini **wajib** diikuti untuk menghindari ketidakcocokan sertifikat:

```bash
down → up → createChannel → startPostgres → startExplorer → middleware
```

Jangan pernah menjalankan `up` dua kali berturut-turut tanpa `down` di antara keduanya.

---

## 6. Akses Cepat & Kredensial Pengguna

| Layanan | Endpoint | Username | Password |
|---|---|---|---|
| **Hyperledger Explorer** | `localhost:8080` | `admin` | `adminpw` |
| **PostgreSQL (pgAudit)** | `localhost:5432` | `admin` | `adminpw` |
| **CouchDB Org1** | `localhost:5984` | `admin` | `adminpw` |
| **CouchDB Org2** | `localhost:7984` | `admin` | `adminpw` |

---

*(Dokumen ini dapat dikutip kembali sebagai rujukan penyusunan latar belakang infrastruktur di jurnal/tesis Anda.)*
