-- Deterministic P0 release-gate test.
-- Uses only synthetic fixed fixtures and rolls back every change.

BEGIN;

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous
)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'qa-admin@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, false, false),
  ('10000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'qa-owner@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, false, false),
  ('10000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'qa-super@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, false, false);

INSERT INTO public.users (id, nama, username, role)
VALUES
  ('10000000-0000-0000-0000-000000000001', 'QA Admin', 'qa_admin', 'admin_operasional'),
  ('10000000-0000-0000-0000-000000000002', 'QA Owner', 'qa_owner', 'owner'),
  ('10000000-0000-0000-0000-000000000003', 'QA Super', 'qa_super', 'super_admin');

INSERT INTO public.master_mitra (
  id, nama, kode, alamat, no_hp, fee_per_kg, aktif, tipe_mitra,
  tarif_sewa_angkut_per_kg, dana_operasional_trip
)
VALUES (
  '20000000-0000-0000-0000-000000000001',
  'QA Mitra', 'QA-M01', 'Alamat QA', '0800000000', 100, true, 'eksternal', 50, 100000
);

INSERT INTO public.sopir (
  id, nama, no_hp, mitra_id, plat_nomor, is_armada_cb, aktif
)
VALUES (
  '30000000-0000-0000-0000-000000000001',
  'QA Sopir', '0811111111', '20000000-0000-0000-0000-000000000001',
  'BM 1000 QA', false, true
);

INSERT INTO public.harga_tbs (id, tanggal, harga_per_kg, set_oleh)
VALUES (
  '40000000-0000-0000-0000-000000000001',
  DATE '2026-01-01', 3000, '10000000-0000-0000-0000-000000000002'
);

DO $assert_schema$
DECLARE
  v_default text;
  v_sensitive_columns integer;
BEGIN
  SELECT column_default
  INTO v_default
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'role';

  IF v_default IS NOT NULL THEN
    RAISE EXCEPTION 'users.role masih memiliki default: %', v_default;
  END IF;

  SELECT count(*)
  INTO v_sensitive_columns
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name IN ('v_master_mitra_operasional', 'v_transaksi_mitra_operasional')
    AND column_name IN (
      'fee_per_kg', 'fee_owner_per_kg', 'total_fee_owner',
      'harga_pabrik_per_kg', 'tarif_sewa_angkut_per_kg',
      'tarif_sewa_angkut_per_kg_snapshot', 'biaya_sewa_armada_total',
      'dana_operasional_trip', 'dana_operasional_trip_snapshot'
    );

  IF v_sensitive_columns <> 0 THEN
    RAISE EXCEPTION 'DTO operasional masih mengekspos % kolom sensitif.', v_sensitive_columns;
  END IF;

  IF has_function_privilege('authenticated', 'public.save_transaksi_mitra_v2(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.update_transaksi_mitra_controlled(uuid,jsonb,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'RPC legacy finansial penuh masih dapat dipanggil authenticated.';
  END IF;

  IF NOT has_function_privilege('authenticated', 'public.save_transaksi_mitra_operational(jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.update_transaksi_mitra_operational(uuid,jsonb,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'RPC operasional belum diberikan ke authenticated.';
  END IF;

  IF has_table_privilege('authenticated', 'public.audit_log', 'INSERT')
     OR has_table_privilege('authenticated', 'public.audit_log', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.audit_log', 'DELETE')
     OR has_table_privilege('authenticated', 'public.audit_log', 'TRUNCATE') THEN
    RAISE EXCEPTION 'authenticated masih dapat memutasi audit_log.';
  END IF;
END;
$assert_schema$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

DO $admin_tests$
DECLARE
  v_doc public.piutang_dokumen%ROWTYPE;
  v_transaction_id uuid;
  v_count integer;
BEGIN
  SELECT *
  INTO v_doc
  FROM public.create_piutang_request(
    'karyawan', 100000, 'Fixture maker-checker', 'potong_gaji',
    DATE '2026-01-02', DATE '2026-02-02', NULL, NULL, NULL,
    'Karyawan QA', 'Fixture deterministik'
  );

  IF v_doc.status <> 'menunggu_persetujuan'
     OR v_doc.diajukan_oleh <> auth.uid()
     OR v_doc.disetujui_oleh IS NOT NULL THEN
    RAISE EXCEPTION 'Pengajuan Admin tidak masuk maker-checker.';
  END IF;

  BEGIN
    PERFORM public.review_piutang_request(v_doc.id, 'setujui', 'self approval', NULL);
    RAISE EXCEPTION 'self_approval_was_not_denied';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM public.save_transaksi_mitra_operational(jsonb_build_object(
      'tanggal', '2026-01-02',
      'sopir_id', '30000000-0000-0000-0000-000000000001',
      'mitra_id', '20000000-0000-0000-0000-000000000001',
      'plat_nomor', 'BM 1000 QA',
      'sopir_default_id', '30000000-0000-0000-0000-000000000001',
      'sopir_default_nama', 'QA Sopir',
      'sopir_aktual_id', '30000000-0000-0000-0000-000000000001',
      'sopir_aktual_nama', 'QA Sopir',
      'sopir_aktual_source', 'master',
      'berat_netto_pabrik_kg', 1000,
      'potongan_pabrik_kg', 100,
      'menggunakan_armada_cb_snapshot', false,
      'kenakan_sewa_armada_cb', false,
      'catat_dana_operasional_trip', false,
      'fee_owner_per_kg', 999999
    ));
    RAISE EXCEPTION 'malicious_create_payload_was_not_denied';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  SELECT public.save_transaksi_mitra_operational(jsonb_build_object(
    'tanggal', '2026-01-02',
    'sopir_id', '30000000-0000-0000-0000-000000000001',
    'mitra_id', '20000000-0000-0000-0000-000000000001',
    'plat_nomor', 'BM 1000 QA',
    'sopir_default_id', '30000000-0000-0000-0000-000000000001',
    'sopir_default_nama', 'QA Sopir',
    'sopir_aktual_id', '30000000-0000-0000-0000-000000000001',
    'sopir_aktual_nama', 'QA Sopir',
    'sopir_aktual_source', 'master',
    'sopir_diganti_dari_default', false,
    'berat_netto_pabrik_kg', 1000,
    'potongan_pabrik_kg', 100,
    'menggunakan_armada_cb_snapshot', false,
    'kenakan_sewa_armada_cb', false,
    'catat_dana_operasional_trip', false
  )) INTO v_transaction_id;

  IF v_transaction_id IS NULL THEN
    RAISE EXCEPTION 'RPC operasional tidak mengembalikan id.';
  END IF;

  SELECT count(*)
  INTO v_count
  FROM public.v_transaksi_mitra_operasional
  WHERE id = v_transaction_id;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Admin tidak dapat membaca DTO transaksi yang dibuat.';
  END IF;

  BEGIN
    PERFORM public.update_transaksi_mitra_operational(
      v_transaction_id,
      jsonb_build_object('total_kotor', 1),
      'Payload manipulatif'
    );
    RAISE EXCEPTION 'malicious_update_payload_was_not_denied';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  PERFORM public.update_transaksi_mitra_operational(
    v_transaction_id,
    jsonb_build_object(
      'berat_netto_pabrik_kg', 1100,
      'potongan_pabrik_kg', 100
    ),
    'Koreksi berat fixture deterministik'
  );

  PERFORM set_config('qa.transaction_id', v_transaction_id::text, true);
  PERFORM set_config('qa.document_id', v_doc.id::text, true);
END;
$admin_tests$;

SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);

DO $owner_review$
DECLARE
  v_doc public.piutang_dokumen%ROWTYPE;
BEGIN
  SELECT *
  INTO v_doc
  FROM public.review_piutang_request(
    current_setting('qa.document_id')::uuid,
    'setujui',
    'Disetujui fixture Owner',
    NULL
  );

  IF v_doc.status <> 'disetujui'
     OR v_doc.disetujui_oleh <> auth.uid()
     OR v_doc.disetujui_oleh = v_doc.diajukan_oleh THEN
    RAISE EXCEPTION 'Review dua identitas tidak menghasilkan status yang benar.';
  END IF;
END;
$owner_review$;

RESET ROLE;

DO $server_snapshot_assertions$
DECLARE
  v_row public.transaksi_mitra%ROWTYPE;
  v_audit_count integer;
BEGIN
  SELECT *
  INTO v_row
  FROM public.transaksi_mitra
  WHERE id = current_setting('qa.transaction_id')::uuid;

  IF v_row.berat_dibayar_kg <> 1000
     OR v_row.harga_pabrik_per_kg <> 3000
     OR v_row.fee_owner_per_kg <> 100
     OR v_row.harga_bersih_per_kg <> 2900
     OR v_row.total_kotor <> 3000000
     OR v_row.total_fee_owner <> 100000
     OR v_row.total_nilai_bersih <> 2900000 THEN
    RAISE EXCEPTION 'Snapshot server-authoritative salah: %', row_to_json(v_row);
  END IF;

  SELECT count(*)
  INTO v_audit_count
  FROM public.audit_log
  WHERE entity_type = 'piutang_dokumen'
    AND entity_id = current_setting('qa.document_id')::uuid
    AND action IN ('create_request', 'setujui');

  IF v_audit_count <> 2 THEN
    RAISE EXCEPTION 'Maker-checker seharusnya menghasilkan tepat dua audit event, aktual %.', v_audit_count;
  END IF;

  BEGIN
    UPDATE public.piutang_dokumen
    SET status = 'disetujui',
        disetujui_oleh = diajukan_oleh,
        disetujui_at = now()
    WHERE id = current_setting('qa.document_id')::uuid;
    RAISE EXCEPTION 'database_self_approval_was_not_denied';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END;
$server_snapshot_assertions$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000099', true);

DO $fail_closed_actor$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.v_master_mitra_operasional;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Actor tanpa profile dapat membaca DTO operasional.';
  END IF;

  BEGIN
    PERFORM public.save_transaksi_mitra_operational('{}'::jsonb);
    RAISE EXCEPTION 'no_profile_rpc_was_not_denied';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END;
$fail_closed_actor$;

RESET ROLE;
ROLLBACK;
