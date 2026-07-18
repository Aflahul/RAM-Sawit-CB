# Work Package: <Judul>

| Field | Nilai |
| --- | --- |
| ID | `TASK-<DOMAIN>-NNN` |
| Status | Draft / Ready / In Progress / Review / Verified / Released / Blocked |
| Prioritas | P0 / P1 / P2 / P3 |
| Severity terkait | S0 / S1 / S2 / S3 / N/A |
| Kelas risiko | KR0 / KR1 / KR2 / KR3 / KR4 |
| Jenis perubahan | UI / aplikasi / dependency / data / migration / auth / security / operasi |
| Klasifikasi data | Publik / internal / pribadi / finansial sensitif |
| Environment | Local / Development / Staging / Production |
| Work package owner |  |
| Author/implementer | Identitas manusia |
| Reviewer independen | Identitas manusia + peran Business / UX/UI / Data / Security / QA |
| Approver | Identitas manusia + kewenangan |
| Separation of duties | Maker, checker, release operator, dan kombinasi yang dilarang |
| Target release |  |
| Tautan requirement | `BR-*`, `FLOW-*`, `AC-*` |
| Tautan temuan/keputusan | `AUD-*`, `BDR-*`, `ADR-*` |

## Tujuan

Jelaskan hasil pengguna/bisnis yang harus tercapai.

## Scope

### Masuk

-

### Tidak masuk

-

## Pengguna dan Alur

| Role | Pemicu | Langkah utama | Hasil |
| --- | --- | --- | --- |
|  |  |  |  |

## Aturan Bisnis dan Data

- Sumber data:
- Formula/status:
- Snapshot/ledger/audit:
- Permission:
- Dampak histori/migration:

## Kepemilikan Implementasi

| Area/file | Implementer | Reviewer independen | Catatan dependency |
| --- | --- | --- | --- |
|  |  |  |  |

Satu orang yang memakai beberapa topi peran tetap dihitung sebagai satu identitas. Untuk `KR3/KR4`, author tidak boleh menjadi satu-satunya reviewer atau pemberi keputusan Go. Perubahan setelah approval membatalkan approval yang terdampak.

## Acceptance Criteria

- [ ] `AC-<DOMAIN>-NNN`:
- [ ] Happy path terverifikasi.
- [ ] Validation, empty, loading, error, retry, cancel/reversal, dan permission relevan terverifikasi.
- [ ] Tidak ada regresi pada laporan, snapshot, kas, kwitansi, atau role terkait.

## Verification Plan

| ID test | Skenario | Role/data | Expected | Bukti |
| --- | --- | --- | --- | --- |
| `TEST-<DOMAIN>-NNN` |  |  |  |  |

Perintah verifikasi:

```powershell
npm run lint
npm run build
git diff --check
```

Tambahkan perintah database, unit, integration, atau browser test sesuai risiko.

## Risiko dan Rollback

| Risiko | Dampak | Pencegahan | Trigger rollback | Langkah pemulihan |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

## Handoff

- File diubah:
- Test dijalankan:
- Asumsi/batas:
- Risiko tersisa:
- Dokumen diperbarui:
