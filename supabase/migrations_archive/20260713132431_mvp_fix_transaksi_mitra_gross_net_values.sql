-- Sawit CB - koreksi nilai kotor pabrik vs nilai bersih mitra
--
-- Latar belakang:
-- Beberapa transaksi MVP sempat menyimpan harga_harian/total_kotor memakai
-- harga bersih mitra. Setelah ada snapshot fee owner, harga_harian/total_kotor
-- harus merepresentasikan harga/nilai kotor pabrik, sementara
-- harga_bersih_per_kg/total_nilai_bersih merepresentasikan hak mitra.

BEGIN;

UPDATE public.transaksi_mitra tm
SET
  harga_pabrik_per_kg = COALESCE(tm.harga_pabrik_per_kg, tm.harga_bersih_per_kg + tm.fee_owner_per_kg),
  harga_harian = COALESCE(tm.harga_pabrik_per_kg, tm.harga_bersih_per_kg + tm.fee_owner_per_kg, tm.harga_harian),
  total_kotor = ROUND(tm.tonase * COALESCE(tm.harga_pabrik_per_kg, tm.harga_bersih_per_kg + tm.fee_owner_per_kg, tm.harga_harian)),
  harga_bersih_per_kg = COALESCE(tm.harga_bersih_per_kg, GREATEST(COALESCE(tm.harga_pabrik_per_kg, tm.harga_harian) - COALESCE(tm.fee_owner_per_kg, 0), 0)),
  total_fee_owner = ROUND(tm.tonase * COALESCE(tm.fee_owner_per_kg, 0)),
  total_nilai_bersih = ROUND(tm.tonase * COALESCE(
    tm.harga_bersih_per_kg,
    GREATEST(COALESCE(tm.harga_pabrik_per_kg, tm.harga_harian) - COALESCE(tm.fee_owner_per_kg, 0), 0)
  ))
WHERE tm.tonase IS NOT NULL
  AND (
    tm.harga_pabrik_per_kg IS NOT NULL
    OR (tm.harga_bersih_per_kg IS NOT NULL AND tm.fee_owner_per_kg IS NOT NULL)
    OR tm.fee_owner_per_kg IS NOT NULL
  );

COMMIT;
