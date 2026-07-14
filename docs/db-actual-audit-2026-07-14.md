# Audit Database Aktual - 14 Juli 2026

Audit ini dilakukan read-only terhadap project Supabase linked `sawit-cb` (`yavntiympbrjlouzkhnl`) melalui `npx supabase db query --linked`.

## 1. Lingkup Audit

Yang berhasil dicek:

- Postgres remote berjalan di versi `17.6`.
- Exact row count semua tabel `public`.
- RLS aktif/tidak aktif per tabel.
- Policy ringkas per tabel.
- Dependency FK khusus tabel legacy/arsip.
- Referensi tabel dari frontend melalui pencarian `.from(...)` dan `.rpc(...)`.

Catatan batasan:

- Query REST memakai `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` menampilkan `0` row untuk semua tabel karena tidak ada session user; ini tidak dipakai sebagai row count final.
- Beberapa query introspeksi panjang kadang gagal dengan pesan `SUPABASE_DB_PASSWORD` diperlukan untuk temp role. Query yang lebih kecil berhasil dan cukup untuk keputusan freeze UI.
- Tidak ada query tulis, migration, atau perubahan data database yang dijalankan.

## 2. Exact Row Count Tabel Public

| Tabel | Row |
| --- | ---: |
| `armada_mitra` | 0 |
| `armada_perusahaan` | 1 |
| `audit_log` | 7 |
| `biaya_operasional` | 1 |
| `bukti_pembayaran` | 0 |
| `fee_mitra_history` | 0 |
| `fee_owner_mitra_history` | 31 |
| `harga_tbs` | 3 |
| `harga_tbs_lokal` | 2 |
| `hutang` | 0 |
| `hutang_ledger` | 0 |
| `hutang_log` | 0 |
| `kas_ledger` | 0 |
| `kendaraan` | 1 |
| `master_mitra` | 22 |
| `mitra` | 0 |
| `pabrik` | 2 |
| `panjar_mitra` | 2 |
| `pembayaran_mitra` | 0 |
| `pembayaran_mitra_kwitansi` | 2 |
| `pembayaran_mitra_kwitansi_item` | 2 |
| `pembayaran_pabrik` | 0 |
| `pembayaran_pabrik_detail` | 0 |
| `pengaturan_bisnis` | 7 |
| `pengiriman` | 0 |
| `pengiriman_lokal_detail` | 0 |
| `petani` | 1 |
| `rekening_kas` | 1 |
| `settlement_mitra` | 0 |
| `sopir` | 63 |
| `stok_tbs_lokal_ledger` | 0 |
| `tarif_armada` | 0 |
| `transaksi_beli` | 0 |
| `transaksi_beli_tbs` | 0 |
| `transaksi_mitra` | 55 |
| `users` | 2 |

## 3. Kesimpulan Data

- Data operasional yang nyata saat ini terutama ada di `transaksi_mitra`, `master_mitra`, `sopir`, `fee_owner_mitra_history`, `harga_tbs`, `harga_tbs_lokal`, dan kwitansi mitra.
- Tabel legacy lokal seperti `pengiriman`, `pengiriman_lokal_detail`, `transaksi_beli`, `hutang`, dan `hutang_log` kosong.
- `armada_perusahaan` dan `kendaraan` masing-masing masih punya 1 row, tetapi hasil audit sopir menunjukkan tidak ada sopir yang masih terhubung ke `armada_perusahaan`.
- Audit sopir: 63 total sopir, 61 sudah punya `mitra_id`, 62 punya `plat_nomor`, dan 0 punya `armada_perusahaan_id`.
- Ini mendukung keputusan UX terbaru: menu Armada aktif memakai `sopir.mitra_id` dan `sopir.plat_nomor`, bukan tabel `armada_perusahaan` lama.

## 4. Dependency Legacy yang Perlu Diingat

Walau beberapa tabel kosong, DB belum boleh langsung drop karena masih ada FK:

| Tabel / Kolom | Mengarah ke |
| --- | --- |
| `armada_mitra.mitra_id` | `mitra.id` |
| `fee_mitra_history.mitra_id` | `mitra.id` |
| `hutang_ledger.mitra_id` | `mitra.id` |
| `pembayaran_mitra.mitra_id` | `mitra.id` |
| `settlement_mitra.mitra_id` | `mitra.id` |
| `pengiriman.mitra_id` | `mitra.id` |
| `pengiriman.kendaraan_id` | `kendaraan.id` |
| `pengiriman.armada_perusahaan_id` | `armada_perusahaan.id` |
| `pengiriman_lokal_detail.pengiriman_id` | `pengiriman.id` |
| `kas_ledger.pengiriman_id` | `pengiriman.id` |
| `biaya_operasional.pengiriman_id` | `pengiriman.id` |
| `pembayaran_pabrik_detail.pengiriman_id` | `pengiriman.id` |
| `settlement_mitra.pengiriman_id` | `pengiriman.id` |
| `sopir.armada_perusahaan_id` | `armada_perusahaan.id` |
| `sopir.kendaraan_id` | `kendaraan.id` |
| `tarif_armada.armada_id` | `armada_perusahaan.id` |

Implikasi: freeze UI aman, archive/drop DB harus menunggu migration terencana yang melepas FK dan memastikan tidak ada data penting.

## 5. RLS dan Policy yang Perlu Diperbaiki

Semua tabel public yang dicek sudah `rls_enabled = true`.

Policy yang masih terlalu longgar dan perlu ditinjau:

| Tabel | Policy Saat Ini | Risiko |
| --- | --- | --- |
| `master_mitra` | `Authenticated full access:ALL` | Semua user authenticated berpotensi punya akses tulis penuh. |
| `transaksi_mitra` | `Authenticated full access:ALL` | Transaksi utama bisnis terlalu terbuka jika tidak dibatasi role. |
| `kendaraan` | `Authenticated full access:ALL` | Tabel legacy masih bisa ditulis oleh authenticated user. |
| `fee_owner_mitra_history` | `Authenticated full access:ALL` | Fee owner sensitif dan sebaiknya dibatasi role. |

Rekomendasi: ganti policy longgar ini menjadi policy berbasis role aplikasi seperti pola `read_authenticated`, `write_operations`, `write_finance`, atau policy khusus owner/super admin.

## 6. Freeze UI yang Sudah Dilakukan

- Sidebar memisahkan menu `Mitra` dan `Armada` di grup Master Data.
- Menu `Armada` aktif memakai tabel `sopir`; halaman `armada_perusahaan` lama tidak menjadi workflow aktif.
- Halaman `/master/armada` diubah menjadi arsip baca-saja dan mengarah ke `/owner/master-data`.
- Halaman `/transaksi/kirim` sudah menjadi arsip baca-saja untuk pengiriman lokal legacy; tidak ada lagi tombol input/update legacy.

## 7. Keputusan Lanjutan

Tahap berikutnya yang aman:

1. Buat migration hardening policy untuk `master_mitra`, `transaksi_mitra`, `fee_owner_mitra_history`, dan tabel legacy yang masih longgar.
2. Buat migration non-destruktif untuk menandai tabel legacy sebagai read-only dari role aplikasi.
3. Jangan drop tabel sampai FK legacy dilepas dengan migration yang jelas.
4. Tambahkan master `karyawan` setelah policy/RLS dasar rapi, karena kasbon karyawan butuh master sendiri.
