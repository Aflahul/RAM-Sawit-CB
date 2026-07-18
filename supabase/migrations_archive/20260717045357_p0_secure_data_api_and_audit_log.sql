-- P0 containment for TASK-SEC-001 and TASK-SEC-002.
--
-- This migration deliberately preserves the current permissions of the four
-- recognized application roles. It closes the authenticated-without-profile
-- path first, then makes the audit trail append-only. Column-scoped DTO/RPC
-- access for operational users is delivered separately before direct reads
-- from strategic financial tables are revoked.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Replace broad authenticated reads with an explicit application-role gate.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'armada_mitra',
    'armada_perusahaan',
    'biaya_operasional',
    'bukti_pembayaran',
    'fee_mitra_history',
    'fee_owner_mitra_history',
    'harga_tbs',
    'harga_tbs_lokal',
    'hutang',
    'hutang_ledger',
    'hutang_log',
    'kendaraan',
    'master_mitra',
    'mitra',
    'pabrik',
    'panjar_mitra',
    'pembayaran_mitra',
    'pembayaran_mitra_kwitansi',
    'pembayaran_mitra_kwitansi_item',
    'pembayaran_mitra_kwitansi_mitra',
    'pembayaran_pabrik',
    'pembayaran_pabrik_batch',
    'pembayaran_pabrik_detail',
    'pembayaran_pabrik_item',
    'pengaturan_bisnis',
    'pengiriman',
    'pengiriman_lokal_detail',
    'petani',
    'piutang_dokumen',
    'piutang_pelunasan',
    'settlement_mitra',
    'sopir',
    'stok_tbs_lokal_ledger',
    'tarif_armada',
    'transaksi_beli',
    'transaksi_beli_tbs',
    'transaksi_mitra'
  ]
  LOOP
    IF to_regclass(format('public.%I', v_table)) IS NULL THEN
      RAISE EXCEPTION 'Tabel wajib untuk security containment tidak ditemukan: %', v_table;
    END IF;

    EXECUTE format(
      'DROP POLICY IF EXISTS read_authenticated ON public.%I',
      v_table
    );
    EXECUTE format(
      'DROP POLICY IF EXISTS require_valid_app_role ON public.%I',
      v_table
    );
    EXECUTE format(
      'CREATE POLICY read_authenticated ON public.%I
       FOR SELECT TO authenticated
       USING ((SELECT public.has_app_role(
         ARRAY[''owner'', ''super_admin'', ''admin_operasional'', ''admin_keuangan'']
      )))',
      v_table
    );
    EXECUTE format(
      'CREATE POLICY require_valid_app_role ON public.%I
       AS RESTRICTIVE
       FOR ALL TO authenticated
       USING ((SELECT public.has_app_role(
         ARRAY[''owner'', ''super_admin'', ''admin_operasional'', ''admin_keuangan'']
       )))
       WITH CHECK ((SELECT public.has_app_role(
         ARRAY[''owner'', ''super_admin'', ''admin_operasional'', ''admin_keuangan'']
       )))',
      v_table
    );
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Keep audit writes inside the controlled writer and make rows immutable.
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'app_audit_writer'
  ) THEN
    CREATE ROLE app_audit_writer NOLOGIN NOINHERIT;
  END IF;
END;
$$;

ALTER ROLE app_audit_writer NOLOGIN NOINHERIT;
GRANT app_audit_writer TO postgres;

CREATE OR REPLACE FUNCTION public.current_audit_actor_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT auth.uid();
$$;

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

CREATE OR REPLACE FUNCTION public.guard_audit_log_insert()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_writer_owner name;
  v_actor_role text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(proc.proowner)
  INTO v_writer_owner
  FROM pg_catalog.pg_proc proc
  WHERE proc.oid = 'public.write_audit_log(text,uuid,text,jsonb,jsonb,text,uuid)'::regprocedure;

  IF v_writer_owner IS NULL OR current_user <> v_writer_owner THEN
    RAISE EXCEPTION 'Audit hanya dapat ditulis melalui fungsi internal.'
      USING ERRCODE = '42501';
  END IF;

  IF public.current_audit_actor_id() IS NULL
     OR NEW.actor_user_id IS DISTINCT FROM public.current_audit_actor_id() THEN
    RAISE EXCEPTION 'Aktor audit tidak sesuai dengan pengguna yang sedang login.'
      USING ERRCODE = '42501';
  END IF;

  v_actor_role := public.current_app_role();
  IF v_actor_role NOT IN ('owner', 'super_admin', 'admin_operasional', 'admin_keuangan')
     OR NEW.actor_role IS DISTINCT FROM v_actor_role THEN
    RAISE EXCEPTION 'Role aktor audit tidak valid.'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_audit_log_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Audit bersifat permanen dan tidak dapat diubah, dihapus, atau dikosongkan.'
    USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS guard_audit_log_insert ON public.audit_log;
CREATE TRIGGER guard_audit_log_insert
BEFORE INSERT ON public.audit_log
FOR EACH ROW
EXECUTE FUNCTION public.guard_audit_log_insert();

DROP TRIGGER IF EXISTS reject_audit_log_mutation ON public.audit_log;
CREATE TRIGGER reject_audit_log_mutation
BEFORE UPDATE OR DELETE OR TRUNCATE ON public.audit_log
FOR EACH STATEMENT
EXECUTE FUNCTION public.reject_audit_log_mutation();

DROP POLICY IF EXISTS insert_authenticated ON public.audit_log;
DROP POLICY IF EXISTS insert_via_controlled_function ON public.audit_log;
DROP POLICY IF EXISTS insert_internal_writer ON public.audit_log;

REVOKE ALL PRIVILEGES ON TABLE public.audit_log
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.audit_log TO authenticated, service_role;
GRANT INSERT ON TABLE public.audit_log TO app_audit_writer;

CREATE POLICY insert_internal_writer
ON public.audit_log
FOR INSERT
TO app_audit_writer
WITH CHECK (
  actor_user_id = public.current_audit_actor_id()
  AND actor_role = public.current_app_role()
  AND actor_role IN ('owner', 'super_admin', 'admin_operasional', 'admin_keuangan')
);

GRANT USAGE ON SCHEMA public TO app_audit_writer;
GRANT EXECUTE ON FUNCTION public.current_audit_actor_id() TO app_audit_writer;
GRANT EXECUTE ON FUNCTION public.current_app_role() TO app_audit_writer;

GRANT CREATE ON SCHEMA public TO app_audit_writer;
ALTER FUNCTION public.write_audit_log(text, uuid, text, jsonb, jsonb, text, uuid)
  SET search_path = '';
ALTER FUNCTION public.write_audit_log(text, uuid, text, jsonb, jsonb, text, uuid)
  OWNER TO app_audit_writer;
REVOKE CREATE ON SCHEMA public FROM app_audit_writer;

REVOKE ALL ON FUNCTION
  public.write_audit_log(text, uuid, text, jsonb, jsonb, text, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.current_audit_actor_id()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.guard_audit_log_insert()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.reject_audit_log_mutation()
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
