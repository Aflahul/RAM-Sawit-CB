# Audit UX/UI Seluruh Aplikasi Sawit CB

| Metadata | Nilai |
| --- | --- |
| Status dokumen | In Review; persetujuan Product Owner dan bukti runtime masih diperlukan |
| Tanggal audit | 17 Juli 2026 |
| Baseline kode | Branch main, commit 31a52ba |
| Auditor | UX Research Lead dan UI Design System Auditor |
| Pemilik | UX/UI Reviewer |
| Approver | Product Owner |
| Tinjau berikutnya | Sebelum rilis berikutnya atau paling lambat 31 Juli 2026 |
| Tata kelola | [Tata Kelola Audit](audit-governance.md), [SOP Pengembangan dan Delivery](development-sop.md), dan [Indeks Dokumentasi](documentation-index.md) |

## 1. Ringkasan Eksekutif

Sawit CB sudah memiliki fondasi produk operasional yang kuat: shell aplikasi konsisten, role dan route guard tersedia, istilah finansial utama makin jelas, reversal dan alasan koreksi sudah masuk flow, serta halaman Pengiriman Mitra telah menindaklanjuti pain point input batch pada audit sebelumnya. Sistem desain juga mempunyai token warna, tipografi, spacing, tabel, badge, form, dan pola cetak yang cukup jelas.

Risiko UX/UI tertinggi saat baseline ini adalah:

1. Empat route berstatus Coming Soon hanya ditutup overlay dan pointer-events. Child page tetap dirender dan kontrol di bawah overlay belum terbukti terkunci dari keyboard. Risiko mount/query/write menjadi finding primer `AUD-SEC-20260717-005`; audit UX/UI ini menangani focus, keyboard, inert, dan komunikasi status.
2. Baseline aksesibilitas belum merata: zoom viewport dibatasi, dialog belum memiliki semantik/focus management lengkap, sebagian besar label form tidak terasosiasi secara programatik, toast tidak diumumkan ke assistive technology, dan tidak ada reduced-motion mode.
3. Tipografi mobile diperkecil secara global menjadi 13px lalu 12px. Beberapa grid inline 3-4 kolom dapat mengalahkan media query satu kolom. Keduanya berisiko pada keterbacaan dan layout tugas keuangan.
4. UI konsisten pada warna dan shell, tetapi belum pada perilaku komponen. Modal, toast, field, table action, dan responsive style masih banyak dibuat per halaman.
5. Bahasa antarmuka dominan Bahasa Indonesia, tetapi masih bercampur dengan Coming Soon, Legacy, Invoice, pending review, raw database error, dan singkatan TBS/TWB yang belum memiliki glosarium tampilan.

Audit ini tidak membuka kembali temuan flow bisnis yang sudah dinyatakan selesai. Makna angka, role, snapshot, ledger, reversal, dan status pembayaran tetap mengikuti [baseline audit flow bisnis](page-flow-control-audit-2026-07-16.md). Dokumen ini menilai apakah makna tersebut dapat ditemukan, dipahami, dan dioperasikan secara jelas, cepat, konsisten, accessible, responsive, dan print-safe.

Audit UX/UI ini juga tidak mengubah keputusan **NO-GO untuk rilis fitur finansial baru** pada [Audit Security dan Kesiapan Rilis 17 Juli 2026](security-release-audit-2026-07-17.md). Temuan security, data, dan QA tetap dikelola pada register sumbernya; temuan UX/UI P0 di dokumen ini adalah gate pendamping, bukan pengganti gate rilis aktif.

## 2. Tujuan dan Scope

### 2.1 Tujuan

- Menetapkan baseline UX/UI lintas seluruh route aplikasi.
- Mengukur apakah Admin, Owner, Super Admin, dan Admin Keuangan dapat menyelesaikan tugas sesuai kewenangannya.
- Memeriksa UI sebagai bagian dari UX, bukan sekadar kosmetik terpisah.
- Menemukan pola lintas halaman yang meningkatkan beban kognitif, risiko salah input, atau hambatan akses.
- Membuat register temuan dan backlog yang dapat ditelusuri ke route, komponen, task, test, dan release evidence.

### 2.2 Scope masuk

- Seluruh 25 route page yang ditemukan di app, terdiri dari 17 layar interaktif aktif, 1 route arsip read-only, 4 route dikunci Coming Soon, dan 3 route utilitas/redirect.
- Navigasi, role-aware visibility, page title, task flow, form, validation feedback, error/recovery, modal, tabel, filter, sort, pagination, export, responsive, print, dan content language.
- Design system intent pada .stitch/DESIGN.md dan implementasi aktual pada app/globals.css.
- Komponen layout, branding, transaksi, dan UI bersama pada components.
- Temuan historis Input Timbangan sebagai pembanding sebelum/sesudah.

### 2.3 Scope tidak masuk

- Audit ulang formula finansial, RLS, migration, ledger, snapshot, atau data produksi.
- Penetration test, audit performa jaringan, dan observability backend.
- Uji browser, screen reader, perangkat fisik, atau usability test dengan pengguna nyata pada sesi ini.
- Perubahan desain atau kode. Audit ini hanya menghasilkan dokumen.

Konsekuensinya, fakta source code ditandai sebagai bukti langsung. Risiko perilaku browser yang belum dijalankan ditandai sebagai inferensi statis dan wajib mendapat bukti test sebelum status Verified.

## 3. UX dan UI

| Aspek | UX | UI |
| --- | --- | --- |
| Pertanyaan | Apakah pengguna dapat menyelesaikan tujuan dengan benar, cepat, dan yakin? | Apakah informasi dan kontrol tampil konsisten, terbaca, dan memiliki affordance yang tepat? |
| Objek audit | Task flow, urutan kerja, role, feedback, error prevention, recovery, beban kognitif | Token, hierarchy, typography, color, spacing, icon, field, table, modal, responsive, print |
| Contoh Sawit CB | Memilih armada dahulu lalu mitra terisi; tanggal batch tetap; reversal meminta alasan | Searchable combobox, badge status, mono number, tombol danger, kwitansi putih saat print |
| Risiko bila dipisah | Flow benar dapat tetap sulit dipakai jika label, fokus, atau hierarchy buruk | Tampilan rapi dapat tetap menyebabkan salah bayar jika urutan dan makna status salah |

Keputusan tata kelola: UI adalah lapisan yang membuat UX dapat dipahami dan dioperasikan. Karena itu temuan visual, component consistency, responsive, print, dan accessibility berada di register UX/UI ini. Jika sebuah temuan mengubah arti angka atau state bisnis, temuan pendamping harus dibuat pada audit flow, bukan diduplikasi di sini.

## 4. Sumber, Metode, dan Batas Bukti

### 4.1 Sumber aktif

1. [Tata Kelola Audit](audit-governance.md), sumber taxonomy, severity, status, ownership, dan traceability.
2. [Indeks Dokumentasi](documentation-index.md), sumber status dan hierarki dokumen.
3. [Audit Flow Bisnis dan Kontrol](page-flow-control-audit-2026-07-16.md), baseline aktif untuk proses, angka, role, dan kontrol.
4. [SOP Pengembangan dan Delivery](development-sop.md), sumber proses delivery, kelas risiko perubahan, quality gate, dan release gate aktif.
5. [Audit Security dan Kesiapan Rilis 17 Juli 2026](security-release-audit-2026-07-17.md), sumber keputusan NO-GO terkini; temuan lintas domain tidak diduplikasi ke register UX/UI.
6. app routes, proxy.js, lib/roles.js, app/globals.css, dan components, bukti executable kondisi UI saat audit.

### 4.2 Sumber referensi/historis

1. [Arsip Audit UX Input Timbangan](archive/audit-ux-input-timbangan-legacy.md), pain point input batch yang dibandingkan dengan implementasi sekarang.
2. `.stitch/DESIGN.md`, referensi visual lokal yang tidak dilacak Git. Sesuai indeks dokumentasi, keputusan aktif harus tercermin di audit ini atau komponen aplikasi.
3. [Audit Konten Halaman](page-content-audit.md) dan [Rencana UX Flow Bisnis](business-flow-ux-plan.md), konteks historis keputusan navigasi dan roadmap; tidak dipakai sendirian untuk menyimpulkan kondisi sekarang.

### 4.3 Metode

1. Route inventory terhadap seluruh app/**/page.js.
2. Task-flow mapping untuk Pengiriman Mitra, Kwitansi Mitra, Pembayaran Pabrik, Buku Kas, Pinjaman/Panjar, Biaya, master data, dan laporan.
3. Role and navigation review terhadap proxy.js, lib/roles.js, Sidebar, BottomNav, Header, dan AppShell.
4. Heuristic review menggunakan 10 prinsip usability, ditambah error prevention untuk data finansial.
5. Static accessibility review berbasis WCAG 2.2 AA: perceivable, operable, understandable, dan robust.
6. Design-system comparison antara intent .stitch/DESIGN.md, token app/globals.css, dan pemakaian komponen/page.
7. Content review untuk terminologi, action label, status, error, empty state, angka, tanggal, dan singkatan.
8. Responsive/print source review terhadap breakpoint, inline layout, horizontal table, CSS print, dan dokumen transaksi.
9. Cross-check terhadap tindak lanjut implementasi pada audit flow terbaru.

### 4.4 Kode bukti

| Tag | Arti |
| --- | --- |
| CODE | Fakta langsung pada source code dengan file dan line baseline |
| DOC | Keputusan atau temuan pada sumber dokumentasi aktif/referensi |
| COUNT | Inventaris statis yang dapat direproduksi dari source |
| CALC | Perhitungan token, misalnya contrast ratio |
| INFERENCE | Dampak yang logis dari source tetapi masih membutuhkan runtime test |
| TEST | Bukti browser, role, assistive technology, print, atau usability test |

Inventaris statis baseline:

- COUNT-ROUTE-01: 25 page route.
- COUNT-A11Y-01: 24 elemen table, 0 caption, 125 label, dan 2 pemakaian htmlFor pada page files. Sebagian label membungkus kontrol, sehingga angka ini adalah indikator audit, bukan klaim bahwa seluruh 123 label lain pasti gagal.
- COUNT-STYLE-01: 502 pemakaian inline style pada page files. Ini indikator fragmentasi dan risiko override responsive, bukan defect per pemakaian.
- TEST-PLAN-UX-001: runtime browser, role, keyboard, screen reader, dan print belum dijalankan pada audit statis ini.

## 5. Format Temuan

ID mengikuti pola AUD-UX-YYYYMMDD-NNN. Severity dan status tidak dimasukkan ke ID.

### 5.1 Severity

| Severity | Definisi yang dipakai |
| --- | --- |
| S0 Kritis | Potensi kehilangan/korupsi data atau uang, kebocoran akses, atau sistem utama tidak dapat dipakai |
| S1 Tinggi | Workflow utama terhenti, status/perhitungan salah, atau ada risiko salah bayar nyata |
| S2 Sedang | Tugas masih dapat selesai tetapi membingungkan, lambat, tidak konsisten, inaccessible bagi sebagian pengguna, atau rawan salah |
| S3 Rendah | Perapian/polish lokal tanpa dampak material |

Prioritas backlog memakai P0-P3 dan tidak menggantikan severity.

### 5.2 Status

| Status | Aturan |
| --- | --- |
| Open | Temuan diterima untuk triage tetapi belum memiliki komitmen implementasi |
| Planned | Sudah masuk work package/task dengan owner dan target |
| In Progress | Implementasi sedang berjalan |
| Blocked | Tidak dapat maju tanpa keputusan atau dependency |
| Verified | Sudah diuji pada role, data, viewport, dan evidence yang relevan |
| Accepted Risk | Risiko diterima dengan alasan, owner, mitigasi, dan tanggal tinjau |

Semua temuan pada baseline ini berstatus Open. Backlog dan owner di bawah adalah usulan audit, belum menjadi komitmen sampai Product Owner/Engineering Lead memindahkannya ke task list aktif.

## 6. Heuristic Review

| Heuristic | Penilaian | Bukti positif | Gap utama |
| --- | --- | --- | --- |
| Visibility of system status | Parsial kuat | Loading, skeleton, badge, toast, status bayar, dan pending queue tersedia | Toast/status dinamis tidak memakai live region; access denial berpotensi tanpa penjelasan |
| Match with real world | Kuat | Pengiriman, berat, potongan, kwitansi, kas, panjar, sewa, dan Dana Trip mengikuti pekerjaan RAM | Campuran TBS/TWB dan istilah Inggris/internal belum dikendalikan glosarium |
| User control and freedom | Kuat | Batal/reversal, alasan wajib, filter reset, dan jalur kembali tersedia | Dialog/drawer belum mengelola fokus secara konsisten |
| Consistency and standards | Parsial | Shell, token, button class, badge, table, number format, dan Lucide cukup konsisten | Modal, toast, field association, inline layout, dan icon legacy masih beragam |
| Error prevention | Kuat pada flow, parsial pada UI | Lock transaksi dibayar, review, validasi berat, duplicate plate check, confirm/reason | Coming Soon belum menjadi feature gate nyata; raw backend error tidak memberi recovery yang stabil |
| Recognition over recall | Kuat | Menu berkelompok, combobox mencari plat/nama/mitra, status memakai teks | Route nonaktif tetap menonjol dan user harus mengingat arti singkatan/status tertentu |
| Flexibility and efficiency | Kuat | Search, sort, pagination, export, quick add armada, tanggal batch dipertahankan | Belum ada bukti end-to-end keyboard flow dan benchmark waktu tugas |
| Aesthetic and minimalist design | Parsial | Hierarki dark operational dashboard jelas | Hover scale/glow dan card radius besar masih dominan pada work surface padat |
| Error recovery | Kuat pada data, parsial pada komunikasi | Reversal dan audit reason tersedia | Pesan error sering meneruskan error.message; denial redirect tidak tampak dikonsumsi Dashboard |
| Help and documentation | Parsial | Hint, empty state, info alert, preview kalkulasi/cetak tersedia | Belum ada glossary/status help dan copy untuk langkah pemulihan yang konsisten |

## 7. Accessibility Review

Target rekomendasi adalah WCAG 2.2 AA untuk route aktif dan dokumen cetak yang menjadi bukti transaksi.

### 7.1 Kekuatan

- Root document memakai lang="id" pada app/layout.js:17.
- Input login mengasosiasikan label dengan email dan password pada app/login/page.js:64 dan app/login/page.js:95.
- SearchableCombobox memiliki role combobox/listbox/option, aria-expanded, aria-selected, Arrow Up/Down, Enter, Escape, dan pengembalian fokus pada components/ui/SearchableCombobox.js:108-226.
- SortableHeader memakai aria-sort dan label teks pada components/ui/SortableHeader.js:3-19.
- Badge status pada flow kritis umumnya memakai teks, bukan warna saja.
- Form input memiliki focus ring hijau pada app/globals.css:747-763.

### 7.2 Perceivable

- Text primary dan secondary memiliki contrast yang baik pada surface gelap.
- CALC-CONTRAST-01 menunjukkan text-tertiary #64748B hanya 4.24:1 pada body #020617 dan 3.91:1 pada card #0E1223, padahal sering dipakai pada ukuran kecil.
- White text pada endpoint primary #3BAB71 adalah 2.90:1; white text pada danger #E74C3C adalah 3.82:1. Keduanya berada di bawah 4.5:1 untuk normal text. Referensi implementasi: app/globals.css:625-678.
- Tabel kompleks belum mempunyai pola accessible name/caption. Context heading membantu, tetapi ledger dan report harus memiliki nama programatik konsisten.

### 7.3 Operable

- maximumScale: 1 pada app/layout.js:9-13 membatasi pinch zoom.
- Modal bersama menangani Escape dan body scroll, tetapi belum memiliki role dialog, aria-modal, aria-labelledby, focus trap, initial focus yang konsisten, atau focus return. ConfirmDialog dan PromptDialog juga belum memakai semantik dialog lengkap.
- Drawer Sidebar ditampilkan sebagai aside dengan overlay klik, tetapi tidak memiliki Escape handling, focus trap, inert pada konten utama, atau pengembalian fokus ke tombol menu.
- AppShell dan global CSS menjalankan motion/transitions tanpa prefers-reduced-motion fallback.
- Active navigation belum memakai aria-current="page"; nav mobile juga belum mempunyai accessible label.

### 7.4 Understandable

- Mayoritas field memiliki visible label, tetapi asosiasi label-control belum distandarkan dengan id/htmlFor atau wrapping.
- Error dinamis dan toast belum memakai role alert/status atau aria-live.
- Raw backend error berpotensi berbahasa teknis/Inggris dan tidak selalu memberi tindakan pemulihan.
- Istilah internal dan singkatan belum mempunyai satu kamus tampilan.

### 7.5 Robust

- Semantic main sudah dipakai melalui motion.main.
- Komponen combobox/sort merupakan pola baik yang perlu dipertahankan.
- Dialog, table naming, field error relationship, navigation state, dan live feedback perlu distandarkan sebagai shared primitive.

### 7.6 Test wajib sebelum Verified

1. Keyboard-only: login, tambah pengiriman, bayar kwitansi, catat pembayaran pabrik, reversal kas, dan pengajuan/penyerahan pinjaman.
2. Screen reader: NVDA + Chrome/Edge pada Windows untuk dialog, combobox, error, status, dan table.
3. Zoom 200% dan 400% tanpa clipping atau kehilangan fungsi.
4. Contrast check untuk default, hover, focus, disabled, success, warning, danger, dan print.
5. Reduced motion dan high-contrast/forced-colors smoke test.

## 8. Content Language

### 8.1 Prinsip

- Gunakan Bahasa Indonesia sebagai default. Istilah bisnis yang memang dipakai lapangan boleh dipertahankan setelah disetujui Product Owner.
- CTA memakai kata kerja + objek: Tambah Pengiriman, Tandai Dibayar, Batalkan Pembayaran, Cetak Kwitansi.
- Status memakai bentuk kondisi: Belum Dibayar, Sudah Dibayar, Perlu Diperiksa, Dibatalkan.
- Error menjelaskan apa yang gagal, apa yang tetap aman, dan tindakan berikutnya. Detail teknis dicatat untuk log, bukan ditampilkan mentah.
- Gunakan sentence case untuk heading, label, status, dan tombol kecuali nama dokumen resmi.
- Angka uang, kg, tanggal, dan waktu memakai helper terpusat serta rata kanan/mono pada tabel.

### 8.2 Kamus tampilan yang diusulkan

| Saat ini | Target | Catatan |
| --- | --- | --- |
| Coming Soon / comingsoon | Belum tersedia | Tampilkan hanya jika route sengaja tetap terlihat |
| Legacy | Arsip lama | Istilah internal tidak perlu muncul ke user |
| Invoice | Kwitansi | Produk sudah memakai Kwitansi Pembayaran TBS |
| pending review / review | perlu diperiksa / pemeriksaan | Pertahankan nilai status database, ubah display label |
| Toggle menu | Buka menu / Tutup menu | Label dinamis sesuai state |
| Dashboard & Cetak Invoice Mitra | Siapkan, bayar, dan cetak kwitansi mitra | Jelaskan tugas, bukan jenis layout |
| TWB dan TBS | Validasi dengan Product Owner | TBS jelas untuk komoditas; TWB harus didefinisikan bila memang istilah harga/timbang berbeda |
| error.message mentah | Pesan terpetakan + kode referensi | Detail teknis masuk log |

### 8.3 Content rules untuk state

- Loading: sebut objek yang dimuat.
- Empty: sebut kondisi dan satu tindakan yang relevan.
- Success: sebut objek, nilai penting, dan state baru.
- Warning: sebut konsekuensi bila dilanjutkan.
- Destructive confirm: sebut objek, dampak, alasan, dan cara pemulihan/reversal.
- Permission denied: sebut bahwa akses ditolak, alasan role secara aman, dan route kembali.

## 9. Responsive dan Print

### 9.1 Baseline layout

| Rentang | Implementasi saat ini | Audit |
| --- | --- | --- |
| Desktop | Sidebar 260px, sticky header 64px, content max 1200px | Struktur stabil dan sesuai dashboard operasional |
| <= 768px | Sidebar menjadi drawer, bottom nav tampil, page padding mengecil | Pola tepat; drawer semantics/focus perlu diperbaiki |
| <= 600px | form-grid menjadi satu kolom | Baik untuk form utama |
| <= 480px | Root font-size menjadi 12px | Terlalu kecil untuk repeated operational work |

Risiko responsive:

- app/globals.css:1643-1688 mengubah root font 16px menjadi 13px dan 12px. Karena token body/button berbasis rem, text-sm menjadi sekitar 10.6px pada <=768px dan 9.75px pada <=480px.
- Inline grid pada app/keuangan/hutang/page.js:383 dan app/laporan/laba-rugi/page.js:203 dapat mengalahkan media query .stats-grid satu kolom.
- Toolbar kwitansi memakai minmax(260px, 1fr) auto auto pada app/owner/kwitansi-mitra/page.js:676 dan perlu viewport test.
- Tabel memakai horizontal overflow sebagai fallback. Primary action dan status tidak boleh hanya tersedia di kolom paling kanan tanpa mobile alternative.

Viewport minimum untuk regression:

| Kelas | Viewport |
| --- | --- |
| Small Android | 360 x 800 |
| Common mobile | 390 x 844 |
| Tablet portrait | 768 x 1024 |
| Tablet/desktop compact | 1024 x 768 |
| Laptop | 1366 x 768 |
| Desktop | 1440 x 900 |
| Accessibility | 200% dan 400% zoom |

### 9.2 Print inventory

| Output | Route | Format target | Status source |
| --- | --- | --- | --- |
| Kwitansi Pembayaran TBS | /owner/kwitansi-mitra | A4/PDF | Print area, paid/draft stamp, logo, detail dan total tersedia |
| Laporan Mitra | /owner/laporan-mitra | A4 landscape bila tabel lebar | Print-specific style tersedia |
| Pendapatan Owner | /owner/pendapatan-owner | A4 | Print area tersedia |
| Bukti pemberian/pengembalian pinjaman | /keuangan/hutang | A4 | Print document dan signature block tersedia |
| Struk pembelian lokal | /transaksi/beli | Thermal 80mm | Tersedia tetapi route masih Coming Soon |

Global print CSS pada app/globals.css:1411-1424 menyembunyikan body dan hanya menampilkan .struk-thermal. Beberapa page kemudian menimpa aturan itu dengan style lokal untuk .print-area. Pola ini dapat bekerja karena cascade/specificity, tetapi rapuh dan belum mempunyai satu regression matrix.

Print acceptance:

1. Tidak ada toolbar, navigation, overlay, atau dark background.
2. Tidak ada clipping kolom, total, status, logo, dan signature.
3. Draft selalu terlihat jelas dan WhatsApp resmi tetap terkunci sebelum pembayaran.
4. Hitam-putih tetap membedakan status melalui teks/border, bukan warna saja.
5. Page break tidak memisahkan header tabel dari isi atau total dari rincian.
6. Nama file/PDF, nomor bukti, periode, dan waktu cetak dapat ditelusuri.

## 10. Consistency Inventory

| Area | Intent/sumber | Kondisi aktual | Keputusan audit |
| --- | --- | --- | --- |
| Color | Token hijau sawit, gold, dark slate, semantic states | globals.css sejalan dengan DESIGN.md | Pertahankan palette; perbaiki contrast endpoint |
| Typography | Plus Jakarta Sans + JetBrains Mono | Konsisten pada UI dan angka | Jangan mengecilkan root font; pertahankan mono untuk audit fields |
| Spacing | Grid 4/8px | Token 4, 8, 16, 24, 32, 48, 64 tersedia | Pertahankan |
| Radius | Work surface tenang 8-10px | Card/modal global memakai radius 20px | Turunkan radius work surface; modal/KPI boleh berbeda terbatas |
| Elevation/motion | Fokus pada operational clarity | Card hover scale 1.02 dan neon glow global | Hapus scale dari ledger/work card; sediakan reduced motion |
| Shell | Sidebar, sticky header, bottom nav | Konsisten lintas route aktif | Pertahankan; tambah semantics/focus |
| Buttons | Primary, gold, danger, outline, ghost | Class tersedia; sebagian action masih +, x, emoji, atau text-only | Standarkan icon Lucide, accessible name, dan target size |
| Form field | Label, input, hint, error, required | Visual konsisten; association/error semantics tidak | Buat Field primitive dengan id, label, hint, error, required |
| Selector | SearchableCombobox untuk master besar | Baik pada Pengiriman/Mitra tertentu; select biasa masih banyak | Jadikan default untuk data besar, select untuk option kecil |
| Modal/dialog | Shared Modal, ConfirmDialog, PromptDialog | Masih ada banyak overlay/modal ad hoc pada page | Satukan pada accessible Dialog primitive |
| Feedback | Alert, toast, spinner, skeleton, empty state | Visual ada, implementasi per page dan tanpa live region | Buat Toast/InlineNotice/LoadingState bersama |
| Table | table-container, SortableHeader, TablePagination | Pola kuat tetapi tidak merata; 0 caption pada inventory | Buat DataTable conventions, caption, mobile priority, sticky action |
| Status | Badge success/warning/danger/neutral | Teks status cukup jelas | Buat status dictionary tunggal; jangan bergantung warna |
| Number/date | Helper format Rupiah/tanggal + mono | Umumnya konsisten, sebagian toLocaleString langsung | Pertahankan helper satu pintu |
| Print | White document surface | CSS global dan page-local terfragmentasi | Buat print tokens/layout dan regression suite |
| Inline CSS | Page-specific visual control | 502 inline style pada page files | Migrasikan hanya pola berulang/berisiko, bukan rewrite massal |

Design decision: .stitch/DESIGN.md adalah intent visual, sedangkan app/globals.css dan komponen adalah implementasi aktual. Jika berbeda, accessibility dan operational clarity menang atas efek dekoratif. Dark brand tetap dipertahankan, tetapi work surface harus lebih tenang daripada KPI/brand surface.

## 11. Page Audit Matrix

Legenda state:

- Aktif: workflow dapat digunakan.
- Role-limited: aktif tetapi dibatasi role/guard.
- Coming Soon: route ada dan child page dirender di balik overlay.
- Legacy: arsip read-only.
- Redirect: tidak memiliki layar kerja sendiri.

Kelas akses route pada baseline:

| Kelas | Exact role pada route guard | Scope UX/UI | Backend assurance |
| --- | --- | --- | --- |
| Publik | Belum login | Login/redirect | Auth tetap mengikuti audit security |
| Semua pengguna login | `admin_operasional`, `admin_keuangan`, `owner`, `super_admin` | Discoverability dan task flow | Read/mutation scope belum dianggap aman; lihat audit security |
| Finance | `admin_operasional`, `admin_keuangan`, `owner`, `super_admin` | Menu, direct-route feedback, content disclosure | Data API/RPC/RLS dirujuk ke `AUD-SEC-20260717-001..003` |
| Owner | `owner`, `super_admin` | Profit/settings visibility | Data API/RPC/RLS dirujuk ke audit security |

Nav visibility, direct-route permission, dan backend permission adalah tiga kontrol berbeda. Matrix di bawah menilai dua yang pertama secara UX; ia tidak menyatakan backend read/mutation telah terjamin.

| Route | State dan role | Tugas utama/pola | Penilaian UX/UI | Open finding tertinggi | Evidence |
| --- | --- | --- | --- | --- | --- |
| / | Redirect, publik | Mengarahkan ke login | Tepat sebagai entry utility | Tidak ada route-local | app/page.js:4 |
| /login | Aktif, publik | Email/password, show password, sign in | Label login baik; emoji dan raw auth message perlu dinormalisasi | AUD-UX-20260717-011, S3 | app/login/page.js:50-157 |
| /dashboard | Aktif, semua role login | Command center hari ini, pending, quick action, role-aware finance/profit | Struktur exception-oriented kuat; access denial query belum dikomunikasikan dan copy masih campuran | AUD-UX-20260717-009, S2 | app/dashboard/page.js:569-850; proxy.js:58 |
| /admin/input-timbangan | Aktif, semua role login | Riwayat/koreksi + modal tambah pengiriman | Pain point batch lama sudah diimplementasikan; form/edit masih terkena gap dialog/field global | AUD-UX-20260717-004, S2 | app/admin/input-timbangan/page.js:717-938; components/transaksi/FormPengirimanModal.js:595-1050 |
| /transaksi/beli | Coming Soon, semua role login | Form pembelian lokal, struk, pembatalan | UI lengkap tetapi hanya ditutup overlay; keyboard lock belum dibuktikan. Mount/write guard: AUD-SEC-20260717-005 | AUD-UX-20260717-001, S1 | components/layout/AppShell.js:12-16; components/layout/AppShell.js:113-133; app/transaksi/beli/page.js:219-470 |
| /transaksi/kirim | Legacy read-only, semua role login | Arsip pengiriman lokal dan detail alokasi | Read-only intent jelas; istilah Legacy sebaiknya tidak tampil ke user | AUD-UX-20260717-011, S3 | app/transaksi/kirim/page.js:102-216 |
| /keuangan/biaya | Aktif, Admin/Owner/Super Admin/Admin Keuangan | Filter, export, tambah, pagination, reversal | Flow ringkas; emoji, raw error, dan modal ad hoc mengurangi konsistensi | AUD-UX-20260717-010, S2 | app/keuangan/biaya/page.js:133-295 |
| /keuangan/hutang | Aktif, Admin/Owner/Super Admin/Admin Keuangan | Pengajuan, approval, penyerahan, repayment, reversal, print | Workflow kaya dan traceable; density serta grid 4 kolom perlu mobile test | AUD-UX-20260717-007, S2 | app/keuangan/hutang/page.js:359-550 |
| /keuangan/kas | Aktif, Admin/Owner/Super Admin/Admin Keuangan | Saldo, mutasi manual, pagination, reversal | Saldo pembuka/akhir dan reversal jelas; modal ad hoc dan close x belum accessible | AUD-UX-20260717-004, S2 | app/keuangan/kas/page.js:191-382 |
| /master/armada | Aktif, semua role login | Search, sort, export, verify, add/edit/nonaktif | Pola master kuat dan status verifikasi jelas; field/modal semantics perlu standar | AUD-UX-20260717-005, S2 | app/master/armada/page.js:224-431 |
| /master/harga | Role-limited, Owner/Super Admin | Harga TBS lokal dan history | Halaman jelas tetapi modul lokal masih beku; visibility/IA perlu keputusan Product Owner | AUD-UX-20260717-014, S2 | app/master/harga/page.js:74-201; components/layout/Sidebar.js:48 |
| /master/pabrik | Aktif, semua role login | Add/edit/nonaktif/verify pabrik | Ringkas dan status verifikasi baik; memakai modal/field pattern lama | AUD-UX-20260717-005, S2 | app/master/pabrik/page.js:131-262 |
| /master/petani | Coming Soon, semua role login | Master petani lokal | Title Petani / Mitra berpotensi ambigu; keyboard lock belum dibuktikan. Feature gate: AUD-SEC-20260717-005 | AUD-UX-20260717-001, S1 | components/layout/AppShell.js:12-16; components/layout/AppShell.js:113-133; app/master/petani/page.js:119-302 |
| /laporan/harian | Redirect, semua role login | Mengarah ke Dashboard | Mendukung satu pintu sementara; deep link kehilangan penjelasan bahwa Closing Harian belum ada | AUD-UX-20260717-014, S2 | app/laporan/harian/page.js:4 |
| /laporan/laba-rugi | Role-limited, Owner/Super Admin | Ringkasan arus kas dan export | Rename dari laba/rugi sudah tepat; grid 3 kolom inline berisiko pada mobile | AUD-UX-20260717-007, S2 | app/laporan/laba-rugi/page.js:148-220 |
| /laporan/petani | Coming Soon, semua role login | Rekap transaksi/pembayaran/pinjaman petani | Konten tetap dirender di balik overlay; fixed 300px + 1fr perlu diperbaiki sebelum aktivasi | AUD-UX-20260717-001, S1 | components/layout/AppShell.js:12-16; components/layout/AppShell.js:113-133; app/laporan/petani/page.js:145-324 |
| /laporan/stok | Coming Soon, semua role login | Rekonsiliasi dan koreksi stok | Focus/keyboard lock belum dibuktikan. Mount/write guard: AUD-SEC-20260717-005 | AUD-UX-20260717-001, S1 | components/layout/AppShell.js:12-16; components/layout/AppShell.js:113-133; app/laporan/stok/page.js:196-382 |
| /owner/kwitansi-mitra | Aktif, Admin/Owner/Super Admin/Admin Keuangan | Pilih mitra/periode, bayar, print, WhatsApp, reversal | Draft stamp, WA lock, grouping, dan print kuat; toolbar/dialog/content masih beragam | AUD-UX-20260717-004, S2 | app/owner/kwitansi-mitra/page.js:643-1551 |
| /owner/laporan-armada-cb | Role-limited, finance/profit | Rekap trip, muatan, dana, margin sesuai role, export/payment | Role-aware disclosure dan exception link kuat; table/density perlu mobile/AT test | AUD-UX-20260717-016, S2 | app/owner/laporan-armada-cb/page.js:363-576 |
| /owner/laporan-mitra | Aktif, semua role login | Filter, status bayar, export, print, link kwitansi | Tujuan laporan vs pembayaran dijelaskan; TWB/TBS dan table naming perlu normalisasi | AUD-UX-20260717-011, S3 | app/owner/laporan-mitra/page.js:451-858 |
| /owner/master-data | Aktif, semua role login | Master mitra/tarif, verify, export, pagination | Pola master paling lengkap; 11 visible labels tanpa shared field association | AUD-UX-20260717-005, S2 | app/owner/master-data/page.js:239-446 |
| /owner/panjar-mitra | Redirect, semua role login | Mengarah ke Pinjaman & Panjar | Konsolidasi satu pintu tepat; route lama sebaiknya diberi deprecation plan | AUD-UX-20260717-014, S2 | app/owner/panjar-mitra/page.js:4 |
| /owner/pembayaran-pabrik | Role-limited, finance | Catat uang masuk, cocokkan timbang, history, reversal | Bahasa tugas dan reversal jelas; form/table padat dan field semantics belum standar | AUD-UX-20260717-005, S2 | app/owner/pembayaran-pabrik/page.js:342-819 |
| /owner/pendapatan-owner | Role-limited, Owner/Super Admin | Filter, sync fee, report, print, pagination | Label bruto jelas dan sync memakai confirm; responsive/print perlu regression | AUD-UX-20260717-015, S2 | app/owner/pendapatan-owner/page.js:330-737 |
| /owner/pengaturan-web | Role-limited, Owner/Super Admin | Branding, upload/remove logo, preview, save | Preview screen/print membantu; upload lalu save adalah two-step flow yang perlu state feedback kuat | AUD-UX-20260717-006, S2 | app/owner/pengaturan-web/page.js:121-410 |

## 12. Register Temuan Aktif

Semua entry dibuat 17 Juli 2026 oleh UX Research Lead + UI Design System Auditor. Owner dan target adalah usulan untuk triage. Tautan backlog menunjuk work item internal pada bagian 13; task repository belum dibuat karena scope audit ini hanya satu file.

| ID | Scope/role | Kondisi dan bukti | Dampak | Severity / priority | Rekomendasi hasil | Owner / target | Status / tautan |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AUD-UX-20260717-001 | Empat route Coming Soon; semua role login | CODE components/layout/AppShell.js:113-133 hanya menambah overlay dan pointerEvents none. INFERENCE focus/keyboard dapat tetap mencapai background karena belum ada inert/focus guard. Mount/query/write dicatat sebagai `AUD-SEC-20260717-005`. | User dapat kehilangan konteks atau mengaktifkan kontrol yang dinyatakan belum tersedia; komunikasi status tidak sesuai perilaku | S1 / P0 | Setelah feature gate backend/route aktif, terapkan inert/focus guard, aria relationship, status Bahasa Indonesia, dan uji keyboard/role | Engineering Lead + UX/UI Reviewer + QA / sebelum penggunaan berikutnya | Open / BACKLOG-UX-001 |
| AUD-UX-20260717-002 | Semua route; pengguna low vision | CODE app/layout.js:9-13 menetapkan maximumScale 1 | Pengguna tidak dapat mengandalkan pinch zoom; tugas angka padat menjadi inaccessible | S2 / P1 | Hapus maximumScale dan buktikan reflow pada 200%/400% | Implementer + UX/UI Reviewer / iterasi berikutnya | Open / BACKLOG-UX-002 |
| AUD-UX-20260717-003 | Button, hint, metadata; semua role | CODE app/globals.css:625-678 dan app/globals.css:734-782. CALC endpoint primary/white 2.90:1, danger/white 3.82:1, tertiary/card 3.91:1 | Label action/status kecil sulit dibaca dan tidak mencapai target contrast normal text | S2 / P1 | Gelapkan background action atau gunakan text inverse; naikkan tertiary token; test semua state | UX/UI Reviewer / iterasi berikutnya | Open / BACKLOG-UX-002 |
| AUD-UX-20260717-004 | Modal, confirm, prompt, drawer; semua role | CODE components/ui/Modal.js:40-123, components/ui/ConfirmDialog.js:27-61, dan components/ui/PromptDialog.js:50-108 tidak memiliki role dialog/aria-modal/title relationship/focus trap/return lengkap. Modal dasar hanya menangani Escape | Keyboard/screen-reader user dapat kehilangan konteks atau berinteraksi dengan background saat action kritis | S2 / P1 | Satu Dialog primitive accessible untuk modal/form/confirm/prompt; initial focus, trap, Escape policy, return focus, labelled/described by | Implementer + UX/UI Reviewer / iterasi berikutnya | Open / BACKLOG-UX-003 |
| AUD-UX-20260717-005 | Forms pada route aktif; semua role | COUNT-A11Y-01 menemukan 125 label dan hanya 2 htmlFor pada page files; contoh sibling label/input components/transaksi/FormPengirimanModal.js:615-655 | Nama, hint, required, dan error tidak selalu terhubung secara programatik; voice/screen reader operation tidak stabil | S2 / P1 | Field primitive dengan generated id, htmlFor, aria-describedby, aria-invalid, dan error id | Implementer + UX/UI Reviewer / dua iterasi | Open / BACKLOG-UX-004 |
| AUD-UX-20260717-006 | Toast, alerts, loading, save/upload; semua role | CODE components/transaksi/FormPengirimanModal.js:596-607 dan app/laporan/laba-rugi/page.js:149-154 menampilkan update dinamis tanpa role status/alert atau aria-live | Success/error dapat tidak terdengar; user dapat mengulang submit atau tidak tahu state berubah | S2 / P1 | Shared Toast/InlineNotice/LoadingState dengan live-region policy dan focus-to-error summary | Implementer + UX/UI Reviewer / iterasi berikutnya | Open / BACKLOG-UX-004 |
| AUD-UX-20260717-007 | Mobile pada Hutang dan Ringkasan Arus Kas; semua role terkait | CODE app/globals.css:1643-1688 mengecilkan root font; inline 4/3-column grids pada app/keuangan/hutang/page.js:383 dan app/laporan/laba-rugi/page.js:203 dapat mengalahkan media query | Angka/tombol sangat kecil, cards menyempit, teks dapat wrap/overlap, dan scanning finansial melambat | S2 / P1 | Pertahankan root 16px, gunakan responsive class/container query, minimum card width, dan viewport regression | Implementer + UX/UI Reviewer + QA / iterasi berikutnya | Open / BACKLOG-UX-005 |
| AUD-UX-20260717-008 | Semua route dengan animation; pengguna motion-sensitive | CODE components/layout/AppShell.js:100-108, app/globals.css:525-539, dan app/globals.css:1550-1608 menjalankan fade/scale/shimmer tanpa prefers-reduced-motion | Discomfort dan hilangnya stabilitas visual pada repeated work | S3 / P2 | Reduced-motion tokens; nonaktifkan scale, transform transition, shimmer/motion non-esensial | UX/UI Reviewer / setelah P1 a11y | Open / BACKLOG-UX-006 |
| AUD-UX-20260717-009 | Route denied; role tanpa izin | CODE proxy.js:58 menulis akses=ditolak. Repo search menemukan tidak ada consumer akses pada Dashboard | User kembali ke Dashboard tanpa penjelasan dan dapat mengira link rusak/session gagal | S2 / P1 | Dashboard membaca one-shot denial reason dan menampilkan safe notice; log route/role tanpa membuka data sensitif | Implementer + Product/BA / iterasi berikutnya | Open / BACKLOG-UX-007 |
| AUD-UX-20260717-010 | Error path pada hampir semua workflow; semua role | CODE banyak page meneruskan error.message, misalnya components/transaksi/FormPengirimanModal.js:388, components/transaksi/FormPengirimanModal.js:550, app/keuangan/hutang/page.js:222-331, dan app/owner/kwitansi-mitra/page.js:610-632 | Pesan teknis/Inggris tidak konsisten, dapat membingungkan dan berpotensi mengungkap detail implementasi | S2 / P1 | Error catalog per use case: user message, recovery, retry policy, reference code, technical log | Engineering Lead + Implementer / dua iterasi | Open / BACKLOG-UX-008 |
| AUD-UX-20260717-011 | Login, nav, dashboard, laporan, kwitansi; semua role | CODE components/layout/Header.js:22, components/layout/Sidebar.js:28, components/layout/Sidebar.js:46, components/layout/Sidebar.js:56-57, app/owner/kwitansi-mitra/page.js:643, app/dashboard/page.js:569, app/dashboard/page.js:820, dan app/transaksi/kirim/page.js:102 | Mixed language/internal jargon menambah beban interpretasi dan mengurangi konsistensi produk | S3 / P2 | Terapkan glossary bagian 8, content lint/review, dan display-label dictionary | Product/BA + UX/UI Reviewer + Implementer / P2 | Open / BACKLOG-UX-009 |
| AUD-UX-20260717-012 | Work cards/ledger; semua role | DOC .stitch/DESIGN.md:23 dan .stitch/DESIGN.md:76 meminta work surface lebih tenang dan radius 8-10px. CODE app/globals.css:525-539 masih radius 20px, scale 1.02, neon hover. Dampak tugas belum diuji. | Visual emphasis berpotensi terlalu merata; dampak operasional belum terbukti | S3 / P2 | Uji repeated-scan task; pisahkan KPI card dan work container bila evidence mendukung | UX/UI Reviewer / P2 | Open / BACKLOG-UX-010 |
| AUD-UX-20260717-013 | Dialog ad hoc lintas route | CODE shared Modal/Confirm/Prompt tersedia, tetapi app/admin/input-timbangan/page.js:944-948 masih membuat modal-overlay ad hoc dan close x | Perilaku focus, Escape, return-focus, dan responsive dapat drift | S2 / P2 | Migrasikan dialog ad hoc pada scope yang disentuh ke primitive yang lolos `AUD-UX-20260717-004`; metrik inline style tetap technical-debt indicator, bukan defect UX tersendiri | Engineering Lead + UX/UI Reviewer / bertahap | Open / BACKLOG-UX-010 |
| AUD-UX-20260717-014 | Navigation/IA; mobile dan desktop | CODE route Coming Soon tetap ada pada components/layout/Sidebar.js:15-58 dan components/layout/BottomNav.js:6-24; redirect app/laporan/harian/page.js:4 dan app/owner/panjar-mitra/page.js:4 tidak memberi konteks; active state pada components/layout/Sidebar.js:230 dan components/layout/BottomNav.js:24 tidak memakai aria-current | Menu menambah dead-end, route state tidak jelas, dan deep link kehilangan konteks | S2 / P1 | Product Owner memilih hide vs disabled; label Belum tersedia; redirect notice/deprecation; aria-current dan nav label | Product/BA + UX/UI Reviewer + Implementer / iterasi berikutnya | Open / BACKLOG-UX-011 |
| AUD-UX-20260717-015 | Print outputs; Owner/Admin finance | CODE global print hanya memunculkan struk pada app/globals.css:1411-1424, sedangkan report/kwitansi mengandalkan override lokal | Perubahan cascade dapat menghasilkan blank/clipped print tanpa terdeteksi; bukti transaksi terdampak | S2 / P1 | Print foundation dan Playwright/PDF visual regression untuk A4/80mm/black-white/page break | Implementer + QA / sebelum rilis berikutnya | Open / BACKLOG-UX-012 |
| AUD-UX-20260717-016 | 24 data tables; semua role | COUNT-A11Y-01 menemukan 24 table dan 0 caption; mobile bergantung pada horizontal scroll | Screen-reader context dan mobile scanning ledger/report tidak konsisten; action column dapat jauh dari identitas row | S2 / P2 | DataTable convention: caption/sr label, scope, mobile priority, sticky identity/action, sort/pagination semantics | UX/UI Reviewer + Implementer / P2 | Open / BACKLOG-UX-013 |

### 12.1 Perubahan positif yang didukung repo

Temuan berikut bukan active finding baru, tetapi penting untuk menjaga keputusan yang sudah benar:

1. Audit lama meminta form Pengiriman menyatu dengan riwayat. Sekarang app/admin/input-timbangan/page.js:718 membuka FormPengirimanModal dari halaman riwayat yang sama.
2. Audit lama meminta armada dapat dipilih dahulu dan mitra auto-fill. Urutan sekarang Tanggal -> Sopir/Armada -> Mitra -> Berat -> Potongan, dan handleSopirChange mengisi mitra default pada components/transaksi/FormPengirimanModal.js:255-295.
3. Audit lama meminta tanggal batch dipertahankan. Reset setelah save menyebarkan form lama dan tidak mengosongkan tanggal pada components/transaksi/FormPengirimanModal.js:560-583.
4. Opsi sopir aktual dipindahkan ke accordion Opsi Lanjutan pada components/transaksi/FormPengirimanModal.js:854-940.
5. Draft kwitansi sekarang memiliki cap DRAFT - BELUM DIBAYAR dan WhatsApp resmi baru aktif setelah payment snapshot pada app/owner/kwitansi-mitra/page.js:553-558 dan app/owner/kwitansi-mitra/page.js:811-815.
6. Laba/Rugi basis kas telah dilabel ulang menjadi Ringkasan Arus Kas pada app/laporan/laba-rugi/page.js:148-194.
7. Route panjar lama dan laporan harian telah dikonsolidasikan melalui redirect, sedangkan Kas/Biaya memakai pagination. Keputusan ini juga tercatat sebagai selesai pada docs/page-flow-control-audit-2026-07-16.md:400-416.

Perubahan positif di atas belum disebut Verified oleh audit UX/UI ini karena tidak ada usability/assistive-technology test pada sesi ini. Status kontrol bisnisnya tetap mengikuti audit flow aktif.

## 13. Backlog Operasional

| Backlog ID | Pri | Temuan | Work package | Acceptance criteria minimum | Proposed owner |
| --- | --- | --- | --- | --- | --- |
| BACKLOG-UX-001 | P0 | 001 | UX lock route lokal/petani, pendamping TASK-SEC-005 | Keyboard/focus tidak mencapai kontrol; background inert; status jelas; role test tersedia. Mount/query/write ditutup oleh task security primer | Engineering Lead + UX/UI Reviewer + QA |
| BACKLOG-UX-002 | P1 | 002,003 | Accessibility visual foundation | Zoom bebas; contrast normal text >=4.5:1; no clipping pada 200%/400% | UX/UI Reviewer + Implementer + QA |
| BACKLOG-UX-003 | P1 | 004 | Accessible Dialog v1 | role/aria lengkap; initial focus; trap; Escape policy; return focus; background inert; tests untuk confirm/prompt/form | Implementer + UX/UI Reviewer |
| BACKLOG-UX-004 | P1 | 005,006 | Accessible Field and Feedback | 100% active form controls named; hint/error relationship; aria-invalid; error summary; polite/assertive live policy | Implementer + UX/UI Reviewer |
| BACKLOG-UX-005 | P1 | 007 | Responsive finance pages | Root >=16px; Hutang, Arus Kas, Kwitansi, dan payment forms lulus 360/390/768/1024 tanpa overlap atau action hilang | Implementer + QA |
| BACKLOG-UX-006 | P2 | 008 | Reduced motion | OS preference menghapus non-essential scale/fade/shimmer; state tetap terlihat | UX/UI Reviewer |
| BACKLOG-UX-007 | P1 | 009 | Permission feedback | Redirect denied menampilkan notice satu kali, menjelaskan akses dengan aman, dan tidak membuat loop | Implementer + Product/BA |
| BACKLOG-UX-008 | P1 | 010 | Error translation and recovery | Critical workflows memiliki mapped error, recovery action, reference ID, technical logging, dan no raw stack/DB message | Engineering Lead + Implementer |
| BACKLOG-UX-009 | P2 | 011 | UI glossary/content pass | Product Owner menyetujui TBS/TWB; mixed terms diganti; status/action dictionary terpusat | Product/BA + UX/UI Reviewer |
| BACKLOG-UX-010 | P2 | 012,013 | Operational UI primitives | KPI card terpisah dari work container; Dialog/Toast/Toolbar/StatsGrid reusable; inline style turun pada touched scope | Engineering Lead + UX/UI Reviewer |
| BACKLOG-UX-011 | P1 | 014 | Navigation state cleanup | Hide/disabled decision per route; aria-current; mobile nav role-aware; redirect/deprecation notice | Product/BA + UX/UI Reviewer + Implementer |
| BACKLOG-UX-012 | P1 | 015 | Print regression suite | Kwitansi, Laporan Mitra, Pendapatan, Pinjaman, dan thermal sample lolos A4/80mm/PDF/black-white/page-break | Implementer + QA |
| BACKLOG-UX-013 | P2 | 016 | DataTable accessibility/mobile | Accessible table name, header scope, sort announcement, mobile identity/action visibility, pagination label | UX/UI Reviewer + Implementer |
| BACKLOG-UX-014 | P2 | Seluruh | Task-based usability benchmark | 5 critical task scripts, Admin/Owner observation, baseline time/error/confidence, issue linkage ke audit ID | UX Research + Product |

Urutan rekomendasi:

1. Tutup BACKLOG-UX-001 sebelum menganggap modul Coming Soon aman.
2. Jalankan BACKLOG-UX-002 sampai 008 dan 011-012 sebagai release-quality package.
3. Lanjutkan konsistensi visual/content pada P2 tanpa mengubah formula atau kontrol bisnis.
4. Validasi perubahan dengan benchmark tugas, bukan hanya screenshot.

## 14. Cadence, Ownership, dan Traceability

### 14.1 Cadence

| Waktu | Aktivitas | Output |
| --- | --- | --- |
| Segera | Triage P0 Coming Soon lock bersama `AUD-SEC-20260717-005` | Keputusan go/no-go, task, owner, test |
| Mingguan saat development aktif | 30 menit audit triage Product, UX, FE, QA | Severity/status/priority/owner diperbarui |
| Setiap PR UI | Review task flow, role, content, keyboard, responsive, print impact | Checklist + screenshot/test evidence |
| Setiap sprint | Jalankan 5 critical-path smoke tests dan viewport matrix | TEST-UX/QA evidence |
| Bulanan | Observasi Admin/Owner pada tugas aktual atau data representatif | Task time, error, hesitation, confidence |
| Sebelum rilis | Audit release gate untuk S0/S1, print, role, a11y, dan regression | Go/no-go record |
| Setelah rilis | Smoke test produksi dan review exception/support | Temuan baru atau status Verified |
| Perubahan besar / minimal per rilis besar | Baseline ulang seluruh route dan consistency inventory | Versi audit baru |

Cadence di atas tidak memberi kewenangan rilis. Keputusan go/no-go tetap mengikuti SOP dan audit security/release aktif. Status Verified pada temuan UX/UI tidak dapat mengubah NO-GO menjadi GO tanpa seluruh gate lintas domain ditutup. Perubahan UI yang dapat menyebabkan salah bayar atau melemahkan feature gate harus diperlakukan minimal sebagai perubahan KR3 sesuai SOP.

### 14.2 RACI ringkas

| Peran | Tanggung jawab |
| --- | --- |
| Product Owner | Menyetujui istilah, IA, priority, dan Accepted Risk |
| UX/UI Reviewer | Menjaga task flow, content, design system, responsive, print, accessibility, register |
| Engineering Lead | Membentuk work package dan menjaga component architecture |
| Frontend Implementer | Mengimplementasikan acceptance criteria dan component tests |
| Security/Data Reviewer | Meninjau feature gate/write guard dan dampak flow finansial |
| QA/Release Reviewer | Menyimpan evidence keyboard, role, viewport, print, regression, dan go/no-go |

### 14.3 Status transition

- Open -> Planned hanya setelah ada TASK ID, owner, target, dan acceptance criteria.
- Planned -> In Progress saat implementasi dimulai.
- In Progress -> Verified hanya setelah TEST evidence pada role/data/viewport relevan.
- Accepted Risk memerlukan alasan Product Owner, mitigasi, owner risiko, dan tanggal tinjau.
- Temuan tidak dihapus; duplicate/superseded menautkan ID utama/baru.
- Jika satu finding memiliki beberapa task turunan, seluruh task wajib `Verified` sebelum finding induk ditutup, kecuali finding dipecah dan closure note menyatakan scope yang telah dipindahkan.

Traceability target:

PRD/BDR -> AUD-UX ID -> BACKLOG-UX -> TASK/AC -> code -> TEST -> commit/PR -> release record.

Karena permintaan audit ini membatasi perubahan pada satu file, BACKLOG-UX belum dimasukkan ke IMPLEMENTATION-TASKS.md. Audit tidak boleh dianggap governance-complete sampai P0/P1 dipindahkan ke task aktif dan Product Owner/Engineering Lead menyetujui owner/targetnya.

Task publikasi audit telah tersedia pada IMPLEMENTATION-TASKS.md:20 dan work product ini sudah tercantum pada implementation_plan.md:22. Kedua file tersebut dimiliki workstream tata kelola lain dan tidak diubah dalam pekerjaan audit ini.

## 15. Metrics dan Definition of Done

### 15.1 Metrics baseline yang perlu dikumpulkan

- Task success rate untuk Tambah Pengiriman, Bayar Kwitansi, Pembayaran Pabrik, Reversal Kas, dan Pinjaman/Panjar.
- Median time dan jumlah Tab/click pada input pengiriman batch.
- Validation error, duplicate attempt, cancellation/reversal, dan retry rate.
- Persentase permission denial yang mempunyai penjelasan.
- Keyboard-only completion rate.
- Jumlah critical/serious accessibility issue per route.
- Print defect rate per format.
- Support question yang berasal dari istilah/status tidak jelas.

Target awal:

- 0 open S0/S1 untuk route yang dirilis.
- 100% critical form controls mempunyai accessible name, hint/error relationship, dan keyboard path.
- 100% critical dynamic feedback diumumkan dengan benar.
- 0 overlap/clipping/action hilang pada viewport regression.
- 0 blank/clipped print pada sample release.
- Perbaikan waktu input batch ditetapkan setelah baseline observasi pertama, bukan ditebak dari source.

### 15.2 Definition of audit complete

- Seluruh route dalam scope telah diinventarisasi: selesai.
- UX dan UI telah diperiksa sebagai satu scope: selesai.
- Temuan memiliki ID, severity, evidence, owner usulan, dan status: selesai.
- Temuan duplikat dengan flow audit tidak disalin; hubungan sumber aktif dijelaskan: selesai.
- P0/P1 masuk task list aktif dengan acceptance criteria: belum, karena scope file dibatasi.
- Runtime/role/a11y/print evidence tersedia untuk status Verified: belum.
- Product Owner dan reviewer domain menyetujui: belum.
- Tanggal tinjau berikutnya tercatat: selesai.

Dengan demikian dokumen ini adalah baseline audit aktif dan operasional, tetapi belum dinyatakan closed/Verified. Fokus berikutnya adalah menutup feature gate S0, membangun accessibility foundation, lalu menguji lima workflow kritis pada role dan perangkat yang benar.
