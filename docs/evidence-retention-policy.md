# Kebijakan Retensi Bukti Pengembangan dan Operasional

| Metadata | Nilai |
| --- | --- |
| Status | Draft, menunggu validasi Product Owner, Accounting/Legal, dan Data/Security |
| Berlaku sejak | Belum berlaku sampai disetujui |
| Pemilik | Product Owner dan Data/Security Owner |
| Tujuan | Menjaga bukti dapat ditelusuri tanpa menyimpan data lebih lama atau lebih luas dari kebutuhan |

## 1. Prinsip

1. Retensi mengikuti kebutuhan bisnis, audit, keamanan, dan kewajiban hukum yang telah divalidasi, bukan asumsi teknis.
2. Data pribadi diminimalkan, dienkripsi saat transit/tersimpan, dan hanya dapat diakses oleh identitas yang berwenang.
3. Bukti release/audit harus tahan perubahan diam-diam melalui system of record, immutable artifact, checksum, atau kontrol ekuivalen.
4. Secret, token, password, service-role key, dan dump production tidak boleh disimpan sebagai bukti biasa.
5. Legal hold menghentikan penghapusan terjadwal untuk scope yang sedang diperiksa.
6. Setelah masa retensi berakhir, data dihapus secara terverifikasi kecuali ada hold atau kewajiban yang lebih panjang.

## 2. Jadwal Retensi Usulan

Angka di bawah adalah **usulan internal**, bukan pernyataan kewajiban hukum. Product Owner wajib memvalidasinya dengan fungsi accounting/legal sebelum policy berstatus aktif.

| Kategori | Contoh | System of record | Usulan masa simpan | Owner akses |
| --- | --- | --- | --- | --- |
| Source dan review | Git commit, PR, ADR/BDR | Private GitHub repository | Selama produk aktif + 2 tahun | Engineering Lead |
| CI dan test biasa | Raw lint/build/unit/E2E output | CI artifact store | 24 bulan | QA/Engineering |
| Release dan migration | Commit SHA, migration hash/list, ACL matrix, approval, reconciliation | Release record + restricted artifact store | 10 tahun, pending legal/accounting | Release + Data/Security |
| Bukti finansial/audit | Kwitansi, approval, reversal, audit trail, ledger evidence | Database/Storage bisnis terkontrol | 10 tahun, pending legal/accounting | Product Owner/Finance |
| Auth/security evidence | Auth attestation, access review, security test, key-rotation record | Restricted security store | 5 tahun | Data/Security |
| Incident/postmortem | Timeline, evidence, recovery, communication | Restricted incident system | 5 tahun | Incident Commander/Security |
| Backup | Database/Storage backup dan restore evidence | Provider backup + encrypted off-site bila disetujui | Sesuai RPO/RTO, tier, dan legal hold | Release/Data Owner |
| UX research | Rekaman/screenshot pengguna, catatan observasi | Restricted research folder | Maksimal 12 bulan atau sampai tujuan selesai | UX/Product |

## 3. Metadata Bukti Wajib

- ID `TEST/AUD/TASK/INC/EXC/Release`;
- commit SHA/build/deployment/migration version;
- environment dan target project yang disanitasi;
- waktu WIB dan UTC;
- executor, reviewer independen, dan approver;
- expected, actual, result, serta checksum bila relevan;
- klasifikasi data, retention category, expiry, dan legal-hold status.

## 4. Akses dan Integritas

- Gunakan least privilege dan MFA untuk penyimpanan bukti sensitif.
- Pisahkan bukti umum PR dari bukti production yang mengandung ID/nominal/PII.
- Setiap akses atau perubahan bukti sensitif diaudit.
- Jangan menaruh raw dump, screenshot PII, atau log token di issue/PR umum.
- Artifact penting diberi checksum/signature atau disimpan pada media/versioning yang tidak dapat diubah tanpa jejak.
- Review akses dilakukan minimal per kuartal dan saat anggota tim/role berubah.

## 5. Legal Hold dan Penghapusan

Legal/accounting hold minimal mencatat scope, alasan, requester, approver, tanggal mulai, review date, dan kriteria pelepasan. Saat hold dilepas atau retention habis:

1. owner memverifikasi tidak ada dependency audit/incident/legal aktif;
2. data dihapus dari system utama dan antrean disposal backup sesuai kemampuan provider;
3. disposal dicatat tanpa menyalin isi sensitif yang telah dihapus;
4. akses/link/index terkait diperbarui.

## 6. Gate Aktivasi

Policy ini menjadi aktif setelah:

- [ ] Product Owner menyetujui kebutuhan bisnis.
- [ ] Accounting/legal memvalidasi kategori dan durasi.
- [ ] Data/Security memvalidasi enkripsi, system of record, legal hold, dan disposal.
- [ ] QA/Release memvalidasi evidence upload/retrieval pada satu release rehearsal.
- [ ] Owner tiap kategori dan review calendar ditetapkan.

Sampai itu selesai, evidence tidak boleh dihapus hanya berdasarkan tabel usulan ini. Gunakan keputusan khusus yang terdokumentasi dan pertahankan data minimum yang diperlukan.

