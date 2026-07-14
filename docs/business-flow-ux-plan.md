# Audit Alur Bisnis dan UX - Sawit CB

Tanggal audit: 14 Juli 2026

Dokumen ini memetakan tujuan website, kondisi alur saat ini, use case, activity user, gap standar pencatatan, dan rencana perubahan menuju sistem business management yang lebih matang.

## 1. Ringkasan Eksekutif

Sawit CB sudah berada di arah yang benar sebagai sistem bisnis RAM sawit: ada pemisahan sumber TBS lokal dan mitra, ada snapshot harga/fee, ada buku kas, hutang/panjar universal, status pembayaran kwitansi, reversal untuk beberapa flow finansial, dan role Owner/Super Admin/Admin Operasional/Admin Keuangan.

Kondisi saat ini paling tepat disebut **Sistem Bisnis Minimal Fase 2**. Sistem sudah dapat mendukung kontrol kas dan hutang harian, tetapi belum layak diposisikan sebagai sistem final karena settlement mitra advanced, alokasi pembayaran pabrik multi-transaksi, bukti/lampiran transaksi, approval limit kasbon, audit/role hardening penuh, dan tutup-harian belum lengkap.

Prioritas perbaikan terbaik bukan menambah halaman baru sebanyak mungkin, melainkan menata ulang workflow agar pengguna bekerja mengikuti siklus bisnis harian:

1. Set/cek harga dan master aktif.
2. Input transaksi operasional.
3. Rekam uang aktual ke ledger.
4. Rekonsiliasi stok, DO, hutang/panjar, dan kas.
5. Cetak/kirim bukti.
6. Tutup hari dengan laporan dan audit exception.

## 2. Tujuan Produk yang Terbaca

Sawit CB adalah aplikasi internal untuk bisnis RAM kelapa sawit yang harus mencatat:

- Pembelian TBS dari petani lokal.
- Stok sementara TBS lokal.
- Pengiriman TBS dari mitra, termasuk mitra internal untuk hasil pembelian lokal yang dikirim ke pabrik.
- Harga TBS lokal, harga pabrik/TWB, fee owner, dan snapshot harga saat transaksi.
- Panjar/kasbon/hutang lintas pihak.
- Biaya operasional.
- Uang masuk pabrik dan uang keluar ke petani/mitra/pihak lain.
- Kwitansi, bukti pembayaran, laporan harian, laporan stok, laporan mitra, dan laba-rugi owner.

Implikasi bisnisnya: sistem harus lebih dekat ke **ledger dan rekonsiliasi** daripada sekadar CRUD. Setiap transaksi yang menyentuh uang, stok, tonase, pembayaran, atau hutang harus punya sumber data, status, alasan koreksi, dan jejak audit.

## 3. Prinsip Standar Business Management dan Pencatatan

Prinsip yang harus menjadi standar desain alur:

- **Ledger-first**: kas, hutang/panjar, dan stok dihitung dari mutasi, bukan angka manual yang ditimpa.
- **Snapshot rate**: harga, fee, tarif, dan rumus yang berlaku saat transaksi wajib disimpan agar perubahan master tidak mengubah histori.
- **No physical delete**: transaksi finansial/operasional memakai batal, reversal, atau koreksi dengan alasan.
- **Segregation of duties**: admin operasional input transaksi, admin keuangan input pembayaran/kas, owner/super admin melihat profit dan override.
- **Evidence-based**: DO, tiket timbang, bukti transfer, kwitansi, dan alasan koreksi harus bisa dilampirkan atau minimal diberi nomor referensi.
- **Reconciliation-first reporting**: laporan utama harus menunjukkan selisih, transaksi pending, settlement belum selesai, kwitansi perlu review, stok minus, dan hutang melewati limit.
- **Close day discipline**: akhir hari harus ada proses review kas, stok, DO, biaya, hutang, dan transaksi batal/koreksi.
- **Role enforcement di backend**: menu boleh disembunyikan, tetapi database/RPC/RLS tetap harus menolak role yang tidak berhak.

## 4. Peta Modul Saat Ini

| Area | Route Saat Ini | Fungsi | Catatan |
| --- | --- | --- | --- |
| Auth | `/login` | Login Supabase Auth | Sudah ada redirect session. |
| Dashboard | `/dashboard` | Harga pabrik, ringkasan mitra/petani, quick action | Sudah mulai diarahkan menjadi command center harian. |
| Mitra | `/admin/input-timbangan` | Input pengiriman mitra | Nama route/menu sebaiknya menjadi "Pengiriman Mitra". |
| Mitra | `/owner/riwayat-pengiriman-mitra` | Edit/batal transaksi mitra | Sudah ada audit log untuk edit/batal. |
| Mitra | `/owner/kwitansi-mitra` | Cetak, WhatsApp, tandai dibayar | Sudah memakai snapshot pembayaran batch. |
| Mitra | `/owner/panjar-mitra` | Arsip panjar mitra | Bukan pintu input. Input panjar satu pintu lewat `/keuangan/hutang`. |
| Mitra | `/owner/laporan-mitra` | Rekap pengiriman mitra | Cocok sebagai laporan operasional, bukan profit. |
| Owner | `/owner/pendapatan-owner` | Pendapatan owner bruto | Harus tetap owner/super admin only. |
| Lokal | `/transaksi/beli` | Pembelian TBS petani lokal | Dibekukan sementara sebagai Coming Soon sampai alur lokal selesai. |
| Lokal | `/transaksi/kirim` | Pengiriman lokal ke pabrik | Route lama/opsional. Alur utama sebaiknya memakai mitra internal agar tidak ada workflow pengiriman lokal yang dobel. |
| Keuangan | `/keuangan/kas` | Buku kas | Sudah ledger-first, masih perlu bukti/ref/closing. |
| Keuangan | `/keuangan/hutang` | Hutang dan panjar semua pihak | Sudah lintas pihak, approval limit belum final. |
| Keuangan | `/keuangan/biaya` | Biaya operasional | Sudah kas ledger dan batal/reversal. |
| Laporan | `/laporan/harian` | Rekap harian lama | Disembunyikan dari navigasi. Akan dibangun ulang sebagai Closing Harian. |
| Laporan | `/laporan/stok` | Rekonsiliasi stok lokal | Dibekukan sementara sebagai Coming Soon sampai alur stok lokal selesai. |
| Laporan | `/laporan/laba-rugi` | Profit owner | Memakai kas ledger; laba final menunggu pembayaran pabrik tercatat sebagai kas masuk. |
| Master | `/master/*`, `/owner/master-data` | Petani, pabrik, armada, mitra, sopir, harga | Perlu konsolidasi istilah dan searchable selector merata. |

## 4.1 Sumber Data Kanonik dan Legacy

Standar sumber data yang harus dipakai agar UI sinkron:

| Area Data | Sumber Kanonik | Legacy / Perlu Ditahan | Aturan UI |
| --- | --- | --- | --- |
| Pengiriman mitra dan mitra internal | `transaksi_mitra` | `pengiriman` dengan `sumber = lokal` | Dashboard, Laporan Mitra, Kwitansi, Pendapatan Owner, dan Closing Harian berikutnya membaca `transaksi_mitra`. Route `/transaksi/kirim` hanya arsip legacy. |
| Pembelian petani lokal | `transaksi_beli_tbs` + RPC `create_transaksi_beli_tbs` | Input manual langsung ke tabel | Semua input pembelian wajib lewat RPC agar stok, kas, dan hutang ikut terbentuk. UI dikunci sementara sampai alur lokal final. |
| Stok lokal | `stok_tbs_lokal_ledger` | Angka stok manual | Stok dihitung dari mutasi masuk/keluar/koreksi, bukan field saldo yang diedit. UI dikunci sementara sampai rekonsiliasi stok final. |
| Kas | `kas_ledger` + RPC kas terkait | Catatan kas di tabel transaksi tanpa ledger | Buku Kas dan Laba/Rugi memakai kas ledger sebagai uang aktual. |
| Hutang/panjar semua pihak | `hutang_ledger` | Angka sisa yang diedit manual | UI menyebut hasil hitungnya "Sisa Hutang/Panjar", bukan "saldo aktif". |
| Panjar mitra yang dipotong kwitansi | `panjar_mitra` + `hutang_ledger` | Panjar mitra yang hanya dicatat di `hutang_ledger` | Input tetap satu pintu lewat Hutang & Panjar. Jika pihak Mitra dan jenis Panjar, sistem memanggil `create_panjar_mitra_kas` agar Kwitansi Mitra bisa memotongnya. |
| Armada internal/perusahaan | `master_mitra` tipe internal + `sopir.mitra_id` + `sopir.plat_nomor` | `armada_perusahaan`, `kendaraan`, `sopir.armada_perusahaan_id`, `sopir.kendaraan_id` | Armada dikelola di menu Armada, tetapi tetap memakai tabel `sopir` dan afiliasi mitra agar alur pengiriman satu pintu. |
| Sopir/plat default mitra | `sopir.mitra_id` + `sopir.plat_nomor` | `armada_mitra` lama/parsial | Menu Armada memakai tabel `sopir` sebagai default autofill transaksi mitra. |

### 4.2 Status Modul Lokal/Petani

Untuk rilis saat ini, modul lokal/petani dibekukan sementara sebagai **Coming Soon** agar user tidak memakai alur yang belum selesai:

- `/transaksi/beli` - Pembelian Petani Lokal.
- `/master/petani` - Petani Lokal.
- `/laporan/petani` - Laporan Petani.
- `/laporan/stok` - Stok Lokal.

Halaman tetap boleh dibuka untuk melihat bentuk dan data konteks, tetapi input, tombol aksi, dan perubahan data dinonaktifkan. Alur lokal akan dibuka kembali setelah pembelian petani, stok lokal, laporan petani, dan rekonsiliasi ke mitra internal sudah satu sumber data dan lolos uji kas/stok.

## 5. Use Case Utama

| ID | Use Case | Aktor Utama | Prasyarat | Hasil Bisnis | Status Saat Ini |
| --- | --- | --- | --- | --- | --- |
| UC-01 | Login dan validasi role | Semua user | Akun Supabase dan row `users` ada | User masuk sesuai role | Ada. |
| UC-02 | Kelola master petani | Owner, Super Admin, Admin Operasional | Role operasi | Petani aktif untuk transaksi lokal | Ada, tetapi UI dikunci sementara sebagai Coming Soon. |
| UC-03 | Kelola master mitra, mitra internal, sopir, dan plat default | Owner, Super Admin, Admin Operasional | Role operasi | Mitra, fee owner, armada internal, sopir, plat siap dipakai | Ada. |
| UC-04 | Kelola pabrik tujuan | Owner, Super Admin, Admin Operasional | Role operasi | Pabrik aktif untuk DO | Ada. |
| UC-05 | Set harga pabrik/TWB | Owner, Super Admin, Admin Operasional sesuai kebijakan | Harga harian diketahui | Transaksi mitra menyimpan harga snapshot | Ada, masih perlu rule approval bila sensitif. |
| UC-06 | Set harga beli lokal | Owner, Super Admin, Admin Operasional sesuai kebijakan | Harga pembelian diset | Pembelian petani dapat berjalan | Ada. |
| UC-07 | Input pembelian TBS lokal | Admin Operasional | Petani dan harga aktif | Transaksi, stok masuk, kas keluar/potong hutang | Ada, tetapi UI dikunci sementara sebagai Coming Soon. |
| UC-08 | Batalkan pembelian lokal | Owner, Super Admin, role yang diizinkan | Transaksi belum dikunci periode | Status batal dan reversal ledger | Ada, tetapi UI dikunci sementara sebagai Coming Soon. |
| UC-09 | Kirim hasil pembelian lokal sebagai mitra internal | Admin Operasional | Mitra internal, sopir/plat, harga pabrik aktif | Pengiriman masuk ke transaksi mitra internal | Perlu dirapikan dari route lokal lama. |
| UC-10 | Rekam settlement/pembayaran pabrik | Admin Keuangan, Owner, Super Admin | Transaksi mitra internal ada | Kas masuk dan rekonsiliasi pembayaran | Target fase rekonsiliasi berikutnya. |
| UC-11 | Input pengiriman mitra | Admin Operasional | Mitra, sopir, harga pabrik, fee aktif | Transaksi mitra dengan snapshot harga/fee | Ada. |
| UC-12 | Koreksi/batalkan transaksi mitra | Owner, Super Admin, role terbatas | Ada alasan koreksi | Transaksi berubah/batal dengan audit | Ada dasar. |
| UC-13 | Catat panjar/kasbon | Admin Keuangan, Owner, Super Admin | Pihak jelas | Hutang/panjar dan kas ledger tercatat | Ada. |
| UC-14 | Catat biaya operasional | Admin Keuangan, Admin Operasional, Owner | Kategori biaya jelas | Kas keluar dan biaya tercatat | Ada. |
| UC-15 | Buat kwitansi mitra | Admin Keuangan, Owner, Super Admin | Transaksi mitra periode tersedia | Bukti pembayaran mitra | Ada. |
| UC-16 | Tandai kwitansi dibayar | Admin Keuangan, Owner, Super Admin | Kas tersedia, periode dipilih | Kas keluar, panjar dipotong, snapshot pembayaran | Ada. |
| UC-17 | Kirim kwitansi WhatsApp | Admin Keuangan, Owner | Nomor WA valid | Pesan ringkasan dan instruksi PDF | Ada MVP link/manual. |
| UC-18 | Lihat buku kas | Admin Keuangan, Owner, Super Admin | Ledger kas tersedia | Posisi masuk/keluar per periode | Ada. |
| UC-19 | Lihat laba-rugi owner | Owner, Super Admin | Data kas/transaksi ada | Laba kas dan estimasi transaksi | Ada dengan guard UI dan role helper. |
| UC-20 | Audit log dan release gate | Owner, Super Admin | Audit aktif | Riwayat perubahan sensitif | Ada parsial, perlu UI audit dan verifikasi RLS. |

## 6. Activity User yang Direkomendasikan

### 6.1 Activity Harian Admin Operasional

1. Buka Dashboard.
2. Cek status harga pabrik/TWB dan harga lokal.
3. Jika harga belum ada, ajukan/set sesuai hak akses.
4. Input pengiriman mitra dari armada masuk.
5. Input pembelian TBS lokal dari petani.
6. Cetak struk petani bila perlu.
7. Jika hasil lokal dikirim ke pabrik, catat sebagai pengiriman mitra internal.
8. Cek riwayat hari ini dan koreksi hanya dengan alasan.
9. Serahkan transaksi pending ke Admin Keuangan.

Kebutuhan UX: dashboard harus menampilkan checklist harian "Harga siap", "Transaksi masuk", "Stok tersedia", "Kwitansi/pembayaran pending", dan "Butuh koreksi".

### 6.2 Activity Admin Keuangan

1. Buka halaman Keuangan Hari Ini.
2. Review kas keluar dari pembelian, panjar, pembayaran mitra, dan biaya.
3. Catat hutang/panjar/pembayaran balik pihak bila ada uang nyata.
4. Review settlement mitra internal ketika pembayaran pabrik sudah masuk.
5. Buat kwitansi mitra per periode.
6. Tandai kwitansi sudah dibayar setelah uang keluar.
7. Cetak/simpan PDF dan kirim WhatsApp.
8. Review Buku Kas dan transaksi reversal.
9. Tutup hari setelah selisih kas, stok, DO, dan hutang jelas.

Kebutuhan UX: perlu "Inbox Keuangan" berisi settlement mitra internal pending, kwitansi belum dibayar, panjar aktif, biaya hari ini, dan mutasi manual tanpa bukti.

### 6.3 Activity Owner

1. Buka Dashboard Owner.
2. Cek laba bersih kas, estimasi transaksi, settlement pending, hutang/panjar aktif, dan kwitansi perlu review.
3. Review pendapatan owner bruto dari flow mitra.
4. Setujui override harga/fee/tarif/limit jika diperlukan.
5. Cek audit log untuk transaksi batal, koreksi, dan pembayaran besar.
6. Export laporan owner.

Kebutuhan UX: owner tidak perlu banyak form input; owner perlu exception dashboard, approval queue, dan laporan yang sudah dipisah antara kas aktual dan estimasi.

### 6.4 Activity Super Admin

1. Kelola user dan role.
2. Verifikasi matrix akses route, tabel, dan RPC.
3. Review audit log.
4. Menjalankan release gate: staging test, backup, migration non-destruktif, rollback plan.
5. Monitor storage policy, RLS, dan akses laporan profit.

Kebutuhan UX: perlu menu Admin Sistem terpisah dari Owner agar tidak mencampur operasional dan konfigurasi keamanan.

## 7. Alur Bisnis Target

### 7.1 Alur A - Petani Lokal ke Mitra Internal

1. Master petani, pabrik, sopir/armada, dan harga lokal aktif.
2. Admin Operasional input pembelian TBS lokal.
3. Sistem menghitung potongan, berat bersih, total harga, dan potong hutang bila ada.
4. Sistem membuat transaksi pembelian, stok masuk, kas keluar, dan hutang ledger bila relevan.
5. Admin mencetak struk.
6. Saat hasil lokal dikirim ke pabrik, operator memilih mitra internal terkait, sopir/plat, dan tonase.
7. Sistem menyimpan pengiriman sebagai transaksi mitra internal agar laporan mitra, harga pabrik, fee, dan kwitansi tetap satu jalur.
8. Saat pabrik membayar, Keuangan merekonsiliasi kas masuk terhadap transaksi mitra internal.
9. Laporan harian menunjukkan stok sisa, pengiriman mitra internal, kas masuk/keluar, dan margin estimasi.

Gap utama: rekonsiliasi stok lokal ke transaksi mitra internal, bukti pembayaran pabrik, dan closing harian.

### 7.2 Alur B - Mitra Mengirim Sendiri ke Pabrik

1. Master mitra, sopir/armada, harga pabrik, dan fee owner aktif.
2. Admin Operasional input tanggal, mitra, sopir/armada, sopir aktual, dan tonase.
3. Sistem menyimpan snapshot harga pabrik, fee owner, harga bersih ke mitra, total fee owner, dan total nilai bersih.
4. Owner/Admin mengecek riwayat, edit/batal hanya dengan alasan.
5. Keuangan membuat kwitansi mitra per periode.
6. Sistem mengambil transaksi aktif, panjar belum lunas, dan status pembayaran sebelumnya.
7. Keuangan menandai dibayar setelah uang keluar.
8. Sistem membuat snapshot pembayaran, kas keluar, dan potongan panjar.
9. Kwitansi dicetak/dikirim WhatsApp.

Gap utama: settlement per DO berbasis pembayaran pabrik, selisih tonase mitra vs pabrik, biaya bantuan mitra, tarif armada perusahaan, dan status revisi kwitansi yang lebih lengkap.

### 7.3 Alur C - Armada Internal sebagai Mitra

Target final:

1. Owner membuat mitra tipe internal untuk mewakili armada/unit internal.
2. Sopir dan plat default dikelola di menu Armada.
3. Pengiriman hasil pembelian lokal ke pabrik dicatat lewat Pengiriman Mitra dengan memilih mitra internal.
4. Sistem menyimpan harga pabrik, fee, tonase, sopir, dan plat dalam satu alur `transaksi_mitra`.
5. Jika nanti ada tarif/biaya armada internal, aturan itu masuk settlement Fase 3 tanpa membuka menu armada perusahaan terpisah.

Status: belum lengkap dan sebaiknya masuk Fase 3.

### 7.4 Mekanisme Pencatatan Laba/Rugi

Prinsip utama: laba/rugi tidak diinput manual. Laba dihitung dari uang aktual dan snapshot transaksi agar laporan tidak bisa dimanipulasi dari satu form angka.

Rumus operasional yang dipakai:

```text
Laba Kas = Uang diterima dari pabrik - Uang dibayar ke mitra/petani - Biaya operasional
```

Sumber datanya:

- Pendapatan aktual: mutasi `kas_ledger` dengan sumber `pembayaran_pabrik`.
- Pengeluaran aktual: mutasi `kas_ledger` untuk `pembayaran_mitra`, `pembelian_tbs`, panjar/hutang yang benar-benar keluar kas, dan `biaya_operasional`.
- Laba bruto owner dari pengiriman mitra: snapshot `transaksi_mitra.total_fee_owner`. Ini berguna sebagai estimasi hak owner, tetapi belum menjadi laba final sebelum pembayaran pabrik dan biaya aktual masuk ledger.
- Laba final owner: angka kas yang sudah direkonsiliasi, bukan hanya total fee di transaksi.

Konsekuensi saat ini: jika pembayaran pabrik belum dicatat ke `kas_ledger`, halaman Laba/Rugi akan terlihat belum tracking karena pendapatan kas memang belum ada. Perbaikannya bukan membuat tabel laba manual, tetapi menambahkan flow **Pembayaran Pabrik** yang membuat kas masuk dan mengalokasikan uang itu ke transaksi mitra/internal.

Alur target pencatatan laba:

1. Admin Operasional input pengiriman mitra.
2. Sistem menyimpan snapshot harga pabrik, fee owner, dan nilai bersih mitra di `transaksi_mitra`.
3. Admin Keuangan menerima pembayaran pabrik.
4. Admin Keuangan mencatat Pembayaran Pabrik.
5. Sistem membuat mutasi kas masuk `pembayaran_pabrik`.
6. Sistem mengalokasikan pembayaran ke transaksi mitra terkait.
7. Admin Keuangan membayar mitra melalui Kwitansi Mitra.
8. Sistem membuat kas keluar `pembayaran_mitra` dan snapshot item kwitansi.
9. Laba/Rugi menghitung laba kas dari ledger dan menandai transaksi yang belum lengkap rekonsiliasinya.

### 7.5 Tindak Lanjut Mitra yang Sudah Dibayar dan Diberi Kwitansi

Laporan Mitra adalah rekap operasional pengiriman, sedangkan Kwitansi Mitra adalah bukti pembayaran. Keduanya harus terhubung lewat status pembayaran.

Status tindak lanjut:

| Status di Laporan Mitra | Arti Bisnis | Tindak Lanjut |
| --- | --- | --- |
| Belum Dibayar | Transaksi aktif belum masuk snapshot kwitansi bayar. | Masuk antrian pembayaran di Kwitansi Mitra. |
| Sudah Dibayar | Transaksi sudah masuk `pembayaran_mitra_kwitansi_item` dan header kwitansi berstatus dibayar. | Arsipkan sebagai sudah lunas, cetak/kirim ulang dari Kwitansi Mitra bila diperlukan. |
| Perlu Review | Ada transaksi baru, batal, atau berubah setelah kwitansi dibayar. | Owner/Keuangan wajib cek ulang sebelum mencetak ulang atau membuat revisi kwitansi. |

Saat user klik **Tandai Dibayar** di Kwitansi Mitra:

1. Sistem menyimpan header pembayaran di `pembayaran_mitra_kwitansi`.
2. Sistem menyimpan snapshot transaksi di `pembayaran_mitra_kwitansi_item`.
3. Sistem memotong panjar mitra yang belum lunas.
4. Sistem mencatat kas keluar pembayaran mitra.
5. Laporan Mitra membaca item kwitansi itu untuk menampilkan status Sudah Dibayar/Perlu Review.

Catatan data historis: kwitansi yang sudah ditandai dibayar sebelum integrasi `kas_ledger` bisa berstatus dibayar tetapi belum muncul sebagai kas keluar. Jangan tandai ulang pembayaran. Jalankan migration backfill agar sistem membuat mutasi `kas_ledger` dengan sumber `pembayaran_mitra` dan menghubungkannya kembali ke header kwitansi.

Dengan alur ini, transaksi yang sudah dibayar tidak hilang dari laporan. Ia tetap terlihat untuk audit, tetapi tidak lagi menjadi antrian pembayaran berikutnya.

## 8. Gap Analysis

### Proses Bisnis

- Menu dan dashboard masih membawa istilah fase implementasi seperti MVP/Tahap 2. Untuk user bisnis, ini harus diganti menjadi istilah workflow.
- Belum ada halaman "Tutup Hari" yang menyatukan kas, stok, DO, hutang, biaya, dan exception.
- Approval limit kasbon/panjar belum menjadi workflow terstruktur.
- Settlement mitra belum menjadi sumber final hak mitra.
- Pembayaran pabrik masih dasar per DO, belum mendukung satu pembayaran untuk banyak DO.
- Bukti transaksi dan nomor referensi belum menjadi standar wajib.

### Data dan Audit

- Pola ledger/reversal sudah bagus, tetapi perlu konsistensi untuk semua flow yang menyentuh uang/stok/settlement.
- RLS awal pernah memakai "Authenticated full access"; migration terbaru mulai memperketat, tetapi perlu verifikasi langsung ke `pg_policies` di staging/production.
- RPC `SECURITY DEFINER` sudah punya validasi role di beberapa fungsi penting; tetap perlu audit semua fungsi agar tidak ada bypass tanpa role check.
- Audit log sudah ada, tetapi belum menjadi halaman review bisnis.
- Perubahan harga/fee/tarif harus selalu punya alasan dan tanggal berlaku.

### UX/UI

- Hover scale/glow pada kartu cocok untuk kesan premium, tetapi kurang ideal untuk tool operasional harian karena elemen bergerak saat discan.
- Card radius 20px dan glass effect terlalu dominan untuk tabel/ledger padat; gunakan container yang lebih stabil untuk data.
- Beberapa tombol aksi masih berupa teks biasa atau karakter/icon emoji; gunakan lucide icon dan tooltip.
- Selector master data belum seragam searchable di semua halaman.
- Route/menu "Input Pengiriman" ambigu karena bisa berarti mitra atau lokal.
- Mobile flow perlu fokus pada input cepat, bukan tabel lebar.

## 9. Information Architecture Target

Rekomendasi menu baru:

1. **Dashboard**
   - Hari Ini
   - Pending & Review
   - Owner Summary, hanya Owner/Super Admin

2. **Operasi**
   - Pengiriman Mitra
   - Pembelian Petani Lokal
   - Riwayat & Koreksi

3. **Keuangan**
   - Buku Kas
   - Hutang & Panjar Semua Pihak
   - Biaya Operasional
   - Pembayaran Pabrik
   - Kwitansi & Pembayaran Mitra

4. **Master Data**
   - Petani
   - Mitra
   - Armada
   - Pabrik
   - Harga & Fee
   - Pengaturan Bisnis

5. **Laporan**
   - Closing Harian, pengembangan berikutnya
   - Stok Lokal
   - Petani
   - Mitra
   - Pabrik / DO
   - Laba Rugi Owner

6. **Admin Sistem**
   - User & Role
   - Audit Log
   - Branding Web
   - Backup / Release Checklist

## 10. UX Target per Halaman Kritis

### Dashboard

Ubah dari ringkasan campuran menjadi command center:

- Checklist harga: Harga Pabrik, Harga Petani, Fee berubah hari ini.
- Operasi hari ini: TBS mitra, TBS petani masuk, stok lokal, pengiriman mitra internal.
- Keuangan hari ini: kas masuk, kas keluar, pembayaran mitra, biaya.
- Pending: kwitansi belum dibayar, kwitansi perlu review, settlement mitra internal pending, hutang/panjar melewati limit, transaksi batal/koreksi.
- Quick action sesuai role.

### Input Pengiriman Mitra

Rename menjadi "Pengiriman Mitra".

Tambahkan step visual:

1. Tanggal dan mitra.
2. Sopir/armada dan sopir aktual.
3. Tonase.
4. Review snapshot harga/fee.
5. Simpan.

Form review snapshot harus jelas sebelum save: Harga Pabrik, Fee Owner, Harga Bersih Mitra, Total Fee, Total Hak Mitra.

### Pembelian TBS Lokal

Pertahankan kalkulasi real-time dan struk.

Tambahkan:

- Searchable combobox petani.
- Indikator stok setelah transaksi.
- Nomor struk lebih menonjol setelah save.
- Opsi lampiran/tiket timbang di Fase 4.
- Guard jika periode hari sudah ditutup.

### Pengiriman Lokal sebagai Mitra Internal

Alur utama tidak perlu menjadi menu terpisah. Hasil pembelian lokal yang dikirim ke pabrik sebaiknya dicatat melalui mitra internal, misalnya BL/SL, sehingga user memakai satu pola input pengiriman.

Tambahkan:

- Penanda tipe mitra "Internal Owner" yang jelas di menu Mitra.
- Default sopir/plat untuk mitra internal.
- Rekonsiliasi stok lokal ke transaksi mitra internal.
- Pemisahan "nilai tagihan pabrik" dan "uang diterima aktual".
- Pembayaran pabrik multi-transaksi di fase rekonsiliasi.

Route `/transaksi/kirim` boleh dipertahankan sementara sebagai route legacy/opsional sampai migrasi data dan SOP selesai.

### Kwitansi Mitra

Pertahankan preview print dan status batch.

Tambahkan:

- Nomor kwitansi unik.
- Revisi kwitansi jika transaksi berubah setelah dibayar/dikirim.
- Log WhatsApp/manual sent.
- Bukti transfer/lampiran.
- Preview "data yang akan dikunci" sebelum Tandai Dibayar.

### Buku Kas

Tambahkan:

- Saldo awal, saldo akhir, dan tutup kas.
- Nomor bukti/ref wajib untuk mutasi manual.
- Filter sumber dan export.
- Indikator mutasi tanpa lampiran.
- Link balik ke sumber transaksi.

### Hutang & Panjar Semua Pihak

Definisi penggunaan:

- **Hutang** adalah kewajiban yang belum lunas, bisa RAM yang wajib membayar pihak lain atau pihak lain yang wajib mengembalikan uang ke RAM.
- **Panjar/kasbon** adalah uang muka yang diberikan sebelum settlement final dan biasanya dipotong dari pembayaran berikutnya.
- Panjar mitra bukan pintu input terpisah. Secara UI tetap masuk dari Hutang & Panjar Semua Pihak; secara data sistem juga membuat `panjar_mitra` agar bisa dipotong di Kwitansi Mitra.

Skenario permintaan uang ke owner:

| Pihak meminta uang | Dicatat sebagai | Pihak di sistem | Jenis debit yang disarankan | Cara pelunasan/pemantauan |
| --- | --- | --- | --- | --- |
| Petani minta uang sebelum jual TBS | Hutang/kasbon petani | Petani | Kasbon atau Peminjaman | Dipotong saat pembelian TBS berikutnya atau dibayar tunai. Pantau di Hutang & Panjar Semua Pihak, Dashboard, Buku Kas, dan Laporan Petani. |
| Karyawan minta uang pribadi/talangan | Kasbon karyawan | Karyawan | Kasbon atau Gaji / Talangan | Dibayar tunai ke kas atau dipotong gaji secara manual. Pantau di Hutang & Panjar Semua Pihak dan Buku Kas. |
| Sopir minta uang jalan | Uang jalan sopir | Sopir | Uang Jalan | Dipertanggungjawabkan atau dilunasi manual. Pantau di Hutang & Panjar Semua Pihak dan Buku Kas. |
| Mitra minta uang sebelum kwitansi | Panjar mitra | Mitra | Panjar | Dipotong otomatis saat pembayaran kwitansi mitra. Pantau di Hutang & Panjar, Kwitansi Mitra, Buku Kas, dan arsip Panjar Mitra bila dibutuhkan. |

Alur input di aplikasi:

1. Buka Keuangan -> Hutang & Panjar Semua Pihak.
2. Pilih tipe pihak: Petani, Mitra, Sopir, Karyawan, atau Lainnya.
3. Pilih nama master data. Untuk Karyawan/Lainnya, isi nama manual.
4. Klik Catat Hutang & Panjar.
5. Gunakan aksi "Tambah hutang / uang keluar".
6. Pilih jenis: Kasbon, Panjar, Peminjaman, Uang Jalan, Gaji / Talangan, atau lainnya.
7. Isi nominal dan keterangan singkat.
8. Simpan. Sistem membuat mutasi debit di `hutang_ledger` dan kas keluar di `kas_ledger`.
9. Saat uang dikembalikan/dipotong, pilih pihak yang sama lalu gunakan aksi "Pembayaran / uang masuk" atau alur potong otomatis yang relevan.

Catatan istilah: `hutang_ledger` adalah buku mutasi hutang/panjar. Angka yang ditampilkan ke user sebaiknya disebut **Sisa Hutang/Panjar**, yaitu total debit dikurangi total kredit yang belum selesai.

Standar monitoring:

- Dashboard menampilkan total "Sisa Hutang/Panjar" dan jumlah pihak yang masih perlu dipantau.
- Halaman Hutang & Panjar menampilkan daftar sisa hutang/panjar per pihak dan riwayat debit/kreditnya.
- Buku Kas menampilkan kas keluar saat uang diberikan dan kas masuk saat pelunasan.
- Laporan Petani menampilkan hutang petani; untuk karyawan perlu laporan khusus fase berikutnya bila dibutuhkan.
- Transaksi yang salah tidak dihapus fisik; gunakan batal/reversal dengan alasan.

Tambahkan:

- Limit per pihak dengan status "normal", "mendekati limit", "melewati limit".
- Approval queue jika melewati limit.
- Riwayat potong otomatis dari pembelian/settlement/kwitansi.
- Bukti pencairan dan pembayaran balik.

## 11. Roadmap Perubahan

### P0 - Hardening dan Tata Kelola

- Verifikasi RLS dan RPC di staging/production.
- Buat matrix akses route, tabel, dan RPC.
- Pastikan semua `SECURITY DEFINER` punya validasi `auth.uid()` dan role.
- Hilangkan physical delete untuk semua transaksi finansial.
- Tambahkan halaman Audit Log minimal.
- Buat SOP backup, migration, dan rollback.

### P1 - UX Workflow Harian

- Rename dan regroup sidebar menjadi task-based.
- Buat Dashboard "Hari Ini" dan "Pending Review".
- Standarkan searchable combobox untuk master data besar.
- Standarkan form: input -> kalkulasi -> review -> simpan -> bukti.
- Kurangi hover scale/glow pada table/card operasional.
- Bangun ulang Laporan Harian lama menjadi Closing Harian dengan checklist, exception, dan status kunci periode.

### P2 - Keuangan dan Rekonsiliasi

- Pembayaran pabrik multi-transaksi.
- Bukti pembayaran dan nomor referensi.
- Saldo awal/akhir kas dan tutup kas harian.
- Approval limit hutang/panjar.
- Link semua ledger ke sumber transaksi.

### P3 - Settlement Mitra Final

- Settlement per DO.
- Selisih tonase mitra vs pabrik.
- Potongan armada perusahaan.
- Biaya bantuan mitra.
- Tarif armada history dan override approval.
- Kwitansi final berdasarkan settlement.

### P4 - Bukti, Otomasi, dan Monitoring

- Upload tiket timbang, DO, bukti transfer.
- WhatsApp send log dan revisi.
- Dashboard exception owner.
- Monitoring error, backup health, dan audit export.
- UI polish responsive untuk penggunaan HP di lapangan.

## 12. Acceptance Criteria untuk Alur Baru

- Admin Operasional dapat menyelesaikan input transaksi harian tanpa membuka laporan owner.
- Admin Keuangan dapat melihat semua uang masuk/keluar aktual dari satu Buku Kas.
- Owner dapat melihat laba kas utama dan estimasi transaksi dengan label jelas.
- Semua pembatalan dan koreksi meminta alasan dan masuk audit log.
- Semua transaksi uang memiliki ledger, sumber transaksi, tanggal, pembuat, dan status.
- Semua laporan dapat difilter periode dan diekspor sesuai role.
- Data profit tidak bocor ke admin biasa, baik dari UI maupun RLS/RPC.
- Kuitansi mitra yang sudah dibayar memakai snapshot, bukan hitung ulang bebas.
- Jika data transaksi berubah setelah kwitansi dibayar, sistem menandai perlu review.
- Closing harian dapat mengungkap selisih kas, stok, settlement pending, hutang aktif, dan transaksi koreksi.

## 12.1 Rencana Cleanup Database

Rencana teknis pembersihan tabel legacy, tabel kanonik, tabel baru yang direkomendasikan, dan opsi database baru yang bersih dipisahkan di dokumen [`docs/db-cleanup-migration-plan.md`](./db-cleanup-migration-plan.md). Hasil audit database aktual ada di [`docs/db-actual-audit-2026-07-14.md`](./db-actual-audit-2026-07-14.md).

Prinsip keputusan utamanya: jangan menghapus tabel produksi secara langsung. Tabel lama seperti `pengiriman`, `pengiriman_lokal_detail`, `kendaraan`, `mitra`, `armada_mitra`, dan `fee_mitra_history` harus melalui audit, freeze, archive, validasi laporan, lalu baru dipertimbangkan untuk drop.

## 12.2 Audit Isi Halaman

Audit duplikasi isi halaman, keputusan navigasi, dan rekomendasi tindak lanjut UX dipisahkan di dokumen [`docs/page-content-audit.md`](./page-content-audit.md). Keputusan pentingnya: `/laporan/harian` disembunyikan dari navigasi saat ini dan nanti dibangun ulang sebagai **Closing Harian**, bukan laporan rekap biasa.

## 13. Kesimpulan

Sawit CB sudah punya fondasi sistem bisnis yang kuat untuk Fase 2 minimum. Langkah terbaik berikutnya adalah mengubah orientasi aplikasi dari "kumpulan modul berdasarkan fase implementasi" menjadi "workflow harian bisnis RAM sawit". Fokusnya: role-safe, ledger-first, audit-ready, settlement-ready, dan bukti transaksi yang rapi.

Jika rencana ini diikuti, website akan bergerak dari aplikasi pencatatan operasional menjadi sistem business management internal yang lebih disiplin, mudah dipakai admin, dan lebih aman untuk keputusan owner.
