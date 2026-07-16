-- Keep the cancellation routine warning-free without changing its behavior.
CREATE OR REPLACE FUNCTION public.cancel_biaya_operasional_kas(p_biaya_id uuid, p_alasan text)
RETURNS public.biaya_operasional
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.biaya_operasional%ROWTYPE;
  v_after public.biaya_operasional%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Tidak berwenang membatalkan biaya operasional.' USING ERRCODE = '42501';
  END IF;

  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before
  FROM public.biaya_operasional
  WHERE id = p_biaya_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Biaya operasional tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_before.status, 'aktif') <> 'aktif' THEN
    RAISE EXCEPTION 'Biaya operasional sudah tidak aktif.' USING ERRCODE = '22023';
  END IF;

  IF v_before.kas_ledger_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.kas_ledger
       WHERE reversal_of_id = v_before.kas_ledger_id
         AND status = 'aktif'
     ) THEN
    INSERT INTO public.kas_ledger (
      rekening_kas_id, tanggal, tipe, sumber, jumlah,
      biaya_operasional_id, source_table, source_id, reversal_of_id,
      idempotency_key, keterangan, created_by
    ) VALUES (
      COALESCE(v_before.rekening_kas_id, public.get_default_rekening_kas_id()),
      v_before.tanggal, 'masuk', 'reversal', v_before.jumlah,
      v_before.id, 'biaya_operasional', v_before.id, v_before.kas_ledger_id,
      'biaya_operasional:' || v_before.id::text || ':reversal',
      'Reversal biaya: ' || btrim(p_alasan), v_actor
    );
  END IF;

  UPDATE public.biaya_operasional
  SET status = 'dibatalkan',
      alasan_batal = btrim(p_alasan),
      dibatalkan_at = now(),
      dibatalkan_by = v_actor
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  RETURN v_after;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_biaya_operasional_kas(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_biaya_operasional_kas(uuid, text) TO authenticated;

-- Transaction corrections are atomic: data and audit either both succeed or
-- both roll back. Only the fields used by the correction form are accepted.
CREATE OR REPLACE FUNCTION public.update_transaksi_mitra_controlled(
  p_transaksi_id uuid,
  p_changes jsonb,
  p_alasan text
)
RETURNS public.transaksi_mitra
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.transaksi_mitra%ROWTYPE;
  v_candidate public.transaksi_mitra%ROWTYPE;
  v_after public.transaksi_mitra%ROWTYPE;
  v_unknown_key text;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang mengoreksi pengiriman.' USING ERRCODE = '42501';
  END IF;
  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan koreksi wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before
  FROM public.transaksi_mitra
  WHERE id = p_transaksi_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Pengiriman tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF v_before.status = 'dibatalkan' THEN
    RAISE EXCEPTION 'Pengiriman sudah dibatalkan.' USING ERRCODE = '22023';
  END IF;

  SELECT key INTO v_unknown_key
  FROM jsonb_object_keys(COALESCE(p_changes, '{}'::jsonb)) key
  WHERE key <> ALL (ARRAY[
    'tanggal', 'sopir_id', 'sopir_default_id', 'sopir_default_nama',
    'mitra_id', 'plat_nomor', 'sopir_aktual_id', 'sopir_aktual_nama',
    'sopir_aktual_no_hp', 'sopir_aktual_source', 'sopir_diganti_dari_default',
    'catatan_sopir', 'tonase', 'berat_netto_pabrik_kg',
    'potongan_pabrik_kg', 'berat_dibayar_kg', 'harga_harian',
    'harga_pabrik_per_kg', 'fee_owner_per_kg', 'harga_bersih_per_kg',
    'fee_owner_history_id', 'total_kotor', 'total_fee_owner',
    'total_nilai_bersih', 'pakai_sewa_armada_bl',
    'biaya_sewa_armada_per_kg', 'tarif_sewa_angkut_per_kg_snapshot',
    'biaya_sewa_armada_kotor', 'biaya_sewa_armada_total'
  ])
  LIMIT 1;

  IF v_unknown_key IS NOT NULL THEN
    RAISE EXCEPTION 'Field koreksi tidak diizinkan: %', v_unknown_key USING ERRCODE = '22023';
  END IF;

  v_candidate := jsonb_populate_record(v_before, COALESCE(p_changes, '{}'::jsonb));

  UPDATE public.transaksi_mitra
  SET tanggal = v_candidate.tanggal,
      sopir_id = v_candidate.sopir_id,
      sopir_default_id = v_candidate.sopir_default_id,
      sopir_default_nama = v_candidate.sopir_default_nama,
      mitra_id = v_candidate.mitra_id,
      plat_nomor = v_candidate.plat_nomor,
      sopir_aktual_id = v_candidate.sopir_aktual_id,
      sopir_aktual_nama = v_candidate.sopir_aktual_nama,
      sopir_aktual_no_hp = v_candidate.sopir_aktual_no_hp,
      sopir_aktual_source = v_candidate.sopir_aktual_source,
      sopir_diganti_dari_default = v_candidate.sopir_diganti_dari_default,
      catatan_sopir = v_candidate.catatan_sopir,
      tonase = v_candidate.tonase,
      berat_netto_pabrik_kg = v_candidate.berat_netto_pabrik_kg,
      potongan_pabrik_kg = v_candidate.potongan_pabrik_kg,
      berat_dibayar_kg = v_candidate.berat_dibayar_kg,
      harga_harian = v_candidate.harga_harian,
      harga_pabrik_per_kg = v_candidate.harga_pabrik_per_kg,
      fee_owner_per_kg = v_candidate.fee_owner_per_kg,
      harga_bersih_per_kg = v_candidate.harga_bersih_per_kg,
      fee_owner_history_id = v_candidate.fee_owner_history_id,
      total_kotor = v_candidate.total_kotor,
      total_fee_owner = v_candidate.total_fee_owner,
      total_nilai_bersih = v_candidate.total_nilai_bersih,
      pakai_sewa_armada_bl = v_candidate.pakai_sewa_armada_bl,
      biaya_sewa_armada_per_kg = v_candidate.biaya_sewa_armada_per_kg,
      tarif_sewa_angkut_per_kg_snapshot = v_candidate.tarif_sewa_angkut_per_kg_snapshot,
      biaya_sewa_armada_kotor = v_candidate.biaya_sewa_armada_kotor,
      biaya_sewa_armada_total = v_candidate.biaya_sewa_armada_total,
      updated_by = v_actor,
      alasan_edit = btrim(p_alasan)
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  PERFORM public.write_audit_log('transaksi_mitra', v_before.id, 'update', to_jsonb(v_before), to_jsonb(v_after), p_alasan, v_actor);
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_transaksi_mitra_controlled(
  p_transaksi_id uuid,
  p_alasan text
)
RETURNS public.transaksi_mitra
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.transaksi_mitra%ROWTYPE;
  v_after public.transaksi_mitra%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang membatalkan pengiriman.' USING ERRCODE = '42501';
  END IF;
  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before
  FROM public.transaksi_mitra
  WHERE id = p_transaksi_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Pengiriman tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF v_before.status = 'dibatalkan' THEN
    RAISE EXCEPTION 'Pengiriman sudah dibatalkan.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.transaksi_mitra
  SET status = 'dibatalkan',
      dibatalkan_at = now(),
      dibatalkan_by = v_actor,
      alasan_batal = btrim(p_alasan),
      updated_by = v_actor,
      alasan_edit = 'Dibatalkan: ' || btrim(p_alasan)
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  PERFORM public.write_audit_log('transaksi_mitra', v_before.id, 'cancel', to_jsonb(v_before), to_jsonb(v_after), p_alasan, v_actor);
  RETURN v_after;
END;
$$;

REVOKE ALL ON FUNCTION public.update_transaksi_mitra_controlled(uuid, jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_transaksi_mitra_controlled(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_transaksi_mitra_controlled(uuid, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_transaksi_mitra_controlled(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.write_audit_log(text, uuid, text, jsonb, jsonb, text, uuid) FROM authenticated;

-- Direct writes to ledgers and payment headers are not application workflows.
-- Their SECURITY DEFINER RPCs perform role checks, locks, audit, and reversal.
DROP POLICY IF EXISTS insert_finance ON public.kas_ledger;
DROP POLICY IF EXISTS update_finance ON public.kas_ledger;
DROP POLICY IF EXISTS insert_finance ON public.hutang_ledger;
DROP POLICY IF EXISTS update_finance ON public.hutang_ledger;
DROP POLICY IF EXISTS insert_finance ON public.biaya_operasional;
DROP POLICY IF EXISTS update_finance ON public.biaya_operasional;
DROP POLICY IF EXISTS insert_finance ON public.pembayaran_mitra_kwitansi;
DROP POLICY IF EXISTS update_finance ON public.pembayaran_mitra_kwitansi;
DROP POLICY IF EXISTS insert_finance ON public.pembayaran_pabrik_batch;
DROP POLICY IF EXISTS update_finance ON public.pembayaran_pabrik_batch;

DROP POLICY IF EXISTS update_operations ON public.transaksi_mitra;

DROP POLICY IF EXISTS write_operations ON public.harga_tbs;
CREATE POLICY insert_business_settings ON public.harga_tbs FOR INSERT TO authenticated
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin']));
CREATE POLICY update_business_settings ON public.harga_tbs FOR UPDATE TO authenticated
  USING (public.has_app_role(ARRAY['owner', 'super_admin']))
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin']));

DROP POLICY IF EXISTS "Authenticated full access" ON public.kendaraan;
CREATE POLICY read_authenticated ON public.kendaraan FOR SELECT TO authenticated USING (true);
CREATE POLICY insert_operations ON public.kendaraan FOR INSERT TO authenticated
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']));
CREATE POLICY update_operations ON public.kendaraan FOR UPDATE TO authenticated
  USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']))
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']));

-- A paid Dana Trip must be corrected through one cash and ledger reversal.
CREATE OR REPLACE FUNCTION public.cancel_pembayaran_dana_trip(
  p_transaksi_id uuid,
  p_alasan text
)
RETURNS public.transaksi_mitra
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_transaksi public.transaksi_mitra%ROWTYPE;
  v_biaya public.biaya_operasional%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
  v_pelunasan public.hutang_ledger%ROWTYPE;
  v_kas_reversal_id uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat membatalkan Dana Trip.' USING ERRCODE = '42501';
  END IF;
  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_transaksi
  FROM public.transaksi_mitra
  WHERE id = p_transaksi_id
  FOR UPDATE;

  IF v_transaksi.id IS NULL THEN
    RAISE EXCEPTION 'Pengiriman tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF v_transaksi.biaya_sopir_dibayar_at IS NULL
     OR v_transaksi.biaya_sopir_operasional_id IS NULL
     OR v_transaksi.tagihan_sopir_bayar_ledger_id IS NULL THEN
    RAISE EXCEPTION 'Dana Trip belum dibayar atau referensinya tidak lengkap.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_biaya
  FROM public.biaya_operasional
  WHERE id = v_transaksi.biaya_sopir_operasional_id
  FOR UPDATE;

  SELECT * INTO v_pelunasan
  FROM public.hutang_ledger
  WHERE id = v_transaksi.tagihan_sopir_bayar_ledger_id
  FOR UPDATE;

  SELECT * INTO v_kas
  FROM public.kas_ledger
  WHERE id = COALESCE(v_biaya.kas_ledger_id, v_pelunasan.kas_ledger_id)
  FOR UPDATE;

  IF v_kas.id IS NULL THEN
    RAISE EXCEPTION 'Kas keluar Dana Trip tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM public.kas_ledger WHERE reversal_of_id = v_kas.id AND status <> 'dibatalkan') THEN
    RAISE EXCEPTION 'Dana Trip ini sudah memiliki transaksi balik.' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.kas_ledger (
    rekening_kas_id, tanggal, tipe, sumber, jumlah,
    biaya_operasional_id, hutang_ledger_id, source_table, source_id,
    reversal_of_id, idempotency_key, keterangan, created_by
  ) VALUES (
    v_kas.rekening_kas_id, (now() AT TIME ZONE 'Asia/Jakarta')::date,
    'masuk', 'reversal', v_kas.jumlah,
    v_biaya.id, v_pelunasan.id, 'transaksi_mitra', v_transaksi.id,
    v_kas.id, 'dana_trip:' || v_transaksi.id::text || ':reversal',
    'Pembalikan Dana Trip: ' || btrim(p_alasan), v_actor
  ) RETURNING id INTO v_kas_reversal_id;

  INSERT INTO public.hutang_ledger (
    pihak_type, petani_id, mitra_id, master_mitra_id, sopir_id,
    pihak_nama_manual, pihak_ref_id, tanggal, tipe, sumber, jumlah,
    transaksi_beli_id, settlement_id, keterangan, status,
    reversal_of_id, rekening_kas_id, kas_ledger_id, created_by
  ) VALUES (
    v_pelunasan.pihak_type, v_pelunasan.petani_id, v_pelunasan.mitra_id,
    v_pelunasan.master_mitra_id, v_pelunasan.sopir_id,
    v_pelunasan.pihak_nama_manual, v_pelunasan.pihak_ref_id,
    (now() AT TIME ZONE 'Asia/Jakarta')::date, 'debit', 'reversal',
    v_pelunasan.jumlah, v_pelunasan.transaksi_beli_id,
    v_pelunasan.settlement_id, 'Pembalikan Dana Trip: ' || btrim(p_alasan),
    'reversal', v_pelunasan.id, v_kas.rekening_kas_id,
    v_kas_reversal_id, v_actor
  );

  UPDATE public.kas_ledger
  SET reversed_at = now(), reversed_by = v_actor, reversal_reason = btrim(p_alasan)
  WHERE id = v_kas.id;

  UPDATE public.biaya_operasional
  SET status = 'dibatalkan', alasan_batal = btrim(p_alasan),
      dibatalkan_at = now(), dibatalkan_by = v_actor
  WHERE id = v_biaya.id;

  UPDATE public.transaksi_mitra
  SET tagihan_sopir_bayar_ledger_id = NULL,
      biaya_sopir_operasional_id = NULL,
      biaya_sopir_dibayar_at = NULL,
      updated_by = v_actor,
      alasan_edit = 'Pembayaran Dana Trip dibatalkan: ' || btrim(p_alasan)
  WHERE id = v_transaksi.id
  RETURNING * INTO v_transaksi;

  PERFORM public.write_audit_log('transaksi_mitra', v_transaksi.id, 'reverse_dana_trip', NULL, to_jsonb(v_transaksi), p_alasan, v_actor);
  RETURN v_transaksi;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_pembayaran_dana_trip(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_pembayaran_dana_trip(uuid, text) TO authenticated;

-- Legacy master rows remain usable, but ambiguous unit/driver data is placed
-- in the Owner verification queue instead of being deleted or guessed.
UPDATE public.sopir driver
SET status_verifikasi = 'perlu_verifikasi',
    catatan_verifikasi = CASE
      WHEN NULLIF(btrim(driver.plat_nomor), '') IS NULL THEN 'Plat nomor belum diisi pada data lama.'
      ELSE 'Plat yang sama dipakai lebih dari satu master. Owner perlu menentukan sopir tetap atau data pengganti.'
    END
WHERE driver.aktif = true
  AND (
    NULLIF(btrim(driver.plat_nomor), '') IS NULL
    OR public.normalize_plat_nomor(driver.plat_nomor) IN (
      SELECT public.normalize_plat_nomor(plat_nomor)
      FROM public.sopir
      WHERE aktif = true AND NULLIF(btrim(plat_nomor), '') IS NOT NULL
      GROUP BY public.normalize_plat_nomor(plat_nomor)
      HAVING count(*) > 1
    )
  );

CREATE OR REPLACE FUNCTION public.get_dashboard_pending_summary()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_unpaid_mitra bigint := 0;
  v_unpaid_weight numeric := 0;
  v_review bigint := 0;
  v_pending_mitra bigint := 0;
  v_pending_armada bigint := 0;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang melihat antrian dashboard.' USING ERRCODE = '42501';
  END IF;

  SELECT count(DISTINCT transaction.mitra_id),
         COALESCE(sum(COALESCE(transaction.berat_dibayar_kg, transaction.tonase)), 0)
  INTO v_unpaid_mitra, v_unpaid_weight
  FROM public.transaksi_mitra transaction
  WHERE transaction.status <> 'dibatalkan'
    AND NOT EXISTS (
      SELECT 1
      FROM public.pembayaran_mitra_kwitansi_item item
      JOIN public.pembayaran_mitra_kwitansi payment ON payment.id = item.pembayaran_id
      WHERE item.transaksi_mitra_id = transaction.id
        AND payment.status <> 'dibatalkan'
    );

  SELECT count(*) INTO v_review
  FROM public.pembayaran_mitra_kwitansi
  WHERE status = 'perlu_review';

  SELECT count(*) INTO v_pending_mitra FROM public.master_mitra WHERE status_verifikasi = 'perlu_verifikasi';
  SELECT count(*) INTO v_pending_armada FROM public.sopir WHERE aktif = true AND status_verifikasi = 'perlu_verifikasi';

  RETURN jsonb_build_object(
    'kwitansi_belum_dibayar', v_unpaid_mitra,
    'kwitansi_belum_dibayar_kg', v_unpaid_weight,
    'kwitansi_perlu_review', v_review,
    'mitra_perlu_verifikasi', v_pending_mitra,
    'armada_perlu_verifikasi', v_pending_armada
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_dashboard_pending_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_dashboard_pending_summary() TO authenticated;
