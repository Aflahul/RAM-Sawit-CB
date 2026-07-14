# Implementation Plan: Unifikasi & Redesign UX Pengiriman Mitra

Berdasarkan realita bisnis bahwa pengguna utama adalah **Admin Back-Office Owner** (meng-input data secara *batch* dari kumpulan kwitansi/nota fisik pabrik), maka penyatuan halaman *Input* dan *Riwayat* menjadi satu antarmuka yang solid adalah **sangat layak dan sangat direkomendasikan**.

Ini akan menciptakan alur **"Data Grid with Quick Add Modal"** yang jauh lebih cepat daripada berpindah-pindah halaman.

## Tujuan Utama (Goal)
Menyatukan `Riwayat & Koreksi Mitra` dengan form `Input Timbangan` ke dalam satu halaman utama bernama **Pengiriman Mitra**. Form input lama akan diubah menjadi sebuah *Modal/Popup* (Dialog) yang ringkas dan cepat, dengan flow UX yang telah diperbaiki.

## User Review Required
> [!IMPORTANT]
> **Perubahan Rute & Sidebar:** Saya akan menghapus menu "Riwayat & Koreksi Mitra" dari sidebar, karena seluruh tabel riwayat dan fitur koreksi (Edit/Batal) akan digabungkan ke halaman "Pengiriman Mitra" (`/admin/input-timbangan` atau memindahkannya ke rute netral `/transaksi/kirim`). Mohon setujui apakah Anda ingin menggunakan rute `/admin/input-timbangan` atau memindahkannya. (Saya akan asumsikan tetap di `/admin/input-timbangan` untuk menjaga link lama, namun isinya dirombak total).

## Proposed Changes

### Komponen Reusable
#### [NEW] `components/ui/Modal.js`
- Membuat komponen Modal universal dengan dukungan *overlay backdrop*, *scrollable body*, dan tombol silang (Tutup). Ini penting karena form pengiriman cukup panjang.

### Komponen Transaksi
#### [NEW] `components/transaksi/FormPengirimanModal.js`
- Memisahkan seluruh form dari `input-timbangan/page.js` ke dalam komponen ini.
- Menerapkan **Solusi UX Audit**:
  - Kolom **Sopir/Armada** ditaruh paling atas dan *bisa diketik duluan*.
  - Kolom **Mitra Transaksi** otomatis terisi (Auto-fill) saat Sopir dipilih, tetapi tetap bisa diganti manual jika perlu.
  - Kolom **Berat Netto**, **Potongan**, dan **Checkbox Armada CB** diletakkan tepat di bawah Mitra.
  - Fitur **Sopir Pengganti** disembunyikan di dalam *accordion* atau diletakkan paling bawah sebagai "Opsi Lanjutan".

### Halaman Aplikasi (Pages)
#### [MODIFY] `app/admin/input-timbangan/page.js`
- Mengganti isinya dengan menampilkan **Tabel Riwayat Pengiriman Mitra** (yang diambil dari kode `riwayat-pengiriman-mitra/page.js`).
- Menambahkan tombol besar **"+ Tambah Pengiriman"** di pojok kanan atas yang akan membuka `FormPengirimanModal`.
- Saat data baru berhasil di-submit dari Modal, tabel riwayat akan langsung me-*refresh* datanya (tanpa perlu reload halaman).

#### [DELETE] `app/owner/riwayat-pengiriman-mitra/page.js`
- Halaman ini akan dihapus/dikosongkan dan dialihkan (redirect) ke `input-timbangan` karena sudah disatukan.

#### [MODIFY] `components/layout/Sidebar.js`
- Menghapus menu "Riwayat & Koreksi Mitra".
- Memastikan menu "Pengiriman Mitra" mudah diakses.

## Verification Plan

### Manual Verification
1. Buka halaman "Pengiriman Mitra". Pastikan langsung melihat tabel riwayat (hari ini).
2. Klik tombol "+ Tambah Pengiriman". Modal form muncul.
3. Uji kecepatan input: Ketik plat nomor -> Mitra otomatis terpilih -> Ketik Berat Netto 3000 -> Simpan.
4. Pastikan modal menutup dan tabel riwayat langsung bertambah 1 baris di paling atas.
5. Uji fitur koreksi (Edit/Batal) di dalam tabel untuk memastikan tidak ada fitur lama yang hilang.
