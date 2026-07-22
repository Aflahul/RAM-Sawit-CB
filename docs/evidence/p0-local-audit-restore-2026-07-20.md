# Evidence P0: Local Audit Restore Drill 20 Juli 2026

| Field | Nilai |
| --- | --- |
| Status | **PASS untuk scoped local logical restore; hosted recovery tetap Blocked** |
| Source | Supabase PostgreSQL 17 lokal pada Docker; database utama hanya dibaca melalui `pg_dump` |
| Target | Dua database sementara bernama ketat `restore_drill_source_<epoch>` dan `restore_drill_target_<epoch>` |
| Data | Satu fixture audit sintetis; tidak memakai data production atau staging |
| Script | [`scripts/test-p0-local-audit-restore.ps1`](../../scripts/test-p0-local-audit-restore.ps1) |
| Waktu | 20 Juli 2026, mulai `2026-07-20T01:22:11.8710492Z` |
| Durasi | 7,45 detik |

## Metode

1. Verifikasi container target adalah database Supabase lokal dan tidak ada database sementara dengan nama yang akan dipakai.
2. Buat logical dump schema aplikasi `public` beserta dependency `auth`, `storage`, dan `graphql_public`.
3. Buat dua database sementara dan pasang dependency extension `btree_gist` serta `pgcrypto`.
4. Restore baseline schema/data ke source dan target dengan `pg_restore --exit-on-error`.
5. Tambahkan satu fixture sintetis ke `source.public.audit_log`, kemudian dump hanya data audit.
6. Restore data audit ke target, aktifkan kembali trigger, bandingkan count/checksum, dan jalankan negative mutation test.
7. Hapus kedua database sementara dan dump di blok cleanup, termasuk ketika langkah gagal.

## Hasil

```json
{"status":"PASS","scope":"local logical restore of public/auth/storage plus audit-log reconciliation","source_signature":"1|5a003dab2eeaadaad535b9aa3093f31e","target_signature":"1|5a003dab2eeaadaad535b9aa3093f31e","trigger_state":"guard_audit_log_insert:O,reject_audit_log_mutation:O","mutation_denied":true,"duration_seconds":7.45}
```

Pemeriksaan cleanup setelah drill menemukan nol database `restore_drill_%` dan nol file `/tmp/restore_drill_*.dump` pada container lokal.

## Batas Bukti

Drill ini tidak menutup `AUD-QA-20260717-003` karena staging dan production melaporkan `backups: null` serta `pitr_enabled: false`. Drill juga tidak mencakup object Storage, snapshot/clone production tersamarkan, actual RPO/RTO, operator dan verifier manusia terpisah, atau pemulihan hosted lintas project. Karena itu G2/G4 dan keputusan production tetap **NO-GO**.
