# Implementation Plan: Pengiriman Mitra dan Operasional Armada CB

Dokumen ini adalah plan ringkas yang menyambungkan `PRD-final.md` dan `IMPLEMENTATION-TASKS.md`.

## Audit Lintas Halaman - 16 Juli 2026

Audit lengkap tersedia di `docs/page-flow-control-audit-2026-07-16.md`. Audit mencakup route, role, tombol, query, RPC, snapshot, ledger, laporan, dan data remote.

Keputusan pengembangan setelah audit yang sudah dilaksanakan:

1. Release gate audit P0 diselesaikan sebelum workflow Pinjaman & Panjar ditambahkan.
2. Amankan RLS dan fungsi audit agar role operasional tidak dapat mengubah atau membaca data di luar kewenangannya.
3. Kunci transaksi yang sudah masuk kwitansi atau Dana Trip, lalu sediakan alur koreksi/reversal yang menjaga kas dan laporan tetap seimbang.
4. Pisahkan istilah **Berat Netto** dan **Berat Dibayar** di kwitansi agar angka tidak berubah arti setelah pembayaran.
5. Betulkan laporan Pendapatan Owner dan definisikan ulang halaman Laba/Rugi sebagai laporan arus kas sampai akuntansi periodenya tersedia.

Temuan data remote yang menjadi release gate:

- Ada 1 transaksi batal yang masih terhubung ke kwitansi aktif dan sudah dibayar.
- Ada 8 kwitansi dibayar yang header tonasenya memakai Berat Netto, sedangkan rincian pembayaran memakai Berat Dibayar.
- Ada 19 pasangan periode fee yang tumpang tindih pada 13 mitra.
- Ada 3 kelompok plat aktif duplikat setelah normalisasi dan 1 armada aktif tanpa plat.
- Seluruh pembayaran mitra/pabrik yang diperiksa sudah memiliki pasangan Buku Kas dengan nominal yang sesuai.

### Status Release Gate P0 - Diimplementasikan 16 Juli 2026

- Enam migration P0 kontrol bisnis, snapshot, reversal, audit, dan hardening direct-write sudah aktif di Supabase remote.
- Admin, Owner, dan Super Admin menjadi tiga role pengguna; `admin_keuangan` tetap tersedia sebagai role internal cadangan.
- Admin dapat melakukan pencatatan rutin serta quick-add Sopir/Armada, tetapi master baru masuk antrean `perlu_verifikasi` dan Admin tidak dapat mengubah tarif atau melakukan reversal Owner.
- Menu laporan Admin menggunakan nama **Rekap Operasional**. Admin dapat melihat muatan, trip, status pembayaran, filter, cetak, dan ekspor operasional tanpa melihat sewa masuk, biaya lain, margin, atau laporan profit Owner.
- Admin dapat menambah atau mengoreksi identitas Mitra, Armada, dan Pabrik. Perubahan Admin masuk antrean `perlu_verifikasi`; hanya Owner/Super Admin yang memverifikasi atau menonaktifkan master.
- Harga TBS Lokal dan pengaturan bisnis hanya dapat dibuka serta diubah oleh Owner/Super Admin.
- Transaksi yang sudah masuk kwitansi, pembayaran pabrik, atau Dana Trip dikunci dari edit/batal biasa.
- Pembatalan kwitansi, mutasi kas manual, dan Dana Trip membuat baris pembalik; histori lama tidak dihapus.
- Kwitansi menyimpan dan menampilkan Berat Netto serta Berat Dibayar secara terpisah. Rekonsiliasi remote menunjukkan mismatch header-item `0`.
- Histori fee sudah tidak tumpang tindih. Rekonsiliasi remote menunjukkan overlap `0`.
- Laba/Rugi basis kas telah diganti nama menjadi **Ringkasan Arus Kas**; laporan laba akrual tetap pengembangan berikutnya.
- Smoke test rollback dan uji akun Admin nyata sudah lulus. Lint serta production build aplikasi lulus.
- Kontrol laporan dan Master Data berbasis role aktif melalui migration `20260716050000_role_aware_reports_and_master_data.sql`.
- Workflow Pinjaman & Panjar aktif: Admin mengajukan dan menyerahkan uang yang sudah disetujui; Owner/Super Admin menyetujui dan melakukan reversal; riwayat legacy dapat direkonsiliasi tanpa membuat kas historis baru.
- Potongan Panjar pada kwitansi dipasangkan per mitra. Kwitansi gabungan tidak boleh memakai hak Mitra A untuk menutup panjar atau sewa Mitra B, dan snapshot lama tanpa pemilik dipulihkan dari relasi `panjar_mitra`.
- Kontrol tersebut aktif melalui migration `20260716120505_enforce_kwitansi_panjar_per_mitra.sql` dan `20260716121121_enrich_kwitansi_panjar_snapshot_on_write.sql`.

Tindakan bisnis yang masih terbuka:

- Owner perlu memeriksa satu kwitansi `perlu_review` yang berisi transaksi lama berstatus batal, lalu memilih **Batalkan Pembayaran** dan menerbitkan ulang bila pembayarannya memang harus dikoreksi.
- Tujuh master Sopir/Armada lama yang platnya duplikat/kosong harus diverifikasi Owner. Sistem tidak menggabungkan data historis secara otomatis.

Status **selesai** di bawah ini hanya berlaku untuk scope Armada CB tanggal 15 Juli 2026. Status tersebut tidak menggantikan release gate audit lintas halaman di atas.

## Status Implementasi - Selesai 15 Juli 2026

- P0 selesai: alur Armada First, pemisahan Mitra Transaksi, dan rumus sewa kotor sudah aktif.
- P1 dikoreksi: biaya satu kali jalan tidak lagi dipecah menjadi upah dan uang jalan. Sistem memakai **Dana Operasional Trip** berdasarkan Mitra Transaksi.
- P2 selesai: laporan bulanan per armada, biaya operasional per truk, dan margin owner sudah tersedia.
- Migrasi remote aktif: `20260715105207_armada_cb_driver_costs.sql`.
- Koreksi final remote aktif: `20260715123147_armada_cb_dana_operasional_trip_mitra.sql`.
- Pagar edit snapshot remote aktif: `20260715124617_correct_armada_cb_tariff_refresh.sql`.
- Sinkronisasi tagihan saat mitra/tanggal berubah aktif: `20260715124759_sync_dana_trip_ledger_on_route_change.sql`.
- Snapshot sewa kwitansi dibekukan melalui `20260715113428_freeze_kwitansi_sewa_snapshots.sql`; detail kwitansi dibayar tidak lagi mengambil nominal dari transaksi live.
- RPC finansial lama dibersihkan melalui `20260715114309_repair_financial_rpc_lint.sql` dan `20260715114553_repair_kwitansi_panjar_audit_field.sql`; remote DB lint kini lulus tanpa error.
- Peringatan palsu **Perlu Cek** pada transaksi berpotongan diperbaiki: halaman Pengiriman Mitra membandingkan `berat_dibayar_kg` dengan `berat_dibayar_snapshot`, bukan dengan berat netto lama.
- Verifikasi: lint dan production build lulus; remote memiliki dua trigger aktif dan tidak ada baris sewa yang totalnya berbeda dari sewa kotor.
- Tarif owner per 15 Juli 2026 disiapkan untuk `SL`, `BL`, `SL/F`, `SL/BS`, `SL/MLD`, dan `BL/ML`. Tarif mitra lain tetap `Rp0` sampai dikonfirmasi.

## Tujuan Utama

Membangun alur **Pengiriman Mitra** sebagai satu pintu untuk:

- mencatat muatan mitra ke pabrik dari nota/timbangan,
- memilih sopir/plat terlebih dahulu agar input cepat,
- memisahkan **Armada CB** dari **Mitra Transaksi**,
- menghitung Berat Netto, Potongan Pabrik, Berat Dibayar, Fee Owner, dan Sewa Armada CB,
- menjaga kwitansi, kas, laba/rugi, dan laporan armada tetap konsisten.

## Keputusan Prioritas

### P0 - Wajib Dikoreksi Sekarang

P0 adalah koreksi fondasi karena memengaruhi angka kwitansi, pendapatan owner, dan laporan.

- Armada CB adalah sopir/plat internal CB dengan `sopir.is_armada_cb = true`.
- Armada CB tidak wajib punya `sopir.mitra_id`.
- Admin tetap wajib memilih **Mitra Transaksi** karena mitra transaksi adalah pihak yang punya muatan dan masuk kwitansi.
- Sewa Armada CB dihitung dari `berat_netto_pabrik_kg x tarif_sewa_armada_per_kg`.
- Sewa Armada CB tidak boleh dikurangi uang jalan/perongkosan.
- `nominal_perongkosan` tidak lagi dipakai sebagai pengurang sewa armada.

### P1 - Dana Operasional Trip

- Satu Dana Operasional Trip diberikan untuk satu kali jalan Armada CB.
- Dana ini sudah mencakup solar, makan, uang jalan, dan bagian sopir. Sistem tidak mengaku mengetahui upah bersih sopir.
- Besarnya ditentukan oleh Mitra Transaksi yang menyewa Armada CB.
- Kas tidak otomatis berkurang saat DO diinput.
- Admin memakai aksi **Bayar Dana Trip** untuk mencatat kas keluar.

### P2 - Add-on Laporan Profit Armada

- Laporan per truk/per bulan: total trip, total muatan, sewa masuk, Dana Operasional Trip, biaya operasional lain, dan margin.
- Saat memilih Semua Armada, tampilkan rekap per plat agar owner bisa membandingkan jumlah trip, total muatan, dan margin tanpa mengganti filter satu per satu.
- Rincian trip disembunyikan secara default untuk menghindari tabel berulang; owner membukanya hanya saat perlu memeriksa transaksi atau membayar Dana Trip.

## Alur UX Target

Urutan form mengikuti cara admin membaca nota fisik:

```text
Tanggal
Sopir / Plat
Mitra Transaksi
Berat Netto dari Pabrik
Potongan Pabrik
Ringkasan Otomatis
Simpan
```

Perilaku form:

- Admin boleh mencari plat/sopir sebelum memilih mitra.
- Jika sopir/plat punya mitra default, Mitra Transaksi otomatis terisi dan tetap bisa diganti.
- Jika sopir/plat adalah Armada CB tanpa mitra default, tampilkan badge **Armada CB** dan minta admin memilih Mitra Transaksi manual.
- Opsi sopir pengganti, catatan, dan override lain masuk ke **Opsi Lanjutan**.
- Tanggal tetap sticky setelah simpan untuk input batch nota tanggal yang sama.

## Perubahan Teknis P0

### Schema / Field

- Pastikan query sopir mengambil `is_armada_cb`.
- Pertahankan `sopir.mitra_id` nullable.
- Gunakan `sopir.is_armada_cb` sebagai penanda Armada CB.
- Pertahankan field legacy `pakai_sewa_armada_bl` sementara jika sudah ada, tetapi istilah UI/helper harus menyebut Armada CB.
- Jangan aktifkan lagi `armada_perusahaan` sebagai fondasi fitur baru.

### Kalkulasi

Rumus P0:

```text
Berat Dibayar = Berat Netto Pabrik - Potongan Pabrik
Nilai Bersih Mitra = Berat Dibayar x (Harga Pabrik - Fee Owner/kg)
Fee Owner = Berat Dibayar x Fee Owner/kg
Sewa Armada CB = Berat Netto Pabrik x Tarif Sewa Armada/kg
```

Yang harus dihapus dari kalkulasi sewa:

```text
Sewa Armada CB = (Berat Netto x Tarif) - Perongkosan
```

Dana satu kali jalan dicatat sebagai Dana Operasional Trip pada P1.

### Snapshot Kwitansi

- `biaya_sewa_armada_snapshot` adalah nominal yang benar-benar ditagihkan saat kwitansi diterbitkan.
- Kwitansi yang sudah dibayar hanya membaca snapshot berat, tarif, sewa, dan nilai pembayaran; perubahan transaksi live tidak boleh mengubah tampilan kwitansi.
- Sistem menyimpan sewa standar dan selisih historis sebagai metadata audit tanpa mengubah Buku Kas.
- Koreksi kwitansi dilakukan dengan pembatalan dan penerbitan kwitansi baru, bukan mengedit item snapshot.

### P0 - Penanganan Status Perlu Cek

- **Perlu Cek** hanya muncul jika berat/nilai transaksi berbeda dari snapshot, header pembayaran memang ditandai review, atau pembayaran belum terhubung ke Buku Kas.
- Pengiriman Mitra menampilkan alasan awam dan tombol **Periksa kwitansi** yang membawa admin ke mitra serta periode terkait.
- Transaksi baru setelah kwitansi sebelumnya terbit tetap berstatus **Belum Dibayar** dan masuk kwitansi berikutnya; kondisi ini bukan kesalahan kwitansi lama.
- Admin tidak boleh menghapus peringatan dengan checkbox bebas.
- Jika snapshot benar dan data transaksi salah, koreksi harus melalui alur pembatalan/reversal pembayaran, lalu terbitkan kwitansi baru.
- Alur reversal pembayaran mitra sudah tersedia untuk Owner dan membalik kas keluar serta pelunasan panjar secara atomik dengan alasan dan audit log.

### P0 - Kontrol Perlakuan Armada CB per Pengiriman

- Fakta perjalanan memakai Armada CB disimpan di `menggunakan_armada_cb_snapshot` berdasarkan plat/sopir yang dipilih. Admin tidak mematikan fakta trip dengan checkbox.
- **Potong sewa dari pembayaran mitra** disimpan di `kenakan_sewa_armada_cb`.
- **Buat Dana Operasional Trip** disimpan terpisah di `catat_dana_operasional_trip`.
- Jika salah satu keputusan uang dimatikan, admin wajib mengisi alasan agar bantuan armada, keputusan owner, atau pembayaran di luar transaksi tetap dapat diaudit.
- Trip tanpa sewa tetap menambah jumlah trip dan muatan Armada CB, tetapi tidak menjadi potongan kwitansi atau pendapatan sewa.
- Trip tanpa Dana Operasional Trip tidak membuat tagihan sopir, biaya operasional, atau kas keluar.
- Field lama `pakai_sewa_armada_bl` dipertahankan sebagai kompatibilitas dan sekarang mengikuti keputusan potongan sewa, bukan fakta penggunaan Armada CB.
- Data lama yang armadanya sekarang terdeteksi sebagai Armada CB tetapi belum memiliki keputusan uang ditandai `armada_cb_perlu_review`; sistem tidak membuat nilai uang baru secara otomatis.

### UI Pengiriman Mitra

- Ubah halaman menjadi Data Grid + Quick Add Modal.
- Modal memakai urutan input target.
- Badge status armada:
  - **Armada CB**
  - **Armada Mitra**
  - **Tanpa Default**
- Ringkasan transaksi menampilkan:
  - Berat Netto
  - Potongan Pabrik
  - Berat Dibayar
  - Nilai Bersih Mitra
  - Fee Owner
  - Sewa Armada CB jika berlaku

## Perubahan P1

- Tambahkan `master_mitra.dana_operasional_trip` dan riwayat tanggal berlakunya.
- Simpan `transaksi_mitra.dana_operasional_trip_snapshot` saat pengiriman dibuat.
- Pertahankan field upah/uang jalan lama hanya untuk membaca arsip lama.
- Buat tagihan Dana Operasional Trip saat pengiriman Armada CB disimpan.
- Buat aksi **Bayar Dana Trip** yang mencatat biaya operasional dan kas keluar.
- Cegah pembayaran ganda untuk tagihan sopir yang sama.

## Verification Plan

### P0

1. Cari plat Armada CB yang tidak punya mitra default.
2. Pastikan armada tetap bisa dipilih.
3. Pastikan badge **Armada CB** tampil.
4. Pastikan Mitra Transaksi wajib dipilih manual.
5. Input Berat Netto dan Potongan.
6. Pastikan Sewa Armada CB = Berat Netto x Tarif, tanpa dikurangi perongkosan.
7. Pastikan kwitansi memotong sewa Armada CB dari hak mitra.
8. Pastikan pendapatan owner membaca sewa Armada CB dengan arti yang sama.
9. Pastikan transaksi berpotongan yang tidak berubah tetap berstatus Sudah Dibayar.
10. Ubah berat atau nilai transaksi yang sudah dibayar pada data uji dan pastikan alasan Perlu Cek serta pintasan kwitansi tampil.

### P1

1. Simpan pengiriman dengan Armada CB.
2. Pastikan Dana Operasional Trip mengikuti tarif Mitra Transaksi pada tanggal pengiriman.
3. Klik Bayar Dana Trip.
4. Pastikan kas keluar tercatat satu kali.
5. Pastikan pembayaran ulang ditolak atau dinonaktifkan.

### P2

1. Filter laporan per truk/per bulan.
2. Cocokkan total trip dan total muatan.
3. Cocokkan sewa masuk, Dana Operasional Trip, biaya operasional lain, dan margin.

## Tarif Awal Owner - 15 Juli 2026

| Mitra | Sewa Armada CB | Dana Operasional Trip |
| --- | ---: | ---: |
| SL | Rp150/kg | Rp800.000/trip |
| BL | Rp150/kg | Rp750.000/trip |
| SL/F | Rp150/kg | Rp750.000/trip |
| SL/BS | Rp150/kg | Rp750.000/trip |
| SL/MLD | Rp150/kg | Rp750.000/trip |
| BL/ML | Rp180/kg | Rp900.000/trip |

Rumus laporan armada:

```text
Sewa Masuk = Berat Netto x Tarif Sewa Mitra
Margin Sebelum Perawatan = Sewa Masuk - Dana Operasional Trip
Margin Armada = Sewa Masuk - Dana Operasional Trip - Biaya Operasional Lain
```

## P0 - Pinjaman & Panjar (Selesai - 16 Juli 2026)

Tujuan: semua uang yang diberikan CB lebih dahulu memiliki persetujuan, bukti penyerahan, sumber kas, cara pengembalian, sisa pinjaman, dan histori koreksi yang dapat diaudit.

Alur final:

1. Admin mengajukan Panjar Mitra, Pinjaman Karyawan/Sopir, Panjar Petani, atau Pinjaman Pihak Lain.
2. Owner/Super Admin menyetujui atau menolak. Pengajuan oleh Owner dapat langsung berstatus disetujui.
3. Admin mengonfirmasi penyerahan uang dan rekening kas. Baru pada langkah ini `kas_ledger` dan `hutang_ledger` dibuat.
4. Sistem menerbitkan bukti pemberian sesuai jenis Pinjaman/Panjar dengan nomor dan snapshot identitas penerima.
5. Panjar Mitra diselesaikan dari Kwitansi Pembayaran TBS. Pihak lain dapat membayar tunai/transfer atau dipotong dari gaji/upah sesuai kesepakatan.
6. Pengembalian tunai/transfer menerbitkan Bukti Pengembalian Uang dan menambah kas CB.
7. Kesalahan dibatalkan Owner/Super Admin melalui reversal, bukan delete.
8. Panjar legacy yang sudah dipotong tetapi belum memiliki catatan pemberian awal dicocokkan Owner melalui bukti manual; sistem melengkapi saldo awal tanpa mengubah Buku Kas.

Pemisahan dokumen:

- **Kwitansi Pembayaran TBS Mitra**: bukti CB membayar transaksi TBS.
- **Bukti Pemberian Panjar Mitra/Petani**: bukti CB menyerahkan uang muka yang akan dipotong dari hak pembayaran berikutnya.
- **Bukti Pemberian Pinjaman Karyawan/Sopir** atau **Surat Pengakuan Pinjaman**: bukti CB menyerahkan uang yang harus dikembalikan.
- **Bukti Pengembalian Uang**: bukti CB menerima uang kembali.

Implementasi memakai migration:

- `20260716100224_add_piutang_document_approval_workflow.sql`
- `20260716101654_complete_piutang_repayment_reversal_sync.sql`
- `20260716104718_add_legacy_loan_reconciliation_control.sql`
- `20260716110212_expand_audit_actions_for_loan_workflow.sql`
- `20260716110725_archive_reconciled_legacy_loans.sql`

Tabel `piutang_dokumen` menjadi sumber dokumen dan status workflow, `piutang_pelunasan` menyimpan rincian pengembalian, `hutang_ledger` tetap menjadi buku mutasi kompatibel, dan `panjar_mitra` tetap dipakai untuk integrasi potongan Kwitansi TBS. Nama teknis lama tidak digunakan sebagai label UI.

Status verifikasi:

- Pengajuan, persetujuan, penyerahan, pengembalian parsial, reversal, dan arsip riwayat sudah aktif.
- Rekonsiliasi legacy Owner-only sudah aktif dan hasilnya dapat dibuka dari **Riwayat Lunas** menuju Kwitansi TBS terkait.
- Kas hanya bergerak saat uang benar-benar diserahkan atau dikembalikan; rekonsiliasi saldo awal legacy tidak membuat mutasi kas baru.
- Backlog lanjutan: lampiran bukti, batas pinjaman per pihak, laporan umur pinjaman, dan alokasi parsial Panjar Mitra ketika hak TBS tidak mencukupi.
