-- P0 hardening: master verification and payment snapshots must only change
-- through their controlled SECURITY DEFINER RPCs.

DROP POLICY IF EXISTS insert_operations ON public.master_mitra;
DROP POLICY IF EXISTS update_operations ON public.master_mitra;
REVOKE INSERT, UPDATE ON public.master_mitra FROM anon, authenticated;

DROP POLICY IF EXISTS write_operations ON public.sopir;
REVOKE INSERT, UPDATE ON public.sopir FROM anon, authenticated;

DROP POLICY IF EXISTS insert_finance ON public.pembayaran_mitra_kwitansi_item;
DROP POLICY IF EXISTS update_finance ON public.pembayaran_mitra_kwitansi_item;
REVOKE INSERT, UPDATE ON public.pembayaran_mitra_kwitansi_item FROM anon, authenticated;

-- Transaction corrections are handled by update/cancel_transaksi_mitra_controlled.
REVOKE UPDATE ON public.transaksi_mitra FROM anon, authenticated;
