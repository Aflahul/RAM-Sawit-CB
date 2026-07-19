# Evidence P0: Rehearsal Lokal 19 Juli 2026

| Field | Nilai |
| --- | --- |
| Status | Implemented, locally verified, and rehearsed on isolated staging; hosted Auth baseline hardened, while plan-dependent controls, MFA enforcement, restore drill, and independent review remain pending |
| Branch / baseline SHA | `agent/p0-security-release-gates` / `6b2ac10880976869396422bf189556570f70378d` plus the Auth hardening changes documented here |
| Environment | Supabase CLI `2.109.1`, PostgreSQL 17 container lokal, Node.js `24.14.0` |
| Data | Fixture sintetis di dalam transaction `BEGIN`/`ROLLBACK`; tidak memakai row production |
| Hosted staging | `Aflahul's Project` / `mfxyeybmjpcdckajfjen`; migration lokal dan remote sejajar 13/13 |
| Production boundary | Project `sawit-cb` / `yavntiympbrjlouzkhnl` tidak menerima `db push`, DDL, DML, atau perubahan Auth |

## Hasil yang Lulus

| Gate | Perintah / metode | Hasil |
| --- | --- | --- |
| Migration source | `npm run check:migrations` | 13 file valid, UTF-8 tanpa BOM, non-empty, versi unik |
| Clean install | `npx supabase db reset --local --no-seed` | Lulus dari baseline sampai `20260719062302` |
| Deterministic DB suite | `psql -v ON_ERROR_STOP=1 -f supabase/tests/p0_deterministic_release_gate_rollback.sql` melalui container lokal | Lulus dua run berurutan dan satu run lagi setelah reset bersih |
| Database lint | `npx supabase db lint --local --level error --fail-on error` | Tidak ada temuan |
| Security advisor | `npx supabase db advisors --local --type security --level warn --fail-on warn` | Tidak ada temuan |
| Staging migration dry-run | `supabase db push --linked --dry-run` pada workdir terisolasi | Tepat satu migration maju `20260719062302`; tidak ada migration lain |
| Staging migration ledger | `supabase migration list --linked` pada workdir staging | 13 versi lokal dan remote sejajar |
| Staging deterministic suite | `supabase db query --linked --file ...p0_deterministic_release_gate_rollback.sql` | Exit 0; fixture Auth dan public kembali 0 setelah rollback |
| Staging SQL security audit | Management API query terhadap katalog PostgreSQL | 41 tabel public, 0 tanpa RLS, 0 view dapat dibaca `anon` |
| Residual function ACL | Audit `pg_proc` dan `has_function_privilege` | RPC pengiriman tidak dapat dieksekusi `anon`; dua trigger function hanya untuk `service_role`; dua helper role tetap fail-closed untuk evaluasi RLS |
| Hosted Auth baseline | Management API GET/PATCH pada staging | Public signup disabled; password minimum 12; lower/upper/digit required; password-change reauthentication enabled; TOTP enroll/verify API enabled |
| Hosted Auth regression | Public dan Admin Auth endpoints dengan fixture sintetis | Public signup ditolak HTTP 422; Admin strong-password create/delete lulus; seluruh fixture dibersihkan dan total Auth user kembali 0 |
| Application password gate | `npm run test:password-policy` | Validator server menerima strong fixture dan menolak null, pendek, grup karakter tidak lengkap, spasi, serta emoji sebagai simbol |
| Application lint | `npm run lint` | Lulus |
| Production build | `npm run build` | Lulus; 29 static pages generated |
| Dependency gate | `npm audit --audit-level=high` | Lulus; 0 critical, 0 high |
| Secret scan | Gitleaks `8.29.1`, seluruh riwayat lokal | 65 commit / sekitar 3.64 MB, tidak ada leak |
| Diff hygiene | `git diff --check` | Tidak ada whitespace error; hanya peringatan line-ending Windows |
| GitHub release gate | Draft PR #5 dan branch protection `main` | Seluruh checks hijau; strict required checks, PR, linear history, dan conversation resolution aktif |

Advisory residual: `npm audit` masih melaporkan dua temuan moderate yang berasal dari PostCSS di dependency Next.js. Saran otomatis npm adalah downgrade besar ke Next 9 dan tidak dipakai karena tidak aman/kompatibel. High advisory pada `xlsx` ditutup dengan mengganti kedua paket SheetJS lama menjadi `write-excel-file@4.1.1`; lint dan production build lulus setelah migrasi ekspor.

## Cakupan Tes Deterministik

Suite P0 membuktikan role tanpa default, DTO tanpa kolom sensitif, legacy RPC tidak dapat dieksekusi actor aplikasi, RPC pengiriman tidak dapat dieksekusi `anon`, trigger function tidak dapat dipanggil langsung role aplikasi, audit append-only, maker-checker Admin, penolakan self-approval, kalkulasi transaksi server-authoritative, penolakan payload finansial buatan client, rekalkulasi input operasional, approval oleh identitas Owner yang berbeda, tepat dua audit event, dan actor tanpa profile ditolak.

Tiga test rollback lama tidak dijadikan release gate karena memilih row bisnis yang diasumsikan sudah ada sehingga gagal pada database bersih. File tersebut dipertahankan sebagai artefak historis; penggantinya adalah fixture sintetis deterministik di `p0_deterministic_release_gate_rollback.sql`.

## Rehearsal Hosted dan Batas Bukti

Project staging sebelumnya berisi delapan tabel portfolio yang tidak terkait aplikasi. Untuk menjaga pemulihan, schema `public` lama tidak dihapus: schema tersebut dipindahkan ke `portfolio_backup_20260719`, akses role API dicabut, kemudian schema `public` baru dibuat untuk rehearsal. Staging menerima baseline dan seluruh migration aplikasi melalui workdir yang secara eksplisit tertaut ke `mfxyeybmjpcdckajfjen`; link workspace utama tetap menunjuk ke production `yavntiympbrjlouzkhnl` dan tidak digunakan untuk push.

`db lint --linked` dan `db advisors --linked` tidak dapat diselesaikan tanpa password database lama. Sebagai pengganti bukti hosted, audit read-only dijalankan melalui Management API terhadap migration ledger, RLS, view ACL, function ACL, dan rollback fixture. Lint serta advisor resmi tetap lulus pada database PostgreSQL 17 lokal yang dibangun bersih dari migration yang sama. Peringatan cache katalog `pg-delta` tentang file sertifikat muncul setelah migration staging berhasil diaplikasikan; exit code push dan ledger remote kemudian diverifikasi secara terpisah.

Auth staging diuji dengan akun sintetis yang langsung dihapus. Uji tersebut membuktikan endpoint Admin Supabase dapat melewati password policy hosted; karena itu validasi password kuat ditambahkan di server action aplikasi, bukan hanya atribut HTML, dan dijadikan CI gate. Otorisasi server action juga memvalidasi token lewat `auth.getUser()` sebelum memeriksa role. Hosted Auth mewajibkan panjang 12 serta lower/upper/digit, sementara server action juga mewajibkan simbol. Percobaan mengaktifkan leaked-password protection dan session timebox/inactivity timeout ditolak plan staging secara terpisah dan tidak mengubah konfigurasi. TOTP API aktif, tetapi aplikasi belum memiliki enrollment/challenge flow dan belum menegakkan AAL2.

Bukti ini belum menutup:

- upgrade plan atau kontrol pengganti untuk leaked-password dan session timebox/inactivity timeout;
- implementasi dan enforcement MFA/AAL2 pada aplikasi;
- rehearsal terhadap clone/snapshot production yang representatif dan rekonsiliasi data;
- concurrency/retry/idempotency/reversal/print-export test di staging;
- backup/PITR serta restore drill database dan Storage;
- review manusia independen dan keputusan GO/NO-GO.

Sampai semua item tersebut selesai, keputusan rilis tetap **NO-GO**.
