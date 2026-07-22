# INC-20260722-002 — Dana Operasional Trip tidak terlihat pada edit dan kwitansi

| Metadata | Nilai |
| --- | --- |
| Severity | S1 — risiko pencatatan uang tidak lengkap |
| Status | Dalam penanganan |
| Tanggal | 22 Juli 2026 |
| Route | `/admin/input-timbangan`, `/owner/kwitansi-mitra` |
| Release | Hotfix production dari `main` |

## Dampak

Owner melihat checkbox **Buat Dana Operasional Trip** aktif dengan tarif Rp750.000, tetapi nominal tersebut tidak muncul pada ringkasan edit maupun rincian kwitansi. Pada data dengan snapshot lama bernilai nol, menyimpan edit tanpa mengganti mitra, tanggal, sopir, atau checkbox juga tidak menyegarkan snapshot dan tagihan Dana Trip.

## Akar masalah

1. Ringkasan edit dan kwitansi hanya merender nilai bersih, panjar, dan sewa armada.
2. Trigger transaksi hanya menyegarkan snapshot Dana Trip ketika kontrol/rute berubah; kombinasi checkbox aktif + snapshot nol tidak dipulihkan saat edit biasa.
3. Item kwitansi belum memiliki snapshot khusus Dana Operasional Trip.

## Keputusan containment

- Perbaiki snapshot nol hanya ketika transaksi aktif, memakai Armada CB, Dana Trip dicentang, dan Dana Trip belum dibayar.
- Bekukan Dana Trip pada item kwitansi baru dan tampilkan sebagai **biaya CB yang dibayar terpisah**.
- Dana Trip tidak dikurangkan lagi dari hak mitra; nominal pembayaran mitra tetap `nilai bersih - sewa - panjar` agar kas tidak tercatat ganda.
- Kwitansi yang sudah diterbitkan tidak diubah atau di-backfill otomatis.
- Tidak ada fitur/layanan Supabase berbayar yang ditambahkan.

## Verifikasi wajib

- Reproduksi SQL dengan netto 10.930 kg, sewa Rp150/kg, Dana Trip Rp750.000.
- Snapshot transaksi dan tagihan Dana Trip menjadi Rp750.000 setelah edit.
- Item kwitansi baru menyimpan snapshot Dana Trip Rp750.000.
- Ringkasan edit dan kwitansi menampilkan Dana Trip; sisa bayar mitra tidak terpotong dua kali.
- Lint, build, migration, dan smoke production lulus.

## Release darurat

Atas instruksi Owner, syarat satu approval pada `main` boleh diturunkan menjadi nol hanya selama merge hotfix ini. Seluruh status check tetap wajib. Setelah merge dan deployment production berhasil, syarat approval `main` wajib dikembalikan menjadi satu.
