-- Destructive-path smoke test. This file always rolls back and is intended
-- for an explicitly selected staging/linked database.
BEGIN;

CREATE TEMP TABLE p0_test_ids ON COMMIT DROP AS
SELECT
  (SELECT id FROM public.users WHERE role IN ('owner', 'super_admin') ORDER BY role = 'super_admin', created_at LIMIT 1) approver_user_id,
  (SELECT id FROM public.users WHERE role = 'admin_operasional' ORDER BY created_at LIMIT 1) admin_user_id,
  (
    SELECT transaction.id
    FROM public.transaksi_mitra transaction
    WHERE transaction.status = 'aktif'
      AND transaction.biaya_sopir_dibayar_at IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.pembayaran_mitra_kwitansi_item item
        JOIN public.pembayaran_mitra_kwitansi payment ON payment.id = item.pembayaran_id
        WHERE item.transaksi_mitra_id = transaction.id
          AND payment.status <> 'dibatalkan'
      )
    LIMIT 1
  ) unpaid_transaction_id,
  (
    SELECT id
    FROM public.pembayaran_mitra_kwitansi
    WHERE status <> 'dibatalkan'
    ORDER BY created_at DESC
    LIMIT 1
  ) active_payment_id;

SELECT set_config('request.jwt.claim.sub', approver_user_id::text, true)
FROM p0_test_ids;
GRANT SELECT ON p0_test_ids TO authenticated;
SET LOCAL ROLE authenticated;

DO $test$
DECLARE
  v_row public.transaksi_mitra;
  v_payment public.pembayaran_mitra_kwitansi;
BEGIN
  IF EXISTS (
    SELECT 1 FROM p0_test_ids
    WHERE approver_user_id IS NULL OR unpaid_transaction_id IS NULL OR active_payment_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Data uji belum lengkap.';
  END IF;

  SELECT * INTO v_row FROM public.update_transaksi_mitra_controlled(
    (SELECT unpaid_transaction_id FROM p0_test_ids),
    '{}'::jsonb,
    'Uji atomik rollback'
  );
  RAISE NOTICE 'controlled_update_ok=%', v_row.id;

  SELECT * INTO v_payment FROM public.cancel_pembayaran_mitra_kwitansi(
    (SELECT active_payment_id FROM p0_test_ids),
    'Uji reversal rollback'
  );
  RAISE NOTICE 'receipt_reversal_ok=% status=%', v_payment.id, v_payment.status;

  BEGIN
    PERFORM public.cancel_pembayaran_mitra_kwitansi(
      (SELECT active_payment_id FROM p0_test_ids),
      'Uji kedua'
    );
    RAISE EXCEPTION 'idempotency_failed';
  EXCEPTION
    WHEN SQLSTATE '22023' THEN
      RAISE NOTICE 'receipt_idempotency_ok=true';
  END;
END;
$test$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', admin_user_id::text, true)
FROM p0_test_ids;
SET LOCAL ROLE authenticated;

DO $admin_test$
DECLARE
  v_row public.transaksi_mitra;
  v_driver public.sopir;
BEGIN
  IF EXISTS (
    SELECT 1 FROM p0_test_ids
    WHERE admin_user_id IS NULL OR unpaid_transaction_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Data uji Admin belum lengkap.';
  END IF;

  SELECT * INTO v_row FROM public.update_transaksi_mitra_controlled(
    (SELECT unpaid_transaction_id FROM p0_test_ids),
    '{}'::jsonb,
    'Uji akses Admin rollback'
  );
  RAISE NOTICE 'admin_controlled_update_ok=%', v_row.id;

  SELECT * INTO v_driver FROM public.save_sopir_armada(
    NULL,
    'Sopir Uji Rollback',
    NULL,
    NULL,
    'TEST 1607 QA',
    false
  );

  IF v_driver.status_verifikasi <> 'perlu_verifikasi' THEN
    RAISE EXCEPTION 'Master baru Admin tidak masuk antrean verifikasi.';
  END IF;
  RAISE NOTICE 'admin_quick_add_verification_ok=%', v_driver.id;
END;
$admin_test$;

ROLLBACK;
