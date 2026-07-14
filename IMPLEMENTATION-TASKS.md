# Implementation Tasks - Sawit CB

Dokumen ini menurunkan `PRD-final.md` menjadi task implementasi teknis berdasarkan kondisi repo saat ini.

## Aturan Pencatatan Implementasi

Setiap perubahan yang sudah diimplementasikan wajib tercatat di dokumen ini agar status MVP, migration, UI, dan backlog tidak tercecer.

Ketentuan:

- Setelah membuat migration, catat nama file migration, status apply remote/local, dan dampak schema.
- Setelah mengubah UI, catat route/halaman yang berubah dan acceptance yang sudah terpenuhi.
- Setelah menambah fitur MVP live, tambahkan checklist `[x]` pada bagian terkait.
- Setelah menambah rencana di `PRD-final.md`, tambahkan agenda implementasi di dokumen ini dengan status jelas: `[x]` untuk analisis/dokumen yang sudah selesai, `[ ]` untuk fitur yang belum dibuat.
- Jangan menandai fitur sebagai selesai jika baru berupa analisis atau rencana.

## 0. Kondisi Saat Ini (MVP Tahap 1 Selesai)

Semua fitur MVP (Tahap 1) terkait **Pengiriman Mitra ke Pabrik** telah selesai dibangun. 
Modul yang sudah live dan beroperasi:
- **Master Data MVP:** `master_mitra`, `sopir` (dengan afiliasi mitra).
- **Pengiriman Mitra:** Menggunakan `transaksi_mitra` dengan pemotongan Fee/DO tersembunyi (Skenario B) dengan `harga_tbs` (Harga Pabrik/TWB).
- **Panjar Mitra:** Menggunakan `panjar_mitra` dengan tombol *Quick Add*.
- **Kwitansi Mitra:** Pemotongan panjar otomatis.
- **Laporan Mitra:** Rekapitulasi global transaksi Mitra.

### Kondisi Baru - Pergantian Sopir Armada (13 Juli 2026)

Di lapangan, sopir yang membawa mobil/armada kadang diganti. Dampaknya:

- Relasi sopir ke armada di master tidak boleh dianggap permanen.
- Master sopir-armada hanya boleh menjadi default/auto-fill.
- Default mitra pada sopir/armada hanya usulan awal; mitra transaksi tetap harus bisa dipilih/diubah saat input.
- Armada bersama atau pool seperti `SL/BL` boleh tidak punya default mitra agar tidak terkunci ke kode yang salah.
- Setiap pengiriman/DO harus menyimpan sopir aktual dan snapshot nama sopir/plat pada saat transaksi.
- Jika default sopir armada berubah setelah DO dibuat, histori DO lama tidak boleh ikut berubah.
- Form input harus mengizinkan override sopir aktual, termasuk sopir manual jika belum ada di master.

Status implementasi MVP live:

- [x] Migration non-destruktif `202607130001_mvp_sopir_aktual_transaksi_mitra.sql`.
- [x] `/admin/input-timbangan` mendukung sopir aktual default, pilih dari master, atau manual.
- [x] `/admin/input-timbangan` mendukung override `Mitra Transaksi` terpisah dari default sopir/armada.
- [x] `transaksi_mitra` menyimpan snapshot sopir default dan sopir aktual.
- [x] Laporan mitra dan kwitansi menampilkan sopir aktual serta tanda pengganti.
- [x] Migration schema `202607130001_mvp_sopir_aktual_transaksi_mitra.sql` sudah dijalankan di Supabase remote/production.
- [x] Seed SQL daftar sopir/plat dibuat: `202607130002_mvp_seed_sopir_armada_default.sql`.
- [x] Seed SQL sopir/plat `202607130002_mvp_seed_sopir_armada_default.sql` sudah dijalankan ke Supabase remote via CLI.
- [x] Supabase migration history sudah sinkron sampai `202607130002`.
- [x] `/owner/kwitansi-mitra` dan `/owner/laporan-mitra` memakai snapshot `sopir_aktual_nama` agar tidak gagal karena relasi `sopir` ambigu.
- [x] Halaman `/owner/riwayat-pengiriman-mitra` dibuat untuk melihat detail transaksi, edit kesalahan input, dan membatalkan transaksi tanpa delete fisik.
- [x] `transaksi_mitra` ditambah status `aktif/dibatalkan`, alasan edit, alasan batal, dan metadata update lewat migration `20260713053518_mvp_riwayat_pengiriman_mitra_status.sql`.
- [x] Laporan dan kwitansi mitra mengecualikan transaksi `dibatalkan`.
- [x] `/owner/laporan-mitra` mendukung filter multi-mitra, mode gabung beberapa mitra, dan mode kelompok per mitra.
- [x] `/owner/master-data` dan `/owner/laporan-mitra` mendukung export Excel `.xlsx` rapi dengan header berwarna dan row ganjil/genap beda warna.
- [x] Dashboard MVP mengecualikan transaksi mitra `dibatalkan` dari total pengiriman pabrik dan jumlah mitra mengirim hari ini.
- [x] Rincian transaksi memakai label **Waktu** dari `transaksi_mitra.created_at`, bukan label "Waktu Input".
- [x] `/owner/riwayat-pengiriman-mitra`, `/owner/laporan-mitra`, `/owner/kwitansi-mitra`, dan `/owner/pendapatan-owner` menampilkan Waktu transaksi serta bisa mengurutkan berdasarkan Waktu pada halaman yang memakai tabel sortable.
- [x] Sorting kolom **Waktu** memakai timestamp penuh `created_at` sampai detik/milidetik; UI tetap menampilkan jam dan menit saja.
- [x] Halaman `/owner/pendapatan-owner` dibuat untuk laporan pendapatan owner dari snapshot Fee Owner transaksi mitra.
- [x] Menu Pendapatan Owner Bruto hanya tampil untuk role yang boleh melihat profit (`owner`/`super_admin`).
- [x] Migration non-destruktif `20260713074944_mvp_mitra_internal_owner_classification.sql` dibuat untuk `master_mitra.tipe_mitra`.
- [x] Kode `BL`, `BL/%`, `SL`, dan `SL/%` diklasifikasikan sebagai `internal_owner`; lainnya default `eksternal`.
- [x] `/owner/master-data` mendukung edit tipe mitra/grup: Mitra Eksternal atau Internal Owner.
- [x] `/owner/pendapatan-owner` diberi label **Pendapatan Owner Bruto**, filter tipe mitra, dan catatan belum dikurangi biaya operasional.
- [x] `/owner/pendapatan-owner` menampilkan catatan kecil breakdown Pendapatan Owner Bruto per nilai Fee Owner aktif (mis. 40/kg, 30/kg, 20/kg) sesuai transaksi periode/filter.
- [x] `/owner/pendapatan-owner` tabel rincian transaksi menampilkan Hasil Kotor Pabrik per transaksi dan menyembunyikan kolom tipe mitra di detail.
- [x] Input Fee Owner nominal awal sudah dijalankan lewat migration `20260713092933_mvp_fee_owner_input_20260713.sql`.
- [x] Tanggal berlaku Fee Owner dikoreksi menjadi mulai `2026-01-01` lewat migration `20260713093508_mvp_fee_owner_effective_20260101.sql`.
- [x] Fee 20/Kg: `SL`, `BL`, `SL/NL`, `SL/CHT`.
- [x] Fee 30/Kg: `SL/F`, `SL/MLD`, `SL/BS`, `SL/HB`, `SL/SW`, `SL/WRD`, `SL/ANC`, `SL/B`, `SL/IMAN` alias input `SL/IMN`, `SL/NSL`, `BL/P`, `BL/ML`.
- [x] Catatan input fee: `BL/ML` muncul di fee 20 dan 30 sehingga nilai final mengikuti daftar terakhir = 30; `SL/WND` belum ada di master mitra.
- [x] Patch repo: input pengiriman, riwayat koreksi, laporan mitra, kwitansi, dan pendapatan owner memakai fallback Fee Owner dari master mitra jika snapshot awal history masih 0/basi.
- [x] Migration non-destruktif `20260714011606_mvp_sync_fee_history_from_master.sql` dibuat dan sudah dijalankan ke Supabase remote/production sebagai RPC `sync_fee_owner_mitra_period`, agar sinkronisasi Fee Owner hanya berlaku untuk periode/filter yang sedang dibuka.
- [x] Halaman `/owner/pengaturan-web` dibuat untuk mengatur nama aplikasi, subjudul aplikasi, logo website berwarna, dan logo kwitansi.
- [x] Sidebar dan kwitansi memakai pengaturan branding dari `pengaturan_bisnis.web_branding`.
- [x] File logo disimpan di Supabase Storage bucket `branding`; database hanya menyimpan path logo agar hemat ukuran Postgres.
- [x] Logo kwitansi mendukung satu PNG berwarna yang otomatis dibuat hitam saat cetak; PNG hitam khusus tetap bisa diupload sebagai override bila hasil print perlu lebih presisi.
- [x] Migration non-destruktif `20260713123454_mvp_web_branding_waktu.sql` dibuat untuk seed `web_branding`, bucket Storage `branding`, policy upload/delete owner, dan index waktu transaksi `transaksi_mitra(tanggal, created_at)`.
- [x] Migration `20260713123454_mvp_web_branding_waktu.sql` sudah dijalankan ke Supabase remote/production via CLI.
- [x] Migration non-destruktif `20260713125945_mvp_kwitansi_mitra_payment_status.sql` dibuat dan sudah dijalankan ke Supabase remote/production via CLI.
- [x] Migration pengencangan policy `20260713131711_mvp_kwitansi_payment_policy_tightening.sql` dibuat dan sudah dijalankan ke Supabase remote/production via CLI.
- [x] Status pembayaran kwitansi mitra live dengan tabel `pembayaran_mitra_kwitansi` dan `pembayaran_mitra_kwitansi_item`.
- [x] `/owner/kwitansi-mitra` mendukung status Belum Dibayar, Sudah Dibayar, atau Perlu Review.
- [x] `/owner/kwitansi-mitra` memiliki tombol **Tandai Dibayar** untuk role `owner`, `super_admin`, dan `admin_keuangan`.
- [x] Kwitansi yang sudah dibayar memakai snapshot transaksi/panjar/nilai pembayaran agar arsip pembayaran tidak berubah diam-diam ketika transaksi lama diedit.
- [x] Saat kwitansi ditandai dibayar, panjar mitra yang dipotong otomatis ditandai `lunas` agar tidak terpotong lagi.
- [x] `/owner/laporan-mitra` mendukung filter status pembayaran: semua, belum dibayar, sudah dibayar, dan perlu review.
- [x] `/owner/laporan-mitra` menampilkan kolom hasil kotor pabrik dan nilai bersih mitra tanpa menampilkan harga per kg di tabel utama.
- [x] `/owner/laporan-mitra` memakai tabel ringkas: Tanggal/Waktu digabung, Sopir/Mitra/Plat digabung, agar muat di layar laptop/tablet.
- [x] `/owner/kwitansi-mitra` memakai typography dan spacing preview yang lebih compact untuk laptop/tablet.
- [x] Header tabel ringkas maksimal 2 kata untuk tabel operasional utama, misalnya `Tanggal`, `Mitra`, `Hasil Pabrik`, `Nilai Bersih`, dan `Bruto`.
- [x] Input pengiriman mitra baru menyimpan `total_kotor` sebagai hasil kotor pabrik dan `total_nilai_bersih` sebagai hak mitra setelah Fee Owner.
- [x] Menu dan halaman `/admin/input-timbangan` diganti label menjadi **Input Pengiriman**.
- [x] Alur form `/admin/input-timbangan` diubah menjadi: Tanggal -> Mitra Transaksi -> Sopir/Armada -> Sopir Aktual -> Tonase, dengan sopir/armada mitra terpilih diprioritaskan tanpa mengunci pilihan lintas mitra.
- [x] Migration backfill `20260713132431_mvp_fix_transaksi_mitra_gross_net_values.sql` sudah dijalankan ke Supabase remote/production untuk membetulkan data kotor pabrik vs nilai bersih mitra.
- [x] Migration koreksi `20260713133009_mvp_fix_blml_fee_final_30.sql` sudah dijalankan ke Supabase remote/production; `BL/ML` final menjadi Fee Owner 30/kg mulai `2026-01-01`.
- [ ] Tahap 2: biaya operasional owner, kepemilikan armada, status sopir, dan pendapatan owner bersih.
- [ ] Review apakah `SL/MD` perlu dibuat sebagai master mitra baru atau tetap menjadi armada tanpa default mitra.

### Agenda Baru - Tahap 2 Kas, Uang Masuk, dan Hutang/Panjar Universal (14 Juli 2026)

Tahap 2 perlu menyatukan pencatatan uang dan utang agar tidak terpecah antara panjar mitra, hutang petani, pembayaran pabrik, biaya, dan pembayaran mitra.

Kondisi sistem sekarang:

- **Uang masuk pabrik** sudah punya fondasi schema `pembayaran_pabrik` dan `pembayaran_pabrik_detail`, tetapi UI alokasi satu pembayaran ke satu/banyak DO belum selesai.
- **Pendapatan Owner Bruto** saat ini dihitung dari snapshot Fee Owner transaksi mitra, jadi masih basis transaksi/bruto, belum basis kas aktual.
- **Kwitansi/Pembayaran Mitra** adalah uang keluar dari owner/perusahaan ke mitra, bukan uang masuk.
- **Panjar Mitra** masih tercatat di `panjar_mitra` dan dipotong saat kwitansi; ini perlu dimigrasikan atau disinkronkan ke ledger hutang/piutang universal.
- **Hutang Petani** sudah memakai `hutang_ledger`, tetapi belum cukup fleksibel untuk mitra, sopir, karyawan, dan pihak lain.
- **Biaya Operasional** sudah ada sebagai pencatatan biaya, tetapi belum menjadi bagian dari buku kas yang menyatukan seluruh arus uang.

Keputusan desain Tahap 2:

- Panjar, kasbon, pinjaman, dan pembayaran balik diperlakukan sebagai **saldo pihak** dalam satu ledger, bukan modul terpisah per jenis orang.
- Pihak yang bisa punya saldo: `petani`, `mitra`, `sopir`, `karyawan`, dan `lainnya`.
- Semua uang masuk dan uang keluar harus masuk ke **Buku Kas** (`kas_ledger`).
- Uang masuk minimal mencakup pembayaran pabrik, pengembalian kasbon/panjar, setoran modal/owner, pendapatan lain, dan koreksi plus.
- Uang keluar minimal mencakup pembayaran petani, pembayaran mitra, biaya operasional, panjar/kasbon, gaji/fee, tarik owner, dan koreksi minus.
- Laporan owner harus membedakan **Laba Kas** dari uang aktual yang sudah masuk/keluar dan **Laba Estimasi** dari nilai transaksi/DO yang belum tentu sudah dibayar.
- Transaksi finansial tidak boleh dihapus fisik; koreksi memakai reversal/pembatalan dengan alasan dan audit log.

Praktik bisnis yang harus diikuti:

- Pisahkan uang kas tunai, rekening bank, dan akun owner/modal jika nanti ada lebih dari satu sumber uang.
- Setiap kasbon/panjar wajib punya pihak, tanggal, nominal, sumber kas, alasan, pencatat, dan status approval jika melewati batas.
- Setiap pembayaran wajib punya bukti atau nomor referensi: transfer, kwitansi, catatan kas, atau lampiran.
- Tutup kas harian direkomendasikan: saldo awal + uang masuk - uang keluar = saldo akhir, lalu direkonsiliasi dengan kas fisik/bank.
- Tidak ada edit langsung pada transaksi yang sudah memengaruhi kas; gunakan koreksi/reversal agar histori tetap bisa diaudit.
- Role minimal: operator input, admin keuangan verifikasi, owner/super_admin approval transaksi besar atau melewati limit.

### Agenda Baru - Searchable Combobox untuk Semua Dropdown Master (13 Juli 2026)

Native `<select>` mulai tidak ergonomis karena data sopir/armada, mitra, petani, pabrik, dan armada akan terus bertambah. Metode input terbaik untuk MVP berikutnya:

- Ganti dropdown data referensi/master menjadi reusable `SearchableCombobox`.
- Dropdown enum kecil seperti status, kategori biaya, bulan, atau periode tetap boleh memakai `<select>` biasa.
- Nilai yang disimpan tetap `id`; label hanya untuk tampilan.
- Mitra bisa dicari dari `kode`, `alamat`, `nama`, dan penanggung jawab jika nanti ada.
- Sopir/armada bisa dicari dari `nama sopir`, `plat nomor`, serta `kode/alamat/nama mitra default`.
- Petani, pabrik, dan armada perusahaan memakai pola yang sama sesuai field utama masing-masing.
- Tampilan opsi dibuat dua baris: baris utama untuk identitas cepat, baris kedua untuk konteks.
- Tambahkan tombol clear, keyboard navigation, dan state kosong/error/loading.
- Untuk mobile, gunakan panel pencarian besar agar operator tidak perlu scroll dropdown browser yang panjang.
- Untuk data lebih dari 300 opsi, lanjutkan dengan virtualized list atau pencarian server-side.

Task:

- [x] Buat komponen `SearchableCombobox` reusable.
- [x] Ganti dropdown `Armada / Sopir Default` dan `Sopir Pengganti` di `/admin/input-timbangan`.
- [x] Ganti dropdown `Mitra Transaksi` di `/admin/input-timbangan`.
- [x] Ganti dropdown `Nama Mitra` di `/owner/kwitansi-mitra`.
- [x] Ganti dropdown `Pilih Mitra` di `/owner/panjar-mitra`.
- [x] Ganti dropdown afiliasi mitra default di `/owner/master-data`.
- [ ] Ganti dropdown petani di `/transaksi/beli` dan `/keuangan/hutang`.
- [ ] Ganti dropdown sopir, kendaraan, pabrik, dan alokasi stok di `/transaksi/kirim`.
- [ ] Ganti dropdown armada/sopir di `/master/armada`.
- [x] Siapkan helper label standar: mitra = `kode - alamat - nama`, sopir/armada = `nama - plat - kode/alamat mitra`.

Acceptance:

- [x] Operator bisa menemukan mitra/sopir tanpa scroll panjang.
- [x] Search bekerja untuk kode, alamat, nama, dan plat.
- [x] Bisa dipakai dengan mouse, touch, dan keyboard.
- [ ] Performa tetap nyaman untuk minimal 500 opsi lokal.
- [x] Tidak mengubah data yang tersimpan, hanya metode pemilihan di UI.

### Agenda Baru - Sort dan Pagination Tabel MVP (13 Juli 2026)

Tabel dengan data banyak perlu bisa diurutkan dari header dan dipaginasi agar operator tidak perlu scroll panjang.

Task:

- [x] Buat helper sort reusable `sortRows` dan `getNextSort`.
- [x] Buat komponen header tabel sortable `SortableHeader`.
- [x] Buat helper pagination reusable `paginateRows`.
- [x] Buat komponen kontrol halaman `TablePagination`.
- [x] Terapkan sort header dan pagination 20 data/halaman di `/owner/laporan-mitra`.
- [x] Tambahkan filter multi-mitra dan mode kelompok per mitra di `/owner/laporan-mitra`.
- [x] Terapkan sort header dan pagination 20 data/halaman di `/owner/riwayat-pengiriman-mitra`.
- [x] Terapkan sort header dan pagination 20 data/halaman di `/owner/panjar-mitra`.
- [x] Terapkan sort header dan pagination 20 data/halaman di `/owner/master-data`.
- [x] Terapkan sort header dan pagination 20 data/halaman di `/owner/pendapatan-owner`.
- [x] Dashboard dibatasi menampilkan maksimal 10 transaksi terakhir.
- [ ] Terapkan pola yang sama ke tabel modul Tahap 2 saat modul tersebut dibuka penuh.

Acceptance:

- [x] Klik header tabel mengurutkan data ascending/descending.
- [x] Kolom angka diurutkan sebagai angka, bukan teks.
- [x] Kolom teks memakai urutan natural `id-ID`.
- [x] Tabel utama MVP menampilkan 20 data per halaman.
- [x] Tabel dashboard tetap ringkas dengan maksimal 10 data.

### Agenda Baru - Pengaturan Web dan Logo Kwitansi MVP (13 Juli 2026)

Identitas aplikasi perlu bisa dikelola dari UI agar logo dan nama usaha tidak terkunci di kode. Untuk kebutuhan kwitansi, sistem mendukung satu logo PNG berwarna transparan yang otomatis ditampilkan hitam saat cetak.

Task:

- [x] Buat helper branding default dan normalisasi data `web_branding`.
- [x] Buat hook `useBrandingSettings` untuk membaca/menyimpan `pengaturan_bisnis.web_branding`.
- [x] Buat komponen `BrandMark` untuk logo website dan logo print.
- [x] Buat route `/owner/pengaturan-web`.
- [x] Buat bucket Supabase Storage `branding` khusus logo aplikasi.
- [x] Batasi menu dan akses halaman pengaturan web untuk `owner` dan `super_admin`.
- [x] Upload logo website berwarna sebagai PNG.
- [x] Upload logo kwitansi hitam sebagai PNG opsional.
- [x] Simpan file logo di Supabase Storage, bukan sebagai base64 di Postgres.
- [x] Simpan hanya path logo di `pengaturan_bisnis.web_branding`.
- [x] Jika logo kwitansi hitam kosong, gunakan logo berwarna dengan mode otomatis hitam untuk cetak.
- [x] Sidebar membaca nama aplikasi, subjudul, dan logo dari pengaturan branding.
- [x] Kwitansi mitra memakai logo print dan nama aplikasi dari pengaturan branding.

Acceptance:

- [x] Satu PNG berwarna transparan cukup untuk logo website dan kwitansi.
- [x] Sistem tetap menyediakan override PNG hitam untuk hasil print yang lebih presisi.
- [x] Database hanya menyimpan konfigurasi kecil, bukan file logo.
- [x] Pengaturan tidak terlihat oleh admin operasional/admin keuangan.
- [x] Jika belum ada pengaturan tersimpan, aplikasi memakai fallback `SAWIT CB` dan `Manajemen RAM`.

### Agenda Baru - Status Pembayaran Mitra (MVP Live)

Kwitansi menunjukkan nilai yang harus dibayar owner ke mitra, tetapi MVP perlu tambahan pencatatan agar owner tahu mitra mana yang sudah dibayarkan.

Keputusan desain awal:

- Status pembayaran tidak dicatat sebagai checkbox bebas di setiap transaksi.
- Status pembayaran dicatat sebagai **batch pembayaran mitra** berdasarkan mitra dan periode kwitansi.
- Batch menyimpan snapshot total tonase, total nilai bersih TBS, potongan panjar mitra, nominal dibayar, tanggal bayar, metode bayar, catatan, dan user pencatat.
- Transaksi yang masuk batch pembayaran harus bisa ditelusuri kembali agar laporan bisa membedakan `belum dibayar`, `dibayar`, atau `perlu review` jika transaksi dikoreksi setelah pembayaran.
- **Kwitansi adalah bukti pembayaran utama**. Setelah owner menandai pembayaran sebagai dibayar, kwitansi menjadi arsip/bukti pembayaran resmi untuk mitra.
- Lampiran transfer hanya opsional sebagai bukti pendukung jika pembayaran dilakukan via transfer; file pendukung disimpan di Storage, bukan di database.

Task:

- [x] Tambah migration `pembayaran_mitra_kwitansi` untuk header batch pembayaran.
- [x] Tambah migration `pembayaran_mitra_kwitansi_item` untuk mengunci daftar transaksi yang dibayar dalam batch.
- [x] Tambah migration tightening policy agar RPC tidak bisa dieksekusi `anon` dan policy SELECT tidak ganda.
- [x] Tambah status pembayaran di `/owner/kwitansi-mitra`: Belum Dibayar, Sudah Dibayar, atau Perlu Review.
- [x] Tambah tombol **Tandai Dibayar** setelah kwitansi selesai dicek owner.
- [x] Simpan snapshot nominal pembayaran agar perubahan transaksi setelahnya tidak diam-diam mengubah riwayat pembayaran.
- [x] Kwitansi yang sudah ditandai dibayar menampilkan status **Sudah Dibayar**, tanggal/jam bayar, dan metode bayar.
- [x] User pencatat pembayaran disimpan di kolom `created_by` dan `updated_by`.
- [ ] Tampilkan nama pencatat pembayaran di UI kwitansi setelah relasi user display dibuat stabil.
- [x] Tambah filter pembayaran di `/owner/laporan-mitra`.
- [ ] Tambah ringkasan mitra sudah/belum dibayar untuk periode tertentu.
- [x] Jika transaksi dalam batch diedit setelah pembayaran, tampilkan badge **Perlu Review** di kwitansi dan laporan.
- [ ] Tambah alur pembatalan/reversal pembayaran mitra jika pembayaran salah ditandai.

Acceptance:

- [x] Owner bisa melihat daftar transaksi/mitra yang sudah dibayar untuk periode tertentu lewat filter Laporan Mitra.
- [x] Owner bisa membedakan kwitansi yang belum dibayar dan sudah dibayar.
- [x] Kwitansi menjadi bukti pembayaran utama setelah statusnya ditandai **Sudah Dibayar**.
- [x] Pembayaran yang sudah tercatat tidak hilang walau transaksi lama diedit.
- [x] Lampiran pendukung opsional tidak disimpan sebagai blob di Postgres.
- [ ] Ringkasan agregat mitra sudah/belum dibayar tersedia dalam satu panel periode.

### Agenda Baru - Export Spreadsheet MVP (13 Juli 2026)

Data master dan laporan perlu bisa dibawa ke Excel/Spreadsheet untuk pengecekan manual dan arsip owner.

Task:

- [x] Tambah helper reusable `exportStyledWorkbook` untuk file `.xlsx`.
- [x] Style export: judul, subtitle, header berwarna, border, dan row ganjil/genap beda warna.
- [x] Export daftar Mitra dari `/owner/master-data` sesuai filter/search/sort aktif.
- [x] Export daftar Armada & Sopir dari `/owner/master-data` sesuai filter/search/sort aktif.
- [x] Export Laporan Mitra dari `/owner/laporan-mitra` sesuai periode dan filter multi-mitra aktif.
- [x] Laporan Mitra export dua sheet: detail pengiriman dan ringkasan per mitra.
- [ ] Terapkan export spreadsheet ke laporan Tahap 2 saat modul final dibuka.

Acceptance:

- [x] File export berbentuk `.xlsx`, bukan CSV polos.
- [x] Header tabel tampil berwarna.
- [x] Row ganjil/genap dibedakan warna.
- [x] Kolom angka tetap menjadi angka agar bisa dihitung di spreadsheet.
- [x] Export memakai data hasil filter/search/sort, bukan hanya data halaman pagination yang sedang terlihat.

### Add-on MVP - Pengiriman Kwitansi Mitra via WhatsApp (13 Juli 2026)

Add-on ini sudah direncanakan di `PRD-final.md` sebagai fitur tambahan MVP untuk mengirim kwitansi mitra ke nomor WhatsApp penanggung jawab mitra.

Keputusan desain:

- Format utama yang dikirim adalah PDF.
- Tombol **Cetak / Simpan PDF** tetap dipertahankan.
- Tombol **Kirim WhatsApp** akan memakai nomor dari `master_mitra.no_hp`.
- Nama penerima memakai `master_mitra.penanggung_jawab`.
- Alur MVP memakai pendekatan hybrid:
  - jika browser mendukung file share, bagikan PDF lewat Web Share API;
  - jika tidak mendukung, fallback ke download/cetak PDF dan buka `wa.me` dengan caption otomatis.
- WhatsApp Business Platform / Cloud API ditunda untuk tahap lanjut karena butuh setup akun bisnis, token, webhook, dan kontrol biaya.

Task:

- [x] Analisis opsi implementasi: WhatsApp link, Web Share API, dan WhatsApp Business Platform / Cloud API.
- [x] Pilih solusi MVP: hybrid PDF + Web Share API + fallback `wa.me`.
- [x] Catat keputusan format file: PDF sebagai format utama, teks WhatsApp sebagai caption/ringkasan.
- [x] Tambahkan addendum perencanaan ke `PRD-final.md`.
- [x] Tambah normalisasi nomor WA: `08...` menjadi `628...`, hapus spasi/strip/titik/tanda plus.
- [x] Tambah validasi nomor WA di halaman Kwitansi Mitra.
- [x] Tambah preview penerima: kode mitra, nama/alamat mitra, nama PJ, dan nomor WA.
- [ ] Tambah generator PDF kwitansi yang stabil untuk dibagikan/diunduh.
- [ ] Tambah auto-download PDF sebelum membuka WhatsApp jika generator PDF sudah tersedia.
- [x] Tambah tombol **Kirim WhatsApp** di `/owner/kwitansi-mitra`.
- [x] Buat caption otomatis berisi mitra, periode, total tonase, total nilai bersih TBS, potongan panjar mitra, dan sisa dibayar ke mitra.
- [x] Koreksi istilah kwitansi: panjar ditampilkan sebagai potongan panjar mitra/uang muka, bukan "panjar belum lunas".
- [x] Koreksi label master mitra: `fee_per_kg` ditampilkan sebagai **Fee Owner**, bukan Fee Pabrik/Fee Mitra.
- [x] Tambah kontrol koreksi harga bersih di `/owner/riwayat-pengiriman-mitra`: input Harga Pabrik/TWB, tampilkan Fee Owner aktif, hitung ulang Harga Bersih/Kg dan Nilai Bersih.
- [x] Tambah tombol koreksi cepat untuk data lama yang tersimpan sebelum Fee Owner dipotong: gunakan harga lama sebagai Harga Pabrik/TWB lalu kurangi Fee Owner aktif.
- [x] Tambah migration non-destruktif `20260713071118_mvp_fee_owner_snapshot_history.sql` untuk `fee_owner_mitra_history` dan snapshot harga/fee di `transaksi_mitra`.
- [x] Transaksi mitra baru menyimpan snapshot `harga_pabrik_per_kg`, `fee_owner_per_kg`, `harga_bersih_per_kg`, `total_fee_owner`, `total_nilai_bersih`, dan `fee_owner_history_id`.
- [x] Master Mitra mencatat riwayat Fee Owner saat fee disimpan, termasuk tanggal berlaku dan alasan perubahan.
- [x] Input/Riwayat/Kwitansi/Laporan Mitra membaca harga/nilai bersih dari snapshot baru, dengan fallback ke kolom lama untuk data existing.
- [ ] Implement Web Share API untuk membagikan PDF jika browser mendukung.
- [x] Implement fallback desktop: download/cetak PDF dan buka `https://wa.me/<nomor>?text=<caption>`.
- [x] Pastikan transaksi `dibatalkan` tidak masuk PDF/caption yang dikirim.
- [x] Tambah instruksi jelas saat file harus dilampirkan manual di WhatsApp Web.
- [ ] Tambah send log manual `kwitansi_mitra_send_log` jika sudah dibutuhkan untuk riwayat kirim.
- [ ] Tambah status revisi jika kwitansi pernah dikirim lalu transaksi dikoreksi.
- [ ] Evaluasi WhatsApp Business API setelah volume transaksi dan kebutuhan tracking meningkat.

Acceptance:

- [x] Tombol **Kirim WhatsApp** hanya aktif saat mitra dipilih, transaksi tersedia, dan nomor WA valid.
- [x] Operator melihat preview penerima sebelum membuka WhatsApp/share sheet.
- [ ] File yang dibagikan adalah PDF kwitansi.
- [x] Caption tidak memuat laba/margin owner.
- [x] Alur desktop tetap bisa dipakai walau browser tidak mendukung file share.
- [ ] Alur mobile bisa membagikan PDF langsung jika browser/perangkat mendukung.

### Panduan Environment (PENTING UNTUK TAHAP 2)
Untuk menjaga integritas data operasional MVP (Tahap 1) yang sudah mulai digunakan oleh Owner:
1. Pengerjaan Tahap 2 **WAJIB** menggunakan database *Development / Staging* yang terpisah dari *Production*.
2. Segala skema/tabel baru (`petani_lokal`, dll) dibuat dan diuji di database *Development* terlebih dahulu.
3. Migrasi ke *Production* wajib berupa *Non-Destructive Migration* (hanya menambah tabel/kolom, tidak menghapus/mengubah struktur tabel MVP yang sudah berjalan).
4. Lakukan *Backup* database *Production* di Supabase sebelum me-release Tahap 2.

Langkah selanjutnya adalah mengunci **P0-0 - Fondasi Keamanan Produksi** terlebih dahulu, lalu melanjutkan modul Tahap 2 berdasarkan gate bisnis: lokal, kas, hutang/panjar universal, settlement, dan laporan.

Stack:

- Next.js App Router
- React client components
- Supabase JS client
- Supabase/PostgreSQL schema di `supabase-schema.sql`

Kondisi teknis saat ini:

- Role sudah berkembang menjadi `owner`, `super_admin`, `admin_operasional`, dan `admin_keuangan`, tetapi test query role belum lengkap.
- Modul MVP live masih memakai `master_mitra`, `sopir`, `transaksi_mitra`, `panjar_mitra`, dan tabel kwitansi pembayaran.
- Schema P0 sudah menambah fondasi lokal: `petani`, `pabrik`, `armada_perusahaan`, `harga_tbs_lokal`, `transaksi_beli_tbs`, `stok_tbs_lokal_ledger`, `pengiriman_lokal_detail`, `hutang_ledger`, `pembayaran_pabrik`, `settlement_mitra`, `pembayaran_mitra`, `biaya_operasional`, `audit_log`, `rekening_kas`, dan `kas_ledger`.
- Penguatan RLS sudah dimulai tetapi belum boleh dianggap final sampai ada matrix test per role dan per modul.
- Uang masuk/keluar dasar sudah punya `kas_ledger`: pembelian petani lokal, pembayaran pabrik dari pengiriman lokal, pembayaran mitra lewat kwitansi, biaya operasional, serta hutang/panjar universal.
- Panjar mitra masih mempertahankan tabel legacy `panjar_mitra`, tetapi input baru sudah disinkronkan ke `hutang_ledger` dan `kas_ledger`. Backfill data panjar legacy lama belum dilakukan.
- Pembayaran pabrik sudah mencatat uang aktual ke kas untuk alur dasar pengiriman lokal. UI alokasi satu pembayaran ke banyak DO belum selesai.
- `master_mitra` MVP dan `mitra` final perlu mapping/sumber kebenaran sebelum settlement final agar tidak terjadi data ganda.

Prinsip implementasi:

- Kerjakan migration database dulu sebelum UI besar.
- Jangan delete transaksi yang berdampak ke stok, hutang, kas, atau settlement; gunakan status/reversal.
- Buat fungsi/formula settlement sebagai unit test sebelum UI settlement.
- Jaga kompatibilitas data lama dengan migration yang eksplisit.
- Jangan deploy perubahan RLS/policy besar ke production tanpa uji role di staging.
- Rilis Tahap 2 per gate kecil: security -> kas -> hutang/panjar -> settlement -> laporan.

Roadmap gate bisnis:

1. **Gate Keamanan:** role, RLS, RPC, audit, dan no-delete untuk data finansial.
2. **Gate Operasional Lokal:** pembelian petani, stok, pengiriman lokal, dan pembayaran pabrik stabil.
3. **Gate Kas:** semua uang aktual masuk/keluar dicatat di `kas_ledger`.
4. **Gate Hutang/Panjar:** semua pihak yang mengutang atau menerima panjar masuk ledger universal.
5. **Gate Settlement:** formula mitra, fee history, selisih tonase, potongan armada, dan potongan kasbon dihitung dari data yang sudah terkunci.
6. **Gate Laporan:** owner melihat kas, hutang/panjar, settlement, laba kas, dan laba estimasi dengan label jelas.
7. **Gate Release:** security verification, regression test modul live, backup production, dan rollback checklist.

Tahapan kelayakan produk:

1. **Fase 1 - MVP Operasional Terbatas (status saat ini):**
   - Boleh dipakai untuk input pengiriman mitra ke pabrik, panjar mitra dasar, kwitansi mitra, laporan mitra, dan koreksi/batal transaksi mitra.
   - Belum boleh disebut sistem bisnis minimal karena uang masuk, uang keluar, hutang/panjar semua pihak, dan pembayaran aktual belum memakai ledger tunggal.
   - Live production boleh berjalan sambil pengembangan lanjut selama perubahan production bersifat kecil, non-destruktif, sudah lolos build, dan sudah diuji di staging jika menyentuh database/policy.

2. **Fase 2 - Sistem Bisnis Minimal:**
   - Target minimum agar web layak dipakai sebagai kontrol bisnis harian, bukan hanya pencatatan pengiriman.
   - Wajib selesai: P0-0 security gate, no-delete/reversal finansial, pembayaran pabrik dasar, `rekening_kas`, `kas_ledger`, pencatatan semua uang masuk/keluar aktual, hutang/panjar universal, pembayaran mitra dasar yang tercatat ke kas, dan laporan owner dasar untuk kas, hutang/panjar, DO belum dibayar, dan mitra belum dibayar.
   - Pada fase ini owner boleh memakai laporan kas/hutang sebagai referensi operasional harian, tetapi laba/margin detail masih harus diberi label estimasi jika settlement penuh belum selesai.
   - Status 14 Juli 2026: Fase 2 minimum sudah diimplementasikan untuk fondasi kas, hutang/panjar universal, biaya, panjar mitra baru, pembayaran mitra dasar, pembayaran pabrik dasar, dan laporan laba kas berbasis `kas_ledger`. Fase ini belum berarti aplikasi utuh karena settlement advanced, bukti/lampiran, limit kasbon, dan alokasi multi-DO masih masuk Fase 3/Fase 4.

3. **Fase 3 - Sistem Operasional Lengkap:**
   - Target agar seluruh alur utama sawit berjalan rapi: petani lokal, stok lokal, pengiriman lokal, pembayaran pabrik multi-DO, settlement mitra, fee history, tarif armada, biaya bantuan, audit/reversal, laporan operasional, dan export.
   - Pada fase ini laporan settlement, stok, pabrik, mitra, dan kas sudah bisa menjadi sumber kerja utama admin/owner.

4. **Fase 4 - Aplikasi Utuh dan Matang:**
   - Target polish dan kontrol lanjutan: upload bukti/tiket timbang, WhatsApp evidence flow, multi-lokasi, rekonsiliasi anomali, dashboard margin lebih dalam, monitoring, SOP backup/restore, dan hardening final.
   - Pada fase ini aplikasi bisa dianggap utuh, bukan sekadar alat operasional internal yang masih berkembang.

## P0-0 - Fondasi Keamanan Produksi

Tujuan: memastikan sistem live aman untuk data operasional asli sebelum fitur uang, hutang universal, dan settlement diperluas.

Keputusan:

- Penguatan keamanan dilakukan bertahap per modul, bukan satu migration besar yang mengubah semua policy sekaligus.
- UI hiding tetap dipakai untuk kenyamanan, tetapi bukan kontrol utama; RLS/RPC/backend harus menolak akses yang tidak sah.
- Aksi finansial penting tidak boleh memakai delete fisik.
- Semua perubahan policy harus diuji dengan akun nyata/peran nyata: owner, super_admin, admin_operasional, admin_keuangan.

Task:

- [ ] Buat matrix akses final per tabel/RPC/route berdasarkan PRD bagian Hak Akses.
- [ ] Audit semua policy Supabase yang masih `USING (true)` atau full access.
- [ ] Audit semua RPC `SECURITY DEFINER` dan pastikan ada validasi `auth.uid()` serta role aplikasi.
- [ ] Revoke execute RPC sensitif dari `PUBLIC`/`anon`; grant hanya ke role yang diperlukan.
- [ ] Pisahkan policy SELECT, INSERT, UPDATE, DELETE untuk tabel finansial agar tidak semua role dapat semua aksi.
- [ ] Pastikan tabel profit/margin/laba hanya dapat dibaca owner dan super_admin.
- [ ] Pastikan owner tidak bisa mengelola user/role; hanya super_admin.
- [ ] Pastikan admin_operasional bisa input operasional tetapi tidak bisa melihat laba/profit.
- [ ] Pastikan admin_keuangan bisa input pembayaran/kas/hutang tetapi tidak bisa melihat laba/profit.
- [ ] Ganti delete fisik tersisa pada transaksi finansial menjadi cancel/reversal, minimal untuk panjar, biaya, pembayaran, dan ledger.
- [ ] Tambahkan checklist uji manual role sebelum deploy production.
- [ ] Dokumentasikan rollback plan untuk migration/policy yang berisiko.

### Audit Awal P0-0 - 14 Juli 2026

Status: audit statis dari repo selesai. Belum ada perubahan policy production; temuan ini masih harus diverifikasi di staging/remote sebelum migration security diterapkan.

Temuan prioritas tinggi:

- [ ] `fee_owner_mitra_history` masih punya policy `"Authenticated full access"` dengan `USING (true)` dan `WITH CHECK (true)` di migration `20260713071118_mvp_fee_owner_snapshot_history.sql`.
- [ ] Beberapa policy dasar masih memakai `read_authenticated USING (true)` untuk tabel operasional/finansial. Ini perlu diklasifikasi ulang: mana yang memang boleh dibaca semua role, mana yang harus dibatasi owner/super_admin/admin_keuangan.
- [ ] Policy write finansial masih banyak memakai `FOR ALL`, sehingga UPDATE/DELETE ikut terbuka untuk role yang sama. Perlu dipisah menjadi INSERT/UPDATE/DELETE dan delete fisik dibatasi atau dihapus.
- [ ] `biaya_operasional` mengizinkan `owner`, `super_admin`, `admin_keuangan`, dan `admin_operasional` untuk `FOR ALL`; ini terlalu longgar karena admin operasional boleh input, tetapi tidak otomatis boleh delete/update bebas.
- [ ] Tabel pembayaran kwitansi mitra sudah dipisah insert/update/delete pada migration tightening, tetapi masih ada `delete_finance`. Untuk data pembayaran live, delete sebaiknya diganti status `dibatalkan` atau reversal.
- [ ] Tabel MVP live `master_mitra`, `transaksi_mitra`, `panjar_mitra`, dan `kendaraan` tidak terlihat masuk daftar policy hardening P0 foundation. Perlu query langsung ke `pg_policies` di staging/remote untuk memastikan RLS dan policy aktual.

Temuan RPC/security definer:

- [ ] Mutation RPC `set_harga_tbs_lokal`, `create_transaksi_beli_tbs`, dan `cancel_transaksi_beli_tbs` memiliki role guard di dalam function, tetapi belum terlihat ada `REVOKE ALL ... FROM PUBLIC/anon` pada migration terkait.
- [ ] RPC `create_pengiriman_lokal` sudah punya `REVOKE ALL FROM PUBLIC` dan `GRANT EXECUTE TO authenticated`; tetap perlu cek role guard dan test role.
- [ ] RPC `create_pembayaran_mitra_kwitansi` sudah di-tighten dengan revoke `PUBLIC`/`anon`; tetap perlu test role owner/super_admin/admin_keuangan/admin_operasional.
- [ ] RPC `write_audit_log` adalah `SECURITY DEFINER` dan dipanggil langsung dari client pada `/owner/riwayat-pengiriman-mitra`. Ini berisiko karena user bisa membuat audit log palsu atau update berhasil tetapi audit gagal. Jangka pendek perlu revoke/role guard; jangka menengah edit/cancel transaksi mitra harus pindah ke RPC transactional.
- [ ] Helper `current_app_role` dan `has_app_role` adalah `SECURITY DEFINER`. Perlu pastikan grant-nya cukup untuk RLS tetapi tidak membuka data user lebih dari yang diperlukan.

Temuan delete fisik dan audit gap:

- [x] `/owner/panjar-mitra` tidak lagi memakai `.delete()`; patch mengganti hapus fisik menjadi status `dibatalkan` dan pada Fase 2 baru memakai reversal kas/hutang lewat RPC.
- [x] `/keuangan/biaya` tidak lagi memakai `.delete()`; patch mengganti hapus fisik menjadi status `dibatalkan` dan reversal `kas_ledger` lewat RPC.
- [ ] `/owner/riwayat-pengiriman-mitra` masih melakukan update `transaksi_mitra` langsung dari client lalu memanggil `write_audit_log` terpisah. Ini belum atomic.
- [x] `/keuangan/hutang` sudah pindah dari direct insert ke RPC `create_hutang_pihak` dan `cancel_hutang_ledger`, sehingga mutasi hutang dan kas berjalan satu transaksi.

Temuan positif:

- [x] Tidak ditemukan penggunaan `service_role` key di kode aplikasi `app/`, `lib/`, dan `utils/`; client memakai publishable key.
- [x] Route laba-rugi dan pendapatan owner sudah punya guard UI berbasis `canViewProfit`, tetapi tetap harus dibuktikan lewat RLS/query langsung.
- [x] Beberapa RPC penting sudah memiliki validasi role di body function, sehingga patch awal bisa fokus pada revoke/grant dan policy table tanpa membongkar semua flow sekaligus.

Urutan patch security yang disarankan:

1. Buat migration audit-only/query checklist untuk staging: daftar RLS, policy, function execute grant, dan role test.
2. [x] Patch no-delete paling kecil: ganti delete panjar dan biaya menjadi status `dibatalkan`/`aktif`, lalu lanjutkan ke reversal kas/hutang untuk Fase 2 minimum.
3. Tighten RPC grants untuk mutation RPC: revoke `PUBLIC`/`anon`, grant hanya `authenticated`, lalu test role.
4. Tighten `fee_owner_mitra_history`: read sesuai kebutuhan, write hanya owner/super_admin, admin_operasional tidak boleh ubah fee history bebas.
5. Verifikasi dan tighten policy tabel MVP live: `master_mitra`, `transaksi_mitra`, `panjar_mitra`, `kendaraan`.
6. Pisahkan policy finansial `FOR ALL` menjadi `SELECT`, `INSERT`, `UPDATE`, dan `DELETE`; delete fisik dinonaktifkan untuk pembayaran, ledger, dan transaksi finansial.
7. Pindahkan edit/cancel `transaksi_mitra` ke RPC transactional agar update dan audit selalu satu operasi.

Acceptance:

- [ ] Semua tabel public yang terekspos punya RLS aktif dan policy sesuai role.
- [ ] Query langsung dari admin_operasional/admin_keuangan ke data laba/profit ditolak.
- [ ] Query owner untuk manage user/role ditolak.
- [ ] Query super_admin untuk manage user/role berhasil.
- [ ] RPC sensitif tidak bisa dipanggil oleh `anon` atau user tanpa role sesuai.
- [ ] Tidak ada delete fisik untuk transaksi yang memengaruhi stok, kas, hutang, settlement, atau pembayaran.
- [ ] Semua perubahan security diuji di staging sebelum production.

## P0A - Fondasi dan Alur Lokal

Tujuan: alur pembelian petani lokal, stok sementara, pengiriman lokal, pembayaran pabrik dasar, dan reversal operasional aman.

### P0A.1 Schema Foundation

Status: migration `supabase/migrations/202607110001_p0_foundation.sql` sudah berhasil di-apply ke Supabase remote pada 12 Juli 2026.

- [x] Buat migration baru, jangan overwrite schema lama langsung.
- [x] Update `users.role` menjadi `owner`, `super_admin`, `admin_operasional`, `admin_keuangan`.
- [x] Tambah/rapikan tabel master:
  - [x] `petani`
  - [x] `pabrik`
  - [x] `armada_perusahaan`
  - [x] `sopir` atau relasi sopir pada armada sesuai pola repo
  - [x] `harga_tbs_lokal`
- [x] Buat `transaksi_beli_tbs` atau migrasikan `transaksi_beli` agar sesuai PRD.
- [x] Buat `stok_tbs_lokal_ledger`.
- [x] Buat `pengiriman_lokal_detail`.
- [x] Buat `hutang_ledger`.
- [x] Buat `pengaturan_bisnis`.
- [x] Buat `audit_log`.
- [x] Tambahkan field status/reversal di transaksi yang perlu dibatalkan.

Acceptance:

- [x] Semua tabel P0A bisa dibuat ulang di Supabase tanpa error.
- [x] Data lama punya jalur migrasi dari `transaksi_beli`, `hutang`, `hutang_log`, `kendaraan`, dan `pengiriman`.
- [x] Nomor struk tetap unik.
- [x] Saldo stok dan saldo hutang dihitung dari ledger.

### P0A.2 Role and Access Control

Catatan: bagian ini mencatat pekerjaan role yang sudah berjalan. Finalisasi security dan RLS mengikuti gate `P0-0 - Fondasi Keamanan Produksi`.

- [x] Tambah helper role di frontend/backend.
- [x] Update `AppShell`, `Sidebar`, dan route guard untuk role baru.
- [x] Owner tidak bisa kelola user/role.
- [ ] Super admin bisa semua termasuk user/role.
- [x] Admin operasional tidak bisa melihat laba-rugi.
- [x] Admin keuangan tidak bisa melihat laba-rugi.
- [ ] Lengkapi RLS final berbasis role sesuai matrix P0-0.
- [ ] Tambahkan test query langsung untuk tabel sensitif.
- [ ] Pastikan route guard dan RLS memakai definisi role yang sama.

Acceptance:

- [x] Menu laba-rugi hanya terlihat untuk owner/super admin.
- [ ] Menu pengaturan user hanya terlihat untuk super admin.
- [ ] Query Supabase untuk tabel sensitif ditolak untuk role yang tidak berhak.
- [ ] Perubahan role di database langsung tercermin di akses aplikasi setelah session refresh.

### P0A.3 Harga TBS Lokal

- [x] Ubah harga dari harian menjadi `berlaku_mulai`/`berlaku_sampai`.
- [x] Update `/master/harga`.
- [x] Update dashboard banner harga agar mengambil harga aktif berdasarkan waktu sekarang.
- [x] Update `/transaksi/beli` agar mengambil harga aktif pada waktu transaksi.
- [x] Tambahkan audit log untuk override harga.

Acceptance:

- [x] Harga bisa berubah lebih dari sekali dalam satu hari.
- [x] Transaksi lama tidak berubah saat harga baru dibuat.
- [x] Transaksi tidak bisa disimpan jika tidak ada harga aktif.

### P0A.4 Pembelian TBS Petani

- [x] Update `/transaksi/beli` agar memakai schema baru.
- [x] Simpan berat dalam kg.
- [x] Simpan transaksi beli dan stok masuk dalam satu operasi aman.
- [x] Potongan hutang masuk ke `hutang_ledger`, bukan `hutang_log`.
- [x] Nomor struk dibuat aman dari race condition.
- [x] Hapus fisik transaksi diganti menjadi batal/reversal.
- [x] Update struk cetak sesuai field baru.
- [x] Update `/keuangan/hutang` agar kasbon/pembayaran petani memakai `hutang_ledger`.
- [x] Update `/laporan/petani` agar rekap transaksi memakai `transaksi_beli_tbs` dan saldo hutang memakai `hutang_ledger`.

Acceptance:

- [x] Pembelian menambah `stok_tbs_lokal_ledger`.
- [x] Potongan hutang hanya tercatat satu kali.
- [x] Batal transaksi membuat reversal stok dan hutang.
- [x] Dua admin input bersamaan tidak menghasilkan nomor struk bentrok.

### P0A.5 Stok Lokal

- [x] Buat UI laporan stok lokal.
- [x] Tambah stock opname/adjustment.
- [x] Implement alokasi FIFO default untuk pengiriman lokal.
- [ ] Admin tetap bisa memilih transaksi petani manual.
- [x] Cegah alokasi melebihi berat bersih transaksi.
- [x] Cegah stok minus tanpa role owner/super_admin.

Acceptance:

- [x] Laporan stok menunjukkan masuk, keluar, koreksi, sisa.
- [x] Koreksi stok membuat ledger baru.
- [x] Dua pengiriman bersamaan tidak bisa memakai stok yang sama melebihi saldo.

### P0A.6 Pengiriman Lokal ke Pabrik

- [x] Update `/transaksi/kirim` agar mendukung `sumber = lokal`.
- [x] Tambahkan detail alokasi transaksi petani ke pengiriman.
- [x] Tambahkan nomor DO unik per pabrik lintas sumber saat bukan draft.
- [x] Tambahkan status pengiriman lokal sesuai PRD.
- [x] Catat tonase pabrik, harga pabrik, sortasi, biaya timbang.
- [ ] Sortasi lokal tampil sebagai potongan/kerugian kualitas di laporan owner.

Acceptance:

- [x] Pengiriman lokal mengurangi stok.
- [x] Pengiriman dapat ditelusuri ke transaksi petani.
- [x] Nomor DO duplikat untuk pabrik yang sama ditolak saat bukan draft.

### P0A.7 Pembayaran Pabrik Dasar

Dependency:

- P0-0 security gate minimal untuk tabel pengiriman, pembayaran pabrik, dan laporan owner.
- P0A.6 pengiriman lokal ke pabrik sudah stabil.

- [x] Buat `pembayaran_pabrik`.
- [x] Buat `pembayaran_pabrik_detail`.
- [ ] Update UI pembayaran pabrik agar satu pembayaran bisa dialokasikan ke satu atau banyak DO.
- [ ] Bedakan `total_pembayaran_pabrik` sebagai nilai tagihan DO vs `total_bayar` sebagai uang aktual diterima.
- [ ] Cegah alokasi melebihi nilai tagihan DO.
- [ ] Catat audit saat pembayaran dibuat, dialokasikan, dibatalkan, atau dikoreksi.

Acceptance:

- [ ] Status pembayaran DO dihitung dari alokasi pembayaran.
- [ ] Laba Bersih Kas memakai uang aktual dari pembayaran pabrik detail.
- [ ] DO belum dibayar tidak masuk laba kas.
- [ ] Admin operasional hanya bisa melihat status pembayaran, bukan mengubah pembayaran.

### P0A.8 Buku Kas dan Pencatatan Uang Masuk

Tujuan: semua uang masuk dan uang keluar tercatat di satu buku kas agar laporan laba kas, saldo kas, dan audit pembayaran tidak tersebar di banyak tabel.

Dependency:

- P0-0 security gate untuk tabel finansial sudah lolos staging.
- P0A.7 pembayaran pabrik sudah membedakan tagihan DO dan uang aktual diterima.

Task:

- [x] Buat master `rekening_kas` untuk kas tunai, rekening bank, dan akun kas lain.
- [x] Buat `kas_ledger` untuk semua arus uang masuk/keluar dengan tanggal, rekening, arah, kategori, nominal, sumber transaksi, catatan, dan user pencatat.
- [x] Catat pembayaran pabrik sebagai `kas_masuk` saat pembayaran aktual diterima.
- [x] Hubungkan `pembayaran_pabrik` ke `kas_ledger` agar alokasi DO dan uang aktual tetap bisa ditelusuri untuk alur dasar satu pengiriman/DO.
- [x] Tambah form uang masuk non-DO: setoran owner/modal, pendapatan lain, pengembalian kasbon/panjar, dan koreksi plus melalui `/keuangan/kas` dan `/keuangan/hutang`.
- [x] Catat pembayaran mitra, pembayaran petani, biaya operasional, kasbon/panjar, dan gaji/fee sebagai `kas_keluar` pada flow Fase 2 minimum.
- [ ] Tambahkan nomor referensi/bukti untuk transaksi kas: transfer, kwitansi, catatan kas, atau lampiran.
- [x] Tambahkan validasi agar transaksi kas tidak bisa negatif pada RPC kas/hutang/biaya/pembayaran dasar. Tutup kas periodik belum dibuat.
- [x] Siapkan reversal kas untuk koreksi transaksi yang salah pada hutang/panjar, biaya, pembelian, dan panjar mitra baru.
- [x] Tambahkan ringkasan total masuk, total keluar, dan net per periode/rekening di `/keuangan/kas`. Saldo awal/akhir tutup kas masuk Fase 3.

Acceptance:

- [x] Semua uang masuk aktual pada flow Fase 2 minimum tercatat di `kas_ledger`.
- [x] Semua uang keluar aktual pada flow Fase 2 minimum tercatat di `kas_ledger`.
- [x] Laba Kas memakai `kas_ledger`, bukan hanya nilai transaksi/DO.
- [ ] Laba Estimasi tetap bisa dibandingkan dengan nilai transaksi/DO yang belum dibayar.
- [x] Satu pembayaran pabrik dasar bisa ditelusuri ke pengiriman/DO yang dibayar dan ke kas/rekening yang menerima uang.
- [x] Koreksi kas pada flow yang sudah dipindah ke RPC membuat entry reversal, bukan mengubah histori diam-diam.

## P0B - Alur Mitra dan Settlement

Tujuan: pisahkan mitra, pengiriman mitra, settlement per DO, Fee Owner history, kasbon mitra, biaya armada, dan bukti pembayaran.

### P0B.0 Pengaturan Bisnis

- [ ] Buat UI `/pengaturan/bisnis`.
- [x] Simpan default Fee Owner per kg.
- [x] Simpan default persentase selisih tonase perusahaan/mitra.
- [x] Simpan tindakan kasbon melewati limit: `blokir_otomatis` atau `wajib_approval`.
- [x] Simpan toleransi anomali tonase.
- [ ] Simpan prioritas kartu dashboard dan laporan harian.
- [ ] Batasi edit pengaturan bisnis untuk owner/super_admin.
- [ ] Audit setiap perubahan pengaturan bisnis.

Acceptance:

- [ ] Persentase selisih perusahaan + mitra selalu 100%.
- [ ] Admin operasional/admin keuangan hanya bisa melihat pengaturan yang dibutuhkan untuk input.
- [ ] Settlement, kasbon, dashboard, dan laporan memakai pengaturan aktif.

### P0B.1 Master Mitra

- [x] Buat tabel `mitra`.
- [ ] Buat halaman `/master/mitra` atau pisahkan dari `/master/petani`.
- [ ] Migrasikan data mitra jika sebelumnya tersimpan sebagai petani.
- [ ] Tambahkan field boleh kasbon, batas kasbon, rekening, persentase selisih tonase.
- [ ] Tambah ringkasan tonase, nilai pabrik, fee, hak mitra, dibayar, sisa bayar.

Acceptance:

- [ ] Petani tidak muncul di form pengiriman mitra.
- [ ] Mitra tidak muncul di form transaksi pembelian petani lokal.

### P0B.2 Fee Owner History

- [x] Buat `fee_mitra_history` sebagai riwayat Fee Owner dari mitra.
- [ ] Tambahkan UI set fee per kg dengan tanggal/jam berlaku.
- [ ] Settlement mengambil fee berdasarkan tanggal pengiriman/DO.
- [ ] Perubahan fee tidak mengubah settlement lama.

Acceptance:

- [ ] DO lama tetap memakai fee lama.
- [ ] DO baru memakai fee yang berlaku.

### P0B.3 Pengiriman Mitra (Sesuai MVP Terbaru)

- [ ] Buat route `/admin/input-timbangan` (Khusus Admin Lapangan, UI Mobile-Friendly).
- [x] Review route `/admin/input-timbangan` yang sudah ada agar kompatibel dengan schema final `pengiriman`/settlement.
- [x] Input mendukung pilihan armada/plat dan **sopir aktual** per DO, bukan hanya pemilihan nama sopir sebagai sumber utama.
- [x] Implementasikan auto-fill: saat armada atau sopir default dipilih, **Plat Armada**, **Sopir Default**, dan **Afiliasi Mitra** otomatis terisi.
- [x] Tambahkan pilihan **Mitra Transaksi** yang bisa dioverride dari default sopir/armada untuk kasus armada bersama SL/BL.
- [x] Tambahkan override sopir aktual jika sopir yang membawa armada berbeda dari default.
- [x] Simpan snapshot sopir aktual dan plat kendaraan ke transaksi/pengiriman agar histori tidak berubah saat master diubah.
- [x] Tambahkan riwayat transaksi mitra untuk edit koreksi dan pembatalan tanpa delete fisik.
- [ ] Input tonase pabrik/timbangan.
- [ ] Buat route `/owner/kwitansi-mitra` untuk mencetak Kwitansi per Mitra.
- [ ] Kwitansi harus menjumlahkan total nilai bersih TBS mitra, lalu **dikurangi Panjar Mitra** untuk mendapat sisa yang dibayar owner ke mitra.
- [ ] Deteksi anomali jika `tonase_dasar_settlement > tonase_timbang_mitra` melewati toleransi.

Acceptance:

- [ ] Pengiriman mitra tidak mengubah stok lokal.
- [ ] Pengiriman mitra bisa lanjut menjadi settlement setelah pembayaran pabrik/DO final.
- [ ] Setelah transaksi masuk settlement/pembayaran, edit langsung harus dikunci dan memakai flow koreksi/reversal.
- [ ] Anomali tampil di laporan mitra.
- [x] Pengiriman dengan sopir pengganti tetap bisa disimpan dan laporan menampilkan sopir default vs sopir aktual.

### P0B.4 Settlement Mitra Formula

Dependency:

- Pembayaran pabrik dan status DO sudah jelas.
- Fee history sudah berjalan dan bisa mengambil nilai berdasarkan tanggal pengiriman/DO.
- Hutang/panjar universal sudah punya pola potongan yang tidak double count.
- Fungsi kalkulasi wajib dibuat dan diuji sebelum UI settlement final.

- [ ] Implement fungsi kalkulasi settlement terpisah dari UI.
- [ ] Unit test kasus:
  - [ ] sortasi none
  - [ ] sortasi kg
  - [ ] sortasi percent
  - [ ] sortasi nominal
  - [ ] selisih timbang mitra lebih besar
  - [ ] tonase dasar settlement lebih besar dari timbang mitra
  - [ ] fee per kg
  - [ ] potongan armada
  - [ ] potongan kasbon
  - [ ] pembulatan rupiah
- [ ] Snapshot hasil settlement ke `settlement_mitra`.
- [ ] Gunakan `tonase_dasar_settlement`.
- [ ] Gunakan `fee_mitra_history`.

Acceptance:

- [ ] Formula sama dengan Bab 7 PRD.
- [ ] Semua nilai rupiah dibulatkan ke rupiah terdekat.
- [ ] Hak mitra tidak negatif tanpa approval owner/super_admin.

### P0B.5 Hutang/Panjar Universal

Tujuan: panjar, kasbon, pinjaman, dan pembayaran balik untuk petani, mitra, sopir, karyawan, atau pihak lain dicatat dalam satu pola ledger.

Dependency:

- P0A.8 `kas_ledger` sudah tersedia untuk mencatat uang keluar/masuk aktual.
- P0-0 security gate untuk tabel hutang/panjar dan kas sudah lolos staging.

Keputusan desain:

- `hutang_ledger` dikembangkan menjadi ledger pihak universal, atau dibuat ledger baru yang kompatibel dengan data hutang petani lama.
- `panjar_mitra` tidak menjadi sumber utama jangka panjang; data lama dipertahankan sebagai legacy, dimigrasikan, atau disinkronkan ke ledger universal.
- Saldo pihak dihitung dari mutasi ledger, bukan dari field saldo manual.
- Kasbon/panjar yang dibayar tunai atau transfer harus sekaligus membuat mutasi `kas_ledger`.
- Potongan saat settlement/kwitansi hanya membuat mutasi pelunasan, tidak boleh memotong saldo dua kali.

Task:

- [x] Tentukan final schema Fase 2: perluas `hutang_ledger` agar data hutang petani lama tetap kompatibel.
- [x] Tambahkan `pihak_type`: `petani`, `mitra`, `sopir`, `karyawan`, `lainnya`.
- [x] Tambahkan referensi pihak nullable (`petani_id`, `master_mitra_id`, `sopir_id`, `mitra_id` legacy) dan `pihak_nama_manual` untuk pihak non-master.
- [x] Tambahkan kategori mutasi: kasbon/panjar, pembayaran balik, potongan settlement/kwitansi, koreksi, reversal, dan kategori operasional dasar.
- [x] Tambah form kasbon/panjar universal dengan pilihan pihak dan sumber kas/rekening.
- [ ] Tambah batas kasbon per pihak atau per tipe pihak.
- [ ] Implement `blokir_otomatis` atau `wajib_approval` sesuai pengaturan bisnis.
- [x] Integrasikan kasbon/panjar dengan `kas_ledger` saat uang benar-benar keluar.
- [x] Integrasikan pengembalian kasbon/panjar dengan `kas_ledger` saat uang benar-benar masuk.
- [x] Potong saldo mitra saat kwitansi melalui ledger universal. Settlement advanced tetap Fase 3.
- [ ] Migrasikan atau backfill `panjar_mitra` aktif ke ledger universal tanpa mengubah histori pembayaran.
- [x] Tambahkan halaman ringkasan saldo per pihak dan riwayat mutasi. Status melewati limit menunggu fitur limit kasbon.

Acceptance:

- [x] Saldo kasbon/panjar semua pihak dihitung dari ledger universal untuk transaksi baru Fase 2.
- [x] Petani, mitra, sopir, karyawan, dan pihak lain bisa dicatat utang/kasbonnya.
- [x] Kasbon/panjar yang mengeluarkan uang tercatat juga sebagai `kas_keluar`.
- [x] Pengembalian kasbon/panjar tercatat juga sebagai `kas_masuk`.
- [x] Potongan kwitansi tidak double count untuk panjar mitra baru yang tersambung ke ledger. Settlement advanced tetap Fase 3.
- [ ] Kasbon melewati batas butuh role owner/super_admin atau ditolak.
- [ ] Histori panjar mitra lama tetap bisa ditelusuri setelah migrasi.

### P0B.6 Biaya Bantuan Mitra dan Armada

- [x] Tambah migration non-destruktif untuk sopir aktual per pengiriman: `sopir_aktual_id`, snapshot nama/no HP, source master/manual, dan flag berbeda dari default.
- [x] MVP: afiliasi default sopir/armada dibuat opsional dan tidak mengunci `mitra_id` transaksi.
- [ ] Tambah/rapikan relasi default sopir-armada sebagai default/assignment, bukan kebenaran transaksi.
- [ ] Buat/update `biaya_operasional` dengan `tipe_biaya`.
- [ ] Buat `tarif_armada` dengan tanggal berlaku.
- [ ] Hitung biaya armada: `max(jarak_km x tonase_ton x tarif_per_km_per_ton, minimum_charge)`.
- [ ] Override tarif wajib alasan dan audit log.
- [ ] Bedakan biaya aktual perusahaan vs biaya dibebankan ke mitra.

Acceptance:

- [ ] Biaya bantuan mitra tidak mengurangi laba dua kali.
- [ ] Potongan armada tampil di settlement.
- [x] Perubahan sopir default armada tidak mengubah sopir aktual pada pengiriman/settlement lama.

### P0B.7 Pembayaran dan Bukti Mitra

Dependency:

- Settlement mitra sudah menghasilkan snapshot final.
- `kas_ledger` sudah siap mencatat pembayaran mitra sebagai uang keluar.
- Reversal pembayaran sudah jelas sebelum fitur batal pembayaran dibuka.

- [x] Buat `pembayaran_mitra`.
- [x] Buat `bukti_pembayaran`.
- [ ] Buat UI pembayaran mitra.
- [ ] Tambah status pembayaran mitra.
- [ ] Generate bukti pembayaran mitra PDF/gambar untuk WhatsApp.
- [ ] Nomor bukti unik.
- [ ] Bukti bisa diunduh/cetak ulang.

Acceptance:

- [ ] Bukti berisi DO, mitra, pabrik, tonase, harga, fee, potongan, total hak, status.
- [ ] Settlement lunas setelah pembayaran dicatat penuh.

## P0C - Kontrol, Audit, dan Laporan Owner

Tujuan: sistem aman untuk dipakai serius, laporan owner jelas, dan transaksi bisa diaudit.

### P0C.1 Audit Log

- [x] Buat helper audit log.
- [ ] Catat before/after JSON untuk perubahan penting.
- [ ] Catat actor, role, alasan, approved_by, approved_at.
- [ ] Audit aksi: create, update, cancel, approve, override, export.

Acceptance:

- [ ] Override tarif/harga, kasbon melewati batas, koreksi stok, dan batal transaksi selalu masuk audit.

### P0C.2 Reversal and Cancel Flow

- [ ] Ganti delete transaksi di UI menjadi cancel/reversal.
- [ ] Pembelian batal membuat reversal stok dan hutang.
- [ ] Pengiriman batal membuat reversal stok keluar.
- [ ] Pembayaran batal membatalkan alokasi.
- [ ] Settlement batal membatalkan status dan pembayaran terkait sesuai aturan.

Acceptance:

- [ ] Tidak ada delete fisik untuk transaksi finansial/ledger.
- [ ] Audit log menyimpan alasan batal.

### P0C.3 Laporan Owner

- [ ] Update dashboard owner.
- [x] Update `/laporan/laba-rugi`.
- [x] Tambah `/owner/pendapatan-owner` untuk rekap Fee Owner bruto MVP dari transaksi mitra.
- [x] Tambah klasifikasi mitra/grup internal owner vs mitra eksternal di laporan owner.
- [x] Tampilkan Laba Bersih Kas sebagai angka utama.
- [x] Tampilkan Laba Estimasi Transaksi sebagai pembanding.
- [ ] Pisahkan lokal dan mitra.
- [ ] Tampilkan dampak sortasi lokal.
- [x] Tampilkan Fee Owner bruto mitra dari snapshot transaksi MVP.
- [ ] Tampilkan potongan armada, biaya aktual, koreksi selisih.
- [x] Tambahkan laporan kas masuk/keluar per rekening dan periode dari `kas_ledger` melalui `/keuangan/kas`.
- [x] Tambahkan laporan saldo hutang/panjar per pihak dari ledger universal melalui `/keuangan/hutang`.
- [ ] Tambahkan rekonsiliasi pembayaran pabrik: tagihan DO vs uang aktual diterima.
- [x] Sembunyikan dari admin biasa.

Acceptance:

- [x] Owner/super_admin melihat laporan pendapatan owner bruto.
- [ ] Owner/super_admin melihat laba-rugi.
- [ ] Admin operasional/admin keuangan tidak bisa melihat laba-rugi.
- [x] Admin operasional/admin keuangan tidak melihat menu Pendapatan Owner Bruto.
- [ ] Dashboard owner menampilkan basis kas sebagai angka utama.
- [x] Label basis kas/transaksi jelas.
- [x] Owner/super_admin bisa melihat total uang masuk, uang keluar, dan net periode per rekening. Saldo awal/akhir tutup kas masuk Fase 3.
- [ ] Owner/super_admin bisa membedakan pendapatan bruto, kas diterima, dan uang yang masih belum dibayar pabrik.

### P0C.4 Laporan Operasional

- [ ] Update dashboard umum untuk ringkasan lokal dan mitra secara terpisah.
- [ ] Update laporan harian sesuai prioritas PRD.
- [ ] Tambah laporan pabrik per DO.
- [ ] Tambah laporan mitra.
- [ ] Tambah laporan stok lokal.
- [ ] Tambah ekspor laporan operasional tanpa laba-rugi sesuai role.

Acceptance:

- [ ] Laporan harian menampilkan kas, stok/TBS lokal, DO pabrik, settlement mitra, hutang/kasbon.
- [ ] Laporan mitra menampilkan anomali tonase.

### P0C.5 Security Verification and Release Gate

- [ ] Review ulang seluruh policy setelah kas, hutang universal, settlement, dan laporan selesai.
- [ ] Pastikan tidak ada policy baru yang kembali ke pola full access.
- [ ] Pastikan admin biasa tidak bisa query data laba-rugi/margin.
- [ ] Pastikan owner tidak bisa manage user/role.
- [ ] Pastikan super_admin bisa manage user/role.
- [ ] Jalankan test manual role sebelum deploy production.
- [ ] Backup production sebelum deploy migration besar.
- [ ] Siapkan rollback checklist untuk policy/RPC jika ada role yang gagal akses.
- [x] Jalankan `supabase db lint` level error setelah migration Fase 2 dan bersihkan error function/schema yang muncul.

Acceptance:

- [ ] Tes manual query untuk semua role berbeda sudah didokumentasikan.
- [ ] UI hiding tidak menjadi satu-satunya kontrol; RLS/backend tetap membatasi.
- [ ] Tidak ada regression pada modul live: input pengiriman, kwitansi, laporan mitra, pembayaran kwitansi, pembelian petani, dan stok lokal.

### P0C.6 Encoding and UI Cleanup

- [x] Perbaiki teks/icon yang rusak encoding di sidebar, dashboard, dan halaman transaksi (mengganti ikon huruf statis PB, MT, TB dengan lucide-react SVGs).
- [x] Perbaikan layout responsive khusus mode HP dan Tablet (tabel overflow, padding form input, date filter side-by-side).
- [x] Menerapkan overlay pengunci "Tahap 2: Dalam Pengembangan" untuk semua halaman dan widget fitur Tahap 2.
- [x] Membuka halaman Fase 2 minimum yang sudah siap dipakai dan menyesuaikan sidebar berdasarkan role keuangan/owner.
- [x] Hapus judul konten duplikat di halaman utama; title halaman cukup dari AppShell/top bar, area konten menyisakan deskripsi, filter, dan aksi.
- [x] Perbesar logo kwitansi cetak dan preview pengaturan web agar proporsinya lebih dominan dan seimbang dengan judul kwitansi.
- [ ] Pastikan label UI memakai istilah final: petani lokal, mitra, DO, settlement, kasbon, laba kas, laba estimasi.
- [ ] Pastikan menu dan judul halaman mengikuti role baru.

Acceptance:

- [ ] Tidak ada karakter rusak di navigasi utama dan laporan.
- [ ] Istilah UI konsisten dengan `PRD-final.md`.

## P1 - Operasional Harian

- [ ] Laporan per mitra lengkap.
- [ ] Laporan pabrik per DO lengkap.
- [ ] Riwayat tarif armada dan override.
- [ ] Bukti pembayaran mitra PDF/gambar final polish.
- [ ] Laporan stok lokal dengan filter periode.
- [ ] Ekspor laporan operasional sesuai role.

## P2 - Lanjutan

- [ ] Upload foto tiket timbang/DO.
- [ ] Multi-lokasi timbang.
- [ ] Ekspor Excel settlement mitra.
- [ ] Dashboard owner dengan margin per sumber.
- [ ] Template WhatsApp otomatis.
- [ ] Rekonsiliasi lanjutan pola anomali timbang.

## Urutan Eksekusi Disarankan

Mapping fase:

- **Fase 1 berjalan sekarang:** pertahankan modul MVP live dan hanya patch bug/security kecil yang sudah teruji.
- **Fase 2 tercapai setelah langkah 1-11 selesai:** ini batas sistem bisnis minimal.
- **Fase 3 tercapai setelah langkah 12-17 selesai:** ini batas sistem operasional lengkap.
- **Fase 4 mencakup P2, polish, otomasi, monitoring, dan SOP production:** ini batas aplikasi utuh dan matang.

1. Inventory keamanan: matrix akses tabel/RPC/route, daftar policy full access, daftar RPC `SECURITY DEFINER`, dan daftar delete fisik tersisa.
2. Staging safety: backup production, uji migration di staging, dan siapkan rollback checklist.
3. Role/RLS dasar final untuk modul live: login, dashboard, input pengiriman, kwitansi mitra, laporan mitra, panjar, pembelian petani, stok, dan laba-rugi.
4. Reversal/delete cleanup untuk modul finansial live: panjar, biaya, pembayaran, dan transaksi yang berdampak ledger.
5. Pengaturan bisnis dasar dan audit perubahan pengaturan.
6. Finalisasi alur lokal yang sudah ada: pembelian petani, stok ledger, pengiriman lokal, sortasi lokal di laporan owner.
7. Pembayaran pabrik dasar: UI alokasi satu pembayaran ke satu/banyak DO, validasi alokasi, dan status pembayaran DO.
8. Buku Kas: `rekening_kas`, `kas_ledger`, uang masuk pabrik, uang keluar dasar, koreksi/reversal kas.
9. Hutang/panjar universal: petani, mitra, sopir, karyawan, pihak lain; integrasi dengan `kas_ledger`.
10. Mapping master mitra: putuskan sumber kebenaran `master_mitra` MVP vs `mitra` final sebelum settlement final.
11. Pembayaran mitra dasar: status bayar dari kwitansi/panjar masuk ke `kas_ledger`, tanpa menunggu settlement advanced.
12. Fee history dan pengaturan bisnis settlement: fee, persentase selisih, toleransi anomali, limit kasbon.
13. Formula settlement mitra + unit test sebelum UI settlement.
14. Biaya armada/bantuan mitra dan tarif armada history.
15. UI settlement dan pembayaran mitra final, termasuk bukti pembayaran/kwitansi.
16. Audit/reversal menyeluruh untuk stok, kas, hutang, pembayaran, settlement, dan pengaturan.
17. Laporan owner dan operasional berbasis Buku Kas: kas, DO pabrik, hutang/panjar, settlement, laba kas, laba estimasi.
18. Security verification/release gate sebelum production.
19. Cleanup encoding, label final, dan polish UI.

## Test Wajib Sebelum Release P0

- [ ] Semua migration Tahap 2 diuji di staging sebelum production.
- [ ] Backup production tersedia sebelum migration production.
- [ ] Owner tidak bisa mengelola user/role.
- [ ] Super admin bisa mengelola user/role.
- [ ] Admin operasional tidak bisa query tabel/field laba, profit, margin, dan pendapatan owner.
- [ ] Admin keuangan tidak bisa query tabel/field laba, profit, margin, dan pendapatan owner.
- [ ] RPC sensitif tidak bisa dipanggil oleh `anon` atau role yang tidak berhak.
- [ ] Tidak ada policy tabel finansial yang memberi write access bebas ke semua authenticated users.
- [ ] Dua transaksi beli bersamaan tidak bentrok nomor struk.
- [ ] Dua pengiriman lokal bersamaan tidak over-allocate stok.
- [ ] Hutang petani tidak double count setelah potong TBS.
- [x] Hutang/panjar petani, mitra, sopir, karyawan, dan pihak lain dihitung dari ledger universal untuk transaksi baru.
- [x] Hutang/panjar mitra tidak double count setelah kwitansi untuk flow Fase 2 minimum. Settlement advanced belum diuji.
- [x] Kasbon/panjar keluar tercatat di ledger pihak dan `kas_ledger`.
- [x] Pengembalian kasbon/panjar tercatat di ledger pihak dan `kas_ledger`.
- [x] Pembayaran pabrik tercatat sebagai uang masuk aktual dan bisa ditelusuri ke DO/pengiriman dasar. Alokasi multi-DO belum selesai.
- [x] Laba Kas tidak memasukkan DO yang belum benar-benar dibayar pabrik.
- [ ] Persentase selisih tonase tidak bisa disimpan jika totalnya bukan 100%.
- [ ] Settlement sortasi kg tidak double count.
- [ ] Settlement sortasi percent membagi 100 dengan benar.
- [ ] Fee mitra berubah tidak mengubah settlement lama.
- [ ] Tarif armada berubah tidak mengubah pengiriman lama.
- [ ] Sopir default armada berubah tidak mengubah sopir aktual DO lama.
- [ ] Pengiriman bisa disimpan saat sopir aktual berbeda dari sopir default armada.
- [ ] DO duplikat per pabrik ditolak saat bukan draft.
- [ ] Admin biasa tidak bisa melihat laba-rugi lewat UI maupun query.
- [ ] Batal transaksi membuat reversal, bukan delete.
