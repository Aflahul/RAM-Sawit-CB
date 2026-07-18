-- Sawit CB - Finalisasi fee BL/ML = 30/kg
--
-- BL/ML sempat muncul di daftar fee 20 dan 30. Keputusan MVP mengikuti
-- daftar terakhir: BL/ML = 30/kg berlaku mulai 2026-01-01.

BEGIN;

WITH target_mitra AS (
  UPDATE public.master_mitra mm
  SET fee_per_kg = 30
  WHERE upper(btrim(mm.kode)) = 'BL/ML'
  RETURNING mm.id
)
INSERT INTO public.fee_owner_mitra_history (
  master_mitra_id,
  fee_per_kg,
  berlaku_mulai,
  berlaku_sampai,
  aktif
)
SELECT
  id,
  30,
  DATE '2026-01-01',
  NULL,
  true
FROM target_mitra
ON CONFLICT (master_mitra_id, berlaku_mulai)
DO UPDATE SET
  fee_per_kg = EXCLUDED.fee_per_kg,
  berlaku_sampai = NULL,
  aktif = true;

WITH target_history AS (
  SELECT h.id AS history_id, mm.id AS mitra_id
  FROM public.master_mitra mm
  JOIN public.fee_owner_mitra_history h
    ON h.master_mitra_id = mm.id
   AND h.berlaku_mulai = DATE '2026-01-01'
  WHERE upper(btrim(mm.kode)) = 'BL/ML'
)
UPDATE public.transaksi_mitra tm
SET
  fee_owner_per_kg = 30,
  fee_owner_history_id = target_history.history_id,
  harga_pabrik_per_kg = COALESCE(tm.harga_pabrik_per_kg, tm.harga_harian),
  harga_harian = COALESCE(tm.harga_pabrik_per_kg, tm.harga_harian),
  harga_bersih_per_kg = GREATEST(COALESCE(tm.harga_pabrik_per_kg, tm.harga_harian) - 30, 0),
  total_kotor = ROUND(tm.tonase * COALESCE(tm.harga_pabrik_per_kg, tm.harga_harian)),
  total_fee_owner = ROUND(tm.tonase * 30),
  total_nilai_bersih = ROUND(tm.tonase * GREATEST(COALESCE(tm.harga_pabrik_per_kg, tm.harga_harian) - 30, 0))
FROM target_history
WHERE tm.mitra_id = target_history.mitra_id
  AND tm.tanggal >= DATE '2026-01-01'
  AND COALESCE(tm.status, 'aktif') <> 'dibatalkan';

COMMIT;
