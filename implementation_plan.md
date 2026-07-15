# Implementation Plan: Pengiriman Mitra, Armada CB, dan Biaya Sopir

Dokumen ini adalah plan ringkas yang menyambungkan `PRD-final.md` dan `IMPLEMENTATION-TASKS.md`.

## Status Implementasi - Selesai 15 Juli 2026

- P0 selesai: alur Armada First, pemisahan Mitra Transaksi, dan rumus sewa kotor sudah aktif.
- P1 selesai: tarif global/override, snapshot biaya sopir, tagihan otomatis, serta Bayar Tunai Sopir sudah aktif.
- P2 selesai: laporan bulanan per armada, biaya operasional per truk, dan margin owner sudah tersedia.
- Migrasi remote aktif: `20260715105207_armada_cb_driver_costs.sql`.
- Snapshot sewa kwitansi dibekukan melalui `20260715113428_freeze_kwitansi_sewa_snapshots.sql`; detail kwitansi dibayar tidak lagi mengambil nominal dari transaksi live.
- RPC finansial lama dibersihkan melalui `20260715114309_repair_financial_rpc_lint.sql` dan `20260715114553_repair_kwitansi_panjar_audit_field.sql`; remote DB lint kini lulus tanpa error.
- Verifikasi: lint dan production build lulus; remote memiliki dua trigger aktif dan tidak ada baris sewa yang totalnya berbeda dari sewa kotor.
- Tindakan operasional tersisa: owner harus mengisi nominal **Upah Sopir / Trip** dan **Uang Jalan / Trip** di menu Armada. Nilai awal sengaja `Rp0` karena nominal belum dijawab; setelah diisi, gunakan **Terapkan Tarif Saat Ini** pada Laporan Armada CB untuk trip lama yang belum dibayar.

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

### P1 - Add-on Operasional

- Tracking tagihan sopir CB: upah flat per trip + uang jalan/perongkosan.
- Kas tidak otomatis berkurang saat DO diinput.
- Admin memakai aksi **Bayar Tunai Sopir** untuk mencatat kas keluar.

### P2 - Add-on Laporan Profit Armada

- Laporan per truk/per bulan: total trip, total muatan, sewa masuk, upah sopir, uang jalan, biaya operasional, dan margin.

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

Perongkosan/uang jalan pindah ke biaya sopir CB pada P1.

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

- Tambahkan pengaturan global:
  - `upah_sopir_cb_per_trip`
  - `uang_jalan_sopir_cb_per_trip`
- Simpan snapshot di transaksi:
  - `upah_sopir_cb_snapshot`
  - `uang_jalan_sopir_cb_snapshot`
  - `total_biaya_sopir_cb_snapshot`
- Buat tagihan sopir saat pengiriman Armada CB disimpan.
- Buat aksi **Bayar Tunai Sopir** yang mencatat kas keluar.
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
2. Pastikan tagihan sopir terbentuk: upah + uang jalan.
3. Klik Bayar Tunai Sopir.
4. Pastikan kas keluar tercatat satu kali.
5. Pastikan pembayaran ulang ditolak atau dinonaktifkan.

### P2

1. Filter laporan per truk/per bulan.
2. Cocokkan total trip dan total muatan.
3. Cocokkan sewa masuk, biaya sopir, biaya operasional, dan margin.
