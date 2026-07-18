-- Smoke test for 20260717045357_p0_secure_data_api_and_audit_log.sql.
-- Run only against an explicitly selected staging database. All test objects,
-- data, grants, and mutations are rolled back.

BEGIN;

CREATE TEMP TABLE p0_security_target_tables (
  table_name text PRIMARY KEY
) ON COMMIT DROP;

INSERT INTO p0_security_target_tables (table_name)
VALUES
  ('armada_mitra'), ('armada_perusahaan'), ('biaya_operasional'),
  ('bukti_pembayaran'), ('fee_mitra_history'),
  ('fee_owner_mitra_history'), ('harga_tbs'), ('harga_tbs_lokal'),
  ('hutang'), ('hutang_ledger'), ('hutang_log'), ('kendaraan'),
  ('master_mitra'), ('mitra'), ('pabrik'), ('panjar_mitra'),
  ('pembayaran_mitra'), ('pembayaran_mitra_kwitansi'),
  ('pembayaran_mitra_kwitansi_item'),
  ('pembayaran_mitra_kwitansi_mitra'), ('pembayaran_pabrik'),
  ('pembayaran_pabrik_batch'), ('pembayaran_pabrik_detail'),
  ('pembayaran_pabrik_item'), ('pengaturan_bisnis'), ('pengiriman'),
  ('pengiriman_lokal_detail'), ('petani'), ('piutang_dokumen'),
  ('piutang_pelunasan'), ('settlement_mitra'), ('sopir'),
  ('stok_tbs_lokal_ledger'), ('tarif_armada'), ('transaksi_beli'),
  ('transaksi_beli_tbs'), ('transaksi_mitra');

DO $policy_test$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*)
  INTO v_count
  FROM p0_security_target_tables target
  LEFT JOIN pg_catalog.pg_class relation
    ON relation.oid = to_regclass(format('public.%I', target.table_name))
  WHERE relation.oid IS NULL OR relation.relrowsecurity IS NOT TRUE;

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% tabel target tidak memiliki RLS aktif.', v_count;
  END IF;

  SELECT count(*)
  INTO v_count
  FROM p0_security_target_tables target
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies policy
    WHERE policy.schemaname = 'public'
      AND policy.tablename = target.table_name
      AND policy.policyname = 'require_valid_app_role'
      AND policy.permissive = 'RESTRICTIVE'
      AND policy.cmd = 'ALL'
      AND 'authenticated' = ANY(policy.roles)
      AND policy.qual LIKE '%has_app_role%'
      AND policy.with_check LIKE '%has_app_role%'
  );

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% tabel target tidak memiliki restrictive role gate.', v_count;
  END IF;

  SELECT count(*)
  INTO v_count
  FROM pg_catalog.pg_policies policy
  JOIN p0_security_target_tables target ON target.table_name = policy.tablename
  WHERE policy.schemaname = 'public'
    AND policy.permissive = 'PERMISSIVE'
    AND policy.cmd IN ('SELECT', 'ALL')
    AND 'authenticated' = ANY(policy.roles)
    AND regexp_replace(COALESCE(policy.qual, ''), '[[:space:]()]', '', 'g') = 'true';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Masih ada % policy permissive broad-read pada tabel target.', v_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger trigger
    WHERE trigger.tgrelid = 'public.audit_log'::regclass
      AND trigger.tgname = 'guard_audit_log_insert'
      AND trigger.tgenabled <> 'D'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger trigger
    WHERE trigger.tgrelid = 'public.audit_log'::regclass
      AND trigger.tgname = 'reject_audit_log_mutation'
      AND trigger.tgenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'Trigger immutable audit belum aktif.';
  END IF;
END;
$policy_test$;

DO $audit_writer_state_test$
DECLARE
  v_writer_oid oid;
  v_postgres_oid oid;
  v_writer_function regprocedure :=
    'public.write_audit_log(text,uuid,text,jsonb,jsonb,text,uuid)'::regprocedure;
  v_function_owner name;
  v_security_definer boolean;
  v_function_config text[];
BEGIN
  SELECT oid
  INTO v_writer_oid
  FROM pg_catalog.pg_roles
  WHERE rolname = 'app_audit_writer'
    AND rolcanlogin IS FALSE
    AND rolinherit IS FALSE;

  IF v_writer_oid IS NULL THEN
    RAISE EXCEPTION 'Role app_audit_writer tidak ada atau bukan NOLOGIN NOINHERIT.';
  END IF;

  SELECT oid INTO v_postgres_oid
  FROM pg_catalog.pg_roles
  WHERE rolname = 'postgres';

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members membership
    WHERE membership.roleid = v_writer_oid
      AND membership.member = v_postgres_oid
  ) THEN
    RAISE EXCEPTION 'Role postgres bukan anggota app_audit_writer.';
  END IF;

  SELECT
    pg_catalog.pg_get_userbyid(proc.proowner),
    proc.prosecdef,
    proc.proconfig
  INTO v_function_owner, v_security_definer, v_function_config
  FROM pg_catalog.pg_proc proc
  WHERE proc.oid = v_writer_function;

  IF v_function_owner IS DISTINCT FROM 'app_audit_writer'
     OR v_security_definer IS NOT TRUE
     OR NOT ('search_path=""' = ANY(COALESCE(v_function_config, ARRAY[]::text[]))) THEN
    RAISE EXCEPTION
      'Writer audit harus SECURITY DEFINER milik app_audit_writer dengan search_path kosong.';
  END IF;

  IF pg_catalog.has_schema_privilege('app_audit_writer', 'public', 'CREATE')
     OR NOT pg_catalog.has_schema_privilege('app_audit_writer', 'public', 'USAGE') THEN
    RAISE EXCEPTION 'Privilege schema app_audit_writer tidak minimum.';
  END IF;

  IF NOT pg_catalog.has_table_privilege(
    'app_audit_writer', 'public.audit_log', 'INSERT'
  ) OR pg_catalog.has_table_privilege(
    'app_audit_writer', 'public.audit_log', 'UPDATE'
  ) OR pg_catalog.has_table_privilege(
    'app_audit_writer', 'public.audit_log', 'DELETE'
  ) OR pg_catalog.has_table_privilege(
    'app_audit_writer', 'public.audit_log', 'TRUNCATE'
  ) THEN
    RAISE EXCEPTION 'Privilege tabel app_audit_writer tidak sesuai kontrak append-only.';
  END IF;

  IF pg_catalog.has_table_privilege(
    'authenticated', 'public.audit_log', 'INSERT'
  ) OR pg_catalog.has_table_privilege(
    'authenticated', 'public.audit_log', 'UPDATE'
  ) OR pg_catalog.has_table_privilege(
    'authenticated', 'public.audit_log', 'DELETE'
  ) OR pg_catalog.has_table_privilege(
    'authenticated', 'public.audit_log', 'TRUNCATE'
  ) OR pg_catalog.has_table_privilege(
    'anon', 'public.audit_log', 'INSERT'
  ) OR pg_catalog.has_table_privilege(
    'anon', 'public.audit_log', 'UPDATE'
  ) OR pg_catalog.has_table_privilege(
    'anon', 'public.audit_log', 'DELETE'
  ) OR pg_catalog.has_table_privilege(
    'anon', 'public.audit_log', 'TRUNCATE'
  ) OR pg_catalog.has_table_privilege(
    'service_role', 'public.audit_log', 'INSERT'
  ) OR pg_catalog.has_table_privilege(
    'service_role', 'public.audit_log', 'UPDATE'
  ) OR pg_catalog.has_table_privilege(
    'service_role', 'public.audit_log', 'DELETE'
  ) OR pg_catalog.has_table_privilege(
    'service_role', 'public.audit_log', 'TRUNCATE'
  ) THEN
    RAISE EXCEPTION 'Role aplikasi masih memiliki mutation langsung pada audit_log.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class relation
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(relation.relacl, pg_catalog.acldefault('r', relation.relowner))
    ) acl
    WHERE relation.oid = 'public.audit_log'::regclass
      AND acl.grantee = 0
      AND acl.privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
  ) THEN
    RAISE EXCEPTION 'PUBLIC masih memiliki mutation privilege pada audit_log.';
  END IF;

  IF NOT pg_catalog.has_function_privilege(
    'app_audit_writer', v_writer_function, 'EXECUTE'
  ) OR pg_catalog.has_function_privilege(
    'authenticated', v_writer_function, 'EXECUTE'
  ) OR pg_catalog.has_function_privilege(
    'anon', v_writer_function, 'EXECUTE'
  ) OR pg_catalog.has_function_privilege(
    'service_role', v_writer_function, 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Execute privilege writer audit tidak sesuai kontrak internal.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc proc
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(proc.proacl, pg_catalog.acldefault('f', proc.proowner))
    ) acl
    WHERE proc.oid = v_writer_function
      AND acl.grantee = 0
      AND acl.privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PUBLIC masih dapat mengeksekusi writer audit.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies policy
    WHERE policy.schemaname = 'public'
      AND policy.tablename = 'audit_log'
      AND policy.policyname = 'insert_internal_writer'
      AND policy.cmd = 'INSERT'
      AND 'app_audit_writer' = ANY(policy.roles)
  ) THEN
    RAISE EXCEPTION 'Policy insert_internal_writer tidak ditemukan.';
  END IF;
END;
$audit_writer_state_test$;

CREATE TEMP TABLE p0_security_test_ids (
  admin_user_id uuid,
  created_mitra_id uuid
) ON COMMIT DROP;

CREATE TEMP TABLE p0_security_test_roles (
  role_name text PRIMARY KEY,
  user_id uuid NOT NULL
) ON COMMIT DROP;

INSERT INTO p0_security_test_roles (role_name, user_id)
SELECT DISTINCT ON (role) role, id
FROM public.users
WHERE role IN ('owner', 'super_admin', 'admin_operasional', 'admin_keuangan')
ORDER BY role, created_at;

INSERT INTO p0_security_test_ids (admin_user_id)
SELECT user_id
FROM p0_security_test_roles
WHERE role_name = 'admin_operasional';

DO $fixture_test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM p0_security_test_ids WHERE admin_user_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Fixture Admin Operasional belum tersedia di staging.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM p0_security_test_roles
    WHERE role_name IN ('owner', 'super_admin')
  ) THEN
    RAISE EXCEPTION 'Fixture Owner atau Super Admin belum tersedia di staging.';
  END IF;
END;
$fixture_test$;

GRANT SELECT, UPDATE ON p0_security_test_ids TO authenticated;
GRANT SELECT ON p0_security_test_roles TO authenticated;
GRANT SELECT ON p0_security_target_tables TO authenticated, anon;

-- Create one known sentinel through the real controlled path. It also proves
-- that the dedicated audit writer still works for a business RPC.
SELECT set_config('request.jwt.claim.sub', admin_user_id::text, true)
FROM p0_security_test_ids;
SET LOCAL ROLE authenticated;

DO $create_sentinel$
DECLARE
  v_mitra public.master_mitra;
  v_code text := 'QA-SEC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
BEGIN
  SELECT * INTO v_mitra
  FROM public.save_master_mitra(
    NULL,
    v_code,
    'Mitra Uji Security Rollback',
    NULL,
    NULL,
    NULL,
    'eksternal',
    0,
    0,
    0,
    CURRENT_DATE,
    'Uji audit append-only dalam transaction rollback'
  );

  UPDATE p0_security_test_ids SET created_mitra_id = v_mitra.id;
END;
$create_sentinel$;

RESET ROLE;

DO $controlled_audit_assertion$
DECLARE
  v_count bigint;
BEGIN
  SELECT count(*)
  INTO v_count
  FROM public.audit_log audit
  WHERE audit.entity_type = 'master_mitra'
    AND audit.entity_id = (
      SELECT created_mitra_id FROM p0_security_test_ids LIMIT 1
    );

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'RPC terkontrol menghasilkan % audit row, seharusnya tepat 1.', v_count;
  END IF;
END;
$controlled_audit_assertion$;

-- A valid JWT without a public.users profile must not see the sentinel or any
-- row from the target tables.
SELECT set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
SET LOCAL ROLE authenticated;

DO $no_profile_test$
DECLARE
  v_table text;
  v_count bigint;
BEGIN
  FOR v_table IN SELECT table_name FROM p0_security_target_tables
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
    IF v_count <> 0 THEN
      RAISE EXCEPTION 'Akun tanpa profil dapat membaca %.% baris.', v_table, v_count;
    END IF;
  END LOOP;

  SELECT count(*) INTO v_count
  FROM public.master_mitra
  WHERE id = (SELECT created_mitra_id FROM p0_security_test_ids LIMIT 1);
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Akun tanpa profil dapat membaca sentinel Mitra.';
  END IF;
END;
$no_profile_test$;

RESET ROLE;

-- Anonymous callers must receive no rows. A missing table grant is also a
-- valid denial, so insufficient_privilege is accepted per table.
SELECT set_config('request.jwt.claim.sub', '', true);
SET LOCAL ROLE anon;

DO $anon_test$
DECLARE
  v_table text;
  v_count bigint;
BEGIN
  FOR v_table IN SELECT table_name FROM p0_security_target_tables
  LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I', v_table) INTO v_count;
      IF v_count <> 0 THEN
        RAISE EXCEPTION 'Anon dapat membaca %.% baris.', v_table, v_count;
      END IF;
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;
  END LOOP;
END;
$anon_test$;

RESET ROLE;

-- Every recognized role present in staging must still see the sentinel.
SET LOCAL ROLE authenticated;

DO $recognized_role_test$
DECLARE
  v_role record;
  v_count bigint;
BEGIN
  FOR v_role IN SELECT role_name, user_id FROM p0_security_test_roles
  LOOP
    PERFORM set_config('request.jwt.claim.sub', v_role.user_id::text, true);
    SELECT count(*) INTO v_count
    FROM public.master_mitra
    WHERE id = (SELECT created_mitra_id FROM p0_security_test_ids LIMIT 1);

    IF v_count <> 1 THEN
      RAISE EXCEPTION 'Role % tidak dapat membaca sentinel operasional.', v_role.role_name;
    END IF;
  END LOOP;
END;
$recognized_role_test$;

RESET ROLE;

-- Temporarily grant a test path inside this rollback-only transaction. This
-- ensures the following denials are produced by the triggers, not merely ACL.
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON public.audit_log TO authenticated;
CREATE POLICY qa_audit_select ON public.audit_log
  FOR SELECT TO authenticated USING (true);
CREATE POLICY qa_audit_insert ON public.audit_log
  FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY qa_audit_update ON public.audit_log
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY qa_audit_delete ON public.audit_log
  FOR DELETE TO authenticated USING (true);

SELECT set_config('request.jwt.claim.sub', admin_user_id::text, true)
FROM p0_security_test_ids;
SET LOCAL ROLE authenticated;

DO $audit_denial_test$
BEGIN
  BEGIN
    PERFORM public.write_audit_log(
      'security_test', gen_random_uuid(), 'create', NULL, '{}'::jsonb,
      'Pemanggilan langsung harus ditolak', NULL
    );
    RAISE EXCEPTION 'direct_audit_function_was_not_denied';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.audit_log (actor_user_id, actor_role, entity_type, action)
    VALUES (auth.uid(), 'admin_operasional', 'security_test', 'create');
    RAISE EXCEPTION 'direct_audit_insert_was_not_denied';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    UPDATE public.audit_log SET alasan = 'tamper-test' WHERE false;
    RAISE EXCEPTION 'direct_audit_update_was_not_denied';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    DELETE FROM public.audit_log WHERE false;
    RAISE EXCEPTION 'direct_audit_delete_was_not_denied';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    TRUNCATE TABLE public.audit_log;
    RAISE EXCEPTION 'direct_audit_truncate_was_not_denied';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END;
$audit_denial_test$;

ROLLBACK;
