# Work Package Program: P0 Security dan Kesiapan Rilis

| Field | Nilai |
| --- | --- |
| Program | `PROGRAM-SEC-001` |
| Status | Draft/Blocked / No-Go production; implementasi dan staging proof tersedia, tetapi named owners, recovery, MFA/AAL2, rehearsal clone production, dan approval release lintas peran belum lengkap |
| Target release | `R-SEC-01` containment dan proof; fitur finansial baru tetap No-Go |
| Prioritas | P0 |
| Kelas risiko | KR3; TASK-DATA-001 dan koreksi production tertentu dapat menjadi KR4 |
| Product Owner | Belum ditetapkan dengan nama |
| Engineering Lead | Belum ditetapkan dengan nama |
| Data/Security reviewer | Belum ditetapkan dengan nama |
| QA/Release reviewer | Belum ditetapkan dengan nama |
| Independent code reviewer | `afikafiranti`; GitHub `APPROVED` pada commit `cc96dbb` tanggal 20 Juli 2026; increment setelah SHA tersebut wajib direview ulang |
| Baseline | [Audit Security dan Kesiapan Rilis](../security-release-audit-2026-07-17.md) |
| Proses | [SOP Pengembangan](../development-sop.md) |

## 1. Tujuan dan Batas

Program menutup blocker security, data, business control, QA, dan recovery yang menyebabkan status No-Go. Program tidak menambah fitur finansial baru dan tidak boleh dipakai untuk memperluas scope secara diam-diam.

Scope masuk:

- least-privilege Data API, audit-log integrity, final-state ACL/RPC, Auth fail-closed;
- feature gate modul Coming Soon;
- maker-checker tindakan finansial berisiko;
- CI/supply-chain gate, migration rehearsal, deterministic test, restore proof;
- observability/incident/retention minimum yang dibutuhkan untuk rilis.

Scope tidak masuk:

- fitur bisnis baru;
- cleanup/drop tabel legacy;
- refactor UI massal;
- perubahan formula tanpa BDR terpisah;
- koreksi data production yang belum memiliki work package KR4 spesifik.

## 2. Aturan Program

1. Nama owner/implementer/reviewer wajib diisi sebelum task berubah dari `Draft/Blocked` menjadi `Ready`.
2. Satu identitas manusia tidak boleh dihitung sebagai beberapa approval independen.
3. Migration yang sudah applied tidak diedit. Semua fix memakai migration maju baru.
4. Perubahan production hanya berasal dari commit immutable yang telah direview.
5. Evidence closure masuk [Closure Evidence Matrix](../security-release-audit-2026-07-17.md#9-closure-evidence-matrix).
6. Status `Verified` hanya diberikan reviewer independen. Perubahan setelah approval membatalkan approval terkait.
7. `R-SEC-01` hanya berisi containment/remediasi. Status Go fitur finansial memerlukan review baseline baru.

## 3. Task Register

| Task | Audit | Pri/KR | Accountable role | Target | Status |
| --- | --- | --- | --- | --- | --- |
| `TASK-SEC-001` Batasi pembacaan data sensitif | `AUD-SEC-20260717-001` | P0/KR3 | Data/Security Owner | R-SEC-01 | Implemented and staging-verified; per-finding closure sign-off pending |
| `TASK-SEC-002` Kunci audit trail | `AUD-SEC-20260717-002` | P0/KR3 | Data/Security Owner | R-SEC-01 | Implemented and staging-verified; per-finding closure sign-off pending |
| `TASK-SEC-003` Hardening privilege dan RPC | `AUD-SEC-20260717-003` | P0/KR3 | Data/Security Owner | R-SEC-01 | Implemented and staging-verified; per-finding closure sign-off pending |
| `TASK-SEC-004` Auth dan role fail-closed | `AUD-SEC-20260717-004` | P0/KR3 | Data/Security Owner | R-SEC-01 | Partial: signup/password/reauth and fail-closed proof pass; MFA/AAL2 plus plan-dependent session controls pending |
| `TASK-SEC-005` Feature gate modul beku | `AUD-SEC-20260717-005` | P0/KR3 | Engineering Lead | R-SEC-01 | Implemented and staging smoke-tested; security/UX/accessibility closure pending |
| `TASK-SEC-006` Snapshot transaksi dihitung server | `AUD-SEC-20260717-006` | P0/KR3 | Engineering + Data/Security | R-SEC-01 | Implemented and staging-verified; per-finding closure sign-off pending |
| `TASK-BIZ-001` Maker-checker finansial | `AUD-BIZ-20260717-001` | P0/KR3 | Product Owner | R-SEC-01 | Implemented and staging-verified; Product Owner/UAT approval pending |
| `TASK-QA-001` Required CI dan supply chain | `AUD-QA-20260717-001` | P0/KR3 | QA/Release Owner | R-SEC-01 | Technical controls active: required CI, CodeQL, Gitleaks, dependency gate, and strict branch protection pass at `cc96dbb` |
| `TASK-DATA-001` Upgrade rehearsal dan backfill proof | `AUD-DATA-20260717-001` | P0/KR3-4 | Data Owner | R-SEC-01 | Clean install and fresh staging 15/15 pass; representative production-clone upgrade proof pending |
| `TASK-QA-002` Deterministic financial/security test | `AUD-QA-20260717-002` | P0/KR3 | QA Owner | R-SEC-01 | Deterministic local/staging, concurrency, UI smoke, and print/export gates pass; formal QA closure pending |
| `TASK-QA-003` RPO/RTO dan restore drill | `AUD-QA-20260717-003` | P0/KR3 | QA/Release + Data Owner | R-SEC-01 | Partial: local scoped audit restore passes; zero-cost production logical backup, salinan off-site/Storage, Docker production-clone restore, serta actual RPO/RTO pending; PITR dan isolated hosted drill sengaja tidak dipakai karena tidak tersedia dalam jalur biaya nol |
| `TASK-QA-004` Observability, incident, retention | `AUD-QA-20260717-004` | P1/KR2-3 | Engineering Lead | Setelah containment; scope-dependent | Draft |
| `TASK-UX-001` UX lock route Coming Soon | `AUD-UX-20260717-001` | P0/KR3 | UX/UI Reviewer | Bersama TASK-SEC-005 | Implemented locally; accessibility reviewer pending |

Evidence implementasi dan staging saat ini: [Rehearsal P0 19 Juli 2026](../evidence/p0-local-rehearsal-2026-07-19.md). Review PR independen telah tersedia pada commit final, tetapi status `Verified` per temuan tetap memerlukan closure evidence dan verifier yang sesuai domain. Status release terpadu dicatat pada [Release Checklist R-SEC-01](../releases/R-SEC-01-2026-07-20.md).

## 4. Acceptance dan Test Contract

### TASK-SEC-001: Pembacaan data sensitif

- `AC-SEC-001`: Admin hanya menerima kolom/row yang diperlukan tugas operasional melalui policy, view `security_invoker`, atau RPC minimum.
- `AC-SEC-002`: Fee, sewa, profit, identitas/dokumen sensitif, dan data Owner ditolak dari direct Data API untuk role yang tidak berwenang.
- `AC-SEC-003`: `anon`, profile hilang, unknown/disabled role, dan stale session tidak memperoleh data bisnis.
- `TEST-SEC-001`: before/after ACL-RLS-view-RPC matrix untuk seluruh actor dengan raw evidence.
- `TEST-SEC-002`: positive test Owner/Super Admin dan negative test Admin/Data API pada data representatif tersanitasi.

### TASK-SEC-002: Integritas audit trail

- `AC-SEC-004`: `PUBLIC`, `anon`, dan `authenticated` tidak memiliki mutation langsung pada tabel audit.
- `AC-SEC-005`: internal trigger/RPC yang disetujui tetap dapat menulis actor, action, before/after, reason, dan waktu secara valid.
- `AC-SEC-006`: audit row append-only; update/delete/truncate ditolak dan perubahan privileged terdeteksi/direview.
- `TEST-SEC-003`: direct insert/update/delete/truncate ditolak dari seluruh role aplikasi.
- `TEST-SEC-004`: setiap RPC kritis menghasilkan event audit tepat satu kali dengan actor sebenarnya.

Artefak implementasi yang menunggu rehearsal staging:

- migration [`20260718004159_p0_secure_audit_and_api.sql`](../../supabase/migrations/20260718004159_p0_secure_audit_and_api.sql);
- smoke test rollback [`p0_security_containment_rollback.sql`](../../supabase/tests/p0_security_containment_rollback.sql);
- [runbook restore audit log](../runbooks/audit-log-restore.md).

### TASK-SEC-006: Snapshot transaksi server-authoritative

- `AC-SEC-014`: browser hanya mengirim input operasional; tarif, fee, total, dan snapshot keuangan dipilih serta dihitung database berdasarkan aturan efektif pada tanggal transaksi.
- `AC-SEC-015`: create/update RPC menolak atau mengabaikan nilai keuangan buatan client dan menghasilkan nilai deterministik dalam satu transaction.
- `AC-SEC-016`: transaksi dalam kwitansi aktif/dibayar tidak dihitung ulang; koreksi menggunakan reversal dan kwitansi baru sehingga bukti lama tetap konsisten.
- `AC-SEC-017`: setelah frontend memakai DTO/RPC baru, Admin tidak memiliki direct insert/update transaksi atau direct read histori fee/profit yang tidak diperlukan.
- `TEST-SEC-010`: payload dengan fee, tarif, total, dan snapshot palsu ditolak atau tidak memengaruhi hasil database.
- `TEST-SEC-011`: input operasional yang sama menghasilkan snapshot yang sama menurut tarif efektif tanggal transaksi.
- `TEST-QA-005`: kwitansi dibayar sebelum migrasi tetap identik setelah deploy dan setelah tarif master berubah.
- `TEST-SEC-012`: matrix Admin/Data API membuktikan direct write serta pembacaan fee/profit sensitif ditolak setelah frontend dimigrasikan.

### TASK-SEC-003: Final-state privilege dan RPC

- `AC-SEC-007`: default privileges untuk tabel/function baru minimum dan reproducible.
- `AC-SEC-008`: tidak ada `DELETE/TRUNCATE` pada histori finansial untuk role aplikasi.
- `AC-SEC-009`: seluruh RPC mutation mencabut execute dari `PUBLIC/anon`; `SECURITY DEFINER` memiliki fixed search path, auth, role, dan input validation.
- `TEST-SEC-005`: final-state ACL/function-execute matrix sebelum/sesudah clean install dan upgrade.
- `TEST-SEC-006`: anonymous direct RPC mutation ditolak; role sah hanya dapat menjalankan scope-nya.

### TASK-SEC-004: Hosted Auth dan role fail-closed

- `AC-SEC-010`: role tidak dikenal/profile hilang tidak dinormalisasi menjadi Admin pada client/server/database.
- `AC-SEC-011`: hosted Auth memenuhi invitation-only, password/leaked-password control, MFA privileged role, session/idle, dan reauthentication baseline yang disetujui.
- `AC-SEC-012`: disable/role change menolak sesi lama dalam batas yang disetujui.
- `TEST-SEC-007`: actor matrix mencakup anon, no-profile, unknown, disabled, role-changed, stale session, UI, Data API, RPC, dan Storage.
- `TEST-SEC-008`: Auth attestation menyimpan nilai aktual, expected, pass/fail, environment, waktu, executor, dan reviewer.

### TASK-SEC-005 dan TASK-UX-001: Feature gate Coming Soon

- `AC-SEC-013`: route beku tidak me-mount child, tidak menjalankan query/effect, dan backend menolak mutation langsung.
- `AC-UX-001`: keyboard/focus tidak dapat mencapai kontrol tersembunyi; background inert dan status “Belum tersedia” terbaca assistive technology.
- `AC-UX-002`: sidebar dan bottom navigation menerapkan keputusan hide/disabled yang sama serta role-aware.
- `TEST-SEC-009`: direct handler/Data API/RPC write pada seluruh modul beku ditolak.
- `TEST-UX-001`: keyboard, screen-reader smoke, desktop/mobile navigation, dan direct URL test.

### TASK-BIZ-001: Maker-checker

- `AC-BIZ-001`: BDR menetapkan aksi/nominal yang wajib maker-checker, identity rules, dan break-glass.
- `AC-BIZ-002`: database menolak `diajukan_oleh = disetujui_oleh` pada scope wajib.
- `AC-BIZ-003`: break-glass memerlukan incident ID, reason, TTL, scope, revoke, dan review satu hari kerja.
- `TEST-BIZ-001`: self-approval normal ditolak; dua identitas sah berhasil; role stacking satu orang tidak dianggap dua approval.
- `TEST-BIZ-002`: perubahan setelah approval membatalkan approval dan memerlukan review ulang.

### TASK-QA-001: CI dan supply chain

- `AC-QA-001`: protected `main` memerlukan lint, build, test, secret/SAST, dependency, lockfile, dan migration checks yang disepakati.
- `AC-QA-002`: failure memblokir merge; bypass tercatat dan hanya melalui jalur emergency yang disetujui.
- `AC-QA-003`: dependency critical/high memblokir kecuali Exception Record S1 non-P0 yang sah.
- `TEST-QA-001`: PR sengaja gagal pada tiap required check dan terbukti tidak dapat merge normal.
- `TEST-QA-002`: artifact evidence menyimpan SHA, UTC, environment, executor, dan reviewer.

### TASK-DATA-001: Migration/upgrade rehearsal

- `AC-DATA-001`: clean install seluruh migration lulus pada local terisolasi.
- `AC-DATA-002`: dry-run hanya dipakai sebagai inventory; upgrade benar-benar dijalankan pada clone/snapshot tersamarkan dari versi production.
- `AC-DATA-003`: lock duration, timeout, row count, checkpoint, backfill idempotency, rekonsiliasi, serta forward-fix/rollback tercatat.
- `AC-DATA-004`: `db reset --linked`, source rewriting, migration applied edit, dan service-role direct-write ad hoc dilarang/enforced melalui review.
- `TEST-DATA-001`: clean + upgrade path menghasilkan schema/ACL/RLS/function state yang sama.
- `TEST-DATA-002`: rerun backfill aman dan before/after reconciliation sesuai expected.

### TASK-QA-002: Deterministic test baseline

- `AC-QA-004`: fixture sintetis/staging tidak memilih transaksi production secara acak.
- `AC-QA-005`: suite mencakup formula boundary, authorization negative, concurrency, retry, idempotency, reversal, snapshot, ledger, print/export, dan error network sesuai risiko.
- `AC-QA-006`: test destruktif tidak dapat diarahkan ke production dan target environment dibuktikan sebelum run.
- `AC-QA-010`: development interaktif fail-closed bila target Supabase bukan loopback; launcher lokal hanya mengambil API URL dan publishable/anon key dari Supabase Docker, mengosongkan credential sensitif dari environment proses/file, dan config guard menolak nilai sensitif yang masih aktif.
- `TEST-QA-003`: repeated run dari fixture bersih memberikan hasil sama.
- `TEST-QA-004`: double-click/retry/concurrent payment tidak menggandakan uang atau audit event.
- `TEST-QA-006`: unit test membuktikan URL hosted ditolak, URL loopback diterima, environment file hanya dibaca nama variabelnya, credential diwariskan/dimuat dikosongkan, dan config guard menolak secret aktif; smoke launcher membuktikan target lokal serta flow login/redirect pengguna tanpa sesi.

### TASK-QA-003: Recovery proof

- `AC-QA-007`: Product Owner/Engineering Lead menyetujui RPO/RTO numerik melalui BDR.
- `AC-QA-008`: logical backup terenkripsi, salinan off-site/Storage, serta recovery DB dan Storage melalui clone Docker memenuhi target RPO/RTO yang disetujui; PITR hanya dapat dipertimbangkan sebagai keputusan biaya terpisah.
- `AC-QA-009`: restore dilakukan ke project terisolasi dan lulus rekonsiliasi saldo, ledger, snapshot, role, row count, serta file bukti.
- `TEST-REC-001`: restore drill mencatat actual RPO/RTO, operator, target, checksum/row count, hasil, dan reviewer.

### TASK-QA-004: Operasional resilience

- `AC-OPS-001`: health/error signal, alert route, observation window, IC/cadangan, secure channel, dan contact tree tersedia.
- `AC-OPS-002`: incident tabletop memakai template dan menghasilkan action owner/target.
- `AC-OPS-003`: retensi evidence disetujui Accounting/Legal/Data Security dan diuji retrieval/disposal-nya.
- `TEST-OPS-001`: alert-to-acknowledge dan incident tabletop lulus target.
- `TEST-OPS-002`: evidence release dapat ditemukan, diverifikasi integritasnya, diberi legal hold, dan dihapus setelah expiry pada data uji.

## 5. Dependency dan Urutan

```text
Named owners + staging + BDR maker-checker/RPO-RTO
  -> SEC-001/002 containment
  -> SEC-006 server-authoritative snapshots + frontend migration
  -> SEC-001 least-privilege DTO/read revoke + SEC-003/004/005 + UX-001
  -> QA-001 CI + DATA-001 rehearsal + QA-002 deterministic tests
  -> BIZ-001 enforcement + QA-003 restore proof
  -> QA-004 resilience sesuai scope
  -> closure evidence review
  -> baseline audit ulang
  -> GO/NO-GO decision
```

Task dapat berjalan paralel hanya jika ownership file/environment tidak tumpang tindih. Migration security digabung dalam urutan yang direhearsal agar policy/grant sementara tidak membuka akses.

## 6. Definition of Ready Program

- [ ] Product Owner, Engineering Lead, Data/Security, QA/Release, dan Release Operator diisi dengan identitas manusia.
- [ ] Staging Supabase/Vercel terpisah serta data sintetis/tersamarkan tersedia.
- [ ] Target project, backup tier, hosted Auth, dan credential custody diverifikasi.
- [ ] BDR maker-checker dan RPO/RTO disetujui.
- [ ] File ownership, migration order, test fixture, serta release window disepakati.
- [ ] Tidak ada task P0 yang dinyatakan `N/A`.

## 7. Definition of Done Program

- [ ] Semua task P0 berstatus Verified oleh reviewer independen.
- [ ] Closure Evidence Matrix lengkap dan tautan raw evidence dapat diakses reviewer.
- [ ] G0-G5 lulus sebelum deploy; G6 lulus setelah containment deploy.
- [ ] Remote ACL/RLS/RPC/Auth matrix dan audit-log integrity terverifikasi ulang.
- [ ] Migration clean/upgrade, deterministic suite, restore drill, dan maker-checker lulus.
- [ ] Tidak ada regression pada pengiriman, kwitansi, kas, Pinjaman/Panjar, pembayaran, snapshot, laporan, dan role.
- [ ] Audit Security/Release baseline baru diterbitkan dan keputusan GO/NO-GO disetujui.
