# PRD (Product Requirements Document) - Sistem Operasional Sawit CB (Versi Excel Sementara)

## 1. Ringkasan Produk

Versi Excel ini adalah purwarupa (prototype) dan solusi operasional sementara (fallback) untuk bisnis RAM kelapa sawit Sawit CB. Sistem dirancang menggunakan arsitektur **Dua File (Linked Workbooks)** untuk menyelesaikan masalah keamanan dan hak akses yang sering menjadi kelemahan di ekosistem Excel tunggal.

Dengan memisahkan file untuk Admin dan Owner, sistem ini secara aman dapat: **mencatat pengiriman TBS oleh mitra dan petani ke pabrik, melacak biaya operasional, menghitung hak mitra, melacak panjar (kasbon), dan merekap laporan laba-rugi.**

## 2. Ruang Lingkup (Scope) & Hak Akses

**Arsitektur Split-File menjamin pemisahan hak akses:**
- **Admin Operasional** hanya memiliki akses ke file input harian (Tonase, Sopir, Plat). Admin tidak mengetahui harga, fee, atau margin perusahaan.
- **Owner / Admin Keuangan** memiliki akses ke file utama (Master Harga, Laba-Rugi, dan Buku Kas) yang secara otomatis akan "menyedot" data tonase dari file Admin.

**In-Scope:**
- Pencatatan master data Mitra, Sopir, dan Armada (otomatisasi Dropdown).
- Pencatatan harga TBS harian dari pabrik dan untuk petani lokal.
- Pencatatan log DO masuk ke pabrik dari mitra dan pembelian dari petani lokal.
- Perhitungan otomatis tagihan bruto, potongan fee perusahaan, dan hak bersih mitra per DO.
- Pencatatan buku kas (uang keluar/masuk) untuk panjar mitra, pelunasan mitra, pembayaran petani, dan biaya operasional.
- Dashboard rekapitulasi sisa tagihan hutang/piutang ke mitra.
- Dashboard rekaptulasi Laba-Rugi sederhana.

**Out-of-Scope (Tidak dicakup di versi Excel):**
- Manajemen stok fisik di RAM dan opname susut secara mendetail.
- Audit Log (riwayat siapa yang mengubah data tanggal berapa).

## 3. Struktur Sistem (Arsitektur Dua File)

Sistem terdiri dari dua file Excel terpisah (`.xlsx`) yang diletakkan dalam folder yang sama di komputer.

### 📁 File 1: `1_Operasional_Admin.xlsx`
File ini dipegang oleh Admin Timbang/Lapangan. Admin melakukan input menggunakan bantuan *Shortcut* `Ctrl + ;` untuk tanggal otomatis dan *Dropdown* untuk meminimalisir salah ketik.
- **Sheet 1: Master Armada**
  - Kolom: Nama Sopir, Plat Armada. (Digunakan sebagai sumber *Dropdown*).
- **Sheet 2: Transaksi Mitra**
  - Kolom: Tanggal, Nama Mitra, Nama Sopir (Dropdown), Plat Armada (Terisi otomatis via VLOOKUP), Tonase Masuk Pabrik (kg).
- **Sheet 3: Transaksi Petani Lokal**
  - Kolom: Tanggal, Nama Petani, Tonase Bersih (kg).

### 📁 File 2: `2_Keuangan_Owner.xlsx`
File ini dipegang secara rahasia oleh Owner. File ini membaca seluruh baris data di `File 1` menggunakan rumus koneksi (`=[1_Operasional_Admin.xlsx]Sheet2!A:A`).
- **Sheet 1: Master Harga & Fee**
  - Kolom: Daftar Mitra, Alamat, Fee Mitra (Rp/kg).
  - Kolom: Tanggal, Harga Pabrik (Rp/kg), Harga Beli Petani (Rp/kg).
- **Sheet 2: Rekap Tagihan Mitra (Settlement)**
  - Mengambil data Tonase Mitra dari `File 1`.
  - Mengalikan Tonase dengan Harga Pabrik dan memotong Fee Mitra berdasarkan tanggal transaksi.
- **Sheet 3: Rekap Pembelian Petani**
  - Mengambil data Tonase Petani dari `File 1`.
  - Mengalikan Tonase dengan Harga Beli Petani.
- **Sheet 4: Buku Kas & Operasional**
  - Kolom Input Manual: Tanggal, Pihak Terkait (Nama Mitra/Petani/Vendor), Tipe (Panjar Mitra / Pelunasan Mitra / Bayar Petani / Biaya Solar / dll), Jumlah Keluar (Rp), Keterangan.
- **Sheet 5: Dashboard Laba-Rugi & Piutang**
  - **Sisa Tagihan Mitra**: `Total Hak Mitra (Sheet 2) - Total Uang Diterima Mitra (Sheet 4)`.
  - **Laba-Rugi**: `Total Uang dari Pabrik - Total Hak Mitra - Total Bayar Petani - Total Biaya Operasional`.

## 4. Alur Kerja (User Flow)

1. **Setup Pagi Hari:** Owner membuka `File 2` dan memperbarui *Harga Pabrik* serta *Harga Beli Petani* hari itu di Sheet 1. (File kemudian disave dan boleh ditutup).
2. **Menerima Truk di Lapangan:** Sopir (mitra/petani) datang membawa TBS.
3. **Input Transaksi (Admin):** Admin membuka `File 1`. Menekan `Ctrl + ;` untuk input tanggal dengan cepat, memilih nama sopir dari *Dropdown*, plat mobil terisi otomatis, lalu mengisi tonase masuk pabrik. Admin men-save `File 1`.
4. **Transaksi Uang (Owner/Kasir):** Jika ada yang meminta panjar atau kas operasional, Owner mencatatnya di `File 2` Sheet Buku Kas.
5. **Monitoring (Owner):** Kapan saja Owner membuka `File 2`, sebuah popup *"Update Links"* akan muncul. Owner mengklik *Update*, dan otomatis semua data dari `File 1` (Admin) tersedot masuk. Owner langsung bisa melihat Laba-Rugi dan sisa hutang di Dashboard.

## 5. Acceptance Criteria (Definisi Selesai)
1. Terbuat 2 buah file `.xlsx`.
2. `File 1` tidak memiliki rumus yang berkaitan dengan uang (Rp), hanya tonase.
3. Kolom "Nama Sopir" pada `File 1` berupa validasi *Dropdown*, dan kolom "Plat Armada" terisi otomatis dengan `VLOOKUP`.
4. `File 2` berhasil menarik data secara *real-time* atau *on-open* dari `File 1`.
5. Kolom numerik yang berkaitan dengan uang di `File 2` dikonfigurasi menggunakan format *Accounting/Currency* (Rp) tanpa desimal.

## 6. Risiko Ekosistem Excel & File Berantai
- **Link Putus (Broken Links):** Jika `File 1` diubah namanya (rename) atau dipindah ke folder lain, rumus di `File 2` akan *Error/Ref*. Kedua file harus selalu ada di struktur folder yang sama.
- **Tidak ada Audit Log:** Jika admin mengubah data tonase hari kemarin di `File 1`, data di `File 2` akan ikut berubah tanpa riwayat (history) siapa yang mengubahnya.
- **Batas Kinerja:** Jika transaksi sudah mencapai puluhan ribu baris, fitur *External Reference* di Excel mungkin akan membuat file menjadi sedikit lambat saat pertama kali dibuka (*Updating Links*).
