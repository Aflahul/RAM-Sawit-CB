-- Fail closed: when no threshold has been configured, every Admin request
-- requires an independent Owner/Super Admin review.
UPDATE public.pengaturan_bisnis
SET value_json = jsonb_set(
      COALESCE(value_json, '{}'::jsonb),
      '{pinjaman_panjar_threshold}',
      '0'::jsonb,
      true
    ),
    updated_at = now()
WHERE key = 'MAKER_CHECKER_CONFIG'
  AND scope = 'global'
  AND aktif = true
  AND (value_json->>'pinjaman_panjar_threshold') IS NULL;

INSERT INTO public.pengaturan_bisnis (key, scope, value_json, updated_by)
SELECT
  'MAKER_CHECKER_CONFIG',
  'global',
  '{"pinjaman_panjar_threshold": 0}'::jsonb,
  NULL
WHERE NOT EXISTS (
  SELECT 1
  FROM public.pengaturan_bisnis
  WHERE key = 'MAKER_CHECKER_CONFIG'
    AND scope = 'global'
    AND aktif = true
);

CREATE OR REPLACE FUNCTION public.enforce_piutang_checker_identity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $$
DECLARE
  v_maker_role text;
BEGIN
  IF NEW.disetujui_oleh IS NULL OR NEW.disetujui_oleh <> NEW.diajukan_oleh THEN
    RETURN NEW;
  END IF;

  SELECT role
  INTO v_maker_role
  FROM public.users
  WHERE id = NEW.diajukan_oleh;

  IF v_maker_role NOT IN ('owner', 'super_admin') THEN
    RAISE EXCEPTION 'Pembuat pengajuan tidak boleh menyetujui pengajuannya sendiri.'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_piutang_checker_identity
ON public.piutang_dokumen;

CREATE TRIGGER enforce_piutang_checker_identity
BEFORE INSERT OR UPDATE OF diajukan_oleh, disetujui_oleh, status
ON public.piutang_dokumen
FOR EACH ROW
EXECUTE FUNCTION public.enforce_piutang_checker_identity();

CREATE OR REPLACE FUNCTION public.create_piutang_request(
  p_pihak_type text,
  p_jumlah numeric,
  p_tujuan text,
  p_metode_pelunasan text,
  p_tanggal date DEFAULT NULL,
  p_tanggal_jatuh_tempo date DEFAULT NULL,
  p_petani_id uuid DEFAULT NULL,
  p_master_mitra_id uuid DEFAULT NULL,
  p_sopir_id uuid DEFAULT NULL,
  p_pihak_nama_manual text DEFAULT NULL,
  p_catatan text DEFAULT NULL
)
RETURNS public.piutang_dokumen
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
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
  v_threshold numeric := 0;
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
      INTO v_name, v_code, v_contact
      FROM public.master_mitra
      WHERE id = p_master_mitra_id AND aktif = true;
      v_kind := 'panjar_mitra';
      v_expected_method := 'potong_kwitansi_tbs';
      v_prefix := 'BPM';
    WHEN 'petani' THEN
      SELECT nama, NULL, no_hp
      INTO v_name, v_code, v_contact
      FROM public.petani
      WHERE id = p_petani_id AND aktif = true;
      v_kind := 'panjar_petani';
      v_expected_method := p_metode_pelunasan;
      v_prefix := 'BPP';
    WHEN 'sopir' THEN
      SELECT NULLIF(btrim(concat_ws(' - ', nama, plat_nomor)), ''), plat_nomor, no_hp
      INTO v_name, v_code, v_contact
      FROM public.sopir
      WHERE id = p_sopir_id AND aktif = true;
      v_kind := 'kasbon_sopir';
      v_expected_method := p_metode_pelunasan;
      v_prefix := 'BKS';
    WHEN 'karyawan' THEN
      v_name := NULLIF(btrim(COALESCE(p_pihak_nama_manual, '')), '');
      v_kind := 'kasbon_karyawan';
      v_expected_method := p_metode_pelunasan;
      v_prefix := 'BKK';
    WHEN 'lainnya' THEN
      v_name := NULLIF(btrim(COALESCE(p_pihak_nama_manual, '')), '');
      v_kind := 'piutang_lainnya';
      v_expected_method := 'tunai_transfer';
      v_prefix := 'BPL';
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

  SELECT COALESCE((value_json->>'pinjaman_panjar_threshold')::numeric, 0)
  INTO v_threshold
  FROM public.pengaturan_bisnis
  WHERE key = 'MAKER_CHECKER_CONFIG'
    AND scope = 'global'
    AND aktif = true
  ORDER BY berlaku_mulai DESC NULLS LAST, created_at DESC
  LIMIT 1;

  v_threshold := COALESCE(v_threshold, 0);
  v_needs_approval := v_role NOT IN ('owner', 'super_admin')
    AND p_jumlah >= v_threshold;

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
    COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    p_tanggal_jatuh_tempo,
    round(p_jumlah, 2),
    btrim(p_tujuan),
    v_expected_method,
    CASE WHEN v_needs_approval THEN 'menunggu_persetujuan' ELSE 'disetujui' END,
    v_actor,
    CASE WHEN v_needs_approval THEN NULL ELSE v_actor END,
    CASE WHEN v_needs_approval THEN NULL ELSE now() END,
    NULLIF(btrim(COALESCE(p_catatan, '')), '')
  )
  RETURNING * INTO v_row;

  PERFORM public.write_audit_log(
    'piutang_dokumen', v_row.id, 'create_request', NULL, to_jsonb(v_row), NULL, NULL
  );

  RETURN v_row;
END;
$$;

ALTER FUNCTION public.create_piutang_request(
  text, numeric, text, text, date, date, uuid, uuid, uuid, text, text
) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.enforce_piutang_checker_identity()
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.create_piutang_request(
  text, numeric, text, text, date, date, uuid, uuid, uuid, text, text
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_piutang_request(
  text, numeric, text, text, date, date, uuid, uuid, uuid, text, text
) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.review_piutang_request(uuid, text, text, text)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.review_piutang_request(uuid, text, text, text)
TO authenticated, service_role;
