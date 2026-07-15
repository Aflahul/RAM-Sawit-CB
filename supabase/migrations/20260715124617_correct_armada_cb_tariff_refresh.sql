-- Saat mitra/tanggal/sopir pada trip belum dibayar berubah, kedua snapshot
-- Armada CB harus mengikuti mitra baru. Edit berat saja tetap memakai snapshot.

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_transaksi_mitra_armada_cb()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sopir public.sopir%ROWTYPE;
  v_is_armada_cb boolean := false;
  v_berat_netto numeric(15,2) := 0;
  v_tarif_sewa numeric(15,2) := 0;
  v_tarif_sewa_mitra numeric(15,2) := 0;
  v_dana_trip numeric(15,2) := 0;
  v_refresh_snapshot boolean := false;
BEGIN
  SELECT * INTO v_sopir
  FROM public.sopir
  WHERE id = NEW.sopir_id;

  v_is_armada_cb := COALESCE(v_sopir.is_armada_cb, false);
  NEW.pakai_sewa_armada_bl := v_is_armada_cb;

  v_refresh_snapshot := TG_OP = 'INSERT';
  IF TG_OP = 'UPDATE' THEN
    v_refresh_snapshot := OLD.biaya_sopir_dibayar_at IS NULL
      AND (
        OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
        OR OLD.mitra_id IS DISTINCT FROM NEW.mitra_id
        OR OLD.tanggal IS DISTINCT FROM NEW.tanggal
      );
  END IF;

  IF NEW.mitra_id IS NOT NULL THEN
    SELECT
      COALESCE(h.tarif_sewa_angkut_per_kg, mm.tarif_sewa_angkut_per_kg, 0),
      COALESCE(h.dana_operasional_trip, mm.dana_operasional_trip, 0)
    INTO v_tarif_sewa_mitra, v_dana_trip
    FROM public.master_mitra mm
    LEFT JOIN LATERAL (
      SELECT fh.tarif_sewa_angkut_per_kg, fh.dana_operasional_trip
      FROM public.fee_owner_mitra_history fh
      WHERE fh.master_mitra_id = mm.id
        AND fh.aktif = true
        AND fh.berlaku_mulai <= NEW.tanggal
        AND (fh.berlaku_sampai IS NULL OR fh.berlaku_sampai >= NEW.tanggal)
      ORDER BY fh.berlaku_mulai DESC, fh.created_at DESC
      LIMIT 1
    ) h ON true
    WHERE mm.id = NEW.mitra_id;
  END IF;

  v_berat_netto := GREATEST(COALESCE(NEW.berat_netto_pabrik_kg, NEW.tonase, 0), 0);
  IF v_refresh_snapshot THEN
    v_tarif_sewa := GREATEST(COALESCE(v_tarif_sewa_mitra, 0), 0);
  ELSE
    v_tarif_sewa := GREATEST(COALESCE(
      NULLIF(NEW.tarif_sewa_angkut_per_kg_snapshot, 0),
      NULLIF(NEW.biaya_sewa_armada_per_kg, 0),
      v_tarif_sewa_mitra,
      0
    ), 0);
  END IF;

  IF v_is_armada_cb THEN
    NEW.tarif_sewa_angkut_per_kg_snapshot := v_tarif_sewa;
    NEW.biaya_sewa_armada_per_kg := v_tarif_sewa;
    NEW.biaya_sewa_armada_kotor := round(v_berat_netto * v_tarif_sewa, 2);
    NEW.biaya_sewa_armada_total := NEW.biaya_sewa_armada_kotor;
  ELSE
    NEW.tarif_sewa_angkut_per_kg_snapshot := 0;
    NEW.biaya_sewa_armada_per_kg := 0;
    NEW.biaya_sewa_armada_kotor := 0;
    NEW.biaya_sewa_armada_total := 0;
  END IF;

  IF v_refresh_snapshot THEN
    IF v_is_armada_cb THEN
      NEW.dana_operasional_trip_snapshot := GREATEST(COALESCE(v_dana_trip, 0), 0);
      NEW.upah_sopir_cb_snapshot := 0;
      NEW.uang_jalan_sopir_cb_snapshot := 0;
      NEW.total_biaya_sopir_cb_snapshot := NEW.dana_operasional_trip_snapshot;
      NEW.nominal_perongkosan_snapshot := 0;
    ELSE
      NEW.dana_operasional_trip_snapshot := 0;
      NEW.upah_sopir_cb_snapshot := 0;
      NEW.uang_jalan_sopir_cb_snapshot := 0;
      NEW.total_biaya_sopir_cb_snapshot := 0;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.normalize_transaksi_mitra_armada_cb() FROM PUBLIC, anon, authenticated;

COMMIT;
