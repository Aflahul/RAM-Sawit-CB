# Decision Records

Folder ini menyimpan keputusan material yang perlu dipahami tanpa membaca ulang seluruh percakapan, PRD, atau histori commit.

## Jenis Record

- `business/BDR-YYYYMMDD-NNN-judul.md`: aturan, pengecualian, dan trade-off bisnis.
- `architecture/ADR-YYYYMMDD-NNN-judul.md`: keputusan arsitektur, data, security, atau integrasi.

Gunakan template pada:

- [`business-decision-record-template.md`](../templates/business-decision-record-template.md)
- [`architecture-decision-record-template.md`](../templates/architecture-decision-record-template.md)

## Aturan

1. Record baru dimulai dengan status `Proposed` dan memiliki decision owner.
2. Record `Accepted` menjadi sumber keputusan sampai digantikan.
3. Keputusan lama tidak ditulis ulang untuk mengubah sejarah. Buat record baru dan tandai yang lama `Superseded`.
4. Record harus menautkan requirement, audit, task, test, migration, atau PR yang relevan.
5. Rahasia, kredensial, dan data produksi tidak boleh ditulis di record.

