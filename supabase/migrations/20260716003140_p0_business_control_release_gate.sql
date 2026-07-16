-- P0 release gate: three active roles, controlled master-data writes, and
-- explicit audit/security rules. Existing records remain usable.

ALTER TABLE public.sopir
  ADD COLUMN IF NOT EXISTS status_verifikasi text NOT NULL DEFAULT 'terverifikasi',
  ADD COLUMN IF NOT EXISTS dibuat_oleh uuid REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS diverifikasi_oleh uuid REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS diverifikasi_at timestamptz,
  ADD COLUMN IF NOT EXISTS catatan_verifikasi text;

ALTER TABLE public.master_mitra
  ADD COLUMN IF NOT EXISTS status_verifikasi text NOT NULL DEFAULT 'terverifikasi',
  ADD COLUMN IF NOT EXISTS dibuat_oleh uuid REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS diverifikasi_oleh uuid REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS diverifikasi_at timestamptz,
  ADD COLUMN IF NOT EXISTS catatan_verifikasi text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sopir_status_verifikasi_check'
  ) THEN
    ALTER TABLE public.sopir
      ADD CONSTRAINT sopir_status_verifikasi_check
      CHECK (status_verifikasi IN ('perlu_verifikasi', 'terverifikasi'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'master_mitra_status_verifikasi_check'
  ) THEN
    ALTER TABLE public.master_mitra
      ADD CONSTRAINT master_mitra_status_verifikasi_check
      CHECK (status_verifikasi IN ('perlu_verifikasi', 'terverifikasi'));
  END IF;
END $$;

UPDATE public.sopir
SET status_verifikasi = 'terverifikasi',
    diverifikasi_at = COALESCE(diverifikasi_at, created_at, now())
WHERE status_verifikasi IS DISTINCT FROM 'terverifikasi'
   OR diverifikasi_at IS NULL;

UPDATE public.master_mitra
SET status_verifikasi = 'terverifikasi',
    diverifikasi_at = COALESCE(diverifikasi_at, created_at, now())
WHERE status_verifikasi IS DISTINCT FROM 'terverifikasi'
   OR diverifikasi_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_sopir_verifikasi
  ON public.sopir (status_verifikasi, aktif, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_master_mitra_verifikasi
  ON public.master_mitra (status_verifikasi, aktif, created_at DESC);

CREATE OR REPLACE FUNCTION public.normalize_plat_nomor(p_plat text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT upper(regexp_replace(COALESCE(p_plat, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

CREATE INDEX IF NOT EXISTS idx_sopir_plat_normalized
  ON public.sopir (public.normalize_plat_nomor(plat_nomor))
  WHERE COALESCE(aktif, true) = true AND NULLIF(btrim(COALESCE(plat_nomor, '')), '') IS NOT NULL;

-- Admin Operasional is the visible "Admin" role for the current three-user
-- deployment. Add it only to routine finance functions; cancellation and
-- reversal functions intentionally remain Owner/Super Admin only.
DO $$
DECLARE
  v_function record;
  v_definition text;
BEGIN
  FOR v_function IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname IN (
        'bayar_tagihan_sopir_cb',
        'create_biaya_operasional_kas',
        'create_hutang_pihak',
        'create_kas_mutasi',
        'create_panjar_mitra_kas',
        'create_pembayaran_mitra_kwitansi',
        'create_pembayaran_pabrik_batch',
        'record_pengiriman_lokal_status',
        'settle_panjar_mitra_manual'
      )
  LOOP
    v_definition := pg_get_functiondef(v_function.oid);
    v_definition := replace(
      v_definition,
      'ARRAY[''owner'', ''super_admin'', ''admin_keuangan'']',
      'ARRAY[''owner'', ''super_admin'', ''admin_keuangan'', ''admin_operasional'']'
    );
    EXECUTE v_definition;
  END LOOP;

  FOR v_function IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND p.proname IN (
        'cancel_biaya_operasional_kas',
        'cancel_hutang_ledger',
        'cancel_panjar_mitra_kas',
        'cancel_pembayaran_pabrik_batch'
      )
  LOOP
    v_definition := pg_get_functiondef(v_function.oid);
    v_definition := replace(
      v_definition,
      'ARRAY[''owner'', ''super_admin'', ''admin_keuangan'', ''admin_operasional'']',
      'ARRAY[''owner'', ''super_admin'']'
    );
    v_definition := replace(
      v_definition,
      'ARRAY[''owner'', ''super_admin'', ''admin_keuangan'']',
      'ARRAY[''owner'', ''super_admin'']'
    );
    EXECUTE v_definition;
  END LOOP;
END $$;

-- Audit rows can only be produced by an authenticated application user.
CREATE OR REPLACE FUNCTION public.write_audit_log(
  p_entity_type text,
  p_entity_id uuid,
  p_action text,
  p_before_json jsonb DEFAULT NULL,
  p_after_json jsonb DEFAULT NULL,
  p_alasan text DEFAULT NULL,
  p_approved_by uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_actor_role text;
  v_approved_by uuid := NULL;
  v_new_id uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Login diperlukan untuk mencatat audit.' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_entity_type, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_action, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Jenis data dan aksi audit wajib diisi.' USING ERRCODE = '22023';
  END IF;

  v_actor_role := public.current_app_role();

  IF p_approved_by IS NOT NULL THEN
    IF v_actor_role NOT IN ('owner', 'super_admin') OR p_approved_by <> v_actor THEN
      RAISE EXCEPTION 'Persetujuan audit hanya dapat diberikan oleh pengguna yang sedang login.'
        USING ERRCODE = '42501';
    END IF;
    v_approved_by := v_actor;
  END IF;

  INSERT INTO public.audit_log (
    actor_user_id,
    actor_role,
    entity_type,
    entity_id,
    action,
    before_json,
    after_json,
    alasan,
    approved_by,
    approved_at
  ) VALUES (
    v_actor,
    v_actor_role,
    btrim(p_entity_type),
    p_entity_id,
    btrim(p_action),
    p_before_json,
    p_after_json,
    NULLIF(btrim(COALESCE(p_alasan, '')), ''),
    v_approved_by,
    CASE WHEN v_approved_by IS NULL THEN NULL ELSE now() END
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.write_audit_log(text, uuid, text, jsonb, jsonb, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.write_audit_log(text, uuid, text, jsonb, jsonb, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.write_audit_log(text, uuid, text, jsonb, jsonb, text, uuid) TO authenticated;

DROP POLICY IF EXISTS insert_authenticated ON public.audit_log;
CREATE POLICY insert_via_controlled_function
ON public.audit_log
FOR INSERT
TO authenticated
WITH CHECK (actor_user_id = auth.uid() AND actor_role = public.current_app_role());

-- Master Mitra and its tariff history are saved atomically. Admin may maintain
-- identity data, while only Owner/Super Admin may alter financial rates.
CREATE OR REPLACE FUNCTION public.save_master_mitra(
  p_id uuid DEFAULT NULL,
  p_kode text DEFAULT NULL,
  p_nama text DEFAULT NULL,
  p_penanggung_jawab text DEFAULT NULL,
  p_no_hp text DEFAULT NULL,
  p_alamat text DEFAULT NULL,
  p_tipe_mitra text DEFAULT 'eksternal',
  p_fee_per_kg numeric DEFAULT 0,
  p_tarif_sewa_angkut_per_kg numeric DEFAULT 0,
  p_dana_operasional_trip numeric DEFAULT 0,
  p_berlaku_mulai date DEFAULT CURRENT_DATE,
  p_alasan_perubahan text DEFAULT NULL
)
RETURNS public.master_mitra
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_role text := public.current_app_role();
  v_before public.master_mitra%ROWTYPE;
  v_after public.master_mitra%ROWTYPE;
  v_can_set_tariff boolean;
  v_fee numeric := GREATEST(COALESCE(p_fee_per_kg, 0), 0);
  v_sewa numeric := GREATEST(COALESCE(p_tarif_sewa_angkut_per_kg, 0), 0);
  v_dana numeric := GREATEST(COALESCE(p_dana_operasional_trip, 0), 0);
  v_next_start date;
BEGIN
  IF v_actor IS NULL OR v_role NOT IN ('owner', 'super_admin', 'admin_operasional') THEN
    RAISE EXCEPTION 'Tidak berwenang menyimpan Mitra.' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_kode, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_nama, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Kode dan nama Mitra wajib diisi.' USING ERRCODE = '22023';
  END IF;

  IF COALESCE(p_tipe_mitra, 'eksternal') NOT IN ('eksternal', 'internal_owner') THEN
    RAISE EXCEPTION 'Tipe Mitra tidak valid.' USING ERRCODE = '22023';
  END IF;

  v_can_set_tariff := v_role IN ('owner', 'super_admin');

  IF p_id IS NOT NULL THEN
    SELECT * INTO v_before FROM public.master_mitra WHERE id = p_id FOR UPDATE;
    IF v_before.id IS NULL THEN
      RAISE EXCEPTION 'Mitra tidak ditemukan.' USING ERRCODE = 'P0002';
    END IF;

    IF NOT v_can_set_tariff AND (
      round(v_fee, 2) IS DISTINCT FROM round(COALESCE(v_before.fee_per_kg, 0), 2)
      OR round(v_sewa, 2) IS DISTINCT FROM round(COALESCE(v_before.tarif_sewa_angkut_per_kg, 0), 2)
      OR round(v_dana, 2) IS DISTINCT FROM round(COALESCE(v_before.dana_operasional_trip, 0), 2)
    ) THEN
      RAISE EXCEPTION 'Perubahan tarif hanya dapat dilakukan Owner.' USING ERRCODE = '42501';
    END IF;

    UPDATE public.master_mitra
    SET kode = upper(btrim(p_kode)),
        nama = btrim(p_nama),
        penanggung_jawab = NULLIF(btrim(COALESCE(p_penanggung_jawab, '')), ''),
        no_hp = NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
        alamat = NULLIF(btrim(COALESCE(p_alamat, '')), ''),
        tipe_mitra = COALESCE(p_tipe_mitra, 'eksternal'),
        fee_per_kg = CASE WHEN v_can_set_tariff THEN v_fee ELSE fee_per_kg END,
        tarif_sewa_angkut_per_kg = CASE WHEN v_can_set_tariff THEN v_sewa ELSE tarif_sewa_angkut_per_kg END,
        dana_operasional_trip = CASE WHEN v_can_set_tariff THEN v_dana ELSE dana_operasional_trip END,
        status_verifikasi = CASE WHEN v_can_set_tariff THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
        diverifikasi_oleh = CASE WHEN v_can_set_tariff THEN v_actor ELSE NULL END,
        diverifikasi_at = CASE WHEN v_can_set_tariff THEN now() ELSE NULL END
    WHERE id = p_id
    RETURNING * INTO v_after;
  ELSE
    IF NOT v_can_set_tariff AND (v_fee > 0 OR v_sewa > 0 OR v_dana > 0) THEN
      RAISE EXCEPTION 'Admin dapat membuat Mitra baru dengan tarif Rp0. Owner mengisi tarif setelah verifikasi.'
        USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.master_mitra (
      kode, nama, penanggung_jawab, no_hp, alamat, tipe_mitra,
      fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip,
      aktif, dibuat_oleh, status_verifikasi, diverifikasi_oleh, diverifikasi_at
    ) VALUES (
      upper(btrim(p_kode)), btrim(p_nama),
      NULLIF(btrim(COALESCE(p_penanggung_jawab, '')), ''),
      NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
      NULLIF(btrim(COALESCE(p_alamat, '')), ''),
      COALESCE(p_tipe_mitra, 'eksternal'),
      CASE WHEN v_can_set_tariff THEN v_fee ELSE 0 END,
      CASE WHEN v_can_set_tariff THEN v_sewa ELSE 0 END,
      CASE WHEN v_can_set_tariff THEN v_dana ELSE 0 END,
      true, v_actor,
      CASE WHEN v_can_set_tariff THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
      CASE WHEN v_can_set_tariff THEN v_actor ELSE NULL END,
      CASE WHEN v_can_set_tariff THEN now() ELSE NULL END
    )
    RETURNING * INTO v_after;
  END IF;

  IF v_can_set_tariff THEN
    SELECT min(berlaku_mulai)
    INTO v_next_start
    FROM public.fee_owner_mitra_history
    WHERE master_mitra_id = v_after.id
      AND aktif = true
      AND berlaku_mulai > COALESCE(p_berlaku_mulai, CURRENT_DATE);

    UPDATE public.fee_owner_mitra_history
    SET berlaku_sampai = COALESCE(p_berlaku_mulai, CURRENT_DATE) - 1
    WHERE master_mitra_id = v_after.id
      AND aktif = true
      AND berlaku_mulai < COALESCE(p_berlaku_mulai, CURRENT_DATE)
      AND (berlaku_sampai IS NULL OR berlaku_sampai >= COALESCE(p_berlaku_mulai, CURRENT_DATE));

    INSERT INTO public.fee_owner_mitra_history (
      master_mitra_id, fee_per_kg, tarif_sewa_angkut_per_kg,
      dana_operasional_trip, berlaku_mulai, berlaku_sampai,
      aktif, alasan_perubahan, created_by
    ) VALUES (
      v_after.id, v_fee, v_sewa, v_dana,
      COALESCE(p_berlaku_mulai, CURRENT_DATE),
      CASE WHEN v_next_start IS NULL THEN NULL ELSE v_next_start - 1 END,
      true,
      COALESCE(NULLIF(btrim(COALESCE(p_alasan_perubahan, '')), ''), 'Perubahan tarif dari Master Mitra'),
      v_actor
    )
    ON CONFLICT (master_mitra_id, berlaku_mulai)
    DO UPDATE SET
      fee_per_kg = EXCLUDED.fee_per_kg,
      tarif_sewa_angkut_per_kg = EXCLUDED.tarif_sewa_angkut_per_kg,
      dana_operasional_trip = EXCLUDED.dana_operasional_trip,
      berlaku_sampai = EXCLUDED.berlaku_sampai,
      aktif = true,
      alasan_perubahan = EXCLUDED.alasan_perubahan;
  END IF;

  PERFORM public.write_audit_log(
    'master_mitra', v_after.id,
    CASE WHEN p_id IS NULL THEN 'create' ELSE 'update' END,
    CASE WHEN p_id IS NULL THEN NULL ELSE to_jsonb(v_before) END,
    to_jsonb(v_after),
    p_alasan_perubahan,
    CASE WHEN v_can_set_tariff THEN v_actor ELSE NULL END
  );

  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_master_mitra(p_id uuid, p_catatan text DEFAULT NULL)
RETURNS public.master_mitra
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.master_mitra%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat memverifikasi Mitra.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.master_mitra
  SET status_verifikasi = 'terverifikasi',
      diverifikasi_oleh = v_actor,
      diverifikasi_at = now(),
      catatan_verifikasi = NULLIF(btrim(COALESCE(p_catatan, '')), '')
  WHERE id = p_id
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Mitra tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  PERFORM public.write_audit_log('master_mitra', v_row.id, 'verify', NULL, to_jsonb(v_row), p_catatan, v_actor);
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_sopir_armada(
  p_id uuid DEFAULT NULL,
  p_nama text DEFAULT NULL,
  p_no_hp text DEFAULT NULL,
  p_mitra_id uuid DEFAULT NULL,
  p_plat_nomor text DEFAULT NULL,
  p_is_armada_cb boolean DEFAULT false
)
RETURNS public.sopir
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_role text := public.current_app_role();
  v_before public.sopir%ROWTYPE;
  v_after public.sopir%ROWTYPE;
  v_plat text := upper(regexp_replace(btrim(COALESCE(p_plat_nomor, '')), '\s+', ' ', 'g'));
BEGIN
  IF v_actor IS NULL OR v_role NOT IN ('owner', 'super_admin', 'admin_operasional') THEN
    RAISE EXCEPTION 'Tidak berwenang menyimpan Sopir/Armada.' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_nama, '')), '') IS NULL OR NULLIF(v_plat, '') IS NULL THEN
    RAISE EXCEPTION 'Nama sopir/unit dan plat nomor wajib diisi.' USING ERRCODE = '22023';
  END IF;

  IF p_mitra_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.master_mitra WHERE id = p_mitra_id AND COALESCE(aktif, true) = true
  ) THEN
    RAISE EXCEPTION 'Mitra default tidak ditemukan atau sudah tidak aktif.' USING ERRCODE = 'P0002';
  END IF;

  IF p_id IS NOT NULL THEN
    SELECT * INTO v_before FROM public.sopir WHERE id = p_id FOR UPDATE;
    IF v_before.id IS NULL THEN
      RAISE EXCEPTION 'Sopir/Armada tidak ditemukan.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.sopir
    SET nama = btrim(p_nama),
        no_hp = NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
        mitra_id = p_mitra_id,
        plat_nomor = v_plat,
        is_armada_cb = COALESCE(p_is_armada_cb, false),
        status_verifikasi = CASE WHEN v_role IN ('owner', 'super_admin') THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
        diverifikasi_oleh = CASE WHEN v_role IN ('owner', 'super_admin') THEN v_actor ELSE NULL END,
        diverifikasi_at = CASE WHEN v_role IN ('owner', 'super_admin') THEN now() ELSE NULL END,
        updated_at = now()
    WHERE id = p_id
    RETURNING * INTO v_after;
  ELSE
    INSERT INTO public.sopir (
      nama, no_hp, mitra_id, plat_nomor, is_armada_cb, aktif,
      dibuat_oleh, status_verifikasi, diverifikasi_oleh, diverifikasi_at
    ) VALUES (
      btrim(p_nama), NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
      p_mitra_id, v_plat, COALESCE(p_is_armada_cb, false), true,
      v_actor,
      CASE WHEN v_role IN ('owner', 'super_admin') THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
      CASE WHEN v_role IN ('owner', 'super_admin') THEN v_actor ELSE NULL END,
      CASE WHEN v_role IN ('owner', 'super_admin') THEN now() ELSE NULL END
    )
    RETURNING * INTO v_after;
  END IF;

  PERFORM public.write_audit_log(
    'sopir_armada', v_after.id,
    CASE WHEN p_id IS NULL THEN 'create' ELSE 'update' END,
    CASE WHEN p_id IS NULL THEN NULL ELSE to_jsonb(v_before) END,
    to_jsonb(v_after), NULL,
    CASE WHEN v_role IN ('owner', 'super_admin') THEN v_actor ELSE NULL END
  );

  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_sopir_armada(p_id uuid, p_catatan text DEFAULT NULL)
RETURNS public.sopir
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.sopir%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat memverifikasi Sopir/Armada.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.sopir
  SET status_verifikasi = 'terverifikasi',
      diverifikasi_oleh = v_actor,
      diverifikasi_at = now(),
      catatan_verifikasi = NULLIF(btrim(COALESCE(p_catatan, '')), ''),
      updated_at = now()
  WHERE id = p_id
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Sopir/Armada tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  PERFORM public.write_audit_log('sopir_armada', v_row.id, 'verify', NULL, to_jsonb(v_row), p_catatan, v_actor);
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_master_mitra_sensitive_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := public.current_app_role();
BEGIN
  IF auth.uid() IS NULL OR v_role IN ('owner', 'super_admin') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF COALESCE(NEW.fee_per_kg, 0) <> 0
       OR COALESCE(NEW.tarif_sewa_angkut_per_kg, 0) <> 0
       OR COALESCE(NEW.dana_operasional_trip, 0) <> 0 THEN
      RAISE EXCEPTION 'Tarif Mitra baru diisi oleh Owner setelah verifikasi.' USING ERRCODE = '42501';
    END IF;
    NEW.status_verifikasi := 'perlu_verifikasi';
    NEW.diverifikasi_oleh := NULL;
    NEW.diverifikasi_at := NULL;
    NEW.dibuat_oleh := auth.uid();
    RETURN NEW;
  END IF;

  IF OLD.aktif IS DISTINCT FROM NEW.aktif THEN
    RAISE EXCEPTION 'Penonaktifan Mitra memerlukan Owner.' USING ERRCODE = '42501';
  END IF;

  IF OLD.fee_per_kg IS DISTINCT FROM NEW.fee_per_kg
     OR OLD.tarif_sewa_angkut_per_kg IS DISTINCT FROM NEW.tarif_sewa_angkut_per_kg
     OR OLD.dana_operasional_trip IS DISTINCT FROM NEW.dana_operasional_trip THEN
    RAISE EXCEPTION 'Perubahan tarif memerlukan Owner.' USING ERRCODE = '42501';
  END IF;

  NEW.status_verifikasi := 'perlu_verifikasi';
  NEW.diverifikasi_oleh := NULL;
  NEW.diverifikasi_at := NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_master_mitra_sensitive_changes ON public.master_mitra;
CREATE TRIGGER guard_master_mitra_sensitive_changes
BEFORE INSERT OR UPDATE ON public.master_mitra
FOR EACH ROW EXECUTE FUNCTION public.guard_master_mitra_sensitive_changes();

CREATE OR REPLACE FUNCTION public.guard_sopir_armada_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := public.current_app_role();
BEGIN
  IF auth.uid() IS NULL OR v_role IN ('owner', 'super_admin') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.status_verifikasi := 'perlu_verifikasi';
    NEW.diverifikasi_oleh := NULL;
    NEW.diverifikasi_at := NULL;
    NEW.dibuat_oleh := auth.uid();
    RETURN NEW;
  END IF;

  IF OLD.aktif IS DISTINCT FROM NEW.aktif THEN
    RAISE EXCEPTION 'Penonaktifan Sopir/Armada memerlukan Owner.' USING ERRCODE = '42501';
  END IF;

  NEW.status_verifikasi := 'perlu_verifikasi';
  NEW.diverifikasi_oleh := NULL;
  NEW.diverifikasi_at := NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_sopir_armada_verification ON public.sopir;
CREATE TRIGGER guard_sopir_armada_verification
BEFORE INSERT OR UPDATE ON public.sopir
FOR EACH ROW EXECUTE FUNCTION public.guard_sopir_armada_verification();

REVOKE ALL ON FUNCTION public.save_master_mitra(uuid, text, text, text, text, text, text, numeric, numeric, numeric, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_master_mitra(uuid, text, text, text, text, text, text, numeric, numeric, numeric, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.verify_master_mitra(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_master_mitra(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.save_sopir_armada(uuid, text, text, uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_sopir_armada(uuid, text, text, uuid, text, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.verify_sopir_armada(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_sopir_armada(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.guard_master_mitra_sensitive_changes() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_sopir_armada_verification() FROM PUBLIC, anon, authenticated;

-- Replace broad full-access policies with explicit operation policies.
DROP POLICY IF EXISTS "Authenticated full access" ON public.master_mitra;
DROP POLICY IF EXISTS read_authenticated ON public.master_mitra;
DROP POLICY IF EXISTS insert_operations ON public.master_mitra;
DROP POLICY IF EXISTS update_operations ON public.master_mitra;
CREATE POLICY read_authenticated ON public.master_mitra FOR SELECT TO authenticated USING (true);
CREATE POLICY insert_operations ON public.master_mitra FOR INSERT TO authenticated
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']));
CREATE POLICY update_operations ON public.master_mitra FOR UPDATE TO authenticated
  USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']))
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']));

DROP POLICY IF EXISTS "Authenticated full access" ON public.transaksi_mitra;
DROP POLICY IF EXISTS read_authenticated ON public.transaksi_mitra;
DROP POLICY IF EXISTS insert_operations ON public.transaksi_mitra;
DROP POLICY IF EXISTS update_operations ON public.transaksi_mitra;
CREATE POLICY read_authenticated ON public.transaksi_mitra FOR SELECT TO authenticated USING (true);
CREATE POLICY insert_operations ON public.transaksi_mitra FOR INSERT TO authenticated
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']));
CREATE POLICY update_operations ON public.transaksi_mitra FOR UPDATE TO authenticated
  USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']))
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']));

DROP POLICY IF EXISTS "Authenticated full access" ON public.fee_owner_mitra_history;
DROP POLICY IF EXISTS read_authenticated ON public.fee_owner_mitra_history;
DROP POLICY IF EXISTS write_owner ON public.fee_owner_mitra_history;
CREATE POLICY read_authenticated ON public.fee_owner_mitra_history FOR SELECT TO authenticated USING (true);
CREATE POLICY write_owner ON public.fee_owner_mitra_history FOR ALL TO authenticated
  USING (public.has_app_role(ARRAY['owner', 'super_admin']))
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin']));

DROP POLICY IF EXISTS write_operations ON public.sopir;
CREATE POLICY write_operations ON public.sopir FOR ALL TO authenticated
  USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']))
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']));

-- Current Admin performs routine finance recording. Sensitive cancellation is
-- still protected inside Owner-only RPCs.
DROP POLICY IF EXISTS read_finance ON public.kas_ledger;
CREATE POLICY read_finance ON public.kas_ledger FOR SELECT TO authenticated
  USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));
DROP POLICY IF EXISTS insert_finance ON public.kas_ledger;
CREATE POLICY insert_finance ON public.kas_ledger FOR INSERT TO authenticated
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));
DROP POLICY IF EXISTS update_finance ON public.kas_ledger;
CREATE POLICY update_finance ON public.kas_ledger FOR UPDATE TO authenticated
  USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']))
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));

DROP POLICY IF EXISTS insert_finance ON public.hutang_ledger;
CREATE POLICY insert_finance ON public.hutang_ledger FOR INSERT TO authenticated
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));
DROP POLICY IF EXISTS update_finance ON public.hutang_ledger;
CREATE POLICY update_finance ON public.hutang_ledger FOR UPDATE TO authenticated
  USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']))
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));

DROP POLICY IF EXISTS insert_finance ON public.pembayaran_mitra_kwitansi;
CREATE POLICY insert_finance ON public.pembayaran_mitra_kwitansi FOR INSERT TO authenticated
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));
DROP POLICY IF EXISTS update_finance ON public.pembayaran_mitra_kwitansi;
CREATE POLICY update_finance ON public.pembayaran_mitra_kwitansi FOR UPDATE TO authenticated
  USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']))
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));

DROP POLICY IF EXISTS insert_finance ON public.pembayaran_mitra_kwitansi_item;
CREATE POLICY insert_finance ON public.pembayaran_mitra_kwitansi_item FOR INSERT TO authenticated
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));
DROP POLICY IF EXISTS update_finance ON public.pembayaran_mitra_kwitansi_item;
CREATE POLICY update_finance ON public.pembayaran_mitra_kwitansi_item FOR UPDATE TO authenticated
  USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']))
  WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));

-- Hard delete and truncate are never application workflows.
DO $$
DECLARE
  v_table record;
BEGIN
  FOR v_table IN
    SELECT schemaname, tablename
    FROM pg_tables
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format('REVOKE DELETE, TRUNCATE ON TABLE %I.%I FROM anon, authenticated', v_table.schemaname, v_table.tablename);
  END LOOP;
END $$;
