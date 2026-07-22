# Incident Record: INC-20260722-001

| Field | Nilai |
| --- | --- |
| Status | Investigating; forward-fix aplikasi lulus staging dan menunggu review/deploy production |
| Severity | S1 |
| Waktu deteksi (WIB/UTC) | 22 Juli 2026 sekitar 10:30 WIB melalui laporan pengguna |
| Environment/commit/deploy | Production `https://ram-sawit-cb.vercel.app`; branch `main` pada `3fba024` |
| Reporter | Owner melalui laporan pengguna; identitas personal tidak dicatat di repository |
| Incident Commander | Belum ditetapkan dengan identitas manusia |
| Alternate IC | Belum ditetapkan dengan identitas manusia |
| Data/nominal/role terdampak | Owner tidak dapat melihat riwayat Pengiriman Mitra untuk mengoreksi satu transaksi yang dilaporkan salah input; nominal/record sensitif tidak disalin |
| Target RPO/RTO | Tidak ada write atau kehilangan data pada diagnosis; target pemulihan workflow pada hari yang sama sesuai S1 |
| Secure channel/contact tree | Belum ditetapkan |

## Ringkasan Faktual

Halaman production `/admin/input-timbangan` berhenti pada teks **Memuat riwayat...**. Transaksi yang sudah disimpan tidak terhapus, tetapi owner tidak dapat melihat baris dan membuka aksi koreksi/batal. Probe Data API read-only dengan `limit=0` menunjukkan view `v_transaksi_mitra_operasional` dan `v_master_mitra_operasional` yang dipanggil frontend belum tersedia di production (`PGRST205`).

Reproduksi aman pada staging memakai user dan transaksi sintetis menunjukkan dua query HTTP 400, kemudian client melempar `Cannot read properties of undefined (reading 'data')`. Git history mengaitkan regresi ke refactor `2eecee1`: sumber query dipindah dari tabel production ke view security, elemen query fee history dihapus tetapi hasil keempat masih didestruktur, dan beberapa field perhitungan edit dihapus sementara referensinya tertinggal.

## Timeline

| Waktu WIB/UTC | Actor | Kejadian/keputusan | Bukti |
| --- | --- | --- | --- |
| 22 Jul sekitar 10:30 WIB | Owner/reporting user | Melaporkan riwayat Pengiriman Mitra production menggantung dan ada salah input yang perlu dikoreksi | Screenshot pengguna; tidak disimpan ulang untuk menghindari data/identitas tambahan |
| 22 Jul 2026 | AI implementer | Membuat branch `hotfix/production-mitra-history` langsung dari `origin/main`; PR P0 tidak dibawa ke hotfix | Git branch/log |
| 22 Jul 2026 | AI implementer | Reproduksi staging merah: row tidak tampil, loading tetap aktif, dua HTTP 400, satu page error | `node scripts/repro-mitra-history-staging.mjs` |
| 22 Jul 2026 | AI implementer | Probe production read-only `limit=0` memastikan kedua view tidak tersedia | Response `PGRST205`; tidak mengambil row production |
| 22 Jul 2026 | AI implementer | Forward-fix mengembalikan kontrak tabel production dan menambahkan cleanup loading melalui `finally` | Diff hotfix |
| 22 Jul 2026 | AI implementer | Reproduksi staging hijau: row terlihat, modal Edit terbuka, loading hilang, runtime error 0, residue 0 | `npm run test:mitra-history:staging` |
| 22 Jul 2026 | AI implementer | Gate lokal menemukan clean reset baseline `main` berhenti pada migration `20260718010012` karena kolom `pengaturan_bisnis.keterangan` tidak ada; hotfix dipastikan tidak memiliki diff `supabase/` | Supabase Docker lokal; `git diff origin/main...HEAD -- supabase/` |

## Containment

- Write/deploy yang dihentikan: tidak ada migration, DDL, DML, koreksi record, atau perubahan Auth production selama diagnosis.
- Fitur/role yang dibatasi: tidak ada perubahan akses; owner tetap diminta tidak membuat koreksi manual di database.
- Session/key yang dicabut/dirotasi: tidak ada indikasi kebocoran dan tidak ada rotasi.
- Bukti yang dipertahankan: error code, URL endpoint tanpa key, commit sumber regresi, serta output red/green sintetis.
- Risiko yang masih berjalan: owner belum dapat mengoreksi transaksi salah sampai hotfix production selesai dan diverifikasi.

## Assessment

- Rentang waktu dan record terdampak: seluruh riwayat pada halaman Pengiriman Mitra selama deployment frontend bermasalah; jumlah record aktual belum dihitung karena diagnosis tidak membaca data production.
- Nominal/ledger/snapshot/rekening: tidak diubah; satu transaksi salah input dilaporkan tetapi detail/nominal belum direkonsiliasi.
- Akses tidak sah atau role bypass: tidak ditemukan.
- Dampak turunan: koreksi/batal transaksi dari halaman terhenti; laporan dan kwitansi dapat tetap membawa data salah sampai owner melakukan koreksi melalui UI yang pulih.

## Recovery Decision

| Opsi | Risiko data | Downtime | Dipilih/alasan | Approver |
| --- | --- | --- | --- | --- |
| Rollback aplikasi penuh | Dapat menghapus perubahan main lain yang sah | Redeploy | Tidak dipilih |
| Forward-fix aplikasi terisolasi | Rendah; query/read dan error-state saja, tanpa schema/data write | Satu redeploy | **Dipilih** untuk memulihkan kontrak production yang terakhir bekerja | Menunggu reviewer/release operator manusia |
| Reversal bisnis | Dapat mengubah ledger tanpa bukti cukup | Tidak relevan | Tidak dipilih; koreksi tetap melalui flow aplikasi | Product Owner setelah UI pulih |
| Restore database | Risiko tinggi dan tidak diperlukan | Tinggi | Tidak dipilih | Tidak relevan |

## Verification dan Rekonsiliasi

| Test/query | Expected | Actual | Evidence | Reviewer |
| --- | --- | --- | --- | --- |
| Repro staging sebelum fix | Menangkap loading menggantung | Red: loading true, row false, HTTP 400, page error | Harness staging sintetis | AI self-check; review manusia pending |
| Repro staging setelah fix | Riwayat dan koreksi siap | Green: row true, modal Edit true, loading false, runtime error 0, residue 0 | `npm run test:mitra-history:staging` | AI self-check; review manusia pending |
| Probe production `limit=0` | Tidak mengambil row | Kedua view mengembalikan `PGRST205` | Read-only Data API probe | AI self-check |
| Clean reset database lokal | Migration production dapat direplay | Blocked oleh kegagalan baseline `main` pada `20260718010012`; bukan perubahan hotfix | Supabase Docker lokal | Remediasi penuh terisolasi di PR #5; review manusia pending |

### Pengecualian Gate Emergency yang Menunggu Approval

- Diff hotfix terhadap `origin/main` pada direktori `supabase/` wajib kosong; perubahan schema, migration, RLS, RPC, atau data membuat gate gagal.
- Job database hotfix hanya menoleransi pasangan error baseline yang exact: migration `20260718010012_p0_maker_checker_pinjaman_panjar.sql` dan kolom `pengaturan_bisnis.keterangan` yang tidak ada. Error lain tetap gagal.
- Status job tersebut bukan klaim bahwa migration history production sudah clean. Remediasi clean reset dan regression suite penuh tetap berada pada PR #5 menuju `dev`, lalu hanya boleh dipromosikan ke `main` melalui release terpisah.
- Audit dependency hotfix menunjukkan nol critical dan empat high pada dependency production yang sudah ada. Hotfix memblokir critical; remediasi dependency high tetap terisolasi pada PR #5 agar emergency UI tidak bercampur dengan upgrade dependency.
- Pengecualian ini belum sah sampai reviewer/release operator manusia menyetujui PR #6; branch protection tetap mewajibkan satu approval independen.

- [ ] Saldo, ledger, snapshot, kwitansi, pembayaran, dan row transaksi salah direkonsiliasi setelah owner mengidentifikasi record melalui UI.
- [ ] Role owner dan route production diuji kembali setelah deploy.
- [ ] Pengguna operasional mengonfirmasi riwayat tampil dan koreksi yang dimaksud dapat dilakukan.
- [ ] Observation window selesai tanpa trigger baru.

## Komunikasi

| Waktu | Audience | Pesan ringkas | Pengirim |
| --- | --- | --- | --- |
| 22 Jul 2026 | Pengguna/owner | Insiden diprioritaskan; tidak ada koreksi data langsung; hotfix terisolasi dari PR P0 | AI implementer melalui sesi pengguna |

## Closure dan Postmortem

- Waktu resolved/closed: belum ditetapkan.
- Dampak aktual: workflow melihat dan mengoreksi riwayat Pengiriman Mitra production terhenti.
- Root dan contributing factors: kontrak frontend/view dipromosikan tanpa migration production terkait; refactor parsial tidak diuji terhadap kondisi query gagal maupun flow edit owner.
- Kontrol yang bekerja/gagal: laporan owner dan reproduksi staging bekerja; deployment coupling frontend-database serta regression coverage halaman gagal.
- Tindak lanjut: pertahankan regression test riwayat/edit, tambah compatibility gate frontend-database, dan lakukan review retrospektif maksimal satu hari kerja setelah stabil.
- Update test/SOP/PRD/BDR/ADR: incident record dan test staging ditambahkan; perubahan aturan bisnis tidak diperlukan.
- Persetujuan closure PO + Engineering Lead + QA: pending.
