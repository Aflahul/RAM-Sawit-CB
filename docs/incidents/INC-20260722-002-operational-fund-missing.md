# INC-20260722-002 — Dana Operasional Trip tidak terlihat pada edit dan kwitansi

| Metadata | Nilai |
| --- | --- |
| Severity | S1 — risiko pencatatan uang tidak lengkap |
| Status | Dalam penanganan |
| Tanggal | 22 Juli 2026 |
| Route | `/admin/input-timbangan`, `/owner/kwitansi-mitra` |
| Release | Hotfix production dari `main` |

## Dampak

Owner melihat checkbox Dana Operasional aktif dengan tarif Rp750.000, tetapi nominal tersebut tidak masuk ke formula potongan akhir pada ringkasan edit dan kwitansi. Owner kemudian menegaskan bahwa Dana Operasional sudah dibayar langsung oleh Mitra kepada sopir sebelum berangkat, sehingga sistem lama juga salah membuatnya sebagai kewajiban Kas CB.

## Akar masalah

1. Ringkasan edit dan kwitansi hanya merender nilai bersih, panjar, dan sewa armada.
2. Trigger transaksi hanya menyegarkan snapshot Dana Operasional ketika kontrol/rute berubah; kombinasi checkbox aktif + snapshot nol tidak dipulihkan saat edit biasa.
3. Implementasi lama memperlakukan Dana Operasional sebagai tagihan dan biaya CB, padahal sumber uangnya adalah Mitra.
4. Item kwitansi belum membekukan sumber Dana Operasional dan tiga angka audit: sewa kotor, dana langsung, dan potongan akhir.

## Keputusan containment

- Perbaiki snapshot nol hanya untuk transaksi aktif dan lindungi dokumen yang sudah terbit.
- Terapkan `potongan akhir sewa = max(sewa kotor - Dana Operasional yang dibayar Mitra, 0)`.
- Bekukan sewa kotor, Dana Operasional, sumber dana, dan potongan akhir pada item kwitansi baru.
- Hentikan pembuatan tagihan, biaya operasional, dan kas keluar Dana Trip untuk skema baru.
- Nominal pembayaran Mitra menjadi `nilai bersih - potongan akhir sewa - panjar`.
- Kwitansi yang sudah diterbitkan tidak diubah atau di-backfill otomatis.
- Tidak ada fitur/layanan Supabase berbayar yang ditambahkan.

## Verifikasi wajib

- Reproduksi SQL dengan netto 10.930 kg, sewa Rp150/kg, Dana Trip Rp750.000.
- Snapshot transaksi menjadi Rp750.000 dan tagihan Dana Trip aktif dibatalkan setelah edit/migrasi terkontrol.
- Potongan akhir menjadi Rp889.500 dari sewa kotor Rp1.639.500.
- Item kwitansi baru menyimpan ketiga angka dan sumber dana langsung dari Mitra.
- Kas CB hanya keluar sebesar pembayaran akhir Mitra; tidak ada biaya/kas Dana Operasional tambahan.
- Lint, build, migration, dan smoke production lulus.

## Release darurat

Atas instruksi Owner, syarat satu approval pada `main` boleh diturunkan menjadi nol hanya selama merge hotfix ini. Seluruh status check tetap wajib. Setelah merge dan deployment production berhasil, syarat approval `main` wajib dikembalikan menjadi satu.
