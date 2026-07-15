-- Bekukan rincian sewa pada kwitansi yang sudah terbit.
-- Nilai pembayaran lama tidak diubah; kolom tambahan hanya menyimpan dasar audit.

BEGIN;

ALTER TABLE public.pembayaran_mitra_kwitansi_item
  ADD COLUMN IF NOT EXISTS tarif_sewa_angkut_per_kg_snapshot numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS biaya_sewa_armada_standar_snapshot numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS selisih_sewa_armada_historis_snapshot numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS metode_sewa_armada_snapshot text NOT NULL DEFAULT 'tidak_ada';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'pembayaran_mitra_item_metode_sewa_check'
      AND conrelid = 'public.pembayaran_mitra_kwitansi_item'::regclass
  ) THEN
    ALTER TABLE public.pembayaran_mitra_kwitansi_item
      ADD CONSTRAINT pembayaran_mitra_item_metode_sewa_check
      CHECK (
        metode_sewa_armada_snapshot IN (
          'tidak_ada',
          'netto_x_tarif',
          'legacy_snapshot'
        )
      ) NOT VALID;
  END IF;
END;
$$;

COMMENT ON COLUMN public.pembayaran_mitra_kwitansi_item.biaya_sewa_armada_snapshot IS
  'Nominal sewa yang benar-benar ditagihkan pada kwitansi. Snapshot finansial ini tidak boleh mengikuti perubahan transaksi live.';
COMMENT ON COLUMN public.pembayaran_mitra_kwitansi_item.tarif_sewa_angkut_per_kg_snapshot IS
  'Tarif sewa per kg saat kwitansi diterbitkan.';
COMMENT ON COLUMN public.pembayaran_mitra_kwitansi_item.biaya_sewa_armada_standar_snapshot IS
  'Sewa standar saat kwitansi diterbitkan: berat netto snapshot dikali tarif snapshot.';
COMMENT ON COLUMN public.pembayaran_mitra_kwitansi_item.selisih_sewa_armada_historis_snapshot IS
  'Sewa standar dikurangi sewa yang ditagihkan. Positif berarti kwitansi lama menagihkan lebih kecil.';
COMMENT ON COLUMN public.pembayaran_mitra_kwitansi_item.metode_sewa_armada_snapshot IS
  'netto_x_tarif untuk rumus aktif; legacy_snapshot jika nominal historis berbeda atau dasar tarif lama tidak lengkap.';

-- Backfill hanya mengisi metadata audit. biaya_sewa_armada_snapshot tetap utuh.
WITH snapshot_source AS (
  SELECT
    item.id,
    COALESCE(item.pakai_sewa_armada_snapshot, false) AS pakai_sewa,
    GREATEST(COALESCE(item.berat_netto_snapshot, item.tonase_snapshot, 0), 0) AS berat_netto,
    GREATEST(COALESCE(
      NULLIF(tm.tarif_sewa_angkut_per_kg_snapshot, 0),
      NULLIF(tm.biaya_sewa_armada_per_kg, 0),
      0
    ), 0) AS tarif,
    GREATEST(COALESCE(item.biaya_sewa_armada_snapshot, 0), 0) AS sewa_ditagihkan
  FROM public.pembayaran_mitra_kwitansi_item item
  LEFT JOIN public.transaksi_mitra tm ON tm.id = item.transaksi_mitra_id
), calculated AS (
  SELECT
    id,
    pakai_sewa,
    tarif,
    sewa_ditagihkan,
    CASE
      WHEN NOT pakai_sewa THEN 0
      WHEN berat_netto > 0 AND tarif > 0 THEN round(berat_netto * tarif, 2)
      ELSE sewa_ditagihkan
    END AS sewa_standar
  FROM snapshot_source
)
UPDATE public.pembayaran_mitra_kwitansi_item item
SET tarif_sewa_angkut_per_kg_snapshot = calculated.tarif,
    biaya_sewa_armada_standar_snapshot = calculated.sewa_standar,
    selisih_sewa_armada_historis_snapshot = calculated.sewa_standar - calculated.sewa_ditagihkan,
    metode_sewa_armada_snapshot = CASE
      WHEN NOT calculated.pakai_sewa THEN 'tidak_ada'
      WHEN calculated.tarif <= 0 THEN 'legacy_snapshot'
      WHEN abs(calculated.sewa_standar - calculated.sewa_ditagihkan) <= 0.01 THEN 'netto_x_tarif'
      ELSE 'legacy_snapshot'
    END
FROM calculated
WHERE item.id = calculated.id;

ALTER TABLE public.pembayaran_mitra_kwitansi_item
  VALIDATE CONSTRAINT pembayaran_mitra_item_metode_sewa_check;

-- Kwitansi baru mendapatkan snapshot turunan tanpa memperbesar RPC pembayaran.
CREATE OR REPLACE FUNCTION public.snapshot_sewa_item_kwitansi()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_transaksi public.transaksi_mitra%ROWTYPE;
  v_berat_netto numeric(15,2) := 0;
  v_tarif numeric(12,2) := 0;
  v_sewa_ditagihkan numeric(15,2) := 0;
  v_sewa_standar numeric(15,2) := 0;
BEGIN
  SELECT * INTO v_transaksi
  FROM public.transaksi_mitra
  WHERE id = NEW.transaksi_mitra_id;

  IF v_transaksi.id IS NULL THEN
    RAISE EXCEPTION 'Transaksi sumber item kwitansi tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  IF NOT COALESCE(NEW.pakai_sewa_armada_snapshot, false) THEN
    NEW.tarif_sewa_angkut_per_kg_snapshot := 0;
    NEW.biaya_sewa_armada_standar_snapshot := 0;
    NEW.selisih_sewa_armada_historis_snapshot := 0;
    NEW.metode_sewa_armada_snapshot := 'tidak_ada';
    RETURN NEW;
  END IF;

  v_berat_netto := GREATEST(COALESCE(NEW.berat_netto_snapshot, NEW.tonase_snapshot, 0), 0);
  v_tarif := GREATEST(COALESCE(
    NULLIF(v_transaksi.tarif_sewa_angkut_per_kg_snapshot, 0),
    NULLIF(v_transaksi.biaya_sewa_armada_per_kg, 0),
    0
  ), 0);
  v_sewa_ditagihkan := GREATEST(COALESCE(NEW.biaya_sewa_armada_snapshot, 0), 0);
  v_sewa_standar := CASE
    WHEN v_berat_netto > 0 AND v_tarif > 0 THEN round(v_berat_netto * v_tarif, 2)
    ELSE v_sewa_ditagihkan
  END;

  NEW.tarif_sewa_angkut_per_kg_snapshot := v_tarif;
  NEW.biaya_sewa_armada_standar_snapshot := v_sewa_standar;
  NEW.selisih_sewa_armada_historis_snapshot := v_sewa_standar - v_sewa_ditagihkan;
  NEW.metode_sewa_armada_snapshot := CASE
    WHEN v_tarif > 0 AND abs(v_sewa_standar - v_sewa_ditagihkan) <= 0.01
      THEN 'netto_x_tarif'
    ELSE 'legacy_snapshot'
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS snapshot_sewa_item_kwitansi
  ON public.pembayaran_mitra_kwitansi_item;
CREATE TRIGGER snapshot_sewa_item_kwitansi
  BEFORE INSERT ON public.pembayaran_mitra_kwitansi_item
  FOR EACH ROW
  EXECUTE FUNCTION public.snapshot_sewa_item_kwitansi();

-- Item adalah bukti transaksi. Koreksi dilakukan dengan pembatalan header dan
-- penerbitan kwitansi baru, bukan mengedit snapshot lama.
CREATE OR REPLACE FUNCTION public.prevent_kwitansi_item_snapshot_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'Detail kwitansi yang sudah terbit tidak dapat diubah. Batalkan kwitansi dan terbitkan yang baru.'
      USING ERRCODE = '55000';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS prevent_kwitansi_item_snapshot_update
  ON public.pembayaran_mitra_kwitansi_item;
CREATE TRIGGER prevent_kwitansi_item_snapshot_update
  BEFORE UPDATE ON public.pembayaran_mitra_kwitansi_item
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_kwitansi_item_snapshot_update();

REVOKE INSERT, UPDATE, DELETE ON public.pembayaran_mitra_kwitansi_item FROM authenticated, anon;
GRANT SELECT ON public.pembayaran_mitra_kwitansi_item TO authenticated;

REVOKE ALL ON FUNCTION public.snapshot_sewa_item_kwitansi() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.prevent_kwitansi_item_snapshot_update() FROM PUBLIC, anon, authenticated;

COMMIT;
