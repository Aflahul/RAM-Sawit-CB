-- Follow-up for the already deployed piutang workflow: controlled reversal of
-- repayment rows and reopening partner advances when a TBS receipt is reversed.

CREATE OR REPLACE FUNCTION public.cancel_piutang_repayment(p_payment_id uuid, p_alasan text)
RETURNS public.piutang_pelunasan
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.piutang_pelunasan%ROWTYPE;
  v_after public.piutang_pelunasan%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR public.current_app_role() NOT IN ('owner', 'super_admin') THEN
    RAISE EXCEPTION 'Hanya Owner atau Super Admin yang dapat membatalkan pengembalian.' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(btrim(COALESCE(p_alasan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before FROM public.piutang_pelunasan WHERE id = p_payment_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'Pengembalian tidak ditemukan.' USING ERRCODE = 'P0002'; END IF;
  IF v_before.status <> 'aktif' THEN RAISE EXCEPTION 'Pengembalian ini sudah dibatalkan.' USING ERRCODE = '22023'; END IF;

  PERFORM public.cancel_hutang_ledger(v_before.hutang_ledger_id, p_alasan);
  UPDATE public.piutang_pelunasan SET status = 'dibatalkan' WHERE id = v_before.id RETURNING * INTO v_after;
  UPDATE public.piutang_dokumen SET status = 'diserahkan', updated_at = now()
  WHERE id = v_before.piutang_dokumen_id AND status = 'lunas';

  PERFORM public.write_audit_log(
    'piutang_pelunasan', v_after.id, 'cancel', to_jsonb(v_before), to_jsonb(v_after), p_alasan, v_actor
  );
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_piutang_document_from_panjar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'lunas' AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE public.piutang_dokumen SET status = 'lunas', updated_at = now()
    WHERE panjar_mitra_id = NEW.id AND status = 'diserahkan';
  ELSIF NEW.status = 'belum_lunas' AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE public.piutang_dokumen SET status = 'diserahkan', updated_at = now()
    WHERE panjar_mitra_id = NEW.id AND status = 'lunas';
  ELSIF NEW.status = 'dibatalkan' AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE public.piutang_dokumen SET status = 'dibatalkan', updated_at = now()
    WHERE panjar_mitra_id = NEW.id AND status <> 'dibatalkan';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_piutang_repayment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_piutang_repayment(uuid, text) TO authenticated;
