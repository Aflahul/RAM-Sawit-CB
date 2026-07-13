-- Sawit CB - tighten policies for kwitansi payment status MVP
-- Keeps the new payment tables readable by authenticated users while avoiding
-- permissive SELECT overlap from FOR ALL policies.

BEGIN;

DROP POLICY IF EXISTS "write_finance" ON public.pembayaran_mitra_kwitansi;
DROP POLICY IF EXISTS "insert_finance" ON public.pembayaran_mitra_kwitansi;
DROP POLICY IF EXISTS "update_finance" ON public.pembayaran_mitra_kwitansi;
DROP POLICY IF EXISTS "delete_finance" ON public.pembayaran_mitra_kwitansi;

CREATE POLICY "insert_finance"
ON public.pembayaran_mitra_kwitansi
FOR INSERT TO authenticated
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

CREATE POLICY "update_finance"
ON public.pembayaran_mitra_kwitansi
FOR UPDATE TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

CREATE POLICY "delete_finance"
ON public.pembayaran_mitra_kwitansi
FOR DELETE TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

DROP POLICY IF EXISTS "write_finance" ON public.pembayaran_mitra_kwitansi_item;
DROP POLICY IF EXISTS "insert_finance" ON public.pembayaran_mitra_kwitansi_item;
DROP POLICY IF EXISTS "update_finance" ON public.pembayaran_mitra_kwitansi_item;
DROP POLICY IF EXISTS "delete_finance" ON public.pembayaran_mitra_kwitansi_item;

CREATE POLICY "insert_finance"
ON public.pembayaran_mitra_kwitansi_item
FOR INSERT TO authenticated
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

CREATE POLICY "update_finance"
ON public.pembayaran_mitra_kwitansi_item
FOR UPDATE TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

CREATE POLICY "delete_finance"
ON public.pembayaran_mitra_kwitansi_item
FOR DELETE TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

REVOKE ALL ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text) TO authenticated;

COMMIT;
