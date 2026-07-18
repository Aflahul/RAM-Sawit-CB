# BDR-20260718-001: Aturan Maker-Checker Transaksi Finansial

| Metadata | Nilai |
| --- | --- |
| Status | Approved / Active |
| Tanggal | 18 Juli 2026 |
| Pemilik | Product Owner |
| Dampak | Modul Pinjaman dan Panjar |
| Relasi | `TASK-BIZ-001` |

## 1. Konteks
Sistem membutuhkan mekanisme persetujuan ganda (Maker-Checker) untuk transaksi pengeluaran/pembayaran demi mencegah *fraud* dan meminimalisir kesalahan input, sebagaimana disyaratkan dalam baseline audit keamanan. Namun, bisnis juga menuntut agar operasional harian tidak terhambat (*bottleneck*) jika Owner/pihak penyetuju sedang tidak dapat diakses.

## 2. Pilihan yang Dipertimbangkan
1. Menetapkan batas kaku (misal Rp 50.000.000) yang selalu butuh *approval*.
2. Memblokir seluruh transaksi tanpa memandang nominal hingga ada *approval*.
3. Menyediakan kerangka Maker-Checker yang konfigurasinya (*threshold*) diserahkan sepenuhnya kepada Owner, dengan pintu darurat (*break-glass*) yang diaudit ketat.

## 3. Keputusan
Kami memilih opsi **3**. Keputusan spesifiknya adalah:
- **Batas Nominal (Threshold):** Saat ini, fitur diaktifkan tetapi batas nominal tidak dikunci secara kaku (misal, sementara bisa diset Rp 0 atau tak terhingga) hingga Owner siap menentukan angka pasti berdasarkan profil transaksi berjalan. Konfigurasi ini akan disimpan dalam tabel `pengaturan_bisnis`.
- **Aturan Peran (Role Rules):**
  - **Maker** (Pembuat Transaksi): Admin (Operasional / Keuangan).
  - **Checker** (Penyetuju): Owner atau Super Admin.
  - *Jika Maker adalah Owner atau Super Admin, transaksi otomatis disetujui tanpa perlu menunggu (Auto-Approve).*
  - *Sistem wajib menolak apabila Maker (berstatus Admin) mencoba menyetujui transaksinya sendiri (Self-Approval).*
- **Pintu Darurat (Break-Glass):** Super Admin diizinkan melakukan 'Force Approve' (memotong jalur persetujuan Owner) pada kondisi mendesak. Tindakan darurat ini wajib menyertakan pengisian **Alasan Darurat** yang akan tercatat secara permanen di Audit Trail.

## 4. Alasan
Owner saat ini masih meraba pola transaksi yang wajar sehingga belum bisa menentukan batas *approval* baku. Memaksakan batas kaku saat ini akan menghambat operasional. Solusi *Break-Glass* via Super Admin dipilih untuk menyeimbangkan antara keamanan (tetap tercatat) dan kelancaran operasional saat keadaan darurat.

## 5. Konsekuensi
- **Teknis:** Basis data perlu disiapkan dengan kolom `diajukan_oleh`, `disetujui_oleh`, `status_approval`, dan tabel audit untuk *break-glass*. Konfigurasi nominal *threshold* harus dinamis dan dapat diatur lewat antarmuka khusus (hanya oleh Owner/Super Admin).
- **Operasional:** Admin tetap dapat membuat draf pembayaran berapapun nilainya, namun pencairan saldo tidak terjadi sampai statusnya disetujui (jika melebihi *threshold* aktif).
