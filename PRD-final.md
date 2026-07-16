# ADDENDUM MVP TAHAP 1 (Selesai - Juli 2026)
Pengembangan Tahap 1 (MVP) berfokus pada **Pengiriman Mitra ke Pabrik** telah selesai. Setelah pembaruan Fase 2 minimum pada 14 Juli 2026, sebagian menu operasional dan keuangan dasar sudah dibuka. Label [Coming Soon] hanya dipakai lagi untuk fitur Fase 3/Fase 4 yang belum aman dipakai.
Fitur utama yang telah live:
1. **Master Data Mitra & Sopir**: Relasi `sopir` ke `master_mitra`, termasuk pengaturan `fee_per_kg` sebagai **Fee Owner** per mitra.
2. **Pengiriman Mitra**: Pencatatan armada masuk dengan perhitungan Skenario B (Harga Bersih ke Mitra = Harga Pabrik/TWB - Fee Owner).
3. **Panjar Mitra**: Modul kasbon mitra dengan tombol input cepat (Quick Add).
4. **Kwitansi Mitra**: Cetak kwitansi pembayaran otomatis dari owner ke mitra, dengan potongan panjar dari total nilai bersih TBS.
5. **Laporan Mitra**: Ledger rekapan global seluruh transaksi pengiriman mitra.
6. **Laporan Pendapatan Owner Bruto**: Rekap Fee Owner bruto dari transaksi mitra, hanya untuk Owner dan Super Admin.
7. **Dashboard Multi-Harga**: Pemisahan input Harga Pabrik (TWB) untuk MVP dan Harga Beli Lokal untuk Tahap 2.
8. **Pengaturan Web & Logo Kwitansi**: Owner dapat mengatur nama aplikasi, logo website berwarna, dan logo kwitansi.

# ADDENDUM FASE 2 MINIMUM (Diimplementasikan - 14 Juli 2026)

Status: Fase 2 minimum sudah masuk sebagai fondasi sistem bisnis harian, tetapi belum boleh disebut aplikasi final/utuh.

Yang sudah tersedia:

1. **Buku Kas**: `rekening_kas` dan `kas_ledger` menjadi buku kas tunggal untuk arus uang aktual.
2. **Uang Masuk Pabrik Dasar**: status pengiriman lokal dibayar pabrik membuat `pembayaran_pabrik` dan `kas_masuk`.
3. **Uang Keluar Dasar**: pembelian petani lokal, biaya operasional, pembayaran mitra kwitansi, dan panjar/hutang baru membuat `kas_keluar`.
4. **Hutang/Panjar Universal**: `hutang_ledger` diperluas untuk `petani`, `mitra`, `sopir`, `karyawan`, dan `lainnya`.
5. **Panjar Mitra Baru**: input baru di `panjar_mitra` disambungkan ke `hutang_ledger` dan `kas_ledger`; data legacy lama tetap dipertahankan.
6. **UI Minimum**: halaman Buku Kas, Hutang/Panjar, Biaya Operasional, Panjar Mitra, Pengiriman Lokal, Pembelian Lokal, dan Laba/Rugi sudah terhubung ke RPC/fondasi kas.
7. **No Delete Finansial Dasar**: koreksi memakai status batal dan reversal ledger pada flow yang sudah dipindah ke RPC.

Batasan yang sengaja belum disebut selesai:

- Alokasi pembayaran pabrik satu transaksi ke banyak DO.
- Upload bukti, nomor referensi wajib, atau lampiran pembayaran.
- Limit kasbon/panjar dan approval otomatis.
- Backfill panjar mitra legacy lama ke ledger universal.
- Settlement mitra advanced, pembagian selisih tonase, tarif armada, dan biaya bantuan.
- SOP backup production dan latihan pemulihan penuh. Uji role Admin dengan akun nyata serta smoke test rollback finansial sudah tersedia per 16 Juli 2026.

Kesimpulan produk: web sudah dapat dipakai sebagai **Sistem Bisnis Minimal Fase 2** untuk kontrol kas dan hutang harian, sambil pengembangan Fase 3 berjalan. Hardening role dan reversal P0 sudah diterapkan 16 Juli 2026, tetapi web belum boleh diposisikan sebagai sistem akuntansi penuh/final sampai settlement lanjutan, limit, lampiran bukti, persediaan, dan laba akrual selesai.

# ADDENDUM KONTROL BISNIS P0 (Diimplementasikan - 16 Juli 2026)

Keputusan produk:

1. Pengguna aktif disederhanakan menjadi **Admin**, **Owner**, dan **Super Admin**. Role `admin_keuangan` dipertahankan untuk ekspansi staf, tetapi tidak perlu menjadi akun terpisah saat ini.
2. Admin mencatat operasi dan pembayaran rutin. Owner/Super Admin menyetujui tarif, verifikasi master, pembatalan pembayaran, dan reversal.
3. Master Sopir/Armada atau Mitra yang dibuat Admin langsung dapat dipakai pada transaksi saat itu, tetapi berstatus **Perlu Verifikasi** sampai diperiksa Owner.
4. Transaksi yang sudah masuk kwitansi, pembayaran pabrik, atau Dana Trip tidak boleh diedit/batalkan melalui tombol biasa.
5. Koreksi pembayaran tidak menghapus catatan lama. Sistem membuat transaksi pembalik, menyimpan alasan, waktu, pelaku, dan hubungan ke catatan asal.
6. Kwitansi membedakan **Berat Netto** dari pabrik dan **Berat Dibayar** setelah potongan. Snapshot kwitansi yang sudah dibayar tidak mengikuti perubahan transaksi live.
7. Halaman yang sebelumnya disebut Laba/Rugi basis kas diberi nama **Ringkasan Arus Kas**. Laba akuntansi membutuhkan pengembangan terpisah untuk persediaan, hutang periode, penyusutan, dan penutupan periode.

Gerbang data:

- Periode Fee Owner tidak boleh tumpang tindih.
- Direct write ke master terverifikasi, item kwitansi, ledger, dan koreksi transaksi ditutup; aplikasi memakai RPC terkontrol.
- Tidak ada role aplikasi yang boleh melakukan `DELETE`/`TRUNCATE` tabel bisnis dan finansial.
- Kas menampilkan Saldo Pembuka, Kas Masuk, Kas Keluar, dan Saldo Akhir berdasarkan rekening serta periode.
- Satu kasus legacy yang sudah ditandai **Perlu Review** harus diputuskan Owner; sistem tidak melakukan reversal uang secara otomatis tanpa keputusan manusia.

Aturan Fee Owner MVP:

- `master_mitra.fee_per_kg` adalah Fee Owner aktif/default untuk tampilan cepat.
- Perubahan Fee Owner harus dicatat sebagai riwayat dengan tanggal berlaku.
- Setiap transaksi mitra wajib menyimpan snapshot harga/fee saat transaksi dibuat: Harga Pabrik/TWB, Fee Owner/Kg, Harga Bersih/Kg, Total Fee Owner, dan Total Nilai Bersih.
- Perubahan Fee Owner di masa depan tidak boleh mengubah transaksi lama.
- Koreksi transaksi lama dilakukan dari Riwayat Pengiriman Mitra dengan alasan edit.

Aturan Laporan Pendapatan Owner Bruto MVP:

- Pendapatan owner dari alur mitra dihitung dari snapshot `total_fee_owner` atau `fee_owner_per_kg x tonase`.
- Angka ini disebut **Pendapatan Owner Bruto** karena belum dikurangi biaya operasional owner.
- Biaya operasional seperti solar, gaji sopir, uang jalan, perawatan armada, kuli, retribusi, dan biaya timbang masuk Tahap 2.
- Laporan ini tidak boleh masuk ke kwitansi mitra, caption WhatsApp, atau laporan operasional yang bisa dilihat admin biasa.
- Jika transaksi lama belum memiliki snapshot Fee Owner, sistem menandainya sebagai perlu koreksi dan tidak memaksa memakai fee master terbaru.
- Koreksi pendapatan owner untuk transaksi lama dilakukan dari Riwayat Pengiriman Mitra agar alasan perubahan tersimpan.

Aturan Klasifikasi Mitra/Grup MVP:

- `master_mitra.tipe_mitra` dipakai untuk membedakan `eksternal` dan `internal_owner`.
- Kode `BL`, `BL/...`, `SL`, dan `SL/...` diklasifikasikan sebagai `internal_owner` karena merupakan grup/timbangan milik owner.
- Klasifikasi ini belum mengubah formula pembayaran atau kwitansi; fungsinya untuk filter dan konteks laporan.
- Perlakuan biaya operasional, kepemilikan armada, status sopir, dan pendapatan bersih owner ditunda ke Tahap 2 agar tidak terjadi double count.

Aturan Branding dan Waktu Transaksi MVP:

- Rincian transaksi menampilkan label **Waktu** berdasarkan `transaksi_mitra.created_at`.
- Label yang dipakai cukup **Waktu**, bukan "Waktu Input".
- Pengaturan branding disimpan sebagai konfigurasi `web_branding`.
- File logo disimpan sebagai objek di Storage khusus logo; database hanya menyimpan path/konfigurasi kecil agar tidak membebani Postgres.
- Logo website memakai PNG berwarna.
- Logo kwitansi boleh memakai PNG hitam khusus, tetapi jika tidak tersedia sistem boleh mengubah logo berwarna menjadi hitam saat cetak.
- Fitur pengaturan branding hanya dapat dikelola Owner dan Super Admin.

Aturan Status Pembayaran Mitra yang Direncanakan:

- Status sudah dibayar dicatat sebagai batch pembayaran mitra, bukan checkbox bebas per baris transaksi.
- Batch pembayaran dibuat dari kwitansi mitra berdasarkan mitra dan periode.
- Batch menyimpan snapshot total tonase, nilai bersih TBS, potongan panjar, nominal dibayar, tanggal bayar, metode bayar, catatan, dan pencatat.
- Daftar transaksi yang masuk pembayaran disimpan sebagai item batch agar bisa diaudit.
- Kwitansi adalah bukti pembayaran utama setelah owner menandai batch pembayaran sebagai **Sudah Dibayar**.
- Jika transaksi dalam batch diubah atau dibatalkan setelah pembayaran, status batch ditandai perlu review.
- Lampiran transfer hanya menjadi bukti pendukung opsional dan disimpan di Storage, sedangkan database hanya menyimpan path/metadata.

## ADDENDUM MVP - Pengiriman Kwitansi Mitra via WhatsApp (Direncanakan - Juli 2026)

### Tujuan

Kwitansi Mitra perlu memiliki dua aksi utama:

1. **Cetak / Simpan PDF** untuk kebutuhan arsip fisik atau kirim manual.
2. **Kirim WhatsApp** ke nomor WhatsApp penanggung jawab mitra berdasarkan data master mitra.

Fitur ini adalah add-on MVP karena owner membutuhkan cara cepat mengirim kwitansi ke mitra tanpa mengetik ulang ringkasan pembayaran. Sistem harus tetap menjaga kontrol manusia sebelum pesan benar-benar dikirim agar tidak salah kirim bukti transaksi.

### Kondisi Data Saat Ini

Sumber nomor WhatsApp memakai data `master_mitra.no_hp` dan nama penerima memakai `master_mitra.penanggung_jawab`.

Ketentuan data:

- `no_hp` wajib dinormalisasi ke format internasional sebelum dipakai WhatsApp.
- Untuk Indonesia, nomor `08xxxxxxxxxx` dinormalisasi menjadi `628xxxxxxxxxx`.
- Karakter selain angka seperti spasi, strip, titik, dan tanda plus harus dibersihkan.
- Jika nomor kosong atau tidak valid, tombol **Kirim WhatsApp** harus nonaktif atau menampilkan peringatan untuk melengkapi master mitra.
- Jika satu mitra memiliki lebih dari satu kontak, v1 cukup memakai nomor penanggung jawab utama; multi-kontak menjadi pengembangan lanjutan.

### Analisis Opsi Implementasi

#### Opsi A - WhatsApp Link / Click to Chat

Alur:

- Sistem membuat link `https://wa.me/<nomor>?text=<pesan>`.
- WhatsApp Web atau aplikasi WhatsApp terbuka dengan pesan ringkasan otomatis.
- Operator memeriksa penerima dan menekan kirim.
- File PDF dilampirkan manual jika browser tidak mendukung share file langsung.

Kelebihan:

- Paling cepat dibuat dan langsung bisa dipakai.
- Tidak membutuhkan akun WhatsApp Business Platform, token API, webhook, atau biaya API.
- Aman untuk MVP karena pengiriman tetap dikonfirmasi manusia.
- Cocok dengan pola kerja owner/operator yang sudah memakai WhatsApp harian.

Kekurangan:

- Link `wa.me` hanya membuka chat dan teks; bukan API otomatis untuk melampirkan file.
- Status terkirim/terbaca tidak bisa diverifikasi otomatis oleh sistem.
- Di desktop, operator mungkin tetap harus mengunduh/mencetak PDF lalu melampirkannya manual.

#### Opsi B - Web Share API dengan File PDF

Alur:

- Sistem membuat file kwitansi dalam format PDF.
- Jika browser mendukung `navigator.canShare()` dan `navigator.share()` untuk file, sistem membuka share sheet perangkat.
- Operator memilih WhatsApp dan mengirim file ke mitra.
- Jika tidak didukung, sistem fallback ke download PDF + buka WhatsApp link.

Kelebihan:

- Pengalaman terbaik untuk HP/tablet karena file bisa langsung dibagikan ke WhatsApp dari share sheet.
- Tetap tidak membutuhkan WhatsApp Business API.
- Tetap ada konfirmasi manusia sebelum file dikirim.

Kekurangan:

- Dukungan browser tidak merata, terutama desktop dan beberapa browser tertentu.
- Membutuhkan generator PDF yang stabil.
- Sistem tidak bisa memastikan apakah pengguna benar-benar memilih WhatsApp atau batal share.

#### Opsi C - WhatsApp Business Platform / Cloud API

Alur:

- Sistem membuat atau mengambil file PDF kwitansi.
- Sistem mengirim pesan dokumen ke nomor mitra lewat WhatsApp Business Platform.
- Status pengiriman dapat dilacak lewat webhook.

Kelebihan:

- Paling otomatis dan profesional untuk jangka panjang.
- Bisa mengirim dokumen PDF sebagai pesan dokumen.
- Bisa menyimpan status API seperti terkirim, gagal, dan webhook delivery.
- Cocok saat volume transaksi naik dan perlu bukti kirim sistematis.

Kekurangan:

- Membutuhkan setup WhatsApp Business Account, business verification, nomor bisnis, token, konfigurasi webhook, dan pengelolaan template pesan.
- Ada risiko aturan template/customer service window berubah sesuai kebijakan Meta.
- Ada biaya operasional API.
- Implementasi lebih sensitif: token API tidak boleh berada di frontend dan harus dipanggil dari server/Edge Function.

### Analisis Format File

| Format | Kelebihan | Kekurangan | Keputusan |
| --- | --- | --- | --- |
| PDF | Paling cocok untuk invoice/kwitansi, layout stabil, mudah dicetak, mudah diarsipkan, tampak resmi | Perlu generator PDF atau print-to-PDF; preview di chat tidak seinstan gambar | **Dipilih sebagai format utama** |
| PNG/JPG | Mudah dilihat langsung di chat, cocok untuk ringkasan pendek | Rentan buram/crop jika kwitansi panjang, kurang ideal untuk arsip resmi, sulit multi-halaman | Opsional sebagai preview ringkas |
| Teks WhatsApp saja | Sangat cepat, tidak perlu file | Tidak cukup sebagai bukti pembayaran resmi, mudah kehilangan detail tabel | Hanya sebagai caption/ringkasan |

Keputusan format:

- Format utama kwitansi WhatsApp adalah **PDF**.
- Pesan WhatsApp tetap berisi ringkasan singkat: mitra, periode, total tonase, total nilai bersih TBS, potongan panjar mitra, sisa dibayar ke mitra, dan status.
- Gambar/PNG boleh ditambahkan nanti hanya sebagai preview cepat, bukan pengganti PDF.

### Solusi Terbaik yang Dipilih

Solusi terbaik untuk Sawit CB adalah **hybrid bertahap**:

#### Tahap 1 - MVP Cepat dan Aman

Gunakan kombinasi:

- Tombol **Cetak / Simpan PDF** tetap tersedia.
- Tombol **Kirim WhatsApp**:
  - validasi nomor WA PJ mitra;
  - buat caption otomatis;
  - jika generator PDF sudah tersedia, unduh PDF otomatis sebelum membuka WhatsApp;
  - jika perangkat mendukung Web Share file, bagikan PDF melalui share sheet;
  - jika tidak mendukung, fallback ke download/cetak PDF dan buka `wa.me` dengan caption otomatis.
- Operator tetap melakukan konfirmasi terakhir di WhatsApp.

Catatan batasan:

- Link `wa.me` hanya aman dipakai untuk membuka chat dan mengisi teks. File PDF tidak bisa dipasang otomatis sebagai attachment WhatsApp Web dari frontend biasa.
- Skenario terbaik sebelum WhatsApp API adalah: sistem membuat/mengunduh PDF, membuka WhatsApp dengan caption otomatis, lalu operator melampirkan file PDF yang sudah terunduh.
- Auto-attach file baru realistis melalui Web Share API pada perangkat yang mendukung, atau lewat WhatsApp Business Platform / Cloud API pada tahap lanjut.

Alasan pemilihan:

- Langsung bisa dipakai tanpa proses onboarding WhatsApp Business API.
- Risiko salah kirim lebih rendah karena manusia tetap melihat penerima dan isi pesan.
- Cocok dengan MVP saat ini yang masih memakai halaman kwitansi berbasis print.
- Jalur teknis tetap bisa ditingkatkan ke API penuh tanpa mengganti logika bisnis kwitansi.

#### Tahap 2 - Otomasi Terkontrol

Jika kebutuhan naik, tambahkan:

- Supabase Storage private bucket untuk menyimpan PDF kwitansi.
- Tabel `kwitansi_mitra_send_log`.
- Tombol **Tandai Terkirim** untuk MVP manual.
- Nomor bukti/kwitansi unik.
- Riwayat kirim ulang jika kwitansi berubah setelah koreksi transaksi.

#### Tahap 3 - WhatsApp Business API

Jika owner membutuhkan pengiriman otomatis:

- Pakai WhatsApp Business Platform / Cloud API dari server/Edge Function.
- Kirim PDF sebagai document message.
- Simpan status API dan webhook.
- Gunakan template pesan jika pengiriman berada di luar customer service window atau jika aturan Meta mewajibkan template.

### Simulasi Skenario Terbaik

#### Skenario 1 - Data Lengkap dan Operator Mengirim dari HP

1. Owner membuka `/owner/kwitansi-mitra`.
2. Owner memilih mitra dan periode.
3. Sistem menghitung transaksi aktif, mengecualikan transaksi `dibatalkan`.
4. Tombol **Kirim WhatsApp** aktif karena `no_hp` mitra valid.
5. Sistem membuat PDF kwitansi dan caption:

```text
Kwitansi Pembayaran Sawit CB
Mitra: SL/B - Salulemo - H. Bayu
Periode: 2026-07-12 s/d 2026-07-13
Total Tonase: 9.898 Kg
Total Nilai Bersih TBS: Rp 29.199.100
Potongan Panjar Mitra: Rp 0
Sisa Dibayar ke Mitra: Rp 29.199.100

Mohon dicek. Terima kasih.
```

6. Browser membuka share sheet.
7. Operator memilih WhatsApp, mengecek penerima, lalu mengirim PDF.
8. Sistem dapat menampilkan instruksi atau tombol **Tandai Terkirim** jika send log manual sudah dibuat.

#### Skenario 2 - Desktop atau Browser Tidak Mendukung Share File

1. Owner klik **Kirim WhatsApp**.
2. Sistem mendeteksi file share tidak didukung.
3. Sistem menawarkan:
   - download/simpan PDF;
   - buka WhatsApp dengan caption otomatis.
4. Operator melampirkan PDF secara manual di WhatsApp Web.

#### Skenario 3 - Nomor PJ Mitra Kosong atau Tidak Valid

1. Tombol **Kirim WhatsApp** nonaktif atau menampilkan peringatan.
2. Sistem menampilkan pesan: `Nomor WA penanggung jawab mitra belum valid`.
3. Operator diarahkan memperbarui data di Master Mitra.

#### Skenario 4 - Transaksi Sudah Pernah Dikirim lalu Ada Koreksi

1. Operator mengedit/batalkan transaksi dari Riwayat Pengiriman.
2. Kwitansi berubah.
3. Sistem harus membuat file baru dengan label revisi, misalnya `Revisi 1`.
4. Tombol kirim ulang memberi caption:

```text
Kwitansi Sawit CB - Revisi
Kwitansi sebelumnya dikoreksi karena: salah input tonase.
Mohon gunakan file terbaru ini.
```

### Tantangan dan Risiko

1. **Salah kirim ke nomor yang salah**
   - Mitigasi: tampilkan nama PJ, nama mitra, nomor WA, dan preview caption sebelum membuka WhatsApp.

2. **Nomor tidak valid**
   - Mitigasi: normalisasi nomor, validasi minimal panjang nomor, dan blok tombol kirim jika tidak valid.

3. **File tidak ikut terkirim pada fallback WhatsApp Web**
   - Mitigasi: instruksi jelas: `PDF sudah diunduh, lampirkan file ini di WhatsApp`.

4. **Kwitansi berubah setelah dikirim**
   - Mitigasi: kirim ulang harus diberi label revisi dan alasan koreksi.

5. **Tidak ada bukti delivery otomatis pada MVP**
   - Mitigasi: send log manual dengan status `dibuka_wa`, `ditandai_terkirim`, atau `gagal`.

6. **API WhatsApp membutuhkan biaya dan setup**
   - Mitigasi: API penuh ditunda sampai volume transaksi dan kebutuhan tracking benar-benar membutuhkan.

7. **Data finansial tersebar melalui file**
   - Mitigasi: file hanya berisi data mitra terkait, tidak memuat margin/laba perusahaan, dan link file tidak dibuat publik permanen.

8. **Token API WhatsApp bocor jika implementasi API langsung dari frontend**
   - Mitigasi: jika memakai API, panggil hanya dari backend/Edge Function; frontend tidak boleh menyimpan token rahasia.

### Data Model Tambahan yang Disarankan

Untuk Tahap 2 add-on:

#### Tabel `kwitansi_mitra_send_log`

Field:

- id
- mitra_id
- periode_dari
- periode_sampai
- nomor_wa_tujuan
- nama_penerima
- file_url
- file_format: pdf, image
- total_tonase
- total_kotor
- total_panjar
- sisa_bayar
- status: draft, dibuka_wa, dibagikan, ditandai_terkirim, api_sent, api_failed, dibatalkan
- message_text
- revision_no
- alasan_revisi
- sent_by
- sent_at
- created_at

Acceptance:

- Setiap pengiriman WhatsApp tercatat minimal sebagai `dibuka_wa` atau `ditandai_terkirim`.
- Jika memakai API, status dikontrol dari response API dan webhook.
- File lama tidak ditimpa saat terjadi revisi; buat file baru dengan revision number.

### Acceptance Criteria Add-on

- Tombol **Cetak / Simpan PDF** tetap tersedia.
- Tombol **Kirim WhatsApp** muncul di halaman Kwitansi Mitra.
- Tombol **Kirim WhatsApp** hanya aktif jika mitra dipilih, transaksi tersedia, dan nomor WA valid.
- Sistem mengambil nomor dari `master_mitra.no_hp` dan menampilkan nama PJ jika tersedia.
- Caption WhatsApp otomatis berisi ringkasan kwitansi.
- Format utama file adalah PDF.
- Jika Web Share API file didukung, sistem mencoba membagikan PDF langsung.
- Jika tidak didukung, sistem fallback ke download/cetak PDF dan membuka `wa.me` dengan caption.
- Transaksi berstatus `dibatalkan` tidak masuk kwitansi yang dikirim.
- Admin biasa tidak menerima informasi laba/margin owner di file atau caption.

### Rujukan Teknis

- [WhatsApp Help Center - Click to Chat](https://faq.whatsapp.com/5913398998672934): link `wa.me/<nomor>` membuka chat dengan nomor internasional tanpa menyimpan kontak.
- [Meta WhatsApp Business Platform - Document Messages](https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/document-messages): Cloud API dapat mengirim file sebagai pesan dokumen.
- [MDN Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Share_API): browser dapat membagikan teks, link, dan file melalui share target perangkat jika didukung dan dipicu dari aksi pengguna.

> [!CAUTION]
> **ATURAN KERJA TAHAP 2 (SANGAT PENTING)**
> Karena sistem MVP ini **SUDAH LIVE** dan digunakan oleh Owner untuk mencatat data operasional asli, pengembangan Tahap 2 **DILARANG KERAS** menyentuh, merusak, atau menghapus struktur database MVP saat ini (`master_mitra`, `sopir`, `transaksi_mitra`, `panjar_mitra`, `harga_tbs`, dsb). 
> 
> Seluruh pengembangan fitur baru (Tahap 2) wajib:
> 1. Menggunakan database *Development* yang terpisah.
> 2. Menggunakan metode *Non-Destructive Migration* (hanya boleh menambah kolom/tabel baru).
> 3. Melakukan *Backup* database *Production* sebelum rilis fitur baru.

# PRD Final - Sawit CB

Tanggal konfirmasi klien: 11 Juli 2026, 06:12:40

## 1. Ringkasan Produk

Sawit CB adalah aplikasi operasional dan keuangan untuk bisnis RAM kelapa sawit. Sistem mencatat pembelian TBS dari petani lokal, stok sementara, pengiriman TBS ke pabrik, pengiriman TBS dari mitra, hutang/kasbon, biaya operasional, pembayaran pabrik, settlement mitra, dan laporan laba-rugi owner.

Pada versi final ini, sistem wajib memisahkan dua sumber TBS:

1. **Petani lokal**: pemasok individu yang menjual TBS langsung ke perusahaan. TBS ditimbang di timbangan perusahaan, dicatat sebagai stok sementara, dibayar oleh perusahaan, lalu dikirim ke pabrik.
2. **Mitra**: pengumpul/RAM kecil yang mengirim TBS ke pabrik atas nama perusahaan. Pabrik membayar ke perusahaan, lalu perusahaan membayar mitra berdasarkan berat final pabrik setelah dikurangi fee dan potongan yang disepakati.

## 2. Keputusan Final dari Klien

Keputusan berikut menjadi dasar final pengembangan sistem:

| Area | Keputusan |
| --- | --- |
| Fee perusahaan dari mitra | Selalu ada fee untuk perusahaan |
| Cara hitung Fee Owner dari mitra | Potongan nominal per kg |
| Dasar pembayaran ke mitra | Berat final yang diterima pabrik |
| Selisih berat mitra vs pabrik | Dibagi antara mitra dan perusahaan dengan persentase yang bisa diatur owner/super admin |
| Pembayaran pabrik | Per surat jalan / DO |
| Pembayaran ke mitra | Mitra langsung dibayar penuh setelah pabrik membayar |
| Panjar/uang muka mitra | Ada, tetapi hanya untuk mitra tertentu |
| Armada perusahaan dipakai mitra | Biaya selalu dipotong dari pembayaran mitra |
| Cara hitung biaya armada | Berdasarkan jarak, kemudian dihitung dengan tonase muatan |
| Pergantian sopir armada | Sopir yang dicatat di transaksi adalah sopir aktual saat pengiriman; relasi sopir-armada di master hanya default/riwayat |
| Hutang/kasbon mitra | Mitra bisa punya hutang/kasbon seperti petani |
| Data kendaraan mitra | Cukup nama sopir dan plat kendaraan jika ada |
| Stok TBS lokal | Perlu dicatat sebagai stok sementara |
| Pengiriman TBS lokal | Perlu detail transaksi petani dan total harian |
| Potongan pabrik | Sortasi/grading dan biaya timbang |
| Laba-rugi | Perlu dua versi: basis kas dan basis transaksi |
| Bukti pembayaran mitra | Perlu file PDF atau gambar untuk WhatsApp |
| Akses laporan keuntungan | Owner dan super admin saja |

Catatan: jawaban untuk laporan harian yang paling sering dibutuhkan tidak diberikan secara spesifik. Untuk v1 final, sistem memakai prioritas laporan harian default yang dijelaskan di bagian Laporan Harian dan dapat diubah oleh owner/super admin melalui Pengaturan Bisnis.

## 3. Dampak ke Produk

### 3.1 Dampak ke Alur Mitra

Alur mitra menjadi lebih pasti dan lebih ketat:

- Setiap pengiriman mitra wajib memiliki nomor DO atau tiket timbang.
- Pembayaran pabrik dicatat per DO.
- Hak mitra dihitung dari `tonase_dasar_settlement` yang berasal dari data pabrik, bukan berat timbang mitra.
- Fee perusahaan dihitung sebagai nominal per kg.
- Jika ada selisih berat antara timbang mitra dan timbang pabrik, sistem harus mencatat nilai selisih dan menghitung pembagian tanggungan berdasarkan persentase yang diatur owner/super admin.
- Jika `tonase_dasar_settlement` lebih besar dari timbang mitra, sistem tetap memakai data pabrik sebagai dasar pembayaran tetapi wajib menandai kondisi tersebut sebagai anomali rekonsiliasi.
- Setelah pabrik membayar per DO, settlement mitra dapat langsung dihitung dan dibayar penuh.
- Mitra tertentu boleh memiliki panjar/kasbon, sehingga perlu ledger hutang mitra.

### 3.2 Dampak ke Armada

Jika mitra memakai armada perusahaan:

- Biaya armada wajib menjadi potongan settlement mitra.
- Formula biaya armada harus mendukung komponen jarak, tonase, tarif default per armada, dan override manual jika diperlukan.
- Sistem perlu menyimpan jarak, tonase muatan, tarif, total biaya armada yang dipotong, dan sumber tarif yang dipakai.
- Biaya ini tidak boleh tercatat ganda sebagai pengurang laba jika sudah dipotong dari hak mitra.
- Sopir tidak boleh dianggap selalu melekat permanen pada satu armada, karena di lapangan sopir yang membawa mobil/armada bisa diganti.
- Master relasi sopir-armada hanya dipakai sebagai default/auto-fill. Setiap pengiriman wajib menyimpan sopir aktual dan snapshot nama/plat yang berlaku saat transaksi dibuat.
- Default mitra pada sopir/armada hanya dipakai untuk auto-fill. Setiap pengiriman mitra wajib menyimpan mitra transaksi yang bisa dioverride, terutama untuk armada bersama SL/BL atau armada tanpa afiliasi tetap.
- Jika sopir aktual berbeda dari sopir default armada, transaksi tetap sah tetapi harus mudah terlihat di laporan operasional dan audit perubahan.

### 3.3 Dampak ke Stok TBS Lokal

Karena TBS petani lokal perlu dicatat sebagai stok sementara:

- Pembelian dari petani lokal menambah stok TBS lokal.
- Pengiriman lokal ke pabrik mengurangi stok TBS lokal.
- Pengiriman lokal perlu bisa dikaitkan ke detail transaksi petani, serta tetap menyimpan total tonase harian.
- Sistem perlu laporan rekonsiliasi: TBS masuk dari petani, TBS keluar ke pabrik, dan sisa stok.

### 3.4 Dampak ke Laporan Keuangan

Laba-rugi perlu tersedia dalam dua cara:

1. **Basis kas**: hanya menghitung uang yang benar-benar sudah masuk dan keluar.
2. **Basis transaksi/akrual sederhana**: menghitung transaksi yang sudah terjadi walaupun uangnya belum dibayar.

Dashboard owner harus menampilkan **Laba Bersih Kas** sebagai angka utama karena paling mendekati uang nyata yang tersedia. **Laba Estimasi Transaksi** ditampilkan sebagai angka pembanding untuk melihat potensi margin dari transaksi yang belum selesai dibayar.

Laporan keuntungan hanya boleh dilihat oleh owner dan super admin.

### 3.5 Dampak ke Bukti Pembayaran

Settlement dan pembayaran mitra harus bisa dibuat menjadi bukti digital:

- PDF atau gambar.
- Format cocok untuk dikirim via WhatsApp.
- Berisi detail DO, tonase pabrik, harga, fee, potongan armada, potongan hutang/kasbon, total hak mitra, dan status pembayaran.

## 4. Role Pengguna

### Owner

- Melihat seluruh dashboard dan laporan.
- Melihat laporan keuntungan/laba-rugi.
- Mengatur harga, Fee Owner dari mitra, formula settlement, biaya, dan konfigurasi bisnis.
- Mengonfirmasi pembayaran pabrik.
- Mengonfirmasi pembayaran ke mitra.
- Melihat audit perubahan transaksi penting.
- Tidak dapat mengelola akun user dan role akses.

### Super Admin

- Memiliki akses penuh ke seluruh sistem.
- Boleh melihat laporan keuntungan/laba-rugi.
- Mengelola akun user dan role akses.
- Mengelola master data dan konfigurasi sistem.
- Perbedaan utama dengan owner: super admin dapat mengelola akun user, sedangkan owner tidak.
- Disarankan ada minimal dua akun super admin aktif agar perusahaan tetap bisa menonaktifkan akun karyawan jika salah satu super admin tidak tersedia.

### Admin Operasional

- Input transaksi TBS petani lokal.
- Input stok masuk dari petani lokal.
- Input pengiriman lokal ke pabrik.
- Input pengiriman dari mitra.
- Input data armada, sopir, pabrik, petani, dan mitra.
- Tidak boleh melihat laporan keuntungan/laba-rugi.

### Admin Keuangan

- Mencatat pembayaran pabrik.
- Mencatat pembayaran ke petani.
- Mencatat pembayaran dan settlement mitra.
- Mencatat hutang/kasbon petani dan mitra.
- Melihat laporan hutang, settlement, kas masuk, dan kas keluar.
- Tidak boleh melihat laporan keuntungan/laba-rugi kecuali diberi role super admin.

## 5. Entitas Utama

### Petani

Petani adalah pemasok individu yang menjual TBS langsung ke perusahaan.

Data minimal:

- Nama
- Nomor HP
- Alamat
- Nomor KTP, opsional
- Batas hutang/kasbon
- Status aktif/nonaktif

### Mitra

Mitra adalah pihak pengumpul/RAM kecil yang mengirim TBS ke pabrik atas nama perusahaan.

Data minimal:

- Nama mitra/usaha
- Penanggung jawab
- Nomor HP
- Alamat/lokasi timbang
- Nomor rekening, opsional
- Fee default per kg
- Status boleh panjar/kasbon
- Batas panjar/kasbon, opsional
- Persentase tanggungan selisih tonase, opsional jika berbeda dari default sistem
- Status aktif/nonaktif

### Armada Perusahaan

Armada milik/sewa perusahaan yang digunakan untuk pengiriman TBS lokal atau membantu pengiriman mitra.

Data minimal:

- Plat nomor
- Jenis kendaraan
- Kapasitas
- Kepemilikan
- Tarif default per km per ton
- Status tarif default aktif/nonaktif
- Sopir default/utama, opsional
- Status aktif/nonaktif

Catatan:

- Sopir default/utama hanya untuk mempercepat input dan bukan sumber kebenaran transaksi.
- Perubahan sopir default armada tidak boleh mengubah data sopir pada pengiriman lama.

### Sopir

Sopir adalah orang yang membawa armada perusahaan atau armada mitra pada pengiriman tertentu.

Data minimal:

- Nama
- Nomor HP, opsional
- Afiliasi: perusahaan, mitra, atau bebas/umum
- Mitra terkait, opsional jika sopir biasa membawa armada mitra tertentu
- Armada default, opsional
- Status aktif/nonaktif

Catatan:

- Satu sopir bisa membawa armada yang berbeda pada hari berbeda.
- Satu armada bisa dibawa sopir berbeda pada pengiriman berbeda.
- Sistem harus membedakan `sopir default` di master dari `sopir aktual` yang disimpan di transaksi.
- Afiliasi mitra pada master sopir boleh kosong untuk sopir/armada bersama. Mitra yang dipakai transaksi tetap dipilih pada saat input pengiriman.

### Armada Mitra

Armada yang digunakan oleh mitra. Sistem cukup mencatat data sederhana jika tersedia.

Data minimal:

- Plat kendaraan, opsional
- Nama sopir default, opsional
- Mitra pemilik

### Pabrik

Tujuan pengiriman TBS yang melakukan pembayaran ke perusahaan.

Data minimal:

- Nama pabrik
- Alamat
- Kontak
- Harga pabrik per kg jika tersedia
- Pola pembayaran per DO
- Informasi rekening atau referensi pembayaran, opsional

## 6. Alur Bisnis Final

### 6.1 Alur A - Petani Lokal ke Perusahaan

1. Admin mengatur harga beli TBS lokal.
2. Petani lokal membawa TBS ke lokasi perusahaan.
3. TBS ditimbang di timbangan perusahaan.
4. Sistem mencatat berat kotor, potongan, berat bersih, harga beli, total beli, potong hutang jika ada, dan bayar tunai.
5. Transaksi pembelian menambah stok sementara TBS lokal.
6. Perusahaan membayar petani.
7. Saat TBS dikirim ke pabrik, admin membuat pengiriman lokal.
8. Pengiriman lokal wajib dapat dikaitkan ke detail transaksi petani atau kelompok transaksi harian.
9. Pengiriman lokal mengurangi stok sementara.
10. Pabrik membayar ke perusahaan per DO.
11. Pendapatan masuk ke laporan laba-rugi perusahaan.

### 6.2 Alur B - Mitra Mengirim Sendiri ke Pabrik

1. Mitra membeli atau mengumpulkan TBS dari sumbernya sendiri.
2. Mitra menimbang TBS di tempat mitra.
3. Mitra mengirim ke pabrik atas nama perusahaan.
4. Admin mencatat pengiriman mitra:
   - Mitra
   - Tanggal kirim
   - Pabrik tujuan
   - Nomor DO/tiket timbang
   - Tonase timbang mitra
   - Tonase final pabrik
   - Nama sopir aktual mitra, jika ada
   - Plat kendaraan mitra, jika ada
   - Catatan pergantian sopir jika sopir aktual berbeda dari default armada/mitra
5. Pabrik membayar ke perusahaan per DO.
6. Sistem menghitung hak mitra memakai `tonase_dasar_settlement` dari data pabrik.
7. Fee perusahaan dipotong nominal per kg.
8. Potongan pabrik yang dicatat minimal sortasi/grading dan biaya timbang.
9. Selisih tonase mitra vs pabrik dihitung dan dibagi berdasarkan persentase tanggungan yang berlaku.
10. Setelah pabrik membayar, mitra dibayar penuh sesuai settlement.
11. Settlement menjadi lunas setelah pembayaran mitra dicatat.

### 6.3 Alur C - Mitra Memakai Armada Perusahaan

1. Mitra meminta bantuan armada perusahaan.
2. Admin membuat pengiriman mitra dengan pilihan armada perusahaan.
3. Sistem mengambil tarif default armada, lalu admin mencatat armada, sopir aktual, jarak, tonase muatan, tarif yang dipakai, dan total biaya armada.
4. Biaya armada wajib dipotong dari hak mitra.
5. Saat settlement, biaya armada tampil sebagai potongan.
6. Laporan membedakan:
   - Biaya operasional perusahaan murni
   - Biaya bantuan mitra
   - Potongan armada dari settlement mitra
   - Margin bersih dari pengiriman mitra

## 7. Rumus Settlement Mitra

Catatan satuan:

- Semua berat TBS untuk pembelian, pengiriman, timbang mitra, timbang pabrik, stok, dan settlement disimpan dalam **kg**.
- Tampilan UI boleh menampilkan ton untuk kemudahan baca, tetapi penyimpanan dan perhitungan harga per kg wajib memakai kg.
- Perhitungan biaya armada memakai ton, sehingga `tonase_muatan_ton = tonase_muatan_kg / 1000`.
- Dalam formula settlement, `tonase_timbang_mitra` adalah nilai `tonase_timbang_sumber` untuk pengiriman mitra.
- Dalam formula settlement, `tonase_final_pabrik` adalah nilai `tonase_pabrik` pada data model.

### 7.1 Input Settlement

- Mitra
- Mitra transaksi, dapat dioverride dari default master sopir/armada
- Nomor DO
- Pabrik
- Tanggal kirim
- Tonase timbang mitra
- Tonase final pabrik
- Tonase dasar settlement
- Selisih tonase
- Persentase selisih ditanggung perusahaan
- Persentase selisih ditanggung mitra
- Koreksi nilai selisih
- Harga pabrik per kg
- Total pembayaran pabrik
- Potongan pabrik: sortasi/grading, tipe sortasi, nilai sortasi, biaya timbang
- Fee perusahaan per kg
- Total fee perusahaan
- Potongan armada perusahaan, jika ada
- Potongan hutang/kasbon mitra, jika ada
- Potongan lain, jika ada
- Total hak mitra
- Jumlah dibayar ke mitra
- Status settlement

### 7.2 Formula Dasar

```text
Tonase dasar settlement =
  jika potongan_sortasi_type = kg:
    tonase_final_pabrik - potongan_sortasi_value
  jika potongan_sortasi_type = none, percent, atau nominal:
    tonase_final_pabrik

Potongan sortasi rupiah =
  jika potongan_sortasi_type = none:
    0
  jika potongan_sortasi_type = kg:
    0
  jika potongan_sortasi_type = percent:
    (tonase_dasar_settlement x harga_pabrik_per_kg) x (potongan_sortasi_value / 100)
  jika potongan_sortasi_type = nominal:
    potongan_sortasi_value

Total bruto pabrik = tonase_dasar_settlement x harga_pabrik_per_kg

Total potongan pabrik =
  potongan_sortasi_rupiah
  + biaya_timbang
  + potongan_pabrik_lain

Total pembayaran pabrik = total_bruto_pabrik - total_potongan_pabrik

Fee perusahaan = tonase_dasar_settlement x fee_per_kg

Selisih tonase = tonase_timbang_mitra - tonase_dasar_settlement

Nilai selisih tonase = abs(selisih_tonase) x harga_pabrik_per_kg

Jika tonase_timbang_mitra > tonase_dasar_settlement:
  koreksi_selisih_dibayar_perusahaan =
    nilai_selisih_tonase x (persentase_selisih_ditanggung_perusahaan / 100)

Jika tonase_timbang_mitra <= tonase_dasar_settlement:
  koreksi_selisih_dibayar_perusahaan = 0

Biaya armada dasar =
  jarak_km x tonase_muatan_ton x tarif_armada_per_km_per_ton

Biaya armada mitra memakai armada perusahaan =
  max(biaya_armada_dasar, minimum_charge)

Total potongan mitra =
  fee_perusahaan
  + potongan_armada_perusahaan
  + potongan_hutang_kasbon_mitra
  + potongan_lain

Hak mitra final = total_pembayaran_pabrik - total_potongan_mitra
  + koreksi_selisih_dibayar_perusahaan

Margin perusahaan dari mitra =
  fee_perusahaan
  + potongan_armada_perusahaan
  - koreksi_selisih_dibayar_perusahaan
  - biaya_aktual_armada_perusahaan
```

Validasi angka:

- `minimum_charge` default bernilai 0 jika tidak diisi.
- `tonase_dasar_settlement` tidak boleh kurang dari 0.
- `total_pembayaran_pabrik` tidak boleh kurang dari 0.
- `hak_mitra_final` tidak boleh kurang dari 0, kecuali owner/super admin menyetujui sebagai kasus koreksi khusus.
- Semua nilai persentase disimpan dalam angka 0 sampai 100.
- Semua hasil rupiah dibulatkan ke rupiah terdekat tanpa desimal.

### 7.3 Selisih Berat Mitra vs Pabrik

Sistem wajib mencatat:

- Tonase timbang mitra.
- Tonase final pabrik.
- Selisih tonase.
- Nilai rupiah selisih.
- Persentase tanggungan perusahaan.
- Persentase tanggungan mitra.
- Koreksi nilai selisih yang masuk ke settlement.

Untuk v1 final, pembayaran utama memakai `tonase_dasar_settlement`. Jika tonase timbang mitra lebih besar dari `tonase_dasar_settlement`, selisih susut dibagi berdasarkan persentase tanggungan. Default awal disarankan 50% ditanggung perusahaan dan 50% ditanggung mitra, tetapi owner/super admin dapat mengubah default global atau mengatur khusus per mitra.

Jika `tonase_dasar_settlement` lebih besar dari tonase timbang mitra, sistem tetap memakai `tonase_dasar_settlement` sebagai dasar pembayaran. Selisih lebih dicatat sebagai informasi rekonsiliasi, tanpa koreksi otomatis kecuali owner/super admin mengisi koreksi manual.

Kondisi `tonase_dasar_settlement > tonase_timbang_mitra` wajib diberi tanda anomali jika selisihnya melewati toleransi yang diatur owner/super admin. Default toleransi awal adalah 0 kg, artinya setiap selisih lebih tetap ditandai untuk ditinjau. Jika pola anomali berulang pada mitra yang sama, laporan mitra harus menampilkan peringatan rekonsiliasi.

## 8. Modul Produk

### 8.1 Dashboard

Dashboard menampilkan ringkasan operasional sendiri dan mitra secara terpisah.

Kartu utama:

- TBS petani lokal masuk hari ini
- Stok sementara TBS lokal
- TBS lokal keluar ke pabrik hari ini
- TBS mitra masuk pabrik hari ini
- Total tonase ke pabrik hari ini
- Pembayaran pabrik menunggu diterima
- Settlement mitra menunggu dibayar
- Hutang/kasbon petani aktif
- Hutang/kasbon mitra aktif
- Biaya operasional hari ini
- Laba Bersih Kas owner, hanya untuk owner/super admin
- Laba Estimasi Transaksi owner, hanya untuk owner/super admin

Filter:

- Hari ini
- Mingguan
- Bulanan
- Sumber TBS: petani lokal, mitra, semua
- Pabrik
- Mitra

### 8.2 Master Petani

Fungsi:

- Tambah/edit/nonaktifkan petani.
- Set batas hutang/kasbon.
- Melihat riwayat transaksi petani.
- Melihat saldo hutang petani.

Acceptance criteria:

- Petani tidak tercampur dengan mitra.
- Petani hanya muncul di form transaksi pembelian lokal.
- Hutang petani dihitung dari ledger tunggal.

### 8.3 Master Mitra

Fungsi:

- Tambah/edit/nonaktifkan mitra.
- Set fee default per kg.
- Set riwayat fee per kg berdasarkan tanggal/jam berlaku.
- Tandai apakah mitra boleh panjar/kasbon.
- Set batas panjar/kasbon jika diperlukan.
- Melihat riwayat pengiriman, settlement, dan hutang/kasbon.

Acceptance criteria:

- Mitra tidak muncul di form transaksi petani lokal.
- Mitra muncul di form pengiriman mitra.
- Setiap mitra memiliki ringkasan tonase, nilai pabrik, fee, hak mitra, sudah dibayar, sisa bayar, dan saldo hutang/kasbon.

### 8.4 Harga TBS Lokal

Fungsi:

- Set harga beli TBS lokal berdasarkan tanggal/jam berlaku.
- Riwayat harga.

Acceptance criteria:

- Harga beli petani lokal tidak selalu sama dengan harga pabrik.
- Transaksi pembelian lokal tidak bisa disimpan jika belum ada harga yang berlaku pada waktu transaksi.
- Jika harga berubah lebih dari satu kali dalam sehari, transaksi mengambil harga terbaru yang `berlaku_mulai`-nya paling dekat tetapi tidak melebihi waktu transaksi.
- Override harga pada form transaksi hanya boleh dilakukan owner/super admin atau admin yang diberi otorisasi, dan wajib masuk audit log.

### 8.5 Input TBS Petani Lokal

Fungsi:

- Pilih petani.
- Input berat kotor dan potongan.
- Ambil harga beli harian.
- Hitung berat bersih dan total harga.
- Potong hutang petani jika ada.
- Simpan transaksi.
- Tambahkan berat bersih ke stok sementara.
- Cetak struk.

Acceptance criteria:

- Nomor struk harus unik walaupun ada input bersamaan.
- Potongan hutang harus tercatat satu kali di ledger hutang.
- Transaksi yang sudah masuk pengiriman tidak boleh diubah sembarangan tanpa audit.

### 8.6 Stok Sementara TBS Lokal

Fungsi:

- Menampilkan stok awal, TBS masuk dari petani, TBS keluar ke pabrik, koreksi, dan sisa stok.
- Menghubungkan pengiriman lokal dengan transaksi petani.
- Menyediakan bantuan alokasi FIFO berdasarkan tanggal transaksi, tetapi admin tetap bisa memilih transaksi petani secara manual.
- Mencatat koreksi stok jika ada selisih timbang.
- Menyediakan stock opname/adjustment untuk mencatat susut stok lokal karena penyimpanan, penguapan, atau koreksi fisik.

Acceptance criteria:

- Pembelian petani menambah stok.
- Pengiriman lokal mengurangi stok.
- Sistem bisa menunjukkan detail petani yang masuk ke pengiriman tertentu.
- Default alokasi stok memakai FIFO dari transaksi petani yang belum terkirim, lalu bisa disesuaikan manual sebelum pengiriman disimpan.
- Total alokasi satu transaksi petani ke satu atau beberapa pengiriman tidak boleh melebihi berat bersih transaksi tersebut.
- Stok tidak boleh minus tanpa otorisasi owner/super admin.
- Stock opname membuat baris ledger koreksi, tidak mengubah atau menghapus transaksi pembelian/pengiriman lama.

### 8.7 Pengiriman Lokal ke Pabrik

Fungsi:

- Pilih tanggal.
- Pilih pabrik.
- Pilih armada dan sopir aktual perusahaan.
- Pilih detail transaksi petani atau kelompok transaksi harian.
- Input total tonase kirim.
- Input nomor DO.
- Update tonase final pabrik.
- Update harga pabrik, potongan pabrik, dan pembayaran pabrik.

Acceptance criteria:

- Pengiriman lokal mengurangi stok sementara.
- Nomor DO tidak boleh duplikat untuk pabrik yang sama lintas sumber lokal/mitra, kecuali transaksi masih berstatus draft dan belum dikirim.
- Status pembayaran pabrik jelas per DO.
- Pendapatan dari pengiriman lokal masuk ke laporan laba-rugi.
- Sortasi pabrik pada pengiriman lokal harus tampil sebagai kerugian/potongan kualitas pada laporan owner agar owner dapat mengevaluasi grading saat beli dari petani.

### 8.8 Pengiriman Mitra ke Pabrik

Fungsi:

- Pilih mitra.
- Pilih pabrik.
- Input tanggal kirim.
- Input nomor DO/tiket timbang.
- Input tonase timbang mitra.
- Input tonase final pabrik.
- Input atau pilih sopir aktual dan plat kendaraan mitra jika ada.
- Pilih armada: armada mitra atau armada perusahaan.
- Jika armada perusahaan, input jarak, tonase muatan, tarif, dan total potongan armada.
- Update pembayaran pabrik per DO.

Acceptance criteria:

- Operasional mitra tidak masuk ke biaya perusahaan kecuali armada perusahaan digunakan.
- Pembayaran pabrik masuk ke perusahaan.
- Nomor DO tidak boleh duplikat untuk pabrik yang sama lintas sumber lokal/mitra, kecuali transaksi masih berstatus draft dan belum dikirim.
- Setelah pabrik membayar, sistem membuat atau mengupdate settlement mitra.
- Hak mitra dihitung berdasarkan `tonase_dasar_settlement`.
- Sopir dan plat kendaraan pada pengiriman disimpan sebagai snapshot sehingga perubahan master sopir/armada tidak mengubah histori DO lama.
- Jika sopir aktual berbeda dari sopir default armada, laporan operasional tetap menampilkan armada, sopir default, dan sopir aktual.

### 8.9 Settlement Mitra

Fungsi:

- Melihat daftar settlement per mitra dan per DO.
- Menghitung hak mitra.
- Mencatat pembayaran penuh ke mitra.
- Mencatat potongan fee per kg.
- Mencatat potongan armada perusahaan.
- Mencatat potongan hutang/kasbon mitra.
- Membuat bukti settlement PDF atau gambar untuk WhatsApp.

Acceptance criteria:

- Settlement dibuat per DO.
- Settlement memiliki status: belum dihitung, menunggu pembayaran pabrik, menunggu bayar mitra, sebagian/koreksi, lunas, dibatalkan.
- Karena keputusan klien adalah mitra dibayar penuh, pembayaran sebagian tidak menjadi alur utama v1 final dan hanya dipakai untuk kasus koreksi/pengecualian.
- Owner/super admin/admin keuangan dapat melihat sisa kewajiban ke mitra.
- Laporan per mitra menunjukkan semua DO, pembayaran pabrik, fee, potongan, pembayaran ke mitra, dan sisa bayar.
- Admin keuangan boleh melihat rincian fee dan potongan settlement karena dibutuhkan untuk menjelaskan pembayaran ke mitra. Pembatasan laba-rugi tetap berlaku pada ringkasan margin/laba owner.

### 8.10 Hutang/Kasbon Petani

Fungsi:

- Tambah kasbon/panjar/pupuk/lainnya.
- Bayar tunai.
- Potong dari transaksi TBS.
- Riwayat debit/kredit.

Acceptance criteria:

- Saldo hutang dihitung dari ledger tunggal.
- Tidak ada double count antara transaksi dan log pembayaran.

### 8.11 Hutang/Kasbon Mitra

Fungsi:

- Menandai mitra yang boleh panjar/kasbon.
- Tambah panjar/kasbon mitra.
- Bayar tunai.
- Potong dari settlement mitra.
- Riwayat debit/kredit.

Acceptance criteria:

- Hutang mitra dihitung dari ledger tunggal.
- Potongan hutang mitra pada settlement tercatat satu kali.
- Mitra yang tidak diizinkan panjar/kasbon tidak bisa diberi kasbon tanpa otorisasi owner/super admin.

### 8.12 Biaya Operasional

Fungsi:

- Catat biaya perusahaan: solar, gaji sopir, kuli, retribusi, perawatan, lainnya.
- Tandai biaya sebagai:
  - Biaya perusahaan murni
  - Biaya bantuan mitra yang akan dipotong dari settlement
- Catat biaya aktual armada perusahaan jika membantu mitra.

Acceptance criteria:

- Biaya bantuan mitra tidak mengurangi laba dua kali jika sudah dipotong di settlement.
- Laporan memisahkan biaya perusahaan dan biaya bantuan mitra.

### 8.13 Pembayaran Pabrik

Fungsi:

- Mencatat pembayaran pabrik per DO.
- Mendukung satu pembayaran/transfer pabrik untuk satu DO atau beberapa DO.
- Mencatat harga pabrik per kg.
- Mencatat tonase final pabrik.
- Mencatat sortasi/grading sebagai tidak ada, kg, persentase, atau nominal rupiah.
- Mencatat biaya timbang.
- Mencatat tanggal pembayaran dan metode pembayaran.

Acceptance criteria:

- Satu DO memiliki status pembayaran yang jelas.
- Satu DO tidak boleh dialokasikan pembayaran melebihi nilai tagihannya.
- Potongan sortasi/grading harus dinormalisasi sebelum masuk perhitungan: tipe `kg` mengurangi `tonase_dasar_settlement`, sedangkan tipe `percent` dan `nominal` menjadi `potongan_sortasi_rupiah`.
- Jika tidak ada sortasi/grading atau pabrik sudah memberi tonase net/final, `potongan_sortasi_type` wajib bernilai `none`.
- Jika potongan sortasi/grading memakai tipe `percent`, nilainya disimpan sebagai angka 0 sampai 100.
- Jika pabrik sudah memberikan tonase final setelah potongan sortasi kg, admin tidak boleh menginput sortasi kg lagi agar tidak terjadi double count.
- Jika pabrik memberikan tonase bruto dan potongan sortasi kg secara terpisah, sistem menghitung `tonase_dasar_settlement = tonase_final_pabrik - potongan_sortasi_kg`.
- `total_pembayaran_pabrik` pada pengiriman/settlement adalah nilai final DO atau nilai tagihan pabrik setelah potongan, bukan bukti uang sudah diterima.
- Uang pabrik yang benar-benar sudah diterima dihitung dari alokasi pada `pembayaran_pabrik_detail`.
- Pembayaran pabrik menjadi dasar settlement mitra.
- Pembayaran pabrik menjadi dasar laporan kas dan laba-rugi.

### 8.14 Bukti Pembayaran Mitra

Fungsi:

- Generate bukti pembayaran dalam format PDF atau gambar.
- Format mudah dikirim via WhatsApp.
- Memuat identitas perusahaan, mitra, DO, pabrik, tonase, harga, fee, potongan, total hak mitra, dan status lunas.

Acceptance criteria:

- Bukti dapat dibuat setelah pembayaran mitra dicatat.
- Nomor bukti unik.
- Bukti dapat dicetak ulang atau diunduh ulang.

### 8.15 Laporan

#### Laporan Harian

Isi:

- TBS lokal masuk
- Stok lokal sementara
- Pengiriman lokal
- Pengiriman mitra
- Pembayaran pabrik
- Pembayaran ke petani
- Pembayaran ke mitra
- Biaya operasional
- Total kas keluar/masuk

Prioritas tampilan laporan harian:

1. Kas masuk dan kas keluar hari ini
2. TBS lokal masuk dan stok lokal
3. Pengiriman ke pabrik per DO
4. Settlement mitra yang menunggu bayar
5. Hutang/kasbon petani dan mitra
6. Ringkasan margin owner, hanya untuk owner/super admin

#### Laporan Petani

Isi:

- Riwayat transaksi TBS
- Hutang/kasbon
- Potongan hutang
- Total pembayaran

#### Laporan Mitra

Isi:

- Riwayat DO/pengiriman
- Tonase mitra vs tonase pabrik
- Tonase dasar settlement
- Selisih tonase
- Koreksi selisih tonase
- Pembayaran pabrik ke perusahaan
- Fee per kg
- Potongan armada
- Potongan hutang/kasbon
- Hak mitra
- Sudah dibayar
- Sisa bayar

#### Laporan Pabrik

Isi:

- Semua pengiriman atas nama perusahaan
- Sumber: lokal atau mitra
- Nomor DO
- Tonase
- Harga pabrik
- Sortasi/grading
- Tipe dan nilai sortasi/grading
- Biaya timbang
- Total pembayaran
- Status pembayaran

#### Laporan Stok Lokal

Isi:

- Stok awal
- TBS masuk dari petani
- TBS keluar ke pabrik
- Koreksi stok
- Sisa stok
- Detail transaksi petani yang terkait dengan pengiriman

#### Laba-Rugi Owner

Laporan ini hanya boleh diakses oleh owner dan super admin.

Minimal memisahkan:

- Pendapatan pengiriman lokal
- Pendapatan pengiriman mitra
- Pembelian TBS lokal
- Hak mitra
- Fee perusahaan dari mitra
- Biaya operasional perusahaan
- Biaya bantuan mitra
- Potongan armada mitra
- Margin bersih perusahaan

Mode laporan:

- Basis kas
- Basis transaksi

Aturan tampilan:

- **Laba Bersih Kas** menjadi angka utama di dashboard owner karena menunjukkan uang yang benar-benar sudah masuk/keluar.
- **Laba Estimasi Transaksi** menjadi angka pembanding karena memasukkan transaksi yang sudah terjadi tetapi belum selesai dibayar.
- Label laporan harus selalu menampilkan basis perhitungan agar owner tidak bingung membedakan uang nyata dan estimasi.

Aturan pengakuan laba-rugi:

- **Laba Bersih Kas** = pembayaran pabrik yang sudah diterima - pembayaran TBS petani yang sudah keluar - pembayaran mitra yang sudah keluar - biaya operasional yang sudah dibayar.
- **Laba Estimasi Transaksi** = nilai DO/pengiriman yang sudah memiliki tonase dan harga final - nilai pembelian TBS lokal - hak mitra - biaya operasional tercatat.
- Kasbon/panjar petani dan mitra bukan biaya laba-rugi. Kasbon/panjar ditampilkan sebagai piutang/kasbon aktif dan memengaruhi kas tersedia, tetapi tidak langsung mengurangi laba sampai dipotong/dikoreksi sesuai transaksi.
- Jika harga pabrik atau tonase final belum tersedia, transaksi boleh masuk estimasi hanya jika diberi label `estimasi`.

### 8.16 Pengaturan Bisnis

Fungsi:

- Mengatur fee default perusahaan per kg untuk mitra.
- Mengatur riwayat fee per kg per mitra berdasarkan tanggal/jam berlaku.
- Mengatur persentase default pembagian selisih tonase antara perusahaan dan mitra.
- Mengatur persentase khusus per mitra jika berbeda dari default sistem.
- Mengatur tarif default per armada berdasarkan km dan tonase.
- Mengatur tanggal berlaku tarif armada.
- Mengatur apakah tarif armada boleh dioverride pada pengiriman tertentu.
- Mengatur batas hutang/kasbon per mitra.
- Mengatur tindakan jika kasbon melebihi batas: blokir otomatis atau wajib approval owner/super admin.
- Mengatur prioritas kartu dashboard dan laporan harian.
- Mengatur toleransi anomali saat `tonase_dasar_settlement` lebih besar dari timbang mitra.

Acceptance criteria:

- Persentase selisih tonase perusahaan + mitra harus selalu 100%.
- Persentase disimpan dalam angka 0 sampai 100.
- Default awal pembagian selisih tonase adalah 50% perusahaan dan 50% mitra, kecuali owner/super admin mengubahnya.
- Tarif armada memakai satuan `tarif per km per ton`.
- Jarak armada disimpan dalam km dan tonase muatan disimpan dalam ton.
- Override tarif armada wajib menyimpan alasan dan masuk audit log.
- Kasbon mitra yang melewati batas tidak bisa disimpan tanpa approval sesuai pengaturan bisnis.
- Tindakan kasbon melebihi batas wajib bernilai salah satu: `blokir_otomatis` atau `wajib_approval`.
- Untuk v1, approval memakai mekanisme langsung berbasis role: admin biasa tidak bisa menyimpan aksi khusus, sedangkan owner/super admin dapat menyimpan dengan alasan approval yang wajib masuk audit log.
- Sistem tidak wajib menyediakan antrean approval terpisah pada v1, kecuali nanti diputuskan sebagai pengembangan lanjutan.
- Owner dan super admin bisa mengelola pengaturan bisnis.
- Admin operasional dan admin keuangan hanya bisa melihat pengaturan yang diperlukan untuk input transaksi.

### 8.17 Pembatalan dan Koreksi Transaksi

Fungsi:

- Membatalkan transaksi pembelian, pengiriman, pembayaran, settlement, hutang/kasbon, dan biaya operasional dengan alasan.
- Membuat reversal ledger untuk stok dan hutang/kasbon.
- Menyimpan audit log sebelum/sesudah pembatalan atau koreksi.

Acceptance criteria:

- Transaksi yang sudah berdampak ke stok, hutang, kas, atau settlement tidak boleh dihapus fisik dari database.
- Pembatalan harus membuat transaksi pembalik/reversal atau mengubah status menjadi dibatalkan dengan referensi reversal.
- Reversal stok memakai baris baru di `stok_tbs_lokal_ledger`.
- Reversal hutang/kasbon memakai baris baru di `hutang_ledger`.
- Pembatalan pembayaran pabrik atau mitra mengubah status pembayaran dan membatalkan alokasi/efek kas terkait.
- Aksi batal dan koreksi wajib dilakukan oleh owner/super admin atau role yang diberi otorisasi, serta wajib masuk audit log.

## 9. Status

### Status Pengiriman Lokal

- Draft
- Stok siap kirim
- Dikirim
- Diterima pabrik
- Dibayar pabrik
- Selesai
- Dibatalkan

### Status Pengiriman Mitra

- Dikirim mitra
- Diterima pabrik
- Menunggu pembayaran pabrik
- Sudah dibayar pabrik ke perusahaan
- Menunggu pembayaran mitra
- Pembayaran mitra sebagian/koreksi
- Settlement lunas
- Dibatalkan

### Status Settlement Mitra

- Belum dihitung
- Menunggu pembayaran pabrik
- Menunggu bayar mitra
- Sebagian/koreksi
- Lunas
- Dibatalkan

### Status Pembayaran Pabrik

- Draft
- Teralokasi sebagian
- Teralokasi penuh
- Dibatalkan

### Status Pembayaran Mitra

- Draft
- Dibayar
- Sebagian/koreksi
- Dibatalkan

### Status Transaksi Umum

- Aktif
- Menunggu approval langsung
- Disetujui
- Dibatalkan
- Direversal

## 10. Rekomendasi Data Model

### Tabel `petani`

Field:

- id
- nama
- no_hp
- alamat
- nomor_ktp
- batas_kasbon
- aktif
- created_at

### Tabel `mitra`

Field:

- id
- nama
- penanggung_jawab
- no_hp
- alamat
- rekening
- fee_per_kg
- boleh_kasbon
- batas_kasbon
- persen_selisih_ditanggung_perusahaan
- persen_selisih_ditanggung_mitra
- aktif
- created_at

Catatan:

- `fee_per_kg` pada master mitra dipakai sebagai nilai default/current untuk tampilan cepat.
- Perhitungan settlement wajib memakai `fee_mitra_history` yang berlaku pada tanggal pengiriman/DO.

### Tabel `pabrik`

Field:

- id
- nama
- alamat
- kontak
- rekening
- pola_pembayaran: per_do
- harga_default_per_kg
- aktif
- created_at

### Tabel `armada_perusahaan`

Field:

- id
- plat_nomor
- jenis_kendaraan
- kapasitas_kg
- kepemilikan
- aktif
- created_at

Catatan:

- Relasi sopir default dapat disimpan di tabel `sopir` atau tabel assignment terpisah; fungsinya hanya membantu auto-fill saat input.
- Perhitungan biaya armada tetap melekat ke armada, bukan ke sopir default.

### Tabel `sopir`

Field:

- id
- nama
- no_hp
- tipe_sopir: perusahaan, mitra, umum
- mitra_id
- armada_default_id
- aktif
- created_at

Catatan:

- `armada_default_id` bersifat opsional dan boleh berubah.
- Histori pengiriman tidak boleh bergantung pada nilai `armada_default_id` terbaru.

### Tabel `armada_mitra`

Field:

- id
- mitra_id
- plat_kendaraan
- nama_sopir
- no_hp_sopir
- aktif
- created_at

### Tabel `harga_tbs_lokal`

Field:

- id
- harga_per_kg
- berlaku_mulai
- berlaku_sampai
- aktif
- created_by
- created_at

Catatan:

- Harga yang dipakai transaksi adalah harga aktif dengan `berlaku_mulai` paling dekat tetapi tidak melebihi waktu transaksi.
- Perubahan harga tidak boleh mengubah transaksi lama yang sudah tersimpan.

### Tabel `fee_mitra_history`

Field:

- id
- mitra_id
- fee_per_kg
- berlaku_mulai
- berlaku_sampai
- aktif
- created_by
- created_at

Catatan:

- Fee settlement diambil dari riwayat fee yang berlaku pada tanggal pengiriman/DO, bukan dari nilai master mitra terbaru.
- Perubahan fee tidak boleh mengubah settlement lama.

### Tabel `tarif_armada`

Field:

- id
- armada_id
- tarif_per_km_per_ton
- minimum_charge
- berlaku_mulai
- berlaku_sampai
- aktif
- created_by
- created_at

### Tabel `transaksi_beli_tbs`

Field:

- id
- nomor_struk
- petani_id
- tanggal
- berat_kotor_kg
- potongan_kg
- berat_bersih_kg
- harga_per_kg
- total_harga
- potongan_hutang
- total_bayar_petani
- status
- created_by
- created_at

Catatan:

- `nomor_struk` harus unik.
- Transaksi pembelian membuat baris masuk di `stok_tbs_lokal_ledger`.
- Jika transaksi dibatalkan, stok dan hutang/kasbon dibalik memakai reversal ledger.

### Tabel `pengiriman`

Field utama/tambahan:

- sumber: lokal, mitra
- pabrik_id
- mitra_id
- tanggal_kirim
- nomor_do
- tonase_timbang_sumber
- tonase_pabrik
- tonase_dasar_settlement
- selisih_tonase
- nilai_selisih_tonase
- persen_selisih_ditanggung_perusahaan
- persen_selisih_ditanggung_mitra
- koreksi_selisih_dibayar_perusahaan
- harga_pabrik_per_kg
- potongan_sortasi_type: none, kg, percent, nominal
- potongan_sortasi_value
- potongan_sortasi_rupiah
- biaya_timbang
- potongan_pabrik_lain
- total_pembayaran_pabrik
- armada_type: perusahaan, mitra
- armada_perusahaan_id
- sopir_aktual_id
- sopir_aktual_nama
- sopir_aktual_no_hp
- sopir_aktual_source: master, manual
- sopir_diganti_dari_default
- kendaraan_mitra_text
- sopir_mitra_text
- jarak_armada_km
- tonase_muatan_armada_ton
- tarif_armada_per_km_per_ton
- tarif_armada_source: default, override
- alasan_override_tarif_armada
- biaya_armada_dibebankan_ke_mitra
- biaya_aktual_armada_perusahaan
- settlement_id
- status
- created_by
- created_at

Catatan:

- Jika `sumber = lokal`, maka `mitra_id` wajib kosong.
- Jika `sumber = mitra`, maka `mitra_id` wajib terisi.
- `nomor_do` harus unik untuk `pabrik_id` ketika status bukan draft, lintas sumber lokal dan mitra.
- Validasi alokasi stok lokal harus memakai transaksi database agar dua admin tidak bisa mengalokasikan stok yang sama secara bersamaan.
- V1 mendukung satu tipe sortasi utama per DO melalui `potongan_sortasi_type`. Jika pabrik memberikan beberapa komponen potongan sekaligus, komponen tambahan dicatat pada `potongan_pabrik_lain` sebagai nominal.
- Untuk armada perusahaan, `armada_perusahaan_id` adalah armada yang dipakai, sedangkan `sopir_aktual_id`/snapshot nama adalah sopir yang benar-benar membawa armada pada DO tersebut.
- Untuk armada mitra, sistem boleh memakai `sopir_mitra_text`/`kendaraan_mitra_text` jika sopir atau kendaraan tidak perlu dimasterkan.
- `mitra_id` pada pengiriman adalah mitra transaksi final untuk DO tersebut, bukan sekadar turunan permanen dari default sopir/armada.
- Perubahan master sopir, armada, atau relasi default setelah transaksi dibuat tidak boleh mengubah snapshot sopir/plat pada pengiriman lama.

### Tabel `stok_tbs_lokal_ledger`

Field:

- id
- tanggal
- tipe: masuk, keluar, koreksi
- sumber: pembelian_petani, pengiriman_pabrik, koreksi_manual
- transaksi_beli_id
- pengiriman_id
- berat_kg
- keterangan
- created_by
- created_at

Catatan:

- Saldo stok dihitung dari ledger, bukan disimpan manual sebagai angka utama.
- Koreksi stok dan pembatalan transaksi harus membuat baris ledger baru, bukan mengubah/menghapus baris lama.

### Tabel `pengiriman_lokal_detail`

Field:

- id
- pengiriman_id
- transaksi_beli_id
- petani_id
- berat_alokasi_kg
- created_at

Catatan:

- Satu transaksi petani boleh dialokasikan ke lebih dari satu pengiriman jika diperlukan.
- Total `berat_alokasi_kg` untuk satu `transaksi_beli_id` tidak boleh melebihi berat bersih transaksi pembelian petani.

### Tabel `pembayaran_pabrik`

Field:

- id
- pabrik_id
- tanggal_bayar
- total_bayar
- metode
- rekening_tujuan
- referensi_transfer
- bukti_transfer_url
- status
- keterangan
- created_by
- created_at

Catatan:

- Satu pembayaran pabrik dapat membayar satu DO atau beberapa DO.
- Total alokasi pada detail pembayaran tidak boleh melebihi `total_bayar`.
- `total_bayar` adalah uang aktual yang diterima perusahaan dari pabrik.

### Tabel `pembayaran_pabrik_detail`

Field:

- id
- pembayaran_pabrik_id
- pengiriman_id
- nomor_do
- jumlah_dialokasikan
- tonase_pabrik
- tonase_dasar_settlement
- harga_pabrik_per_kg
- potongan_sortasi_type: none, kg, percent, nominal
- potongan_sortasi_value
- potongan_sortasi_rupiah
- biaya_timbang
- potongan_pabrik_lain
- created_at

Catatan:

- Satu DO tidak boleh menerima alokasi pembayaran melebihi nilai tagihannya.
- Status pembayaran DO dihitung dari total alokasi pembayaran pabrik detail.
- Jika total alokasi sama dengan `total_pembayaran_pabrik` pada pengiriman, status DO menjadi dibayar penuh.

### Tabel `rekening_kas`

Dipakai sebagai daftar sumber/tujuan uang aktual perusahaan.

Field:

- id
- nama
- tipe: kas_tunai, bank, ewallet, owner_modal, lainnya
- nomor_rekening
- atas_nama
- aktif
- created_by
- created_at

Catatan:

- Minimal ada satu rekening kas default agar semua transaksi uang punya sumber/tujuan.
- Jika perusahaan memakai kas tunai dan bank, saldo keduanya harus dipisahkan.

### Tabel `kas_ledger`

Dipakai sebagai buku kas tunggal untuk semua uang aktual yang masuk dan keluar.

Field:

- id
- rekening_kas_id
- tanggal
- arah: masuk, keluar
- kategori: pembayaran_pabrik, pembayaran_petani, pembayaran_mitra, kasbon_panjar, pengembalian_kasbon_panjar, biaya_operasional, setoran_owner, tarik_owner, pendapatan_lain, koreksi, reversal
- jumlah
- sumber_tabel
- sumber_id
- nomor_referensi
- bukti_url
- keterangan
- status: aktif, dibatalkan, reversal
- created_by
- created_at

Catatan:

- Laba Bersih Kas wajib dihitung dari `kas_ledger`.
- Pembayaran pabrik, pembayaran petani, pembayaran mitra, biaya, dan kasbon/panjar yang benar-benar menggerakkan uang wajib membuat baris `kas_ledger`.
- Koreksi kas tidak mengubah baris lama; koreksi membuat baris reversal atau baris koreksi baru.

### Tabel `settlement_mitra`

Field:

- id
- mitra_id
- pengiriman_id
- nomor_do
- tanggal_settlement
- tonase_timbang_mitra
- tonase_pabrik
- tonase_dasar_settlement
- selisih_tonase
- nilai_selisih_tonase
- persen_selisih_ditanggung_perusahaan
- persen_selisih_ditanggung_mitra
- koreksi_selisih_dibayar_perusahaan
- harga_pabrik_per_kg
- total_bruto_pabrik
- potongan_sortasi_type: none, kg, percent, nominal
- potongan_sortasi_value
- potongan_sortasi_rupiah
- biaya_timbang
- potongan_pabrik_lain
- total_pembayaran_pabrik
- fee_per_kg
- fee_perusahaan
- potongan_armada
- potongan_hutang_kasbon
- potongan_lain
- total_hak_mitra
- total_dibayar
- sisa_bayar
- status
- created_at

### Tabel `pembayaran_mitra`

Field:

- id
- settlement_id
- mitra_id
- tanggal
- jumlah
- metode
- status
- keterangan
- created_by
- created_at

### Tabel `biaya_operasional`

Field:

- id
- tanggal
- kategori: solar, gaji_sopir, kuli, retribusi, perawatan, lainnya
- jumlah
- tipe_biaya: biaya_perusahaan, bantuan_mitra_dipotong_settlement
- pengiriman_id
- mitra_id
- armada_id
- keterangan
- status
- created_by
- created_at

Catatan:

- Jika `tipe_biaya = bantuan_mitra_dipotong_settlement`, biaya harus bisa dikaitkan ke pengiriman/settlement mitra.
- Biaya bantuan mitra tidak boleh mengurangi laba dua kali jika sudah menjadi potongan settlement.
- Pembatalan biaya operasional dilakukan dengan status/reversal, bukan delete fisik.


### Tabel `hutang_ledger` / `pihak_ledger`

Dipakai untuk saldo kasbon, panjar, pinjaman, dan pembayaran balik semua pihak agar tidak double count.

Field:

- id
- pihak_type: petani, mitra, sopir, karyawan, lainnya
- petani_id
- mitra_id
- sopir_id
- karyawan_id
- pihak_nama_manual
- tanggal
- tipe: debit, kredit
- sumber: kasbon, panjar, bayar_tunai, potong_tbs, potong_settlement, pembayaran_balik, koreksi, reversal
- jumlah
- transaksi_beli_id
- settlement_id
- kas_ledger_id
- keterangan
- created_by
- created_at

Catatan:

- Jika `pihak_type = petani`, maka `petani_id` wajib terisi dan `mitra_id` harus kosong.
- Jika `pihak_type = mitra`, maka `mitra_id` wajib terisi dan `petani_id` harus kosong.
- Jika `pihak_type = sopir` atau `karyawan`, relasi master terkait diisi jika master sudah tersedia.
- Jika `pihak_type = lainnya`, `pihak_nama_manual` wajib terisi.
- Saldo hutang/kasbon dihitung dari ledger, bukan disimpan manual sebagai angka terpisah.
- Kasbon/panjar yang menyebabkan uang keluar harus terhubung ke `kas_ledger`.
- Pengembalian kasbon/panjar yang menyebabkan uang masuk harus terhubung ke `kas_ledger`.

### Tabel `bukti_pembayaran`

Field:

- id
- tipe: pembayaran_mitra, pembayaran_petani, pembayaran_pabrik
- nomor_bukti
- pembayaran_mitra_id
- pembayaran_pabrik_id
- transaksi_beli_id
- file_url
- format: pdf, image
- created_by
- created_at

### Tabel `pengaturan_bisnis`

Field:

- id
- key
- value_json
- scope: global, mitra, armada
- scope_id
- berlaku_mulai
- aktif
- updated_by
- updated_at

Contoh `key`:

- default_fee_per_kg_mitra
- default_persen_selisih_perusahaan
- default_persen_selisih_mitra
- default_tindakan_kasbon_melebihi_limit
- default_toleransi_anomali_tonase_kg
- default_mode_approval_v1
- dashboard_owner_primary_profit_metric
- prioritas_laporan_harian

### Tabel `audit_log`

Field:

- id
- actor_user_id
- actor_role
- entity_type
- entity_id
- action: create, update, delete, cancel, approve, export, override
- before_json
- after_json
- alasan
- approved_by
- approved_at
- created_at

Transaksi yang wajib masuk audit log:

- Pembelian TBS petani
- Pengiriman lokal
- Pengiriman mitra
- Pembayaran pabrik
- Settlement mitra
- Pembayaran mitra
- Hutang/kasbon petani
- Hutang/kasbon mitra
- Biaya operasional
- Pembatalan/reversal transaksi
- Override tarif armada
- Koreksi stok
- Perubahan pengaturan bisnis

## 11. Hak Akses

| Modul | Owner | Super Admin | Admin Operasional | Admin Keuangan |
| --- | --- | --- | --- | --- |
| Dashboard umum | Ya | Ya | Ya | Ya |
| Laba-rugi / keuntungan | Ya | Ya | Tidak | Tidak |
| Master petani | Ya | Ya | Ya | Lihat |
| Master mitra | Ya | Ya | Ya | Lihat |
| Pembelian petani | Ya | Ya | Ya | Lihat |
| Pengiriman lokal | Ya | Ya | Ya | Lihat |
| Pengiriman mitra | Ya | Ya | Ya | Lihat |
| Pembayaran pabrik | Ya | Ya | Lihat | Ya |
| Kas masuk/keluar | Ya | Ya | Lihat | Ya |
| Settlement mitra | Ya | Ya | Lihat | Ya |
| Hutang petani | Ya | Ya | Lihat | Ya |
| Hutang mitra | Ya | Ya | Lihat | Ya |
| Hutang/panjar sopir/karyawan/lainnya | Ya | Ya | Lihat | Ya |
| Biaya operasional | Ya | Ya | Input | Ya |
| Pengaturan bisnis | Ya | Ya | Lihat | Lihat |
| Audit log | Ya | Ya | Tidak | Tidak |
| Pengaturan user | Tidak | Ya | Tidak | Tidak |
| Pengaturan role akses | Tidak | Ya | Tidak | Tidak |

Prinsip hak akses detail:

- Super admin dapat melakukan semua aksi, termasuk mengelola akun user dan role akses.
- Owner dapat melihat, membuat, mengubah, membatalkan, menyetujui, dan mengekspor data bisnis, tetapi tidak dapat mengelola akun user dan role akses.
- Admin operasional fokus pada input operasional dan tidak dapat melihat laba-rugi/keuntungan.
- Admin keuangan fokus pada pembayaran, hutang/kasbon, settlement, dan laporan kas, tetapi tidak dapat melihat laba-rugi/keuntungan.
- Aksi sensitif seperti batal transaksi, koreksi stok, override tarif armada, dan kasbon melewati batas wajib masuk audit log.

## 12. Prioritas Implementasi

### Prinsip Urutan Pengembangan

Karena MVP sudah live dan dipakai untuk data operasional asli, Tahap 2 wajib dikerjakan dengan prinsip **security-first, kas-first, dan non-destructive migration**.

Urutan pengembangan tidak boleh hanya mengikuti kemudahan coding. Urutan harus mengikuti risiko bisnis:

1. Lindungi data dan akses role sebelum membuka fitur uang yang lebih sensitif.
2. Rapikan ledger uang aktual sebelum laporan laba kas dianggap final.
3. Satukan hutang/panjar sebelum settlement mitra memakai potongan otomatis.
4. Hitung settlement dengan fungsi teruji sebelum UI pembayaran dibuat penuh.
5. Rilis per modul kecil agar jika ada bug, dampaknya tidak menyebar ke seluruh sistem.

### Tahapan Produk dan Batas Kelayakan

Pengembangan dibagi menjadi 4 fase produk. Fase ini bukan sekadar urutan coding, tetapi batas kelayakan penggunaan bisnis.

#### Fase 1 - MVP Operasional Terbatas

Status: sudah live untuk alur pengiriman mitra ke pabrik.

Fase ini boleh digunakan untuk:

- Master mitra/sopir/armada MVP.
- Input pengiriman mitra ke pabrik.
- Panjar mitra dasar.
- Kwitansi mitra.
- Laporan mitra.
- Koreksi atau pembatalan transaksi mitra tanpa menghapus histori.

Batasan fase ini:

- Belum menjadi sistem bisnis minimal.
- Belum semua uang masuk dan uang keluar dicatat di ledger kas tunggal.
- Panjar/kasbon belum universal untuk petani, mitra, sopir, karyawan, dan pihak lain.
- Laporan laba, margin, dan kas tidak boleh dianggap final.
- Development berikutnya harus berjalan di staging/development dan production hanya menerima perubahan kecil yang non-destruktif.

#### Fase 2 - Sistem Bisnis Minimal

Fase ini adalah batas pertama ketika web boleh disebut sistem bisnis minimal. Sebelum pembaruan 14 Juli 2026, MVP belum layak disebut sistem bisnis minimal karena bisnis sawit tidak cukup hanya dengan input DO dan cetak kwitansi; uang, hutang/panjar, pembayaran, dan akses role harus terkunci dulu. Setelah pembaruan Fase 2 minimum, fondasi kas dan hutang sudah tersedia untuk flow dasar, dengan catatan release gate manual tetap wajib sebelum ekspansi fitur yang lebih sensitif.

Wajib selesai sebelum fase ini dianggap lulus:

- P0-0 security gate: role, RLS, RPC grant, audit dasar, dan test manual role.
- Tidak ada delete fisik untuk transaksi finansial; semua memakai cancel/reversal.
- Pembayaran pabrik dasar berjalan dan membedakan nilai tagihan DO dari uang aktual diterima.
- `rekening_kas` dan `kas_ledger` menjadi sumber semua uang masuk/keluar aktual.
- Hutang/panjar universal untuk petani, mitra, sopir, karyawan, dan pihak lain.
- Panjar/kasbon dicatat sebagai saldo pihak/piutang, bukan biaya langsung.
- Pembayaran mitra dasar bisa dicatat sebagai kas keluar dan status bayar.
- Laporan owner dasar tersedia: posisi kas, uang masuk pabrik, uang keluar, DO belum dibayar, mitra belum dibayar, dan saldo hutang/panjar per pihak.
- Backup production, staging test, dan rollback checklist tersedia sebelum release.

Status implementasi 14 Juli 2026:

- `rekening_kas`, `kas_ledger`, hutang/panjar universal, pembayaran pabrik dasar, pembayaran mitra dasar, biaya operasional, dan laporan kas minimum sudah diimplementasikan.
- Test otomatis/build/lint dan lint database level error sudah lulus.
- Test manual semua role, SOP backup/rollback production, alokasi pembayaran multi-DO, limit kasbon, dan bukti transaksi masih menjadi syarat sebelum menyebut sistem ini selesai penuh.

Batasan fase ini:

- Sistem sudah layak untuk kontrol bisnis harian minimum.
- Laba Bersih Kas boleh dipakai jika bersumber dari `kas_ledger`.
- Laba Estimasi Transaksi masih harus diberi label jelas jika settlement penuh, selisih tonase, tarif armada, dan biaya bantuan belum lengkap.
- Fitur advanced seperti upload bukti, WhatsApp otomatis, multi-lokasi, dan dashboard margin detail belum wajib.

#### Fase 3 - Sistem Operasional Lengkap

Fase ini membuat web layak menjadi sistem kerja utama untuk owner dan admin.

Wajib selesai:

- Alur petani lokal: pembelian TBS, harga berlaku, stok lokal, dan pengiriman lokal ke pabrik.
- Pembayaran pabrik multi-DO dan rekonsiliasi dasar.
- Settlement mitra lengkap: fee history, tonase dasar settlement, pembagian selisih, potongan kasbon, biaya bantuan, dan tarif armada.
- Pembayaran mitra final beserta bukti/kwitansi.
- Audit/reversal untuk stok, kas, hutang, pembayaran, settlement, dan pengaturan bisnis.
- Laporan operasional harian: kas, pabrik per DO, stok, hutang/panjar, settlement mitra, dan export sesuai role.

Batasan fase ini:

- Sistem sudah bisa menjadi sumber kerja utama operasional.
- Masih mungkin ada polish dan otomasi lanjutan, tetapi alur bisnis inti sudah utuh.

#### Fase 4 - Aplikasi Utuh dan Matang

Fase ini adalah tahap final polish, otomasi, dan kontrol lanjutan.

Target fase ini:

- Upload foto tiket timbang, DO, dan bukti pembayaran.
- WhatsApp evidence flow yang lebih rapi.
- Multi-lokasi timbang atau multi-site jika bisnis membutuhkan.
- Rekonsiliasi lanjutan untuk anomali tonase, pembayaran, dan kas.
- Dashboard owner dengan margin dan tren lebih dalam.
- Monitoring error, SOP backup/restore, dan hardening final.
- UI/UX final untuk pemakaian jangka panjang.

Pada fase ini aplikasi bisa dianggap utuh dan matang, bukan hanya sistem operasional internal yang masih bertumbuh.

### P0 - Wajib Sebelum Dipakai Serius

#### P0-0 - Fondasi Keamanan Produksi

- Pisahkan environment development/staging dan production.
- Backup production sebelum migration Tahap 2.
- Audit tabel, RPC, Storage policy, dan route UI yang sudah live.
- Perketat RLS Supabase bertahap per modul, bukan satu migration besar tanpa uji role.
- Pastikan UI hiding bukan satu-satunya kontrol; backend/RLS tetap menolak role yang tidak berhak.
- Batasi laporan laba-rugi, margin, dan pendapatan owner untuk owner/super admin.
- Batasi pengaturan user/role hanya untuk super admin.
- Batasi aksi finansial sensitif untuk owner/super admin/admin keuangan sesuai matriks role.
- Revoke atau batasi eksekusi RPC sensitif dari role yang tidak berhak.
- Semua `SECURITY DEFINER` function harus punya validasi `auth.uid()` dan role aplikasi di dalam function.
- Tidak boleh ada delete fisik untuk transaksi yang memengaruhi stok, kas, hutang, settlement, atau pembayaran.
- Siapkan test manual role: owner, super admin, admin operasional, admin keuangan.

#### P0A - Fondasi dan Alur Lokal

- Pisahkan petani dan mitra.
- Tambah role super admin.
- Batasi pengelolaan akun user dan role akses hanya untuk super admin.
- Batasi laporan laba-rugi hanya untuk owner dan super admin.
- Tambah master petani, pabrik, armada perusahaan, dan harga TBS lokal berbasis tanggal/jam berlaku.
- Tambah stok sementara TBS lokal.
- Tambah alokasi stok lokal default FIFO dengan opsi pilih manual transaksi petani.
- Tambah transaksi pembelian TBS petani dan nomor struk unik.
- Tambah pengiriman lokal ke pabrik dan pembayaran pabrik per DO.
- Perbaiki hutang/kasbon memakai ledger tunggal.
- Perbaiki nomor struk dan nomor bukti agar aman dari bentrok.
- Tambah pembatalan/reversal ledger untuk transaksi uang, stok, hutang, dan pembayaran.

#### P0B - Kas, Pembayaran Pabrik, dan Hutang/Panjar Universal

- Tambah `rekening_kas` dan `kas_ledger`.
- Catat semua uang masuk aktual ke `kas_ledger`.
- Catat semua uang keluar aktual ke `kas_ledger`.
- Selesaikan UI pembayaran pabrik agar satu pembayaran bisa dialokasikan ke satu/banyak DO.
- Bedakan nilai tagihan DO dari uang aktual diterima.
- Laba Bersih Kas dihitung dari `kas_ledger`, bukan dari nilai estimasi transaksi.
- Perluas hutang/panjar menjadi ledger pihak universal: petani, mitra, sopir, karyawan, dan pihak lain.
- Migrasikan/sinkronkan `panjar_mitra` aktif ke ledger universal tanpa merusak histori MVP.
- Kasbon/panjar bukan biaya laba-rugi; kasbon/panjar adalah saldo pihak dan arus kas.
- Setiap kasbon/panjar yang mengeluarkan uang harus membuat mutasi ledger pihak dan Buku Kas (`kas_ledger`).
- Setiap pengembalian kasbon/panjar harus membuat mutasi ledger pihak dan Buku Kas (`kas_ledger`).

#### P0C - Alur Mitra dan Settlement

- Tambah modul pengaturan bisnis untuk fee, pembagian selisih tonase, tarif armada, limit kasbon, dan prioritas laporan.
- Tambah riwayat fee mitra berdasarkan tanggal/jam berlaku.
- Tambah alur pengiriman mitra per DO.
- Pisahkan konsep **Armada CB** dari **Mitra Transaksi**: Armada CB adalah sopir/plat internal CB dan tidak wajib memiliki `mitra_id`; Mitra Transaksi adalah pihak yang punya muatan dan masuk kwitansi.
- Form Pengiriman Mitra wajib bisa mencari plat/sopir Armada CB walaupun armada tersebut tidak punya mitra default.
- Sewa Armada CB yang dipotong dari mitra dihitung dari Berat Netto Pabrik dan tidak boleh dikurangi uang jalan/perongkosan.
- Tambah settlement mitra per DO.
- Fee mitra nominal per kg.
- Pembayaran mitra berdasarkan `tonase_dasar_settlement`.
- Tambah pembagian selisih tonase berdasarkan persentase yang bisa diatur.
- Tambah alert anomali jika `tonase_dasar_settlement` lebih besar dari timbang mitra melewati toleransi.
- Tambah batas hutang/kasbon per pihak dan approval jika melewati batas.
- Tambah biaya operasional dan biaya bantuan mitra yang bisa dipotong settlement.
- Settlement dan pembayaran mitra harus memakai data kas/pembayaran yang sudah kuat, bukan estimasi bebas.

#### P0D - Kontrol, Audit, dan Laporan Owner

- Tampilkan Laba Bersih Kas sebagai angka utama owner dan Laba Estimasi Transaksi sebagai pembanding.
- Tambah audit log minimal untuk transaksi uang, tonase, stok, settlement, dan pengaturan bisnis.
- Tambah laporan dasar harian, pabrik per DO, stok lokal, settlement mitra, dan laba-rugi owner.
- Tambah rekonsiliasi kas masuk/keluar per rekening.
- Tambah laporan saldo hutang/panjar per pihak.
- Perbaiki encoding teks/icon.

### P1 - Penting Untuk Operasional Harian

- Laporan per mitra.
- Laporan pabrik per DO.
- Potongan sortasi/grading dan biaya timbang.
- Tracking tagihan sopir Armada CB: upah flat per trip dan uang jalan/perongkosan sebagai biaya CB yang dibayar ke sopir.
- Aksi bayar tunai sopir Armada CB yang mencatat kas keluar tanpa otomatis mengurangi kas saat DO diinput.
- Riwayat tarif armada dan override tarif dengan alasan.
- Bukti pembayaran mitra PDF/gambar untuk WhatsApp.
- Laporan stok lokal.
- Ekspor laporan operasional tanpa data laba-rugi sesuai role.

### P2 - Pengembangan Lanjutan

- Upload foto tiket timbang/DO.
- Multi-lokasi timbang.
- Ekspor Excel settlement mitra.
- Dashboard owner dengan margin per sumber.
- Laporan profit Armada CB per truk/bulan: total trip, total muatan, sewa masuk, Dana Operasional Trip, biaya operasional lain, dan margin.
- Tampilan Semua Armada menyediakan rekap per plat untuk membandingkan produktivitas armada dalam satu layar.
- Template WhatsApp otomatis untuk bukti pembayaran.
- Rekonsiliasi lanjutan selisih timbang mitra vs pabrik.

## 13. Catatan Implementasi dan Risiko

- Penguatan RLS tidak boleh dilakukan sebagai perubahan massal tanpa test role, karena sistem sudah live dan bisa membuat operator gagal input data.
- Setiap migration Tahap 2 harus non-destruktif: tambah tabel/kolom/index/policy baru, hindari rename/drop sampai ada rencana migrasi dan rollback.
- Perubahan pada tabel MVP live seperti `master_mitra`, `sopir`, `transaksi_mitra`, `panjar_mitra`, dan kwitansi harus menjaga kompatibilitas data lama.
- Jika ada dua tabel/konsep yang tumpang tindih, misalnya `master_mitra` MVP dan `mitra` final, sistem harus menentukan mapping/sumber kebenaran sebelum settlement final.
- Laporan kas tidak boleh dianggap final sebelum `kas_ledger` menjadi sumber utama seluruh uang masuk/keluar.
- Pembayaran pabrik perlu dipisah antara nilai tagihan DO dan uang aktual diterima agar laba kas tidak terlalu besar di atas kertas.
- Kasbon/panjar untuk petani, mitra, sopir, karyawan, atau pihak lain tidak boleh langsung dianggap biaya; posisinya adalah saldo pihak/piutang dan arus kas.
- Pembagian selisih berat harus selalu memakai persentase yang tersimpan agar settlement bisa diaudit.
- Tarif armada perlu riwayat tanggal berlaku agar perubahan tarif tidak mengubah perhitungan pengiriman lama.
- Fee mitra perlu riwayat tanggal berlaku agar perubahan fee tidak mengubah pengiriman/settlement lama.
- Sopir aktual harus disimpan per pengiriman karena sopir armada bisa diganti sewaktu-waktu; relasi default di master tidak cukup untuk audit DO lama.
- Ledger hutang/kasbon harus generik untuk semua pihak agar tidak terjadi double count.
- Transaksi yang sudah berdampak ke ledger tidak boleh dihapus; pembatalan harus memakai reversal agar audit tetap utuh.
- Kondisi `tonase_dasar_settlement` lebih besar dari timbang mitra harus ditandai sebagai anomali rekonsiliasi agar tidak luput dari perhatian owner/admin.
- Laporan owner harus memakai label jelas: Laba Bersih Kas untuk uang nyata, Laba Estimasi Transaksi untuk transaksi yang belum selesai dibayar.
- Bukti pembayaran WhatsApp harus ringkas dan mudah dibaca di HP.
- Prioritas laporan harian mengikuti urutan yang paling sering dipakai: kas, stok/TBS lokal, DO pabrik, settlement mitra, hutang/kasbon, lalu margin owner.

## 14. Definisi Sukses Final

Versi final dianggap berhasil jika:

- Admin bisa mencatat pembelian TBS dari petani lokal.
- Pembelian petani otomatis menambah stok sementara.
- Harga beli petani memakai harga yang berlaku berdasarkan tanggal/jam transaksi.
- Admin bisa mengirim TBS lokal ke pabrik dengan detail transaksi petani dan total harian.
- Admin bisa mencatat pengiriman mitra ke pabrik per DO.
- Admin bisa mencatat sopir aktual per DO, termasuk saat sopir berbeda dari default armada.
- Sistem bisa mencatat pembayaran pabrik per DO.
- Sistem menghitung hak mitra berdasarkan `tonase_dasar_settlement`.
- Sistem memotong fee perusahaan nominal per kg.
- Sistem memakai fee mitra yang berlaku pada tanggal/jam pengiriman/DO.
- Sistem membagi selisih tonase memakai persentase yang bisa diatur owner/super admin.
- Sistem memberi peringatan anomali jika `tonase_dasar_settlement` lebih besar dari timbang mitra melewati toleransi.
- Sistem memotong sewa Armada CB dari hak mitra jika sopir/plat internal CB dipakai.
- Sistem memakai tarif sewa Armada CB yang tersimpan sebagai snapshot transaksi dan mencatat override tarif jika ada.
- Sistem mencatat upah sopir dan uang jalan Armada CB sebagai biaya CB terpisah, bukan sebagai pengurang sewa armada yang dipotong dari mitra.
- Sistem bisa mencatat hutang/kasbon petani, mitra, sopir, karyawan, dan pihak lain tanpa double count.
- Sistem bisa membatasi kasbon/panjar sesuai limit pihak dan meminta approval jika melewati batas.
- Sistem mencatat seluruh uang aktual masuk/keluar di `kas_ledger`.
- Sistem bisa membedakan nilai tagihan DO, pembayaran pabrik aktual, dan alokasi pembayaran ke DO.
- Sistem membatalkan/koreksi transaksi menggunakan reversal dan audit log, bukan delete fisik.
- Sistem bisa membuat bukti pembayaran mitra dalam PDF atau gambar untuk WhatsApp.
- Owner dan super admin bisa melihat Laba Bersih Kas dan Laba Estimasi Transaksi.
- Admin biasa tidak bisa melihat laporan keuntungan.
- Admin biasa tidak bisa membaca data keuntungan lewat query langsung, bukan hanya lewat menu yang disembunyikan.
- Laporan bisa memisahkan sumber lokal dan mitra.
- Biaya perusahaan tidak tercampur dengan biaya mitra.

# ADDENDUM FASE 2 - UX BACK-OFFICE (15 Juli 2026)

Berdasarkan tinjauan operasional, pengguna utama modul Pengiriman Mitra adalah **Admin Back-Office Owner** yang memasukkan data secara *batch* dari tumpukan kwitansi/nota fisik pabrik. 

**Keputusan Pengembangan (P0 UX Refinement):**
1. **Unified Interface:** Halaman "Input Timbangan" dan "Riwayat Pengiriman" disatukan menjadi satu halaman antarmuka bergaya *Data Grid* dengan *Quick Add Modal*. Tujuannya agar admin dapat melihat daftar transaksi hari ini untuk menghindari *double entry* sekaligus dapat menambah data baru tanpa pindah halaman.
2. **Armada First:** Pemilihan Mitra tidak lagi menjadi *blocker* untuk memilih Armada/Sopir. Admin dapat mengetik Plat Nomor terlebih dahulu. Jika armada punya mitra default, sistem boleh meng-*auto-fill* Mitra Transaksi. Jika armada adalah Armada CB dan tidak punya mitra default, sistem tetap memilih armada itu lalu meminta admin memilih Mitra Transaksi secara eksplisit.
3. **Sticky Date:** Tanggal transaksi dipertahankan setelah proses *submit* (tidak otomatis reset ke `today`) untuk mempercepat entri tumpukan nota dari hari sebelumnya.

# ADDENDUM FASE 2 - Armada CB, Sewa Armada, dan Dana Operasional Trip (15 Juli 2026)

**Status implementasi:** P0, P1, dan P2 selesai diterapkan melalui migrasi fondasi `20260715105207_armada_cb_driver_costs.sql`, koreksi final `20260715123147_armada_cb_dana_operasional_trip_mitra.sql`, dan halaman Laporan Armada CB.

Berdasarkan jawaban owner 15 Juli 2026, Armada CB adalah armada internal CB dan tidak wajib terafiliasi dengan mitra mana pun. Sopir menerima satu Dana Operasional Trip yang sudah mencakup seluruh kebutuhan satu kali jalan.

**Keputusan P0 yang wajib dikoreksi:**
- `sopir.mitra_id` bersifat opsional. Untuk Armada CB, field ini boleh kosong.
- `sopir.is_armada_cb = true` menjadi penanda utama bahwa plat/sopir tersebut adalah Armada CB.
- Pengiriman Mitra tetap wajib memilih **Mitra Transaksi**, karena mitra transaksi adalah pihak yang punya muatan dan menerima kwitansi.
- Sewa Armada CB adalah pemasukan/potongan ke mitra: `Berat Netto Pabrik x Tarif Sewa Armada/kg`.
- Dana Operasional Trip adalah biaya CB, bukan pengurang sewa armada yang dipotong dari mitra.
- Field/istilah lama seperti `pakai_sewa_armada_bl` boleh dipertahankan sementara untuk kompatibilitas, tetapi UI dan helper kalkulasi harus memakai istilah Armada CB.

**Posisi pengembangan:**
- **P0 koreksi fondasi:** benahi form, helper kalkulasi, field snapshot, dan kwitansi agar sewa Armada CB tidak tertukar dengan uang jalan.
- **P1 add-on:** catat tagihan Dana Operasional Trip berdasarkan Mitra Transaksi.
- **P2 add-on:** laporan profit Armada CB per bulan/per truk, termasuk biaya operasional seperti ganti oli.

**Workflow Dana Operasional Trip:**
1. Admin input Pengiriman Mitra.
2. Jika plat yang dipilih adalah Armada CB, sistem menghitung sewa Armada CB sebagai potongan/tagihan ke mitra.
3. Sistem mengambil Dana Operasional Trip dari tarif Mitra Transaksi dan membekukannya sebagai snapshot.
4. Kas tidak otomatis berkurang saat DO diinput. Admin menekan aksi **Bayar Dana Trip** untuk mencatat kas keluar.
5. Laporan Armada CB membaca sewa masuk, Dana Operasional Trip, biaya operasional lain, dan margin.

**Aturan snapshot kwitansi:**
- Kwitansi yang sudah diterbitkan adalah dokumen finansial beku. Berat, tarif, sewa Armada CB, panjar, dan nominal dibayar harus dibaca dari snapshot saat penerbitan.
- Perubahan atau backfill pada `transaksi_mitra` tidak boleh mengubah detail, total, maupun Buku Kas dari kwitansi yang sudah dibayar.
- Sistem boleh menyimpan sewa menurut rumus terbaru dan selisih historis sebagai metadata audit, tetapi angka tersebut tidak menggantikan nominal yang pernah ditagihkan.
- Kesalahan kwitansi diselesaikan melalui pembatalan dan penerbitan kwitansi baru, bukan mengedit item kwitansi lama.
- Status **Perlu Cek** wajib memiliki penyebab yang dapat dipahami admin dan pintasan ke kwitansi terkait; status tidak boleh diselesaikan dengan checkbox tanpa tindakan finansial.
- Transaksi baru setelah pembayaran sebelumnya tetap menjadi tagihan baru dan tidak menandai kwitansi lama sebagai bermasalah.
- Pembatalan pembayaran wajib membalik kas dan pelunasan panjar secara atomik serta menyimpan alasan dan audit log.

Enam tarif awal telah diisi berdasarkan konfirmasi owner. Mitra lain tetap `Rp0` dan tidak boleh dipakai untuk pengiriman Armada CB sebelum tarif sewa serta Dana Operasional Trip dilengkapi di menu Mitra.

## KOREKSI FINAL - Dana Operasional Trip Armada CB (15 Juli 2026)

Keterangan sebelumnya tentang pemisahan upah sopir dan uang jalan digantikan oleh keputusan berikut:

- Owner memberikan satu nominal flat per trip kepada sopir Armada CB.
- Nominal tersebut sudah mencakup solar, makan, uang jalan, dan bagian sopir.
- Sistem tidak menghitung atau menampilkan “upah bersih sopir” karena pembagian dana dilakukan oleh sopir dan tidak diketahui owner.
- Nama bisnis yang dipakai adalah **Dana Operasional Trip**.
- Dana Operasional Trip ditentukan oleh **Mitra Transaksi** yang menyewa Armada CB, bukan oleh sopir atau truk.
- Sewa masuk CB tetap dihitung `Berat Netto Pabrik x Tarif Sewa Mitra/kg`.
- Margin armada dihitung `Sewa Masuk - Dana Operasional Trip - Biaya Operasional Lain`.
- Saat pengiriman dibuat, tarif sewa dan Dana Operasional Trip disimpan sebagai snapshot agar perubahan tarif berikutnya tidak mengubah arsip lama.
- Trip yang sudah dibayar tidak boleh diubah oleh proses sinkronisasi tarif.

Tarif berlaku mulai 15 Juli 2026:

| Mitra | Sewa/kg | Dana Operasional Trip |
| --- | ---: | ---: |
| SL | Rp150 | Rp800.000 |
| BL | Rp150 | Rp750.000 |
| SL/F | Rp150 | Rp750.000 |
| SL/BS | Rp150 | Rp750.000 |
| SL/MLD | Rp150 | Rp750.000 |
| BL/ML | Rp180 | Rp900.000 |

Field `upah_sopir_cb_snapshot`, `uang_jalan_sopir_cb_snapshot`, dan pengaturan global/override lama dipertahankan hanya untuk kompatibilitas data historis. Transaksi baru memakai `dana_operasional_trip_snapshot` sebagai sumber kebenaran.
