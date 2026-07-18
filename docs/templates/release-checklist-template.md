# Release Checklist: <Versi/Tanggal>

| Field | Nilai |
| --- | --- |
| Release owner |  |
| Target | Preview / Staging / Production |
| Commit/PR |  |
| Scope | `BR-*`, `TASK-*`, `AUD-*` |
| Kelas risiko | KR0 / KR1 / KR2 / KR3 / KR4 |
| Jenis perubahan | UI / aplikasi / dependency / data / migration / auth / security / operasi |
| Klasifikasi data | Publik / internal / pribadi / finansial sensitif |
| Author/implementer |  |
| Waktu rilis |  |
| Status | Preparing / Go / No-Go / Released / Rolled Back |

## 1. Scope dan Persetujuan

- [ ] Scope dan perubahan di luar scope telah ditulis.
- [ ] Product Owner menyetujui perubahan bisnis material.
- [ ] Reviewer domain menyetujui perubahan uang, role, security, atau data.
- [ ] Tidak ada `P0` atau `S0` terkait scope yang masih terbuka. Keduanya tidak dapat dikecualikan.
- [ ] Setiap `S1` non-P0 yang belum ditutup memiliki Exception ID, mitigasi aktif, expiry, serta persetujuan Product Owner + Data/Security + QA.
- [ ] Author, reviewer independen, dan approver wajib adalah identitas manusia yang berbeda sesuai kelas risiko.

### Gate Applicability

`N/A` wajib memiliki alasan dan persetujuan QA. `G2` tidak boleh `N/A` untuk migration, auth, RLS/RPC, data finansial, atau baseline P0. `G5` tidak boleh `N/A` untuk `KR3/KR4`.

| Gate | Applicable/`N/A` | Alasan | Owner | Evidence | Hasil |
| --- | --- | --- | --- | --- | --- |
| `G0 Scope` |  |  |  |  |  |
| `G1 Code/Supply Chain` |  |  |  |  |  |
| `G2 Database/Security` |  |  |  |  |  |
| `G3 Functional QA` |  |  |  |  |  |
| `G4 Release Readiness` |  |  |  |  |  |
| `G5 Approval` |  |  |  |  |  |
| `G6 Post-deploy` |  |  |  |  |  |

## 2. Quality Gate Aplikasi

- [ ] `npm run lint` lulus.
- [ ] `npm run build` lulus.
- [ ] `git diff --check` lulus.
- [ ] Test unit/integration/browser yang relevan lulus.
- [ ] Secret/SAST scan, dependency audit, dan lockfile integrity sesuai gate lulus.
- [ ] Tidak ada secret, data produksi, atau artefak lokal dalam diff.
- [ ] Dependency dan environment baru terdokumentasi.
- [ ] Bila CI belum tersedia, raw output menyimpan commit SHA, waktu UTC, environment, executor, dan reviewer.

## 3. Bisnis dan UX/UI

- [ ] Formula, status, role, dan acceptance criteria diuji dengan contoh nyata.
- [ ] Loading, empty, validation, error, retry, cancel/reversal, dan permission relevan diuji.
- [ ] Desktop dan mobile viewport utama diperiksa.
- [ ] Keyboard, focus, label, contrast, dialog, tabel, export, dan print relevan diperiksa.
- [ ] Istilah dan angka konsisten dengan audit flow serta UX/UI.

## 4. Database dan Security

- [ ] Target project/environment diverifikasi sebelum migration.
- [ ] Clean install migration pada database kosong lulus.
- [ ] Dry-run hanya dipakai untuk inventory migration; tidak diklaim sebagai rehearsal.
- [ ] Upgrade migration benar-benar dieksekusi pada clone/snapshot tersamarkan yang mewakili versi production.
- [ ] Upgrade evidence mencatat durasi/lock, timeout, row count, checkpoint backfill, rekonsiliasi, dan hasil forward-fix/rollback.
- [ ] Backup/PITR dan prosedur restore tersedia sesuai risiko.
- [ ] Restore drill ke target terisolasi lulus; tidak memakai `db reset --linked` atau reset melalui production URL.
- [ ] Rencana forward-fix/rollback dan trigger-nya jelas.
- [ ] Backfill idempotent serta memiliki query rekonsiliasi sebelum/sesudah.
- [ ] RLS, role matrix, RPC permission, dan audit trail diuji.
- [ ] Snapshot, ledger, saldo, row count, dan histori terdampak telah direkonsiliasi.

## 5. Deploy dan Smoke Test

- [ ] Environment variable tersedia tanpa menuliskan nilainya di dokumen.
- [ ] Deployment berhasil dan versi/commit tercatat.
- [ ] Login dan route utama diuji per role.
- [ ] Workflow uang/data kritis dalam scope lulus smoke test.
- [ ] Log/error platform dipantau selama jendela observasi.
- [ ] Owner operasional menerima catatan perubahan yang relevan.

## 6. Bukti

| Gate/test | Commit SHA | Environment + UTC | Expected/actual | Tautan raw evidence | Executor | Independent reviewer |
| --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |

## 7. Keputusan

| Peran | Nama | Go/No-Go | Waktu | Catatan |
| --- | --- | --- | --- | --- |
| Engineering Lead |  |  |  |  |
| QA/Release |  |  |  |  |
| Data/Security, untuk KR3/KR4 terkait |  |  |  |  |
| Product Owner, bila wajib |  |  |  |  |

Perubahan commit, migration, konfigurasi, atau artefak setelah approval membatalkan approval yang terdampak.

## 8. Rollback/Incident

- Trigger yang terjadi:
- Waktu deteksi:
- Tindakan:
- Data yang direkonsiliasi:
- Status akhir:
- Incident record/postmortem:

Gunakan [Incident Record Template](incident-record-template.md) bila incident flow aktif.
