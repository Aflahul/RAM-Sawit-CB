# Arsip Audit UX Input Pengiriman Mitra

| Metadata | Nilai |
| --- | --- |
| Status | Historis, sudah dikonsolidasikan |
| Audit awal | Sebelum 17 Juli 2026 |
| Digantikan oleh | [Audit UX/UI Seluruh Aplikasi](../ux-ui-audit.md) |

Dokumen ini mempertahankan konteks pain point awal halaman Input Pengiriman Mitra. Jangan menambahkan temuan baru di sini.

## Temuan Historis

### Pemilihan armada terkunci oleh mitra

Pada kondisi awal, kolom Sopir/Armada baru dapat digunakan setelah Admin memilih Mitra. Padahal saat input nota pabrik, informasi yang paling mudah dikenali biasanya plat truk, nama sopir, dan angka timbangan. Urutan tersebut menambah beban ingatan dan memperlambat input.

Rekomendasi saat itu: bebaskan pencarian Armada terlebih dahulu, lalu isi Mitra default secara otomatis tanpa menghilangkan pilihan Mitra Transaksi.

### Urutan form tidak mendukung input batch

Kolom kasus khusus seperti Sopir Aktual berada di jalur utama sebelum berat. Admin harus melewati kontrol yang jarang digunakan untuk mencapai input angka utama.

Rekomendasi saat itu: gunakan urutan `Tanggal -> Sopir/Plat -> Mitra -> Berat Netto -> Potongan -> Simpan`, dan pindahkan kasus khusus ke Opsi Lanjutan.

### Tanggal berisiko kembali ke hari ini

Admin dapat memasukkan tumpukan nota dari tanggal yang sama. Jika tanggal selalu direset setelah penyimpanan, risiko salah tanggal dan pekerjaan berulang meningkat.

Rekomendasi saat itu: pertahankan tanggal transaksi sebelumnya setelah penyimpanan berhasil.

### Form terpisah dari riwayat

Admin perlu melihat transaksi yang baru dimasukkan untuk mencegah input ganda dan segera melakukan koreksi.

Rekomendasi saat itu: satukan riwayat dan aksi Tambah Pengiriman pada satu halaman dengan form dialog yang ringkas serta ramah keyboard.

## Status pada Baseline Baru

Audit lintas aplikasi 17 Juli 2026 menemukan bahwa empat arah utama tersebut sudah terlihat pada source code:

- form dibuka dari halaman riwayat yang sama;
- Armada dapat dipilih sebelum Mitra dan dapat mengisi Mitra default;
- tanggal dipertahankan setelah penyimpanan;
- Sopir Aktual ditempatkan pada Opsi Lanjutan.

Status belum disebut `Verified` sampai task-based usability test, keyboard test, dan validasi pengguna Admin dilakukan. Detail evidence dan tindak lanjut berada di [Audit UX/UI Seluruh Aplikasi](../ux-ui-audit.md).

