# Audit Security dan Kesiapan Rilis

| Metadata | Nilai |
| --- | --- |
| Tanggal baseline | 17 Juli 2026 |
| Terakhir diperbarui | 18 Juli 2026 |
| Status | **NO-GO untuk rilis finansial baru** |
| Metode | Review kode/migration, introspeksi remote read-only, ACL/RLS/RPC review, dependency audit, dan pemeriksaan quality gate |
| Reviewer | QA, Security, Data, dan Release independen |
| Pemilik tindak lanjut | Engineering Lead dan Data/Security Owner |
| Aturan audit | [Tata Kelola Audit](audit-governance.md) |

## 1. Kesimpulan

Dokumentasi tata kelola sudah menuju pola yang benar, tetapi kontrol belum seluruhnya ditegakkan oleh database dan pipeline. Dua temuan S0 menunjukkan bahwa pembatasan UI belum cukup untuk melindungi data sensitif dan audit trail belum sepenuhnya tahan manipulasi pengguna login.

Keputusan sementara:

- hentikan rilis fitur finansial baru sampai temuan P0/S0 ditutup;
- penggunaan operasional yang tetap berjalan harus dipantau Owner dan tidak memperluas akses/fitur sensitif;
- perbaikan dilakukan melalui migration baru yang direview, bukan mengubah migration yang sudah diterapkan;
- hasil perbaikan harus diuji dari Data API/RPC dengan setiap role, bukan hanya melalui route dan menu;
- status `GO` hanya diberikan setelah bukti negative authorization test, rekonsiliasi data, migration rehearsal, dan approval QA/Security tersedia.

S0, kegagalan restore, akses lintas role, serta migration yang belum direhearsal tidak dapat dikecualikan. Exception S1 harus memiliki persetujuan Product Owner, Security, dan QA, disertai mitigasi serta tanggal kedaluwarsa.

## 2. Batas dan Bukti

Review independen mencakup 54 migration lokal/remote yang dilaporkan sinkron, policy/ACL remote read-only, helper role frontend, Supabase Auth config lokal, dua smoke test SQL, script operasional, package dependency, dan dokumen release.

Bukti yang sudah tersedia:

- ESLint lulus pada saat review.
- `git diff --check` lulus pada saat review.
- Remote database lint level warning dilaporkan bersih.
- Introspeksi remote menemukan 37 dari 41 tabel memakai pola `SELECT USING (true)` untuk role `authenticated`.
- `npm audit --omit=dev` pada saat review menemukan dependency berisiko tinggi pada `xlsx` dan jalur moderat Next/PostCSS.

Catatan batas:

- hasil remote harus direproduksi dan disimpan sebagai evidence pada work package perbaikan;
- konfigurasi hosted Auth perlu diverifikasi langsung karena `supabase/config.toml` hanya menjelaskan baseline lokal;
- production build tidak dijalankan oleh reviewer independen; quality gate integrasi akhir tetap wajib menjalankannya.

## 3. Register Temuan

| ID | Severity | Prioritas | Gate | Release blocker | Exception | Ringkasan | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `AUD-SEC-20260717-001` | S0 | P0 | G2 | Ya | Tidak | Akun login dapat membaca data sensitif langsung melalui Data API karena policy baca terlalu luas | Open; containment siap, DTO/RPC belum |
| `AUD-SEC-20260717-002` | S0 | P0 | G2 | Ya | Tidak | Pengguna login masih dapat menulis/mengubah baris audit dan memalsukan isi audit trail | Open; implementasi siap, verifikasi staging belum |
| `AUD-SEC-20260717-003` | S1 | P0 | G2 | Ya | Tidak | Revoke privilege tidak persisten untuk tabel/fungsi baru; masih ada risiko `TRUNCATE` dan RPC mutation untuk `anon/PUBLIC` | Open |
| `AUD-SEC-20260717-004` | S1 | P0 | G2 | Ya | Tidak | Baseline hosted Auth, MFA, session, dan role fail-closed belum dibuktikan | Open |
| `AUD-SEC-20260717-005` | S1, confidence statis | P0 | G2/G3 | Ya | Tidak | Route Coming Soon masih me-mount child/query/action; backend write denial dan keyboard lock belum dibuktikan | Open |
| `AUD-SEC-20260717-006` | S0 | P0 | G2/G3 | Ya | Tidak | Browser dapat mengirim nilai snapshot keuangan transaksi sehingga angka strategis belum sepenuhnya dihitung dan dikunci oleh database | Open |
| `AUD-BIZ-20260717-001` | S1 | P0 | G0/G3/G5 | Ya | Tidak | Maker-checker Pinjaman belum ditegakkan sepenuhnya di database | Open |
| `AUD-QA-20260717-001` | S1 | P0 | G1/G4 | Ya | Tidak | Gate CI/supply chain belum enforced dan dependency audit belum lulus | Open |
| `AUD-DATA-20260717-001` | S1 | P0 | G2/G4 | Ya | Tidak | Migration/backfill belum memiliki rehearsal dan rollback evidence yang reproducible | Open |
| `AUD-QA-20260717-002` | S1 | P0 | G3 | Ya | Tidak | Test finansial terlalu tipis dan memakai data bisnis yang tersedia secara nondeterministik | Open |
| `AUD-QA-20260717-003` | S1 | P0 | G2 | Ya | Tidak | Target RPO/RTO, backup capability, dan restore drill terisolasi belum dibuktikan | Open |
| `AUD-QA-20260717-004` | S1 | P1 | G4/G6 | Sesuai scope | Ya, S1 non-P0 | Observability, incident operation, dan evidence retention belum operasional | Open |

## 4. Temuan Kritis

### AUD-SEC-20260717-001: Data sensitif dapat dibaca lintas role

**Kondisi:** banyak tabel memakai policy `FOR SELECT TO authenticated USING (true)`. Contoh tersedia pada `transaksi_mitra`, `fee_owner_mitra_history`, dan tabel dokumen Pinjaman. Menyembunyikan kolom atau halaman dari Admin tidak mencegah pembacaan langsung melalui Supabase Data API.

**Dampak:** Fee Owner, tarif/sewa, nilai bersih, identitas penerima, atau data sensitif lain dapat terbaca oleh akun login yang tidak memerlukannya.

**Bukti kode:**

- `supabase/migrations/20260716003140_p0_business_control_release_gate.sql` pada policy `transaksi_mitra` dan `fee_owner_mitra_history`;
- `supabase/migrations/20260716100224_add_piutang_document_approval_workflow.sql` pada policy baca dokumen Pinjaman.

**Containment yang telah disiapkan, belum diterapkan:** migration
[`20260717045357_p0_secure_data_api_and_audit_log.sql`](../supabase/migrations/20260717045357_p0_secure_data_api_and_audit_log.sql)
menambahkan role gate restriktif pada 37 tabel agar akun tanpa profile atau role
yang tidak dikenal tidak dapat memakai policy permissive lain. Ini belum memenuhi
least-privilege kolom untuk Admin; DTO/RPC minimum dan pencabutan direct read
tetap wajib diselesaikan bersama `AUD-SEC-20260717-006`.

**Kontrol target:**

1. Terapkan default-deny untuk data sensitif.
2. Cabut table-wide `SELECT` yang tidak diperlukan.
3. Sediakan view `security_invoker` atau RPC dengan kolom minimum per role.
4. Uji matriks `anon`, pengguna tanpa profile, Admin, Owner, Super Admin, role berubah, dan sesi lama melalui Data API/RPC.
5. Buktikan Admin tidak dapat membaca kolom profit, fee, sewa, dokumen identitas, dan data owner yang dibatasi.

### AUD-SEC-20260717-002: Audit trail dapat dipalsukan

**Kondisi:** eksekusi helper audit sudah dibatasi, tetapi policy tabel `audit_log` masih menerima `INSERT` dari `authenticated` selama actor mengaku sebagai user aktif. ACL remote juga dilaporkan masih memberi mutation privilege pada tabel audit.

**Dampak:** pengguna dapat membuat event, nilai before/after, approval, atau waktu audit palsu. Audit trail tidak dapat dipakai sebagai bukti kontrol jika penulisannya tidak eksklusif dari jalur internal.

**Bukti kode:** `supabase/migrations/20260716003140_p0_business_control_release_gate.sql` pada policy insert `audit_log` dan migration hardening sesudahnya.

**Implementasi yang telah disiapkan, belum diverifikasi:** migration containment
memindahkan penulisan audit ke role internal `NOLOGIN`, mencabut mutation tabel
dari role aplikasi, dan menolak update/delete/truncate melalui trigger. Smoke test
rollback tersedia di
[`p0_security_containment_rollback.sql`](../supabase/tests/p0_security_containment_rollback.sql),
serta prosedur pemulihan terkontrol tersedia pada
[`audit-log-restore.md`](runbooks/audit-log-restore.md). Status tetap `Open` sampai
upgrade rehearsal dan negative test lulus di staging terisolasi.

**Kontrol target:**

1. Revoke seluruh `INSERT`, `UPDATE`, `DELETE`, dan `TRUNCATE` tabel audit dari `PUBLIC`, `anon`, dan `authenticated`.
2. Hapus policy mutation client.
3. Izinkan penulisan hanya melalui trigger/RPC internal yang memvalidasi actor serta konteks aksi.
4. Jadikan log append-only dan pertimbangkan checkpoint/hash atau salinan terpisah untuk deteksi perubahan.
5. Tambahkan negative test yang mencoba mutation audit langsung dari setiap role aplikasi.

### AUD-SEC-20260717-006: Snapshot keuangan masih ditentukan browser

**Kondisi:** form pengiriman mengirim nilai seperti fee Owner, total fee, dan
snapshot perhitungan bersama data operasional. RPC pembaruan juga masih menerima
sebagian field hasil hitung. Pengguna yang dapat memodifikasi request browser
berpotensi mengirim angka yang berbeda dari aturan bisnis meskipun UI menampilkan
hasil yang benar.

**Dampak:** kwitansi, pendapatan Owner, sewa Armada CB, dan laporan dapat berasal
dari input yang telah dimanipulasi. Snapshot membuat angka historis tetap, tetapi
tidak menjamin angka awalnya benar jika sumber otoritatif masih client.

**Bukti kode:** `components/transaksi/FormPengirimanModal.js` pada payload
penyimpanan transaksi serta kontrak `update_transaksi_mitra_controlled` yang masih
menerima field keuangan hasil hitung.

**Kontrol target:**

1. Browser hanya mengirim fakta operasional, misalnya mitra, armada, tanggal,
   berat dari pabrik, potongan kg, dan pilihan perlakuan sewa.
2. Database memilih tarif/fee efektif berdasarkan tanggal lalu menghitung berat
   dibayar, nilai bruto, fee Owner, sewa, dan nilai bersih secara atomik.
3. RPC create/update mengabaikan atau menolak field keuangan buatan client.
4. Transaksi yang sudah masuk kwitansi tetap memakai snapshot lama dan hanya
   dapat dikoreksi melalui reversal serta penerbitan ulang.
5. Setelah frontend berpindah ke DTO/RPC baru, cabut direct insert/update dan
   direct read kolom sensitif dari role Admin.
6. Uji request yang sengaja memalsukan tarif, fee, total, dan snapshot.

## 5. Temuan Tinggi

### AUD-SEC-20260717-003: Final-state privilege tidak dijaga

Revoke global hanya memproses object yang sudah ada saat migration hardening dijalankan. Tabel/fungsi yang dibuat sesudahnya dapat kembali mewarisi privilege berlebih. Review menemukan tabel Pinjaman yang belum mencabut `TRUNCATE` dan RPC `SECURITY DEFINER` yang perlu diperiksa akses `PUBLIC/anon`-nya.

Kontrol target:

- atur default privileges minimum;
- revoke eksplisit `PUBLIC, anon` pada seluruh RPC mutation;
- validasi `auth.uid()` serta app role di fungsi yang memang harus `SECURITY DEFINER`;
- audit final-state ACL/RLS/RPC setiap migration dan pada release gate.

### AUD-BIZ-20260717-001: Maker-checker belum konsisten

Owner/Super Admin yang membuat Pinjaman dapat ter-auto-approve, dan jalur penyerahan uang belum selalu memisahkan pembuat, penyetuju, serta penjaga kas.

Kontrol target untuk tim tiga pengguna:

- Admin menjadi maker pencatatan rutin;
- Owner menjadi checker approval, reversal, tarif, dan exception;
- Super Admin menjadi custodian akun/deployment dan break-glass, bukan operator harian;
- nominal/aksi berisiko wajib memenuhi `diajukan_oleh <> disetujui_oleh`;
- self-approval hanya melalui break-glass terbatas waktu, wajib alasan dan review setelah kejadian.

### AUD-QA-20260717-001: Quality gate belum enforced

Repository belum memiliki required CI, unit runner, atau E2E. Pull request checklist membantu review, tetapi tidak dapat mencegah merge saat lint/build/test gagal. Dependency audit juga belum lulus.

Kontrol target:

- protected `main` dan required checks;
- CI untuk lint, build, test, secret scan, dependency audit, migration lint, dan lockfile integrity;
- critical/high dependency menjadi blocker kecuali ada exception tertulis, mitigation, owner, dan expiry.

### AUD-DATA-20260717-001: Migration dan backfill belum reproducible

Risiko saat ini mencakup migration produksi sebelum commit immutable direview, source rewriting dengan `pg_get_functiondef`, dan script direct-write yang dapat mengabaikan error.

Kontrol target:

- migration harus berada dalam commit/PR yang direview sebelum production;
- rehearsal clean install dan upgrade pada clone data tersamarkan;
- pola expand-migrate-contract untuk perubahan kontrak;
- backfill idempotent, atomik atau resumable, serta memiliki before/after reconciliation;
- larang perubahan migration yang sudah applied dan script service-role ad hoc.

### AUD-QA-20260717-002: Test finansial tidak deterministik

Dua smoke test SQL belum cukup untuk formula, authorization, concurrency, idempotency, dan recovery. Salah satu test memilih data bisnis tersedia, melakukan reversal, lalu rollback. Pola ini tidak boleh dijalankan pada production karena dapat mengunci atau menyentuh transaksi aktual.

Kontrol target:

- fixture khusus dan terisolasi di staging;
- larangan test destruktif pada production meskipun dibungkus rollback;
- negative authorization test dan direct Data API test;
- concurrency/double-click/retry/idempotency;
- formula batas, pembulatan, kg/ton, tanggal, dan zona waktu;
- ledger balance, snapshot immutability, orphan, duplicate, reversal ganda, print/export, serta error jaringan.

### AUD-SEC-20260717-004: Hosted Auth belum terverifikasi

Baseline lokal masih memungkinkan signup dan password minimum rendah tanpa bukti MFA/session hardening. Helper frontend juga menormalisasi role tidak dikenal menjadi Admin, sehingga perilaku default belum fail-closed.

Kontrol target:

- hosted-setting attestation: invitation-only, password kuat, leaked-password protection, dan session policy;
- MFA untuk Owner/Super Admin;
- reauthentication untuk aksi sensitif;
- role tidak dikenal atau profile hilang harus ditolak, bukan menjadi Admin;
- uji sesi lama setelah role berubah dan setelah user dinonaktifkan.

### AUD-SEC-20260717-005: Feature gate Coming Soon belum terbukti

Empat route lokal/petani tetap me-mount child page di balik overlay. Query/effect dapat berjalan, sementara keyboard focus dan backend write denial belum dibuktikan. Ini adalah finding primer untuk mount/query/write guard; finding UX pendamping hanya mengelola focus, keyboard, inert, dan komunikasi status.

Kontrol target:

- server/route feature flag tidak me-mount child yang dibekukan;
- handler dan database menolak mutation meski endpoint dipanggil langsung;
- negative test Data API/RPC serta keyboard test membuktikan tidak ada kontrol/action yang dapat dicapai;
- status S1 dikonfirmasi atau dinaikkan setelah runtime evidence, bukan hanya inferensi source.

### AUD-QA-20260717-003: Restore readiness belum dibuktikan

Backup tanpa restore drill tidak membuktikan kemampuan pemulihan. Target RPO/RTO, kemampuan tier/PITR, DB + Storage recovery, dan rekonsiliasi setelah restore belum disetujui/direhearsal.

Kontrol target:

- RPO/RTO numerik disetujui Product Owner/Engineering Lead;
- restore DB dan Storage ke project terisolasi;
- role, saldo, ledger, snapshot, row count, serta file bukti direkonsiliasi;
- actual RPO/RTO memenuhi target atau rilis tetap No-Go.

### AUD-QA-20260717-004: Observability, incident, dan retensi belum operasional

Belum ada alert route, contact tree, incident rehearsal, dan kebijakan retensi yang telah disetujui legal/accounting. Runbook/template sudah disiapkan tetapi belum menjadi kontrol yang teruji.

Kontrol target:

- health check, centralized error log, alert owner, dan observation window;
- incident severity, containment, preservation, recovery, reconciliation, communication, dan postmortem;
- evidence release, migration, approval, dan audit finansial disimpan sesuai kebijakan retensi yang telah divalidasi legal.

## 6. Status Mandatory Release Gates

Definisi normatif dan applicability `G0-G6` hanya berada pada [SOP Pengembangan Bagian 16](development-sop.md). Audit ini mengagregasi status blocker:

| Gate | Status baseline | Finding utama |
| --- | --- | --- |
| `G0 Scope` | Blocked | `AUD-BIZ-20260717-001`; work package/AC belum lengkap |
| `G1 Code/Supply Chain` | Blocked | `AUD-QA-20260717-001` |
| `G2 Database/Security` | Blocked | `AUD-SEC-20260717-001` sampai `AUD-SEC-20260717-006`, `AUD-DATA-20260717-001`, `AUD-QA-20260717-003` |
| `G3 Functional QA` | Blocked | `AUD-BIZ-20260717-001`, `AUD-QA-20260717-002`, `AUD-SEC-20260717-005`, `AUD-SEC-20260717-006` |
| `G4 Release Readiness` | Blocked | `AUD-QA-20260717-001`, `AUD-DATA-20260717-001`, `AUD-QA-20260717-004` sesuai scope |
| `G5 Approval` | Blocked | `AUD-BIZ-20260717-001`; identitas reviewer/approver belum dibuktikan |
| `G6 Post-deploy` | Belum dapat dinilai | Release baru belum boleh dimulai |

## 7. Urutan Remediasi

1. **P0 Security containment:** terapkan role gate restriktif dan audit append-only setelah rehearsal staging.
2. **P0 Server-authoritative finance:** pindahkan perhitungan serta snapshot transaksi dari browser ke RPC/database tanpa mengubah kwitansi historis.
3. **P0 Least privilege:** pindahkan frontend ke DTO/RPC minimum, cabut direct read/write sensitif, tutup privilege/RPC berlebih, dan ubah role default menjadi fail-closed.
4. **P0 Proof:** bangun negative authorization matrix dari Data API/RPC dan rekonsiliasi final-state ACL.
5. **P0 Business control:** tegakkan maker-checker untuk Pinjaman, pembayaran, reversal, perubahan rekening, dan role.
6. **P0 Delivery control:** pasang required CI, dependency policy, migration rehearsal, dan deterministic staging tests.
7. **P1 Resilience:** restore drill, observability, incident runbook, dan evidence retention.
8. Setelah semua P0 terverifikasi, lakukan review independen ulang dan putuskan `GO/NO-GO` melalui Release Checklist.

## 8. Anti-Pattern yang Dilarang

- Menganggap route/sidebar sebagai authorization.
- Policy `USING (true)` pada data sensitif tanpa alasan dan mitigasi terdokumentasi.
- Mutation langsung ke audit log dari client.
- Memercayai fee, tarif, total, atau snapshot keuangan yang dikirim browser.
- `SECURITY DEFINER` terbuka untuk `PUBLIC/anon`.
- Direct production write memakai service-role script ad hoc.
- Test destruktif pada data production meskipun memakai rollback.
- Migration production sebelum commit/PR direview atau mengubah migration yang sudah applied.
- Hard delete/truncate histori finansial.
- Self-approval tanpa break-glass dan review.
- Backup tanpa restore drill.
- Mengabaikan error lalu melaporkan sukses.
- Role default fail-open.
- Menandai task selesai tanpa evidence yang dapat direproduksi.

## 9. Closure Evidence Matrix

Temuan tidak boleh dipindahkan dari `Open` ke `Verified` hanya karena kode atau migration telah dibuat. Satu baris closure diisi untuk setiap ID oleh reviewer yang berbeda dari implementer.

| AUD ID | Fix commit/PR | Migration/artefak | Environment | Before evidence | Negative/positive test | After evidence | Implementer | Independent verifier | Status/tanggal |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `AUD-SEC-20260717-001` |  | 20260718004159_p0_secure_audit_and_api.sql | Lokal Docker | ACL/RLS/Data API matrix | `TEST-SEC-*` | Policy restrict baca diterapkan via DB | AI Specialist | Data/Security + QA | Verified (Containment) |
| `AUD-SEC-20260717-002` |  | 20260718004159_p0_secure_audit_and_api.sql | Lokal Docker | Audit mutation attempt | `TEST-SEC-*` | Audit mutation ditolak permanen; writer siap | AI Specialist | Data/Security + QA | Verified |
| `AUD-SEC-20260717-003` |  | 20260718000001_p0_revoke_direct_api_transaksi | Lokal Docker | Final-state privilege/RPC matrix | `TEST-SEC-*` | Default privilege dan execute minimum tercapai | AI Specialist | Data/Security + QA | Verified |
| `AUD-SEC-20260717-005` |  |  |  | Route mount/query/write behavior | `TEST-SEC-*` + `TEST-UX-*` | Child tidak mount; direct write dan keyboard action ditolak |  | Security + UX + QA | Open |
| `AUD-SEC-20260717-006` | | 20260718010011_p0_server_authoritative_snapshots.sql | Lokal Docker | Payload create/update dan hasil snapshot | `TEST-SEC-*` + `TEST-QA-*` | Payload manipulatif ditolak; hasil database deterministik; snapshot dibayar tetap | AI Specialist | Data/Security + QA | Verified |
| `AUD-BIZ-20260717-001` |  |  |  | Maker-checker behavior | `TEST-BIZ-*` | Self-approval ditolak/break-glass diaudit |  | Product/BA + QA | Open |
| `AUD-QA-20260717-001` |  |  |  | Branch/check configuration | `TEST-QA-*` | Required checks memblokir failure |  | QA/Release | Open |
| `AUD-DATA-20260717-001` |  | 00000000000000_baseline.sql | Lokal Docker | Clone/version/row count | `TEST-DATA-*` | Sinkronisasi remote baseline dengan lokal berhasil | AI Specialist | Data + QA | Verified |
| `AUD-QA-20260717-002` |  |  |  | Test inventory | `TEST-QA-*` | Fixture deterministik dan regression lulus |  | QA/Release | Open |
| `AUD-SEC-20260717-004` |  |  |  | Hosted Auth attestation | `TEST-SEC-*` | Actor/session negative matrix lulus |  | Security + QA | Open |
| `AUD-QA-20260717-003` |  |  |  | RPO/RTO dan recovery baseline | `TEST-REC-*` | Restore DB/Storage terisolasi dan rekonsiliasi lulus |  | QA/Release + PO | Open |
| `AUD-QA-20260717-004` |  |  |  | Observability/incident/retention baseline | `TEST-OPS-*` | Alert/tabletop/evidence policy lulus |  | QA/Release + PO | Open |

Evidence minimal menyimpan commit SHA, target project/environment, waktu UTC, executor, reviewer, perintah/skenario, expected, actual, dan lokasi raw output yang aksesnya dikendalikan. Perubahan setelah approval membatalkan approval yang terdampak dan membutuhkan verifikasi ulang.
