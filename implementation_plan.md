# Implementation Plan: Pengiriman Mitra dan Operasional Armada CB

Dokumen ini adalah plan ringkas yang menyambungkan `PRD-final.md` dan `IMPLEMENTATION-TASKS.md`.

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
