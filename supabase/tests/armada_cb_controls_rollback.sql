-- Smoke test kontrol perjalanan, sewa, dan Dana Operasional Trip Armada CB.
-- Seluruh perubahan dibatalkan pada akhir pengujian.
BEGIN;

CREATE TEMP TABLE armada_cb_test_ids ON COMMIT DROP AS
SELECT
  (SELECT id FROM public.users WHERE role IN ('owner', 'super_admin') ORDER BY role = 'super_admin', created_at LIMIT 1) actor_id,
  (
    SELECT transaction.id
    FROM public.transaksi_mitra transaction
    WHERE transaction.status = 'aktif'
      AND transaction.menggunakan_armada_cb_snapshot = true
      AND transaction.armada_cb_perlu_review = true
      AND transaction.biaya_sopir_dibayar_at IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.pembayaran_mitra_kwitansi_item item
        JOIN public.pembayaran_mitra_kwitansi payment ON payment.id = item.pembayaran_id
        WHERE item.transaksi_mitra_id = transaction.id
          AND payment.status <> 'dibatalkan'
      )
    LIMIT 1
  ) transaction_id;

SELECT set_config('request.jwt.claim.sub', actor_id::text, true)
FROM armada_cb_test_ids;
GRANT SELECT ON armada_cb_test_ids TO authenticated;
SET LOCAL ROLE authenticated;

DO $test$
DECLARE
  v_row public.transaksi_mitra;
BEGIN
  IF EXISTS (
    SELECT 1 FROM armada_cb_test_ids
    WHERE actor_id IS NULL OR transaction_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Data uji Armada CB belum tersedia.';
  END IF;

  SELECT * INTO v_row
  FROM public.update_transaksi_mitra_controlled(
    (SELECT transaction_id FROM armada_cb_test_ids),
    jsonb_build_object(
      'kenakan_sewa_armada_cb', false,
      'catat_dana_operasional_trip', false,
      'alasan_tanpa_sewa_armada_cb', 'Uji tanpa sewa rollback',
      'alasan_tanpa_dana_operasional_trip', 'Uji tanpa Dana rollback'
    ),
    'Uji kontrol Armada CB tanpa sewa dan Dana'
  );

  IF NOT v_row.menggunakan_armada_cb_snapshot
     OR v_row.kenakan_sewa_armada_cb
     OR v_row.catat_dana_operasional_trip
     OR v_row.pakai_sewa_armada_bl
     OR v_row.armada_cb_perlu_review
     OR COALESCE(v_row.biaya_sewa_armada_total, 0) <> 0
     OR COALESCE(v_row.dana_operasional_trip_snapshot, 0) <> 0 THEN
    RAISE EXCEPTION 'Kontrol Armada CB saat dimatikan tidak konsisten.';
  END IF;

  SELECT * INTO v_row
  FROM public.update_transaksi_mitra_controlled(
    (SELECT transaction_id FROM armada_cb_test_ids),
    jsonb_build_object(
      'kenakan_sewa_armada_cb', true,
      'catat_dana_operasional_trip', true,
      'alasan_tanpa_sewa_armada_cb', null,
      'alasan_tanpa_dana_operasional_trip', null
    ),
    'Uji kontrol Armada CB dengan sewa dan Dana'
  );

  IF NOT v_row.menggunakan_armada_cb_snapshot
     OR NOT v_row.kenakan_sewa_armada_cb
     OR NOT v_row.catat_dana_operasional_trip
     OR NOT v_row.pakai_sewa_armada_bl THEN
    RAISE EXCEPTION 'Kontrol Armada CB saat dinyalakan tidak konsisten.';
  END IF;

  RAISE NOTICE 'armada_cb_controls_ok=%', v_row.id;
END;
$test$;

ROLLBACK;
