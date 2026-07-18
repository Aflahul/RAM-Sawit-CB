-- TASK-SEC-001 & TASK-SEC-003: Revoke direct API mutations for financial data
-- and harden RPCs

-- 1. Revoke INSERT, UPDATE, DELETE on financial tables from direct API
REVOKE INSERT, UPDATE, DELETE ON TABLE public.transaksi_mitra FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.fee_owner_mitra_history FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.pembayaran_mitra_kwitansi FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.pembayaran_mitra_kwitansi_item FROM authenticated, anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.pembayaran_mitra_kwitansi_mitra FROM authenticated, anon, PUBLIC;

-- 2. Strictly forbid DELETE and TRUNCATE on all ledger/history tables
REVOKE DELETE, TRUNCATE ON TABLE public.transaksi_mitra FROM authenticated, anon, PUBLIC;
REVOKE DELETE, TRUNCATE ON TABLE public.fee_owner_mitra_history FROM authenticated, anon, PUBLIC;
REVOKE DELETE, TRUNCATE ON TABLE public.kas_ledger FROM authenticated, anon, PUBLIC;
REVOKE DELETE, TRUNCATE ON TABLE public.hutang_ledger FROM authenticated, anon, PUBLIC;
REVOKE DELETE, TRUNCATE ON TABLE public.panjar_mitra FROM authenticated, anon, PUBLIC;
REVOKE DELETE, TRUNCATE ON TABLE public.pembayaran_pabrik_batch FROM authenticated, anon, PUBLIC;
REVOKE DELETE, TRUNCATE ON TABLE public.pembayaran_pabrik_item FROM authenticated, anon, PUBLIC;
REVOKE DELETE, TRUNCATE ON TABLE public.stok_tbs_lokal_ledger FROM authenticated, anon, PUBLIC;
REVOKE DELETE, TRUNCATE ON TABLE public.biaya_operasional FROM authenticated, anon, PUBLIC;

-- 3. Revoke EXECUTE on sensitive RPCs from PUBLIC/anon
REVOKE ALL ON FUNCTION public.save_transaksi_mitra_v2 FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_transaksi_mitra_v2 TO authenticated;

-- Apply to existing mutation RPCs that might not have been locked
DO $$
DECLARE
  v_rpc text;
  v_rpcs text[] := ARRAY[
    'update_transaksi_mitra_controlled',
    'cancel_transaksi_mitra_controlled',
    'create_pembayaran_mitra_kwitansi',
    'cancel_pembayaran_mitra_kwitansi',
    'create_pembayaran_pabrik_batch',
    'cancel_pembayaran_pabrik_batch',
    'bayar_tagihan_sopir_cb',
    'cancel_pembayaran_dana_trip',
    'create_kas_mutasi',
    'cancel_kas_mutasi_manual',
    'create_piutang_request',
    'review_piutang_request',
    'disburse_piutang_document',
    'record_piutang_repayment',
    'cancel_piutang_document',
    'cancel_piutang_repayment',
    'save_master_mitra',
    'set_master_mitra_active',
    'save_pabrik_master',
    'set_pabrik_master_active',
    'set_harga_tbs_lokal',
    'save_sopir_armada',
    'set_sopir_armada_active'
  ];
BEGIN
  FOR v_rpc IN SELECT oid::regprocedure::text FROM pg_proc WHERE proname = ANY(v_rpcs) LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon;', v_rpc);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated;', v_rpc);
  END LOOP;
END $$;
