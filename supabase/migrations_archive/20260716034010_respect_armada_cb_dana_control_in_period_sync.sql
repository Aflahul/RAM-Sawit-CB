BEGIN;

CREATE OR REPLACE FUNCTION public.sync_tarif_sopir_cb_period(
  p_date_from date,
  p_date_to date,
  p_armada_sopir_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_updated_count integer := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Tidak berwenang menyelaraskan Dana Operasional Trip.' USING ERRCODE = '42501';
  END IF;
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Periode tidak valid.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.transaksi_mitra tm
  SET dana_operasional_trip_snapshot = public.resolve_dana_operasional_trip_mitra(tm.mitra_id, tm.tanggal),
      upah_sopir_cb_snapshot = 0,
      uang_jalan_sopir_cb_snapshot = 0,
      total_biaya_sopir_cb_snapshot = public.resolve_dana_operasional_trip_mitra(tm.mitra_id, tm.tanggal)
  WHERE tm.menggunakan_armada_cb_snapshot = true
    AND tm.catat_dana_operasional_trip = true
    AND tm.armada_cb_perlu_review = false
    AND tm.status = 'aktif'
    AND tm.biaya_sopir_dibayar_at IS NULL
    AND tm.tanggal BETWEEN p_date_from AND p_date_to
    AND (p_armada_sopir_id IS NULL OR tm.sopir_id = p_armada_sopir_id);

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  RETURN jsonb_build_object('updated_count', v_updated_count);
END;
$$;

REVOKE ALL ON FUNCTION public.sync_tarif_sopir_cb_period(date, date, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_tarif_sopir_cb_period(date, date, uuid) TO authenticated;

COMMIT;
