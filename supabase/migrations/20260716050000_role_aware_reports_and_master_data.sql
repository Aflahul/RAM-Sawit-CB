-- Role-aware operational reports and controlled master-data maintenance.

BEGIN;

ALTER TABLE public.pabrik
  ADD COLUMN IF NOT EXISTS dibuat_oleh uuid REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS status_verifikasi text NOT NULL DEFAULT 'terverifikasi',
  ADD COLUMN IF NOT EXISTS diverifikasi_oleh uuid REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS diverifikasi_at timestamptz,
  ADD COLUMN IF NOT EXISTS catatan_verifikasi text;

UPDATE public.pabrik
SET status_verifikasi = 'terverifikasi',
    diverifikasi_at = COALESCE(diverifikasi_at, created_at)
WHERE status_verifikasi IS NULL
   OR status_verifikasi NOT IN ('perlu_verifikasi', 'terverifikasi');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'pabrik_status_verifikasi_check'
      AND conrelid = 'public.pabrik'::regclass
  ) THEN
    ALTER TABLE public.pabrik
      ADD CONSTRAINT pabrik_status_verifikasi_check
      CHECK (status_verifikasi IN ('perlu_verifikasi', 'terverifikasi'));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.save_pabrik_master(
  p_id uuid DEFAULT NULL,
  p_nama text DEFAULT NULL,
  p_alamat text DEFAULT NULL,
  p_no_hp text DEFAULT NULL
)
RETURNS public.pabrik
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_role text := public.current_app_role();
  v_before public.pabrik%ROWTYPE;
  v_after public.pabrik%ROWTYPE;
  v_is_approver boolean := v_role IN ('owner', 'super_admin');
BEGIN
  IF v_actor IS NULL OR v_role NOT IN ('owner', 'super_admin', 'admin_operasional') THEN
    RAISE EXCEPTION 'Tidak berwenang menyimpan Pabrik.' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_nama, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Nama Pabrik wajib diisi.' USING ERRCODE = '22023';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.pabrik (
      nama, alamat, no_hp, aktif, dibuat_oleh,
      status_verifikasi, diverifikasi_oleh, diverifikasi_at
    ) VALUES (
      btrim(p_nama),
      NULLIF(btrim(COALESCE(p_alamat, '')), ''),
      NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
      true,
      v_actor,
      CASE WHEN v_is_approver THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
      CASE WHEN v_is_approver THEN v_actor ELSE NULL END,
      CASE WHEN v_is_approver THEN now() ELSE NULL END
    )
    RETURNING * INTO v_after;
  ELSE
    SELECT * INTO v_before FROM public.pabrik WHERE id = p_id FOR UPDATE;
    IF v_before.id IS NULL THEN
      RAISE EXCEPTION 'Pabrik tidak ditemukan.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.pabrik
    SET nama = btrim(p_nama),
        alamat = NULLIF(btrim(COALESCE(p_alamat, '')), ''),
        no_hp = NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
        status_verifikasi = CASE WHEN v_is_approver THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
        diverifikasi_oleh = CASE WHEN v_is_approver THEN v_actor ELSE NULL END,
        diverifikasi_at = CASE WHEN v_is_approver THEN now() ELSE NULL END,
        catatan_verifikasi = NULL
    WHERE id = p_id
    RETURNING * INTO v_after;
  END IF;

  PERFORM public.write_audit_log(
    'pabrik', v_after.id,
    CASE WHEN p_id IS NULL THEN 'create' ELSE 'update' END,
    CASE WHEN p_id IS NULL THEN NULL ELSE to_jsonb(v_before) END,
    to_jsonb(v_after),
    CASE WHEN v_is_approver THEN NULL ELSE 'Menunggu verifikasi Owner' END,
    CASE WHEN v_is_approver THEN v_actor ELSE NULL END
  );

  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_pabrik_master(
  p_id uuid,
  p_catatan text DEFAULT NULL
)
RETURNS public.pabrik
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.pabrik%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat memverifikasi Pabrik.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.pabrik
  SET status_verifikasi = 'terverifikasi',
      diverifikasi_oleh = v_actor,
      diverifikasi_at = now(),
      catatan_verifikasi = NULLIF(btrim(COALESCE(p_catatan, '')), '')
  WHERE id = p_id AND aktif = true
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Pabrik aktif tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  PERFORM public.write_audit_log('pabrik', v_row.id, 'verify', NULL, to_jsonb(v_row), p_catatan, v_actor);
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_pabrik_master_active(p_id uuid, p_active boolean)
RETURNS public.pabrik
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.pabrik%ROWTYPE;
  v_after public.pabrik%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat mengubah status Pabrik.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_before FROM public.pabrik WHERE id = p_id FOR UPDATE;
  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Pabrik tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.pabrik SET aktif = COALESCE(p_active, false)
  WHERE id = p_id RETURNING * INTO v_after;

  PERFORM public.write_audit_log(
    'pabrik', v_after.id,
    CASE WHEN v_after.aktif THEN 'activate' ELSE 'deactivate' END,
    to_jsonb(v_before), to_jsonb(v_after), NULL, v_actor
  );
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_master_mitra_active(p_id uuid, p_active boolean)
RETURNS public.master_mitra
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.master_mitra%ROWTYPE;
  v_after public.master_mitra%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat mengubah status Mitra.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_before FROM public.master_mitra WHERE id = p_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'Mitra tidak ditemukan.' USING ERRCODE = 'P0002'; END IF;
  UPDATE public.master_mitra SET aktif = COALESCE(p_active, false)
  WHERE id = p_id RETURNING * INTO v_after;
  PERFORM public.write_audit_log('master_mitra', v_after.id,
    CASE WHEN v_after.aktif THEN 'activate' ELSE 'deactivate' END,
    to_jsonb(v_before), to_jsonb(v_after), NULL, v_actor);
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_sopir_armada_active(p_id uuid, p_active boolean)
RETURNS public.sopir
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.sopir%ROWTYPE;
  v_after public.sopir%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat mengubah status Sopir/Armada.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_before FROM public.sopir WHERE id = p_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'Sopir/Armada tidak ditemukan.' USING ERRCODE = 'P0002'; END IF;
  UPDATE public.sopir SET aktif = COALESCE(p_active, false), updated_at = now()
  WHERE id = p_id RETURNING * INTO v_after;
  PERFORM public.write_audit_log('sopir_armada', v_after.id,
    CASE WHEN v_after.aktif THEN 'activate' ELSE 'deactivate' END,
    to_jsonb(v_before), to_jsonb(v_after), NULL, v_actor);
  RETURN v_after;
END;
$$;

DROP POLICY IF EXISTS write_operations ON public.pabrik;
REVOKE INSERT, UPDATE ON public.pabrik FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.save_pabrik_master(uuid, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.verify_pabrik_master(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_pabrik_master_active(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_master_mitra_active(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_sopir_armada_active(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_pabrik_master(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_pabrik_master(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_pabrik_master_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_master_mitra_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_sopir_armada_active(uuid, boolean) TO authenticated;

-- Local TBS pricing is a business decision, not routine Admin input.
CREATE OR REPLACE FUNCTION public.set_harga_tbs_lokal(
  p_harga_per_kg numeric,
  p_alasan_override text DEFAULT NULL
)
RETURNS public.harga_tbs_lokal
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_now timestamptz := now();
  v_harga public.harga_tbs_lokal%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat mengatur harga TBS lokal.' USING ERRCODE = '42501';
  END IF;
  IF p_harga_per_kg IS NULL OR p_harga_per_kg <= 0 THEN
    RAISE EXCEPTION 'Harga TBS lokal harus lebih dari 0.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.harga_tbs_lokal
  SET aktif = false,
      berlaku_sampai = COALESCE(berlaku_sampai, v_now),
      updated_at = v_now,
      updated_by = v_actor
  WHERE aktif = true AND (berlaku_sampai IS NULL OR berlaku_sampai > v_now);

  INSERT INTO public.harga_tbs_lokal (
    harga_per_kg, berlaku_mulai, aktif, set_oleh, alasan_override
  ) VALUES (
    round(p_harga_per_kg, 2), v_now, true, v_actor,
    NULLIF(btrim(COALESCE(p_alasan_override, '')), '')
  ) RETURNING * INTO v_harga;

  PERFORM public.write_audit_log(
    'harga_tbs_lokal', v_harga.id, 'create', NULL,
    to_jsonb(v_harga), p_alasan_override, v_actor
  );
  RETURN v_harga;
END;
$$;

REVOKE ALL ON FUNCTION public.set_harga_tbs_lokal(numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_harga_tbs_lokal(numeric, text) TO authenticated;

DROP POLICY IF EXISTS write_operations ON public.harga_tbs_lokal;
REVOKE INSERT, UPDATE ON public.harga_tbs_lokal FROM anon, authenticated;

COMMIT;
