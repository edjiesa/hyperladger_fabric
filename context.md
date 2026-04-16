# Application Context & Thesis Design Details

Dokumen `context.md` ini disiapkan sebagai *technical memo* dan pengingat filosofis yang mendasari keputusan arsitektur (Architecture Decisions) di dalam ekosistem *hybrid blockchain-database* proyek ini.

## 1. Problem Statement (Pernyataan Masalah)
Sistem basis data operasional (PostgreSQL, MySQL, dsb.) secara _native_ rentan terhadap manipulasi tingkat lanjut oleh akun Superadmin (_Privilege Escalation_ atau eksekusi _under-the-table DML_). Di sisi lain, sebuah sistem murni _Blockchain_ terlalu berbiaya tinggi dan tak efisien jika digunakan untuk menyimpan _query_ kompleks dengan _throughput_ data relasional per sekian detik.

Maka, dibutuhkan *Sistem Hibrida*: 
Data utama (sistem aplikasi asimilasi pengguna secara dinamis) disimpan *Off-chain* di Relational Database Server, sedangkan Validasi (Audit Log Integritas Relasional tersebut) disimpan secara permanen pada struktur *On-Chain* di Ledger Fabric.

## 2. Arsitektur Komponen Terpilih

* **Hyperledger Fabric (HLF):** Framework *permissioned blockchain* diutamakan. Penggunaan HLF dipilih ketimbang blockchain publik (seperti Ethereum) karena fokusnya pada tata kelola B2B (Bisnis), identitas digital (Fabric CA Server / MSP), dan biaya pemrosesan transaksi yang gratis.
* **pgAudit (PostgreSQL Audit Extension):** Ketimbang membangun logika abstrak sistem _logging manual_ dari level aplikasi berbasis bahasa pemerograman (dimana sebuah bug aplikasi dapat merusak audit), `pgAudit` hidup langsung menyatu (natively bind) di dalam runtime basis data itu sendiri. Setiap rotasi _Disk IO_ yang mengubah data, akan terekam oleh kernel db terlepas dari _frontend gateway_ manapun.
* **Konsensus Raft:** Desain tes uji Tesis ini menggunakan pola _etcdraft consensus_. Menghindari _Solo Orderer_ (yang secara fungsional telah punah/deprecated sejak versi fabric v2) dan menghindari Kafka (yang memakan RAM terlalu besar). Raft secara teknis bisa berjalan hanya dengan memori pasif sekitar `~2 GB RAM` pada _idling container_.

## 3. Topologi & Skematis (Resource Constraint 16GB)

Untuk tesis akademis, penguji kadang kala menuntut bukti bahwa jaringan cukup terdesentralisasi (2 level Organisasi terpisah). Di RAM 16GB, berikut topologi rasionalisasinya:
- 1 Root CA per entita pengaman jaringan (total 3 CA) untuk manajemen lisensi kriptografi (*X.509 certs*).
- **Redundancy** hanya diterapkan pada konsensus (Raft - 3 Nodes), karena toleransi patah tulang protokol HLF tidak boleh _single-point-of-failure_ (SPOF) di Ordering Service.
- **Efisiensi Peer:** Diminimalisasi menjadi tepat 1 Endorsing Peer per Organisasi. Penjejakan memori 1 Peer biasanya `~100MB`, yang menekan angka *footprint* di host *virtualized env* Docker secara signifikan.
- **CouchDB:** Ditambahkan opsional karena *LevelDB* tidak mensupport query _state database JSON_.

## 4. Middleware: Sinkronisasi Asinkron (Asynchronous Bridge)

Sebuah paradigma diatur bahwa Middleware Node.js tidak menggunakan **Two-Phase Commit (2PC)**:
Tesis ini menghindari 2PC (*synchronous*) demi kecepatan latensi log. Jika setiap kali Postgres meng-INSERT data harus menunggu `ledger.commit()`, server akan melambat secara eksponensial.
Sesuai pendekatan di *Microservices*, *Bridge (index.js)* menjalankan prinsip rekonsiliasi _Asynchronous Fire-and-Forget Tailing Log_: Eksekusi utama basis data sangat cepat, log di-*dump* ke _hard disk_ (`csvlog`), agen (Middleware Node) mengejar baris terbawah secara independen dan meng-_endorse_ perubahan log tsb masuk ke Hyperledger Fabric.

*(Dokumen ini dapat dikutip kembali sebagai rujukan penyusunan latar belakang infrastruktur di jurnal/tesis Anda).*

---

## 5. Operational Stability & Maintenance

### A. Nuclear Cleanup vs. Volume Persistence
Dalam pengembangan di lingkungan Windows/WSL2, Docker Compose seringkali membuat prefix volume yang tidak konsisten (misal: `compose_` vs `fabric-network_`) tergantung pada bagaimana daemon dipanggil. Hal ini menyebabkan perintah `docker compose down -v` standar gagal menghapus volume Peer/Orderer. 
Sertifikat "stale" yang tertinggal di volume inilah yang menyebabkan error **"malformed creator/unknown authority"**. Arsitektur `network.sh` dalam repositori ini telah dimodifikasi untuk melakukan pembersihan volume secara eksplisit menggunakan pencocokan pola (*pattern matching*), memastikan setiap deployment dimulai dari titik nol yang benar-benar bersih.

### B. Otomasi Manajemen User (Explorer Integration)
Untuk menjaga keamanan dan kemudahan penggunaan, sistem ini mengotomatiskan pemetaan *Private Key* Admin. Karena Fabric CA men-generate kunci dengan nama *hash* dinamis, `network.sh` melakukan inspeksi direktori setelah pendaftaran identitas untuk mendeteksi kunci tersebut dan memetakannya ke sebuah nama statis (`priv_sk`) yang telah dikonfigurasi pada *Connection Profile* Hyperledger Explorer. Ini menghilangkan intervensi manual yang rentan kesalahan (*error-prone manual intervention*).

