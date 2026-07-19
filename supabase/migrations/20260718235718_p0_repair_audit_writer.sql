DROP POLICY IF EXISTS insert_internal_writer ON public.audit_log;

CREATE POLICY insert_internal_writer
ON public.audit_log
FOR INSERT
TO app_audit_writer
WITH CHECK (
  actor_user_id = public.current_audit_actor_id()
  AND actor_role = public.current_app_role()
  AND actor_role IN ('owner', 'super_admin', 'admin_operasional', 'admin_keuangan')
);

REVOKE SELECT (id) ON public.audit_log FROM app_audit_writer;

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
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := public.current_audit_actor_id();
  v_actor_role text;
  v_approved_by uuid := NULL;
  v_new_id uuid := gen_random_uuid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Login diperlukan untuk mencatat audit.' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_entity_type, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_action, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Jenis data dan aksi audit wajib diisi.' USING ERRCODE = '22023';
  END IF;

  v_actor_role := public.current_app_role();
  IF v_actor_role NOT IN ('owner', 'super_admin', 'admin_operasional', 'admin_keuangan') THEN
    RAISE EXCEPTION 'Role pengguna tidak valid untuk mencatat audit.' USING ERRCODE = '42501';
  END IF;

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
    id,
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
    v_new_id,
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
  );

  RETURN v_new_id;
END;
$$;

ALTER FUNCTION public.write_audit_log(text, uuid, text, jsonb, jsonb, text, uuid)
  OWNER TO app_audit_writer;

REVOKE ALL ON FUNCTION public.write_audit_log(text, uuid, text, jsonb, jsonb, text, uuid)
FROM PUBLIC, anon, authenticated, service_role;
