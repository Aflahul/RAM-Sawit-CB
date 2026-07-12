# Implementation Tasks - Sawit CB

Dokumen ini menurunkan `PRD-final.md` menjadi task implementasi teknis berdasarkan kondisi repo saat ini.

## 0. Kondisi Saat Ini (MVP Tahap 1 Selesai)

Semua fitur MVP (Tahap 1) terkait **Pengiriman Mitra ke Pabrik** telah selesai dibangun. 
Modul yang sudah live dan beroperasi:
- **Master Data MVP:** `master_mitra`, `sopir` (dengan afiliasi mitra).
- **Pengiriman Mitra:** Menggunakan `transaksi_mitra` dengan pemotongan Fee/DO tersembunyi (Skenario B) dengan `harga_tbs` (Harga Pabrik/TWB).
- **Panjar Mitra:** Menggunakan `panjar_mitra` dengan tombol *Quick Add*.
- **Kwitansi Mitra:** Pemotongan panjar otomatis.
- **Laporan Mitra:** Rekapitulasi global transaksi Mitra.

### Panduan Environment (PENTING UNTUK TAHAP 2)
Untuk menjaga integritas data operasional MVP (Tahap 1) yang sudah mulai digunakan oleh Owner:
1. Pengerjaan Tahap 2 **WAJIB** menggunakan database *Development / Staging* yang terpisah dari *Production*.
2. Segala skema/tabel baru (`petani_lokal`, dll) dibuat dan diuji di database *Development* terlebih dahulu.
3. Migrasi ke *Production* wajib berupa *Non-Destructive Migration* (hanya menambah tabel/kolom, tidak menghapus/mengubah struktur tabel MVP yang sudah berjalan).
4. Lakukan *Backup* database *Production* di Supabase sebelum me-release Tahap 2.

Langkah selanjutnya adalah melanjutkan pengembangan **Tahap 2 (P0A - Fondasi dan Alur Lokal)** untuk mengakomodir pembelian dari Petani Lokal.

Stack:

- Next.js App Router
- React client components
- Supabase JS client
- Supabase/PostgreSQL schema di `supabase-schema.sql`

Schema saat ini masih versi awal:

- Role hanya `owner` dan `admin`.
- `petani` masih menjadi pemasok umum dan belum dipisah dari mitra.
- Harga TBS masih harian di `harga_tbs`.
- Hutang masih memakai `hutang` + `hutang_log`, belum ledger tunggal.
- Pengiriman belum punya `sumber` lokal/mitra.
- Pembayaran pabrik masih menempel di `pengiriman`.
- Belum ada settlement mitra.
- Belum ada stok ledger.
- RLS masih memberi akses penuh ke semua authenticated users.

Prinsip implementasi:

- Kerjakan migration database dulu sebelum UI besar.
- Jangan delete transaksi yang berdampak ke stok, hutang, kas, atau settlement; gunakan status/reversal.
- Buat fungsi/formula settlement sebagai unit test sebelum UI settlement.
- Jaga kompatibilitas data lama dengan migration yang eksplisit.

## P0A - Fondasi dan Alur Lokal

Tujuan: alur pembelian petani lokal, stok sementara, pengiriman lokal, pembayaran pabrik dasar, role awal, dan reversal aman.

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

- [x] Tambah helper role di frontend/backend.
- [x] Update `AppShell`, `Sidebar`, dan route guard untuk role baru.
- [x] Owner tidak bisa kelola user/role.
- [ ] Super admin bisa semua termasuk user/role.
- [x] Admin operasional tidak bisa melihat laba-rugi.
- [x] Admin keuangan tidak bisa melihat laba-rugi.
- [x] Ganti RLS full access dengan policy berbasis role.

Acceptance:

- [x] Menu laba-rugi hanya terlihat untuk owner/super admin.
- [ ] Menu pengaturan user hanya terlihat untuk super admin.
- [ ] Query Supabase untuk tabel sensitif ditolak untuk role yang tidak berhak.

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

- [x] Buat `pembayaran_pabrik`.
- [x] Buat `pembayaran_pabrik_detail`.
- [ ] Update UI pembayaran pabrik agar satu pembayaran bisa dialokasikan ke satu atau banyak DO.
- [ ] Bedakan `total_pembayaran_pabrik` sebagai nilai tagihan DO vs `total_bayar` sebagai uang aktual diterima.
- [ ] Cegah alokasi melebihi nilai tagihan DO.

Acceptance:

- [ ] Status pembayaran DO dihitung dari alokasi pembayaran.
- [ ] Laba Bersih Kas memakai uang aktual dari pembayaran pabrik detail.
- [ ] DO belum dibayar tidak masuk laba kas.

## P0B - Alur Mitra dan Settlement

Tujuan: pisahkan mitra, pengiriman mitra, settlement per DO, fee history, kasbon mitra, biaya armada, dan bukti pembayaran.

### P0B.0 Pengaturan Bisnis

- [ ] Buat UI `/pengaturan/bisnis`.
- [x] Simpan default fee mitra per kg.
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

### P0B.2 Fee Mitra History

- [x] Buat `fee_mitra_history`.
- [ ] Tambahkan UI set fee per kg dengan tanggal/jam berlaku.
- [ ] Settlement mengambil fee berdasarkan tanggal pengiriman/DO.
- [ ] Perubahan fee tidak mengubah settlement lama.

Acceptance:

- [ ] DO lama tetap memakai fee lama.
- [ ] DO baru memakai fee yang berlaku.

### P0B.3 Pengiriman Mitra (Sesuai MVP Terbaru)

- [ ] Buat route `/admin/input-timbangan` (Khusus Admin Lapangan, UI Mobile-Friendly).
- [ ] Input berfokus pada pemilihan **Nama Sopir**.
- [ ] Implementasikan auto-fill: Saat Sopir dipilih, **Plat Armada** dan **Afiliasi Mitra** otomatis terisi.
- [ ] Input tonase pabrik/timbangan.
- [ ] Buat route `/owner/kwitansi-mitra` untuk mencetak Kwitansi per Mitra.
- [ ] Kwitansi harus menjumlahkan total tonase afiliasi mitra, dikali harga, lalu **dikurangi Panjar** (dari tabel kasbon/hutang) untuk mendapat Sisa Bayar Bersih.
- [ ] Deteksi anomali jika `tonase_dasar_settlement > tonase_timbang_mitra` melewati toleransi.

Acceptance:

- [ ] Pengiriman mitra tidak mengubah stok lokal.
- [ ] Pengiriman mitra bisa lanjut menjadi settlement setelah pembayaran pabrik/DO final.
- [ ] Anomali tampil di laporan mitra.

### P0B.4 Settlement Mitra Formula

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

### P0B.5 Hutang/Kasbon Mitra

- [ ] Update ledger agar mendukung `pihak_type = mitra`.
- [ ] Tambah form kasbon mitra.
- [ ] Tambah batas kasbon per mitra.
- [ ] Implement `blokir_otomatis` atau `wajib_approval` sesuai pengaturan bisnis.
- [ ] Potong kasbon mitra saat settlement.

Acceptance:

- [ ] Saldo kasbon mitra dihitung dari `hutang_ledger`.
- [ ] Potongan settlement tidak double count.
- [ ] Kasbon melewati batas butuh role owner/super_admin atau ditolak.

### P0B.6 Biaya Bantuan Mitra dan Armada

- [ ] Buat/update `biaya_operasional` dengan `tipe_biaya`.
- [ ] Buat `tarif_armada` dengan tanggal berlaku.
- [ ] Hitung biaya armada: `max(jarak_km x tonase_ton x tarif_per_km_per_ton, minimum_charge)`.
- [ ] Override tarif wajib alasan dan audit log.
- [ ] Bedakan biaya aktual perusahaan vs biaya dibebankan ke mitra.

Acceptance:

- [ ] Biaya bantuan mitra tidak mengurangi laba dua kali.
- [ ] Potongan armada tampil di settlement.

### P0B.7 Pembayaran dan Bukti Mitra

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
- [x] Tampilkan Laba Bersih Kas sebagai angka utama.
- [x] Tampilkan Laba Estimasi Transaksi sebagai pembanding.
- [ ] Pisahkan lokal dan mitra.
- [ ] Tampilkan dampak sortasi lokal.
- [ ] Tampilkan fee mitra, potongan armada, biaya aktual, koreksi selisih.
- [x] Sembunyikan dari admin biasa.

Acceptance:

- [ ] Owner/super_admin melihat laba-rugi.
- [ ] Admin operasional/admin keuangan tidak bisa melihat laba-rugi.
- [ ] Dashboard owner menampilkan basis kas sebagai angka utama.
- [x] Label basis kas/transaksi jelas.

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

### P0C.5 RLS and Security

- [ ] Ganti policy full access.
- [ ] Implement policy per role.
- [ ] Pastikan admin biasa tidak bisa query data laba-rugi/margin.
- [ ] Pastikan owner tidak bisa manage user/role.
- [ ] Pastikan super_admin bisa manage user/role.

Acceptance:

- [ ] Tes manual query untuk role berbeda.
- [ ] UI hiding tidak menjadi satu-satunya kontrol; RLS/backend tetap membatasi.

### P0C.6 Encoding and UI Cleanup

- [ ] Perbaiki teks/icon yang rusak encoding di sidebar, dashboard, dan halaman transaksi.
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

1. Migration schema P0A.
2. Role/RLS dasar.
3. Pengaturan bisnis dasar.
4. Pembelian petani + stok ledger.
5. Pengiriman lokal + pembayaran pabrik.
6. Master mitra + fee history.
7. Pengiriman mitra.
8. Formula settlement + unit test.
9. Hutang/kasbon mitra.
10. Biaya armada/bantuan mitra.
11. Pembayaran dan bukti mitra.
12. Audit/reversal menyeluruh.
13. Laporan owner dan operasional.
14. Cleanup encoding/icon.

## Test Wajib Sebelum Release P0

- [ ] Owner tidak bisa mengelola user/role.
- [ ] Super admin bisa mengelola user/role.
- [ ] Dua transaksi beli bersamaan tidak bentrok nomor struk.
- [ ] Dua pengiriman lokal bersamaan tidak over-allocate stok.
- [ ] Hutang petani tidak double count setelah potong TBS.
- [ ] Hutang mitra tidak double count setelah settlement.
- [ ] Persentase selisih tonase tidak bisa disimpan jika totalnya bukan 100%.
- [ ] Settlement sortasi kg tidak double count.
- [ ] Settlement sortasi percent membagi 100 dengan benar.
- [ ] Fee mitra berubah tidak mengubah settlement lama.
- [ ] Tarif armada berubah tidak mengubah pengiriman lama.
- [ ] DO duplikat per pabrik ditolak saat bukan draft.
- [ ] Admin biasa tidak bisa melihat laba-rugi lewat UI maupun query.
- [ ] Batal transaksi membuat reversal, bukan delete.
