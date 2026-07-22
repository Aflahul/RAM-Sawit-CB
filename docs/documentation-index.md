# Indeks dan Tata Kelola Dokumentasi

| Metadata | Nilai |
| --- | --- |
| Status | Draft manifest untuk persetujuan Product Owner dan Engineering Lead |
| Berlaku sejak | 17 Juli 2026 |
| Pemilik | Product Owner dan Engineering Lead |
| Tujuan | Menentukan sumber kebenaran, status, pemilik, dan pemicu pembaruan setiap dokumen |

## 1. Aturan Umum

1. Tidak ada satu file yang menjadi sumber kebenaran untuk semua jenis informasi.
2. Setiap jenis keputusan hanya memiliki satu sumber aktif; dokumen lain menautkan, bukan menyalin isi lengkap.
3. Kode, migration yang sudah diterapkan, dan lockfile menjadi bukti executable untuk kondisi teknis aktual.
4. Aturan bisnis aktif tetap harus tertulis di PRD atau Business Decision Record. Keberadaan kode saja tidak cukup menjadi persetujuan bisnis.
5. Dokumen berstatus historis tidak boleh menerima requirement atau temuan baru.
6. Perubahan harus memperbarui sumber yang terdampak dan traceability-nya, bukan seluruh dokumen secara mekanis.

## 2. Manifest Dokumen Utama

| Dokumen | Fungsi | Status | Owner | Approver | Diperbarui ketika |
| --- | --- | --- | --- | --- | --- |
| [`README.md`](../README.md) | Onboarding, setup lokal, perintah utama | Aktif | Engineering | Engineering Lead | Setup, command, atau entry point berubah |
| [`PRD-final.md`](work-packages/PRD-final.md) | Tujuan dan aturan bisnis yang disetujui | Aktif-transisi | Product/BA | Product Owner | Scope, formula, role, atau acceptance bisnis berubah |
| [`implementation_plan.md`](work-packages/implementation_plan.md) | Urutan delivery, dependency, dan release scope | Aktif | Engineering Lead | Product Owner | Prioritas atau jalur implementasi berubah |
| [`IMPLEMENTATION-TASKS.md`](work-packages/IMPLEMENTATION-TASKS.md) | Checklist eksekusi sementara | Aktif-transisi | Engineering Lead | Engineering Lead | Task dimulai, diblokir, diverifikasi, atau ditutup |
| [`technical-specification.md`](technical-specification.md) | Arsitektur as-built dan kontrak teknis | In Review | Tech Lead | Engineering Lead | Stack, arsitektur, data, security, atau deployment berubah |
| [`development-sop.md`](development-sop.md) | Tahapan kerja dan quality/release gate | In Review | Engineering Lead | Product Owner + QA/Release | Proses delivery atau kontrol wajib berubah |
| [`audit-governance.md`](audit-governance.md) | Taxonomy, format, severity, dan traceability audit | In Review | Product/BA | Engineering Lead | Model audit atau ownership berubah |
| [`ux-ui-audit.md`](ux-ui-audit.md) | Register dan hasil audit UX/UI seluruh halaman | In Review | UX/UI | Product Owner | Halaman, task flow, komponen, content, atau temuan berubah |
| [`page-flow-control-audit-2026-07-16.md`](page-flow-control-audit-2026-07-16.md) | Baseline audit flow bisnis dan kontrol | Baseline aktif | Product/BA | Product Owner | Ditinjau sampai baseline pengganti diterbitkan |
| [`security-release-audit-2026-07-17.md`](security-release-audit-2026-07-17.md) | Baseline security dan keputusan GO/NO-GO | Baseline aktif | Data/Security dan QA | Engineering Lead | Security, Auth, database, supply chain, atau release gate berubah |
| [`work-packages/p0-security-release-remediation.md`](work-packages/p0-security-release-remediation.md) | Task, AC, TEST, dependency, dan DoD program remediasi P0 | Draft/Blocked/No-Go production | Engineering Lead belum ditetapkan | Product Owner + Data/Security + QA | Owner/evidence/status task berubah |
| [`releases/R-SEC-01-2026-07-20.md`](releases/R-SEC-01-2026-07-20.md) | Status gate terpadu untuk kandidat containment P0 | Preparing/No-Go | Release Owner belum ditetapkan | Engineering + QA + Data/Security + Product Owner | Gate, commit, evidence, approval, atau keputusan berubah |
| [`releases/R-SEC-01-zero-cost-production-plan.md`](releases/R-SEC-01-zero-cost-production-plan.md) | Urutan backup, rehearsal, MFA, migration, deploy, dan recovery tanpa biaya Supabase tambahan | Preparing/No-Go | Engineering + Release | Product Owner + Data/Security + QA | Constraint biaya, recovery target, atau urutan production berubah |
| [`runbooks/audit-log-restore.md`](runbooks/audit-log-restore.md) | Prosedur pemulihan audit log yang append-only | Draft; rehearsal wajib | Data/Security Owner | Product Owner + QA/Release | Kontrol audit, backup, atau restore berubah |
| [`evidence-retention-policy.md`](evidence-retention-policy.md) | Jadwal, akses, legal hold, dan disposal bukti | Draft | Product Owner + Data/Security | Accounting/Legal + QA | Kebutuhan legal, system of record, atau kategori evidence berubah |
| [`ai-specialist-collaboration.md`](ai-specialist-collaboration.md) | Protokol panel spesialis dan koreksi silang | In Review | Engineering Lead | Product Owner | Model kolaborasi atau gate review berubah |
| [`reviews/governance-cross-review-2026-07-17.md`](reviews/governance-cross-review-2026-07-17.md) | Bukti panel spesialis dan koreksi yang diterapkan | Review record | Engineering Lead | Tidak berlaku; record immutable setelah final | Review governance baru selesai |

`Aktif-transisi` berarti dokumen masih dipakai, tetapi strukturnya perlu dinormalisasi tanpa menghentikan pengembangan.

Lifecycle dokumen governance: `Draft -> In Review -> Approved/Active -> Superseded`. Perubahan status ke `Approved/Active` wajib mencatat `approved_by`, tanggal, dan commit/PR. File yang belum dilacak Git atau belum mendapat approval tidak boleh mengklaim status aktif final.

## 3. Dokumen Referensi dan Historis

| Dokumen | Status | Penggunaan yang diperbolehkan |
| --- | --- | --- |
| [`business-flow-ux-plan.md`](business-flow-ux-plan.md) | Historis/strategi | Menelusuri use case, keputusan, dan roadmap awal |
| [`PRD-v1.md`](work-packages/PRD-v1.md) | Historis | Iterasi pertama dari dokumen PRD sebelum difinalisasi |
| [`page-content-audit.md`](page-content-audit.md) | Historis | Menelusuri keputusan navigasi dan overlap halaman per 14 Juli 2026 |
| [`archive/audit-ux-input-timbangan-legacy.md`](archive/audit-ux-input-timbangan-legacy.md) | Historis | Menelusuri pain point input batch yang telah dikonsolidasikan ke audit UX/UI |
| [`db-actual-audit-2026-07-14.md`](db-actual-audit-2026-07-14.md) | Snapshot audit | Bukti kondisi database pada tanggal audit |
| [`db-cleanup-migration-plan.md`](db-cleanup-migration-plan.md) | Rencana referensi | Dasar cleanup setelah divalidasi ulang terhadap schema aktual |
| `.stitch/DESIGN.md` | Referensi lokal, tidak dilacak Git | Panduan visual lokal; keputusan aktif harus tercermin di UX/UI audit atau komponen aplikasi |

Dokumen historis tidak boleh digunakan sendirian untuk menyimpulkan kondisi produksi saat ini.

## 4. Hierarki Saat Terjadi Konflik

| Konflik | Yang berlaku |
| --- | --- |
| Dua aturan bisnis tertulis berbeda | Keputusan owner terbaru yang telah dicatat di PRD/BDR |
| Dokumen teknis berbeda dengan schema produksi | Migration/schema produksi yang terverifikasi; lalu perbaiki spesifikasi |
| Task menyatakan selesai tetapi test/gate gagal | Belum selesai |
| Audit lama berbeda dengan audit baru | Baseline terbaru yang menyatakan dokumen lama digantikan |
| UI berbeda dengan aturan bisnis | Aturan bisnis berlaku; UI menjadi defect |
| Preferensi desain bertentangan dengan aksesibilitas/security | Aksesibilitas dan security berlaku |

## 5. Utang Dokumentasi yang Harus Dinormalisasi

| ID | Masalah | Prioritas | Tindak lanjut |
| --- | --- | --- | --- |
| `DOC-001` | PRD mencampur aturan aktif, addendum, baseline historis, dan status implementasi | P1 | Bentuk PRD aktif yang ringkas; pindahkan kronologi ke arsip dan BDR |
| `DOC-002` | Task list memuat checklist lama dan baru untuk kontrol yang sama | P1 | Pindahkan item selesai/lama ke arsip per rilis; pertahankan backlog aktif |
| `DOC-003` | Status release gate pada audit dan task dapat berbeda | P0 | Mitigated: release checklist aktif `R-SEC-01` dibuat; jaga sinkron setiap gate/evidence berubah |
| `DOC-004` | Requirement, temuan, task, test, dan commit belum memakai ID konsisten | P1 | Terapkan pola ID dari Tata Kelola Audit mulai work package berikutnya |
| `DOC-005` | Keputusan bisnis/arsitektur belum memiliki BDR/ADR terpisah | P2 | Mulai BDR/ADR untuk keputusan material berikutnya; migrasikan keputusan lama saat disentuh |

Normalisasi dilakukan bertahap. Jangan menulis ulang seluruh histori dalam satu perubahan karena berisiko menghilangkan konteks keputusan.

## 6. Record Keputusan

Gunakan record terpisah untuk keputusan material:

- `docs/decisions/business/BDR-YYYYMMDD-NNN-judul.md` untuk aturan atau trade-off bisnis.
- `docs/decisions/architecture/ADR-YYYYMMDD-NNN-judul.md` untuk arsitektur, data, security, dan integrasi.

Setiap record minimal berisi status, konteks, pilihan yang dipertimbangkan, keputusan, alasan, dampak, pemilik, tanggal, serta dokumen/task terkait. Record tidak diedit untuk mengubah sejarah; keputusan pengganti membuat record baru dan menandai record lama sebagai `Superseded`.

## 7. Review Berkala

- Setiap task: perbarui status dan tautan bukti.
- Setiap perubahan kontrak: perbarui sumber kebenaran pada commit/PR yang sama.
- Setiap minggu pengembangan aktif: triage temuan audit dan utang dokumentasi.
- Setiap release: periksa manifest, release gate, dan dokumen yang berubah.
- Setiap tiga bulan atau perubahan besar: baseline ulang PRD, flow, UX/UI, teknis, data, dan security.
