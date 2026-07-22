# Evidence P0: Evaluasi Production Tanpa Biaya Tambahan Supabase

| Field | Nilai |
| --- | --- |
| Tanggal | 20 Juli 2026 |
| Target | Supabase production `yavntiympbrjlouzkhnl` |
| Metode | Query aggregate read-only, schema-only CLI dump, semantic shadow diff, backup inventory, dan review migration |
| Perubahan production | Tidak ada |
| Kesimpulan | Production dapat direncanakan tanpa upgrade Supabase dengan logical backup + Docker rehearsal + maintenance window; residual risk tanpa PITR wajib diterima eksplisit |

## Inventaris Production

| Item | Hasil |
| --- | ---: |
| Ukuran database | 17.607.827 byte, sekitar 17,6 MB |
| Tabel `public` | 41 |
| Estimasi row `public` | 587 |
| Pengguna Auth | 4 |
| Object Storage | 4 |
| Ukuran object menurut metadata | 201.444 byte |
| Migration history | 0/15 |

Inventaris hanya membaca metadata dan aggregate count; isi bisnis, identitas pengguna, nama object, token, dan secret tidak dicetak atau disimpan sebagai evidence.

## Hasil Teknis

1. `supabase db dump --linked` berhasil membuat schema-only dump production sebesar 354.437 byte. File evaluasi langsung dihapus setelah perbandingan.
2. Shadow database hanya diberi migration `00000000000000_baseline.sql`, lalu `supabase db diff --linked --schema public --use-pg-delta` tidak menghasilkan SQL perubahan. Baseline dan schema `public` production setara secara semantik.
3. Ledger kosong berarti baseline harus dicatat sebagai `applied` setelah backup/rehearsal, bukan dijalankan ulang terhadap production.
4. Empat belas migration setelah baseline tidak menghapus tabel atau melakukan `TRUNCATE` data bisnis. Operasi berisiko utamanya adalah perubahan policy/grant, penggantian function/view/trigger, penambahan kolom, dan backfill setting; semuanya tetap wajib direhearsal dengan data production clone.
5. Backup inventory staging dan production tetap `backups: null`, `pitr_enabled: false`, `walg_enabled: true`.
6. Basic TOTP MFA tersedia tanpa biaya dan API staging sudah aktif, tetapi aplikasi belum memiliki enrollment/challenge/verify serta enforcement AAL2.

## Dasar Platform

- Supabase merekomendasikan project Free tier membuat export berkala dengan `supabase db dump` dan menyimpan backup off-site: <https://supabase.com/docs/guides/platform/backups>.
- CLI dump memakai `pg_dump` dengan filter schema internal; schema, data, dan role perlu diekspor terpisah: <https://supabase.com/docs/reference/cli/usage#supabase-db-dump>.
- Object Storage tidak ikut dalam database backup dan harus diunduh terpisah: <https://supabase.com/docs/guides/platform/backups>.
- TOTP MFA gratis dan aktif secara default pada seluruh project: <https://supabase.com/docs/guides/auth/auth-mfa/totp>.

## Batas Bukti

Evaluasi ini belum membuat backup data production karena mesin belum memiliki tool enkripsi arsip (`gpg`, `age`, `7z`, atau `openssl`). Raw dump berisi data sensitif tidak boleh dibuat sebelum media terenkripsi dan lokasi off-site ditetapkan. Evaluasi juga belum mengubah migration ledger, Auth production, Storage, schema, row, atau deployment.
