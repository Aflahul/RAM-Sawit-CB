# BDR-20260722-002: Dana Operasional Armada Dibayar Langsung oleh Mitra

| Field | Nilai |
| --- | --- |
| Status | Accepted |
| Tanggal | 2026-07-22 |
| Decision owner | Product Owner |
| Penyusun | Tim Pengembangan |
| Menggantikan | Aturan Dana Operasional sebagai biaya/tagihan Kas CB pada addendum 15 Juli 2026 |
| Terkait | `INC-20260722-002`, `TASK-HOTFIX-ARMADA-001` s.d. `TASK-HOTFIX-ARMADA-006` |

## Konteks

Owner mengonfirmasi bahwa Dana Operasional Armada diberikan langsung oleh Mitra kepada sopir sebelum kendaraan berangkat membawa muatan ke pabrik. Uang ini tidak diterima atau dibayarkan oleh CB. Karena itu, pencatatan sebagai tagihan sopir, biaya operasional CB, dan kas keluar CB tidak sesuai dengan kejadian bisnis.

## Pilihan yang Dipertimbangkan

| Opsi | Manfaat | Risiko/biaya |
| --- | --- | --- |
| Dana dibayar melalui Kas CB | Selaras dengan implementasi lama | Salah menggambarkan sumber uang dan menggandakan arus kas CB |
| Dana dibayar langsung Mitra dan mengurangi sewa kotor | Selaras dengan kejadian nyata, kas dan laporan dapat direkonsiliasi | Memerlukan koreksi formula, snapshot, kwitansi, dan laporan |

## Keputusan

Untuk transaksi baru dan transaksi aktif yang belum masuk kwitansi:

`Sewa Kotor = Berat Netto Pabrik × Tarif Sewa Mitra/kg`

`Potongan Akhir Sewa = max(Sewa Kotor − Dana Operasional Dibayar Mitra, 0)`

Dana Operasional tidak membuat utang/tagihan sopir, biaya operasional, atau kas keluar CB. Kwitansi dan laporan wajib menampilkan Sewa Kotor, Dana Operasional yang dibayar langsung oleh Mitra, serta Potongan Akhir/Sewa Bersih CB secara terpisah.

## Alasan

Keputusan ini mengikuti aliran uang yang benar: Mitra lebih dahulu menyerahkan dana kepada sopir, lalu CB hanya berhak memotong sisa sewa dari pembayaran TBS Mitra. Pemisahan tiga angka menjaga transparansi tanpa mencatat uang yang tidak pernah melewati kas CB.

## Dampak

- Alur dan role: aksi **Bayar Dana Trip** dari Kas CB dihentikan untuk skema baru.
- Formula/status: Dana Operasional mengurangi sewa kotor; hasil tidak boleh negatif.
- Dokumen/bukti: item kwitansi membekukan sewa kotor, Dana Operasional, sumber dana, dan potongan akhir.
- Data historis: kwitansi dan pembayaran lama yang sudah terbit tidak dihitung ulang; riwayat pembayaran Kas CB lama tetap dapat diaudit.
- UI/UX: form, edit, kwitansi, dan laporan memakai istilah yang menjelaskan siapa yang membayar.
- Kas/laba rugi: hanya nominal pembayaran akhir Mitra yang keluar dari Kas CB; Dana Operasional langsung bukan biaya CB.
- Biaya: implementasi tidak menambah layanan Supabase atau layanan berbayar.

## Acceptance Criteria

- [x] `AC-ARMADA-001`: Netto 10.930 kg × Rp150 menghasilkan Sewa Kotor Rp1.639.500.
- [x] `AC-ARMADA-002`: Dana Operasional Rp750.000 menghasilkan Potongan Akhir Rp889.500.
- [x] `AC-ARMADA-003`: Kwitansi mengurangi hak Mitra hanya sebesar Rp889.500.
- [x] `AC-ARMADA-004`: Dana Operasional tidak membuat biaya, utang, atau kas keluar CB.
- [x] `AC-ARMADA-005`: Laporan menunjukkan sewa kotor, dana dari Mitra, sewa bersih CB, biaya CB lain, dan margin.
- [x] `AC-ARMADA-006`: Kwitansi yang sudah terbit tidak diubah otomatis.

## Persetujuan

| Peran | Nama | Tanggal | Keputusan |
| --- | --- | --- | --- |
| Product Owner | Owner RAM Sawit CB | 2026-07-22 | Disampaikan langsung dan diterima sebagai aturan aktif |
| Tim Pengembangan | Codex | 2026-07-22 | Diimplementasikan sebagai hotfix production |
