# ADDENDUM MVP TAHAP 1 (Selesai - Juli 2026)
Pengembangan Tahap 1 (MVP) berfokus pada **Pengiriman Mitra ke Pabrik** telah selesai. Menu operasional lain diberi label [Coming Soon].
Fitur utama yang telah live:
1. **Master Data Mitra & Sopir**: Relasi `sopir` ke `master_mitra`, termasuk pengaturan `fee_per_kg` per mitra.
2. **Pengiriman Mitra**: Pencatatan armada masuk dengan perhitungan Skenario B (Harga Beli Bersih = Harga Pabrik - Fee DO).
3. **Panjar Mitra**: Modul kasbon mitra dengan tombol input cepat (Quick Add).
4. **Kwitansi Mitra**: Cetak invoice otomatis yang memotong panjar dari total bersih penerimaan.
5. **Laporan Mitra**: Ledger rekapan global seluruh transaksi pengiriman mitra.
6. **Dashboard Multi-Harga**: Pemisahan input Harga Pabrik (TWB) untuk MVP dan Harga Beli Lokal untuk Tahap 2.

> [!CAUTION]
> **ATURAN KERJA TAHAP 2 (SANGAT PENTING)**
> Karena sistem MVP ini **SUDAH LIVE** dan digunakan oleh Owner untuk mencatat data operasional asli, pengembangan Tahap 2 **DILARANG KERAS** menyentuh, merusak, atau menghapus struktur database MVP saat ini (`master_mitra`, `sopir`, `transaksi_mitra`, `panjar_mitra`, `harga_tbs`, dsb). 
> 
> Seluruh pengembangan fitur baru (Tahap 2) wajib:
> 1. Menggunakan database *Development* yang terpisah.
> 2. Menggunakan metode *Non-Destructive Migration* (hanya boleh menambah kolom/tabel baru).
> 3. Melakukan *Backup* database *Production* sebelum rilis fitur baru.

# PRD Final - Sawit CB

Tanggal konfirmasi klien: 11 Juli 2026, 06:12:40

## 1. Ringkasan Produk

Sawit CB adalah aplikasi operasional dan keuangan untuk bisnis RAM kelapa sawit. Sistem mencatat pembelian TBS dari petani lokal, stok sementara, pengiriman TBS ke pabrik, pengiriman TBS dari mitra, hutang/kasbon, biaya operasional, pembayaran pabrik, settlement mitra, dan laporan laba-rugi owner.

Pada versi final ini, sistem wajib memisahkan dua sumber TBS:

1. **Petani lokal**: pemasok individu yang menjual TBS langsung ke perusahaan. TBS ditimbang di timbangan perusahaan, dicatat sebagai stok sementara, dibayar oleh perusahaan, lalu dikirim ke pabrik.
2. **Mitra**: pengumpul/RAM kecil yang mengirim TBS ke pabrik atas nama perusahaan. Pabrik membayar ke perusahaan, lalu perusahaan membayar mitra berdasarkan berat final pabrik setelah dikurangi fee dan potongan yang disepakati.

## 2. Keputusan Final dari Klien

Keputusan berikut menjadi dasar final pengembangan sistem:

| Area | Keputusan |
| --- | --- |
| Fee perusahaan dari mitra | Selalu ada fee untuk perusahaan |
| Cara hitung fee mitra | Potongan nominal per kg |
| Dasar pembayaran ke mitra | Berat final yang diterima pabrik |
| Selisih berat mitra vs pabrik | Dibagi antara mitra dan perusahaan dengan persentase yang bisa diatur owner/super admin |
| Pembayaran pabrik | Per surat jalan / DO |
| Pembayaran ke mitra | Mitra langsung dibayar penuh setelah pabrik membayar |
| Panjar/uang muka mitra | Ada, tetapi hanya untuk mitra tertentu |
| Armada perusahaan dipakai mitra | Biaya selalu dipotong dari pembayaran mitra |
| Cara hitung biaya armada | Berdasarkan jarak, kemudian dihitung dengan tonase muatan |
| Hutang/kasbon mitra | Mitra bisa punya hutang/kasbon seperti petani |
| Data kendaraan mitra | Cukup nama sopir dan plat kendaraan jika ada |
| Stok TBS lokal | Perlu dicatat sebagai stok sementara |
| Pengiriman TBS lokal | Perlu detail transaksi petani dan total harian |
| Potongan pabrik | Sortasi/grading dan biaya timbang |
| Laba-rugi | Perlu dua versi: basis kas dan basis transaksi |
| Bukti pembayaran mitra | Perlu file PDF atau gambar untuk WhatsApp |
| Akses laporan keuntungan | Owner dan super admin saja |

Catatan: jawaban untuk laporan harian yang paling sering dibutuhkan tidak diberikan secara spesifik. Untuk v1 final, sistem memakai prioritas laporan harian default yang dijelaskan di bagian Laporan Harian dan dapat diubah oleh owner/super admin melalui Pengaturan Bisnis.

## 3. Dampak ke Produk

### 3.1 Dampak ke Alur Mitra

Alur mitra menjadi lebih pasti dan lebih ketat:

- Setiap pengiriman mitra wajib memiliki nomor DO atau tiket timbang.
- Pembayaran pabrik dicatat per DO.
- Hak mitra dihitung dari `tonase_dasar_settlement` yang berasal dari data pabrik, bukan berat timbang mitra.
- Fee perusahaan dihitung sebagai nominal per kg.
- Jika ada selisih berat antara timbang mitra dan timbang pabrik, sistem harus mencatat nilai selisih dan menghitung pembagian tanggungan berdasarkan persentase yang diatur owner/super admin.
- Jika `tonase_dasar_settlement` lebih besar dari timbang mitra, sistem tetap memakai data pabrik sebagai dasar pembayaran tetapi wajib menandai kondisi tersebut sebagai anomali rekonsiliasi.
- Setelah pabrik membayar per DO, settlement mitra dapat langsung dihitung dan dibayar penuh.
- Mitra tertentu boleh memiliki panjar/kasbon, sehingga perlu ledger hutang mitra.

### 3.2 Dampak ke Armada

Jika mitra memakai armada perusahaan:

- Biaya armada wajib menjadi potongan settlement mitra.
- Formula biaya armada harus mendukung komponen jarak, tonase, tarif default per armada, dan override manual jika diperlukan.
- Sistem perlu menyimpan jarak, tonase muatan, tarif, total biaya armada yang dipotong, dan sumber tarif yang dipakai.
- Biaya ini tidak boleh tercatat ganda sebagai pengurang laba jika sudah dipotong dari hak mitra.

### 3.3 Dampak ke Stok TBS Lokal

Karena TBS petani lokal perlu dicatat sebagai stok sementara:

- Pembelian dari petani lokal menambah stok TBS lokal.
- Pengiriman lokal ke pabrik mengurangi stok TBS lokal.
- Pengiriman lokal perlu bisa dikaitkan ke detail transaksi petani, serta tetap menyimpan total tonase harian.
- Sistem perlu laporan rekonsiliasi: TBS masuk dari petani, TBS keluar ke pabrik, dan sisa stok.

### 3.4 Dampak ke Laporan Keuangan

Laba-rugi perlu tersedia dalam dua cara:

1. **Basis kas**: hanya menghitung uang yang benar-benar sudah masuk dan keluar.
2. **Basis transaksi/akrual sederhana**: menghitung transaksi yang sudah terjadi walaupun uangnya belum dibayar.

Dashboard owner harus menampilkan **Laba Bersih Kas** sebagai angka utama karena paling mendekati uang nyata yang tersedia. **Laba Estimasi Transaksi** ditampilkan sebagai angka pembanding untuk melihat potensi margin dari transaksi yang belum selesai dibayar.

Laporan keuntungan hanya boleh dilihat oleh owner dan super admin.

### 3.5 Dampak ke Bukti Pembayaran

Settlement dan pembayaran mitra harus bisa dibuat menjadi bukti digital:

- PDF atau gambar.
- Format cocok untuk dikirim via WhatsApp.
- Berisi detail DO, tonase pabrik, harga, fee, potongan armada, potongan hutang/kasbon, total hak mitra, dan status pembayaran.

## 4. Role Pengguna

### Owner

- Melihat seluruh dashboard dan laporan.
- Melihat laporan keuntungan/laba-rugi.
- Mengatur harga, fee mitra, formula settlement, biaya, dan konfigurasi bisnis.
- Mengonfirmasi pembayaran pabrik.
- Mengonfirmasi pembayaran ke mitra.
- Melihat audit perubahan transaksi penting.
- Tidak dapat mengelola akun user dan role akses.

### Super Admin

- Memiliki akses penuh ke seluruh sistem.
- Boleh melihat laporan keuntungan/laba-rugi.
- Mengelola akun user dan role akses.
- Mengelola master data dan konfigurasi sistem.
- Perbedaan utama dengan owner: super admin dapat mengelola akun user, sedangkan owner tidak.
- Disarankan ada minimal dua akun super admin aktif agar perusahaan tetap bisa menonaktifkan akun karyawan jika salah satu super admin tidak tersedia.

### Admin Operasional

- Input transaksi TBS petani lokal.
- Input stok masuk dari petani lokal.
- Input pengiriman lokal ke pabrik.
- Input pengiriman dari mitra.
- Input data armada, sopir, pabrik, petani, dan mitra.
- Tidak boleh melihat laporan keuntungan/laba-rugi.

### Admin Keuangan

- Mencatat pembayaran pabrik.
- Mencatat pembayaran ke petani.
- Mencatat pembayaran dan settlement mitra.
- Mencatat hutang/kasbon petani dan mitra.
- Melihat laporan hutang, settlement, kas masuk, dan kas keluar.
- Tidak boleh melihat laporan keuntungan/laba-rugi kecuali diberi role super admin.

## 5. Entitas Utama

### Petani

Petani adalah pemasok individu yang menjual TBS langsung ke perusahaan.

Data minimal:

- Nama
- Nomor HP
- Alamat
- Nomor KTP, opsional
- Batas hutang/kasbon
- Status aktif/nonaktif

### Mitra

Mitra adalah pihak pengumpul/RAM kecil yang mengirim TBS ke pabrik atas nama perusahaan.

Data minimal:

- Nama mitra/usaha
- Penanggung jawab
- Nomor HP
- Alamat/lokasi timbang
- Nomor rekening, opsional
- Fee default per kg
- Status boleh panjar/kasbon
- Batas panjar/kasbon, opsional
- Persentase tanggungan selisih tonase, opsional jika berbeda dari default sistem
- Status aktif/nonaktif

### Armada Perusahaan

Armada milik/sewa perusahaan yang digunakan untuk pengiriman TBS lokal atau membantu pengiriman mitra.

Data minimal:

- Plat nomor
- Jenis kendaraan
- Kapasitas
- Kepemilikan
- Tarif default per km per ton
- Status tarif default aktif/nonaktif
- Status aktif/nonaktif

### Armada Mitra

Armada yang digunakan oleh mitra. Sistem cukup mencatat data sederhana jika tersedia.

Data minimal:

- Plat kendaraan, opsional
- Nama sopir, opsional
- Mitra pemilik

### Pabrik

Tujuan pengiriman TBS yang melakukan pembayaran ke perusahaan.

Data minimal:

- Nama pabrik
- Alamat
- Kontak
- Harga pabrik per kg jika tersedia
- Pola pembayaran per DO
- Informasi rekening atau referensi pembayaran, opsional

## 6. Alur Bisnis Final

### 6.1 Alur A - Petani Lokal ke Perusahaan

1. Admin mengatur harga beli TBS lokal.
2. Petani lokal membawa TBS ke lokasi perusahaan.
3. TBS ditimbang di timbangan perusahaan.
4. Sistem mencatat berat kotor, potongan, berat bersih, harga beli, total beli, potong hutang jika ada, dan bayar tunai.
5. Transaksi pembelian menambah stok sementara TBS lokal.
6. Perusahaan membayar petani.
7. Saat TBS dikirim ke pabrik, admin membuat pengiriman lokal.
8. Pengiriman lokal wajib dapat dikaitkan ke detail transaksi petani atau kelompok transaksi harian.
9. Pengiriman lokal mengurangi stok sementara.
10. Pabrik membayar ke perusahaan per DO.
11. Pendapatan masuk ke laporan laba-rugi perusahaan.

### 6.2 Alur B - Mitra Mengirim Sendiri ke Pabrik

1. Mitra membeli atau mengumpulkan TBS dari sumbernya sendiri.
2. Mitra menimbang TBS di tempat mitra.
3. Mitra mengirim ke pabrik atas nama perusahaan.
4. Admin mencatat pengiriman mitra:
   - Mitra
   - Tanggal kirim
   - Pabrik tujuan
   - Nomor DO/tiket timbang
   - Tonase timbang mitra
   - Tonase final pabrik
   - Nama sopir mitra, jika ada
   - Plat kendaraan mitra, jika ada
5. Pabrik membayar ke perusahaan per DO.
6. Sistem menghitung hak mitra memakai `tonase_dasar_settlement` dari data pabrik.
7. Fee perusahaan dipotong nominal per kg.
8. Potongan pabrik yang dicatat minimal sortasi/grading dan biaya timbang.
9. Selisih tonase mitra vs pabrik dihitung dan dibagi berdasarkan persentase tanggungan yang berlaku.
10. Setelah pabrik membayar, mitra dibayar penuh sesuai settlement.
11. Settlement menjadi lunas setelah pembayaran mitra dicatat.

### 6.3 Alur C - Mitra Memakai Armada Perusahaan

1. Mitra meminta bantuan armada perusahaan.
2. Admin membuat pengiriman mitra dengan pilihan armada perusahaan.
3. Sistem mengambil tarif default armada, lalu admin mencatat armada, sopir, jarak, tonase muatan, tarif yang dipakai, dan total biaya armada.
4. Biaya armada wajib dipotong dari hak mitra.
5. Saat settlement, biaya armada tampil sebagai potongan.
6. Laporan membedakan:
   - Biaya operasional perusahaan murni
   - Biaya bantuan mitra
   - Potongan armada dari settlement mitra
   - Margin bersih dari pengiriman mitra

## 7. Rumus Settlement Mitra

Catatan satuan:

- Semua berat TBS untuk pembelian, pengiriman, timbang mitra, timbang pabrik, stok, dan settlement disimpan dalam **kg**.
- Tampilan UI boleh menampilkan ton untuk kemudahan baca, tetapi penyimpanan dan perhitungan harga per kg wajib memakai kg.
- Perhitungan biaya armada memakai ton, sehingga `tonase_muatan_ton = tonase_muatan_kg / 1000`.
- Dalam formula settlement, `tonase_timbang_mitra` adalah nilai `tonase_timbang_sumber` untuk pengiriman mitra.
- Dalam formula settlement, `tonase_final_pabrik` adalah nilai `tonase_pabrik` pada data model.

### 7.1 Input Settlement

- Mitra
- Nomor DO
- Pabrik
- Tanggal kirim
- Tonase timbang mitra
- Tonase final pabrik
- Tonase dasar settlement
- Selisih tonase
- Persentase selisih ditanggung perusahaan
- Persentase selisih ditanggung mitra
- Koreksi nilai selisih
- Harga pabrik per kg
- Total pembayaran pabrik
- Potongan pabrik: sortasi/grading, tipe sortasi, nilai sortasi, biaya timbang
- Fee perusahaan per kg
- Total fee perusahaan
- Potongan armada perusahaan, jika ada
- Potongan hutang/kasbon mitra, jika ada
- Potongan lain, jika ada
- Total hak mitra
- Jumlah dibayar ke mitra
- Status settlement

### 7.2 Formula Dasar

```text
Tonase dasar settlement =
  jika potongan_sortasi_type = kg:
    tonase_final_pabrik - potongan_sortasi_value
  jika potongan_sortasi_type = none, percent, atau nominal:
    tonase_final_pabrik

Potongan sortasi rupiah =
  jika potongan_sortasi_type = none:
    0
  jika potongan_sortasi_type = kg:
    0
  jika potongan_sortasi_type = percent:
    (tonase_dasar_settlement x harga_pabrik_per_kg) x (potongan_sortasi_value / 100)
  jika potongan_sortasi_type = nominal:
    potongan_sortasi_value

Total bruto pabrik = tonase_dasar_settlement x harga_pabrik_per_kg

Total potongan pabrik =
  potongan_sortasi_rupiah
  + biaya_timbang
  + potongan_pabrik_lain

Total pembayaran pabrik = total_bruto_pabrik - total_potongan_pabrik

Fee perusahaan = tonase_dasar_settlement x fee_per_kg

Selisih tonase = tonase_timbang_mitra - tonase_dasar_settlement

Nilai selisih tonase = abs(selisih_tonase) x harga_pabrik_per_kg

Jika tonase_timbang_mitra > tonase_dasar_settlement:
  koreksi_selisih_dibayar_perusahaan =
    nilai_selisih_tonase x (persentase_selisih_ditanggung_perusahaan / 100)

Jika tonase_timbang_mitra <= tonase_dasar_settlement:
  koreksi_selisih_dibayar_perusahaan = 0

Biaya armada dasar =
  jarak_km x tonase_muatan_ton x tarif_armada_per_km_per_ton

Biaya armada mitra memakai armada perusahaan =
  max(biaya_armada_dasar, minimum_charge)

Total potongan mitra =
  fee_perusahaan
  + potongan_armada_perusahaan
  + potongan_hutang_kasbon_mitra
  + potongan_lain

Hak mitra final = total_pembayaran_pabrik - total_potongan_mitra
  + koreksi_selisih_dibayar_perusahaan

Margin perusahaan dari mitra =
  fee_perusahaan
  + potongan_armada_perusahaan
  - koreksi_selisih_dibayar_perusahaan
  - biaya_aktual_armada_perusahaan
```

Validasi angka:

- `minimum_charge` default bernilai 0 jika tidak diisi.
- `tonase_dasar_settlement` tidak boleh kurang dari 0.
- `total_pembayaran_pabrik` tidak boleh kurang dari 0.
- `hak_mitra_final` tidak boleh kurang dari 0, kecuali owner/super admin menyetujui sebagai kasus koreksi khusus.
- Semua nilai persentase disimpan dalam angka 0 sampai 100.
- Semua hasil rupiah dibulatkan ke rupiah terdekat tanpa desimal.

### 7.3 Selisih Berat Mitra vs Pabrik

Sistem wajib mencatat:

- Tonase timbang mitra.
- Tonase final pabrik.
- Selisih tonase.
- Nilai rupiah selisih.
- Persentase tanggungan perusahaan.
- Persentase tanggungan mitra.
- Koreksi nilai selisih yang masuk ke settlement.

Untuk v1 final, pembayaran utama memakai `tonase_dasar_settlement`. Jika tonase timbang mitra lebih besar dari `tonase_dasar_settlement`, selisih susut dibagi berdasarkan persentase tanggungan. Default awal disarankan 50% ditanggung perusahaan dan 50% ditanggung mitra, tetapi owner/super admin dapat mengubah default global atau mengatur khusus per mitra.

Jika `tonase_dasar_settlement` lebih besar dari tonase timbang mitra, sistem tetap memakai `tonase_dasar_settlement` sebagai dasar pembayaran. Selisih lebih dicatat sebagai informasi rekonsiliasi, tanpa koreksi otomatis kecuali owner/super admin mengisi koreksi manual.

Kondisi `tonase_dasar_settlement > tonase_timbang_mitra` wajib diberi tanda anomali jika selisihnya melewati toleransi yang diatur owner/super admin. Default toleransi awal adalah 0 kg, artinya setiap selisih lebih tetap ditandai untuk ditinjau. Jika pola anomali berulang pada mitra yang sama, laporan mitra harus menampilkan peringatan rekonsiliasi.

## 8. Modul Produk

### 8.1 Dashboard

Dashboard menampilkan ringkasan operasional sendiri dan mitra secara terpisah.

Kartu utama:

- TBS petani lokal masuk hari ini
- Stok sementara TBS lokal
- TBS lokal keluar ke pabrik hari ini
- TBS mitra masuk pabrik hari ini
- Total tonase ke pabrik hari ini
- Pembayaran pabrik menunggu diterima
- Settlement mitra menunggu dibayar
- Hutang/kasbon petani aktif
- Hutang/kasbon mitra aktif
- Biaya operasional hari ini
- Laba Bersih Kas owner, hanya untuk owner/super admin
- Laba Estimasi Transaksi owner, hanya untuk owner/super admin

Filter:

- Hari ini
- Mingguan
- Bulanan
- Sumber TBS: petani lokal, mitra, semua
- Pabrik
- Mitra

### 8.2 Master Petani

Fungsi:

- Tambah/edit/nonaktifkan petani.
- Set batas hutang/kasbon.
- Melihat riwayat transaksi petani.
- Melihat saldo hutang petani.

Acceptance criteria:

- Petani tidak tercampur dengan mitra.
- Petani hanya muncul di form transaksi pembelian lokal.
- Hutang petani dihitung dari ledger tunggal.

### 8.3 Master Mitra

Fungsi:

- Tambah/edit/nonaktifkan mitra.
- Set fee default per kg.
- Set riwayat fee per kg berdasarkan tanggal/jam berlaku.
- Tandai apakah mitra boleh panjar/kasbon.
- Set batas panjar/kasbon jika diperlukan.
- Melihat riwayat pengiriman, settlement, dan hutang/kasbon.

Acceptance criteria:

- Mitra tidak muncul di form transaksi petani lokal.
- Mitra muncul di form pengiriman mitra.
- Setiap mitra memiliki ringkasan tonase, nilai pabrik, fee, hak mitra, sudah dibayar, sisa bayar, dan saldo hutang/kasbon.

### 8.4 Harga TBS Lokal

Fungsi:

- Set harga beli TBS lokal berdasarkan tanggal/jam berlaku.
- Riwayat harga.

Acceptance criteria:

- Harga beli petani lokal tidak selalu sama dengan harga pabrik.
- Transaksi pembelian lokal tidak bisa disimpan jika belum ada harga yang berlaku pada waktu transaksi.
- Jika harga berubah lebih dari satu kali dalam sehari, transaksi mengambil harga terbaru yang `berlaku_mulai`-nya paling dekat tetapi tidak melebihi waktu transaksi.
- Override harga pada form transaksi hanya boleh dilakukan owner/super admin atau admin yang diberi otorisasi, dan wajib masuk audit log.

### 8.5 Input TBS Petani Lokal

Fungsi:

- Pilih petani.
- Input berat kotor dan potongan.
- Ambil harga beli harian.
- Hitung berat bersih dan total harga.
- Potong hutang petani jika ada.
- Simpan transaksi.
- Tambahkan berat bersih ke stok sementara.
- Cetak struk.

Acceptance criteria:

- Nomor struk harus unik walaupun ada input bersamaan.
- Potongan hutang harus tercatat satu kali di ledger hutang.
- Transaksi yang sudah masuk pengiriman tidak boleh diubah sembarangan tanpa audit.

### 8.6 Stok Sementara TBS Lokal

Fungsi:

- Menampilkan stok awal, TBS masuk dari petani, TBS keluar ke pabrik, koreksi, dan sisa stok.
- Menghubungkan pengiriman lokal dengan transaksi petani.
- Menyediakan bantuan alokasi FIFO berdasarkan tanggal transaksi, tetapi admin tetap bisa memilih transaksi petani secara manual.
- Mencatat koreksi stok jika ada selisih timbang.
- Menyediakan stock opname/adjustment untuk mencatat susut stok lokal karena penyimpanan, penguapan, atau koreksi fisik.

Acceptance criteria:

- Pembelian petani menambah stok.
- Pengiriman lokal mengurangi stok.
- Sistem bisa menunjukkan detail petani yang masuk ke pengiriman tertentu.
- Default alokasi stok memakai FIFO dari transaksi petani yang belum terkirim, lalu bisa disesuaikan manual sebelum pengiriman disimpan.
- Total alokasi satu transaksi petani ke satu atau beberapa pengiriman tidak boleh melebihi berat bersih transaksi tersebut.
- Stok tidak boleh minus tanpa otorisasi owner/super admin.
- Stock opname membuat baris ledger koreksi, tidak mengubah atau menghapus transaksi pembelian/pengiriman lama.

### 8.7 Pengiriman Lokal ke Pabrik

Fungsi:

- Pilih tanggal.
- Pilih pabrik.
- Pilih armada dan sopir perusahaan.
- Pilih detail transaksi petani atau kelompok transaksi harian.
- Input total tonase kirim.
- Input nomor DO.
- Update tonase final pabrik.
- Update harga pabrik, potongan pabrik, dan pembayaran pabrik.

Acceptance criteria:

- Pengiriman lokal mengurangi stok sementara.
- Nomor DO tidak boleh duplikat untuk pabrik yang sama lintas sumber lokal/mitra, kecuali transaksi masih berstatus draft dan belum dikirim.
- Status pembayaran pabrik jelas per DO.
- Pendapatan dari pengiriman lokal masuk ke laporan laba-rugi.
- Sortasi pabrik pada pengiriman lokal harus tampil sebagai kerugian/potongan kualitas pada laporan owner agar owner dapat mengevaluasi grading saat beli dari petani.

### 8.8 Pengiriman Mitra ke Pabrik

Fungsi:

- Pilih mitra.
- Pilih pabrik.
- Input tanggal kirim.
- Input nomor DO/tiket timbang.
- Input tonase timbang mitra.
- Input tonase final pabrik.
- Input nama sopir dan plat kendaraan mitra jika ada.
- Pilih armada: armada mitra atau armada perusahaan.
- Jika armada perusahaan, input jarak, tonase muatan, tarif, dan total potongan armada.
- Update pembayaran pabrik per DO.

Acceptance criteria:

- Operasional mitra tidak masuk ke biaya perusahaan kecuali armada perusahaan digunakan.
- Pembayaran pabrik masuk ke perusahaan.
- Nomor DO tidak boleh duplikat untuk pabrik yang sama lintas sumber lokal/mitra, kecuali transaksi masih berstatus draft dan belum dikirim.
- Setelah pabrik membayar, sistem membuat atau mengupdate settlement mitra.
- Hak mitra dihitung berdasarkan `tonase_dasar_settlement`.

### 8.9 Settlement Mitra

Fungsi:

- Melihat daftar settlement per mitra dan per DO.
- Menghitung hak mitra.
- Mencatat pembayaran penuh ke mitra.
- Mencatat potongan fee per kg.
- Mencatat potongan armada perusahaan.
- Mencatat potongan hutang/kasbon mitra.
- Membuat bukti settlement PDF atau gambar untuk WhatsApp.

Acceptance criteria:

- Settlement dibuat per DO.
- Settlement memiliki status: belum dihitung, menunggu pembayaran pabrik, menunggu bayar mitra, sebagian/koreksi, lunas, dibatalkan.
- Karena keputusan klien adalah mitra dibayar penuh, pembayaran sebagian tidak menjadi alur utama v1 final dan hanya dipakai untuk kasus koreksi/pengecualian.
- Owner/super admin/admin keuangan dapat melihat sisa kewajiban ke mitra.
- Laporan per mitra menunjukkan semua DO, pembayaran pabrik, fee, potongan, pembayaran ke mitra, dan sisa bayar.
- Admin keuangan boleh melihat rincian fee dan potongan settlement karena dibutuhkan untuk menjelaskan pembayaran ke mitra. Pembatasan laba-rugi tetap berlaku pada ringkasan margin/laba owner.

### 8.10 Hutang/Kasbon Petani

Fungsi:

- Tambah kasbon/panjar/pupuk/lainnya.
- Bayar tunai.
- Potong dari transaksi TBS.
- Riwayat debit/kredit.

Acceptance criteria:

- Saldo hutang dihitung dari ledger tunggal.
- Tidak ada double count antara transaksi dan log pembayaran.

### 8.11 Hutang/Kasbon Mitra

Fungsi:

- Menandai mitra yang boleh panjar/kasbon.
- Tambah panjar/kasbon mitra.
- Bayar tunai.
- Potong dari settlement mitra.
- Riwayat debit/kredit.

Acceptance criteria:

- Hutang mitra dihitung dari ledger tunggal.
- Potongan hutang mitra pada settlement tercatat satu kali.
- Mitra yang tidak diizinkan panjar/kasbon tidak bisa diberi kasbon tanpa otorisasi owner/super admin.

### 8.12 Biaya Operasional

Fungsi:

- Catat biaya perusahaan: solar, gaji sopir, kuli, retribusi, perawatan, lainnya.
- Tandai biaya sebagai:
  - Biaya perusahaan murni
  - Biaya bantuan mitra yang akan dipotong dari settlement
- Catat biaya aktual armada perusahaan jika membantu mitra.

Acceptance criteria:

- Biaya bantuan mitra tidak mengurangi laba dua kali jika sudah dipotong di settlement.
- Laporan memisahkan biaya perusahaan dan biaya bantuan mitra.

### 8.13 Pembayaran Pabrik

Fungsi:

- Mencatat pembayaran pabrik per DO.
- Mendukung satu pembayaran/transfer pabrik untuk satu DO atau beberapa DO.
- Mencatat harga pabrik per kg.
- Mencatat tonase final pabrik.
- Mencatat sortasi/grading sebagai tidak ada, kg, persentase, atau nominal rupiah.
- Mencatat biaya timbang.
- Mencatat tanggal pembayaran dan metode pembayaran.

Acceptance criteria:

- Satu DO memiliki status pembayaran yang jelas.
- Satu DO tidak boleh dialokasikan pembayaran melebihi nilai tagihannya.
- Potongan sortasi/grading harus dinormalisasi sebelum masuk perhitungan: tipe `kg` mengurangi `tonase_dasar_settlement`, sedangkan tipe `percent` dan `nominal` menjadi `potongan_sortasi_rupiah`.
- Jika tidak ada sortasi/grading atau pabrik sudah memberi tonase net/final, `potongan_sortasi_type` wajib bernilai `none`.
- Jika potongan sortasi/grading memakai tipe `percent`, nilainya disimpan sebagai angka 0 sampai 100.
- Jika pabrik sudah memberikan tonase final setelah potongan sortasi kg, admin tidak boleh menginput sortasi kg lagi agar tidak terjadi double count.
- Jika pabrik memberikan tonase bruto dan potongan sortasi kg secara terpisah, sistem menghitung `tonase_dasar_settlement = tonase_final_pabrik - potongan_sortasi_kg`.
- `total_pembayaran_pabrik` pada pengiriman/settlement adalah nilai final DO atau nilai tagihan pabrik setelah potongan, bukan bukti uang sudah diterima.
- Uang pabrik yang benar-benar sudah diterima dihitung dari alokasi pada `pembayaran_pabrik_detail`.
- Pembayaran pabrik menjadi dasar settlement mitra.
- Pembayaran pabrik menjadi dasar laporan kas dan laba-rugi.

### 8.14 Bukti Pembayaran Mitra

Fungsi:

- Generate bukti pembayaran dalam format PDF atau gambar.
- Format mudah dikirim via WhatsApp.
- Memuat identitas perusahaan, mitra, DO, pabrik, tonase, harga, fee, potongan, total hak mitra, dan status lunas.

Acceptance criteria:

- Bukti dapat dibuat setelah pembayaran mitra dicatat.
- Nomor bukti unik.
- Bukti dapat dicetak ulang atau diunduh ulang.

### 8.15 Laporan

#### Laporan Harian

Isi:

- TBS lokal masuk
- Stok lokal sementara
- Pengiriman lokal
- Pengiriman mitra
- Pembayaran pabrik
- Pembayaran ke petani
- Pembayaran ke mitra
- Biaya operasional
- Total kas keluar/masuk

Prioritas tampilan laporan harian:

1. Kas masuk dan kas keluar hari ini
2. TBS lokal masuk dan stok lokal
3. Pengiriman ke pabrik per DO
4. Settlement mitra yang menunggu bayar
5. Hutang/kasbon petani dan mitra
6. Ringkasan margin owner, hanya untuk owner/super admin

#### Laporan Petani

Isi:

- Riwayat transaksi TBS
- Hutang/kasbon
- Potongan hutang
- Total pembayaran

#### Laporan Mitra

Isi:

- Riwayat DO/pengiriman
- Tonase mitra vs tonase pabrik
- Tonase dasar settlement
- Selisih tonase
- Koreksi selisih tonase
- Pembayaran pabrik ke perusahaan
- Fee per kg
- Potongan armada
- Potongan hutang/kasbon
- Hak mitra
- Sudah dibayar
- Sisa bayar

#### Laporan Pabrik

Isi:

- Semua pengiriman atas nama perusahaan
- Sumber: lokal atau mitra
- Nomor DO
- Tonase
- Harga pabrik
- Sortasi/grading
- Tipe dan nilai sortasi/grading
- Biaya timbang
- Total pembayaran
- Status pembayaran

#### Laporan Stok Lokal

Isi:

- Stok awal
- TBS masuk dari petani
- TBS keluar ke pabrik
- Koreksi stok
- Sisa stok
- Detail transaksi petani yang terkait dengan pengiriman

#### Laba-Rugi Owner

Laporan ini hanya boleh diakses oleh owner dan super admin.

Minimal memisahkan:

- Pendapatan pengiriman lokal
- Pendapatan pengiriman mitra
- Pembelian TBS lokal
- Hak mitra
- Fee perusahaan dari mitra
- Biaya operasional perusahaan
- Biaya bantuan mitra
- Potongan armada mitra
- Margin bersih perusahaan

Mode laporan:

- Basis kas
- Basis transaksi

Aturan tampilan:

- **Laba Bersih Kas** menjadi angka utama di dashboard owner karena menunjukkan uang yang benar-benar sudah masuk/keluar.
- **Laba Estimasi Transaksi** menjadi angka pembanding karena memasukkan transaksi yang sudah terjadi tetapi belum selesai dibayar.
- Label laporan harus selalu menampilkan basis perhitungan agar owner tidak bingung membedakan uang nyata dan estimasi.

Aturan pengakuan laba-rugi:

- **Laba Bersih Kas** = pembayaran pabrik yang sudah diterima - pembayaran TBS petani yang sudah keluar - pembayaran mitra yang sudah keluar - biaya operasional yang sudah dibayar.
- **Laba Estimasi Transaksi** = nilai DO/pengiriman yang sudah memiliki tonase dan harga final - nilai pembelian TBS lokal - hak mitra - biaya operasional tercatat.
- Kasbon/panjar petani dan mitra bukan biaya laba-rugi. Kasbon/panjar ditampilkan sebagai piutang/kasbon aktif dan memengaruhi kas tersedia, tetapi tidak langsung mengurangi laba sampai dipotong/dikoreksi sesuai transaksi.
- Jika harga pabrik atau tonase final belum tersedia, transaksi boleh masuk estimasi hanya jika diberi label `estimasi`.

### 8.16 Pengaturan Bisnis

Fungsi:

- Mengatur fee default perusahaan per kg untuk mitra.
- Mengatur riwayat fee per kg per mitra berdasarkan tanggal/jam berlaku.
- Mengatur persentase default pembagian selisih tonase antara perusahaan dan mitra.
- Mengatur persentase khusus per mitra jika berbeda dari default sistem.
- Mengatur tarif default per armada berdasarkan km dan tonase.
- Mengatur tanggal berlaku tarif armada.
- Mengatur apakah tarif armada boleh dioverride pada pengiriman tertentu.
- Mengatur batas hutang/kasbon per mitra.
- Mengatur tindakan jika kasbon melebihi batas: blokir otomatis atau wajib approval owner/super admin.
- Mengatur prioritas kartu dashboard dan laporan harian.
- Mengatur toleransi anomali saat `tonase_dasar_settlement` lebih besar dari timbang mitra.

Acceptance criteria:

- Persentase selisih tonase perusahaan + mitra harus selalu 100%.
- Persentase disimpan dalam angka 0 sampai 100.
- Default awal pembagian selisih tonase adalah 50% perusahaan dan 50% mitra, kecuali owner/super admin mengubahnya.
- Tarif armada memakai satuan `tarif per km per ton`.
- Jarak armada disimpan dalam km dan tonase muatan disimpan dalam ton.
- Override tarif armada wajib menyimpan alasan dan masuk audit log.
- Kasbon mitra yang melewati batas tidak bisa disimpan tanpa approval sesuai pengaturan bisnis.
- Tindakan kasbon melebihi batas wajib bernilai salah satu: `blokir_otomatis` atau `wajib_approval`.
- Untuk v1, approval memakai mekanisme langsung berbasis role: admin biasa tidak bisa menyimpan aksi khusus, sedangkan owner/super admin dapat menyimpan dengan alasan approval yang wajib masuk audit log.
- Sistem tidak wajib menyediakan antrean approval terpisah pada v1, kecuali nanti diputuskan sebagai pengembangan lanjutan.
- Owner dan super admin bisa mengelola pengaturan bisnis.
- Admin operasional dan admin keuangan hanya bisa melihat pengaturan yang diperlukan untuk input transaksi.

### 8.17 Pembatalan dan Koreksi Transaksi

Fungsi:

- Membatalkan transaksi pembelian, pengiriman, pembayaran, settlement, hutang/kasbon, dan biaya operasional dengan alasan.
- Membuat reversal ledger untuk stok dan hutang/kasbon.
- Menyimpan audit log sebelum/sesudah pembatalan atau koreksi.

Acceptance criteria:

- Transaksi yang sudah berdampak ke stok, hutang, kas, atau settlement tidak boleh dihapus fisik dari database.
- Pembatalan harus membuat transaksi pembalik/reversal atau mengubah status menjadi dibatalkan dengan referensi reversal.
- Reversal stok memakai baris baru di `stok_tbs_lokal_ledger`.
- Reversal hutang/kasbon memakai baris baru di `hutang_ledger`.
- Pembatalan pembayaran pabrik atau mitra mengubah status pembayaran dan membatalkan alokasi/efek kas terkait.
- Aksi batal dan koreksi wajib dilakukan oleh owner/super admin atau role yang diberi otorisasi, serta wajib masuk audit log.

## 9. Status

### Status Pengiriman Lokal

- Draft
- Stok siap kirim
- Dikirim
- Diterima pabrik
- Dibayar pabrik
- Selesai
- Dibatalkan

### Status Pengiriman Mitra

- Dikirim mitra
- Diterima pabrik
- Menunggu pembayaran pabrik
- Sudah dibayar pabrik ke perusahaan
- Menunggu pembayaran mitra
- Pembayaran mitra sebagian/koreksi
- Settlement lunas
- Dibatalkan

### Status Settlement Mitra

- Belum dihitung
- Menunggu pembayaran pabrik
- Menunggu bayar mitra
- Sebagian/koreksi
- Lunas
- Dibatalkan

### Status Pembayaran Pabrik

- Draft
- Teralokasi sebagian
- Teralokasi penuh
- Dibatalkan

### Status Pembayaran Mitra

- Draft
- Dibayar
- Sebagian/koreksi
- Dibatalkan

### Status Transaksi Umum

- Aktif
- Menunggu approval langsung
- Disetujui
- Dibatalkan
- Direversal

## 10. Rekomendasi Data Model

### Tabel `petani`

Field:

- id
- nama
- no_hp
- alamat
- nomor_ktp
- batas_kasbon
- aktif
- created_at

### Tabel `mitra`

Field:

- id
- nama
- penanggung_jawab
- no_hp
- alamat
- rekening
- fee_per_kg
- boleh_kasbon
- batas_kasbon
- persen_selisih_ditanggung_perusahaan
- persen_selisih_ditanggung_mitra
- aktif
- created_at

Catatan:

- `fee_per_kg` pada master mitra dipakai sebagai nilai default/current untuk tampilan cepat.
- Perhitungan settlement wajib memakai `fee_mitra_history` yang berlaku pada tanggal pengiriman/DO.

### Tabel `pabrik`

Field:

- id
- nama
- alamat
- kontak
- rekening
- pola_pembayaran: per_do
- harga_default_per_kg
- aktif
- created_at

### Tabel `armada_perusahaan`

Field:

- id
- plat_nomor
- jenis_kendaraan
- kapasitas_kg
- kepemilikan
- aktif
- created_at

### Tabel `armada_mitra`

Field:

- id
- mitra_id
- plat_kendaraan
- nama_sopir
- no_hp_sopir
- aktif
- created_at

### Tabel `harga_tbs_lokal`

Field:

- id
- harga_per_kg
- berlaku_mulai
- berlaku_sampai
- aktif
- created_by
- created_at

Catatan:

- Harga yang dipakai transaksi adalah harga aktif dengan `berlaku_mulai` paling dekat tetapi tidak melebihi waktu transaksi.
- Perubahan harga tidak boleh mengubah transaksi lama yang sudah tersimpan.

### Tabel `fee_mitra_history`

Field:

- id
- mitra_id
- fee_per_kg
- berlaku_mulai
- berlaku_sampai
- aktif
- created_by
- created_at

Catatan:

- Fee settlement diambil dari riwayat fee yang berlaku pada tanggal pengiriman/DO, bukan dari nilai master mitra terbaru.
- Perubahan fee tidak boleh mengubah settlement lama.

### Tabel `tarif_armada`

Field:

- id
- armada_id
- tarif_per_km_per_ton
- minimum_charge
- berlaku_mulai
- berlaku_sampai
- aktif
- created_by
- created_at

### Tabel `transaksi_beli_tbs`

Field:

- id
- nomor_struk
- petani_id
- tanggal
- berat_kotor_kg
- potongan_kg
- berat_bersih_kg
- harga_per_kg
- total_harga
- potongan_hutang
- total_bayar_petani
- status
- created_by
- created_at

Catatan:

- `nomor_struk` harus unik.
- Transaksi pembelian membuat baris masuk di `stok_tbs_lokal_ledger`.
- Jika transaksi dibatalkan, stok dan hutang/kasbon dibalik memakai reversal ledger.

### Tabel `pengiriman`

Field utama/tambahan:

- sumber: lokal, mitra
- pabrik_id
- mitra_id
- tanggal_kirim
- nomor_do
- tonase_timbang_sumber
- tonase_pabrik
- tonase_dasar_settlement
- selisih_tonase
- nilai_selisih_tonase
- persen_selisih_ditanggung_perusahaan
- persen_selisih_ditanggung_mitra
- koreksi_selisih_dibayar_perusahaan
- harga_pabrik_per_kg
- potongan_sortasi_type: none, kg, percent, nominal
- potongan_sortasi_value
- potongan_sortasi_rupiah
- biaya_timbang
- potongan_pabrik_lain
- total_pembayaran_pabrik
- armada_type: perusahaan, mitra
- kendaraan_mitra_text
- sopir_mitra_text
- jarak_armada_km
- tonase_muatan_armada_ton
- tarif_armada_per_km_per_ton
- tarif_armada_source: default, override
- alasan_override_tarif_armada
- biaya_armada_dibebankan_ke_mitra
- biaya_aktual_armada_perusahaan
- settlement_id
- status
- created_by
- created_at

Catatan:

- Jika `sumber = lokal`, maka `mitra_id` wajib kosong.
- Jika `sumber = mitra`, maka `mitra_id` wajib terisi.
- `nomor_do` harus unik untuk `pabrik_id` ketika status bukan draft, lintas sumber lokal dan mitra.
- Validasi alokasi stok lokal harus memakai transaksi database agar dua admin tidak bisa mengalokasikan stok yang sama secara bersamaan.
- V1 mendukung satu tipe sortasi utama per DO melalui `potongan_sortasi_type`. Jika pabrik memberikan beberapa komponen potongan sekaligus, komponen tambahan dicatat pada `potongan_pabrik_lain` sebagai nominal.

### Tabel `stok_tbs_lokal_ledger`

Field:

- id
- tanggal
- tipe: masuk, keluar, koreksi
- sumber: pembelian_petani, pengiriman_pabrik, koreksi_manual
- transaksi_beli_id
- pengiriman_id
- berat_kg
- keterangan
- created_by
- created_at

Catatan:

- Saldo stok dihitung dari ledger, bukan disimpan manual sebagai angka utama.
- Koreksi stok dan pembatalan transaksi harus membuat baris ledger baru, bukan mengubah/menghapus baris lama.

### Tabel `pengiriman_lokal_detail`

Field:

- id
- pengiriman_id
- transaksi_beli_id
- petani_id
- berat_alokasi_kg
- created_at

Catatan:

- Satu transaksi petani boleh dialokasikan ke lebih dari satu pengiriman jika diperlukan.
- Total `berat_alokasi_kg` untuk satu `transaksi_beli_id` tidak boleh melebihi berat bersih transaksi pembelian petani.

### Tabel `pembayaran_pabrik`

Field:

- id
- pabrik_id
- tanggal_bayar
- total_bayar
- metode
- rekening_tujuan
- referensi_transfer
- bukti_transfer_url
- status
- keterangan
- created_by
- created_at

Catatan:

- Satu pembayaran pabrik dapat membayar satu DO atau beberapa DO.
- Total alokasi pada detail pembayaran tidak boleh melebihi `total_bayar`.
- `total_bayar` adalah uang aktual yang diterima perusahaan dari pabrik.

### Tabel `pembayaran_pabrik_detail`

Field:

- id
- pembayaran_pabrik_id
- pengiriman_id
- nomor_do
- jumlah_dialokasikan
- tonase_pabrik
- tonase_dasar_settlement
- harga_pabrik_per_kg
- potongan_sortasi_type: none, kg, percent, nominal
- potongan_sortasi_value
- potongan_sortasi_rupiah
- biaya_timbang
- potongan_pabrik_lain
- created_at

Catatan:

- Satu DO tidak boleh menerima alokasi pembayaran melebihi nilai tagihannya.
- Status pembayaran DO dihitung dari total alokasi pembayaran pabrik detail.
- Jika total alokasi sama dengan `total_pembayaran_pabrik` pada pengiriman, status DO menjadi dibayar penuh.

### Tabel `settlement_mitra`

Field:

- id
- mitra_id
- pengiriman_id
- nomor_do
- tanggal_settlement
- tonase_timbang_mitra
- tonase_pabrik
- tonase_dasar_settlement
- selisih_tonase
- nilai_selisih_tonase
- persen_selisih_ditanggung_perusahaan
- persen_selisih_ditanggung_mitra
- koreksi_selisih_dibayar_perusahaan
- harga_pabrik_per_kg
- total_bruto_pabrik
- potongan_sortasi_type: none, kg, percent, nominal
- potongan_sortasi_value
- potongan_sortasi_rupiah
- biaya_timbang
- potongan_pabrik_lain
- total_pembayaran_pabrik
- fee_per_kg
- fee_perusahaan
- potongan_armada
- potongan_hutang_kasbon
- potongan_lain
- total_hak_mitra
- total_dibayar
- sisa_bayar
- status
- created_at

### Tabel `pembayaran_mitra`

Field:

- id
- settlement_id
- mitra_id
- tanggal
- jumlah
- metode
- status
- keterangan
- created_by
- created_at

### Tabel `biaya_operasional`

Field:

- id
- tanggal
- kategori: solar, gaji_sopir, kuli, retribusi, perawatan, lainnya
- jumlah
- tipe_biaya: biaya_perusahaan, bantuan_mitra_dipotong_settlement
- pengiriman_id
- mitra_id
- armada_id
- keterangan
- status
- created_by
- created_at

Catatan:

- Jika `tipe_biaya = bantuan_mitra_dipotong_settlement`, biaya harus bisa dikaitkan ke pengiriman/settlement mitra.
- Biaya bantuan mitra tidak boleh mengurangi laba dua kali jika sudah menjadi potongan settlement.
- Pembatalan biaya operasional dilakukan dengan status/reversal, bukan delete fisik.


### Tabel `hutang_ledger`

Dipakai untuk petani dan mitra agar tidak double count.

Field:

- id
- pihak_type: petani, mitra
- petani_id
- mitra_id
- tanggal
- tipe: debit, kredit
- sumber: kasbon, panjar, bayar_tunai, potong_tbs, potong_settlement, koreksi
- jumlah
- transaksi_beli_id
- settlement_id
- keterangan
- created_by
- created_at

Catatan:

- Jika `pihak_type = petani`, maka `petani_id` wajib terisi dan `mitra_id` harus kosong.
- Jika `pihak_type = mitra`, maka `mitra_id` wajib terisi dan `petani_id` harus kosong.
- Saldo hutang/kasbon dihitung dari ledger, bukan disimpan manual sebagai angka terpisah.

### Tabel `bukti_pembayaran`

Field:

- id
- tipe: pembayaran_mitra, pembayaran_petani, pembayaran_pabrik
- nomor_bukti
- pembayaran_mitra_id
- pembayaran_pabrik_id
- transaksi_beli_id
- file_url
- format: pdf, image
- created_by
- created_at

### Tabel `pengaturan_bisnis`

Field:

- id
- key
- value_json
- scope: global, mitra, armada
- scope_id
- berlaku_mulai
- aktif
- updated_by
- updated_at

Contoh `key`:

- default_fee_per_kg_mitra
- default_persen_selisih_perusahaan
- default_persen_selisih_mitra
- default_tindakan_kasbon_melebihi_limit
- default_toleransi_anomali_tonase_kg
- default_mode_approval_v1
- dashboard_owner_primary_profit_metric
- prioritas_laporan_harian

### Tabel `audit_log`

Field:

- id
- actor_user_id
- actor_role
- entity_type
- entity_id
- action: create, update, delete, cancel, approve, export, override
- before_json
- after_json
- alasan
- approved_by
- approved_at
- created_at

Transaksi yang wajib masuk audit log:

- Pembelian TBS petani
- Pengiriman lokal
- Pengiriman mitra
- Pembayaran pabrik
- Settlement mitra
- Pembayaran mitra
- Hutang/kasbon petani
- Hutang/kasbon mitra
- Biaya operasional
- Pembatalan/reversal transaksi
- Override tarif armada
- Koreksi stok
- Perubahan pengaturan bisnis

## 11. Hak Akses

| Modul | Owner | Super Admin | Admin Operasional | Admin Keuangan |
| --- | --- | --- | --- | --- |
| Dashboard umum | Ya | Ya | Ya | Ya |
| Laba-rugi / keuntungan | Ya | Ya | Tidak | Tidak |
| Master petani | Ya | Ya | Ya | Lihat |
| Master mitra | Ya | Ya | Ya | Lihat |
| Pembelian petani | Ya | Ya | Ya | Lihat |
| Pengiriman lokal | Ya | Ya | Ya | Lihat |
| Pengiriman mitra | Ya | Ya | Ya | Lihat |
| Pembayaran pabrik | Ya | Ya | Lihat | Ya |
| Settlement mitra | Ya | Ya | Lihat | Ya |
| Hutang petani | Ya | Ya | Lihat | Ya |
| Hutang mitra | Ya | Ya | Lihat | Ya |
| Biaya operasional | Ya | Ya | Input | Ya |
| Pengaturan bisnis | Ya | Ya | Lihat | Lihat |
| Audit log | Ya | Ya | Tidak | Tidak |
| Pengaturan user | Tidak | Ya | Tidak | Tidak |
| Pengaturan role akses | Tidak | Ya | Tidak | Tidak |

Prinsip hak akses detail:

- Super admin dapat melakukan semua aksi, termasuk mengelola akun user dan role akses.
- Owner dapat melihat, membuat, mengubah, membatalkan, menyetujui, dan mengekspor data bisnis, tetapi tidak dapat mengelola akun user dan role akses.
- Admin operasional fokus pada input operasional dan tidak dapat melihat laba-rugi/keuntungan.
- Admin keuangan fokus pada pembayaran, hutang/kasbon, settlement, dan laporan kas, tetapi tidak dapat melihat laba-rugi/keuntungan.
- Aksi sensitif seperti batal transaksi, koreksi stok, override tarif armada, dan kasbon melewati batas wajib masuk audit log.

## 12. Prioritas Implementasi

### P0 - Wajib Sebelum Dipakai Serius

#### P0A - Fondasi dan Alur Lokal

- Pisahkan petani dan mitra.
- Tambah role super admin.
- Batasi pengelolaan akun user dan role akses hanya untuk super admin.
- Batasi laporan laba-rugi hanya untuk owner dan super admin.
- Tambah master petani, pabrik, armada perusahaan, dan harga TBS lokal berbasis tanggal/jam berlaku.
- Tambah stok sementara TBS lokal.
- Tambah alokasi stok lokal default FIFO dengan opsi pilih manual transaksi petani.
- Tambah transaksi pembelian TBS petani dan nomor struk unik.
- Tambah pengiriman lokal ke pabrik dan pembayaran pabrik per DO.
- Perbaiki hutang/kasbon memakai ledger tunggal.
- Perbaiki nomor struk dan nomor bukti agar aman dari bentrok.
- Tambah pembatalan/reversal ledger untuk transaksi uang, stok, hutang, dan pembayaran.
- Perketat RLS Supabase dan akses aplikasi.

#### P0B - Alur Mitra dan Settlement

- Tambah modul pengaturan bisnis untuk fee, pembagian selisih tonase, tarif armada, limit kasbon, dan prioritas laporan.
- Tambah riwayat fee mitra berdasarkan tanggal/jam berlaku.
- Tambah alur pengiriman mitra per DO.
- Tambah settlement mitra per DO.
- Tambah tabel pembayaran pabrik dan detail alokasi pembayaran per DO.
- Fee mitra nominal per kg.
- Pembayaran mitra berdasarkan `tonase_dasar_settlement`.
- Tambah pembagian selisih tonase berdasarkan persentase yang bisa diatur.
- Tambah alert anomali jika `tonase_dasar_settlement` lebih besar dari timbang mitra melewati toleransi.
- Tambah hutang/kasbon mitra.
- Tambah batas hutang/kasbon per mitra dan approval jika melewati batas.
- Tambah biaya operasional dan biaya bantuan mitra yang bisa dipotong settlement.

#### P0C - Kontrol, Audit, dan Laporan Owner

- Tampilkan Laba Bersih Kas sebagai angka utama owner dan Laba Estimasi Transaksi sebagai pembanding.
- Tambah audit log minimal untuk transaksi uang, tonase, stok, settlement, dan pengaturan bisnis.
- Perbaiki encoding teks/icon.
- Tambah laporan dasar harian, pabrik per DO, stok lokal, settlement mitra, dan laba-rugi owner.

### P1 - Penting Untuk Operasional Harian

- Laporan per mitra.
- Laporan pabrik per DO.
- Potongan sortasi/grading dan biaya timbang.
- Potongan armada perusahaan untuk mitra.
- Riwayat tarif armada dan override tarif dengan alasan.
- Bukti pembayaran mitra PDF/gambar untuk WhatsApp.
- Laporan stok lokal.
- Ekspor laporan operasional tanpa data laba-rugi sesuai role.

### P2 - Pengembangan Lanjutan

- Upload foto tiket timbang/DO.
- Multi-lokasi timbang.
- Ekspor Excel settlement mitra.
- Dashboard owner dengan margin per sumber.
- Template WhatsApp otomatis untuk bukti pembayaran.
- Rekonsiliasi lanjutan selisih timbang mitra vs pabrik.

## 13. Catatan Implementasi dan Risiko

- Pembagian selisih berat harus selalu memakai persentase yang tersimpan agar settlement bisa diaudit.
- Tarif armada perlu riwayat tanggal berlaku agar perubahan tarif tidak mengubah perhitungan pengiriman lama.
- Fee mitra perlu riwayat tanggal berlaku agar perubahan fee tidak mengubah pengiriman/settlement lama.
- Ledger hutang/kasbon harus generik untuk petani dan mitra agar tidak terjadi double count.
- Transaksi yang sudah berdampak ke ledger tidak boleh dihapus; pembatalan harus memakai reversal agar audit tetap utuh.
- Kondisi `tonase_dasar_settlement` lebih besar dari timbang mitra harus ditandai sebagai anomali rekonsiliasi agar tidak luput dari perhatian owner/admin.
- Laporan owner harus memakai label jelas: Laba Bersih Kas untuk uang nyata, Laba Estimasi Transaksi untuk transaksi yang belum selesai dibayar.
- Bukti pembayaran WhatsApp harus ringkas dan mudah dibaca di HP.
- Prioritas laporan harian mengikuti urutan yang paling sering dipakai: kas, stok/TBS lokal, DO pabrik, settlement mitra, hutang/kasbon, lalu margin owner.

## 14. Definisi Sukses Final

Versi final dianggap berhasil jika:

- Admin bisa mencatat pembelian TBS dari petani lokal.
- Pembelian petani otomatis menambah stok sementara.
- Harga beli petani memakai harga yang berlaku berdasarkan tanggal/jam transaksi.
- Admin bisa mengirim TBS lokal ke pabrik dengan detail transaksi petani dan total harian.
- Admin bisa mencatat pengiriman mitra ke pabrik per DO.
- Sistem bisa mencatat pembayaran pabrik per DO.
- Sistem menghitung hak mitra berdasarkan `tonase_dasar_settlement`.
- Sistem memotong fee perusahaan nominal per kg.
- Sistem memakai fee mitra yang berlaku pada tanggal/jam pengiriman/DO.
- Sistem membagi selisih tonase memakai persentase yang bisa diatur owner/super admin.
- Sistem memberi peringatan anomali jika `tonase_dasar_settlement` lebih besar dari timbang mitra melewati toleransi.
- Sistem memotong biaya armada perusahaan dari hak mitra jika armada perusahaan dipakai.
- Sistem memakai tarif default per armada dan mencatat override tarif jika ada.
- Sistem bisa mencatat hutang/kasbon petani dan mitra tanpa double count.
- Sistem bisa membatasi kasbon mitra sesuai limit dan meminta approval jika melewati batas.
- Sistem membatalkan/koreksi transaksi menggunakan reversal dan audit log, bukan delete fisik.
- Sistem bisa membuat bukti pembayaran mitra dalam PDF atau gambar untuk WhatsApp.
- Owner dan super admin bisa melihat Laba Bersih Kas dan Laba Estimasi Transaksi.
- Admin biasa tidak bisa melihat laporan keuntungan.
- Laporan bisa memisahkan sumber lokal dan mitra.
- Biaya perusahaan tidak tercampur dengan biaya mitra.

