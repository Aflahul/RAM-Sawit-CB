-- Owner-only reconciliation for legacy partner advances that have a receipt
-- deduction but no opening loan row. This never creates a cash mutation.

CREATE OR REPLACE FUNCTION public.reconcile_legacy_panjar_opening(
  p_panjar_id uuid,
  p_alasan text
)
RETURNS public.hutang_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.panjar_mitra%ROWTYPE;
  v_after public.panjar_mitra%ROWTYPE;
  v_settlement public.hutang_ledger%ROWTYPE;
  v_opening public.hutang_ledger%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR public.current_app_role() NOT IN ('owner', 'super_admin') THEN
    RAISE EXCEPTION 'Hanya Owner atau Super Admin yang dapat mencocokkan data lama.' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(btrim(COALESCE(p_alasan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Dasar pencocokan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before
  FROM public.panjar_mitra
  WHERE id = p_panjar_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Panjar lama tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF v_before.hutang_ledger_id IS NOT NULL THEN
    RAISE EXCEPTION 'Catatan pemberian pinjaman awal sudah tersedia.' USING ERRCODE = '22023';
  END IF;
  IF v_before.settlement_hutang_ledger_id IS NULL THEN
    RAISE EXCEPTION 'Panjar ini tidak memiliki catatan potongan kwitansi untuk dicocokkan.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_settlement
  FROM public.hutang_ledger
  WHERE id = v_before.settlement_hutang_ledger_id
  FOR UPDATE;

  IF v_settlement.id IS NULL
     OR v_settlement.status <> 'aktif'
     OR v_settlement.tipe <> 'kredit'
     OR v_settlement.master_mitra_id IS DISTINCT FROM v_before.mitra_id
     OR v_settlement.jumlah < v_before.jumlah THEN
    RAISE EXCEPTION 'Catatan potongan kwitansi tidak sesuai dengan panjar. Periksa kwitansi sebelum melanjutkan.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_opening
  FROM public.create_hutang_pihak(
    'mitra',
    'debit',
    'panjar',
    v_before.jumlah,
    v_before.tanggal,
    NULL,
    v_before.mitra_id,
    NULL,
    NULL,
    'Saldo awal pinjaman lama: ' || COALESCE(NULLIF(btrim(v_before.keterangan), ''), 'Panjar Mitra'),
    NULL,
    false,
    'panjar_mitra_opening_reconciliation',
    v_before.id
  );

  UPDATE public.panjar_mitra
  SET hutang_ledger_id = v_opening.id,
      updated_at = now()
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  PERFORM public.write_audit_log(
    'panjar_mitra',
    v_before.id,
    'reconcile_legacy_opening',
    to_jsonb(v_before),
    to_jsonb(v_after) || jsonb_build_object('opening_hutang_ledger_id', v_opening.id),
    btrim(p_alasan) || ' (tanpa mutasi Buku Kas)',
    v_actor
  );

  RETURN v_opening;
END;
$$;

REVOKE ALL ON FUNCTION public.reconcile_legacy_panjar_opening(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reconcile_legacy_panjar_opening(uuid, text) TO authenticated;
