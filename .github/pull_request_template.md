## Ringkasan

Jelaskan masalah, hasil yang dicapai, dan alasan perubahan.

- Target branch: `dev` untuk pekerjaan normal; `main` hanya untuk PR release dari `dev` atau `hotfix/*` production.
- [ ] Branch asal dan target mengikuti aturan pada SOP Pengembangan.

## Traceability

- Requirement/flow: `BR-*`, `FLOW-*`, `AC-*`
- Audit/decision: `AUD-*`, `BDR-*`, `ADR-*`
- Task/test: `TASK-*`, `TEST-*`

## Jenis Perubahan

- [ ] Fitur/alur bisnis
- [ ] Perbaikan bug
- [ ] UX/UI/accessibility
- [ ] Database/migration/backfill
- [ ] Auth/role/RLS/security
- [ ] Dokumentasi/tooling

## Dampak

- Role dan workflow:
- Formula/status/ledger/snapshot:
- Data historis dan kompatibilitas:
- Route/API/RPC:

## Verifikasi

- [ ] Lint
- [ ] Build
- [ ] Test otomatis relevan
- [ ] Test manual per role
- [ ] Responsive/print/accessibility relevan
- [ ] Rekonsiliasi data relevan

Cantumkan perintah, hasil penting, dan tautan bukti:

```text

```

## Database dan Rollback

- Migration/backfill:
- Dampak RLS/permission:
- Backup/rehearsal:
- Trigger dan langkah rollback/forward-fix:

## Dokumentasi

- [ ] Sumber kebenaran yang terdampak telah diperbarui.
- [ ] Dokumen historis tidak dipakai sebagai aturan aktif baru.
- [ ] Tidak ada secret atau data produksi di diff.

## Reviewer Wajib

- [ ] Business/Product bila aturan bisnis berubah
- [ ] UX/UI bila workflow/tampilan berubah
- [ ] Data/Security bila uang, schema, role, atau RLS berubah
- [ ] QA/Release untuk keputusan go/no-go
