# PRD v1 - Sawit CB

## 1. Ringkasan Produk

Sawit CB adalah aplikasi operasional dan keuangan untuk bisnis RAM kelapa sawit yang mencatat pembelian TBS dari petani lokal, pengiriman TBS ke pabrik, hutang/kasbon, biaya operasional, pembayaran pabrik, dan pembagian hasil ke mitra.

Pada revisi v1, sistem perlu membedakan dua sumber TBS:

1. **Petani lokal**: pemasok individu yang menjual TBS langsung ke klien. TBS ditimbang di timbangan klien, dibayar oleh klien, lalu dikirim ke pabrik menggunakan armada klien.
2. **Mitra**: pihak pengumpul/RAM kecil yang memiliki timbangan sendiri. Mitra mengumpulkan TBS sendiri dan umumnya mengirim ke pabrik dengan sopir/armada sendiri, tetapi pengiriman ke pabrik tetap masuk atas nama klien. Pabrik membayar ke klien, lalu klien membagikan hasil pembayaran ke mitra sesuai tonase, harga, dan potongan yang disepakati.

Sistem harus mampu memisahkan pencatatan operasional, hutang, biaya, dan settlement untuk dua alur tersebut agar laporan klien tidak tercampur.

## 2. Tujuan Produk

- Mencatat seluruh tonase TBS yang masuk ke pabrik atas nama klien, baik dari petani lokal maupun mitra.
- Menyediakan pencatatan pembelian langsung dari petani lokal.
- Menyediakan pencatatan pengiriman mitra yang memakai timbangan, armada, dan biaya operasional mitra sendiri.
- Mengelola pembayaran pabrik ke klien dan pembagian hasil ke mitra.
- Mengelola penggunaan armada klien oleh mitra sebagai biaya/potongan settlement.
- Menghasilkan laporan harian, laporan per petani, laporan per mitra, laporan pengiriman pabrik, hutang/piutang, dan laba-rugi.

## 3. Role Pengguna

### Owner

- Melihat seluruh dashboard dan laporan keuangan.
- Mengelola harga, formula settlement mitra, biaya, dan laba-rugi.
- Mengonfirmasi pembayaran pabrik dan pembayaran ke mitra.
- Melihat audit perubahan transaksi.

### Admin Operasional

- Input transaksi TBS petani lokal.
- Input pengiriman ke pabrik.
- Input data pengiriman dari mitra.
- Input biaya operasional.
- Mengelola master data petani, mitra, pabrik, armada, dan sopir.

### Admin Keuangan

- Mencatat pembayaran pabrik.
- Mencatat pembayaran ke mitra.
- Mencatat hutang/kasbon petani dan potongan pembayaran.
- Melihat laporan hutang, settlement, dan kas keluar/masuk.

## 4. Entitas Utama

### Petani

Petani adalah pemasok individu yang menjual TBS langsung ke klien.

Data minimal:
- Nama
- Nomor HP
- Alamat
- Nomor KTP, opsional
- Batas hutang/kasbon
- Status aktif/nonaktif

### Mitra

Mitra adalah pihak pengumpul yang memiliki timbangan sendiri dan dapat mengirim TBS ke pabrik atas nama klien.

Data minimal:
- Nama mitra/usaha
- Penanggung jawab
- Nomor HP
- Alamat/lokasi timbang
- Nomor rekening, opsional
- Pola settlement default
- Fee/komisi/potongan default, jika ada
- Status aktif/nonaktif

### Armada Klien

Armada milik/sewa klien yang digunakan untuk pengiriman TBS petani lokal atau membantu mitra.

Data minimal:
- Plat nomor
- Jenis kendaraan
- Kapasitas
- Kepemilikan
- Status aktif/nonaktif

### Armada Mitra

Armada yang digunakan oleh mitra dan biayanya ditanggung mitra. Sistem tidak perlu menghitung biaya operasionalnya sebagai biaya klien, tetapi tetap perlu mencatat identitas pengiriman jika dibutuhkan untuk bukti/rekonsiliasi.

Data minimal:
- Nama/plat kendaraan, opsional
- Nama sopir, opsional
- Nomor HP sopir, opsional
- Mitra pemilik

### Pabrik

Tujuan pengiriman TBS yang melakukan pembayaran ke klien.

Data minimal:
- Nama pabrik
- Alamat
- Kontak
- Harga pabrik per kg, jika tersedia per DO

## 5. Alur Bisnis Baru

## 5.1 Alur A - Petani Lokal ke Klien

1. Admin mengatur harga TBS harian.
2. Petani lokal membawa TBS ke lokasi klien.
3. Klien menimbang TBS di timbangan sendiri.
4. Sistem menghitung:
   - Berat kotor
   - Potongan/sortasi
   - Berat bersih
   - Harga beli per kg
   - Total pembelian
   - Potong hutang, jika ada
   - Bayar tunai
5. Klien membayar petani.
6. TBS dikirim ke pabrik menggunakan armada klien.
7. Pengiriman dicatat sebagai stok/tonase milik klien.
8. Pabrik membayar ke klien.
9. Pendapatan masuk ke laporan laba-rugi klien.

Catatan:
- Biaya solar, sopir, kuli, retribusi, dan perawatan armada klien masuk sebagai biaya operasional klien.
- Hutang/kasbon petani hanya berlaku untuk petani lokal, kecuali nanti diputuskan mitra juga bisa punya piutang/hutang.

## 5.2 Alur B - Mitra Mengirim Sendiri ke Pabrik

1. Mitra membeli/mengumpulkan TBS dari sumbernya sendiri.
2. Mitra menimbang di timbangan mitra.
3. Mitra mengirim TBS ke pabrik memakai armada dan sopir mitra.
4. Pengiriman masuk ke pabrik atas nama klien.
5. Admin mencatat pengiriman mitra:
   - Mitra
   - Tanggal kirim
   - Pabrik tujuan
   - Tonase timbang mitra
   - Tonase diterima pabrik, jika sudah ada
   - Nomor DO/tiket timbang
   - Armada/sopir mitra, opsional
   - Status pengiriman
6. Pabrik membayar ke rekening/akun klien.
7. Klien menghitung hak mitra berdasarkan data pabrik dan kesepakatan.
8. Klien membayar mitra.
9. Sistem mencatat settlement mitra dan status lunas/belum lunas.

Prinsip akuntansi:
- Biaya operasional mitra tidak masuk sebagai biaya klien.
- Pendapatan pabrik tetap tercatat sebagai uang masuk ke klien.
- Kewajiban bayar ke mitra harus tercatat sebagai hutang/settlement mitra.
- Margin klien dari mitra berasal dari selisih pembayaran pabrik dengan nilai yang dibayarkan ke mitra, atau dari fee/potongan yang disepakati.

## 5.3 Alur C - Mitra Memakai Armada Klien

Skenario ini terjadi saat mitra kesulitan memuat/mengirim dan memakai armada klien.

1. Mitra meminta bantuan armada klien.
2. Admin membuat pengiriman mitra dengan pilihan `armada_digunakan = armada_klien`.
3. Sistem mencatat:
   - Armada klien
   - Sopir klien
   - Biaya aktual, jika klien menanggung dulu
   - Biaya yang akan dibebankan ke mitra
4. Pabrik tetap membayar ke klien.
5. Saat settlement, biaya armada klien menjadi potongan dari hak mitra atau menjadi tagihan terpisah.
6. Laporan harus bisa membedakan:
   - Biaya operasional klien murni
   - Biaya bantuan mitra yang akan direimburse/dipotong
   - Margin bersih dari pengiriman mitra

Rekomendasi v1:
- Gunakan mekanisme potongan settlement mitra, bukan membuat modul invoice terpisah dulu.
- Field wajib: `biaya_armada_dibebankan_ke_mitra`.
- Field opsional: `biaya_aktual_armada_klien`.

## 6. Status Pengiriman

### Untuk Pengiriman Petani Lokal / Milik Klien

- Draft
- Dikirim
- Diterima pabrik
- Dibayar pabrik
- Selesai
- Dibatalkan

### Untuk Pengiriman Mitra

- Dikirim mitra
- Diterima pabrik
- Menunggu pembayaran pabrik
- Sudah dibayar pabrik ke klien
- Menunggu settlement mitra
- Settlement sebagian
- Settlement lunas
- Dibatalkan

## 7. Settlement Mitra

Settlement adalah proses menghitung hak mitra setelah pabrik membayar ke klien.

### Input Settlement

- Mitra
- Periode atau nomor DO
- Total tonase pabrik
- Harga pabrik per kg
- Total pembayaran pabrik
- Potongan pabrik, jika ada
- Fee/komisi klien, jika ada
- Potongan armada klien, jika ada
- Potongan lain, jika ada
- Total hak mitra
- Jumlah sudah dibayar ke mitra
- Sisa bayar ke mitra
- Status settlement

### Formula Dasar

```text
Total pembayaran pabrik = tonase_pabrik x harga_pabrik_per_kg

Hak mitra sebelum potongan = total pembayaran pabrik - fee_klien

Total potongan mitra =
  potongan_armada_klien
  + potongan_lain
  + kasbon/piutang_mitra, jika fitur ini dipakai

Hak mitra final = hak mitra sebelum potongan - total potongan mitra

Margin klien dari mitra =
  total pembayaran pabrik - hak mitra final - biaya yang benar-benar ditanggung klien
```

Catatan penting:
- Jika fee klien berupa nominal per kg, maka `fee_klien = tonase_pabrik x fee_per_kg`.
- Jika fee klien berupa persentase, maka `fee_klien = total pembayaran pabrik x persentase_fee`.
- Jika klien hanya menjadi perantara tanpa mengambil fee, margin klien dari mitra bisa nol kecuali ada potongan layanan armada.

## 8. Modul Produk

## 8.1 Dashboard

Dashboard harus menampilkan ringkasan berbeda untuk operasional sendiri dan mitra.

Kartu utama:
- TBS petani lokal hari ini
- TBS mitra masuk pabrik hari ini
- Total tonase ke pabrik hari ini
- Pengiriman menunggu pembayaran pabrik
- Settlement mitra belum lunas
- Hutang petani aktif
- Biaya operasional klien hari ini
- Estimasi laba/margin owner

Filter:
- Hari ini
- Mingguan
- Bulanan
- Sumber TBS: petani lokal, mitra, semua

## 8.2 Master Petani

Fungsi:
- Tambah/edit/nonaktifkan petani.
- Batas hutang.
- Riwayat transaksi petani.

Acceptance criteria:
- Petani tidak tercampur dengan mitra.
- Petani hanya muncul di form transaksi pembelian lokal.

## 8.3 Master Mitra

Fungsi:
- Tambah/edit/nonaktifkan mitra.
- Set pola settlement default.
- Set fee default, jika ada.
- Melihat riwayat pengiriman dan settlement.

Acceptance criteria:
- Mitra tidak muncul di form transaksi petani lokal.
- Mitra muncul di form pengiriman mitra.
- Setiap mitra memiliki ringkasan tonase, nilai pabrik, hak mitra, sudah dibayar, dan sisa bayar.

## 8.4 Harga TBS Lokal

Fungsi:
- Set harga beli TBS harian untuk petani lokal.
- Riwayat harga.

Catatan:
- Harga beli petani lokal tidak selalu sama dengan harga pabrik.
- Harga pabrik dicatat di pengiriman/pembayaran pabrik.

## 8.5 Input TBS Petani Lokal

Fungsi:
- Pilih petani.
- Input berat kotor dan potongan.
- Ambil harga harian.
- Hitung total harga.
- Potong hutang petani.
- Simpan transaksi.
- Cetak struk.

Acceptance criteria:
- Transaksi tidak bisa disimpan jika harga harian belum diset.
- Potongan hutang harus tercatat satu kali di ledger hutang.
- Nomor struk harus unik walaupun ada input bersamaan.

## 8.6 Pengiriman Klien ke Pabrik

Untuk TBS dari pembelian lokal yang dikirim memakai armada klien.

Fungsi:
- Pilih tanggal.
- Pilih pabrik.
- Pilih armada dan sopir klien.
- Input tonase kirim.
- Input nomor DO.
- Update tonase diterima pabrik.
- Update harga pabrik dan pembayaran.

Acceptance criteria:
- Pengiriman dapat dikaitkan dengan kumpulan transaksi TBS lokal atau minimal tanggal operasional.
- Status pembayaran pabrik jelas.
- Pendapatan dari pengiriman ini masuk ke laba-rugi klien.

## 8.7 Pengiriman Mitra ke Pabrik

Fungsi:
- Pilih mitra.
- Pilih pabrik.
- Input tanggal kirim.
- Input tonase versi mitra.
- Input tonase versi pabrik.
- Input nomor DO/tiket timbang.
- Pilih armada: armada mitra atau armada klien.
- Jika armada klien, input biaya/potongan armada.
- Update pembayaran pabrik.

Acceptance criteria:
- Operasional mitra tidak masuk ke biaya klien kecuali armada klien digunakan.
- Pembayaran pabrik masuk ke klien.
- Setelah pabrik membayar, sistem membuat atau mengupdate settlement mitra.

## 8.8 Settlement Mitra

Fungsi:
- Melihat daftar settlement per mitra/per DO/per periode.
- Menghitung hak mitra.
- Mencatat pembayaran ke mitra.
- Mencatat pembayaran sebagian.
- Mencatat potongan armada klien atau potongan lain.
- Export bukti settlement.

Acceptance criteria:
- Settlement memiliki status: belum dihitung, menunggu bayar, sebagian, lunas.
- Owner/admin keuangan dapat melihat sisa kewajiban ke mitra.
- Laporan per mitra menunjukkan semua DO, pembayaran pabrik, potongan, dan pembayaran ke mitra.

## 8.9 Hutang Petani

Fungsi:
- Tambah kasbon/panjar/pupuk/lainnya.
- Bayar tunai.
- Potong dari transaksi TBS.
- Riwayat debit/kredit.

Acceptance criteria:
- Saldo hutang dihitung dari ledger tunggal.
- Tidak ada double count antara transaksi dan log pembayaran.

## 8.10 Biaya Operasional

Fungsi:
- Catat biaya klien: solar, gaji sopir, kuli, retribusi, perawatan, lainnya.
- Tandai biaya sebagai:
  - Biaya klien
  - Biaya bantuan mitra yang dibebankan ke mitra

Acceptance criteria:
- Biaya bantuan mitra tidak mengurangi laba klien dua kali jika sudah dipotong di settlement.
- Laporan bisa memisahkan biaya klien dan biaya yang akan ditagihkan/dipotong ke mitra.

## 8.11 Laporan

### Laporan Harian

Isi:
- TBS lokal masuk
- Pengiriman klien
- Pengiriman mitra
- Pembayaran pabrik
- Pembayaran ke petani
- Pembayaran ke mitra
- Biaya operasional
- Total kas keluar/masuk

### Laporan Petani

Isi:
- Riwayat transaksi TBS
- Hutang/kasbon
- Potongan hutang
- Total pembayaran

### Laporan Mitra

Isi:
- Riwayat DO/pengiriman
- Tonase mitra vs tonase pabrik
- Pembayaran pabrik ke klien
- Fee/potongan
- Hak mitra
- Sudah dibayar
- Sisa bayar
- Penggunaan armada klien

### Laporan Pabrik

Isi:
- Semua pengiriman atas nama klien
- Sumber: lokal atau mitra
- Tonase
- Harga pabrik
- Total pembayaran
- Status pembayaran

### Laba-Rugi Owner

Minimal memisahkan:
- Pendapatan pengiriman lokal
- Pendapatan pengiriman mitra
- Pembelian TBS lokal
- Hak mitra
- Biaya operasional klien
- Biaya bantuan mitra
- Margin bersih klien

## 9. Rekomendasi Perubahan Data Model

### Tambah tabel `mitra`

Field:
- id
- nama
- penanggung_jawab
- no_hp
- alamat
- rekening
- fee_type: none, per_kg, percent, nominal
- fee_value
- aktif
- created_at

### Tambah field di `pengiriman`

Field:
- sumber: lokal, mitra
- mitra_id
- tonase_timbang_sumber
- tonase_pabrik
- armada_type: klien, mitra
- kendaraan_mitra_text
- sopir_mitra_text
- biaya_armada_dibebankan_ke_mitra
- biaya_aktual_armada_klien
- settlement_id

### Tambah tabel `settlement_mitra`

Field:
- id
- mitra_id
- periode_start
- periode_end
- total_tonase_pabrik
- total_pembayaran_pabrik
- fee_klien
- potongan_armada
- potongan_lain
- total_hak_mitra
- total_dibayar
- sisa_bayar
- status
- created_at

### Tambah tabel `settlement_mitra_detail`

Field:
- id
- settlement_id
- pengiriman_id
- tonase_pabrik
- harga_pabrik_per_kg
- total_pabrik
- fee_klien
- potongan
- hak_mitra

### Tambah tabel `pembayaran_mitra`

Field:
- id
- settlement_id
- mitra_id
- tanggal
- jumlah
- metode
- keterangan
- created_by
- created_at

### Revisi hutang petani

Gunakan ledger tunggal agar tidak double count:
- `hutang_ledger`
- petani_id
- tanggal
- tipe: debit, kredit
- sumber: kasbon, bayar_tunai, potong_tbs, koreksi
- jumlah
- transaksi_beli_id
- keterangan

## 10. Prioritas Revisi

### P0 - Wajib Sebelum Dipakai Serius

- Pisahkan Petani dan Mitra.
- Tambah alur pengiriman mitra.
- Tambah settlement mitra.
- Perbaiki perhitungan hutang agar tidak double count.
- Perbaiki nomor struk agar aman dari bentrok.
- Perbaiki encoding teks/icon.
- Perketat role owner/admin, minimal di level aplikasi.

### P1 - Penting Untuk Operasional Harian

- Laporan per mitra.
- Laporan pabrik.
- Pembayaran pabrik per DO.
- Pembayaran mitra sebagian/lunas.
- Potongan armada klien untuk mitra.
- Export Excel settlement mitra.
- Audit log transaksi penting.

### P2 - Pengembangan Lanjutan

- Rekonsiliasi stok TBS lokal: masuk dari petani vs keluar ke pabrik.
- Upload foto tiket timbang/DO.
- Multi-lokasi timbang.
- Print bukti settlement mitra.
- Dashboard owner dengan margin per sumber.

## 11. Risiko dan Catatan Teknis dari Kode Saat Ini

- Saat ini petani dan mitra belum dipisah; hanya ada tabel `petani`.
- Pengiriman saat ini belum memiliki sumber lokal/mitra.
- Laba-rugi saat ini hanya menghitung pendapatan dari pengiriman dibayar, pembelian TBS, dan biaya operasional.
- Hutang saat ini berisiko double count karena potong hutang disimpan di transaksi dan juga log.
- RLS Supabase saat ini memberi akses penuh ke semua authenticated users.
- Belum ada environment file Supabase di repo.
- Belum ada test otomatis.

saya ingin tambahkan skenario 1 lagi role, super admin( teknisi) yg bisa edit semua, sehingga ada 3 role, super admin, owner, dan admin biasa. super admin bisa melakukan semua, admin biasa hanya bisa kelola data transaksi, owner hanya bisa melihat dan mengelola laporan dan transaksi. tidak bisa edit data transaksi. bagaimana baiknya?

## 12. Daftar Pertanyaan Untuk Klien

Bagian ini bisa langsung dikirim ke klien untuk mengonfirmasi alur kerja sebelum revisi sistem dibuat.

Halo Pak/Bu, saya ingin konfirmasi beberapa hal agar alur sistemnya sesuai dengan cara kerja di lapangan:

1. Untuk TBS dari mitra, apakah perusahaan mengambil bagian/fee dari setiap kilogram yang masuk ke pabrik?
2. Jika ada bagian/fee untuk perusahaan, cara hitungnya bagaimana: dipotong per kg, persentase dari hasil pabrik, atau nominal tetap?
3. Untuk menghitung pembayaran ke mitra, patokannya memakai berat dari timbangan mitra atau berat final dari pabrik?
4. Jika berat dari timbangan mitra berbeda dengan berat yang diterima pabrik, selisihnya ditanggung siapa?
5. Pabrik biasanya membayar ke perusahaan berdasarkan apa: per surat jalan/DO (dokumen pengiriman), per hari, per minggu, atau per bulan?
6. Setelah pabrik membayar ke perusahaan, apakah mitra langsung dibayar penuh atau bisa dibayar sebagian dulu?
7. Apakah perusahaan pernah memberi uang muka/panjar ke mitra sebelum pembayaran dari pabrik masuk?
8. Jika mitra memakai armada perusahaan, apakah biaya armada selalu dipotong dari pembayaran mitra?
9. Kalau biaya armada dipotong, apakah nominalnya tetap, berdasarkan jarak, berdasarkan tonase, atau sesuai biaya aktual di lapangan?
10. Apakah mitra juga bisa punya hutang/kasbon ke perusahaan seperti petani?
11. Untuk pengiriman mitra, data sopir dan kendaraan mitra perlu dicatat lengkap, atau cukup nama sopir/plat kendaraan saja jika ada?
12. Untuk TBS dari petani lokal yang ditimbang di tempat perusahaan, apakah perlu dicatat sebagai stok sementara sebelum dikirim ke pabrik?
13. Apakah pengiriman ke pabrik perlu menggabungkan beberapa transaksi petani lokal, atau cukup dicatat total tonase yang dikirim hari itu?
14. Saat pabrik membayar, apakah ada potongan dari pabrik yang perlu dicatat, misalnya sortasi, penalti, biaya timbang, atau potongan lain?
15. Untuk laporan laba-rugi, apakah ingin dihitung berdasarkan uang yang benar-benar sudah masuk/keluar, atau berdasarkan transaksi walaupun uangnya belum dibayar?
16. Laporan apa yang paling sering dibutuhkan setiap hari: laporan petani, laporan mitra, laporan pabrik, laporan kas, atau semuanya?
17. Untuk bukti pembayaran ke mitra, apakah perlu dibuatkan cetakan/nota yang bisa diberikan ke mitra?
18. Siapa saja yang boleh melihat laporan keuntungan: owner saja atau admin tertentu juga boleh?

## 13. Definisi Sukses v1

Versi v1 dianggap berhasil jika:

- Admin bisa mencatat pembelian TBS dari petani lokal.
- Admin bisa mencatat pengiriman lokal ke pabrik.
- Admin bisa mencatat pengiriman mitra ke pabrik atas nama perusahaan.
- Keuangan bisa mencatat pembayaran pabrik.
- Sistem bisa menghitung hak mitra dan sisa pembayaran mitra.
- Owner bisa melihat laporan yang memisahkan lokal dan mitra.
- Hutang petani akurat.
- Biaya operasional perusahaan tidak tercampur dengan biaya operasional mitra.
- Laba-rugi owner menampilkan margin yang lebih mendekati kondisi bisnis sebenarnya.
