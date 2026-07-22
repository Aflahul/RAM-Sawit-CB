# Rencana Production R-SEC-01 Tanpa Biaya Tambahan Supabase

| Field | Nilai |
| --- | --- |
| Target biaya tambahan Supabase | **Rp0 / USD 0** |
| Project baru/Branching/PITR | Tidak digunakan |
| Recovery strategy | Logical backup CLI + object Storage copy + restore/rehearsal Docker |
| Deployment strategy | Scheduled maintenance; database lebih dahulu, frontend setelah verifikasi |
| Status | **Preparing / No-Go sampai seluruh exit criteria terpenuhi** |
| Evidence awal | [Evaluasi production 20 Juli 2026](../evidence/p0-production-zero-cost-evaluation-2026-07-20.md) |
| Release checklist | [R-SEC-01](R-SEC-01-2026-07-20.md) |
| Architecture decision | [ADR-20260720-001](../decisions/architecture/ADR-20260720-001-zero-cost-logical-backup-release.md), Proposed |

## 1. Keputusan Arsitektur Operasional

Production tetap memakai project Free yang ada. Staging tidak dihapus atau dijadikan clone. Rehearsal memakai Docker lokal sehingga tidak memerlukan project Supabase ketiga. Backup managed/PITR diganti untuk scope release ini dengan logical backup terenkripsi, salinan off-site, maintenance freeze, restore drill lokal memakai data production, dan forward-fix/restore procedure yang telah diuji.

Strategi ini cukup untuk mengendalikan risiko migration pada database kecil saat ini, tetapi tidak setara dengan PITR. Risiko kehilangan transaksi sejak backup terakhir dan downtime manual tetap ada dan wajib diterima Product Owner, Data/Security, serta QA/Release sebelum `GO`.

## 2. Target Recovery Tanpa PITR

| Kondisi | Target |
| --- | --- |
| Release migration | RPO efektif 0 setelah write freeze; tidak boleh ada transaksi baru antara snapshot final dan migration |
| Operasi normal | RPO maksimum 24 jam melalui logical backup harian |
| Restore rehearsal lokal | Selesai maksimal 60 menit termasuk rekonsiliasi |
| Recovery production | RTO awal maksimal 4 jam; tetap provisional sampai rehearsal production-like selesai |
| Retensi tanpa biaya | 7 backup harian, 4 mingguan, 3 bulanan pada media pengguna |

Ukuran database saat ini sekitar 17,6 MB sehingga retensi tersebut kecil. Target tidak boleh diklaim tercapai hanya berdasarkan ukuran; stopwatch dan hasil restore aktual wajib dicatat.

## 3. Fase dan Exit Criteria

### Fase A — Finalisasi Candidate

1. Selesaikan dokumentasi, backup tooling, MFA/AAL2, maintenance mode, dan test dalam satu commit candidate baru.
2. Jalankan seluruh CI dan staging gate.
3. Minta `afikafiranti` atau reviewer manusia independen melakukan review ulang karena candidate tidak lagi sama dengan `cc96dbb`.
4. Buat clean Git worktree pada SHA final untuk operasi production; jangan deploy dari worktree kotor.

Exit criteria: SHA immutable, checks hijau, PR `CLEAN`, approval berlaku tepat pada SHA final.

### Fase B — Media Backup Gratis

1. Tetapkan folder backup di luar repository pada volume BitLocker/EFS atau arsip AES-256 dengan tool gratis seperti 7-Zip.
2. Tetapkan salinan kedua pada USB terenkripsi atau storage cloud yang sudah dimiliki pengguna. Raw dump tidak boleh masuk Git, workspace sinkronisasi publik, atau log CI.
3. Export secara terpisah:
   - `roles.sql` dengan `supabase db dump --role-only`;
   - `schema.sql` dengan `supabase db dump`;
   - `data.sql` dengan `--data-only --use-copy`;
   - schema/data `supabase_migrations`;
   - keempat object Storage melalui API service-role ke folder privat.
4. Buat `SHA256SUMS`, manifest jumlah file/byte, aggregate row count, timestamp UTC, project ref, CLI version, dan operator. Jangan tulis connection string atau secret.
5. Enkripsi arsip, verifikasi arsip dapat dibuka, salin off-site, lalu hapus raw dump.

Exit criteria: dua salinan terenkripsi, hash cocok, Storage 4/4, manifest lengkap, raw dump nol.

### Fase C — Production-like Rehearsal di Docker

1. Restore schema/data production ke database Docker sementara yang namanya tervalidasi.
2. Pastikan baseline semantic diff tetap kosong.
3. Pada clone saja, catat baseline `00000000000000` sebagai applied dan jalankan 14 forward migrations secara berurutan.
4. Catat durasi per migration, lock/error, before/after row count, dan checksum tabel finansial/audit kritis.
5. Jalankan deterministic P0 suite, concurrency, negative role/RPC, lint/advisor, serta UI smoke terhadap clone.
   UI smoke lokal wajib dijalankan melalui environment process-only/launcher loopback; `.env.local` hosted tidak boleh menjadi target development.
6. Restore ulang dari backup ke database sementara kedua dan cocokkan manifest/hash.
7. Hapus clone dan raw data setelah evidence aggregate tersimpan.

Exit criteria: 15/15 pada clone, seluruh gate lulus, restore lulus, residue sementara nol.

### Fase D — MFA dan Kontrol Pengganti Free Plan

1. Implementasikan TOTP enrollment, challenge, verify, recovery UX, dan login continuation.
2. Wajibkan AAL2 untuk Owner/Super Admin pada UI, server action, dan policy/RPC sensitif.
3. Pertahankan invitation-only, password minimum kuat aplikasi, reauthentication password change, serta fail-closed unknown role.
4. Tambahkan idle logout aplikasi dan reauthentication untuk aksi finansial sensitif sebagai kompensasi karena hosted session timeout tidak tersedia pada Free plan.
5. Catat accepted residual risk bahwa leaked-password protection dan hosted session controls tidak tersedia tanpa upgrade; TOTP/AAL2 wajib menjadi mitigasi primer.

Exit criteria: enrollment/login AAL2 lulus pada staging, bypass AAL1 ditolak, recovery flow diuji, risk acceptance ditandatangani.

### Fase E — Maintenance dan Production Migration

1. Umumkan maintenance kepada empat akun production dan aktifkan maintenance/write freeze.
2. Verifikasi tidak ada aktivitas bisnis baru, lalu ambil snapshot logis + Storage kedua tepat sebelum migration.
3. Cocokkan hash, counts, dan waktu snapshot final. Jika backup atau salinan off-site gagal, batalkan release.
4. Dari clean worktree SHA final, jalankan semantic baseline check sekali lagi.
5. Jalankan `supabase migration repair --status applied 00000000000000` terhadap production. Ini hanya boleh dilakukan setelah bukti baseline setara dan approval tersedia.
6. Verifikasi ledger menunjukkan baseline applied dan tepat 14 migration pending.
7. Jalankan `supabase db push --dry-run`; batalkan bila daftar bukan tepat 14 forward migrations yang direhearsal.
8. Jalankan `supabase db push` oleh satu operator. Jangan memakai `db reset --linked`.
9. Verifikasi ledger 15/15, DB lint/advisor, RLS/RPC matrix, row count/checksum, Auth, dan Storage 4/4.
10. Bila database lulus, merge/deploy frontend SHA yang sama ke Vercel. Database harus lebih dahulu karena frontend baru bergantung pada RPC/schema baru; maintenance mencegah frontend lama dipakai selama interval tersebut.
11. Jalankan smoke per role, transaksi sintetis rollback/cleanup, print/export, dan observasi minimum 30 menit sebelum write freeze dibuka.

Exit criteria: DB 15/15, frontend SHA tepat, smoke lulus, tidak ada residue fixture, keputusan `GO` lintas peran tercatat.

## 4. Abort dan Recovery

| Titik gagal | Tindakan |
| --- | --- |
| Backup/hash/Storage copy gagal | Batalkan sebelum perubahan production |
| Baseline diff tidak kosong | Jangan repair ledger; buat reconciliation migration dan ulang rehearsal |
| Dry-run bukan 14 migration | Batalkan; audit ledger/schema |
| Migration gagal sebelum frontend deploy | Pertahankan maintenance; ambil evidence; gunakan forward-fix yang direhearsal atau restore logical backup |
| Rekonsiliasi finansial/audit gagal | Jangan deploy frontend; restore/forward-fix dan ulang seluruh gate |
| Frontend deploy/smoke gagal setelah DB lulus | Rollback frontend ke deployment sebelumnya; maintenance tetap aktif sampai compatibility dipastikan |
| Incident setelah write dibuka | Bekukan write, catat incident ID, backup keadaan gagal, lalu jalankan recovery yang sudah direhearsal |

Restore logical ke production adalah tindakan terakhir dan memerlukan downtime. Jangan mengimpor dump mentah secara parsial atau mengubah migration history untuk “memaksa hijau”.

## 5. Operasi Backup Setelah Release

1. Jalankan logical backup harian melalui Windows Task Scheduler saat aktivitas rendah.
2. Unduh object Storage dan buat manifest/hash pada run yang sama.
3. Enkripsi sebelum menyalin off-site; hapus raw dump sesudah verifikasi.
4. Jalankan restore drill lokal bulanan dan sebelum setiap release migration.
5. Tinjau kapasitas Free plan: database 500 MB, Storage 1 GB, serta risiko project pause karena inaktivitas.
6. Jika RPO 24 jam/RTO 4 jam tidak lagi dapat diterima bisnis, peningkatan plan menjadi keputusan bisnis baru; rencana gratis tidak boleh mengklaim PITR.

## 6. Tindakan Berikutnya yang Aman

1. Tetapkan media enkripsi/off-site yang tersedia tanpa biaya tambahan.
2. Implementasikan backup + Storage export script dengan safety guard dan redaction.
3. Jalankan snapshot production read-only serta restore/migration rehearsal hanya di Docker.
   Gunakan `npm run dev:local` untuk smoke aplikasi terhadap stack Docker; guard harus menolak URL hosted pada mode development.
4. Implementasikan MFA/AAL2 dan maintenance mode.
5. Commit semua perubahan, CI/staging, dan review ulang.

Tidak ada tindakan pada production ledger, schema, Auth, Storage, atau Vercel sampai Fase A-D selesai.
