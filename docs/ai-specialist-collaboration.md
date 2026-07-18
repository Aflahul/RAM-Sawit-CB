# Protokol Kolaborasi Panel Spesialis

| Metadata | Nilai |
| --- | --- |
| Status | Draft untuk persetujuan Product Owner dan Engineering Lead |
| Berlaku sejak | 17 Juli 2026 |
| Koordinator | Engineering Lead/Codex utama |
| Tujuan | Memecah pekerjaan berdasarkan keahlian, melakukan koreksi silang, dan menjaga satu hasil terintegrasi |

## 1. Prinsip Kerja

Panel spesialis dibentuk per work package. Spesialis dapat berupa anggota tim manusia, subagent AI, atau gabungan keduanya. Panel bukan pengganti persetujuan Product Owner dan tidak boleh membuat keputusan bisnis material tanpa bukti atau konfirmasi.

Prinsip wajib:

1. Satu koordinator memegang tujuan, scope, dependency, dan hasil akhir.
2. Setiap work package memiliki satu pemilik implementasi dan sedikitnya satu reviewer yang berbeda untuk perubahan berisiko.
3. Spesialis bekerja pada file/modul yang tidak tumpang tindih selama eksekusi paralel.
4. Setiap rekomendasi harus menunjuk bukti repository, route, schema, kebutuhan pengguna, atau hasil test.
5. Pendapat tidak otomatis menjadi keputusan. Konflik diselesaikan berdasarkan aturan bisnis, data, risiko, dan persetujuan owner.
6. Tidak ada subagent yang boleh menghapus perubahan pihak lain, kredensial, data produksi, atau histori finansial.

## 2. Peran Spesialis

| Peran | Fokus utama | Keluaran minimum |
| --- | --- | --- |
| Product/Business Analyst | Tujuan, use case, aktor, state, formula, exception | Requirement, flow, acceptance criteria, temuan `BF-*` |
| UX Research/Interaction | Task flow, beban kerja, error prevention, feedback | User journey, flow UI, temuan `UX-*` |
| UI/Design System/Accessibility | Konsistensi komponen, visual hierarchy, responsive, print, a11y | Spesifikasi komponen dan review visual |
| Frontend Engineer | Route, state UI, form, validation, query integration | Implementasi UI dan test terkait |
| Backend/Data Engineer | Schema, RPC, ledger, snapshot, migration, performa | Migration/query dan bukti data |
| Security Reviewer | Auth, role, RLS, auditability, secrets, abuse case | Temuan `SEC-*` dan keputusan kontrol |
| QA/Release Engineer | Test strategy, regression, evidence, rollback | Test report, temuan `QA-*`, go/no-go |
| Documentation/Traceability | Konsistensi sumber kebenaran dan tautan | Dokumen tersinkron dan traceability lengkap |

Untuk tim kecil, satu orang boleh memegang beberapa peran. Namun, perubahan uang, role, RLS, migration, dan penghapusan data tetap memerlukan koreksi silang dari perspektif lain.

## 3. Pola Pembagian Subagent

Koordinator memakai pembagian berikut saat scope cukup besar:

```text
Coordinator
  |-- Product/Business explorer: analisis aturan dan gap
  |-- UX/UI worker: audit atau rancangan interaksi
  |-- Engineering/Data worker: implementasi teknis pada area terpisah
  |-- QA/Security explorer: challenge risiko dan test gap
  `-- Coordinator: integrasi, keputusan, verifikasi, dokumentasi
```

Ketentuan:

- Explorer hanya membaca dan memberi analisis terarah.
- Worker mendapat kepemilikan file yang eksplisit dan menulis perubahan langsung.
- Dua worker tidak mengedit file yang sama secara bersamaan.
- Koordinator tidak mengulang pekerjaan yang sudah didelegasikan; koordinator memeriksa dan mengintegrasikan hasilnya.
- Agent yang sudah memahami domain digunakan kembali untuk review lanjutan agar konteks tidak hilang.

## 4. Work Package Brief

Setiap delegasi minimal memuat:

```text
Tujuan:
Scope masuk:
Scope tidak masuk:
Role pengguna:
Aturan bisnis terkait:
File/modul yang dimiliki:
Dependency dan batasan:
Acceptance criteria:
Perintah verifikasi:
Format laporan hasil:
```

Khusus worker, brief wajib menyebut bahwa ia tidak bekerja sendirian, tidak boleh membatalkan perubahan lain, dan harus melaporkan seluruh file yang diubah.

## 5. Koreksi Silang

| Hasil utama | Reviewer wajib |
| --- | --- |
| Perubahan flow bisnis/formula | UX + Data + QA |
| Perubahan UI workflow | Business + Accessibility + QA |
| Migration/schema/RPC | Data peer + Security + QA |
| Role/RLS/auth | Security + Data + QA role matrix |
| Kwitansi/snapshot/pembayaran | Business + Data + QA finansial |
| Release production | Engineering Lead + QA/Release; Owner untuk perubahan bisnis material |

Reviewer memeriksa:

1. Apakah hasil menjawab kebutuhan dan bukan hanya gejala?
2. Apakah istilah, angka, state, dan sumber data konsisten?
3. Apakah happy path, empty state, validation, error, retry, cancel, reversal, dan permission telah ditangani?
4. Apakah ada dampak ke histori, snapshot, kwitansi, kas, laporan, atau role lain?
5. Apakah bukti test cukup dan rollback realistis?

## 6. Resolusi Perbedaan Pendapat

1. Catat pilihan, bukti, risiko, dan dampak masing-masing opsi.
2. Aturan hukum/keamanan/data mengalahkan preferensi visual.
3. Aturan bisnis yang telah disetujui mengalahkan asumsi implementasi.
4. Jika kebutuhan owner belum jelas dan dampaknya material, hentikan keputusan terkait dan minta konfirmasi.
5. Product Owner memutus trade-off bisnis; Engineering Lead memutus kelayakan teknis; QA/Release dapat menahan rilis jika gate gagal.
6. Keputusan akhir ditulis di PRD/addendum atau implementation plan, bukan hanya di percakapan.

## 7. Gate Khusus Perubahan Berisiko

Perubahan berikut tidak boleh diselesaikan oleh satu perspektif saja:

- formula berat, harga, fee, sewa, panjar, atau pembayaran;
- pembuatan/pembatalan mutasi kas;
- snapshot kwitansi dan dokumen bukti;
- migration yang mengubah atau backfill data;
- RLS, role, login, atau endpoint sensitif;
- penghapusan tabel, kolom, file data, atau histori;
- perubahan status final yang memengaruhi laporan.

Minimal diperlukan implementer, reviewer Data/Security, dan QA. Bukti berupa diff, hasil query/test, serta rencana rollback harus dilampirkan pada task atau PR.

## 8. Handoff dan Laporan Hasil

Setiap spesialis menyerahkan:

- ringkasan keputusan dan alasan;
- file atau area yang diperiksa/diubah;
- temuan dengan ID dan severity;
- asumsi serta hal yang belum terbukti;
- test yang dijalankan dan hasilnya;
- risiko tersisa dan rekomendasi tahap berikutnya.

Koordinator kemudian:

1. memeriksa konflik dan konsistensi lintas hasil;
2. meminta koreksi silang pada perubahan berisiko;
3. menyelesaikan integrasi dan verifikasi repository;
4. memperbarui dokumen sumber kebenaran;
5. menyampaikan hasil, batas, dan status rilis secara jelas.

## 9. Batas Penggunaan AI

- AI tidak menjadi pemegang kredensial atau pemberi persetujuan transaksi produksi.
- AI tidak mengarang data bisnis yang belum tersedia.
- Output AI dianggap usulan sampai diperiksa terhadap kode, database, dan keputusan owner.
- Data pribadi/produksi hanya digunakan sebatas yang diperlukan dan tidak disalin ke dokumen publik.
- Operasi destruktif, perubahan produksi, dan penerimaan risiko tetap memerlukan keputusan manusia yang berwenang.
