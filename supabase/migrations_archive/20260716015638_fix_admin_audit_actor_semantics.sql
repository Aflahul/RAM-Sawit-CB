-- Controlled RPCs pass their actor to the audit helper. For Admin actions this
-- identifies the recorder, but it must not be stored as an Owner approval.
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
    IF p_approved_by <> v_actor THEN
      RAISE EXCEPTION 'Pemberi persetujuan harus sama dengan pengguna yang sedang login.'
        USING ERRCODE = '42501';
    END IF;

    IF v_actor_role IN ('owner', 'super_admin') THEN
      v_approved_by := v_actor;
    END IF;
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

REVOKE ALL ON FUNCTION public.write_audit_log(text, uuid, text, jsonb, jsonb, text, uuid)
  FROM PUBLIC, anon, authenticated;
