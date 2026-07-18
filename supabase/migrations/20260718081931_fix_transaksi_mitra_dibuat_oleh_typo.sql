CREATE OR REPLACE FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") RETURNS "public"."transaksi_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_tanggal date;
  v_sopir_id uuid;
  v_mitra_id uuid;
  v_plat_nomor text;
  v_sopir_default_id uuid;
  v_sopir_default_nama text;
  v_sopir_aktual_id uuid;
  v_sopir_aktual_nama text;
  v_sopir_aktual_no_hp text;
  v_sopir_aktual_source text;
  v_sopir_diganti boolean;
  v_catatan_sopir text;

  v_berat_netto numeric;
  v_potongan numeric;
  v_berat_dibayar numeric;

  v_is_armada_cb boolean;
  v_kenakan_sewa boolean;
  v_catat_dana boolean;
  v_alasan_tanpa_sewa text;
  v_alasan_tanpa_dana text;

  v_harga_pabrik numeric;
  
  v_master_fee numeric;
  v_master_tarif_sewa numeric;
  v_master_dana_trip numeric;
  
  v_hist_id uuid;
  v_hist_fee numeric;
  v_hist_tarif_sewa numeric;
  v_hist_dana_trip numeric;
  v_hist_alasan text;
  
  v_is_initial boolean;
  v_has_stale_history_fee boolean;
  v_should_prefer_master boolean;
  
  v_final_fee numeric;
  v_final_tarif_sewa numeric;
  v_final_dana_trip numeric;
  v_final_history_id uuid;
  
  v_harga_bersih numeric;
  v_total_kotor numeric;
  v_total_fee_owner numeric;
  v_total_nilai_bersih numeric;
  
  v_pakai_sewa_armada boolean;
  v_biaya_sewa_kotor numeric;
  v_tarif_sewa_snapshot numeric;
  v_dana_trip_snapshot numeric;

  v_inserted_row public.transaksi_mitra;
BEGIN
  -- 1. Check Permissions
  IF NOT (SELECT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional', 'admin_keuangan'])) THEN
    RAISE EXCEPTION 'insufficient_privilege: Not authorized to save transaksi_mitra';
  END IF;

  -- 2. Extract operational payload
  v_tanggal := (payload->>'tanggal')::date;
  v_sopir_id := (payload->>'sopir_id')::uuid;
  v_mitra_id := (payload->>'mitra_id')::uuid;
  v_plat_nomor := payload->>'plat_nomor';
  v_sopir_default_id := (payload->>'sopir_default_id')::uuid;
  v_sopir_default_nama := payload->>'sopir_default_nama';
  v_sopir_aktual_id := (payload->>'sopir_aktual_id')::uuid;
  v_sopir_aktual_nama := payload->>'sopir_aktual_nama';
  v_sopir_aktual_no_hp := payload->>'sopir_aktual_no_hp';
  v_sopir_aktual_source := payload->>'sopir_aktual_source';
  v_sopir_diganti := COALESCE((payload->>'sopir_diganti_dari_default')::boolean, false);
  v_catatan_sopir := payload->>'catatan_sopir';

  v_berat_netto := COALESCE((payload->>'berat_netto_pabrik_kg')::numeric, 0);
  v_potongan := COALESCE((payload->>'potongan_pabrik_kg')::numeric, 0);
  
  v_is_armada_cb := COALESCE((payload->>'menggunakan_armada_cb_snapshot')::boolean, false);
  v_kenakan_sewa := COALESCE((payload->>'kenakan_sewa_armada_cb')::boolean, false);
  v_catat_dana := COALESCE((payload->>'catat_dana_operasional_trip')::boolean, false);
  v_alasan_tanpa_sewa := payload->>'alasan_tanpa_sewa_armada_cb';
  v_alasan_tanpa_dana := payload->>'alasan_tanpa_dana_operasional_trip';

  -- Validation
  IF v_berat_netto <= 0 THEN
    RAISE EXCEPTION 'Berat Netto harus lebih dari 0.';
  END IF;
  IF v_potongan < 0 THEN
    RAISE EXCEPTION 'Potongan tidak boleh negatif.';
  END IF;
  IF v_potongan > v_berat_netto THEN
    RAISE EXCEPTION 'Potongan tidak boleh lebih besar dari Berat Netto.';
  END IF;
  
  v_berat_dibayar := GREATEST(0, v_berat_netto - v_potongan);

  -- 3. Resolve Harga Pabrik
  SELECT harga_per_kg INTO v_harga_pabrik
  FROM public.harga_tbs
  WHERE tanggal <= v_tanggal
  ORDER BY tanggal DESC
  LIMIT 1;

  v_harga_pabrik := COALESCE(v_harga_pabrik, 0);

  -- 4. Resolve Fee & Tarif Mitra
  SELECT fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip
  INTO v_master_fee, v_master_tarif_sewa, v_master_dana_trip
  FROM public.master_mitra
  WHERE id = v_mitra_id;

  SELECT id, fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip, alasan_perubahan
  INTO v_hist_id, v_hist_fee, v_hist_tarif_sewa, v_hist_dana_trip, v_hist_alasan
  FROM public.fee_owner_mitra_history
  WHERE master_mitra_id = v_mitra_id
    AND aktif = true
    AND (berlaku_mulai IS NULL OR berlaku_mulai <= v_tanggal)
    AND (berlaku_sampai IS NULL OR berlaku_sampai >= v_tanggal)
  ORDER BY berlaku_mulai DESC NULLS LAST
  LIMIT 1;

  v_is_initial := v_hist_alasan LIKE 'Snapshot awal Fee Owner%';
  v_has_stale_history_fee := (v_hist_id IS NOT NULL AND v_master_fee > 0 AND v_hist_fee = 0);
  v_should_prefer_master := v_master_fee > 0 AND (v_hist_id IS NULL OR v_has_stale_history_fee OR (v_is_initial AND v_hist_fee <> v_master_fee));

  IF v_should_prefer_master THEN
    v_final_fee := v_master_fee;
    v_final_tarif_sewa := COALESCE(v_master_tarif_sewa, 0);
    v_final_dana_trip := COALESCE(v_master_dana_trip, 0);
    IF v_hist_fee = v_master_fee THEN
      v_final_history_id := v_hist_id;
    ELSE
      v_final_history_id := NULL;
    END IF;
  ELSE
    v_final_fee := COALESCE(v_hist_fee, v_master_fee, 0);
    v_final_tarif_sewa := COALESCE(v_hist_tarif_sewa, v_master_tarif_sewa, 0);
    v_final_dana_trip := COALESCE(v_hist_dana_trip, v_master_dana_trip, 0);
    v_final_history_id := v_hist_id;
  END IF;

  -- 5. Calculate Values
  v_harga_bersih := GREATEST(0, v_harga_pabrik - v_final_fee);
  v_total_kotor := ROUND(v_berat_dibayar * v_harga_pabrik);
  v_total_fee_owner := ROUND(v_berat_dibayar * v_final_fee);
  v_total_nilai_bersih := ROUND(v_berat_dibayar * v_harga_bersih);

  v_pakai_sewa_armada := v_is_armada_cb AND v_kenakan_sewa;
  IF v_pakai_sewa_armada THEN
    v_biaya_sewa_kotor := ROUND(v_berat_netto * v_final_tarif_sewa);
    v_tarif_sewa_snapshot := v_final_tarif_sewa;
  ELSE
    v_biaya_sewa_kotor := 0;
    v_tarif_sewa_snapshot := 0;
  END IF;

  IF v_is_armada_cb AND v_catat_dana THEN
    v_dana_trip_snapshot := v_final_dana_trip;
  ELSE
    v_dana_trip_snapshot := 0;
  END IF;

  -- Validation Sewa Armada CB
  IF v_is_armada_cb AND v_kenakan_sewa AND v_final_tarif_sewa <= 0 THEN
    RAISE EXCEPTION 'Tarif sewa Armada CB untuk mitra ini belum diatur.';
  END IF;
  IF v_is_armada_cb AND v_catat_dana AND v_final_dana_trip <= 0 THEN
    RAISE EXCEPTION 'Dana Operasional Trip untuk mitra ini belum diatur.';
  END IF;

  -- 6. Insert Transaksi
  INSERT INTO public.transaksi_mitra (
    tanggal, sopir_id, mitra_id, plat_nomor,
    sopir_default_id, sopir_default_nama,
    sopir_aktual_id, sopir_aktual_nama, sopir_aktual_no_hp,
    sopir_aktual_source, sopir_diganti_dari_default, catatan_sopir,
    
    tonase, berat_netto_pabrik_kg, potongan_pabrik_kg, berat_dibayar_kg,
    harga_harian, harga_pabrik_per_kg, fee_owner_per_kg, harga_bersih_per_kg, fee_owner_history_id,
    total_kotor, total_fee_owner, total_nilai_bersih,
    
    menggunakan_armada_cb_snapshot, kenakan_sewa_armada_cb, catat_dana_operasional_trip,
    alasan_tanpa_sewa_armada_cb, alasan_tanpa_dana_operasional_trip,
    pakai_sewa_armada_bl, tarif_sewa_angkut_per_kg_snapshot, nominal_perongkosan_snapshot,
    biaya_sewa_armada_kotor, biaya_sewa_armada_total,
    dana_operasional_trip_snapshot, upah_sopir_cb_snapshot, uang_jalan_sopir_cb_snapshot, total_biaya_sopir_cb_snapshot,
    created_by
  ) VALUES (
    v_tanggal, v_sopir_id, v_mitra_id, v_plat_nomor,
    v_sopir_default_id, v_sopir_default_nama,
    v_sopir_aktual_id, v_sopir_aktual_nama, v_sopir_aktual_no_hp,
    v_sopir_aktual_source, v_sopir_diganti, v_catatan_sopir,
    
    v_berat_netto, v_berat_netto, v_potongan, v_berat_dibayar,
    v_harga_pabrik, v_harga_pabrik, v_final_fee, v_harga_bersih, v_final_history_id,
    v_total_kotor, v_total_fee_owner, v_total_nilai_bersih,
    
    v_is_armada_cb, v_kenakan_sewa, v_catat_dana,
    CASE WHEN v_kenakan_sewa THEN NULL ELSE v_alasan_tanpa_sewa END, 
    CASE WHEN v_catat_dana THEN NULL ELSE v_alasan_tanpa_dana END,
    v_pakai_sewa_armada, v_tarif_sewa_snapshot, 0,
    v_biaya_sewa_kotor, v_biaya_sewa_kotor,
    v_dana_trip_snapshot, 0, 0, v_dana_trip_snapshot,
    auth.uid()
  ) RETURNING * INTO v_inserted_row;

  RETURN v_inserted_row;
END;
$$;

ALTER FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") TO "authenticated";
