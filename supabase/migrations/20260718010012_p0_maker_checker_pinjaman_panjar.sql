-- 20260718010012_p0_maker_checker_pinjaman_panjar.sql

-- 1. Insert Konfigurasi Maker-Checker
INSERT INTO public.pengaturan_bisnis (key, scope, value_json, updated_by)
SELECT
  'MAKER_CHECKER_CONFIG',
  'global',
  '{"pinjaman_panjar_threshold": null}'::jsonb,
  NULL
WHERE NOT EXISTS (
  SELECT 1
  FROM public.pengaturan_bisnis
  WHERE key = 'MAKER_CHECKER_CONFIG'
    AND scope = 'global'
    AND aktif = true
);

-- 2. Tambah kolom alasan_darurat di piutang_dokumen
ALTER TABLE public.piutang_dokumen ADD COLUMN IF NOT EXISTS alasan_darurat text;

-- 3. Replace create_piutang_request
CREATE OR REPLACE FUNCTION "public"."create_piutang_request"("p_pihak_type" "text", "p_jumlah" numeric, "p_tujuan" "text", "p_metode_pelunasan" "text", "p_tanggal" "date" DEFAULT NULL::"date", "p_tanggal_jatuh_tempo" "date" DEFAULT NULL::"date", "p_petani_id" "uuid" DEFAULT NULL::"uuid", "p_master_mitra_id" "uuid" DEFAULT NULL::"uuid", "p_sopir_id" "uuid" DEFAULT NULL::"uuid", "p_pihak_nama_manual" "text" DEFAULT NULL::"text", "p_catatan" "text" DEFAULT NULL::"text") RETURNS "public"."piutang_dokumen"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_role text := public.current_app_role();
  v_row public.piutang_dokumen%ROWTYPE;
  v_name text;
  v_code text;
  v_contact text;
  v_kind text;
  v_expected_method text;
  v_prefix text;
  v_threshold numeric;
  v_needs_approval boolean := true;
BEGIN
  IF v_actor IS NULL OR v_role NOT IN ('owner', 'super_admin', 'admin_keuangan', 'admin_operasional') THEN
    RAISE EXCEPTION 'Tidak berwenang mengajukan panjar atau kasbon.' USING ERRCODE = '42501';
  END IF;
  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
    RAISE EXCEPTION 'Jumlah harus lebih dari 0.' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(btrim(COALESCE(p_tujuan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Keperluan pemberian uang wajib diisi.' USING ERRCODE = '22023';
  END IF;

  CASE p_pihak_type
    WHEN 'mitra' THEN
      SELECT NULLIF(btrim(concat_ws(' - ', kode, nama)), ''), kode, no_hp
      INTO v_name, v_code, v_contact FROM public.master_mitra WHERE id = p_master_mitra_id AND aktif = true;
      v_kind := 'panjar_mitra'; v_expected_method := 'potong_kwitansi_tbs'; v_prefix := 'BPM';
    WHEN 'petani' THEN
      SELECT nama, NULL, no_hp INTO v_name, v_code, v_contact FROM public.petani WHERE id = p_petani_id AND aktif = true;
      v_kind := 'panjar_petani'; v_expected_method := p_metode_pelunasan; v_prefix := 'BPP';
    WHEN 'sopir' THEN
      SELECT NULLIF(btrim(concat_ws(' - ', nama, plat_nomor)), ''), plat_nomor, no_hp
      INTO v_name, v_code, v_contact FROM public.sopir WHERE id = p_sopir_id AND aktif = true;
      v_kind := 'kasbon_sopir'; v_expected_method := p_metode_pelunasan; v_prefix := 'BKS';
    WHEN 'karyawan' THEN
      v_name := NULLIF(btrim(COALESCE(p_pihak_nama_manual, '')), '');
      v_kind := 'kasbon_karyawan'; v_expected_method := p_metode_pelunasan; v_prefix := 'BKK';
    WHEN 'lainnya' THEN
      v_name := NULLIF(btrim(COALESCE(p_pihak_nama_manual, '')), '');
      v_kind := 'piutang_lainnya'; v_expected_method := 'tunai_transfer'; v_prefix := 'BPL';
    ELSE
      RAISE EXCEPTION 'Jenis penerima tidak valid.' USING ERRCODE = '22023';
  END CASE;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Penerima tidak ditemukan atau belum aktif.' USING ERRCODE = '22023';
  END IF;
  IF v_expected_method NOT IN ('potong_kwitansi_tbs', 'potong_gaji', 'potong_upah', 'tunai_transfer') THEN
    RAISE EXCEPTION 'Cara pengembalian tidak sesuai dengan jenis penerima.' USING ERRCODE = '22023';
  END IF;
  IF p_pihak_type = 'sopir' AND v_expected_method NOT IN ('potong_upah', 'tunai_transfer') THEN
    RAISE EXCEPTION 'Kasbon sopir hanya dapat dipotong dari upah atau dikembalikan tunai/transfer.' USING ERRCODE = '22023';
  END IF;
  IF p_pihak_type = 'karyawan' AND v_expected_method NOT IN ('potong_gaji', 'tunai_transfer') THEN
    RAISE EXCEPTION 'Kasbon karyawan hanya dapat dipotong dari gaji atau dikembalikan tunai/transfer.' USING ERRCODE = '22023';
  END IF;
  IF p_tanggal_jatuh_tempo IS NOT NULL
     AND p_tanggal_jatuh_tempo < COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date) THEN
    RAISE EXCEPTION 'Tanggal target pengembalian tidak boleh sebelum tanggal pengajuan.' USING ERRCODE = '22023';
  END IF;

  -- Logic Maker-Checker Threshold & Auto-Approve
  SELECT (value_json->>'pinjaman_panjar_threshold')::numeric INTO v_threshold
  FROM public.pengaturan_bisnis
  WHERE key = 'MAKER_CHECKER_CONFIG' AND scope = 'global' AND aktif = true;

  IF v_role IN ('owner', 'super_admin') THEN
    v_needs_approval := false;
  ELSIF v_threshold IS NULL THEN
    v_needs_approval := false;
  ELSIF p_jumlah >= v_threshold THEN
    v_needs_approval := true;
  ELSE
    v_needs_approval := false;
  END IF;

  INSERT INTO public.piutang_dokumen (
    nomor_bukti, jenis_dokumen, pihak_type, petani_id, master_mitra_id, sopir_id,
    pihak_nama_manual, pihak_nama_snapshot, pihak_kode_snapshot, pihak_kontak_snapshot,
    tanggal_pengajuan, tanggal_jatuh_tempo, jumlah, tujuan, metode_pelunasan,
    status, diajukan_oleh, disetujui_oleh, disetujui_at, catatan
  ) VALUES (
    public.next_piutang_document_number(v_prefix), v_kind, p_pihak_type,
    CASE WHEN p_pihak_type = 'petani' THEN p_petani_id END,
    CASE WHEN p_pihak_type = 'mitra' THEN p_master_mitra_id END,
    CASE WHEN p_pihak_type = 'sopir' THEN p_sopir_id END,
    CASE WHEN p_pihak_type IN ('karyawan', 'lainnya') THEN v_name END,
    v_name, v_code, v_contact,
    COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date), p_tanggal_jatuh_tempo,
    round(p_jumlah, 2), btrim(p_tujuan), v_expected_method,
    CASE WHEN NOT v_needs_approval THEN 'disetujui' ELSE 'menunggu_persetujuan' END,
    v_actor,
    CASE WHEN NOT v_needs_approval THEN v_actor END,
    CASE WHEN NOT v_needs_approval THEN now() END,
    NULLIF(btrim(COALESCE(p_catatan, '')), '')
  ) RETURNING * INTO v_row;

  PERFORM public.write_audit_log(
    'piutang_dokumen', v_row.id, 'create_request', NULL, to_jsonb(v_row),
    NULL, NULL
  );
  
  RETURN v_row;
END;
$$;

-- 4. Replace review_piutang_request (Add alasan_darurat & Self-Approval Block)
DROP FUNCTION IF EXISTS "public"."review_piutang_request"("uuid", "text", "text");
CREATE OR REPLACE FUNCTION "public"."review_piutang_request"("p_document_id" "uuid", "p_action" "text", "p_catatan" "text" DEFAULT NULL::"text", "p_alasan_darurat" "text" DEFAULT NULL::"text") RETURNS "public"."piutang_dokumen"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_role text := public.current_app_role();
  v_before public.piutang_dokumen%ROWTYPE;
  v_after public.piutang_dokumen%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR v_role NOT IN ('owner', 'super_admin') THEN
    RAISE EXCEPTION 'Hanya Owner atau Super Admin yang dapat memberi persetujuan.' USING ERRCODE = '42501';
  END IF;
  IF p_action NOT IN ('setujui', 'tolak') THEN
    RAISE EXCEPTION 'Pilihan persetujuan tidak valid.' USING ERRCODE = '22023';
  END IF;
  IF p_action = 'tolak' AND NULLIF(btrim(COALESCE(p_catatan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan penolakan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before FROM public.piutang_dokumen WHERE id = p_document_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'Pengajuan tidak ditemukan.' USING ERRCODE = 'P0002'; END IF;
  IF v_before.status <> 'menunggu_persetujuan' THEN
    RAISE EXCEPTION 'Pengajuan ini sudah diproses.' USING ERRCODE = '22023';
  END IF;

  -- Maker-Checker Constraint (AC-BIZ-002): Maker != Checker
  IF v_actor = v_before.diajukan_oleh THEN
    RAISE EXCEPTION 'Anda tidak dapat menyetujui pengajuan Anda sendiri.' USING ERRCODE = '22023';
  END IF;

  -- Break-Glass untuk Super Admin
  IF p_action = 'setujui' AND v_role = 'super_admin' THEN
    IF NULLIF(btrim(COALESCE(p_alasan_darurat, '')), '') IS NULL THEN
      RAISE EXCEPTION 'Super Admin wajib menyertakan Alasan Darurat untuk menyetujui transaksi.' USING ERRCODE = '22023';
    END IF;
  END IF;
  -- Owner tidak boleh isi alasan_darurat
  IF v_role = 'owner' AND p_alasan_darurat IS NOT NULL THEN
    RAISE EXCEPTION 'Owner tidak perlu mengisi Alasan Darurat.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.piutang_dokumen
  SET status = CASE WHEN p_action = 'setujui' THEN 'disetujui' ELSE 'ditolak' END,
      disetujui_oleh = CASE WHEN p_action = 'setujui' THEN v_actor END,
      disetujui_at = CASE WHEN p_action = 'setujui' THEN now() END,
      alasan_penolakan = CASE WHEN p_action = 'tolak' THEN btrim(p_catatan) END,
      alasan_darurat = CASE WHEN p_action = 'setujui' AND v_role = 'super_admin' THEN btrim(p_alasan_darurat) END,
      updated_at = now()
  WHERE id = v_before.id RETURNING * INTO v_after;

  PERFORM public.write_audit_log(
    'piutang_dokumen', v_after.id, p_action, to_jsonb(v_before), to_jsonb(v_after),
    COALESCE(NULLIF(btrim(COALESCE(p_alasan_darurat, '')), ''), NULLIF(btrim(COALESCE(p_catatan, '')), '')), v_actor
  );
  RETURN v_after;
END;
$$;
