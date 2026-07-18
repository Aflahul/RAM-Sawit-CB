# Incident Record: INC-YYYYMMDD-NNN

| Field | Nilai |
| --- | --- |
| Status | Investigating / Contained / Monitoring / Resolved / Closed |
| Severity | S0 / S1 / S2 / S3 |
| Waktu deteksi (WIB/UTC) |  |
| Environment/commit/deploy |  |
| Reporter |  |
| Incident Commander | Identitas manusia |
| Alternate IC | Identitas manusia |
| Data/nominal/role terdampak | Simpan detail sensitif di lokasi terbatas |
| Target RPO/RTO | Mengacu BDR/SLA yang disetujui; absence adalah blocker KR3/KR4 |
| Secure channel/contact tree | Lokasi, bukan secret |

## Ringkasan Faktual

Jelaskan apa yang diketahui, apa yang belum diketahui, dan dampak yang terlihat. Hindari spekulasi serta data pribadi yang tidak perlu.

## Timeline

| Waktu WIB/UTC | Actor | Kejadian/keputusan | Bukti |
| --- | --- | --- | --- |
|  |  |  |  |

## Containment

- Write/deploy yang dihentikan:
- Fitur/role yang dibatasi:
- Session/key yang dicabut/dirotasi:
- Bukti yang dipertahankan:
- Risiko yang masih berjalan:

## Assessment

- Rentang waktu dan record terdampak:
- Nominal/ledger/snapshot/rekening:
- Akses tidak sah atau role bypass:
- Dampak turunan ke laporan, kwitansi, export, Storage, dan pengguna:

## Recovery Decision

| Opsi | Risiko data | Downtime | Dipilih/alasan | Approver |
| --- | --- | --- | --- | --- |
| Rollback aplikasi |  |  |  |  |
| Forward-fix |  |  |  |  |
| Reversal bisnis |  |  |  |  |
| Restore terisolasi/production |  |  |  |  |

## Verification dan Rekonsiliasi

| Test/query | Expected | Actual | Evidence | Reviewer |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

- [ ] Saldo, ledger, snapshot, kwitansi, pembayaran, dan row count terkait cocok.
- [ ] Role/Data API/RPC/Storage terkait diuji kembali.
- [ ] Pengguna operasional mengonfirmasi workflow utama.
- [ ] Observation window selesai tanpa trigger baru.

## Komunikasi

| Waktu | Audience | Pesan ringkas | Pengirim |
| --- | --- | --- | --- |
|  |  |  |  |

## Closure dan Postmortem

- Waktu resolved/closed:
- Dampak aktual:
- Root dan contributing factors:
- Kontrol yang bekerja/gagal:
- `TASK-*` tindak lanjut, owner, target:
- Update test/SOP/PRD/BDR/ADR:
- Persetujuan closure PO + Engineering Lead + QA:

