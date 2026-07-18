# Spesifikasi Teknis Sawit CB

| Metadata | Nilai |
| --- | --- |
| Nama sistem | Sawit CB |
| Jenis sistem | Aplikasi web internal operasional dan keuangan RAM kelapa sawit |
| Versi aplikasi | `0.1.0` |
| Status produk | Sistem Bisnis Minimal Fase 2, pengembangan aktif |
| Tanggal baseline dokumen | 17 Juli 2026 |
| Repository | `Aflahul/RAM-Sawit-CB` |
| Branch rilis aktif | `main` |
| Bahasa antarmuka | Bahasa Indonesia |
| Zona waktu bisnis | Asia/Jakarta |

## 1. Tujuan Sistem

Sawit CB mendukung pencatatan dan kontrol bisnis untuk:

- pengiriman TBS oleh mitra ke pabrik;
- perhitungan berat netto, potongan pabrik, berat dibayar, Fee Owner, sewa Armada CB, dan nilai mitra;
- penerbitan dan histori Kwitansi Pembayaran TBS;
- pencatatan uang masuk dari pabrik;
- Buku Kas dan biaya operasional;
- Pinjaman & Panjar lintas mitra, petani, sopir, karyawan, dan pihak lain;
- master mitra, armada/sopir, pabrik, petani lokal, dan harga;
- laporan operasional, arus kas, pendapatan owner, serta performa Armada CB sesuai role.

Sistem belum diposisikan sebagai aplikasi akuntansi akrual penuh. Halaman Ringkasan Arus Kas bersumber dari mutasi kas aktual dan tidak menggantikan laporan laba/rugi akuntansi yang membutuhkan persediaan, hutang periode, penyusutan, dan penutupan periode.

## 2. Arsitektur Tingkat Tinggi

```text
Browser
  |
  | HTTPS
  v
Next.js App Router (Vercel)
  |-- React Client Components
  |-- proxy.js: session refresh + route guard
  |-- @supabase/ssr: cookie-based session
  |
  | Supabase JS / Data API / RPC
  v
Supabase
  |-- Auth
  |-- PostgreSQL
  |-- Row Level Security
  |-- SECURITY DEFINER RPC terkontrol
  |-- Storage tersedia pada platform, belum menjadi alur bukti utama
  v
Ledger, snapshot transaksi, audit log, dan laporan
```

Pola aplikasi saat ini adalah frontend Next.js yang mengakses Supabase secara langsung menggunakan publishable key dan sesi pengguna. Otorisasi tidak boleh bergantung pada penyembunyian menu; route guard, RLS, grant, dan RPC database tetap menjadi kontrol utama.

## 3. Stack Teknologi

### 3.1 Frontend dan Runtime

| Komponen | Versi | Fungsi |
| --- | --- | --- |
| Next.js | `16.2.10` | Framework web, App Router, build dan routing |
| React | `19.2.4` | UI component runtime |
| React DOM | `19.2.4` | Rendering DOM |
| JavaScript/JSX | ES Modules | Bahasa implementasi aplikasi; TypeScript belum digunakan |
| CSS | Custom global CSS | Design tokens, layout responsif, print styles, dan komponen visual |
| Lucide React | `^1.24.0` | Ikon antarmuka |
| Motion | `^12.42.2` | Animasi UI |
| Recharts | `^3.9.2` | Grafik dashboard dan laporan |
| `xlsx` | `^0.18.5` | Pembuatan file spreadsheet |
| `xlsx-js-style` | `^1.2.0` | Styling spreadsheet |

Alias import `@/*` diarahkan ke root repository melalui `jsconfig.json`.

### 3.2 Backend dan Data

| Komponen | Versi/konfigurasi | Fungsi |
| --- | --- | --- |
| Supabase JS | `^2.110.2` | Query Data API, Auth, dan RPC |
| `@supabase/ssr` | `^0.12.0` | Browser/server client dan cookie session |
| Supabase CLI | `^2.109.1` | Migration, local stack, lint, dan project linking |
| PostgreSQL | Major `17` pada konfigurasi lokal | Database relasional, ledger, constraint, trigger, dan RPC |
| Supabase Auth | Email/password | Identitas pengguna dan sesi |
| Supabase Data API | Schema `public`, `graphql_public` | Akses data terkontrol; batas lokal `1000` row per request |
| Supabase Storage | Aktif pada konfigurasi | Infrastruktur tersedia; unggah bukti transaksi masih backlog |

Project menggunakan **imperative migrations** pada `supabase/migrations/`. `schema_paths` kosong, sehingga repository tidak memakai declarative schema workflow.

### 3.3 Tooling

| Tool | Fungsi |
| --- | --- |
| npm | Instalasi dependency dan script aplikasi |
| ESLint 9 | Static analysis |
| `eslint-config-next/core-web-vitals` | Aturan Next.js dan Core Web Vitals |
| Git/GitHub | Version control dan repository remote |
| Vercel | Target hosting Next.js |
| Supabase CLI | Operasi migration dan database quality checks |

## 4. Kebutuhan Lingkungan

### Minimum

- Node.js `>=20.9.0`, mengikuti `engines` package Next.js yang terpasang.
- npm dengan dukungan lockfile v3.
- Browser modern dengan dukungan JavaScript, cookie, print/PDF, dan responsive layout.
- Akses jaringan ke Vercel dan Supabase.

### Lingkungan Terverifikasi

```text
Node.js       24.14.0
npm           11.9.0
Supabase CLI  2.109.1
```

Docker Desktop diperlukan untuk `supabase start`, database lokal, dan smoke test yang membutuhkan local stack. Docker tidak diperlukan untuk menjalankan Next.js terhadap Supabase hosted project.

## 5. Konfigurasi Environment

Variabel wajib:

| Variabel | Scope | Keterangan |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Browser + server | URL Data API project Supabase |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Browser + server | Publishable key untuk client yang tetap dibatasi Auth/RLS |

Contoh:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Aturan keamanan:

- `.env*` diabaikan Git.
- Jangan menaruh `service_role`, database password, atau secret key pada `NEXT_PUBLIC_*`.
- Kredensial pengguna tidak boleh ditulis pada dokumentasi, source code, migration, atau test yang dikomit.
- Environment production dikelola melalui pengaturan deployment platform.

## 6. Struktur Repository

| Path | Tanggung jawab |
| --- | --- |
| `app/` | Halaman dan route Next.js App Router |
| `components/layout/` | Shell aplikasi, header, sidebar, dan bottom navigation |
| `components/ui/` | Dialog, modal, combobox, sorting, dan pagination reusable |
| `components/transaksi/` | Form dan workflow transaksi pengiriman |
| `components/branding/` | Brand mark dan identitas aplikasi |
| `lib/` | Kalkulasi bisnis, role helper, format, pagination, sorting, branding, dan export |
| `utils/supabase/` | Browser client, server client, dan middleware client |
| `proxy.js` | Refresh sesi dan pembatasan route berdasarkan role |
| `supabase/migrations/` | Migration SQL berurutan; 54 file pada baseline dokumen |
| `supabase/tests/` | Smoke test SQL rollback untuk kontrol finansial dan Armada CB |
| `docs/` | Spesifikasi, audit flow, dan dokumentasi UX |
| `public/` | Aset statis |

## 7. Modul dan Route

Repository memiliki 25 file route `page.js`.

| Domain | Route utama | Keterangan |
| --- | --- | --- |
| Authentication | `/login` | Login email/password Supabase |
| Dashboard | `/dashboard` | Ringkasan operasional sesuai role |
| Pengiriman Mitra | `/admin/input-timbangan` | Input dan riwayat pengiriman mitra |
| Kwitansi Mitra | `/owner/kwitansi-mitra` | Draft, pembayaran, snapshot, cetak, dan histori kwitansi |
| Pembayaran Pabrik | `/owner/pembayaran-pabrik` | Uang masuk dan pencocokan data timbang |
| Buku Kas | `/keuangan/kas` | Mutasi kas masuk/keluar dan saldo periode |
| Pinjaman & Panjar | `/keuangan/hutang` | Pengajuan, persetujuan, penyerahan, pengembalian, reversal, dan histori |
| Biaya Operasional | `/keuangan/biaya` | Biaya dan reversal kas |
| Master Data | `/owner/master-data`, `/master/*` | Mitra, armada/sopir, pabrik, petani, dan harga |
| Laporan | `/owner/laporan-*`, `/laporan/*` | Operasional, Armada CB, arus kas, stok/petani sesuai status fitur |
| Pengaturan | `/owner/pengaturan-web` | Branding dan pengaturan bisnis yang tersedia |

Status bisnis dan keputusan hide/coming soon per halaman mengikuti [Audit Flow Bisnis](page-flow-control-audit-2026-07-16.md), bukan semata keberadaan file route.

## 8. Authentication dan Authorization

### Alur Sesi

1. Pengguna login menggunakan Supabase Auth email/password.
2. `@supabase/ssr` menyimpan dan menyegarkan sesi melalui cookie.
3. `proxy.js` memanggil `auth.getUser()` untuk validasi server-side.
4. Role aplikasi dibaca dari tabel `users`.
5. Route yang tidak diizinkan diarahkan ke `/dashboard?akses=ditolak`.
6. Query dan mutasi tetap diperiksa kembali oleh RLS, grant, constraint, atau RPC database.

### Role

| Role teknis | Label UI | Posisi saat ini |
| --- | --- | --- |
| `admin_operasional` | Admin | Pencatatan operasional dan pembayaran rutin yang diizinkan |
| `owner` | Owner | Kontrol bisnis, laporan sensitif, approval, dan reversal |
| `super_admin` | Super Admin | Kewenangan owner serta administrasi teknis/user |
| `admin_keuangan` | Admin Keuangan | Role cadangan untuk ekspansi staf; belum harus menjadi pengguna terpisah |

`admin` lama dinormalisasi menjadi `admin_operasional` untuk kompatibilitas.

### Kontrol Sensitif

- Laporan profit dan pengaturan bisnis dibatasi untuk Owner/Super Admin.
- Koreksi pembayaran dan reversal dibatasi melalui role dan RPC.
- Data finansial tidak boleh dihapus fisik oleh role aplikasi.
- Transaksi yang sudah masuk snapshot pembayaran dikunci dari edit biasa.
- Audit trail menyimpan pelaku, waktu, alasan, dan referensi transaksi pembalik.

## 9. Arsitektur Database

### Prinsip

- PostgreSQL adalah sumber kebenaran data bisnis.
- Nilai pembayaran yang sudah diterbitkan memakai **snapshot**, bukan membaca ulang transaksi live.
- Kas, Pinjaman/Panjar, biaya, pembayaran, dan reversal memakai ledger.
- Operasi finansial lintas tabel dijalankan melalui RPC atomik.
- Data lama dipertahankan melalui kompatibilitas dan migration non-destructive.
- Koreksi menggunakan status batal dan transaksi pembalik, bukan hard delete.

### Kelompok Data Utama

| Kelompok | Contoh tabel/konsep |
| --- | --- |
| Identitas dan role | `users` |
| Master operasional | `master_mitra`, `sopir`, `armada_perusahaan`, `pabrik`, `petani` |
| Pengiriman mitra | `transaksi_mitra` dan snapshot tarif/berat |
| Kwitansi mitra | header, item, ringkasan per mitra, snapshot transaksi dan panjar |
| Kas | `rekening_kas`, `kas_ledger` |
| Pinjaman & Panjar | `piutang_dokumen`, `piutang_pelunasan`, `hutang_ledger`, kompatibilitas `panjar_mitra` |
| Pabrik | pembayaran pabrik dan detail pencocokan |
| Armada CB | tarif, trip, dana operasional, dan biaya armada |
| Audit | `audit_log`, alasan koreksi, actor, dan referensi reversal |

Nama teknis seperti `hutang_ledger`, `piutang_*`, dan enum `kasbon_*` dipertahankan untuk kompatibilitas schema. Istilah UI final tetap **Pinjaman & Panjar**.

### Migration Workflow

```bash
npx supabase migration new nama_perubahan
npx supabase db push --dry-run
npx supabase db push
npx supabase migration list --linked
npx supabase db lint --linked --level error --fail-on error
```

Aturan migration:

- gunakan nama dan timestamp yang dibuat Supabase CLI;
- satu migration harus memiliki tujuan bisnis yang jelas;
- gunakan `IF EXISTS`/`IF NOT EXISTS` bila sesuai dan tetap tinjau idempotensi;
- fungsi `SECURITY DEFINER` wajib memiliki `search_path`, pemeriksaan actor/role, dan grant minimum;
- tabel pada exposed schema wajib memakai RLS dan policy sesuai role;
- migration remote wajib segera dikomit agar history repository dan database tetap sama.

## 10. Data Flow Kritis

### Pengiriman sampai Pembayaran Mitra

```text
Input Pengiriman Mitra
  -> transaksi dan snapshot berat/tarif
  -> antrian Kwitansi
  -> review per mitra/periode
  -> Tandai Dibayar
  -> snapshot header + item + ringkasan mitra
  -> potongan Panjar/Sewa per mitra
  -> kas keluar
  -> histori dan cetak ulang
```

Pada kwitansi gabungan, transaksi, panjar, sewa, dan subtotal dihitung per mitra. Hak Mitra A tidak boleh dipakai menutup panjar atau sewa Mitra B.

### Pembayaran Pabrik

```text
Nota/timbangan pabrik
  -> input tonase, harga, dan uang diterima
  -> pencocokan dengan data timbang internal
  -> kas masuk
  -> Ringkasan Arus Kas dan laporan owner
```

### Pinjaman & Panjar

```text
Admin mengajukan
  -> Owner/Super Admin menyetujui atau menolak
  -> Admin menyerahkan uang dari rekening kas
  -> dokumen + ledger + kas keluar
  -> pengembalian tunai/transfer atau potongan Kwitansi TBS
  -> sisa pinjaman dan histori
  -> reversal terkontrol bila terjadi kesalahan
```

## 11. UI, UX, dan Design System

Implementasi visual berada pada `app/globals.css` dan `.stitch/DESIGN.md` lokal. Folder `.stitch/` tidak dilacak Git.

Karakteristik utama:

- tema gelap untuk back-office operasional;
- Plus Jakarta Sans untuk teks dan JetBrains Mono untuk angka/transaksi;
- token warna hijau sawit, emas, semantic success/warning/danger/info;
- sidebar desktop dan bottom navigation responsif;
- komponen form, dialog, combobox, tabel sortable, dan pagination reusable;
- print stylesheet untuk kwitansi dan laporan;
- ikon Lucide dan animasi Motion bila diperlukan.

Dokumen design lokal membantu desain, tetapi source of truth production tetap CSS dan komponen yang dikomit.

## 12. Export, Print, dan Integrasi Pengguna

- Export spreadsheet menggunakan `xlsx` dan `xlsx-js-style`.
- Kwitansi/laporan menggunakan print stylesheet browser untuk cetak atau simpan PDF.
- WhatsApp menggunakan tautan `wa.me`; bukan WhatsApp Business API terotomasi.
- Grafik menggunakan Recharts.
- Storage tersedia, tetapi unggah foto tiket timbang, bukti transfer, dan dokumen bertanda tangan belum menjadi flow produksi utama.

## 13. Testing dan Quality Assurance

### Pemeriksaan Tersedia

```bash
npm run lint
npm run build
git diff --check
npx supabase db lint --linked --level error --fail-on error
```

Smoke test SQL:

- `supabase/tests/p0_financial_controls_rollback.sql`
- `supabase/tests/armada_cb_controls_rollback.sql`

Smoke test menggunakan pola transaksi/rollback agar data uji tidak menetap. Pengujian lokal yang memerlukan Supabase stack membutuhkan Docker Desktop.

### Batas Testing Saat Ini

- Belum ada test runner unit/integration JavaScript pada `package.json`.
- Belum ada automated browser/E2E suite yang dikomit.
- Belum ada GitHub Actions/CI pipeline.
- Role dan workflow finansial kritis masih memerlukan smoke test manual selain lint/build.

Rekomendasi berikutnya adalah menambahkan Vitest atau Jest untuk kalkulasi bisnis, Playwright untuk alur login/pengiriman/kwitansi, dan GitHub Actions untuk lint, build, serta test non-production.

## 14. Build dan Deployment

### Production Build

```bash
npm ci
npm run lint
npm run build
npm run start
```

### Target Deployment

- Frontend: Vercel, terhubung ke branch `main`.
- Backend: Supabase hosted project.
- Environment variables: dikonfigurasi pada Vercel, bukan dikomit.
- Database migration: diterapkan melalui Supabase CLI dari commit immutable yang sudah direview dan berada di Git sebelum perubahan production dijalankan.

Repository tidak memiliki `vercel.json`; deployment memakai default integrasi Next.js/Vercel. Repository juga belum memiliki Dockerfile aplikasi.

### Release Checklist

Checklist normatif mengikuti [SOP Pengembangan](development-sop.md) dan [template release](templates/release-checklist-template.md). Ringkasannya:

1. Selesaikan requirement, risk class, review, test plan, rollback, serta bukti staging pada branch/PR.
2. Jalankan lint, build, test, secret/dependency check, migration rehearsal, DB lint, dan dry-run sesuai risiko.
3. Pastikan migration dan aplikasi berada dalam commit immutable yang sudah disetujui sebelum production.
4. Verifikasi target environment, backup/recovery, operator, dan urutan expand/deploy/contract yang kompatibel.
5. Terapkan migration dan deploy aplikasi sesuai urutan yang telah direhearsal.
6. Jalankan negative role test, smoke test, rekonsiliasi, observasi, serta catat keputusan `GO/NO-GO`.

Baseline [Audit Security dan Kesiapan Rilis](security-release-audit-2026-07-17.md) saat ini menetapkan **NO-GO untuk rilis finansial baru**. Hanya containment/remediasi yang mengurangi risiko dan lulus gate terkait yang boleh dipromosikan sampai baseline pengganti diterbitkan.

## 15. Logging, Audit, dan Operasional

Audit bisnis disimpan di database untuk aksi sensitif. Log teknis aplikasi saat ini masih mengandalkan log runtime Next.js/Vercel dan log Supabase.

Belum tersedia:

- error tracking khusus seperti Sentry;
- application performance monitoring;
- centralized log dashboard milik aplikasi;
- health check endpoint khusus;
- automated backup/restore drill di repository.

Untuk penggunaan produksi jangka panjang, tambahkan error tracking, alert kegagalan RPC, monitoring deployment, backup terjadwal, dan latihan restore berkala.

## 16. Keamanan dan Privasi

- Aplikasi adalah sistem internal dan seluruh route bisnis memerlukan login.
- Publishable key boleh berada di browser; keamanan data tetap bergantung pada Auth, RLS, grant, dan RPC.
- Secret/service role tidak boleh berada pada frontend.
- Role aplikasi tidak boleh mendapat `DELETE`/`TRUNCATE` pada data finansial.
- Perubahan master oleh Admin dapat masuk status verifikasi sebelum disahkan Owner.
- Laporan profit dan pengaturan sensitif dibatasi berdasarkan role.
- Data pribadi minimum seperti nama dan nomor telepon harus digunakan hanya untuk operasional yang disetujui.

Review keamanan wajib diulang setiap kali menambah tabel exposed, RPC `SECURITY DEFINER`, storage bucket, atau role baru.

Route guard dan penyembunyian menu bukan kontrol keamanan data. Akses langsung melalui Data API, grant, RLS, view, RPC, audit-log mutation, dan final-state privilege harus diuji untuk setiap role. Temuan aktif tercatat pada [Audit Security dan Kesiapan Rilis](security-release-audit-2026-07-17.md).

## 17. Batas Sistem dan Technical Debt

| Area | Kondisi saat ini |
| --- | --- |
| Akuntansi | Ringkasan Arus Kas tersedia; laba/rugi akrual penuh belum tersedia |
| Testing | Lint, build, DB lint, dan SQL smoke test tersedia; unit/E2E automation belum tersedia |
| CI/CD | Deployment GitHub/Vercel digunakan, tetapi workflow GitHub Actions belum ada |
| Storage bukti | Infrastruktur tersedia; flow lampiran bukti belum selesai |
| Observability | Mengandalkan platform logs; error tracking/APM khusus belum ada |
| Backup | Perlu SOP dan latihan restore yang terdokumentasi |
| Container | Tidak ada Dockerfile aplikasi; Docker hanya untuk Supabase local stack |
| Lisensi | Belum ada file lisensi publik; repository diperlakukan private/internal |
| Type safety | JavaScript/JSX; TypeScript dan generated database types belum digunakan |

## 18. Standar Kontribusi

- Ikuti pola komponen dan helper yang sudah ada.
- Hindari duplikasi formula finansial di UI; tempatkan perhitungan bersama di `lib/` atau RPC.
- Simpan snapshot untuk transaksi yang sudah menjadi bukti pembayaran.
- Jangan mengubah data finansial historis secara langsung.
- Gunakan dialog aplikasi, bukan `alert`, `confirm`, atau `prompt` bawaan browser.
- Perbarui hanya sumber kebenaran yang terdampak beserta traceability-nya sesuai [Indeks Dokumentasi](documentation-index.md); jangan menyalin aturan lengkap ke banyak dokumen.
- Jangan commit `.env.local`, kredensial, data produksi, `.stitch/`, `.agents/`, atau artefak build.

## 19. Peta Dokumentasi

- [README](../README.md): onboarding dan perintah utama.
- [Indeks Dokumentasi](documentation-index.md): sumber kebenaran, status aktif/historis, owner, dan cadence.
- [PRD Final dan Addendum](../PRD-final.md): tujuan produk dan aturan bisnis.
- [Implementation Plan](../implementation_plan.md): urutan serta status implementasi.
- [Implementation Tasks](../IMPLEMENTATION-TASKS.md): checklist teknis.
- [SOP Pengembangan](development-sop.md): lifecycle, metode, RACI, quality gate, release, rollback, dan incident.
- [Tata Kelola Audit](audit-governance.md): taxonomy, severity, format temuan, dan traceability.
- [Audit Flow Bisnis](page-flow-control-audit-2026-07-16.md): audit halaman, tombol, data, role, dan tindak lanjut.
- [Audit UX/UI Seluruh Aplikasi](ux-ui-audit.md): task flow, UI, content, accessibility, responsive, print, dan konsistensi halaman.
- [Audit Security dan Kesiapan Rilis](security-release-audit-2026-07-17.md): temuan security serta keputusan `GO/NO-GO` terkini.
- [Protokol Panel Spesialis](ai-specialist-collaboration.md): pembagian subagent/peran dan koreksi silang.

Dokumen ini harus diperbarui ketika framework utama, versi runtime, model role, strategi deployment, environment variable, migration workflow, atau quality gate berubah.
