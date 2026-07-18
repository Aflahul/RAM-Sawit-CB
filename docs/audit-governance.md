# Tata Kelola Audit Produk Sawit CB

| Metadata | Nilai |
| --- | --- |
| Status | Draft untuk persetujuan Product Owner dan Engineering Lead |
| Berlaku sejak | 17 Juli 2026 |
| Pemilik dokumen | Product Owner dan Engineering Lead |
| Siklus tinjau | Setiap perubahan alur kritis dan minimal sekali per rilis |

## 1. Tujuan

Dokumen ini menjadi indeks dan aturan bersama untuk seluruh audit produk. Tujuannya adalah mencegah temuan berulang di banyak dokumen, memastikan setiap risiko memiliki pemilik, dan menyediakan jejak dari kebutuhan bisnis sampai bukti rilis.

## 2. Keputusan Struktur Audit

Audit tidak digabung menjadi satu dokumen besar karena fokus, pemilik, dan cara verifikasinya berbeda. Dokumen detail tetap dipisahkan, tetapi memakai format temuan dan rantai ketertelusuran yang sama.

| Audit | Pertanyaan utama | Ruang lingkup | Sumber temuan aktif |
| --- | --- | --- | --- |
| Flow Bisnis dan Kontrol | Apakah proses, angka, status, kewenangan, dan pencatatan sudah benar? | Use case, role, state transition, formula, ledger, snapshot, approval, reversal, audit trail | [Audit Flow Bisnis](page-flow-control-audit-2026-07-16.md) |
| UX/UI | Apakah pengguna yang tepat dapat menyelesaikan tugas dengan jelas, cepat, konsisten, dan minim salah? | Navigasi, urutan kerja, informasi, kontrol UI, istilah, feedback, aksesibilitas, responsive, print | [Audit UX/UI Seluruh Halaman](ux-ui-audit.md) |
| Technical/Data/Security Assurance | Apakah implementasi aman, andal, dan sesuai kontrak data? | Schema, migration, RLS/ACL/RPC, Auth, query, dependency, performa, recovery | [Audit Security dan Kesiapan Rilis](security-release-audit-2026-07-17.md) sebagai register assurance aktif; audit database bertanggal sebagai bukti snapshot |
| QA/Release Assurance | Apakah perubahan telah dibuktikan layak dirilis dan dapat dipulihkan? | Acceptance, regression, role test, rehearsal, backup/restore, rollback, incident, evidence | Finding `AUD-QA-*` dan `AUD-DATA-*` pada register assurance aktif |

[SOP Pengembangan](development-sop.md) adalah satu-satunya definisi normatif lifecycle dan gate `G0-G6`. Audit Security/Release tidak mendefinisikan gate kedua; audit tersebut hanya mengagregasi finding dan status lulus/gagal gate pada baseline tertentu.

### Posisi audit UI

Audit UI diperlukan untuk memeriksa konsistensi komponen, hierarki visual, label, status, warna, tabel, dialog, ukuran layar, dan aksesibilitas lintas halaman. Audit UI menjadi bagian dari audit UX/UI, bukan dokumen audit ketiga yang berdiri sendiri.

Konsistensi makna tetap diperiksa bersama:

- Audit Flow Bisnis menentukan arti angka, status, dan aksi yang benar.
- Audit UX/UI menentukan cara arti tersebut ditampilkan dan dipahami secara konsisten.
- Jika keduanya terdampak, satu temuan utama dibuat lalu ditautkan ke temuan pendamping, bukan disalin penuh.

## 3. Sumber Kebenaran Dokumentasi

| Informasi | Sumber kebenaran |
| --- | --- |
| Tujuan produk dan aturan bisnis yang disetujui | `PRD-final.md` |
| Alur implementasi dan keputusan urutan | `implementation_plan.md` |
| Checklist pekerjaan dan status eksekusi | `IMPLEMENTATION-TASKS.md` |
| Kontrak arsitektur, stack, data, keamanan | `docs/technical-specification.md` |
| Temuan proses dan kontrol bisnis | `docs/page-flow-control-audit-2026-07-16.md` |
| Temuan UX dan UI lintas halaman | `docs/ux-ui-audit.md` |
| Temuan Security, Data, QA, dan status gate | `docs/security-release-audit-2026-07-17.md` sampai register/baseline pengganti diterbitkan |
| Cara kerja pengembangan dan release gate | `docs/development-sop.md` |

Dokumen historis boleh dipertahankan sebagai bukti keputusan, tetapi harus diberi status `historis`, tanggal, dan tautan ke sumber aktif. Dokumen historis tidak boleh menjadi tempat menambah temuan baru.

## 4. Format Temuan Wajib

Setiap temuan aktif minimal memiliki:

| Field | Isi |
| --- | --- |
| ID | ID unik sesuai domain |
| Tanggal dan auditor | Kapan dan oleh peran siapa temuan dibuat |
| Halaman/alur | Route, use case, atau komponen terdampak |
| Role terdampak | Admin, Owner, Super Admin, atau publik |
| Kondisi dan bukti | Perilaku aktual, screenshot/query/test bila ada |
| Dampak | Risiko uang, data, operasional, keamanan, atau pengalaman pengguna |
| Severity | `S0`, `S1`, `S2`, atau `S3` |
| Rekomendasi | Hasil yang harus dicapai, bukan sekadar preferensi visual |
| Pemilik dan target | Penanggung jawab serta target iterasi |
| Status | `Open`, `Planned`, `In Progress`, `Blocked`, `Verified`, `Accepted Risk`, `Duplicate`, atau `Superseded` |
| Tautan | Requirement, task, commit/PR, migration, dan bukti uji |

### Pola ID

- `BR-<DOMAIN>-NNN`: business requirement.
- `FLOW-<DOMAIN>-NNN`: alur atau state transition yang disetujui.
- `AC-<DOMAIN>-NNN`: acceptance criteria.
- `AUD-BIZ-YYYYMMDD-NNN`: temuan flow bisnis dan kontrol.
- `AUD-UX-YYYYMMDD-NNN`: temuan UX, UI, content, aksesibilitas, atau responsive.
- `AUD-DATA-YYYYMMDD-NNN`: temuan schema, kualitas, dan migrasi data.
- `AUD-SEC-YYYYMMDD-NNN`: temuan authentication, authorization, RLS, dan privasi.
- `AUD-QA-YYYYMMDD-NNN`: test gap dan release risk.
- `BDR-YYYYMMDD-NNN` / `ADR-YYYYMMDD-NNN`: keputusan bisnis / arsitektur.
- `TASK-<DOMAIN>-NNN` dan `TEST-<DOMAIN>-NNN`: pekerjaan dan bukti uji.

Prioritas, severity, dan status tidak dimasukkan ke ID karena dapat berubah tanpa mengubah identitas item.

## 5. Severity dan Prioritas

Severity menjelaskan dampak masalah. Prioritas menjelaskan urutan pengerjaan. Keduanya tidak boleh dipertukarkan.

| Severity | Definisi |
| --- | --- |
| `S0 Kritis` | Kehilangan/korupsi data atau uang, kebocoran akses, sistem utama tidak dapat dipakai |
| `S1 Tinggi` | Perhitungan/status salah, workflow utama terhenti, atau risiko salah bayar yang nyata |
| `S2 Sedang` | Tugas tetap selesai tetapi membingungkan, lambat, tidak konsisten, atau rawan salah |
| `S3 Rendah` | Perapian, polish, atau masalah lokal tanpa dampak material |

| Prioritas | Aturan |
| --- | --- |
| `P0` | Harus selesai sebelum penggunaan/rilis terkait dilanjutkan |
| `P1` | Masuk iterasi aktif berikutnya |
| `P2` | Direncanakan setelah workflow inti stabil |
| `P3` | Backlog/eksperimen; hanya dikerjakan saat manfaat tervalidasi |

## 6. Rantai Ketertelusuran

Perubahan dianggap terkendali jika memiliki rantai berikut:

```text
PRD requirement / keputusan owner
  -> temuan audit (bila berawal dari gap)
  -> implementation plan
  -> implementation task + acceptance criteria
  -> kode / migration / konfigurasi
  -> bukti review dan pengujian
  -> commit atau PR
  -> release record
```

Rantai target menggunakan ID: `BR -> FLOW -> AC -> AUD (bila ada gap) -> BDR/ADR (bila ada keputusan) -> TASK -> TEST -> commit/PR/migration -> release`.

Aturan:

1. Satu task boleh menyelesaikan beberapa temuan jika acceptance criteria menyebut semua ID.
2. Perubahan formula uang, snapshot, status pembayaran, role, atau migration wajib memiliki requirement dan test evidence.
3. Status `Verified` hanya diberikan oleh reviewer independen setelah hasil diuji pada role, environment, dan data yang relevan. Implementer tidak boleh memverifikasi sendiri temuan finansial/security buatannya.
4. Temuan tidak dihapus. Temuan duplikat ditutup sebagai `Duplicate` melalui catatan yang menunjuk ID utama.
5. Risiko yang sengaja diterima harus memiliki alasan, pemilik risiko, batas waktu tinjau, dan mitigasi.
6. `Superseded` hanya dipakai bila baseline/keputusan baru secara eksplisit menggantikan temuan lama dan menyebut ID penggantinya.

## 7. Siklus Audit

| Waktu | Aktivitas |
| --- | --- |
| Discovery | Audit alur berjalan, kebutuhan owner, data, dan pain point pengguna |
| Sebelum desain | Validasi aturan bisnis dan state; susun task flow serta informasi yang dibutuhkan |
| Sebelum implementasi | Review UX/UI, kontrak data, role, acceptance criteria, dan risiko migrasi |
| Saat review | Periksa kode, visual, aksesibilitas, formula, RLS, test, dan dokumentasi |
| Sebelum rilis | Jalankan release gate dan rekam bukti |
| Setelah rilis | Smoke test, pantau exception, dan lakukan retrospective temuan |
| Berkala | Audit lintas halaman dan rekonsiliasi dokumen minimal sekali per rilis besar |

## 8. Kepemilikan dan Persetujuan

- Product Owner menyetujui aturan bisnis, istilah, prioritas, dan risiko bisnis yang diterima.
- Business Analyst menjaga use case, state, formula bisnis, dan traceability requirement.
- UX/UI Reviewer menjaga task flow, informasi, design system, content, responsive, print, dan aksesibilitas.
- Engineering Lead menjaga arsitektur, kualitas implementasi, integrasi, dan kesiapan teknis.
- Data/Security Reviewer wajib meninjau migration, RLS, role, data finansial, dan operasi koreksi.
- QA/Release Reviewer menjaga acceptance evidence, regression, rollback, dan keputusan go/no-go.
- Implementer tidak boleh menjadi satu-satunya pihak yang memverifikasi perubahan finansial atau keamanan buatannya sendiri.

## 9. Definition of Audit Complete

Audit satu scope selesai bila:

- semua halaman/alur dalam scope terinventarisasi;
- temuan mempunyai ID, severity, bukti, pemilik, dan status;
- duplikasi telah dikonsolidasikan;
- temuan P0/P1 sudah masuk task list dengan acceptance criteria;
- hubungan dengan PRD, kode, migration, dan test dapat ditelusuri;
- reviewer domain terkait menyetujui hasil;
- tanggal tinjau berikutnya tercatat.
