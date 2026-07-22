# SOP Pengembangan dan Delivery Sawit CB

| Metadata | Nilai |
| --- | --- |
| Status | Draft untuk persetujuan Product Owner, Engineering Lead, dan QA/Release |
| Versi | 1.0 |
| Berlaku sejak | 17 Juli 2026 |
| Pemilik dokumen | Engineering Lead |
| Approver | Product Owner |
| Ruang lingkup | Discovery, development, data, security, QA, release, incident, dan dokumentasi |
| Siklus tinjau | Minimal setiap tiga bulan, setiap rilis besar, dan setelah insiden `S0`/`S1` |

Dokumen ini adalah sumber kebenaran untuk cara kerja pengembangan dan release gate Sawit CB. Kata **wajib**, **dilarang**, dan **harus** bersifat normatif. Kata **sebaiknya** adalah praktik yang boleh disesuaikan dengan alasan yang tercatat.

> [!IMPORTANT]
> Baseline [Audit Security dan Kesiapan Rilis 17 Juli 2026](security-release-audit-2026-07-17.md) menetapkan **NO-GO untuk rilis fitur finansial baru** sampai seluruh temuan `P0`/`S0` dan gate terkait ditutup dengan bukti. SOP ini tidak membuka kembali gate tersebut. Release yang diperbolehkan selama NO-GO hanya containment/remediasi yang memperkecil risiko dan telah melewati gate sesuai dampaknya.

## 1. Tujuan dan Ruang Lingkup

SOP ini bertujuan agar tim kecil dapat mengirim perubahan dengan cepat tanpa mengorbankan kebenaran angka, integritas histori, keamanan akses, atau kemampuan pemulihan.

SOP berlaku untuk:

- perubahan requirement, alur bisnis, UI/UX, kode, dependency, konfigurasi, dan dokumentasi;
- perubahan PostgreSQL/Supabase, termasuk schema, migration, RLS, grant, RPC, Storage, backfill, dan koreksi data;
- bug fix, hotfix, eksperimen, audit, technical debt, dan pekerjaan berbantuan AI;
- deployment preview, staging, dan production;
- penanganan insiden operasional, finansial, data, dan keamanan.

SOP tidak memberi kewenangan baru untuk mengakses production. Hak akses tetap mengikuti role aplikasi, pengelolaan kredensial, dan penunjukan Release Operator yang berlaku.

## 2. Prinsip Wajib

1. **Kebenaran uang dan data lebih utama daripada kecepatan.** Perubahan yang menyentuh berat, harga, fee, sewa, pembayaran, kas, Pinjaman & Panjar, snapshot, atau laporan harus dapat direkonsiliasi.
2. **Perubahan dibuat kecil, dapat ditinjau, dan dapat dipulihkan.** Satu perubahan memiliki satu tujuan utama dan rollout yang jelas.
3. **PostgreSQL adalah sumber kebenaran bisnis.** Validasi kritis, otorisasi, constraint, ledger, snapshot, dan operasi atomik tidak boleh hanya bergantung pada UI.
4. **Histori finansial tidak ditulis ulang.** Koreksi memakai status batal, reversal, atau transaksi pengganti dengan actor, alasan, waktu, dan referensi asal. Hard delete data bisnis/finansial dilarang.
5. **Snapshot yang sudah menjadi bukti bersifat beku.** Perubahan master atau transaksi live tidak boleh mengubah kwitansi, pembayaran, atau arsip yang sudah diterbitkan.
6. **Security memakai defense in depth.** Visibilitas menu, route guard, grant, RLS, constraint, dan RPC harus konsisten. Menyembunyikan tombol bukan kontrol otorisasi.
7. **Bukti mengalahkan status.** Checklist `[x]`, label Done, atau klaim lulus tidak berlaku jika test, rekonsiliasi, atau release gate gagal.
8. **Keputusan material ditulis.** Keputusan bisnis masuk PRD/BDR; keputusan arsitektur, data, security, atau integrasi masuk ADR.
9. **Ambiguitas data legacy diputus manusia.** Sistem tidak boleh mengarang relasi, nominal, atau reversal untuk kasus historis yang membutuhkan keputusan Owner.
10. **Kontrol sebanding dengan risiko.** Dokumentasi tidak memerlukan upacara setara migration finansial, tetapi semua perubahan tetap memiliki owner dan bukti minimum.
11. **Satu pekerjaan, satu koordinator, ownership file jelas.** Tim tidak membatalkan atau menimpa perubahan pihak lain.
12. **Belajar tanpa menyalahkan.** Review dan postmortem memperbaiki sistem kerja, bukan menyalahkan individu.

## 3. Sumber Kebenaran dan Ketertelusuran

Sumber kebenaran mengikuti [Indeks dan Tata Kelola Dokumentasi](documentation-index.md):

| Jenis informasi | Sumber aktif |
| --- | --- |
| Tujuan, formula, istilah, role, dan aturan bisnis | [`PRD-final.md`](../PRD-final.md) atau BDR yang disetujui |
| Urutan delivery, dependency, dan release scope | [`implementation_plan.md`](../implementation_plan.md) |
| Status eksekusi dan acceptance | [`IMPLEMENTATION-TASKS.md`](../IMPLEMENTATION-TASKS.md) dan work package aktif |
| Arsitektur as-built, stack, data, security, deployment | [`technical-specification.md`](technical-specification.md) |
| Temuan dan taxonomy audit | [`audit-governance.md`](audit-governance.md) serta register audit domain |
| Temuan security dan readiness rilis terkini | [`security-release-audit-2026-07-17.md`](security-release-audit-2026-07-17.md) sampai baseline pengganti diterbitkan |
| Proses delivery dan release gate | Dokumen ini |
| Perilaku teknis aktual | Kode, migration yang terverifikasi, konfigurasi, lockfile, dan hasil test |

Jika terjadi konflik:

1. aturan bisnis terbaru yang telah disetujui di PRD/BDR berlaku untuk perilaku target;
2. schema/migration production yang terverifikasi berlaku untuk kondisi teknis aktual, lalu spesifikasi harus diperbaiki;
3. task yang mengaku selesai tetapi gate gagal dianggap belum selesai;
4. security dan aksesibilitas mengalahkan preferensi visual;
5. perubahan berisiko dihentikan sampai konflik sumber aktif direkonsiliasi.

Rantai minimum untuk perubahan material adalah:

```text
BR/FLOW/AC atau keputusan Owner
  -> AUD bila ada gap
  -> BDR/ADR bila ada keputusan material
  -> TASK/work package
  -> implementasi/migration
  -> TEST dan review evidence
  -> commit/PR
  -> release checklist
```

Gunakan pola ID pada [Tata Kelola Audit](audit-governance.md). Severity dan prioritas tidak dimasukkan ke ID karena dapat berubah.

## 4. Metode Kerja: Dual-Track Agile Berbasis Risiko

### 4.1 Dua Track

**Discovery Track** mengurangi ketidakpastian sebelum coding. Kegiatannya mencakup observasi kerja Admin/Owner, analisis data, audit alur, validasi formula/status, eksplorasi UX, spike teknis, dan penentuan acceptance criteria.

**Delivery Track** membangun work package yang sudah Ready. Kegiatannya mencakup implementasi, migration, review, test, UAT, release, observasi, dan closure.

Kedua track berjalan paralel, tetapi item tidak boleh masuk Delivery hanya karena mendesak. Item harus memenuhi Definition of Ready sesuai risikonya. Temuan baru selama Delivery kembali ke Discovery bila mengubah aturan bisnis, scope, kontrak data, atau strategi keamanan.

### 4.2 Aturan WIP

- Setiap implementer maksimal memiliki satu work package `In Progress`; pekerjaan kedua hanya boleh berupa review singkat atau insiden.
- Tim maksimal memiliki satu perubahan `KR3`/`KR4` yang sedang dipersiapkan untuk production pada waktu yang sama.
- Lane expedite hanya untuk `P0` atau insiden `S0`/`S1`.
- Item yang terblokir tidak disembunyikan dengan memulai banyak pekerjaan baru. Catat blocker, owner, dan tanggal tindak lanjut.
- Branch yang melewati tiga hari kerja harus ditinjau untuk dipecah atau disinkronkan ulang dengan branch asalnya: `dev` untuk pekerjaan normal dan `main` untuk hotfix production.

### 4.3 Kelas Risiko Perubahan

Kelas risiko (`KR`) berbeda dari severity temuan (`S`) dan prioritas (`P`). Kelas tertinggi dari seluruh dampak menjadi kelas work package.

| Kelas | Contoh | Kontrol minimum |
| --- | --- | --- |
| `KR0 Dokumentasi` | Koreksi teks internal tanpa mengubah kontrak | Owner file, diff review, link check |
| `KR1 Rendah` | Copy/UI lokal, style, refactor kecil tanpa perubahan data/role | Work item, self-check, lint/build relevan, satu reviewer bila tersedia |
| `KR2 Sedang` | Workflow non-finansial, query read, komponen shared, dependency minor | Work package, technical/UX review, regression test, rollback aplikasi |
| `KR3 Tinggi` | Uang, formula, snapshot, ledger, migration, RPC, role, RLS, auth, Storage private, laporan sensitif | Review silang Data/Security dan QA, staging/rehearsal, UAT, rekonsiliasi, backup dan rollback |
| `KR4 Kritis` | Koreksi data production, perubahan destruktif, backfill besar, restore, rotasi kredensial darurat, perubahan yang sulit dibalik | BDR/ADR sesuai dampak, persetujuan eksplisit, dua-person control, rehearsal, backup terverifikasi, jendela rilis dan incident readiness |

Aturan klasifikasi:

- setiap migration production minimal `KR3`;
- setiap koreksi data production adalah `KR4`;
- perubahan UI yang dapat menyebabkan salah bayar minimal `KR3` walaupun tidak mengubah database;
- upgrade major framework/client minimal `KR3` sampai kompatibilitas dibuktikan;
- perubahan campuran mengikuti kelas risiko tertinggi, bukan rata-rata.

### 4.4 Panel Spesialis

Pekerjaan lintas domain mengikuti [Protokol Kolaborasi Panel Spesialis](ai-specialist-collaboration.md): satu koordinator, ownership file eksplisit, dan koreksi silang. AI dapat menjadi explorer atau worker, tetapi tidak menjadi approver bisnis, pemegang kredensial, Release Operator, atau penerima risiko production.

## 5. Lifecycle End-to-End

### 5.1 Intake

Semua permintaan masuk ke satu backlog yang dapat ditelusuri. Percakapan, chat, atau instruksi lisan harus diubah menjadi work item sebelum implementasi normal dimulai.

Informasi minimum:

- masalah dan dampak pengguna/bisnis;
- role, route/alur, dan kondisi aktual;
- hasil yang diinginkan serta scope yang tidak masuk;
- requirement/flow/audit terkait;
- indikasi severity, prioritas, dan kelas risiko;
- owner keputusan dan target waktu bila ada;
- bukti awal seperti screenshot, query, log, atau contoh dokumen.

### 5.2 Triage

Engineering Lead dan Product Owner/BA:

1. menghapus duplikasi dan menautkan item utama;
2. memisahkan severity dari prioritas;
3. menentukan apakah item perlu Discovery, BDR, ADR, audit, atau incident flow;
4. menetapkan kelas risiko awal, dependency, owner, dan reviewer;
5. menentukan `P0`, `P1`, `P2`, `P3`, atau menolak dengan alasan.

### 5.3 Discovery dan Framing

Discovery menjawab:

- siapa melakukan apa, pada pemicu dan data apa;
- state awal, transisi, exception, permission, dan hasil akhir;
- formula, satuan, pembulatan, snapshot, ledger, dan audit yang berlaku;
- dampak ke histori, laporan, kas, kwitansi, role lain, export, dan print;
- alternatif solusi, risiko, serta cara membuktikan keberhasilan.

Output proporsional berupa update PRD/BDR, flow dan acceptance criteria, wireflow/UX note, spike, atau ADR. Discovery selesai ketika ketidakpastian material telah diputus atau dicatat sebagai batas.

### 5.4 Perencanaan Work Package

Gunakan [Work Package Template](templates/work-package-template.md). Work package harus memiliki:

- `TASK-*`, scope masuk/tidak masuk, owner, reviewer, dan target release;
- tautan `BR-*`, `FLOW-*`, `AC-*`, `AUD-*`, `BDR-*`, atau `ADR-*` yang relevan;
- ownership file/modul agar pekerjaan paralel tidak tumpang tindih;
- verification plan dengan `TEST-*`;
- risiko, trigger rollback, dan langkah pemulihan.

Status work package:

```text
Draft -> Ready -> In Progress -> Review -> Verified -> Released
                    |              |
                    +-> Blocked <--+
```

`Verified` berarti acceptance dan review lulus pada environment yang ditentukan. `Released` hanya diberikan setelah deployment, smoke test, dan observasi awal selesai.

### 5.5 Design dan Readiness Review

Sebelum `Ready`, reviewer memastikan:

- aturan bisnis dan terminology telah disetujui;
- desain UI mencegah kesalahan dan mencakup state relevan;
- kontrak data, otorisasi, migration, kompatibilitas, dan rollback realistis;
- acceptance dapat diuji dan test data tersedia;
- perubahan dapat dipecah tanpa meninggalkan state production yang tidak aman.

### 5.6 Implementasi

Implementer:

1. bekerja pada branch dan file yang ditetapkan;
2. menyinkronkan branch target (`dev` untuk pekerjaan normal, `main` untuk hotfix/release) tanpa menghapus perubahan pihak lain;
3. membuat perubahan paling kecil yang memenuhi acceptance;
4. menjalankan test sedini mungkin, bukan menunggu PR selesai;
5. memperbarui work package jika asumsi atau risiko berubah;
6. menghentikan implementasi dan kembali ke Discovery bila kontrak material belum jelas.

### 5.7 Review dan Verification

Review mencakup correctness bisnis, UX, kode, data, security, test, dokumentasi, dan rollback sesuai kelas risiko. Komentar wajib membedakan blocker, defect, pertanyaan, dan saran.

Status `Verified` memerlukan:

- seluruh acceptance criteria relevan lulus;
- bukti `TEST-*` tercatat;
- reviewer domain menyetujui;
- tidak ada temuan `P0` atau `S0`/`S1` yang belum ditangani pada scope;
- risiko tersisa memiliki owner dan keputusan yang sah.

### 5.8 Release, Observe, dan Close

Setelah go/no-go, Release Operator menjalankan prosedur pada Bagian 16. Work package ditutup sebagai `Released` setelah:

- versi/commit dan migration tercatat;
- smoke test per role lulus;
- rekonsiliasi data relevan bernilai sesuai expected;
- jendela observasi selesai tanpa trigger rollback;
- dokumentasi dan komunikasi operasional selesai.

## 6. Intake dan Change Control

### 6.1 Jenis Perubahan

| Jenis | Definisi | Approval |
| --- | --- | --- |
| Standard | Perubahan berulang `KR0`/`KR1` dengan prosedur dan dampak yang sudah dikenal | Engineering Lead atau reviewer file |
| Normal | Fitur, bug, technical debt, dependency, atau perubahan proses yang direncanakan | Sesuai RACI dan kelas risiko |
| Emergency | Perubahan untuk menahan atau memulihkan insiden `S0`/`S1` | Incident Commander + otoritas bisnis/teknis yang tersedia; review retrospektif wajib |

Migration, perubahan role/RLS, dan koreksi data production tidak boleh diklasifikasikan sebagai Standard.

### 6.2 Scope Control

- Perubahan setelah status `Ready` yang mengubah aturan bisnis, data, role, acceptance, atau kelas risiko wajib kembali ke readiness review.
- Perbaikan kecil yang tidak mengubah risiko boleh ditambahkan jika dicatat pada scope dan PR.
- Refactor, dependency update, atau cleanup yang tidak diperlukan tidak boleh diselipkan ke PR finansial.
- Pekerjaan di luar scope dibuat sebagai item baru dan ditautkan.
- Product Owner menyetujui scope bisnis; Engineering Lead menyetujui boundary teknis.

### 6.3 Koreksi Data Production

Koreksi data production hanya boleh dilakukan sebagai `KR4` dengan record yang memuat:

1. sumber masalah dan daftar tabel/record/nominal terdampak;
2. query read-only untuk preview dan row count sebelum perubahan;
3. keputusan bisnis untuk kasus ambigu;
4. backup/recovery point yang terverifikasi;
5. script idempotent atau transaksi terkontrol dengan batas baris;
6. reviewer Data/Security dan QA/Release yang berbeda dari implementer;
7. query rekonsiliasi sebelum/sesudah;
8. actor, waktu, alasan, hasil, dan link audit;
9. migration atau artefak executable di Git.

Edit manual melalui SQL Editor production dilarang untuk perubahan normal. Dalam emergency, perubahan manual minimum harus segera direkonsiliasi menjadi migration/record, diverifikasi terhadap migration history, dan direview maksimal satu hari kerja setelah stabil.

### 6.4 Change Freeze

Perubahan `KR3`/`KR4` tidak dirilis saat:

- Owner/Release Operator yang dibutuhkan tidak tersedia;
- sedang berlangsung pembayaran, settlement, atau rekonsiliasi penting;
- backup, staging, atau rollback tidak dapat diverifikasi;
- ada insiden aktif yang memengaruhi area sama;
- migration history local/remote tidak sinkron.

## 7. Severity dan Prioritas

Severity mengikuti [Tata Kelola Audit](audit-governance.md) dan menjelaskan dampak, bukan urutan pengerjaan.

| Severity | Definisi | Target respons pada jam dukungan |
| --- | --- | --- |
| `S0 Kritis` | Kehilangan/korupsi data atau uang, kebocoran akses, atau sistem utama tidak dapat dipakai | Acknowledge <= 15 menit; bentuk incident team dan mulai containment segera |
| `S1 Tinggi` | Perhitungan/status salah, workflow utama terhenti, atau risiko salah bayar nyata | Acknowledge <= 1 jam; mitigasi pada hari yang sama |
| `S2 Sedang` | Tugas tetap selesai tetapi membingungkan, lambat, tidak konsisten, atau rawan salah | Triage <= 1 hari kerja |
| `S3 Rendah` | Perapian, polish, atau masalah lokal tanpa dampak material | Triage pada sesi mingguan |

Prioritas menjelaskan urutan delivery:

| Prioritas | Aturan |
| --- | --- |
| `P0` | Harus selesai atau diterima secara formal sebelum penggunaan/rilis terkait dilanjutkan |
| `P1` | Masuk iterasi aktif berikutnya |
| `P2` | Dikerjakan setelah workflow inti stabil |
| `P3` | Backlog/eksperimen; dikerjakan setelah manfaat tervalidasi |

Aturan:

- `S0` tidak otomatis berarti semua solusi menjadi `P0`; containment adalah `P0`, sedangkan perbaikan permanen diprioritaskan berdasarkan risiko.
- Temuan `S2` dapat menjadi `P0` jika merupakan compliance/release gate.
- Perubahan prioritas hanya dilakukan Product Owner bersama Engineering Lead dan dicatat dengan alasan.
- Accepted Risk harus memiliki owner, mitigasi, batas waktu, dan tanggal tinjau. Risiko security/data `S0` tidak boleh diterima untuk release normal.

## 8. Artefak Wajib

| Artefak | Kapan wajib | Template/sumber |
| --- | --- | --- |
| Work package | Semua perubahan normal `KR1-KR4` | [Work Package](templates/work-package-template.md) |
| Business Decision Record | Aturan/formula/trade-off bisnis material | [BDR](templates/business-decision-record-template.md) |
| Architecture Decision Record | Keputusan arsitektur, data, security, integrasi material | [ADR](templates/architecture-decision-record-template.md) |
| Audit finding | Gap hasil audit atau insiden yang perlu ditelusuri | [Audit Governance](audit-governance.md) |
| PR record | Semua merge ke `main` | [PR Template](../.github/pull_request_template.md) |
| Test evidence | Semua acceptance; kedalaman mengikuti risiko | `TEST-*` pada work package/PR |
| Release checklist | Setiap calon release staging/production | [Release Checklist](templates/release-checklist-template.md) |
| Incident record/postmortem | Insiden `S0`/`S1`; `S2` bila berulang | Tracker yang disetujui atau `docs/incidents/` |

Aturan artefak:

- tautkan ke sumber, jangan menyalin aturan lengkap ke banyak dokumen;
- jangan menyimpan secret, token, password, dump production, atau data pribadi yang tidak diperlukan;
- screenshot/log harus disanitasi dan memiliki tanggal, environment, serta pemeriksa;
- bukti test memuat perintah/skenario, expected, actual, dan hasil;
- dokumen keputusan tidak ditulis ulang untuk mengubah sejarah. Buat record pengganti berstatus `Superseded`.

## 9. Peran dan RACI

Peran adalah tanggung jawab, bukan jumlah orang. Satu orang boleh memegang beberapa peran pada tim kecil, tetapi pemisahan verifikasi tetap berlaku untuk perubahan finansial, role, RLS, migration, dan koreksi data.

Persetujuan dihitung berdasarkan **identitas manusia**, bukan jumlah topi peran. Satu orang yang bertindak sebagai Engineering Lead, Data/Security, dan Release Operator tetap hanya satu identitas. Perubahan `KR3/KR4` minimal memerlukan author, reviewer independen, dan Product Owner/UAT yang terpisah; bila tidak tersedia, release normal ditahan.

| Singkatan | Peran | Tanggung jawab utama |
| --- | --- | --- |
| PO | Product Owner | Nilai bisnis, aturan, prioritas, UAT, penerimaan risiko bisnis |
| BA | Product/Business Analyst | Requirement, flow, state, formula, acceptance, traceability |
| EL | Engineering Lead/Delivery Lead | Arsitektur, planning, koordinasi, kualitas, go/no-go teknis |
| UX | UX/UI/Accessibility Reviewer | Task flow, content, komponen, responsive, print, accessibility |
| IMP | Implementer | Kode/migration, self-test, handoff, perbaikan review |
| DS | Data/Security Reviewer | Schema, query, RLS, RPC, privacy, performance, rekonsiliasi |
| QA | QA/Release Reviewer | Strategy test, evidence, regression, rollback, release gate |
| OPS | Admin/Owner operasional sebagai UAT user | Validasi task nyata dan kesiapan operasional |
| REL | Release Operator | Eksekusi migration/deploy, pencatatan versi, smoke dan rollback |

RACI: `R` mengerjakan, `A` bertanggung jawab akhir, `C` dikonsultasikan, `I` diinformasikan.

| Aktivitas | PO | BA | EL | UX | IMP | DS | QA | OPS | REL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Intake dan prioritas | A | R | R | C | I | C | C | C | I |
| Requirement/acceptance bisnis | A | R | C | C | C | C | C | C | I |
| Desain arsitektur/teknis | C | C | A | C | R | R | C | I | C |
| Desain dan review UX/UI | C | C | A | R | R | I | C | C | I |
| Implementasi | I | C | A | C | R | C | C | I | I |
| Review data/security `KR3/KR4` | I | C | A | I | C | R | R | I | C |
| Verification dan regression | I | C | A | C | R | C | R | C | I |
| UAT perubahan bisnis | A | R | C | C | C | I | R | R | I |
| Go/no-go teknis | C | I | A | I | C | C | R | I | R |
| Go/no-go bisnis material | A | R | C | C | I | C | C | C | I |
| Deploy production | I | I | A | I | C | C | C | I | R |
| Incident response | C | I | A | I | R | R | R | C | R |
| Dokumentasi dan closure | C | R | A | C | R | C | C | I | C |

Ketentuan pemisahan tugas:

- implementer tidak boleh menjadi satu-satunya verifier perubahan uang, schema, role, RLS, atau security;
- bila hanya ada satu engineer, gunakan reviewer Data/Security eksternal/rotasi dan UAT Product Owner. Tanpa reviewer, release normal `KR3`/`KR4` ditahan;
- emergency boleh memakai approval yang tersedia untuk containment, tetapi review independen dan rekonsiliasi wajib setelah stabil;
- satu Release Operator menjalankan `db push` pada satu waktu.

Untuk transaksi uang, maker-checker minimum adalah:

- Admin menjadi maker pencatatan/pengajuan rutin;
- Owner menjadi checker untuk approval, reversal, tarif, dan exception;
- Super Admin menjadi custodian akun/deployment dan akses break-glass, bukan operator transaksi harian;
- `diajukan_oleh` dan `disetujui_oleh` harus berbeda pada aksi yang diwajibkan maker-checker;
- self-approval hanya melalui break-glass dengan incident ID, aktivator berwenang, scope minimum, TTL yang ditentukan sebelum aktivasi, auto-revoke/manual revoke terverifikasi, alasan, audit, serta review independen maksimal satu hari kerja setelah stabil;
- perubahan commit, migration, konfigurasi, atau artefak setelah approval membatalkan approval yang terdampak.

## 10. Branch, Commit, PR, dan Review

### 10.1 Branch

- `main` adalah branch production/release, tetap menjadi default branch repository, dan harus selalu sesuai dengan commit aplikasi yang layak production.
- `dev` adalah branch integrasi seluruh pengembangan normal. Fitur, perbaikan non-emergency, UX/UI, dokumentasi, dan perubahan Supabase dimulai dari `dev` dan kembali melalui PR ke `dev`.
- Promosi ke production hanya melalui PR release dari `dev` ke `main` setelah work package berstatus siap, seluruh gate relevan lulus, UAT/approval tersedia, dan urutan deploy aplikasi/database telah disetujui.
- Hotfix insiden production dibuat dari `main` dengan pola `hotfix/*`, ditujukan langsung ke `main`, lalu commit `main` hasil hotfix wajib disinkronkan kembali ke `dev` melalui PR agar perbaikan tidak hilang pada release berikutnya.
- Direct push ke `main` dan `dev` dilarang. Keduanya wajib memakai branch protection, required checks, dan conversation resolution. PR ke `main` wajib memiliki minimal satu approval independen. Branch protection `dev` tidak mewajibkan approval, tetapi kebutuhan reviewer berdasarkan kelas risiko pada Bagian 10.4 tetap berlaku dan tidak boleh dianggap gugur hanya karena GitHub mengizinkan merge. Override `main` hanya untuk emergency yang tercatat dan wajib direview retrospektif.
- Format branch:

```text
feat/TASK-DOMAIN-NNN-ringkas
fix/TASK-DOMAIN-NNN-ringkas
hotfix/TASK-DOMAIN-NNN-ringkas
docs/TASK-DOMAIN-NNN-ringkas
chore/TASK-DOMAIN-NNN-ringkas
spike/TASK-DOMAIN-NNN-ringkas
```

- Branch pendek dan fokus. Jangan membawa perubahan unrelated atau membatalkan perubahan pihak lain.
- Branch normal dibuat dari dan disinkronkan dengan `dev` sebelum final review. Hanya `hotfix/*` dibuat dari dan disinkronkan dengan `main`.

### 10.2 Commit

Gunakan subject ringkas dengan pola yang telah dipakai repo:

```text
feat: add controlled receipt reversal
fix: preserve paid receipt snapshots
docs: define release governance
chore: update dependency lockfile
```

Commit harus membangun satu cerita review. Jangan mencampur formatting massal, generated output, atau refactor besar dengan bug finansial.

### 10.3 Pull Request

Semua perubahan ke `dev` atau `main` memakai [PR Template](../.github/pull_request_template.md). PR wajib menjelaskan:

- masalah dan hasil, bukan hanya daftar file;
- traceability `BR/FLOW/AC/AUD/BDR/ADR/TASK/TEST`;
- dampak role, formula, ledger, snapshot, histori, route, RPC, dan data;
- perintah serta hasil test;
- migration/backfill, RLS, backup, rollout, dan rollback;
- dokumentasi yang diperbarui;
- reviewer wajib sesuai domain.

Target ukuran PR adalah kurang dari 400 baris perubahan manual bila memungkinkan, di luar lockfile/generated SQL. PR lebih besar harus menjelaskan alasan, pembagian review, dan urutan commit.

### 10.4 Review Gate

| Risiko | Review minimum |
| --- | --- |
| `KR0/KR1` | Review pemilik dokumen/modul; self-review boleh bila tidak mengubah perilaku dan tidak ada reviewer tersedia |
| `KR2` | Satu reviewer teknis/UX yang berbeda dari implementer |
| `KR3` | Engineering Lead + Data/Security + QA; Product/UX sesuai dampak |
| `KR4` | Seluruh reviewer `KR3`, Product Owner, Release Operator, dan keputusan go/no-go eksplisit |

Reviewer memeriksa:

- kebutuhan akar terselesaikan, bukan hanya gejala;
- permission, validation, error, retry, cancel/reversal, dan concurrency;
- dampak lintas laporan, kas, snapshot, kwitansi, dan role;
- query bounded, pagination, constraint, index, dan error handling;
- test negatif dan rekonsiliasi, bukan hanya happy path;
- rollback dapat dijalankan dalam kondisi nyata.

### 10.5 Merge

- Squash merge adalah default agar history `dev` dan `main` ringkas. Merge commit boleh untuk rangkaian yang perlu dipertahankan dengan alasan jelas.
- Jangan merge dengan gate merah, review unresolved, migration drift, atau dokumentasi kontrak yang tertinggal.
- Hapus branch setelah merge dan tautkan commit final ke work package/release record.

## 11. SOP Coding dan Data

### 11.1 Standar Umum

- Ikuti pola Next.js App Router, React, JavaScript/JSX, CSS, dan helper yang sudah ada. Konversi lintas proyek ke TypeScript/framework lain memerlukan ADR.
- Gunakan komponen/helper existing sebelum membuat abstraksi baru.
- Formula finansial shared ditempatkan di `lib/` atau RPC/SQL terkontrol, bukan diduplikasi pada beberapa halaman.
- Client validation meningkatkan UX; database validation menjaga integritas. Keduanya diperlukan untuk aturan kritis.
- Operasi lintas tabel yang memengaruhi uang, ledger, snapshot, approval, atau reversal harus atomik melalui RPC/transaksi database.
- Mutasi finansial harus idempotent atau memiliki constraint/idempotency key agar retry tidak menggandakan uang.
- Gunakan constraint dan locking yang sesuai untuk nomor unik, alokasi, pembayaran, dan saldo yang rawan race condition.
- Tambahkan komentar hanya pada aturan yang tidak jelas dari kode.
- Tidak boleh memakai `window.alert`, `window.confirm`, atau `window.prompt`; gunakan dialog aplikasi dengan alasan/konfirmasi yang dapat diuji.

### 11.2 Konvensi Data Bisnis

- Berat disimpan dalam kg. Konversi ton hanya untuk tampilan/perhitungan yang memang memerlukan ton.
- Nominal Rupiah disimpan/dihitung tanpa floating-point yang dapat menghasilkan pecahan tidak terkontrol. Aturan pembulatan harus eksplisit.
- `Asia/Jakarta` adalah zona waktu bisnis. Timestamp audit tetap menyimpan waktu yang dapat ditelusuri dan UI menampilkan konteks tanggal yang jelas.
- Tarif, fee, identitas, berat, serta keputusan potongan pada dokumen finansial memakai snapshot.
- Saldo dihitung dari ledger; jangan membuat angka saldo manual kedua tanpa kontrak rekonsiliasi.
- Kwitansi gabungan tetap memisahkan transaksi, panjar, sewa, dan subtotal per mitra.
- Istilah UI final mengikuti PRD, misalnya **Pinjaman & Panjar**, **Berat Netto**, **Berat Dibayar**, dan **Ringkasan Arus Kas**.
- Query tidak boleh mengandalkan truncation diam-diam. Konfigurasi Data API lokal membatasi 1.000 row per request; gunakan pagination, aggregate server-side, atau RPC terukur.

### 11.3 Error, Logging, dan Audit

- Error untuk pengguna menjelaskan tindakan berikutnya tanpa membocorkan detail internal.
- Log teknis tidak boleh memuat password, token, key, atau data pribadi berlebihan.
- Aksi sensitif menyimpan actor dari sesi terverifikasi, role, waktu, alasan, before/after atau referensi perubahan, serta approval bila ada.
- Audit log tidak boleh dapat dipalsukan client atau dipanggil `anon`.
- Kegagalan audit pada operasi finansial harus menggagalkan transaksi utama, bukan dibiarkan sebagai request terpisah.

### 11.4 Dependency dan Konfigurasi

- Gunakan `npm` dan commit `package-lock.json` untuk setiap perubahan dependency.
- Versi baru harus ditinjau changelog, compatibility, license, dan security advisory. Upgrade major memerlukan ADR/verification plan.
- Jalankan `npm ci` pada environment bersih untuk memverifikasi lockfile.
- Jalankan `npm audit --omit=dev` dan secret/dependency scan yang disetujui. Temuan critical/high adalah release blocker kecuali exception `S1` disetujui Product Owner, Data/Security, dan QA dengan mitigasi serta expiry; temuan `S0` tidak dapat dikecualikan.
- CI untuk PR ke `dev` dan `main` wajib menjalankan lint, build, test, secret scan, dependency audit, migration lint, dan lockfile integrity. Sampai CI tersedia, hasil gate dicatat manual dan branch target tidak boleh diperlakukan seolah required checks sudah aktif.
- Jangan commit `.env*`, `.vercel/`, `.stitch/`, `.agents/`, build output, dump, atau data produksi.
- Hanya URL dan publishable key Supabase boleh digunakan pada `NEXT_PUBLIC_*`. Secret/service role key tidak boleh berada di browser.

## 12. SOP Supabase, PostgreSQL, dan Security

### 12.1 Environment

| Environment | Penggunaan | Aturan |
| --- | --- | --- |
| Local | Development awal, reset migration, lint, test terisolasi | Docker diperlukan untuk stack lokal; tidak memakai data production |
| Development/Staging | Integration, role test, migration rehearsal, UAT | Project Supabase terpisah dari production; data sintetis atau tersanitasi |
| Production | Operasi bisnis nyata | Hanya Release Operator; tidak untuk eksperimen/test destruktif |

Perubahan `KR3`/`KR4` normal tidak boleh menuju production bila staging terpisah belum tersedia atau tidak dapat diverifikasi.

Konfigurasi [`supabase/config.toml`](../supabase/config.toml) adalah konfigurasi lokal, bukan bukti konfigurasi hosted production. Target project, Postgres version, Auth, Data API, Storage, backup tier, dan environment variables wajib diverifikasi pada setiap release relevan.

### 12.2 Model Migration

Repo memakai **imperative migrations** di `supabase/migrations/`; `schema_paths` kosong. Aturan:

1. Semua perubahan schema remote berasal dari migration di Git.
2. Buat file dengan CLI, jangan mengarang timestamp:

```powershell
npx supabase migration new nama_perubahan
```

3. Satu migration memiliki satu tujuan bisnis/teknis yang jelas.
4. Migration yang sudah diterapkan tidak diedit. Perbaikan memakai migration maju baru.
5. Dashboard SQL/Table Editor remote tidak digunakan untuk perubahan schema normal.
6. Satu orang menjalankan `db push` pada satu waktu.
7. `migration repair`, `--include-all`, atau rekonsiliasi history hanya digunakan setelah diagnosis dan approval, bukan untuk memaksa push gagal.

Workflow development:

```powershell
npm ci
npx supabase migration list --linked
npx supabase start
npx supabase db reset --local --no-seed
npx supabase db lint --local --schema public --level error --fail-on error
npm run lint
npm run build
git diff --check
```

Catatan baseline: `config.toml` mengaktifkan seed `./seed.sql`, tetapi `supabase/seed.sql` belum tersedia. Sampai seed sintetis yang aman dibuat, reset lokal wajib memakai `--no-seed`. `supabase/seed_update_tarif.sql` tidak dianggap seed default.

Workflow calon release pada staging, lalu production dari commit `main` yang telah disetujui:

```powershell
npx supabase migration list --linked
npx supabase db push --dry-run --linked
npx supabase db push --linked
npx supabase migration list --linked
npx supabase db lint --linked --schema public --level error --fail-on error
```

Setiap perintah linked harus didahului verifikasi target project/environment tanpa menyalin secret ke log. Output penting dicatat pada release checklist.

`db push --dry-run` hanya menginventarisasi migration yang akan diterapkan; perintah itu **bukan upgrade rehearsal**. Gate database memisahkan tiga bukti:

1. **Clean install:** seluruh migration dijalankan dari nol pada database local terisolasi.
2. **Dry-run inventory:** nama dan urutan migration target diperiksa tanpa mengklaim SQL telah berhasil dieksekusi.
3. **Upgrade rehearsal:** migration benar-benar dieksekusi pada clone/snapshot tersamarkan yang mewakili versi production saat ini, lalu diuji lock duration, timeout, row count, checkpoint backfill, rekonsiliasi, dan forward-fix/rollback.

`db reset --linked`, reset melalui production connection string, serta rehearsal destruktif pada production dilarang.

### 12.3 Desain Migration dan Backfill

- Non-destructive adalah default: expand schema, deploy kode kompatibel, backfill, pindahkan read/write, lalu cleanup pada release terpisah.
- `DROP`, destructive rename/type conversion, truncate, atau rewrite tabel besar memerlukan `KR4`, ADR, backup, rehearsal, dan strategi kompatibilitas.
- Tambahan `NOT NULL`, unique, foreign key, atau constraint baru harus diawali query kualitas data dan rencana menangani pelanggaran.
- Backfill harus bounded, dapat dilanjutkan, idempotent, dan memiliki expected row count serta query rekonsiliasi.
- Nilai uang historis tidak boleh dihitung ulang memakai master terbaru kecuali keputusan bisnis dan bukti menyatakan demikian.
- Pertimbangkan lock duration, transaction size, index, query plan, dan waktu operasional sebelum production.
- Untuk query berat, gunakan `EXPLAIN (ANALYZE, BUFFERS)` pada data staging yang representatif tanpa menjalankan eksperimen pada production.
- Setiap migration finansial menyertakan forward-fix plan. Down migration hanya boleh dipakai bila telah diuji dan tidak menghilangkan data.

### 12.4 Grant, RLS, View, dan RPC

- Semua tabel pada schema exposed, termasuk `public`, wajib mengaktifkan RLS.
- Hak Data API harus diberikan eksplisit per role dan operasi. Jangan bergantung pada auto-expose/default grant.
- Atur dan audit default privileges agar tabel/function baru tidak mewarisi `TRUNCATE`, mutation, atau execute berlebih. Verifikasi final-state ACL untuk object lama dan baru pada setiap migration.
- RLS dan grant adalah lapisan berbeda; keduanya harus lolos test.
- `TO authenticated` hanya membuktikan sesi, bukan otorisasi bisnis. Policy harus memeriksa ownership/role yang benar.
- Hindari policy `USING (true)`/`WITH CHECK (true)` pada data sensitif kecuali read access tersebut memang disetujui dan terdokumentasi.
- `UPDATE` membutuhkan policy `SELECT` yang sesuai serta `USING` dan `WITH CHECK` untuk mencegah pemindahan ownership.
- Authorization tidak boleh memakai `raw_user_meta_data`/`user_metadata`; gunakan sumber role aplikasi yang tidak dapat diubah user.
- View exposed memakai `security_invoker = true` pada Postgres 15+ atau aksesnya dicabut/dipindah ke schema private.
- `SECURITY DEFINER` hanya digunakan bila benar-benar diperlukan. Fungsi wajib memiliki fixed `search_path`, pemeriksaan `auth.uid()` dan role, validasi input, audit, serta grant minimum.
- Cabut execute dari `PUBLIC`/`anon` pada RPC sensitif dan grant hanya ke role yang diperlukan.
- Fungsi `SECURITY DEFINER` sebaiknya berada di schema non-exposed; jangan menggunakannya sekadar untuk melewati error permission.
- Role aplikasi tidak memperoleh `DELETE`/`TRUNCATE` pada ledger, pembayaran, snapshot, dan transaksi finansial.

Setiap perubahan role/RLS/RPC diuji melalui matriks minimal:

| Actor | Positive test | Negative test |
| --- | --- | --- |
| `anon` | Hanya endpoint publik yang memang disetujui | Seluruh data bisnis/RPC sensitif ditolak |
| Admin | Pencatatan operasional yang diizinkan | Profit, reversal Owner, direct write sensitif ditolak |
| Owner | Approval, laporan sensitif, reversal yang diizinkan | Pengelolaan user/role Super Admin ditolak |
| Super Admin | Administrasi teknis/user sesuai scope | Operasi tetap tunduk pada constraint dan audit |

### 12.5 Auth, Secret, dan Session

- Aplikasi bisnis memerlukan login; anonymous sign-in tidak menjadi jalur akses bisnis.
- Server/route guard memvalidasi user dengan pola `auth.getUser()` yang berlaku, lalu database tetap menegakkan akses.
- Profile hilang, role tidak dikenal, role berubah, atau sesi lama harus fail-closed. Jangan menormalisasi kondisi tidak dikenal menjadi Admin.
- Publishable key boleh berada di client karena dibatasi Auth/RLS; service role, secret key, database password, JWT signing key, dan token provider dilarang di frontend/repo/log.
- Rotasi/revoke session dilakukan saat akun sensitif dinonaktifkan atau ada indikasi kompromi.
- Perubahan expiry, signup, MFA, redirect, atau provider Auth adalah `KR3` dan harus dibandingkan antara local, staging, dan production. Hosted production harus memiliki attestation terpisah untuk signup/invitation, password, leaked-password protection, MFA, session, dan reauthentication aksi sensitif.

Baseline lulus minimum untuk hosted Auth:

- pembuatan akun invitation-only untuk aplikasi internal;
- password policy kuat dan leaked-password protection aktif sesuai kemampuan platform;
- MFA wajib untuk Owner dan Super Admin;
- session/idle limit ditentukan, didokumentasikan, dan diuji;
- reauthentication untuk perubahan role, rekening, kredensial, dan aksi sensitif yang disepakati;
- disable user atau perubahan role mencabut/menolak sesi lama dalam batas waktu yang disetujui;
- negative test mencakup `anon`, user tanpa profile, unknown role, disabled user, role berubah, stale session, Data API, RPC, dan Storage.

Attestation tanpa nilai aktual dan hasil pass/fail bukan evidence gate.

### 12.6 Storage

- Bucket untuk bukti finansial harus private; public bucket hanya untuk aset yang memang publik seperti branding yang disetujui.
- Database menyimpan path/metadata, bukan blob/base64 besar.
- Policy Storage mengikuti ownership/role, jenis file, ukuran, dan lifecycle.
- Upsert diuji dengan izin `INSERT`, `SELECT`, dan `UPDATE` yang diperlukan.
- Validasi MIME, extension, ukuran, nama file, dan akses URL.
- Cleanup file orphan dan retensi bukti memiliki owner serta audit.
- Backup database tidak memulihkan objek Storage yang telah terhapus; prosedur backup/restore Storage harus terpisah.

### 12.7 Advisors, Performance, dan Drift

- Jalankan DB lint pada local/staging dan linked target sesuai release gate.
- Review Security/Performance Advisors untuk perubahan schema, function, view, RLS, atau index.
- Foreign key dan kolom filter/join berfrekuensi tinggi ditinjau kebutuhan index-nya.
- Query UI harus bounded, menangani pagination, dan tidak melakukan N+1 tanpa alasan.
- `migration list --linked` harus sinkron sebelum dan sesudah release. Drift adalah release blocker.
- Perubahan package Supabase mengikuti versi lockfile dan dokumentasi/changelog resmi terbaru.

### 12.8 Backup dan Restore

- Release Operator memverifikasi backup/PITR yang tersedia pada tier project, waktu recovery point, dan siapa yang berwenang restore.
- Migration `KR3` memerlukan backup/recovery point yang sesuai dampak; `KR4` memerlukan bukti backup dan rehearsal pemulihan.
- Backup logical disimpan terenkripsi dan off-site sesuai kebijakan akses.
- Restore dilakukan ke environment baru/staging untuk drill bila memungkinkan, bukan langsung menimpa production.
- Restore production adalah tindakan terakhir dengan keputusan Incident Commander, Engineering Lead, dan Product Owner karena menimbulkan downtime dan potensi kehilangan data setelah recovery point.
- Latihan restore dilakukan minimal per kuartal dan hasilnya dicatat.

Target pemulihan berikut adalah **usulan baseline** dan belum dianggap efektif sampai Product Owner/Engineering Lead menyetujuinya melalui BDR serta kemampuan backup/PITR dibuktikan lewat restore drill:

| Tier | Contoh | Usulan RPO | Usulan RTO |
| --- | --- | --- | --- |
| A Finansial kritis | Ledger, pembayaran, snapshot, Pinjaman/Panjar | <= 15 menit | <= 4 jam |
| B Operasional | Pengiriman, master aktif, laporan operasional | <= 4 jam | <= 8 jam |
| C Pendukung | Dokumentasi/konfigurasi non-rahasia yang dapat dibangun ulang | <= 24 jam | <= 2 hari kerja |

Selama RPO/RTO belum disetujui atau tidak didukung tier project, `G2` untuk `KR3/KR4` dianggap gagal.

## 13. SOP UX/UI Review

Sawit CB adalah alat back-office operasional dan finansial. Review UX memprioritaskan kecepatan input batch, kejelasan angka, pencegahan salah bayar, dan kemampuan menelusuri koreksi.

### 13.1 Gate Sebelum Implementasi

- Role, tugas, pemicu, frekuensi, perangkat, dan kondisi lapangan dijelaskan.
- Urutan input mengikuti nota/pekerjaan nyata, bukan struktur tabel database.
- Istilah sama dengan PRD/audit flow dan tidak berubah arti antarhalaman.
- Aksi finansial menjelaskan dampak ke kas, panjar, sewa, snapshot, dan histori.
- Permission, approval, cancel/reversal, dan status `Perlu Review/Verifikasi` terlihat jelas.
- Route Coming Soon/terkunci tidak boleh hanya memakai overlay atau `pointer-events`. Child content tidak boleh menjalankan query/mutation dan kontrol di bawahnya harus tidak dapat dicapai keyboard.

### 13.2 State Wajib Ditinjau

Sesuai relevansi, desain dan implementasi mencakup:

- loading dan skeleton/progress yang tidak menggeser layout;
- empty state yang membedakan tidak ada data dari filter kosong;
- validation field dan cross-field;
- error, retry, timeout, dan duplicate submission;
- success dengan hasil yang dapat diverifikasi;
- permission denied dan session expired;
- draft, pending approval, paid, cancelled, reversed, perlu review, dan verified;
- data legacy/tidak lengkap tanpa mengarang nilai;
- confirmation dengan alasan wajib untuk aksi sensitif.

### 13.3 Review Visual dan Interaction

- Uji desktop operasional, tablet, dan mobile utama.
- Uji keyboard order, focus visible, label, touch target, contrast, dialog focus trap, dan screen-reader semantics dasar.
- Pastikan tabel memiliki header jelas, alignment angka, pagination, filter aktif, loading, dan overflow yang terkendali.
- Gunakan format angka yang konsisten dan bedakan Berat Netto/Berat Dibayar serta basis kas/transaksi.
- Uji print/PDF/kwitansi pada ukuran target; angka, logo, status, dan page break tidak boleh terpotong.
- Uji export terhadap filter/sort aktif, tipe angka, header, dan pembatasan role.
- Uji tindakan yang berpotensi ganda dengan loading/disabled state dan idempotency backend.

### 13.4 Bukti UX/UAT

Perubahan UI `KR2+` menyertakan screenshot atau rekaman state utama, viewport yang diuji, role, browser, dan hasil UAT. Screenshot tidak menggantikan acceptance test atau pemeriksaan accessibility.

## 14. Strategi QA dan Test Pyramid

### 14.1 Pyramid

| Lapisan | Fokus | Contoh Sawit CB |
| --- | --- | --- |
| Static | Cepat, dijalankan setiap perubahan | ESLint, build, diff check, secret/diff review |
| Unit | Banyak dan deterministik | Formula berat, fee, Rupiah, role helper, normalisasi nomor |
| Database | Constraint, RLS, function, ledger, idempotency | Migration reset, DB lint, SQL smoke rollback, role matrix |
| Integration | Kontrak UI/client dengan Supabase | Auth/session, query/RPC, error dan pagination |
| E2E | Sedikit, alur bisnis paling kritis | Pengiriman -> kwitansi -> kas; Pinjaman & Panjar; reversal |
| UAT/Exploratory | Kesesuaian kerja nyata dan exception | Batch nota, print, approval Owner, koreksi legacy |

Mayoritas coverage baru ditempatkan pada unit/database; E2E difokuskan pada alur bernilai tinggi agar suite tetap cepat dan dapat dipelihara.

### 14.2 Gate Saat Ini

Perintah minimum untuk perubahan kode:

```powershell
npm ci
npm run lint
npm run build
npm audit --omit=dev
git diff --check
```

Perubahan database menambahkan:

```powershell
npx supabase db push --dry-run --linked
npx supabase db lint --linked --schema public --level error --fail-on error
```

SQL smoke test yang tersedia:

- `supabase/tests/p0_financial_controls_rollback.sql`;
- `supabase/tests/armada_cb_controls_rollback.sql`.

Keduanya hanya dijalankan pada staging/linked database yang dipilih secara eksplisit dan memiliki data uji yang sesuai. Pola `BEGIN ... ROLLBACK` harus tetap dipertahankan. Jangan menjalankannya secara improvisasi pada production.

Smoke test baseline memilih data bisnis yang tersedia secara nondeterministik. Karena itu keduanya belum menjadi fixture deterministik dan tidak boleh menjadi satu-satunya bukti release. Work package finansial harus menambahkan fixture staging terisolasi, negative Data API/RPC test, concurrency/retry/idempotency, formula batas, serta rekonsiliasi ledger/snapshot sesuai scope.

Repository memiliki Node test runner, Playwright staging gate, serta GitHub Actions untuk lint/build/dependency/security/database gate. Automated E2E lintas role dan workflow bisnis secara menyeluruh belum tersedia. Untuk test manual atau scope yang belum terotomasi:

- hasil manual wajib menyimpan raw output dengan `TEST-*`, commit SHA, waktu UTC, environment, executor, role/data, expected, actual, dan reviewer independen;
- ketiadaan pipeline bukan alasan melewati lint/build/test;
- PR tidak boleh menyatakan test otomatis lulus bila test tersebut belum ada;
- penambahan Vitest/Jest, Playwright, dan CI diprioritaskan berdasarkan risiko dan dicatat sebagai work package terpisah.

### 14.3 Kedalaman Test per Risiko

| Risiko | Test minimum |
| --- | --- |
| `KR0` | Diff/link/format review |
| `KR1` | Static gate dan visual/manual test area berubah |
| `KR2` | Static + unit/integration relevan + regression + UX state |
| `KR3` | Semua `KR2` + staging + role negative test + SQL/RPC + rekonsiliasi + UAT |
| `KR4` | Semua `KR3` + rehearsal migration/data fix + backup/restore evidence + observasi dan rollback drill |

### 14.4 Regression Kritis

Pilih skenario sesuai dampak, minimal dari daftar berikut:

- login, session refresh, route guard, dan query langsung per role;
- input Pengiriman Mitra, snapshot tarif/berat, dan duplicate prevention;
- draft/paid Kwitansi Mitra, grouping per mitra, kas keluar, dan print;
- pembayaran pabrik, pencocokan harga/tonase, kas masuk, dan reversal;
- Buku Kas: saldo pembuka, masuk, keluar, akhir, dan referensi reversal;
- Pinjaman & Panjar: pengajuan, approval, penyerahan, pengembalian parsial, potongan, reversal, dan arsip;
- Armada CB: sewa, Dana Operasional Trip, pembayaran satu kali, dan margin;
- data profit tidak dapat dibaca Admin;
- perubahan master tidak mengubah snapshot historis;
- report/export tidak kehilangan data akibat limit/pagination;
- negative input, double click/retry, concurrent operation, dan idempotency.

## 15. Definition of Ready dan Definition of Done

### 15.1 Definition of Ready

Work package boleh berstatus `Ready` bila:

- [ ] ID, tujuan, owner, reviewer, prioritas, severity terkait, dan kelas risiko tersedia.
- [ ] Scope masuk/tidak masuk dan dependency jelas.
- [ ] Requirement/flow/acceptance memiliki ID dan sumber aktif.
- [ ] Istilah, formula, state, role, dan exception material telah diputus.
- [ ] Dampak ke histori, snapshot, ledger, kas, laporan, export, dan role dinilai.
- [ ] Ownership file/modul tidak tumpang tindih.
- [ ] Verification plan dan data/environment test tersedia.
- [ ] Rollout, trigger rollback, dan pemulihan masuk akal.
- [ ] Reviewer domain dan approver tersedia pada target waktu.
- [ ] Tidak ada blocker `P0` yang membuat implementasi tidak aman.

Tambahan `KR3/KR4`:

- [ ] BDR/ADR tersedia bila ada keputusan material.
- [ ] Migration/backfill, RLS/grant/RPC, reconciliation, dan performance plan direview.
- [ ] Staging terpisah, backup, dan hak Release Operator dapat diverifikasi.
- [ ] Positive/negative role matrix dan test idempotency/concurrency didefinisikan.
- [ ] Strategi expand/contract atau kompatibilitas deployment jelas.

### 15.2 Definition of Done: Verified

- [ ] Implementasi memenuhi seluruh `AC-*` yang masuk scope.
- [ ] Review wajib selesai tanpa blocker unresolved.
- [ ] Static, unit, database, integration, E2E, UAT, dan manual test relevan lulus.
- [ ] `TEST-*` memuat expected/actual dan bukti yang dapat ditelusuri.
- [ ] Tidak ada secret, data production, artefak lokal, atau perubahan unrelated di diff.
- [ ] Migration dan kode backward compatible atau urutan rollout telah dibuktikan.
- [ ] Rekonsiliasi uang/data dan negative permission test lulus.
- [ ] Dokumentasi sumber kebenaran diperbarui pada PR yang sama.
- [ ] Risiko tersisa memiliki owner, mitigasi, expiry, dan approval.

### 15.3 Definition of Done: Released

- [ ] Release checklist memiliki keputusan Go.
- [ ] Commit, deployment, migration, operator, waktu, dan target tercatat.
- [ ] Migration history dan DB lint setelah deploy lulus.
- [ ] Smoke test per role dan workflow scope lulus.
- [ ] Rekonsiliasi post-deploy sesuai expected.
- [ ] Observasi log/error selesai tanpa trigger rollback.
- [ ] Catatan perubahan diterima pengguna operasional terkait.
- [ ] Work package, audit finding, dan task ditutup dengan tautan bukti.

Kode selesai tetapi belum terverifikasi/released tidak boleh dilaporkan sebagai fitur production selesai.

## 16. Release, Deploy, dan Rollback

### 16.1 Mandatory Release Gates

Semua gate berikut bersifat blocker dan mengikuti baseline audit security/release terkini:

| Gate | Syarat lulus |
| --- | --- |
| `G0 Scope` | Requirement, kelas risiko, klasifikasi data, owner, separation of duties, dan acceptance tersedia |
| `G1 Code/Supply Chain` | Lint, build, test, SAST/secret scan, dependency audit, dan lockfile integrity lulus |
| `G2 Database/Security` | Clean install + upgrade rehearsal, ACL/RLS/RPC negative matrix, backup, dan restore evidence lulus |
| `G3 Functional QA` | Formula, snapshot, ledger, reversal, retry, concurrency, export/print, desktop/mobile diuji |
| `G4 Release Readiness` | Commit/artifact immutable, urutan deploy kompatibel, monitoring aktif, rollback trigger, dan incident owner jelas |
| `G5 Approval` | Author bukan satu-satunya reviewer; Data/Security dan QA menyetujui perubahan uang/schema/auth |
| `G6 Post-deploy` | Smoke per role, rekonsiliasi saldo/row count, observasi log, dan release record lengkap |

Gate yang belum memiliki otomatisasi tetap wajib dibuktikan manual. Ketiadaan tool atau pipeline tidak mengubah hasil blocker menjadi lulus.

Applicability minimum:

| Gate | KR0 | KR1 | KR2 | KR3 | KR4 |
| --- | --- | --- | --- | --- | --- |
| G0 Scope | Wajib | Wajib | Wajib | Wajib | Wajib |
| G1 Code/Supply Chain | Sesuai artefak | Wajib | Wajib | Wajib | Wajib |
| G2 Database/Security | N/A dengan alasan bila tidak menyentuh runtime/data | N/A dengan alasan | Sesuai dampak | Wajib | Wajib |
| G3 Functional QA | Review dokumen | Manual area berubah | Wajib | Wajib | Wajib |
| G4 Release Readiness | Bila dipromosikan | Wajib | Wajib | Wajib | Wajib |
| G5 Approval | Owner file | Reviewer berbeda bila tersedia | Reviewer independen | Wajib | Wajib |
| G6 Post-deploy | N/A bila tidak dideploy | Wajib bila dideploy | Wajib | Wajib | Wajib |

`N/A` wajib memiliki alasan dan persetujuan QA pada release checklist. `G2` tidak boleh `N/A` untuk baseline P0, auth/RLS/RPC, migration, atau data finansial. `G5` tidak boleh `N/A` untuk `KR3/KR4`.

### 16.2 Persiapan Release

Setiap calon release membuat satu record dari [Release Checklist Template](templates/release-checklist-template.md). Ini menjadi jawaban atas utang dokumentasi `DOC-003`: status release tidak disimpulkan dari checklist historis yang tersebar.

Release scope harus menyebut commit/PR, `BR/TASK/AUD`, migration, environment, owner, waktu, dan risiko. Hindari release `KR3/KR4` menjelang periode operasional kritis atau ketika tim pemulihan tidak tersedia.

### 16.3 Go/No-Go

Keputusan **Go** memerlukan:

- seluruh gate sesuai risiko lulus;
- tidak ada `P0`, `S0`, atau `S1` terkait scope yang belum diselesaikan;
- backup/recovery, rollback, dan observasi tersedia;
- Engineering Lead dan QA/Release menyetujui;
- Product Owner menyetujui perubahan bisnis material;
- Data/Security menyetujui migration, uang, role, RLS, atau koreksi data.

QA/Release atau Data/Security dapat menetapkan **No-Go** bila bukti tidak cukup. Jadwal bukan alasan mengubah hasil gate.

Selama seluruh `P0`, `S0`, atau `S1` terkait scope pada [Audit Security dan Kesiapan Rilis](security-release-audit-2026-07-17.md) belum ditutup, fitur finansial baru tetap **No-Go**. `S1` non-P0 di luar scope hanya dapat mengikuti Exception Record yang sah. Status Go memerlukan negative authorization test, audit-log integrity, maker-checker, dependency gate, migration rehearsal, deterministic test, hosted Auth attestation, dan approval independen yang relevan telah diverifikasi.

### 16.4 Urutan Deploy

1. Freeze scope dan pastikan working tree/release commit bersih serta sudah berada di `main`.
2. Verifikasi target Vercel/Supabase, environment variable, akses operator, backup/PITR, dan jendela release.
3. Jalankan lint, build, diff check, test, migration list, DB lint, dan dry-run terakhir.
4. Untuk perubahan schema, gunakan pola expand/contract. Apply migration additive yang kompatibel sebelum aplikasi bergantung padanya.
5. Jika merge ke `main` otomatis memicu Vercel, pecah release menjadi migration expand dan aplikasi kompatibel atau gunakan mekanisme promotion agar urutan aman.
6. Satu Release Operator menjalankan migration dan mencatat output.
7. Verifikasi migration list dan DB lint setelah push.
8. Deploy/promote aplikasi dan catat commit/deployment ID.
9. Jalankan smoke test role/workflow, query rekonsiliasi, serta pemeriksaan log.
10. Observasi minimal 30 menit untuk `KR3` dan sesuai rehearsal untuk `KR4`; perpanjang bila volume transaksi belum representatif.
11. Nyatakan Released atau aktifkan rollback/incident flow.

### 16.5 Strategi Rollback

Rollback plan harus membedakan:

- **Aplikasi:** promote deployment Vercel stabil sebelumnya atau deploy commit revert yang telah diverifikasi.
- **Database schema:** utamakan forward-fix additive. Jangan mengedit migration applied atau menjalankan down SQL destruktif secara spontan.
- **RLS/grant/RPC:** gunakan migration koreksi/revoke yang telah disiapkan dan test akses ulang.
- **Data finansial:** gunakan reversal/transaksi pembalik, bukan delete/update histori.
- **Backfill:** hentikan batch, identifikasi checkpoint, rekonsiliasi, lalu lanjutkan atau forward-fix secara idempotent.
- **Restore:** tindakan terakhir dengan downtime terencana, recovery point, dan rekonsiliasi data/Storage setelah restore.

Trigger rollback harus terukur, misalnya:

- login/route utama gagal untuk role target;
- migration atau deploy tidak selesai konsisten;
- mismatch kas, kwitansi, snapshot, ledger, atau row count;
- akses tidak sah berhasil atau akses sah terblokir luas;
- error rate/latency melampaui baseline yang disepakati;
- operasi ganda/idempotency gagal.

Setelah rollback, jangan langsung mencoba deploy ulang. Buka incident/work item, pahami state aktual, dan buat rencana koreksi baru.

### 16.6 Hotfix

Hotfix memakai branch `hotfix/*`, scope minimum, dan incident/change record. Gate yang dapat dipercepat hanyalah format pertemuan, bukan test integritas, backup, reviewer finansial/security, atau rekonsiliasi. Retrospective review dan dokumentasi lengkap wajib maksimal satu hari kerja setelah stabil.

## 17. Incident Management

### 17.1 Aktivasi

Incident flow aktif untuk:

- kehilangan, korupsi, duplikasi, atau mismatch data/uang;
- akses tidak sah, secret exposure, atau role/RLS bypass;
- workflow utama production tidak dapat dipakai;
- salah hitung/status yang berisiko salah bayar;
- migration/deployment gagal dan meninggalkan state tidak pasti;
- insiden `S2` yang berulang atau meluas.

Engineering Lead menjadi Incident Commander (IC) atau menunjuk pengganti. IC mengatur prioritas, akses, komunikasi, dan keputusan containment. Implementer/DS menjadi responder, QA menjaga bukti/recovery, PO mengatur dampak bisnis, dan REL menjalankan perubahan production.

Gunakan [Incident Record Template](templates/incident-record-template.md). Sebelum rilis `KR3/KR4`, daftar IC utama/cadangan, secure channel, contact tree, jam dukungan, RPO/RTO, dan lokasi evidence harus diisi tanpa menaruh secret pada dokumen.

### 17.2 Tahapan

1. **Detect dan acknowledge:** buat incident record, severity, waktu, reporter, dan area terdampak.
2. **Contain:** hentikan deploy, batasi aksi/role/fitur yang berbahaya, revoke secret bila perlu, dan lindungi bukti.
3. **Assess:** identifikasi rentang waktu, role, tabel, record, nominal, deployment, dan kemungkinan dampak turunan.
4. **Communicate:** beri update singkat berbasis fakta. Target update `S0` setiap 30 menit dan `S1` setiap 60 menit sampai stabil.
5. **Recover:** pilih rollback, forward-fix, reversal, restore, atau prosedur manual aman dengan approval.
6. **Verify:** role test, smoke, rekonsiliasi data/uang, log, dan konfirmasi pengguna.
7. **Close:** catat timeline, root/contributing factors, dampak aktual, dan follow-up owner.

### 17.3 Aturan Finansial dan Security

- Jangan menghapus atau menulis ulang transaksi untuk menyembunyikan dampak.
- Bekukan aksi yang dapat memperbesar mismatch, tetapi pertahankan akses read-only bila aman untuk operasi.
- Simpan daftar ID/nominal terdampak secara akses terbatas dan sanitasikan laporan umum.
- Secret exposure memicu revoke/rotate, pemeriksaan log, session review, dan security follow-up.
- Dugaan kebocoran data tidak dibagikan ke channel umum; ikuti jalur komunikasi terbatas.

### 17.4 Postmortem

Postmortem blameless wajib untuk `S0`/`S1` maksimal dua hari kerja setelah stabil. Isinya:

- ringkasan dan dampak bisnis/data;
- timeline deteksi sampai pulih;
- akar masalah dan faktor sistemik;
- kontrol yang bekerja/gagal;
- tindakan korektif dengan `TASK-*`, owner, prioritas, dan target;
- update test, monitoring, runbook, SOP, PRD/ADR bila perlu.

Temuan tidak ditutup hanya karena service kembali online. Data dan uang harus direkonsiliasi.

## 18. Tata Kelola Dokumentasi

### 18.1 Pemicu Pembaruan

| Perubahan | Dokumen yang diperbarui pada PR yang sama |
| --- | --- |
| Setup, command, entry point | `README.md` |
| Scope, formula, role, istilah, acceptance bisnis | `PRD-final.md` atau BDR |
| Urutan, dependency, release scope | `implementation_plan.md` |
| Status task dan evidence | Work package / `IMPLEMENTATION-TASKS.md` |
| Stack, arsitektur, schema, security, deployment | `technical-specification.md` atau ADR |
| Temuan audit | Register audit domain dan traceability |
| Proses/gate/ownership | `development-sop.md` |

### 18.2 Aturan

- Dokumen aktif tidak boleh menyalin seluruh isi sumber lain. Gunakan tautan dan ringkasan konteks.
- Addendum/keputusan terbaru harus menyatakan apa yang digantikan.
- Dokumen historis tidak menerima requirement atau temuan baru.
- Checklist `[x]` memerlukan commit/migration/test/release evidence.
- BDR disimpan pada `docs/decisions/business/`; ADR pada `docs/decisions/architecture/`.
- Keputusan pengganti membuat record baru dan menandai record lama `Superseded`.
- Setiap release meninjau manifest dokumentasi dan link yang berubah.
- Jangan mencantumkan secret, credential, dump, atau PII yang tidak diperlukan. ID production hanya dicatat pada record akses terbatas bila dibutuhkan untuk rekonsiliasi.
- Gunakan Bahasa Indonesia profesional untuk proses/bisnis dan nama teknis exact untuk kode/schema.
- Retensi, legal hold, integritas, akses, dan disposal evidence mengikuti [Kebijakan Retensi Bukti](evidence-retention-policy.md). Selama policy masih Draft, ketidakadaan jadwal yang disetujui tetap menjadi gap release/resilience.

### 18.3 Review Governance

- Mingguan: triage audit finding, Accepted Risk, blocker, dan utang dokumentasi.
- Per release: cek sumber kebenaran, status task, evidence, dan release record.
- Triwulanan: baseline ulang PRD, flow, UX/UI, technical/data/security, SOP, dan archive dokumen transisi.
- Setelah insiden/perubahan besar: perbarui dokumen terkait sebelum follow-up dinyatakan selesai.

## 19. Cadence Tim Kecil

Cadence boleh digabung dalam satu pertemuan bila orangnya sama, tetapi outputnya tetap dicatat.

| Waktu | Kegiatan | Output |
| --- | --- | --- |
| Harian, async/10 menit | Status, blocker, incident, rencana hari ini | WIP dan blocker terlihat |
| Mingguan, 45 menit | Intake, severity/priority, replenishment Discovery/Delivery | Backlog terurut dan work package owner |
| Mingguan, 30 menit | Risk/data/security/doc review | Keputusan gate dan follow-up |
| Per PR | Review domain dan test evidence | Approval atau perubahan diminta |
| Dua mingguan | Demo/UAT dan retrospective | Feedback, keputusan, perbaikan proses |
| Per release | Go/no-go dan release review | Release checklist serta outcome |
| Bulanan | KPI, incident trend, advisors, migration drift, rekonsiliasi | Action item terukur |
| Triwulanan | Restore drill, access review, SOP/doc baseline | Bukti pemulihan dan revisi governance |

## 20. KPI dan Health Metrics

KPI dipakai untuk melihat kesehatan sistem delivery, bukan menilai individu. Baseline empat minggu pertama digunakan untuk menyesuaikan target yang tidak berbasis compliance.

| KPI | Definisi | Target awal |
| --- | --- | --- |
| Release gate compliance | Release dengan checklist dan approver lengkap | 100% |
| Traceability `KR3/KR4` | Perubahan dengan requirement/task/test/PR/release link lengkap | 100% |
| Migration drift | Perbedaan migration Git vs target yang tidak dijelaskan | 0 |
| Financial/data reconciliation | Mismatch kas, ledger, snapshot, atau row count setelah release | 0 |
| Escaped `S0/S1` | Insiden kritis/tinggi akibat perubahan yang lolos release | 0; setiap kejadian wajib postmortem |
| Change failure rate | Release yang rollback, hotfix, atau menimbulkan `S0/S1` dalam 7 hari | < 15% rolling 8 release, lalu perbaiki gate bila terlampaui |
| PR first-review time | Waktu Ready for Review sampai review pertama | Median <= 1 hari kerja |
| Aging WIP | Item `In Progress` tanpa bukti kemajuan > 5 hari kerja | 100% ditinjau/dipecah/escalate |
| Incident response | Acknowledge sesuai target severity | >= 95%; `S0` 100% |
| Restore readiness | Drill restore dan bukti rekonsiliasi | 1 kali per kuartal, lulus 100% |
| Documentation freshness | Sumber kebenaran terdampak diperbarui dalam release yang sama | 100% |
| Automation coverage | Alur/formula risiko tinggi yang memiliki test repeatable | Tren naik per rilis; tidak turun tanpa keputusan |

Metric delivery pendukung: lead time, cycle time, throughput, blocked time, reopen rate, defect escape, MTTR, dan UAT pass rate. Angka dibaca bersama ukuran perubahan dan risiko; kecepatan tidak boleh dicapai dengan memecah defect atau melewati gate.

## 21. Baseline dan Asumsi

SOP ini disusun dari baseline repository 17 Juli 2026:

- aplikasi internal Next.js 16.2.11, React 19.2.4, JavaScript/JSX, Supabase JS 2.110.2, `@supabase/ssr` 0.12.0, dan Supabase CLI 2.109.1;
- `npm` dengan `package-lock.json`; `dev` adalah branch integrasi dan `main` adalah branch production/rilis;
- Vercel dan Supabase hosted adalah target deployment menurut spesifikasi teknis;
- model database memakai 54 imperative migration dan dua SQL smoke test rollback;
- PostgreSQL lokal major 17; Data API mengekspos `public`/`graphql_public` dengan limit lokal 1.000 row;
- repository memiliki required CI, Node test runner, dan Playwright staging gate; automated E2E menyeluruh dan observability khusus belum tersedia;
- `supabase/seed.sql` belum ada walaupun seeding aktif pada konfigurasi lokal;
- audit security/release 17 Juli 2026 berstatus NO-GO untuk fitur finansial baru dan memiliki temuan `P0`/`S0-S1` Open; status tersebut hanya berubah melalui bukti verifikasi dan release checklist baru;
- dua SQL smoke test rollback saat ini memakai pemilihan data yang nondeterministik dan hanya boleh menjadi bukti tambahan di staging;
- keberadaan dan kesetaraan project staging, tier backup/PITR production, branch protection, serta promotion Vercel harus diverifikasi dan tidak diasumsikan;
- role organisasi boleh dirangkap, tetapi cross-review finansial/security tetap wajib;
- target respons insiden berlaku pada jam dukungan yang disepakati. Baseline ini tidak menyatakan layanan 24/7;
- perubahan production dan penggunaan credential selalu memerlukan manusia yang berwenang.

Jika baseline teknis atau organisasi berubah, Engineering Lead memperbarui SOP dan manifest dokumentasi melalui PR terpisah atau PR perubahan terkait.

## 22. Pengecualian dan Kepatuhan

Penyimpangan dari SOP harus dicatat sebagai exception/Accepted Risk dengan:

- aturan yang tidak dapat dipenuhi dan alasan;
- dampak, severity, kelas risiko, dan scope waktu;
- mitigasi sementara dan trigger penghentian;
- owner risiko, approver Product Owner/Engineering Lead, dan expiry;
- task untuk menghapus exception.

Gunakan [Exception Record Template](templates/exception-record-template.md). Hanya `S1` non-P0 yang dapat dipertimbangkan dan perubahan scope/commit membatalkan persetujuan exception.

Exception tidak boleh digunakan untuk melegalkan secret di repo, hard delete histori finansial, bypass RLS tanpa kontrol, deployment dengan target tidak terverifikasi, atau klaim test yang tidak dijalankan.

Tidak ada exception untuk temuan `S0`, akses data lintas role yang tidak sah, audit trail yang dapat dimutasi client, kegagalan restore, atau migration/backfill production yang belum direhearsal. Exception `S1` memerlukan persetujuan Product Owner, Data/Security, dan QA, mitigasi aktif, serta tanggal kedaluwarsa.

Anti-pattern permanen yang dilarang:

- memperlakukan dry-run atau DB lint sebagai upgrade rehearsal;
- menjalankan `db push` dari dirty tree, migration untracked, commit yang belum direview, atau target linked yang belum dibuktikan;
- menjalankan `db reset --linked` atau reset melalui production URL;
- memakai service-role script ad hoc untuk direct production write;
- menghitung beberapa topi peran satu orang sebagai approval independen;
- restore langsung menimpa production sebelum drill terisolasi dan keputusan incident;
- checklist `[x]` tanpa raw evidence yang dapat direproduksi.

## 23. Rujukan

Rujukan internal utama:

- [README](../README.md)
- [PRD Final](../PRD-final.md)
- [Implementation Plan](../implementation_plan.md)
- [Implementation Tasks](../IMPLEMENTATION-TASKS.md)
- [Spesifikasi Teknis](technical-specification.md)
- [Audit Flow Bisnis](page-flow-control-audit-2026-07-16.md)
- [Tata Kelola Audit](audit-governance.md)
- [Indeks Dokumentasi](documentation-index.md)
- [Protokol Panel Spesialis](ai-specialist-collaboration.md)
- [Audit Security dan Kesiapan Rilis](security-release-audit-2026-07-17.md)
- [Audit UX/UI Seluruh Aplikasi](ux-ui-audit.md)

Rujukan Supabase yang harus diperiksa ulang sebelum perubahan sensitif:

- [Database migrations](https://supabase.com/docs/guides/deployment/database-migrations)
- [Supabase CLI db push](https://supabase.com/docs/reference/cli/supabase-db-push)
- [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Database backups](https://supabase.com/docs/guides/platform/backups)
- [Perubahan explicit Data API grants](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
