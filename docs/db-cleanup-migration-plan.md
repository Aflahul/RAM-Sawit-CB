# Rencana Pembersihan dan Migrasi Database - Sawit CB

Tanggal rencana: 14 Juli 2026

Dokumen ini menjadi rencana aman untuk merapikan tabel lama, menyatukan sumber data UI, dan menyiapkan opsi database baru yang bersih tanpa merusak database produksi.

## 1. Prinsip Utama

- **Tidak ada `DROP TABLE` langsung di produksi.** Semua tabel lama harus melewati tahap audit, freeze, archive, validasi, lalu baru boleh dipertimbangkan untuk drop.
- **Satu sumber data kanonik per proses bisnis.** UI tidak boleh mengambil sebagian dari tabel MVP lama dan sebagian dari tabel fase baru untuk workflow yang sama.
- **Ledger tetap menjadi sumber uang, hutang, dan stok.** Nilai kas, sisa hutang/panjar, dan stok dihitung dari mutasi.
- **Migrasi harus bisa dibatalkan.** Setiap perubahan struktur harus punya backup, migration rollback, dan catatan data sebelum/sesudah.
- **Tabel baru hanya dibuat jika mengurangi kebingungan workflow.** Jangan menambah tabel hanya karena UI butuh label baru.
- **Supabase security wajib ikut migrasi.** Tabel/RPC baru harus punya RLS, policy, grant, dan role check yang jelas. Catatan Supabase: perubahan Data API terbaru membuat tabel baru perlu diekspos/diberi akses secara sadar, jadi jangan asumsikan tabel baru otomatis tersedia untuk API.

Referensi: https://supabase.com/changelog

Audit database aktual yang sudah dijalankan: [`docs/db-actual-audit-2026-07-14.md`](./db-actual-audit-2026-07-14.md).

## 2. Masalah yang Terlihat Saat Ini

Masalah utama bukan sekadar ada tabel lama, tetapi ada risiko UI membaca sumber data berbeda untuk konsep bisnis yang sama.

Contoh yang sudah terlihat:

| Area | Sumber Baru yang Diinginkan | Sumber Lama yang Masih Ada | Risiko |
| --- | --- | --- | --- |
| Pengiriman mitra/internal | `transaksi_mitra` | `pengiriman`, `pengiriman_lokal_detail` | Dashboard/laporan bisa tidak sinkron bila sebagian halaman membaca tabel lama. |
| Armada internal/perusahaan | `master_mitra` tipe internal + `sopir.mitra_id` + `sopir.plat_nomor` | `armada_perusahaan`, `kendaraan`, `sopir.armada_perusahaan_id`, `sopir.kendaraan_id` | Armada perusahaan tidak perlu menu terpisah karena sudah diwakili mitra internal. |
| Master mitra | `master_mitra` | `mitra` | Fee, tipe mitra internal, dan kwitansi bisa tidak lengkap jika masih membaca tabel lama. |
| Fee mitra/owner | `fee_owner_mitra_history` | `fee_mitra_history` | Perhitungan pendapatan owner bisa memakai riwayat fee yang berbeda. |
| Panjar mitra | `hutang_ledger` + `panjar_mitra` | input panjar terpisah | User bingung karena ada dua pintu input. |
| Kas aktual | `kas_ledger` | nominal uang di tabel transaksi | Laba/rugi bisa tercampur antara estimasi dan uang aktual. |

Keputusan UX terbaru: panjar cukup satu pintu lewat `Keuangan -> Hutang & Panjar Semua Pihak`. `panjar_mitra` tetap dipakai sebagai tabel pendukung agar kwitansi mitra dapat memotong panjar otomatis.

## 3. Klasifikasi Tabel

### 3.1 Tabel Kanonik yang Dipertahankan

Tabel berikut menjadi sumber utama aplikasi saat ini dan arah pengembangan berikutnya:

| Tabel | Peran |
| --- | --- |
| `users` | Profil role aplikasi yang terhubung ke Supabase Auth. |
| `petani` | Master petani lokal. |
| `master_mitra` | Master mitra eksternal dan mitra internal owner. |
| `sopir` | Master sopir, termasuk default sopir/plat untuk mitra. |
| `pabrik` | Master pabrik tujuan. |
| `harga_tbs_lokal` | Harga beli petani lokal berdasarkan tanggal berlaku. |
| `harga_tbs` | Harga pabrik/TWB saat ini. Untuk DB v2 sebaiknya dinamai lebih jelas sebagai harga pabrik. |
| `fee_owner_mitra_history` | Riwayat fee owner per mitra dan tanggal berlaku. |
| `transaksi_beli_tbs` | Pembelian TBS dari petani lokal. |
| `stok_tbs_lokal_ledger` | Mutasi stok lokal. |
| `transaksi_mitra` | Pengiriman mitra, termasuk mitra internal. |
| `pembayaran_mitra_kwitansi` | Batch pembayaran/kwitansi mitra. |
| `pembayaran_mitra_kwitansi_item` | Detail transaksi yang masuk kwitansi. |
| `panjar_mitra` | Pendukung potongan panjar mitra di kwitansi. Bukan pintu input UI. |
| `rekening_kas` | Master rekening/kotak kas. |
| `kas_ledger` | Buku mutasi kas aktual. |
| `hutang_ledger` | Buku mutasi hutang/panjar semua pihak. |
| `biaya_operasional` | Biaya operasional dengan relasi ke kas ledger. |
| `pengaturan_bisnis` | Konfigurasi bisnis dan branding. |
| `bukti_pembayaran` | Rencana/lapisan bukti pembayaran. Perlu distandarkan dengan lampiran transaksi. |
| `audit_log` | Jejak perubahan penting. |

### 3.2 Tabel Legacy / Freeze Candidate

Tabel ini jangan dihapus dulu, tetapi sebaiknya dibekukan dari workflow utama:

| Tabel | Status Rekomendasi | Syarat Sebelum Archive/Drop |
| --- | --- | --- |
| `pengiriman` | Legacy arsip pengiriman lokal. | Pastikan semua pengiriman aktif sudah masuk `transaksi_mitra` sebagai mitra internal. |
| `pengiriman_lokal_detail` | Legacy detail pengiriman lokal. | Migrasikan relasi stok/tonase yang masih dibutuhkan untuk laporan historis. |
| `armada_perusahaan` | Legacy/dormant armada perusahaan. | Sembunyikan dari UI aktif. Pertahankan sementara karena masih ada FK dari `sopir`, `pengiriman`, dan `tarif_armada`. |
| `kendaraan` | Legacy armada lama. | Pastikan semua UI/RPC aktif memakai mitra internal dan `sopir.plat_nomor`; mapping plat lama selesai. |
| `mitra` | Legacy master mitra awal. | Bandingkan row dengan `master_mitra`; pastikan tidak ada FK aktif ke `mitra`. |
| `armada_mitra` | Legacy/parsial armada mitra. | Jika default sopir/plat sudah ditangani `sopir.mitra_id` dan `sopir.plat_nomor`, archive. |
| `fee_mitra_history` | Legacy fee lama. | Pastikan seluruh perhitungan owner memakai `fee_owner_mitra_history`. |
| `transaksi_beli` | Legacy pembelian lama. | Jika masih ada data historis, migrasikan atau jadikan archive read-only. |
| `hutang`, `hutang_log` | Legacy hutang lama. | Migrasikan mutasi penting ke `hutang_ledger` atau archive read-only. |

### 3.3 Tabel Dormant / Perlu Diputuskan

Tabel ini tidak otomatis legacy, tetapi harus diputuskan fungsinya sebelum dipakai luas:

| Tabel | Kemungkinan Fungsi | Rekomendasi |
| --- | --- | --- |
| `pembayaran_pabrik` | Uang masuk dari pabrik versi desain lama. | Archive/legacy setelah flow baru `pembayaran_pabrik_batch` aktif. |
| `pembayaran_pabrik_detail` | Detail pembayaran pabrik versi desain lama. | Archive/legacy karena mengarah ke `pengiriman` lama, bukan catatan timbang mitra aktif. |
| `settlement_mitra` | Settlement final mitra per DO/periode. | Masuk Fase 3, jangan dicampur dengan kwitansi MVP sebelum desain final. |
| `pembayaran_mitra` | Pembayaran mitra versi awal. | Jika kwitansi sudah menjadi jalur utama, archive atau jadikan kompatibilitas sementara. |
| `tarif_armada` | Tarif armada perusahaan. | Dormant. Pakai lagi hanya jika Fase 3 membutuhkan tarif armada internal yang tidak cukup direpresentasikan oleh mitra internal. |

## 4. Tabel Baru yang Direkomendasikan

Tabel baru sebaiknya dibuat setelah alur P1/P2 stabil. Prioritasnya:

| Prioritas | Tabel Baru | Tujuan |
| --- | --- | --- |
| P1 | `karyawan` | Supaya kasbon/talangan karyawan tidak memakai nama manual terus-menerus. |
| P1 | `lampiran_transaksi` | Satu tabel bukti untuk tiket timbang, DO, kwitansi, transfer, dan foto dokumen. |
| P2 | `tutup_hari` | Mengunci periode harian setelah kas, stok, hutang, biaya, dan transaksi dicek. |
| P2 | `approval_request` | Approval untuk panjar/kasbon melewati limit, override harga/fee, dan koreksi besar. |
| P2 | `pembayaran_pabrik_batch` | Catatan uang masuk dari pabrik berdasarkan tonase bersih versi pabrik. |
| P2 | `pembayaran_pabrik_item` | Data timbang internal yang dicocokkan dengan satu pembayaran pabrik. |
| P3 | `settlement_mitra_item` | Settlement final per transaksi/DO, termasuk beda tonase, panjar, biaya bantuan, dan koreksi yang disetujui. |
| P3 | `data_migration_map` | Mapping ID lama ke ID baru saat migrasi dari legacy atau DB lama ke DB v2. |

Catatan desain:

- `karyawan` sebaiknya minimal punya `nama`, `no_hp`, `jabatan`, `aktif`, `created_at`, `updated_at`.
- `lampiran_transaksi` sebaiknya generik: `source_table`, `source_id`, `jenis`, `storage_path`, `nomor_ref`, `uploaded_by`, `created_at`.
- `tutup_hari` harus menyimpan tanggal, status, ringkasan kas/stok/hutang, user yang menutup, dan catatan exception.
- `approval_request` jangan menggantikan audit log; approval adalah workflow, audit log adalah jejak.

## 5. Rencana Cleanup Aman

### Fase A - Audit Tanpa Mengubah Data

1. Snapshot database produksi.
2. Jalankan audit row count semua tabel.
3. Jalankan audit dependency FK, view, function, trigger, dan policy.
4. Cocokkan referensi frontend: `.from(...)` dan `.rpc(...)`.
5. Tandai tabel sebagai `canonical`, `legacy`, `dormant`, atau `unknown`.
6. Buat laporan selisih data master lama vs baru.

Query audit awal:

```sql
select
  schemaname,
  relname as table_name,
  n_live_tup as estimated_rows,
  pg_size_pretty(pg_total_relation_size(relid)) as total_size
from pg_stat_user_tables
order by schemaname, relname;
```

```sql
select
  tc.table_schema,
  tc.table_name,
  kcu.column_name,
  ccu.table_name as foreign_table_name,
  ccu.column_name as foreign_column_name
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name
 and tc.table_schema = kcu.table_schema
join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name
 and ccu.table_schema = tc.table_schema
where tc.constraint_type = 'FOREIGN KEY'
order by tc.table_name, kcu.column_name;
```

### Fase B - Freeze Workflow Legacy

1. UI utama tidak lagi membuka input baru ke tabel legacy.
2. Route legacy diberi label arsip dan read-only bila memungkinkan.
3. RPC legacy tidak dipakai oleh menu utama.
4. Role/policy legacy dibatasi agar tidak ada insert baru dari workflow normal.
5. Export data legacy disiapkan untuk arsip.

Target freeze pertama:

- `pengiriman`
- `pengiriman_lokal_detail`
- `armada_perusahaan`
- `kendaraan`
- `mitra`
- `armada_mitra`
- `fee_mitra_history`
- `transaksi_beli`
- `hutang`
- `hutang_log`

### Fase C - Migrasi Data yang Masih Bernilai

Mapping yang perlu dibuat:

| Legacy | Target | Catatan |
| --- | --- | --- |
| `mitra` | `master_mitra` | Samakan nama/kode/no HP; isi `tipe_mitra` jika internal. |
| `armada_perusahaan` / `kendaraan` | `master_mitra` tipe internal + `sopir.plat_nomor` | Jika datanya masih bernilai, jadikan mitra internal atau plat default sopir; jangan buka menu armada terpisah. |
| `pengiriman` sumber lokal | `transaksi_mitra` mitra internal | Hanya jika data historis masih diperlukan di laporan baru. |
| `transaksi_beli` | `transaksi_beli_tbs` | Migrasi hanya bila transaksi lama perlu muncul di laporan baru. |
| `hutang` + `hutang_log` | `hutang_ledger` | Migrasi sebagai saldo awal/mutasi historis, jangan overwrite ledger baru. |
| `fee_mitra_history` | `fee_owner_mitra_history` | Ambil tanggal berlaku dan nominal fee yang valid. |

Validasi migrasi:

```sql
-- Transaksi mitra tanpa master mitra valid
select tm.id, tm.mitra_id
from transaksi_mitra tm
left join master_mitra mm on mm.id = tm.mitra_id
where tm.mitra_id is not null
  and mm.id is null;
```

```sql
-- Sopir yang belum terhubung ke mitra internal/eksternal
select s.id, s.nama, s.mitra_id, s.plat_nomor
from sopir s
left join master_mitra mm on mm.id = s.mitra_id
where s.mitra_id is null
   or mm.id is null;
```

```sql
-- Panjar mitra yang tidak punya ledger hutang pendukung
select pm.id, pm.mitra_id, pm.nominal, pm.status, pm.hutang_ledger_id
from panjar_mitra pm
where pm.status = 'aktif'
  and pm.hutang_ledger_id is null;
```

### Fase D - Archive Schema, Bukan Drop

Jika audit sudah bersih, pindahkan tabel legacy ke schema `archive` di staging lebih dulu:

```sql
create schema if not exists archive;
```

Contoh strategi:

```sql
alter table public.pengiriman set schema archive;
alter table public.pengiriman_lokal_detail set schema archive;
```

Aturan penting:

- Jangan lakukan ini di produksi sampai seluruh route/RPC tidak lagi membutuhkan tabel tersebut.
- Setelah pindah schema, test build, test smoke route, dan test laporan.
- Jika ada RPC lama yang masih butuh tabel itu, jangan archive dulu.
- Jika app masih butuh riwayat baca, buat view kompatibilitas read-only dengan nama yang jelas.

### Fase E - Drop Setelah Masa Stabil

Drop baru boleh setelah:

- Sudah ada backup yang bisa direstore.
- Tabel sudah masuk archive minimal 1-2 siklus laporan.
- Tidak ada error dari UI, RPC, Edge/API, atau laporan.
- Owner menyetujui bahwa data lama cukup sebagai export/archive.
- Ada migration rollback atau restore plan.

## 6. Opsi Database Baru yang Bersih

Opsi terbaik untuk jangka menengah adalah membuat DB v2 di project/staging baru, lalu melakukan cutover setelah tervalidasi. Ini lebih aman dibanding membersihkan produksi sambil jalan jika data lama terlalu campur.

### Kapan Pilih DB Baru

Pilih DB baru jika:

- Banyak tabel lama punya data tumpang tindih.
- Relasi FK lama sulit dipastikan.
- Ingin nama tabel dan kolom lebih rapi tanpa menahan kompatibilitas MVP.
- Ingin reset RLS/policy dari nol.
- Owner setuju ada periode paralel validasi.

Tetap pakai cleanup in-place jika:

- Data produksi masih kecil.
- Legacy hanya sedikit dan jelas.
- Tidak ingin risiko cutover env dan auth project.

### Desain Modul DB v2

Kelompok schema yang disarankan:

| Modul | Tabel Inti |
| --- | --- |
| Identity & Access | `users`, `role_permissions` opsional |
| Master | `petani`, `karyawan`, `master_mitra`, `sopir`, `pabrik` |
| Harga & Tarif | `harga_tbs_lokal`, `harga_tbs_pabrik`, `fee_owner_mitra_history`, `tarif_armada` |
| Operasi Lokal | `transaksi_beli_tbs`, `stok_tbs_lokal_ledger` |
| Operasi Mitra | `transaksi_mitra`, `settlement_mitra_item` |
| Keuangan | `rekening_kas`, `kas_ledger`, `hutang_ledger`, `biaya_operasional` |
| Pembayaran | `pembayaran_mitra_kwitansi`, `pembayaran_mitra_kwitansi_item`, `pembayaran_pabrik_batch`, `pembayaran_pabrik_item` |
| Kontrol | `approval_request`, `tutup_hari`, `audit_log`, `lampiran_transaksi`, `data_migration_map` |
| Konfigurasi | `pengaturan_bisnis` |

Perubahan nama yang direkomendasikan untuk DB v2:

| Nama Saat Ini | Nama Lebih Jelas |
| --- | --- |
| `harga_tbs` | `harga_tbs_pabrik` |
| `hutang_ledger` | tetap `hutang_ledger`, tetapi UI menyebut "Sisa Hutang/Panjar" |
| `panjar_mitra` | tetap, tetapi diberi komentar sebagai tabel potongan kwitansi |
| `transaksi_mitra` | tetap |
| `master_mitra` | tetap |

### Jalur Migrasi DB Baru

1. Buat project Supabase staging/DB v2.
2. Terapkan schema bersih dari migration baru.
3. Enable RLS semua tabel.
4. Buat policy dan RPC role-safe sebelum import data.
5. Import master data kanonik.
6. Import transaksi aktif dan data historis yang masih dibutuhkan.
7. Simpan mapping ID lama ke `data_migration_map`.
8. Jalankan validasi saldo kas, sisa hutang/panjar, stok, jumlah transaksi, dan kwitansi.
9. Jalankan aplikasi ke staging DB.
10. Bandingkan laporan produksi vs staging untuk periode yang sama.
11. Freeze input produksi saat cutover.
12. Export delta terakhir.
13. Import delta ke DB v2.
14. Ganti environment variable aplikasi.
15. Smoke test route utama.
16. Simpan DB lama read-only sebagai archive.

## 7. Validasi Sinkronisasi UI

Checklist yang harus lulus sebelum cleanup dianggap selesai:

| Halaman | Harus Membaca | Tidak Boleh Lagi Membaca |
| --- | --- | --- |
| Dashboard | `transaksi_mitra`, `transaksi_beli_tbs`, `kas_ledger`, `hutang_ledger`, `stok_tbs_lokal_ledger` | `pengiriman` untuk ringkasan aktif |
| Laporan Harian | `transaksi_mitra`, `transaksi_beli_tbs`, `biaya_operasional`, `stok_tbs_lokal_ledger` | `pengiriman` aktif |
| Laba Rugi | `kas_ledger` sebagai uang aktual | estimasi dari tabel legacy |
| Mitra | `master_mitra` | `mitra` |
| Armada | `sopir.mitra_id`, `sopir.plat_nomor` | `armada_mitra`, `armada_perusahaan`, `kendaraan` untuk input aktif |
| Hutang & Panjar | `hutang_ledger`, RPC `create_hutang_pihak`, RPC `create_panjar_mitra_kas` | input panjar dari halaman terpisah |
| Kwitansi Mitra | `transaksi_mitra`, `panjar_mitra`, `pembayaran_mitra_kwitansi` | `pembayaran_mitra` lama |

## 8. Acceptance Criteria

Rencana cleanup dianggap siap dieksekusi jika:

- Ada daftar tabel kanonik, legacy, dormant, dan unknown dari database aktual.
- Semua route aktif punya sumber data yang sama dengan tabel kanonik.
- Route legacy diberi label arsip atau dipindah ke admin-only.
- Tidak ada data baru masuk ke tabel legacy setelah tanggal freeze.
- Semua tabel baru punya migration, RLS, policy, index, dan audit/created_by jika perlu.
- Saldo kas dari `kas_ledger` cocok dengan laporan kas.
- Sisa Hutang/Panjar dari `hutang_ledger` cocok dengan halaman hutang.
- Stok dari `stok_tbs_lokal_ledger` cocok dengan laporan stok.
- Kwitansi yang sudah dibayar tidak berubah karena perubahan master harga/fee.
- Backup dan rollback sudah diuji di staging.

## 9. Rekomendasi Keputusan

Untuk kondisi sekarang, rekomendasi terbaik adalah:

1. **Jangan buat DB baru hari ini.** Lanjutkan cleanup in-place secara aman karena sebagian besar workflow utama sudah bisa diarahkan ke tabel kanonik.
2. **Freeze tabel legacy dulu.** Terutama `pengiriman`, `pengiriman_lokal_detail`, `armada_perusahaan`, `kendaraan`, `mitra`, `armada_mitra`, dan `fee_mitra_history`.
3. **Buat audit SQL dan laporan row count.** Ini wajib sebelum archive/drop.
4. **Rapikan UI sampai tidak ada halaman aktif yang membaca data campuran.**
5. **Siapkan DB v2 sebagai opsi staging setelah P1/P2 stabil.** DB v2 cocok untuk reset besar ketika settlement pabrik, tutup hari, approval, dan lampiran sudah final.

Dengan jalur ini, database produksi tetap aman, user tidak kehilangan histori, dan arah pengembangan tetap bersih.
