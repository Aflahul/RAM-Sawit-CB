# Audit UX: Halaman Input Pengiriman Mitra

Berdasarkan konteks operasional di mana **Admin Owner bekerja di back-office** (menginput data secara *batch* atau berkala berdasarkan tumpukan nota/kwitansi fisik dari pabrik yang dibawa oleh sopir), berikut adalah hasil audit ulang terhadap kepraktisan UX:

## 🚨 Titik Hambatan (Bottlenecks) Utama

### 1. Pemilihan Armada Terkunci oleh Mitra (Friction Point)
- **Kondisi Saat Ini:** Kolom **"Sopir / Armada"** dalam keadaan *disabled* (tidak bisa diklik) sampai Admin memilih **"Mitra Transaksi"** terlebih dahulu.
- **Realita Bisnis Back-Office:** Pada nota pabrik, informasi yang paling menonjol biasanya adalah **Nomor Polisi (Plat Truk) atau Nama Supir**, dan angka timbangan. Admin yang membaca nota akan mencari plat truk terlebih dahulu.
- **Dampak:** Memaksa Admin untuk mengingat/mencocokkan truk ini milik "Mitra" siapa sebelum bisa menginput plat nomor. Ini menambah beban kognitif dan memperlambat *data entry*.

### 2. Tata Letak (Flow) Input yang Kurang Efisien
- **Kondisi Saat Ini:** Urutan form adalah: 
  `Mitra` ➔ `Panel Info (Makan tempat)` ➔ `Sopir/Truk` ➔ `Sopir Aktual Mode` ➔ `Berat Netto` ➔ `Potongan`.
- **Dampak:** 
  - Kolom **Sopir Aktual** (yang merupakan kasus khusus jika sopir diganti) menghalangi jalan Admin untuk segera mengetik **Berat Netto** (yang merupakan tugas utama 100% transaksi).
  - Admin harus melakukan *scroll* ke bawah atau menekan tombol `Tab` berulang kali melewati opsi sopir aktual hanya untuk memasukkan angka timbangan.

### 3. Masalah Reset Tanggal pada Input Massal (Batch Entry)
- **Kondisi Saat Ini:** Tidak jelas apakah tanggal otomatis tetap tersimpan setelah "Simpan Transaksi" jika Admin sedang menginput tumpukan nota hari kemarin.
- **Dampak:** Risiko kesalahan input tanggal sangat tinggi jika form selalu me-reset tanggal ke hari ini setelah setiap tombol Simpan ditekan, padahal Admin sedang memasukkan 10 nota dari tanggal 14.

---

## 💡 Rekomendasi Perbaikan (Action Plan) untuk Back-Office

Untuk menciptakan pengalaman **"High-Speed Data Entry"**, berikut rekomendasinya:

### ✅ Rekomendasi 1: Form Bebas Urutan (Armada -> Auto-fill Mitra)
- Bebaskan kolom **"Sopir / Armada"**.
- Jika Admin mengetik "BK 1234", sistem otomatis mengisi kolom **Mitra Transaksi** sesuai afiliasi truk tersebut. Admin hanya tinggal menekan "Tab" ke kolom berikutnya.

### ✅ Rekomendasi 2: Redesign Menjadi Pop-up Modal (Unified Page)
- **Penyatuan Halaman:** Gabungkan form input dengan halaman "Riwayat Pengiriman Mitra". Form input tidak lagi memakan satu halaman penuh, melainkan berupa **Modal / Dialog** yang ringkas.
- **Manfaat Back-Office:** Admin bisa langsung melihat tabel daftar kwitansi yang sudah diinput (untuk mencegah input ganda/double entry) sambil menekan tombol "+ Tambah" untuk membuka form baru.

### ✅ Rekomendasi 3: Tata Letak Form Berorientasi Keyboard (Tab-Friendly)
- Susun input berurutan ke bawah secara logis: 
  `Tanggal` ➔ `Sopir/Plat` ➔ `Mitra (Otomatis terisi)` ➔ `Berat Netto` ➔ `Potongan` ➔ `Simpan`.
- Sembunyikan pengaturan kompleks seperti "Sopir Pengganti Manual" di dalam tombol opsi tambahan agar tombol `Tab` di *keyboard* langsung melompat dari Berat ke tombol Simpan.
- Pertahankan input "Tanggal" dari transaksi sebelumnya setelah *submit* sukses, sehingga Admin yang menginput tumpukan nota kemarin tidak perlu mengubah tanggal berulang kali.

---

**Pertanyaan untuk Anda:**
Apakah Anda setuju dengan hasil audit ini? Jika iya, saya bisa langsung merombak UI `input-timbangan/page.js` agar alurnya secepat kilat sesuai Rekomendasi 1 dan 2.
