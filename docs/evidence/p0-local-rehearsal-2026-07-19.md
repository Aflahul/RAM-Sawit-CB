# Evidence P0: Rehearsal Lokal 19 Juli 2026

| Field | Nilai |
| --- | --- |
| Status | Baseline `cc96dbb` independently reviewed; candidate increment local environment/dependency 22 Juli 2026 lulus gate lokal tetapi belum direview ulang. Release tetap No-Go selama review increment, Auth/MFA-AAL2, production-like upgrade rehearsal, dan zero-cost recovery proof belum selesai |
| Branch / baseline SHA | `agent/p0-security-release-gates` / reviewed baseline `cc96dbb27ba192e790391c09e96244efeadf5a4d`; candidate increment berada setelah baseline tersebut |
| Environment | Supabase CLI `2.109.1`, Vercel CLI `56.3.2`, PostgreSQL 17 container lokal, Node.js `24.14.0` |
| Data | Fixture sintetis rollback atau committed-sementara dengan cleanup terverifikasi; tidak memakai row production |
| Hosted staging | `Aflahul's Project` / `mfxyeybmjpcdckajfjen`; migration lokal dan remote sejajar 15/15 |
| Production boundary | Project `sawit-cb` / `yavntiympbrjlouzkhnl` tidak menerima `db push`, DDL, DML, atau perubahan Auth |

## Hasil yang Lulus

| Gate | Perintah / metode | Hasil |
| --- | --- | --- |
| Migration source | `npm run check:migrations` | 15 file valid, UTF-8 tanpa BOM, non-empty, versi unik |
| Clean install | `npx supabase db reset --local --no-seed` | Lulus dari baseline sampai `20260719232219` |
| Deterministic DB suite | `psql -v ON_ERROR_STOP=1 -f supabase/tests/p0_deterministic_release_gate_rollback.sql` melalui container lokal | Lulus setelah reset bersih; mencakup rekonsiliasi header/kas, retry pembayaran, reversal, retry pembatalan, snapshot item, audit tunggal, dan rollback fixture |
| Local concurrency gate | `npm run test:p0:payment-concurrency` | Dua sesi PostgreSQL bersamaan: 1 sukses, 1 ditolak, 1 pembayaran, 1 item, 1 mutasi kas; retry setelah commit ditolak; cleanup lulus |
| Database lint | `npx supabase db lint --local --level error --fail-on error` | Tidak ada temuan |
| Security advisor | `npx supabase db advisors --local --type security --level warn --fail-on warn` | Tidak ada temuan |
| Staging migration dry-run | `supabase db push --dry-run` pada workdir terisolasi | Tepat dua migration maju: `20260719231734` dan `20260719232219`; tidak ada migration lain |
| Staging migration ledger | `supabase migration list` pada workdir staging | 15 versi lokal dan remote sejajar setelah push |
| Staging deterministic suite | `supabase db query --linked --file ...p0_deterministic_release_gate_rollback.sql` | Exit 0; fixture Auth dan public kembali 0 setelah rollback |
| Staging concurrency gate | `npm run test:p0:payment-concurrency:staging` | Dua client HTTP terautentikasi: 1 sukses, 1 ditolak, retry ditolak, nominal header/kas sama Rp2.610.000; cleanup residue 0 |
| Staging SQL security audit | Management API query terhadap katalog PostgreSQL | 41 tabel public, 0 tanpa RLS, 0 view dapat dibaca `anon` |
| Residual function ACL | Audit `pg_proc` dan `has_function_privilege` | RPC pengiriman tidak dapat dieksekusi `anon`; dua trigger function hanya untuk `service_role`; dua helper role tetap fail-closed untuk evaluasi RLS |
| Hosted Auth baseline | Management API GET/PATCH pada staging | Public signup disabled; password minimum 12; lower/upper/digit required; password-change reauthentication enabled; TOTP enroll/verify API enabled |
| Hosted Auth regression | Public dan Admin Auth endpoints dengan fixture sintetis | Public signup ditolak HTTP 422; Admin strong-password create/delete lulus; seluruh fixture dibersihkan dan total Auth user kembali 0 |
| Application password gate | `npm run test:password-policy` | Validator server menerima strong fixture dan menolak null, pendek, grup karakter tidak lengkap, spasi, serta emoji sebagai simbol |
| Application lint | `npm run lint` | Lulus |
| Production build | `npm run build` | Lulus; 29 static pages generated |
| Dependency gate | `npm ci`, `npm audit --audit-level=high`, dan production build | Lulus 22 Juli 2026; Next/ESLint config `16.2.11`, override terkunci `brace-expansion@1.1.16`, `postcss@8.5.10`, dan `sharp@0.35.0`; audit 0 vulnerability dan build 29/29 page lulus |
| Secret scan | Gitleaks `8.29.1`, seluruh riwayat lokal | 65 commit / sekitar 3.64 MB, tidak ada leak |
| Diff hygiene | `git diff --check` | Tidak ada whitespace error; hanya peringatan line-ending Windows |
| Local environment isolation | `npm run test:local-env`, blocked `npm run dev`, `npm run dev:local -- --help`, dan `npm run test:local-app` | Provisional local observation pada candidate increment 22 Juli 2026: 8/8 unit test lulus; URL hosted ditolak, URL loopback diterima, credential proses/file dikosongkan dan secret aktif ditolak, launcher memilih loopback, `/login` 200 serta root redirect 307. Wajib rerun pada candidate SHA melalui CI dan lampirkan raw output sebelum closure |
| GitHub release gate | [PR #5](https://github.com/Aflahul/RAM-Sawit-CB/pull/5) dan branch protection `main` | PR non-draft berstatus `CLEAN`/`MERGEABLE`; seluruh required checks hijau; strict required checks, PR, linear history, dan conversation resolution aktif |
| Independent code review | GitHub review pada reviewed baseline | `afikafiranti` memberikan `APPROVED` pada commit `cc96dbb` tanggal 20 Juli 2026; approval tidak mencakup candidate increment 22 Juli 2026 dan review ulang wajib setelah candidate commit dibuat |
| Vercel preview isolation | Vercel environment metadata, explicit Preview redeploy, inspect, dan authenticated bundle probe | Lulus dan diverifikasi ulang pada deployment HEAD `dpl_4ySoiRQH7ke9vn9odWrxY41Ajvnf`: target `preview`, status Ready; 10/10 aset JavaScript dapat dibaca, ref staging `mfxyeybmjpcdckajfjen` ditemukan, dan ref production `yavntiympbrjlouzkhnl` tidak ditemukan |
| Staging UI smoke | Aplikasi lokal dengan environment staging process-only, akun Super Admin sintetis, dan Chrome headless | Login salah ditolak; login valid redirect ke dashboard; `/dashboard`, `/superadmin/users`, `/owner/master-data`, `/owner/panjar-mitra`, dan `/laporan/harian` seluruhnya HTTP 200 tanpa page/server error; akun dibersihkan dan total Auth user kembali 0 |
| Staging print/export gate | `npm run test:p0:print-export:staging` setelah dua migration diterapkan | `window.print` terpanggil, PDF valid 147.697 byte, XLSX valid 3.700 byte, tanpa HTTP 500/page error; cleanup residue 0 |
| Backup/PITR inventory | `supabase backups list --project-ref ... --output json` pada staging dan production | Keduanya melaporkan `backups: null`, `pitr_enabled: false`, dan `walg_enabled: true`; belum ada restore point yang dapat dijadikan bukti drill |
| Local scoped restore drill | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-p0-local-audit-restore.ps1` | Lulus dan diverifikasi ulang 22 Juli 2026: 1 audit fixture, signature source/target identik, kedua trigger aktif, mutation ditolak, durasi 12,56 detik, cleanup database/dump sementara terverifikasi; bukan pengganti hosted restore proof |

Advisory dependency yang ditemukan ulang pada 22 Juli 2026 ditutup tanpa memakai downgrade besar otomatis npm: Next dan ESLint config dinaikkan ke patch `16.2.11`, lalu versi transitif aman dikunci melalui `overrides`. `npm ci`, `npm audit`, lint, dan production build lulus pada dependency aktual. High advisory lama pada `xlsx` tetap ditutup dengan `write-excel-file@4.1.1`.

## Cakupan Tes Deterministik

Suite P0 membuktikan role tanpa default, DTO tanpa kolom sensitif, legacy RPC tidak dapat dieksekusi actor aplikasi, RPC pengiriman tidak dapat dieksekusi `anon`, trigger function tidak dapat dipanggil langsung role aplikasi, audit append-only, maker-checker Admin, penolakan self-approval, kalkulasi transaksi server-authoritative, penolakan payload finansial buatan client, rekalkulasi input operasional, approval oleh identitas Owner yang berbeda, tepat dua audit event, actor tanpa profile ditolak, agregat kwitansi sesuai snapshot kanonis, retry pembayaran/pembatalan ditolak, serta reversal kas tertaut dan bernilai sama dengan mutasi asli.

Tiga test rollback lama tidak dijadikan release gate karena memilih row bisnis yang diasumsikan sudah ada sehingga gagal pada database bersih. File tersebut dipertahankan sebagai artefak historis; penggantinya adalah fixture sintetis deterministik di `p0_deterministic_release_gate_rollback.sql`.

## Rehearsal Hosted dan Batas Bukti

Project staging sebelumnya berisi delapan tabel portfolio yang tidak terkait aplikasi. Untuk menjaga pemulihan, schema `public` lama tidak dihapus: schema tersebut dipindahkan ke `portfolio_backup_20260719`, akses role API dicabut, kemudian schema `public` baru dibuat untuk rehearsal. Staging menerima baseline dan seluruh migration aplikasi melalui workdir yang secara eksplisit tertaut ke `mfxyeybmjpcdckajfjen`; link workspace utama tetap menunjuk ke production `yavntiympbrjlouzkhnl` dan tidak digunakan untuk push.

`db lint --linked` kini dapat dijalankan melalui Management API dan lulus tanpa temuan. `db advisors --linked --type security --level warn --fail-on warn` tetap gagal pada baseline hosted yang sudah ada: schema cadangan `portfolio_backup_20260719`, dua view operasional lama yang dilaporkan sebagai security definer, helper role, serta RPC `SECURITY DEFINER` terautentikasi yang memang menjadi API aplikasi dan memiliki pemeriksaan role internal. Tidak ada hasil advisor yang menunjuk fungsi/trigger dari migration `20260719231734` atau `20260719232219`. Advisor resmi tetap lulus tanpa temuan pada database PostgreSQL 17 lokal yang dibangun bersih dari migration yang sama. Peringatan cache katalog `pg-delta` tentang file sertifikat muncul setelah migration staging berhasil diaplikasikan; exit code push dan ledger remote kemudian diverifikasi secara terpisah.

Auth staging diuji dengan akun sintetis yang langsung dihapus. Uji tersebut membuktikan endpoint Admin Supabase dapat melewati password policy hosted; karena itu validasi password kuat ditambahkan di server action aplikasi, bukan hanya atribut HTML, dan dijadikan CI gate. Otorisasi server action juga memvalidasi token lewat `auth.getUser()` sebelum memeriksa role. Hosted Auth mewajibkan panjang 12 serta lower/upper/digit, sementara server action juga mewajibkan simbol. Percobaan mengaktifkan leaked-password protection dan session timebox/inactivity timeout ditolak plan staging secara terpisah dan tidak mengubah konfigurasi. TOTP API aktif, tetapi aplikasi belum memiliki enrollment/challenge flow dan belum menegakkan AAL2.

Environment Vercel dipisahkan per target sebelum redeploy: URL, publishable key, dan anon key staging hanya tersedia untuk Preview; service-role staging juga hanya tersedia untuk Preview dan tidak memakai prefix `NEXT_PUBLIC_`. Record URL dan kredensial Production tetap khusus Production/Development sesuai kebutuhan, tanpa record Supabase yang dibagi antara Production dan Preview. Deployment Production tidak diredeploy. Protected Preview kemudian diredeploy eksplisit dengan target Preview dan diverifikasi melalui request Vercel terautentikasi; hasil probe bundle membuktikan staging ref tertanam dan production ref tidak tertanam.

Smoke UI dijalankan tanpa melewati batas Production: proses Next.js lokal menerima environment staging hanya melalui process override dan memiliki safety guard terhadap project ref staging. Test memakai akun sintetis ber-password acak, memeriksa login dan route utama, memanggil cetak kwitansi, menghasilkan PDF melalui media print, dan mengunduh workbook XLSX. Browser/server kemudian ditutup dan seluruh fixture dihapus dalam blok cleanup. Audit akhir berbasis prefix fixture menunjukkan 0 Auth user, profile, mitra, sopir, rekening, dan pembayaran QA.

Bukti ini belum menutup:

- upgrade plan atau kontrol pengganti untuk leaked-password dan session timebox/inactivity timeout;
- implementasi dan enforcement MFA/AAL2 pada aplikasi;
- rehearsal terhadap clone/snapshot production yang representatif dan rekonsiliasi data;
- logical backup production terenkripsi, salinan off-site/Storage, dan restore drill database serta Storage pada clone Docker terisolasi dengan actual RPO/RTO; PITR tidak tersedia dan di luar jalur biaya nol;
- approval final Product Owner/Data-Security/QA-Release yang berlaku untuk keputusan GO/NO-GO.

Sampai semua item tersebut selesai, keputusan rilis tetap **NO-GO**.
