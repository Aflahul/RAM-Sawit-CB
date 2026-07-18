# Audit Isi Halaman dan Rekomendasi Navigasi - Sawit CB

Tanggal audit: 14 Juli 2026

Status: **arsip audit historis**. Keputusan yang masih berlaku harus dirujuk dari [Audit UX/UI Seluruh Halaman](ux-ui-audit.md) atau [Audit Flow Bisnis](page-flow-control-audit-2026-07-16.md). Dokumen ini tidak lagi menjadi tempat pencatatan temuan baru.

Dokumen ini memetakan isi setiap halaman, potensi pengulangan data antar halaman, dan tindak lanjut UX yang disarankan. Fokus keputusan: user tidak boleh melihat banyak halaman yang seolah berbeda padahal isinya data yang sama tanpa tujuan kerja yang jelas.

## Prinsip Keputusan

- Halaman input dipertahankan jika menjadi pintu kerja utama.
- Halaman laporan dipertahankan jika menjawab pertanyaan bisnis yang berbeda dari halaman input.
- Halaman rekap yang hanya mengulang isi dashboard atau laporan lain sebaiknya disembunyikan dulu.
- Halaman legacy tetap boleh ada sebagai arsip baca-saja, tetapi tidak masuk navigasi utama.
- Modul lokal/petani tetap Coming Soon sampai pembelian lokal, stok, dan laporan petani selesai satu alur.
- "Tutup Hari" tidak boleh hanya berupa laporan. Ia harus menjadi workflow validasi dan penguncian periode.

## Ringkasan Keputusan

| Keputusan | Halaman |
| --- | --- |
| Tetap tampil sebagai workflow utama | Dashboard, Pengiriman Mitra, Riwayat & Koreksi Mitra, Kwitansi Mitra, Pembayaran Pabrik, Buku Kas, Hutang & Panjar, Biaya Operasional, Mitra, Armada, Pabrik Tujuan, Laporan Mitra, Pendapatan Owner Bruto, Laba/Rugi, Pengaturan Web |
| Coming Soon / dikunci sementara | Pembelian Petani Lokal, Petani Lokal, Laporan Petani, Stok Lokal |
| Sembunyikan dari navigasi | Laporan Harian, Arsip Panjar Mitra, Pengiriman Lokal Legacy |
| Perlu evaluasi berikutnya | Harga TBS Lokal, karena hanya berguna jika modul lokal aktif |

## Audit Per Halaman

| Route | Isi Saat Ini | Overlap / Risiko Pengulangan | Rekomendasi |
| --- | --- | --- | --- |
| `/dashboard` | Ringkasan harga, transaksi hari ini, stok lokal, kas, hutang/panjar, pending review, quick action, tren lokal, aktivitas terbaru. | Mengambil ringkasan dari banyak halaman. Overlap ini wajar jika dashboard hanya menjadi command center, bukan laporan detail. | Tetap tampil. Batasi ke status, angka penting, exception, dan aksi cepat. Jangan jadikan dashboard tempat detail laporan panjang. |
| `/admin/input-timbangan` | Input pengiriman mitra ke `transaksi_mitra`, memakai master mitra, sopir, harga pabrik, dan fee owner. | Tidak overlap secara fungsi; ini pintu input utama. Judul harus konsisten sebagai Pengiriman Mitra. | Tetap tampil sebagai workflow operasional utama. |
| `/owner/riwayat-pengiriman-mitra` | Daftar transaksi mitra, edit, batal, koreksi, audit log. | Overlap data dengan Laporan Mitra, tetapi tujuannya berbeda: koreksi operasional. | Tetap tampil. Jangan campur dengan laporan; fokus sebagai halaman koreksi dan audit transaksi. |
| `/owner/kwitansi-mitra` | Preview kwitansi, panjar mitra, tandai dibayar, snapshot item pembayaran, WhatsApp. | Overlap transaksi dengan Laporan Mitra, tetapi ini halaman pembayaran dan bukti. | Tetap tampil. Ini sumber tindak lanjut pembayaran mitra. |
| `/owner/pembayaran-pabrik` | Catat uang masuk dari pabrik berdasarkan tonase bersih versi pabrik, harga per kg, uang diterima, dan nomor bukti. Data timbang internal bisa dipilih untuk mencocokkan beda tonase. | Overlap dengan Buku Kas karena membuat kas masuk, tetapi halaman ini adalah pintu input pembayaran pabrik. Tidak menggantikan Laporan Mitra karena pabrik tidak perlu tahu mitra. | Tetap tampil di Keuangan. Pakai bahasa sederhana: uang masuk, tonase dari pabrik, dan cocokkan catatan kita. |
| `/owner/laporan-mitra` | Rekap pengiriman mitra, status bayar, grouping mitra, export/cetak. | Overlap dengan Riwayat Mitra dan Kwitansi Mitra. Masih layak karena fokus laporan, bukan edit atau bayar. | Tetap tampil. Pastikan hanya read-only dan status bayar mengarah ke Kwitansi Mitra. |
| `/owner/pendapatan-owner` | Fee owner bruto dari `transaksi_mitra`, koreksi/sinkron snapshot fee. | Overlap dengan Laba/Rugi, tetapi berbeda makna: bruto/estimasi hak owner, bukan laba kas final. | Tetap tampil khusus Owner/Super Admin. Label harus selalu "bruto" atau "estimasi". |
| `/laporan/laba-rugi` | Laba kas dari `kas_ledger`, biaya, pembelian lokal, pembayaran mitra, dan pembayaran pabrik. | Overlap dengan Buku Kas dan Pendapatan Owner, tetapi menjawab pertanyaan profit. Angka final tetap bergantung pada disiplin catat uang masuk/keluar. | Tetap tampil khusus Owner/Super Admin. Pastikan pembayaran pabrik masuk `kas_ledger` agar laba kas terbaca. |
| `/keuangan/kas` | Buku mutasi uang aktual dari `kas_ledger`, rekening kas, mutasi manual. | Menjadi sumber data bagi laba/rugi dan dashboard. Tidak boleh digantikan laporan. | Tetap tampil sebagai sumber kebenaran uang aktual. |
| `/keuangan/hutang` | Hutang/panjar semua pihak dari `hutang_ledger`, termasuk mitra, petani, sopir, karyawan, lainnya. | Menggantikan kebutuhan menu panjar terpisah. | Tetap tampil sebagai satu pintu hutang/panjar. |
| `/keuangan/biaya` | Input dan pembatalan biaya operasional, membuat kas ledger via RPC. | Overlap dengan Buku Kas karena biaya muncul sebagai kas keluar. Namun halaman biaya adalah sumber input kategori biaya. | Tetap tampil. Nanti bisa masuk ke workspace Keuangan Hari Ini. |
| `/owner/panjar-mitra` | Arsip panjar mitra dan aksi pelunasan/batal lama. | Banyak overlap dengan Hutang & Panjar dan Kwitansi Mitra. Berisiko membuat user bingung karena panjar sudah satu pintu. | Sembunyikan dari navigasi. Pertahankan sebagai arsip/internal sampai seluruh panjar mitra pindah ke detail Hutang & Panjar/Kwitansi. |
| `/owner/master-data` | Master mitra eksternal/internal, fee owner, kontak, status aktif. | Tidak overlap dengan Armada; mitra adalah pihak bisnis, armada adalah sopir/plat default. | Tetap tampil dengan label "Mitra". |
| `/master/armada` | Sopir, plat default, dan afiliasi mitra. | Pernah overlap dengan armada perusahaan, tetapi arah baru memakai mitra internal dan tabel sopir. | Tetap tampil sebagai "Armada". Jangan tampilkan armada perusahaan terpisah. |
| `/master/pabrik` | Master pabrik tujuan. | Dipakai oleh Pembayaran Pabrik sebagai pihak pembayar ke owner. | Tetap tampil. Nanti bisa ditambah nomor DO/kontrak jika workflow pabrik semakin detail. |
| `/master/harga` | Harga TBS lokal dari `harga_tbs_lokal`. | Overlap dengan kartu harga lokal di Dashboard. Karena modul lokal dikunci, manfaatnya sementara rendah. | Evaluasi untuk disembunyikan atau digabung ke "Harga & Fee" setelah alur harga pabrik/lokal dirapikan. |
| `/master/petani` | Master petani lokal. | Terkait langsung modul lokal yang belum selesai. | Coming Soon/dikunci sementara. Buka kembali saat pembelian dan laporan petani siap. |
| `/transaksi/beli` | Input pembelian petani lokal, stok, kas, hutang, struk, batal. | Terkait lokal dan sudah banyak muncul di Dashboard/Laporan Harian/Stok/Petani. | Coming Soon/dikunci sementara. Jangan dipakai operasional dulu. |
| `/laporan/petani` | Rekap transaksi, pembayaran, dan hutang petani. | Overlap dengan Pembelian Lokal dan Hutang & Panjar. Karena modul lokal belum final, berisiko salah baca. | Coming Soon/dikunci sementara. Nanti fokus sebagai kartu histori per petani, bukan rekap umum. |
| `/laporan/stok` | Stok lokal ledger, koreksi stok. | Overlap dengan pembelian lokal, pengiriman lokal, dan dashboard. | Coming Soon/dikunci sementara. Buka kembali setelah rekonsiliasi stok lokal ke mitra internal final. |
| `/laporan/harian` | Rekap pembelian lokal, biaya, stok lokal, pengiriman mitra, export Excel. | Sebagian besar isi sudah ada di Dashboard, Biaya, Laporan Mitra, Stok Lokal, dan Pembelian Lokal. Nama "Tutup Hari" tidak sesuai karena tidak mengunci periode. | Sembunyikan dari navigasi. Bangun ulang nanti sebagai "Closing Harian" dengan checklist dan tabel `tutup_hari`. |
| `/transaksi/kirim` | Arsip pengiriman lokal lama berbasis `pengiriman` dan detail legacy. | Digantikan oleh Pengiriman Mitra dengan mitra internal. | Tetap hidden sebagai arsip baca-saja. Jangan masuk navigasi. |
| `/owner/pengaturan-web` | Branding, logo, identitas aplikasi/kwitansi. | Tidak overlap dengan workflow bisnis. | Tetap tampil untuk role pengaturan. |
| `/login` dan `/` | Login dan redirect/root. | Utilitas sistem. | Tetap. Tidak masuk audit workflow bisnis. |

## Rencana Pengembangan Berikutnya

### 1. Closing Harian

Bangun ulang `/laporan/harian` menjadi halaman **Closing Harian**, bukan rekap harian biasa.

Isi minimal:

- Checklist harga pabrik dan harga/fee yang berlaku.
- Total pengiriman mitra dan transaksi yang belum valid.
- Ringkasan kas masuk/keluar dari `kas_ledger`.
- Biaya operasional hari itu.
- Hutang/panjar yang bertambah atau dilunasi.
- Kwitansi mitra belum dibayar dan kwitansi perlu review.
- Pembayaran pabrik pending atau masuk.
- Stok lokal hanya setelah modul lokal aktif.
- Catatan exception.
- Tombol "Tutup Hari" yang menyimpan status ke tabel `tutup_hari`.

Setelah hari ditutup, transaksi tanggal tersebut tidak boleh diedit bebas. Perubahan harus lewat koreksi, reversal, atau approval.

### 2. Pembayaran Pabrik

Gunakan Pembayaran Pabrik sebagai pintu uang masuk dari pabrik. Input utama: pabrik, tanggal uang masuk, rekening kas, tonase bersih dari pabrik, harga per kg, uang diterima, dan nomor bukti. Pilih data timbang internal hanya untuk mencocokkan beda tonase.

### 3. Konsolidasi Harga

Gabungkan konsep harga lokal, harga pabrik, fee owner, dan histori perubahan ke satu area "Harga & Fee" agar tidak tersebar antara Dashboard dan Master Harga Lokal.

### 4. Modul Lokal/Petani

Buka kembali modul lokal setelah empat hal siap bersama:

- Pembelian petani.
- Stok lokal.
- Laporan petani.
- Rekonsiliasi pengiriman lokal sebagai mitra internal.

### 5. Panjar Mitra

Pertahankan satu pintu input di Hutang & Panjar. Arsip panjar mitra hanya dipakai sebagai referensi internal sampai seluruh potongan kwitansi dapat dilihat dari detail pihak/kwitansi.
