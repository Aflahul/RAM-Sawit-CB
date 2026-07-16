# Audit Flow Bisnis, Halaman, Tombol, dan Data

Tanggal audit: 16 Juli 2026

## 1. Tujuan dan Kesimpulan

Audit ini memeriksa route Next.js, menu, pembatasan role, query Supabase, RPC, tombol yang mengubah data, snapshot, ledger, serta data remote yang sedang digunakan.

Kesimpulan utama:

- Alur utama sudah terbentuk: **Pengiriman Mitra -> Kwitansi Mitra -> Buku Kas -> Laporan**, serta **Pembayaran Pabrik -> Buku Kas -> Laba/Rugi**.
- RPC pembayaran pabrik, pembayaran mitra, biaya, dan hutang sudah lebih aman karena mencatat ledger secara terpusat.
- Sistem belum layak menambah fitur finansial besar sebelum release gate P0 di bagian 8 selesai.
- Risiko terbesar bukan tata letak, melainkan hak akses terlalu luas, koreksi transaksi yang sudah dibayar, arti tonase kwitansi yang berubah, histori tarif tumpang tindih, dan laporan bruto yang tidak konsisten.

## 2. Standar Role Target

### 2.1 Role aktif untuk tiga pengguna saat ini

Untuk kondisi saat ini, gunakan tiga role yang mudah dipahami pengguna. Pemisahan operasional dan keuangan tetap diterapkan pada izin setiap tombol, tetapi belum perlu memaksa adanya dua akun admin yang berbeda.

| Role | Pekerjaan Utama | Aksi yang Layak Dilakukan |
| --- | --- | --- |
| Admin | Input lapangan dan pencatatan rutin | Tambah pengiriman, tambah master operasional, siapkan/catat pembayaran rutin, cetak kwitansi, dan melihat status kas yang diperlukan |
| Owner | Kontrol dan keputusan bisnis | Melihat seluruh angka, menyetujui koreksi sensitif, mengubah tarif, membatalkan pembayaran, dan melihat profit |
| Super Admin | Administrasi teknis | Kelola akun/role, konfigurasi sistem, dan akses pemulihan; bukan pelaksana transaksi harian |

`admin_keuangan` tetap dipertahankan di model internal sebagai role cadangan. Role ini baru dipakai ketika jumlah staf bertambah dan pekerjaan lapangan benar-benar dipegang orang berbeda dari kasir/keuangan.

### 2.2 Hak Admin menambah sopir dan armada

Admin harus tetap dapat menambah sopir/armada yang belum ditemukan saat input pengiriman agar pekerjaan lapangan tidak berhenti. Hak ini harus diberikan secara eksplisit melalui RLS/RPC, bukan bergantung pada full access semua pengguna login.

Alur target:

1. Dari form Pengiriman Mitra, Admin mencari plat atau sopir.
2. Jika tidak ditemukan, tampilkan aksi **Tambah Sopir/Armada** tanpa meninggalkan transaksi.
3. Admin mengisi data minimum: plat, nama sopir, tipe Armada CB/non-CB, dan Mitra Default bila ada.
4. Data disimpan dengan status **Perlu Verifikasi**, beserta `dibuat_oleh` dan waktu pembuatan, tetapi langsung dapat dipilih untuk pengiriman yang sedang dicatat.
5. Owner kemudian memeriksa afiliasi, duplikasi plat, status Armada CB, dan data tambahan.
6. Admin tidak boleh menghapus permanen master yang sudah dipakai transaksi; koreksi dilakukan dengan nonaktifkan, gabungkan duplikat, atau ganti data default tanpa mengubah snapshot transaksi lama.

Catatan skema: halaman Armada saat ini menyimpan sopir dan plat dalam satu tabel `sopir`. Istilah tombol harus tetap **Tambah Sopir/Armada** sampai master kendaraan dan pengemudi benar-benar dipisah. Sopir aktual/pengganti tetap disimpan sebagai snapshot pada transaksi.

### 2.3 Pemisahan fungsi tanpa menambah akun

Karena satu Admin mengerjakan operasional dan pencatatan keuangan, kontrol pengganti pemisahan pegawai adalah:

- Admin boleh melakukan pencatatan rutin, tetapi tidak boleh mengubah tarif, role, atau pengaturan bisnis.
- Admin tidak boleh mengedit langsung transaksi yang sudah dibayar.
- Pembatalan pembayaran, reversal kas, koreksi kwitansi dibayar, dan penghapusan master harus memerlukan Owner/Super Admin serta alasan wajib.
- Semua aksi uang dan koreksi menyimpan actor, waktu, alasan, dan referensi transaksi.
- Dashboard Owner menampilkan antrian **Perlu Persetujuan/Perlu Cek** agar kontrol tidak bergantung pada pesan lisan.

Temuan role saat ini:

- Sidebar sudah menyembunyikan beberapa menu finansial, tetapi route dan data tidak selalu mengikuti pembatasan yang sama.
- Aplikasi masih mendefinisikan empat role internal: `owner`, `super_admin`, `admin_operasional`, dan `admin_keuangan`. Untuk tiga pengguna sekarang, label `admin_operasional` dapat ditampilkan sebagai **Admin**, sedangkan `admin_keuangan` disimpan untuk ekspansi.
- Admin saat ini dapat menambah sopir/armada dari halaman master, tetapi kontrol ini belum dilindungi matriks RLS yang cukup ketat.
- `master_mitra` dan `transaksi_mitra` memiliki policy **full access untuk semua authenticated**, termasuk hak `DELETE` pada grant tabel.
- `hutang_ledger`, biaya, header pembayaran, dan item pembayaran dapat dibaca semua authenticated. Ini perlu keputusan owner: apakah Admin Operasional boleh melihat nominal keuangan atau hanya status ringkas.
- Tombol ubah Harga Pabrik tampil untuk semua role di Dashboard, sedangkan policy write tidak sama untuk semua role.

## 3. Audit Alur Bisnis Utama

### 3.1 Pengiriman sampai Pembayaran Mitra

Alur target:

1. Admin memilih tanggal, armada/sopir, dan Mitra Transaksi.
2. Admin memasukkan Berat Netto dan Potongan Pabrik.
3. Sistem membekukan Berat Dibayar, Harga Pabrik, Fee Owner, sewa Armada CB, dan Dana Operasional Trip.
4. Transaksi belum dibayar masuk antrian Kwitansi.
5. Admin Keuangan/Owner memeriksa rincian dan menandai kwitansi dibayar.
6. RPC membuat snapshot item, kas keluar, serta pelunasan panjar dalam satu transaksi database.
7. Koreksi setelah pembayaran harus melalui pembatalan/reversal, bukan edit transaksi langsung.

Status audit: langkah 1-6 tersedia. Langkah 7 belum tersedia dan saat ini masih dapat dilewati melalui tombol Edit/Batalkan di Pengiriman Mitra.

### 3.2 Pembayaran Pabrik

Alur target:

1. Admin Keuangan memilih periode tanggal timbang.
2. Admin memasukkan nota pabrik: pabrik, tanggal uang masuk, rekening, tonase, harga, uang diterima, dan bukti.
3. Data timbang dipilih untuk pencocokan, bukan untuk menentukan siapa mitra di sisi pabrik.
4. RPC mencatat pembayaran, kas masuk, dan hubungan ke transaksi yang dipilih.
5. Pembatalan membuat reversal kas dan membuka kembali transaksi untuk pencocokan.

Status audit: alur dasar sudah benar. Harga pembanding masih selalu memakai TWB terbaru Dashboard, sehingga pembayaran periode lampau dapat dibandingkan dengan harga yang salah.

### 3.3 Dana Operasional Trip Armada CB

1. Pengiriman dengan Armada CB membuat tagihan Dana Operasional Trip berdasarkan Mitra Transaksi.
2. Kas belum berkurang saat pengiriman disimpan.
3. Admin Keuangan menekan **Bayar Dana Trip**.
4. RPC membuat biaya, kas keluar, dan pelunasan tagihan.

Status audit: alur tersedia. Setelah Dana Trip dibayar, perubahan tanggal, armada, sopir, atau pembatalan pengiriman belum memiliki flow koreksi khusus.

## 4. Audit Setiap Halaman Aktif

### 4.1 Login - `/login`

- Data: email dan password.
- **Tampilkan/Sembunyikan Password**: lokal, tidak mengubah database.
- **Masuk ke Sistem**: Supabase Auth lalu redirect Dashboard.
- Status: layak.
- P2: ganti emoji dekoratif dengan icon Lucide dan buat pesan akun/sesi lebih spesifik.

### 4.2 Dashboard - `/dashboard`

- Data: Harga Pabrik/TWB, tonase mitra hari ini, estimasi pendapatan owner, kwitansi pending, fokus mitra 7 hari, konteks lokal, kas, biaya, hutang/panjar, dan pending review.
- **Set/Ubah Harga**: upsert `harga_tbs` tanggal hari ini.
- **Input Pengiriman**, **Laporan Mitra**, **Kwitansi**, dan aksi cepat: navigasi.
- Tombol mitra pada **Fokus Mitra**: mengganti grafik lokal.
- P0: tombol harga tidak mengikuti role; pending review hanya menghitung header `perlu_review`, bukan selisih snapshot atau transaksi dibatalkan setelah dibayar.
- P1: hitungan antrian memakai limit 1.500 transaksi dan 3.000 item; akan kurang saat data melewati batas.
- P1: link dari Fokus Mitra tidak membawa filter mitra ke halaman tujuan.
- P1: kartu Hutang/Panjar dan Biaya dapat menampilkan nominal ke Admin Operasional karena read policy luas.

### 4.3 Pengiriman Mitra - `/admin/input-timbangan`

- Data: tanggal/waktu, mitra, sopir/plat, status transaksi, status bayar, Berat Netto, Potongan, Berat Dibayar, harga, dan nilai bersih.
- **Buka Kwitansi Mitra**: navigasi ke kwitansi.
- **Muat Ulang**: mengambil ulang data.
- **Tambah Pengiriman**: membuka Quick Add Modal.
- **Tambah Armada Cepat**: menambah sopir/plat dari modal pengiriman.
- **Edit**: mengubah transaksi dan menulis audit log.
- **Batalkan**: mengubah status transaksi dan menulis audit log.
- **Periksa Kwitansi**: membuka mitra/periode terkait jika status perlu cek.
- Baik: validasi berat, potongan, mitra, tarif sewa, Dana Trip, dan sopir aktual tersedia.
- P0: Edit/Batalkan masih direct update dan tetap aktif untuk transaksi yang sudah masuk kwitansi.
- P0: pembatalan transaksi dibayar tidak membalik pembayaran mitra, kas, dan panjar.
- P0: audit log dipanggil terpisah setelah update; jika audit gagal, perubahan utama tetap tersimpan.
- P1: quick-add armada tidak menolak plat yang sama setelah normalisasi spasi/tanda baca.
- Data: remote memiliki 3 kelompok plat aktif duplikat, 1 armada aktif tanpa plat, dan 6 transaksi aktif lama tanpa `sopir_id`.

### 4.4 Kwitansi & Pembayaran Mitra - `/owner/kwitansi-mitra`

- Data: transaksi belum dibayar, snapshot dibayar, rincian per mitra, panjar, sewa Armada CB, total pembayaran, status, dan riwayat periode.
- **Tambah/Hapus/Bersihkan Mitra**: mengubah pilihan lokal.
- **Tandai Dibayar**: RPC atomik membuat header/item kwitansi, kas keluar, dan potongan panjar.
- **Cetak PDF/Struk**: browser print.
- **Kirim WhatsApp**: membuka preview dan `wa.me`; PDF dilampirkan manual.
- Baik: transaksi baru setelah pembayaran lama tidak ikut kembali; multi-mitra sudah dipisah per grup.
- P0: sebelum dibayar, `Total Tonase` memakai Berat Dibayar; setelah dibayar, layar memakai `payment.total_tonase` yang menyimpan Berat Netto. Remote memiliki 8 kwitansi terdampak.
- P0: kwitansi belum dibayar dapat dicetak dan dikirim WhatsApp tanpa watermark **DRAFT/BELUM DIBAYAR**.
- P0: belum ada tombol pembatalan/reversal pembayaran mitra.
- P0: ringkasan modal per mitra mengurangi panjar tetapi belum mengurangi sewa Armada CB, sedangkan total akhir mengurangi keduanya.
- P1: caption WhatsApp tidak menjelaskan potongan sewa Armada CB.
- P1: rekening kas pembayaran tidak dapat dipilih; saat ini remote baru memiliki satu rekening aktif.

### 4.5 Pembayaran Pabrik - `/owner/pembayaran-pabrik`

- Data: periode timbang, transaksi belum dicocokkan, tonase sistem/pabrik, nilai TWB, beda tonase, uang diterima, dan riwayat pembayaran.
- **Hari Ini/Kemarin/7 Hari**: mengganti periode dan membersihkan pilihan.
- **Pakai Tonase Catatan Kita**: menyalin total pilihan ke form.
- **Hitung Otomatis**: tonase pabrik dikali Harga TWB Dashboard.
- **Pilih Semua/Kosongkan**: mengatur transaksi pencocokan.
- **Catat Pembayaran Pabrik**: RPC membuat pembayaran dan kas masuk.
- **Batal**: RPC reversal kas dan membuka data timbang.
- Baik: tanggal uang masuk dipisahkan dari periode timbang dan pembayaran boleh dicatat sebelum pencocokan.
- P0: data periode lampau tetap dihitung memakai Harga TWB paling baru, bukan harga pada nota/periode pembayaran.
- P1: Nomor Bukti masih opsional.
- P1: pencarian tidak membersihkan pilihan tersembunyi; perlu indikator daftar pilihan aktif.

### 4.6 Buku Kas - `/keuangan/kas`

- Data: rekening, tanggal, sumber, keterangan, masuk, keluar, dan net periode.
- Filter rekening/tanggal: hanya tampilan.
- **Kas Masuk Manual/Kas Keluar Manual**: RPC `create_kas_mutasi`.
- P0: mutasi manual tidak memiliki tombol pembatalan/reversal.
- P0: nomor bukti/referensi dan alasan belum wajib.
- P1: **Net Periode** bukan saldo rekening; belum ada saldo awal dan saldo akhir.
- P2: belum ada export dan drill-down sumber.

### 4.7 Hutang & Panjar Semua Pihak - `/keuangan/hutang`

- Data: pihak, kontak, sisa kewajiban, batas, dan ledger debit/kredit.
- **Catat Hutang & Panjar/Tambah**: membuat debit; panjar mitra memakai RPC khusus.
- **Bayar**: membuat kredit/pelunasan dan mutasi kas.
- **Batalkan**: RPC reversal ledger/kas.
- **Tetap Simpan**: override batas setelah konfirmasi.
- **Export Excel**: export saldo pihak.
- Baik: satu pintu lintas petani, mitra, sopir, karyawan, dan pihak lain sudah sesuai arah bisnis.
- P1: tanggal selalu hari ini dan read-only.
- P1: rekening kas tidak dapat dipilih.
- P1: istilah Debit/Kredit perlu diterjemahkan menjadi **Uang Diberikan** dan **Uang Dikembalikan/Dipotong**.
- P0 security: data ledger dapat dibaca semua authenticated walaupun menu hanya tampil untuk role keuangan.

### 4.8 Biaya Operasional - `/keuangan/biaya`

- Data: tanggal, kategori, armada terkait, keterangan, dan jumlah.
- **Tambah Biaya**: RPC biaya + kas.
- **Batalkan**: RPC reversal biaya + kas.
- Filter kategori/tanggal dan **Export**: tampilan/output.
- Baik: biaya umum dan biaya per Armada CB sudah dipisahkan.
- P1: rekening kas dan bukti biaya tidak tersedia.
- P1: query dibatasi 100 baris tanpa pagination/pemberitahuan.
- P2: kategori memakai emoji teks; konsistensi lebih baik memakai icon.

### 4.9 Mitra - `/owner/master-data`

- Data: kode/nama/lokasi, tipe, penanggung jawab, WA, Fee Owner, tarif sewa, dan Dana Operasional Trip.
- **Tambah/Edit**: mengubah `master_mitra`, lalu upsert histori tarif.
- **Nonaktifkan**: soft-disable.
- **Export Excel**, cari, sort, pagination: aman.
- P0: update master dan histori tarif dilakukan dalam dua request, tidak atomik.
- P0: remote memiliki 19 pasangan periode histori overlap pada 13 mitra.
- P0 security: policy memberi semua authenticated full write/delete.
- P1: kode belum dinormalisasi/unique case-insensitive di database.

### 4.10 Armada - `/master/armada`

- Data: nama sopir/unit, plat, HP, mitra default, status Armada CB, dan aturan Dana Trip.
- **Tambah/Edit/Nonaktifkan**, cari, sort, pagination, export: master operasional.
- **Atur Tarif Mitra/Lihat Laporan Armada**: navigasi.
- P0: tidak ada unique constraint plat ternormalisasi; remote memiliki 3 kelompok duplikat aktif.
- P1: saat Armada CB dicentang, Mitra Default sebaiknya dikosongkan atau dijelaskan tidak menentukan Mitra Transaksi.
- P1: perubahan master tidak boleh mengubah snapshot transaksi lama.

### 4.11 Pabrik Tujuan - `/master/pabrik`

- Data: nama, alamat, dan HP.
- **Tambah/Edit/Nonaktifkan**: master pabrik.
- Status: layak untuk Pembayaran Pabrik.
- P1: belum ada kode unik pabrik, identitas pembayaran, dan validasi duplikat nama.

### 4.12 Harga TBS Lokal - `/master/harga`

- Data: harga aktif dan riwayat waktu berlaku.
- **Simpan Harga Baru**: RPC menutup harga lama dan membuat history baru.
- Status: backend baik, tetapi pembelian lokal masih Coming Soon.
- P1: menu perlu status pengembangan yang sama agar tidak dianggap workflow penuh sudah aktif.

### 4.13 Laporan Mitra - `/owner/laporan-mitra`

- Data: tanggal/waktu, mitra/sopir/plat, status bayar, netto/dibayar, hasil pabrik, dan nilai bersih sebelum panjar/sewa.
- Filter periode/mitra/status, mode gabung/kelompok, sort, pagination: aman.
- **Buka Kwitansi**, **Export Excel**, **Cetak**: navigasi/output.
- Baik: status pembayaran membaca `berat_dibayar_snapshot`.
- P1: nama **Nilai Bersih** belum menjelaskan bahwa angka masih sebelum potongan panjar dan sewa.
- P1: tidak ada link per baris ke kwitansi/pengiriman terkait.
- P1: satu transaksi remote yang sudah dibayar lalu dibatalkan masih ada di snapshot kwitansi; perlu status koreksi eksplisit.

### 4.14 Laporan Armada CB - `/owner/laporan-armada-cb`

- Data: trip, muatan netto, sewa masuk, Dana Trip, belum dibayar, biaya lain, dan margin sesuai role.
- **Lihat Detail/Tampilkan Rincian**: membuka rincian trip.
- **Bayar Dana Trip**: RPC biaya + kas + pelunasan tagihan.
- **Terapkan Tarif Mitra**: backfill hanya trip belum dibayar.
- **Export**: output laporan.
- Baik: formula sesuai keputusan owner.
- P0: pembatalan/perpindahan armada atau sopir setelah Dana Trip dibayar belum memiliki reversal.
- P1: pembayaran selalu memakai rekening default.

### 4.15 Pendapatan Owner Bruto - `/owner/pendapatan-owner`

- Data: Fee Owner, sewa Armada CB, bruto, netto/dibayar, hasil pabrik, nilai bersih mitra, dan rincian transaksi.
- **Sinkronkan Fee Periode Ini**: memperbarui snapshot fee transaksi dalam filter.
- **Cetak**, filter, sort, pagination: output/tampilan.
- P0: kartu atas mendefinisikan bruto = Fee Owner + Sewa, tetapi kolom **Bruto** per mitra hanya menampilkan Fee Owner.
- P1: sort Tonase memakai `row.tonase`, sedangkan ringkasan menyimpan `beratNetto`.
- P0: sinkronisasi fee transaksi yang sudah masuk kwitansi harus dikunci atau diarahkan ke review/reversal.
- P1: label Nilai Bersih Mitra harus menyebut **sebelum panjar/sewa**.

### 4.16 Laba/Rugi - `/laporan/laba-rugi`

- Data: pembayaran pabrik diterima, pembayaran petani/mitra, biaya per kategori, dan selisih kas.
- Filter bulan/tahun dan **Export Excel**: output.
- Status: angka saat ini adalah **Surplus/Defisit Kas**, bukan laba akuntansi penuh.
- P0 terminologi: menu/kartu menyebut Laba Bersih Kas walau pembayaran dan transaksi dapat beda periode.
- Rekomendasi: ganti layar menjadi **Ringkasan Arus Kas**; bangun Laba/Rugi terpisah berbasis hak pendapatan dan biaya periode.
- P1: tahun masih hard-coded 2024-2027.

### 4.17 Pengaturan Web - `/owner/pengaturan-web`

- Data: nama/subjudul, logo web/cetak, dan mode logo.
- **Upload/Hapus Logo**: Storage dan state form.
- **Simpan Pengaturan**: menyimpan branding.
- Baik: role guard dan validasi file tersedia.
- P2: upload tanpa menyimpan form dapat meninggalkan file Storage tidak terpakai.

## 5. Halaman Tersembunyi, Legacy, dan Coming Soon

| Route | Status | Keputusan Audit |
| --- | --- | --- |
| `/owner/panjar-mitra` | Tersembunyi | Jadikan arsip read-only atau redirect ke Hutang & Panjar; tombol Lunasi/Batalkan menduplikasi satu pintu. |
| `/laporan/harian` | Tersembunyi | Tetap di roadmap Tutup Hari, tetapi route sekarang sebaiknya Coming Soon/redirect. |
| `/transaksi/kirim` | Legacy | Sudah read-only dan mengarah ke Pengiriman Mitra internal; pertahankan sementara untuk arsip. |
| `/transaksi/beli` | Coming Soon | Overlay menonaktifkan aksi. |
| `/master/petani` | Coming Soon | Overlay menonaktifkan aksi; judul lama `Petani / Mitra` perlu dibersihkan. |
| `/laporan/petani` | Coming Soon | Overlay menonaktifkan aksi. |
| `/laporan/stok` | Coming Soon | Overlay menonaktifkan aksi. |

## 6. Audit Kontrol Umum dan Security

- Search, filter, sort, tab, pagination, serta buka/tutup modal tidak mengubah database.
- Tidak ditemukan `window.alert`, `window.confirm`, atau `window.prompt` pada kode aktif.
- `proxy.js` hanya me-refresh user Supabase dan belum menolak route berdasarkan role.
- Tidak ada tabel public tanpa RLS, tetapi kualitas policy belum merata.
- `write_audit_log` adalah `SECURITY DEFINER`, dapat dieksekusi `anon`, dan tidak memeriksa `auth.uid()`/role. Audit palsu/spam masih mungkin.
- Supabase DB lint tidak memiliki error; ada satu warning variabel `v_reversal` tidak dipakai pada `cancel_biaya_operasional_kas`.

## 7. Audit Data Remote

| Pemeriksaan | Hasil | Makna |
| --- | ---: | --- |
| Transaksi mitra aktif | 93 | Data live utama |
| Transaksi mitra dibatalkan | 29 | Riwayat koreksi tersedia |
| Item kwitansi aktif | 31 | Snapshot pembayaran tersedia |
| Transaksi dibatalkan masih di kwitansi aktif | 1 | Perlu reversal/revisi |
| Transaksi `updated_at` setelah pembayaran | 18 | Perlu klasifikasi perubahan; snapshot uang cocok saat audit |
| Kwitansi tanpa kas | 0 | Integrasi kas sehat |
| Pembayaran pabrik tanpa kas | 0 | Integrasi kas sehat |
| Nominal kwitansi berbeda dari kas | 0 | Nilai kas cocok |
| Nominal pembayaran pabrik berbeda dari kas | 0 | Nilai kas cocok |
| Kwitansi terdampak beda definisi Netto/Dibayar | 8 | UI total tonase harus dipisah |
| Pasangan histori tarif overlap | 19 pada 13 mitra | History perlu dinormalisasi |
| Kelompok plat aktif duplikat | 3 | Pencarian armada ambigu |
| Armada aktif tanpa plat | 1 | Master belum lengkap |
| Transaksi aktif tanpa relasi sopir | 6 | Data legacy perlu mapping |
| Berat transaksi tidak sinkron | 0 | Formula berat konsisten |
| Sewa total dan sewa kotor berbeda | 0 | Formula sewa konsisten |
| Biaya aktif tanpa kas | 0 | Integrasi biaya-kas sehat |
| Panjar aktif tanpa ledger | 0 | Integrasi panjar-ledger sehat |

## 8. Prioritas Perbaikan

### P0-A - Security dan Audit Trail

1. Ganti policy full access `master_mitra` dan `transaksi_mitra` dengan policy berbasis role.
2. Cabut `DELETE` dan `TRUNCATE` authenticated pada seluruh tabel bisnis/finansial.
3. Cabut execute `anon` dari `write_audit_log`; tambahkan pemeriksaan actor atau jadikan fungsi internal RPC.
4. Samakan sidebar, route guard, RLS, dan visibilitas tombol.

### P0-B - Koreksi Finansial Setelah Dibayar

1. Kunci Edit/Batalkan biasa jika transaksi masuk kwitansi atau Dana Trip sudah dibayar.
2. Buat RPC pembatalan pembayaran mitra: reversal kas, buka panjar, status batal, alasan, actor, dan audit atomik.
3. Buat flow koreksi transaksi dan penerbitan kwitansi pengganti.
4. Simpan alasan review terstruktur dan hitung pending review di database.

### P0-C - Ketepatan Angka

1. Pisahkan **Total Berat Netto** dan **Total Berat Dibayar** pada draft, snapshot, cetak, dan WhatsApp.
2. Perbaiki ringkasan per mitra agar mengurangi panjar dan sewa.
3. Bedakan Harga TWB terbaru dengan Harga Nota Pabrik historis.
4. Samakan Bruto per mitra dengan Fee Owner + Sewa Armada CB.
5. Jadikan update master tarif + history satu RPC atomik dan cegah overlap.

### P0-D - Koreksi Kas Manual

1. Tambahkan reversal Kas Masuk/Keluar Manual.
2. Wajibkan alasan, nomor referensi, dan actor.
3. Jangan edit/hapus ledger lama; buat baris pembalik.

### P1 - UX Workflow

1. Tambahkan watermark DRAFT dan blok WhatsApp resmi sebelum pembayaran.
2. Bawa filter mitra/periode saat navigasi antarhalaman.
3. Izinkan tanggal kejadian dan rekening kas pada Hutang/Panjar, Biaya, Dana Trip, dan pembayaran mitra.
4. Terjemahkan istilah debit/kredit tanpa mengubah tipe ledger.
5. Tambah normalized unique untuk kode mitra dan plat; sediakan proses merge/nonaktif duplikat.
6. Ganti Laba/Rugi basis kas menjadi Ringkasan Arus Kas dan rancang laba periode terpisah.

### P2 - Penyempurnaan

1. Cleanup file branding tidak terpakai.
2. Ganti emoji kontrol dengan icon konsisten.
3. Tambah export/drill-down Buku Kas dan pagination Biaya.
4. Hapus/redirect route arsip setelah migrasi selesai.

## 9. Release Gate

- Tidak ada role yang dapat delete/truncate tabel transaksi atau ledger.
- Tidak ada RPC `SECURITY DEFINER` sensitif yang dapat dipanggil anon tanpa pemeriksaan actor.
- Transaksi dibayar tidak dapat diedit/dibatalkan lewat flow biasa.
- Reversal pembayaran mitra dan kas manual lulus uji idempotensi.
- Draft dan snapshot kwitansi menampilkan Netto/Dibayar konsisten.
- Harga pencocokan pabrik mengikuti bukti/periode yang benar.
- Histori tarif tidak overlap.
- Dashboard pending sama dengan daftar kasus yang perlu tindakan.
- Lint, build, DB lint, role test, dan rekonsiliasi kas lulus.

## 10. Tindak Lanjut Implementasi - 16 Juli 2026

Status setelah audit:

- P0-A selesai: matriks tiga role, route guard, RLS/RPC terkontrol, audit actor, dan larangan direct write/delete sudah diterapkan.
- P0-B selesai pada sisi sistem: transaksi dibayar dikunci; reversal kwitansi, kas manual, dan Dana Trip tersedia serta diuji rollback/idempotensi.
- P0-C selesai: Netto/Dibayar dipisah, 8 header lama dibetulkan, Pendapatan Owner disamakan, harga historis dipertahankan, dan overlap fee menjadi `0`.
- P0-D selesai: mutasi manual dapat dibalik Owner, bukti/keterangan diwajibkan sesuai alur, dan Buku Kas menampilkan saldo pembuka serta akhir.
- P1 utama selesai: Laba/Rugi basis kas diganti menjadi Ringkasan Arus Kas, Panjar lama dan Laporan Harian diarahkan ke satu pintu yang benar, serta pagination ditambahkan pada Kas/Biaya.
- P0 kontrol Armada CB selesai: fakta trip, potongan sewa, dan Dana Operasional Trip dipisahkan; pengecualian wajib beralasan dan kasus lama masuk antrean review tanpa membuat uang baru.

Verifikasi:

- `npm run lint`: lulus.
- `npm run build`: lulus, 28 route.
- `supabase/tests/p0_financial_controls_rollback.sql`: lulus dan seluruh data uji ter-rollback.
- Uji akun Admin nyata: akses operasional berhasil; direct write, reversal Owner, dan RPC anonim ditolak.
- Rekonsiliasi remote: mismatch kwitansi `0`, overlap fee `0`, dan data quick-add uji tersisa `0`.
- Rekonsiliasi Armada CB remote: 11 trip aktif; 2 dengan sewa/Dana dan 9 data lama ditandai perlu review tanpa backfill nominal.
- Smoke test kontrol Armada CB sudah disiapkan di `supabase/tests/armada_cb_controls_rollback.sql`; eksekusi CLI dari mesin ini tertunda karena Docker Desktop tidak tersedia.

Tindak lanjut manusia/data legacy:

- Kwitansi `3570425f-5f54-447b-ae4f-10e23ed977b0` tetap `perlu_review` karena memuat transaksi lama yang dibatalkan dengan alasan **Dobel**. Owner harus memutuskan pembatalan pembayaran dan penerbitan ulang.
- Tujuh master Sopir/Armada ambigu berada dalam antrean `perlu_verifikasi`. Data lama tidak digabung atau dihapus otomatis agar transaksi historis tetap dapat ditelusuri.
