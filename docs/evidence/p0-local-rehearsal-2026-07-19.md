# Evidence P0: Rehearsal Lokal 19 Juli 2026

| Field | Nilai |
| --- | --- |
| Status | Implemented and locally verified; staging dan reviewer independen masih pending |
| Branch / baseline SHA | `main` / `3fba0248f5fc6027ab1a88f566cb0aa310828992` plus working-tree changes listed in the associated PR |
| Environment | Supabase CLI `2.109.1`, PostgreSQL 17 container lokal, Node.js `24.14.0` |
| Data | Fixture sintetis di dalam transaction `BEGIN`/`ROLLBACK`; tidak memakai row production |
| Hosted mutation | Tidak ada `db push`, migration repair, DDL, DML, atau perubahan Auth pada project linked |

## Hasil yang Lulus

| Gate | Perintah / metode | Hasil |
| --- | --- | --- |
| Migration source | `npm run check:migrations` | 12 file valid, UTF-8 tanpa BOM, non-empty, versi unik |
| Clean install | `npx supabase db reset --local --no-seed` | Lulus dari baseline sampai `20260719000112` |
| Deterministic DB suite | `psql -v ON_ERROR_STOP=1 -f supabase/tests/p0_deterministic_release_gate_rollback.sql` melalui container lokal | Lulus dua run berurutan dan satu run lagi setelah reset bersih |
| Database lint | `npx supabase db lint --local --level error --fail-on error` | Tidak ada temuan |
| Security advisor | `npx supabase db advisors --local --type security --level warn --fail-on warn` | Tidak ada temuan |
| Application lint | `npm run lint` | Lulus |
| Production build | `npm run build` | Lulus; 29 static pages generated |
| Dependency gate | `npm audit --audit-level=high` | Lulus; 0 critical, 0 high |
| Secret scan | Gitleaks `8.29.1`, seluruh riwayat lokal | 65 commit / sekitar 3.64 MB, tidak ada leak |
| Diff hygiene | `git diff --check` | Tidak ada whitespace error; hanya peringatan line-ending Windows |

Advisory residual: `npm audit` masih melaporkan dua temuan moderate yang berasal dari PostCSS di dependency Next.js. Saran otomatis npm adalah downgrade besar ke Next 9 dan tidak dipakai karena tidak aman/kompatibel. High advisory pada `xlsx` ditutup dengan mengganti kedua paket SheetJS lama menjadi `write-excel-file@4.1.1`; lint dan production build lulus setelah migrasi ekspor.

## Cakupan Tes Deterministik

Suite P0 membuktikan role tanpa default, DTO tanpa kolom sensitif, legacy RPC tidak dapat dieksekusi actor aplikasi, audit append-only, maker-checker Admin, penolakan self-approval, kalkulasi transaksi server-authoritative, penolakan payload finansial buatan client, rekalkulasi input operasional, approval oleh identitas Owner yang berbeda, tepat dua audit event, dan actor tanpa profile ditolak.

Tiga test rollback lama tidak dijadikan release gate karena memilih row bisnis yang diasumsikan sudah ada sehingga gagal pada database bersih. File tersebut dipertahankan sebagai artefak historis; penggantinya adalah fixture sintetis deterministik di `p0_deterministic_release_gate_rollback.sql`.

## Kondisi Linked dan Batas Bukti

`supabase migration list --linked` pada 19 Juli 2026 menunjukkan seluruh 12 versi hanya ada di kolom local dan kolom remote kosong. Karena itu, project linked tidak boleh menerima `db push` langsung: baseline/history perlu direkonsiliasi terlebih dahulu dan seluruh upgrade harus direhearsal pada staging/clone terisolasi.

Bukti ini belum menutup:

- hosted Auth attestation (invitation-only, password/leaked-password, MFA, session/idle, reauthentication);
- upgrade rehearsal terhadap clone/snapshot dari keadaan hosted dan rekonsiliasi data;
- concurrency/retry/idempotency/reversal/print-export test di staging;
- backup/PITR serta restore drill database dan Storage;
- aktivasi required checks/branch protection di GitHub;
- review manusia independen dan keputusan GO/NO-GO.

Sampai semua item tersebut selesai, keputusan rilis tetap **NO-GO**.
