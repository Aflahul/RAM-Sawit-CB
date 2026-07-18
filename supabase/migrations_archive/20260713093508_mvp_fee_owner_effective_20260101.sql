-- Sawit CB - Koreksi tanggal berlaku Fee Owner per 2026-01-01
--
-- Migration sebelumnya (`20260713092933_mvp_fee_owner_input_20260713.sql`)
-- sudah memasukkan nominal fee yang benar, tetapi `berlaku_mulai` masih memakai
-- tanggal input 2026-07-13. Sesuai keputusan bisnis, daftar fee tersebut
-- berlaku sejak 1 Januari 2026.
--
-- Catatan keputusan tetap sama:
-- - BL/ML muncul di daftar fee 20 dan fee 30; nilai final mengikuti daftar terakhir = 30.
-- - SL/IMN dari input diarahkan ke master_mitra SL/IMAN.
-- - SL/WND tidak ada di master_mitra saat koreksi ini dibuat; tidak dibuat otomatis.

BEGIN;

CREATE TEMP TABLE tmp_mvp_fee_owner_effective_20260101 (
  kode text PRIMARY KEY,
  fee_per_kg numeric(12,2) NOT NULL,
  catatan text
) ON COMMIT DROP;

INSERT INTO tmp_mvp_fee_owner_effective_20260101 (kode, fee_per_kg, catatan) VALUES
  ('SL', 20, NULL),
  ('BL', 20, NULL),
  ('SL/NL', 20, NULL),
  ('SL/CHT', 20, NULL),
  ('SL/F', 30, NULL),
  ('SL/MLD', 30, 'Input SL/MLD muncul dua kali di daftar fee 30'),
  ('SL/BS', 30, NULL),
  ('SL/HB', 30, NULL),
  ('SL/SW', 30, NULL),
  ('SL/WRD', 30, NULL),
  ('SL/ANC', 30, NULL),
  ('SL/B', 30, NULL),
  ('SL/IMAN', 30, 'Alias dari input SL/IMN'),
  ('SL/NSL', 30, NULL),
  ('BL/P', 30, NULL),
  ('BL/ML', 30, 'BL/ML muncul di fee 20 dan fee 30; nilai final mengikuti daftar terakhir = 30');

UPDATE public.master_mitra mm
SET fee_per_kg = fee.fee_per_kg
FROM tmp_mvp_fee_owner_effective_20260101 fee
WHERE upper(btrim(mm.kode)) = upper(fee.kode);

INSERT INTO public.fee_owner_mitra_history (
  master_mitra_id,
  fee_per_kg,
  berlaku_mulai,
  alasan_perubahan
)
SELECT
  mm.id,
  fee.fee_per_kg,
  DATE '2026-01-01',
  concat_ws(
    ' - ',
    'Koreksi tanggal berlaku Fee Owner: input user 2026-07-13 berlaku mulai 2026-01-01',
    fee.catatan
  )
FROM tmp_mvp_fee_owner_effective_20260101 fee
JOIN public.master_mitra mm ON upper(btrim(mm.kode)) = upper(fee.kode)
ON CONFLICT (master_mitra_id, berlaku_mulai) DO UPDATE
SET fee_per_kg = EXCLUDED.fee_per_kg,
    alasan_perubahan = EXCLUDED.alasan_perubahan;

UPDATE public.transaksi_mitra tm
SET fee_owner_history_id = new_history.id
FROM public.fee_owner_mitra_history old_history
JOIN public.fee_owner_mitra_history new_history
  ON new_history.master_mitra_id = old_history.master_mitra_id
JOIN public.master_mitra mm
  ON mm.id = old_history.master_mitra_id
JOIN tmp_mvp_fee_owner_effective_20260101 fee
  ON upper(btrim(mm.kode)) = upper(fee.kode)
WHERE tm.fee_owner_history_id = old_history.id
  AND old_history.berlaku_mulai = DATE '2026-07-13'
  AND old_history.alasan_perubahan LIKE 'Input Fee Owner sesuai daftar user 2026-07-13%'
  AND new_history.berlaku_mulai = DATE '2026-01-01';

DELETE FROM public.fee_owner_mitra_history h
USING public.master_mitra mm, tmp_mvp_fee_owner_effective_20260101 fee
WHERE h.master_mitra_id = mm.id
  AND upper(btrim(mm.kode)) = upper(fee.kode)
  AND h.berlaku_mulai = DATE '2026-07-13'
  AND h.alasan_perubahan LIKE 'Input Fee Owner sesuai daftar user 2026-07-13%'
  AND NOT EXISTS (
    SELECT 1
    FROM public.transaksi_mitra tm
    WHERE tm.fee_owner_history_id = h.id
  );

COMMIT;
