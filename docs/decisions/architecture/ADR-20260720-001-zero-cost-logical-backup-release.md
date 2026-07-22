# ADR-20260720-001: Logical Backup dan Docker Rehearsal untuk Release Free Plan

| Field | Nilai |
| --- | --- |
| Status | **Proposed** |
| Tanggal | 2026-07-20 |
| Decision owner | Engineering Lead, belum ditetapkan dengan identitas manusia |
| Reviewer | Data/Security dan QA/Release, belum ditetapkan |
| Menggantikan | - |
| Terkait | `R-SEC-01`, `AUD-DATA-20260717-001`, `AUD-QA-20260717-003`, `TASK-DATA-001`, `TASK-QA-003` |

## Konteks dan Masalah

Production berjalan pada Supabase Free plan dan tidak memiliki automatic backup atau PITR. Constraint bisnis adalah release harus tetap dapat dilakukan tanpa biaya Supabase tambahan. Production berukuran sekitar 17,6 MB dengan 41 tabel, estimasi 587 row, empat akun Auth, dan empat object Storage. Schema `public` setara secara semantik dengan migration baseline, tetapi ledger migration masih 0/15.

Release langsung tanpa backup/rehearsal berisiko merusak data atau membuat aplikasi tidak kompatibel. Upgrade plan/PITR menyelesaikan sebagian risiko tetapi melanggar constraint biaya. Tidak melakukan release juga mempertahankan temuan security aktif.

## Decision Drivers

- Tidak menambah biaya Supabase.
- Menutup temuan security melalui 14 forward migrations yang sudah lulus staging.
- Menjaga data finansial, audit trail, Auth, dan object Storage.
- Memiliki abort point sebelum setiap mutation production.
- Bukti restore dan migration dapat direproduksi tanpa project hosted ketiga.
- Risiko residual harus terlihat dan diterima, bukan disamarkan sebagai kemampuan PITR.

## Opsi

| Opsi | Kelebihan | Kekurangan | Risiko |
| --- | --- | --- | --- |
| A. Upgrade Pro + PITR | Managed backup dan recovery point lebih baik | Menambah biaya tetap dan add-on PITR | Cost constraint gagal |
| B. Logical backup terenkripsi + Docker rehearsal + maintenance | Tidak menambah biaya Supabase; dapat diuji lokal; sesuai ukuran DB saat ini | Manual, membutuhkan downtime dan disiplin operator | Tidak ada point-in-time restore; RPO harian; recovery lebih lambat |
| C. Deploy tanpa backup | Paling cepat | Tidak ada recovery proof | Tidak dapat diterima untuk data finansial/P0 |
| D. Self-host production | Tidak membayar Supabase plan | Menambah beban server, patching, backup, keamanan, dan availability | Risiko operasi lebih besar serta bukan perubahan kecil |

## Keputusan yang Diusulkan

Pilih Opsi B untuk `R-SEC-01`, dengan boundary berikut:

- logical dump schema/data/role, copy object Storage, hash manifest, enkripsi, dan salinan off-site wajib sebelum production mutation;
- clone production dibuat hanya di Docker lokal pada mesin terkendali;
- baseline ledger hanya diperbaiki setelah semantic diff kosong dan rehearsal lulus;
- production memakai scheduled maintenance/write freeze;
- database dipromosikan lebih dahulu, frontend SHA yang sama sesudah verifikasi;
- TOTP/AAL2 wajib untuk privileged role sebagai kontrol gratis;
- keputusan ini hanya mencakup recovery dari release migration pada project yang sama, bukan full hosted disaster recovery atau pengganti PITR permanen.

Status tetap `Proposed` sampai target RPO 24 jam, RTO 4 jam, media backup, dan residual risk diterima oleh identitas manusia yang diwajibkan.

## Konsekuensi

### Positif

- Tidak ada biaya Supabase tambahan.
- Security release tetap dapat dilanjutkan dengan abort point dan bukti restore.
- Production data dapat direhearsal pada Docker tanpa project ketiga.
- Backup manual juga menjadi fondasi operasi harian Free plan.

### Negatif/Trade-off

- Tidak ada automatic backup/PITR dan tidak ada hosted hot standby.
- Restore memerlukan operator, media terenkripsi, downtime, dan koneksi database yang tersedia.
- Standard CLI dump mengecualikan schema internal Auth/Storage; object Storage harus diunduh terpisah dan full project-loss recovery tidak dijamin.
- Password hash Auth bukan bagian dari scope migration rollback; kehilangan project penuh tetap memiliki risiko yang tidak ditutup oleh ADR ini.
- Rehearsal menggunakan data production pada mesin lokal terkendali sehingga custody, cleanup, dan no-log policy wajib ditegakkan.

## Migration dan Rollback

- Langkah rollout: ikuti [Rencana Production Tanpa Biaya](../../releases/R-SEC-01-zero-cost-production-plan.md).
- Kompatibilitas data lama: baseline semantic diff kosong; 14 migration maju wajib diuji pada clone production.
- Backfill/reconciliation: row count dan checksum tabel finansial/audit sebelum/sesudah.
- Trigger rollback: backup/hash gagal, baseline diff berubah, dry-run bukan 14 migration, migration error, atau rekonsiliasi berbeda.
- Langkah pemulihan: maintenance tetap aktif, backup keadaan gagal, lalu forward-fix yang direhearsal atau logical restore ke project yang sama.

## Verification

| ID test | Bukti yang wajib tersedia |
| --- | --- |
| `TEST-DATA-CLONE-001` | Restore production dump ke Docker dan ledger baseline setara |
| `TEST-DATA-MIG-001` | Empat belas migration maju lulus dengan durasi/lock evidence |
| `TEST-REC-001` | Restore kedua, checksum/row count sama, raw dump dibersihkan |
| `TEST-STORAGE-001` | Empat object diunduh dan SHA-256 cocok |
| `TEST-AUTH-MFA-001` | Privileged AAL1 ditolak dan TOTP AAL2 diterima |
| `TEST-RELEASE-001` | Maintenance, DB-first, frontend-second, smoke, dan observation window lulus |

## Persetujuan

| Peran | Nama | Tanggal | Keputusan |
| --- | --- | --- | --- |
| Engineering Lead |  |  | Pending |
| Data/Security Reviewer |  |  | Pending |
| QA/Release |  |  | Pending |
| Product Owner |  |  | Pending risk acceptance |
