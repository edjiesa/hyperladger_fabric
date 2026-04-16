# Hyperledger Fabric Audit Infrastructure

Repositori lengkap infrastruktur **Hyperledger Fabric 2.5.x production-like** dengan 2 Organisasi, consensus Raft, CouchDB, PostgreSQL pgAudit, Middleware Bridge, dan Hyperledger Explorer.

---

## Prasyarat Wajib

| Software | Version | Link |
|---|---|---|
| Docker Desktop (WSL2 enabled) | ≥ 4.x | https://www.docker.com/products/docker-desktop/ |
| WSL2 + Ubuntu | Versi 2 | `wsl --install -d Ubuntu` |
| Node.js (untuk Middleware) | ≥ 16 LTS | https://nodejs.org |

> **Penting untuk Windows**: Semua perintah di bawah ini harus dieksekusi dari dalam terminal **WSL2 (Ubuntu)**, bukan PowerShell atau CMD.

---

## Struktur Direktori

```text
hyperledger_fabric/
├── network/
│   ├── .env                         # Versi image Fabric (2.5.4)
│   ├── network.sh                   # Script utama (entry point)
│   ├── configtx/
│   │   └── configtx.yaml            # Konfigurasi channel & konsensus Raft
│   ├── docker/
│   │   ├── docker-compose-ca.yaml   # 3 Fabric CA (org1, org2, orderer)
│   │   ├── docker-compose-test-net.yaml  # Orderers, Peers, CouchDB, CLI
│   │   ├── docker-compose-pg.yaml   # PostgreSQL + pgAudit
│   │   └── pg/                      # Dockerfile + config untuk pgAudit
│   ├── scripts/
│   │   ├── registerEnroll.sh        # Generate crypto materials via CA
│   │   └── createChannel.sh         # Dijalankan di dalam container CLI
│   └── explorer/
│       ├── config.json              # Konfigurasi Hyperledger Explorer
│       ├── connection-profile/      # Profil koneksi Explorer ke Org1
│       ├── docker-compose-explorer.yaml
│       └── start-explorer.sh
├── chaincode/
│   └── auditLog/                    # Smart Contract Node.js untuk audit log
└── middleware/
    ├── index.js                     # Bridge: PG log -> Fabric Gateway
    └── package.json
```

---

## Cara Instalasi & Menjalankan

### Langkah 0: Buka Terminal WSL2 (Ubuntu)

Di Windows, buka **Start** → cari **Ubuntu** → buka terminal. Kemudian masuk ke direktori proyek:

```bash
cd /mnt/c/DATA/GITHUB/hyperladger_fabric/network
```

Berikan izin eksekusi satu kali:
```bash
chmod +x network.sh scripts/*.sh explorer/start-explorer.sh
```

Fix Windows line-endings (penting jika menggunakan Windows editor):
```bash
sudo apt install -y dos2unix
dos2unix network.sh scripts/*.sh explorer/start-explorer.sh
```

---

### Langkah 1: Download Fabric Binaries (Hanya pertama kali)

```bash
./network.sh installBinaries
```

Tambahkan binary ke PATH agar bisa dipakai permanen:
```bash
echo 'export PATH="$HOME/bin:/mnt/c/DATA/GITHUB/hyperladger_fabric/network/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

### Langkah 2: Nyalakan Jaringan Blockchain

```bash
./network.sh up
```

Proses ini akan:
- ✅ Menyalakan 3 Fabric CA containers
- ✅ Mendaftarkan & meng-enroll semua identitas (Admin, Peer, Orderer)
- ✅ Men-generate genesis block `mychannel.block`
- ✅ Menyalakan 3 Orderer + 2 Peers + 2 CouchDB

---

### Langkah 3: Buat Channel dan Gabungkan Peer

```bash
./network.sh createChannel
```

---

### Langkah 4: Nyalakan Database Off-Chain (pgAudit)

```bash
./network.sh startPostgres
```
Database PostgreSQL siap diakses di `localhost:5432`:
- **User**: `admin` | **Password**: `adminpw` | **DB**: `offchaindb`

---

### Langkah 5: Nyalakan Middleware (Log Bridge)

```bash
cd /mnt/c/DATA/GITHUB/hyperladger_fabric/middleware
npm install
npm start
```

---

### Langkah 6: Buka Hyperledger Explorer (Dashboard Visual)

```bash
cd /mnt/c/DATA/GITHUB/hyperladger_fabric/network
./network.sh startExplorer
```

> [!TIP]
> **Otomasi Kredensial**: Script `./network.sh up` sekarang secara otomatis mendeteksi dan menyediakan Admin Private Key (`priv_sk`) untuk Explorer. Anda tidak perlu lagi melakukan copy-paste manual file secret key.

Buka browser: **http://localhost:8080**
- **Username**: `admin`
- **Password**: `adminpw`

---

## Pemeliharaan & Troubleshooting

### Nuclear Cleanup (Hard Reset)
Jika Anda mengalami error **"access denied"** atau **"creator is malformed"** (biasanya karena ketidakcocokan sertifikat lama di Docker Volume), gunakan fitur pembersihan menyeluruh kami:

```bash
./network.sh down
```
Fungsi ini akan menghapus:
- Seluruh folder `organizations/` (Crypto materials)
- Semua Docker Volumes (Peer, Orderer, CouchDB) terlepas dari prefix project-nya.
- Semua kontainer terkait.

### Error: Exit Code 255
Jika kontainer tiba-tiba mati (status `Exited (255)`), ini biasanya disebabkan oleh resource limit pada Docker Desktop atau restart backend WSL2.
**Solusi**:
1. Pastikan Docker Desktop sedang berjalan dan integrasi WSL2 aktif.
2. Jalankan kembali `./network.sh up` untuk memastikan kontainer hidup kembali.

### Error: Malformed Creator / Unknown Authority
Ini terjadi jika kontainer Orderer/Peer masih membawa "ingatan" volume lama saat CA baru dinyalakan.
**Solusi**: Pastikan Anda menjalankan `./network.sh down` (Nuclear Cleanup) sebelum melakukan deploy ulang dengan `./network.sh up`.


---

### Mematikan Seluruh Network

```bash
./network.sh down
```

---

## Port Reference

| Service | Port | Keterangan |
|---|---|---|
| CA Org1 | 7054 | Fabric CA server |
| CA Org2 | 8054 | Fabric CA server |
| CA Orderer | 9054 | Fabric CA server |
| Orderer 1 | 7050 / 7053 | gRPC / Admin |
| Orderer 2 | 8050 / 8053 | gRPC / Admin |
| Orderer 3 | 9050 / 9053 | gRPC / Admin |
| Peer Org1 | 7051 | gRPC Peer |
| Peer Org2 | 9051 | gRPC Peer |
| CouchDB Org1 | 5984 | REST Admin |
| CouchDB Org2 | 7984 | REST Admin |
| PostgreSQL | 5432 | psql / pgAdmin |
| Explorer | 8080 | Web Dashboard |

---

## Lisensi
Apache-2.0 — Dimodifikasi dari Hyperledger Fabric Samples untuk keperluan Tesis Akademik.
