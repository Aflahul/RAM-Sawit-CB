# Runbook Restore Audit Log

| Metadata | Nilai |
| --- | --- |
| Status | Local scoped drill passed 20 Juli 2026; hosted isolated restore rehearsal tetap wajib sebelum production |
| Pemilik | Data/Security Owner |
| Approver | Product Owner dan QA/Release Owner |
| Terkait | `TASK-SEC-002`, `TASK-QA-003` |
| Bukti lokal | [P0 Local Audit Restore Drill](../evidence/p0-local-audit-restore-2026-07-20.md) |

## Tujuan

Runbook ini adalah jalur terkendali untuk memulihkan `public.audit_log` dari
backup. Jalur ini tidak boleh dipakai untuk mengoreksi, menghapus, atau menulis
ulang histori audit operasional.

## Syarat Masuk

- incident/change record dan alasan restore telah disetujui;
- target environment, backup source, waktu backup, dan checksum tercatat;
- restore rehearsal yang sama telah lulus di staging terisolasi;
- jumlah baris, rentang waktu, dan checksum baseline audit tersedia;
- akses dilakukan melalui koneksi database maintenance, bukan `anon`,
  `authenticated`, atau service key aplikasi;
- dua identitas manusia tersedia sebagai operator dan verifier.

## Prosedur

1. Bekukan mutation aplikasi yang dapat menghasilkan audit baru.
2. Ambil backup baru sebelum restore dan catat checksum serta jumlah baris.
3. Buka transaction maintenance menggunakan role migration yang disetujui.
4. Nonaktifkan hanya trigger `guard_audit_log_insert` dan
   `reject_audit_log_mutation` pada `public.audit_log`.
5. Muat data audit dari backup yang telah diverifikasi. Jangan menjalankan
   transformasi bisnis atau renumbering.
6. Cocokkan jumlah baris, ID unik, actor, action, rentang waktu, dan checksum.
7. Aktifkan kembali kedua trigger sebelum transaction di-commit.
8. Pastikan policy `insert_internal_writer`, ownership writer, RLS, dan grant
   final kembali sesuai migration keamanan.
9. Jalankan negative test insert/update/delete/truncate dan satu controlled RPC
   yang harus menghasilkan tepat satu audit row.
10. Buka kembali aplikasi setelah Data/Security dan QA menyetujui bukti.

## Bukti Wajib

- incident/change ID;
- commit dan migration version yang digunakan;
- environment, UTC start/end, operator, dan verifier;
- checksum sebelum, backup source, hasil restore, dan sesudah;
- jumlah baris sebelum dan sesudah;
- output pemeriksaan trigger, RLS, policy, ownership, serta grants;
- output negative test dan controlled-write test;
- keputusan akhir berhasil, rollback, atau eskalasi.

## Kondisi Rollback

Rollback wajib dilakukan jika checksum tidak cocok, jumlah baris berbeda tanpa
penjelasan yang disetujui, trigger gagal diaktifkan kembali, atau negative test
tidak lulus. Jangan melanjutkan dengan exception manual pada production.

## Batas Drill Lokal

Drill lokal memulihkan schema aplikasi `public`, dependency `auth`/`storage`, dan satu fixture sintetis audit ke database sementara pada container Supabase lokal. Hasil tersebut membuktikan prosedur logical restore, rekonsiliasi checksum, pengaktifan ulang trigger, dan negative mutation test dapat diulang. Hasil ini tidak membuktikan kemampuan backup hosted, PITR, pemulihan Storage object, actual RPO/RTO production, atau recovery dari snapshot production yang representatif.
