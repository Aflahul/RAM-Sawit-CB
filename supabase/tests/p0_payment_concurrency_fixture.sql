-- Committed synthetic fixture for the cross-session payment concurrency test.
-- The companion runner always invokes p0_payment_concurrency_cleanup.sql.

BEGIN;

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, is_sso_user, is_anonymous
)
VALUES
  ('11000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'qa-payment-admin@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, false, false),
  ('11000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'qa-payment-owner@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, false, false);

INSERT INTO public.users (id, nama, username, role)
VALUES
  ('11000000-0000-0000-0000-000000000001', 'QA Payment Admin', 'qa_payment_admin', 'admin_operasional'),
  ('11000000-0000-0000-0000-000000000002', 'QA Payment Owner', 'qa_payment_owner', 'owner');

INSERT INTO public.rekening_kas (
  id, nama, tipe, saldo_awal, aktif, is_default, catatan, created_by
)
VALUES (
  '51000000-0000-4000-8000-000000000001',
  'Kas QA Concurrency', 'kas', 0, true, true,
  'Fixture deterministik pembayaran bersamaan',
  '11000000-0000-0000-0000-000000000002'
);

INSERT INTO public.master_mitra (
  id, nama, kode, alamat, no_hp, fee_per_kg, aktif, tipe_mitra,
  tarif_sewa_angkut_per_kg, dana_operasional_trip
)
VALUES (
  '21000000-0000-4000-8000-000000000001',
  'QA Payment Mitra', 'QA-PAY-01', 'Alamat QA Payment', '0800000001',
  100, true, 'eksternal', 50, 100000
);

INSERT INTO public.sopir (
  id, nama, no_hp, mitra_id, plat_nomor, is_armada_cb, aktif
)
VALUES (
  '31000000-0000-0000-0000-000000000001',
  'QA Payment Sopir', '0811111112', '21000000-0000-4000-8000-000000000001',
  'BM 1100 QA', false, true
);

INSERT INTO public.harga_tbs (id, tanggal, harga_per_kg, set_oleh)
VALUES (
  '41000000-0000-0000-0000-000000000001',
  DATE '2026-02-01', 3000, '11000000-0000-0000-0000-000000000002'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000001', true);

SELECT public.save_transaksi_mitra_operational(jsonb_build_object(
  'tanggal', '2026-02-02',
  'sopir_id', '31000000-0000-0000-0000-000000000001',
  'mitra_id', '21000000-0000-4000-8000-000000000001',
  'plat_nomor', 'BM 1100 QA',
  'sopir_default_id', '31000000-0000-0000-0000-000000000001',
  'sopir_default_nama', 'QA Payment Sopir',
  'sopir_aktual_id', '31000000-0000-0000-0000-000000000001',
  'sopir_aktual_nama', 'QA Payment Sopir',
  'sopir_aktual_source', 'master',
  'sopir_diganti_dari_default', false,
  'berat_netto_pabrik_kg', 1000,
  'potongan_pabrik_kg', 100,
  'menggunakan_armada_cb_snapshot', false,
  'kenakan_sewa_armada_cb', false,
  'catat_dana_operasional_trip', false
));

COMMIT;
