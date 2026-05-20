# Hyperledger Fabric Audit Infrastructure

Repositori infrastruktur **Hyperledger Fabric 2.5.4 production-like** untuk keperluan Tesis Akademik. Mengimplementasikan jaringan blockchain *permissioned* dengan 2 Organisasi, consensus Raft (3 node), CouchDB sebagai state database, PostgreSQL + pgAudit sebagai off-chain audit log, Middleware Bridge asinkron, dan Hyperledger Explorer sebagai dashboard visual.

---

## Prasyarat Wajib

| Software | Version | Keterangan |
|---|---|---|
| Docker Desktop (WSL2 enabled) | ≥ 4.x | https://www.docker.com/products/docker-desktop/ |
| WSL2 + Ubuntu | Versi 2 | `wsl --install -d Ubuntu` |
| Node.js (untuk Middleware) | ≥ 16 LTS | https://nodejs.org |

> [!IMPORTANT]
> Semua perintah **harus dieksekusi dari dalam terminal WSL2 (Ubuntu)**, bukan PowerShell atau CMD. Docker Desktop harus dalam keadaan **running** dengan integrasi WSL2 diaktifkan sebelum menjalankan skrip apapun.

---

## Arsitektur Sistem

```
┌─────────────────────────────────────────────────────────┐
│                    fabric_test (Docker Network)          │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│  │Orderer 1 │  │Orderer 2 │  │Orderer 3 │  (Raft)        │
│  │:7050/7053│  │:8050/8053│  │:9050/9053│               │
│  └──────────┘  └──────────┘  └──────────┘               │
│                                                          │
│  ┌──────────────────┐   ┌──────────────────┐            │
│  │  Peer0 Org1      │   │  Peer0 Org2      │            │
│  │  :7051           │   │  :9051           │            │
│  │  └─ CouchDB :5984│   │  └─ CouchDB :7984│            │
│  └──────────────────┘   └──────────────────┘            │
│                                                          │
│  ┌──────────┐  ┌──────────────┐  ┌─────────────────┐   │
│  │   CLI    │  │  PostgreSQL  │  │    Explorer DB   │   │
│  │ (tools)  │  │  pgAudit     │  │   + Explorer UI  │   │
│  │          │  │  :5432       │  │   :8080          │   │
│  └──────────┘  └──────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## Struktur Direktori

```text
hyperledger_fabric/
├── .gitignore
├── README.md
├── context.md                       # Memo teknis & keputusan arsitektur
├── network/
│   ├── .env                         # Versi image Fabric (2.5.4)
│   ├── network.sh                   # Script utama (entry point)
│   ├── configtx/
│   │   └── configtx.yaml            # Konfigurasi channel & konsensus Raft
│   ├── docker/
│   │   ├── docker-compose-ca.yaml   # 3 Fabric CA (org1, org2, orderer)
│   │   ├── docker-compose-test-net.yaml  # Orderers, Peers, CouchDB, CLI
│   │   ├── docker-compose-pg.yaml   # PostgreSQL + pgAudit
│   │   └── pg/                      # Dockerfile + init SQL + postgresql.conf
│   ├── scripts/
│   │   ├── registerEnroll.sh        # Generate crypto materials via CA
│   │   └── createChannel.sh         # Dijalankan di dalam container CLI
│   └── explorer/
│       ├── config.json              # Konfigurasi Hyperledger Explorer
│       ├── connection-profile/
│       │   └── test-network.json    # Profil koneksi Explorer ke Org1
│       ├── docker-compose-explorer.yaml
│       └── start-explorer.sh
├── chaincode/
│   └── auditLog/                    # Smart Contract Node.js untuk audit log
└── middleware/
    ├── index.js                     # Bridge: PG log → Fabric Gateway
    └── package.json
```

---

## Cara Instalasi & Menjalankan

### Langkah 1: Clone Repositori dari GitHub
Buka terminal **Ubuntu (WSL2)** dan clone repositori ini ke PC lokal Anda:
```bash
# Pindah ke direktori tempat Anda ingin menyimpan project (contoh: /opt/)
cd /opt/
# Clone repositori (ganti URL dengan URL repositori GitHub Anda yang sebenarnya)
git clone https://github.com/USERNAME_ANDA/hyperladger_fabric.git
cd hyperladger_fabric
```
*(Catatan: Path pada langkah-langkah selanjutnya mengasumsikan Anda meng-clone ke `/opt/hyperladger_fabric`. Sesuaikan jika Anda menyimpannya di lokasi berbeda.)*

### Langkah 2: Persiapan Terminal WSL2 & Izin
Arahkan ke direktori `network` dan berikan izin eksekusi pada skrip:
```bash
cd /opt/hyperladger_fabric/network
chmod +x network.sh scripts/*.sh explorer/start-explorer.sh
sudo apt install -y dos2unix && dos2unix network.sh scripts/*.sh explorer/start-explorer.sh
```

### Langkah 3: Install Fabric Binaries (Sekali saja)
```bash
./network.sh installBinaries
# Tambahkan ke PATH agar bisa memanggil 'peer' atau 'osnadmin' dari manapun
echo 'export PATH="/opt/hyperladger_fabric/network/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

### Langkah 4: Deploy Jaringan Blockchain
```bash
./network.sh down          # Bersihkan state lama & volume
./network.sh up            # Nyalakan CA, Peer, Orderer
./network.sh createChannel   # Membuat channel 'mychannel'
```

### Langkah 5: Nyalakan Database Audit (PostgreSQL)
```bash
./network.sh startPostgres
```

### Langkah 6: Nyalakan Hyperledger Explorer (Dashboard Visual)
```bash
./network.sh startExplorer
```

### Langkah 7: Jalankan Middleware (Log Bridge)
```bash
cd /opt/hyperladger_fabric/middleware
npm install && npm start
```

---

## 🔐 Informasi Login & Akses Cepat (Credentials)

| Layanan | URL Akses | Username | Password |
|---|---|---|---|
| **Hyperledger Explorer** | [http://localhost:8080](http://localhost:8080) | `admin` | `adminpw` |
| **PostgreSQL (Database)** | `localhost:5432` | `admin` | `adminpw` |
| **CouchDB Org1 Admin** | [http://localhost:5984/_utils](http://localhost:5984/_utils) | `admin` | `adminpw` |
| **CouchDB Org2 Admin** | [http://localhost:7984/_utils](http://localhost:7984/_utils) | `admin` | `adminpw` |

> [!TIP]
> **Database Name**: `offchaindb` (untuk PostgreSQL)  
> **Channel Name**: `mychannel` (untuk Fabric)

> [!CAUTION]
> Perintah ini menghapus **semua** data: kontainer, volume Docker, dan folder `organizations/` (crypto materials). Ini adalah perilaku yang diinginkan — pastikan Anda memahami bahwa seluruh state jaringan akan terhapus dan harus dimulai ulang dari awal.

---

## Pemeliharaan & Troubleshooting

### Error: "creator is malformed" / "unknown authority"
Penyebab: Kontainer Peer/Orderer masih menyimpan **state volume lama** dari sertifikat yang berbeda dengan CA yang sekarang berjalan.

**Solusi wajib**:
```bash
./network.sh down   # Hapus semua (termasuk volume)
./network.sh up     # Generate ulang dari nol
./network.sh createChannel
```

### Error: "Exit Code 255" / Kontainer Mati Sendiri
Penyebab: Resource limit pada Docker Desktop (RAM/CPU habis) atau restart backend WSL2.

**Solusi**:
1. Pastikan Docker Desktop berjalan dan integrasi WSL2 aktif.
2. Tambah alokasi memori Docker Desktop (Settings → Resources → Memory, minimal 8GB).
3. Jalankan `./network.sh up` untuk me-restart kontainer.

### Error: Explorer "Default client peer is down"
Penyebab: Explorer tidak bisa terhubung ke peer karena channel belum dibuat atau cert tidak cocok.

**Solusi**:
1. Pastikan `./network.sh createChannel` sudah berhasil dijalankan.
2. Jika masih gagal, lakukan Nuclear Cleanup dan deploy ulang.

---

## Port Reference

| Service | Port | Keterangan |
|---|---|---|
| CA Org1 | 7054 | Fabric CA server |
| CA Org2 | 8054 | Fabric CA server |
| CA Orderer | 9054 | Fabric CA server |
| Orderer 1 | 7050 / 7053 | gRPC / Admin (osnadmin) |
| Orderer 2 | 8050 / 8053 | gRPC / Admin (osnadmin) |
| Orderer 3 | 9050 / 9053 | gRPC / Admin (osnadmin) |
| Peer Org1 | 7051 | gRPC Peer (endorser) |
| Peer Org2 | 9051 | gRPC Peer (endorser) |
| CouchDB Org1 | 5984 | REST Admin UI |
| CouchDB Org2 | 7984 | REST Admin UI |
| PostgreSQL | 5432 | psql / pgAdmin |
| Explorer | 8080 | Web Dashboard |

---

## Lisensi
Apache-2.0 — Dimodifikasi dari Hyperledger Fabric Samples untuk keperluan Tesis Akademik.
