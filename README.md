# Sawit CB

Sawit CB adalah aplikasi web internal untuk pencatatan operasional dan keuangan RAM kelapa sawit. Sistem mencakup pengiriman TBS mitra, pembayaran dan kwitansi mitra, penerimaan pembayaran pabrik, Buku Kas, Pinjaman & Panjar, biaya operasional, master data, serta laporan berbasis role.

Status dokumentasi: **17 Juli 2026**

Status produk: **Sistem Bisnis Minimal Fase 2; masih dalam pengembangan aktif**

## Stack Utama

| Area | Teknologi |
| --- | --- |
| Web framework | Next.js 16.2.11, App Router |
| UI runtime | React 19.2.4, JavaScript/JSX |
| Backend platform | Supabase |
| Database | PostgreSQL 17 (target konfigurasi lokal Supabase) |
| Authentication | Supabase Auth, sesi berbasis cookie melalui `@supabase/ssr` |
| Data access | Supabase Data API dan PostgreSQL RPC |
| Styling | CSS global dan design tokens khusus Sawit CB |
| Charts | Recharts |
| Icons dan motion | Lucide React dan Motion |
| Spreadsheet | SheetJS `xlsx` dan `xlsx-js-style` |
| Package manager | npm dengan `package-lock.json` |
| Deployment target | Vercel dan Supabase hosted project |

Spesifikasi arsitektur, keamanan, database, route, testing, deployment, dan batas sistem tersedia di [Dokumentasi Teknis](docs/technical-specification.md).

## Prasyarat

- Node.js `>=20.9.0`.
- npm dan akses ke project Supabase terkait.
- Supabase CLI untuk migration dan database lint.
- Docker Desktop hanya diperlukan jika menjalankan stack Supabase lokal.

Versi lingkungan yang terakhir diverifikasi:

```text
Node.js       24.14.0
npm           11.9.0
Supabase CLI  2.109.1
```

## Menjalankan Lokal

1. Instal dependency.

```bash
npm ci
```

2. Untuk build/deployment hosted, buat `.env.local` dan isi variabel berikut dengan kredensial public/publishable project Supabase.

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Jangan menaruh `service_role` atau secret key pada variabel `NEXT_PUBLIC_*`.

3. Untuk development interaktif, aktifkan Supabase Docker lalu jalankan launcher lokal.

```bash
npx supabase start
npm run dev:local
```

Buka [http://localhost:3000](http://localhost:3000). Pengguna tanpa sesi akan diarahkan ke `/login`.

`npm run dev:local` mengambil hanya API URL dan publishable key dari `supabase status`; credential sensitif yang diwarisi proses atau tercantum di file environment Next.js dikosongkan sebelum server dimulai. `next.config.mjs` juga fail-closed bila secret masih aktif. `npm run dev` akan menolak target non-loopback agar `.env.local` hosted/production tidak terpakai tanpa sengaja untuk development.

## Perintah Utama

```bash
npm run dev       # development server
npm run dev:local # development aman terhadap Supabase Docker lokal
npm run test:local-app # smoke login dan redirect tanpa sesi terhadap stack lokal
npm run lint      # ESLint + Next.js Core Web Vitals
npm run build     # production build
npm run start     # menjalankan hasil production build
```

Database:

```bash
npx supabase migration list --linked
npx supabase db push --dry-run
npx supabase db push
npx supabase db lint --linked --level error --fail-on error
```

Migration wajib ditinjau dengan `--dry-run` sebelum diterapkan. Perubahan finansial harus non-destructive, memakai reversal, dan mempertahankan audit trail.

## Struktur Ringkas

```text
app/                  Route dan halaman Next.js App Router
components/           Layout, branding, form transaksi, dan UI reusable
lib/                  Role, kalkulasi bisnis, format, export, dan client Supabase
utils/supabase/        Browser, server, dan middleware client Supabase
supabase/migrations/   Riwayat migration PostgreSQL
supabase/tests/        Smoke test SQL dengan pola rollback
docs/                 Dokumentasi teknis, audit flow, dan rencana UX
public/                Aset statis
proxy.js               Session refresh dan route-level access guard
```

## Dokumentasi Proyek

- [Indeks dan Tata Kelola Dokumentasi](docs/documentation-index.md)
- [Spesifikasi Teknis](docs/technical-specification.md)
- [PRD Final dan Addendum](docs/work-packages/PRD-final.md)
- [Implementation Plan](docs/work-packages/implementation_plan.md)
- [Implementation Tasks](docs/work-packages/IMPLEMENTATION-TASKS.md)
- [SOP Pengembangan dan Delivery](docs/development-sop.md)
- [Tata Kelola Audit](docs/audit-governance.md)
- [Audit Flow Bisnis dan Kontrol Halaman](docs/page-flow-control-audit-2026-07-16.md)
- [Audit UX/UI Seluruh Aplikasi](docs/ux-ui-audit.md)
- [Audit Security dan Kesiapan Rilis](docs/security-release-audit-2026-07-17.md)
- [Work Package Remediasi P0](docs/work-packages/p0-security-release-remediation.md)
- [Protokol Kolaborasi Panel Spesialis](docs/ai-specialist-collaboration.md)

## Quality Gate

Pekerjaan normal masuk melalui PR ke `dev`; hanya kandidat yang selesai dan siap rilis dipromosikan melalui PR `dev` ke `main`. Hotfix production dibuat dari `main`, kembali ke `main`, lalu disinkronkan ke `dev`. Ikuti gate berdasarkan kelas risiko pada [SOP Pengembangan](docs/development-sop.md). Pemeriksaan minimum repository:

1. Jalankan `npm run lint`.
2. Jalankan `npm run build`.
3. Jalankan `git diff --check`.
4. Untuk perubahan database, jalankan migration rehearsal/dry-run dan DB lint pada environment yang tepat.
5. Uji role dari UI serta Data API/RPC, reversal, idempotency, dan rekonsiliasi untuk perubahan uang/data.
6. Catat reviewer, evidence, rollback, dan keputusan `GO/NO-GO` pada Release Checklist.

Repository memiliki GitHub Actions untuk lint/build/dependency, password policy, migration/database regression, advisor, Gitleaks, dan CodeQL. Node test runner dipakai untuk password policy; Playwright dipakai untuk gate print/export staging. Dockerfile aplikasi dan lisensi publik belum tersedia. Detail batas testing dan tindak lanjut dicatat pada spesifikasi teknis.

> **Status rilis:** kandidat `R-SEC-01` tetap **NO-GO untuk production**. CI, staging, dan independent code review telah lulus pada commit `cc96dbb`; MFA/AAL2, production-like upgrade rehearsal, backup/restore proof, dan approval release lintas peran masih menjadi blocker. Lihat [release checklist aktif](docs/releases/R-SEC-01-2026-07-20.md).
