# Runbook Restore Audit Log

| Metadata | Nilai |
| --- | --- |
| Status | Draft; wajib direhearsal di staging sebelum digunakan di production |
| Pemilik | Data/Security Owner |
| Approver | Product Owner dan QA/Release Owner |
| Terkait | `TASK-SEC-002`, `TASK-QA-003` |

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
