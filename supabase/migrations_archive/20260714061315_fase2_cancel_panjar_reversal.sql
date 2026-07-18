-- Sawit CB - pembatalan panjar mitra dengan reversal hutang/kas.

BEGIN;

CREATE OR REPLACE FUNCTION public.cancel_panjar_mitra_kas(
  p_panjar_id uuid,
  p_alasan text
)
RETURNS public.panjar_mitra
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_panjar public.panjar_mitra%ROWTYPE;
  v_after public.panjar_mitra%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang membatalkan panjar mitra.'
      USING ERRCODE = '42501';
  END IF;

  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan panjar wajib diisi.'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_panjar
  FROM public.panjar_mitra
  WHERE id = p_panjar_id
  FOR UPDATE;

  IF v_panjar.id IS NULL THEN
    RAISE EXCEPTION 'Panjar tidak ditemukan.'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_panjar.status <> 'belum_lunas' THEN
    RAISE EXCEPTION 'Hanya panjar belum lunas yang bisa dibatalkan.'
      USING ERRCODE = '22023';
  END IF;

  IF v_panjar.hutang_ledger_id IS NOT NULL THEN
    PERFORM public.cancel_hutang_ledger(v_panjar.hutang_ledger_id, p_alasan);
  END IF;

  UPDATE public.panjar_mitra
  SET status = 'dibatalkan',
      alasan_batal = btrim(p_alasan),
      dibatalkan_at = now(),
      dibatalkan_by = v_actor,
      updated_at = now()
  WHERE id = v_panjar.id
  RETURNING * INTO v_after;

  RETURN v_after;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_panjar_mitra_kas(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_panjar_mitra_kas(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.cancel_panjar_mitra_kas(uuid, text) TO authenticated;

COMMIT;
