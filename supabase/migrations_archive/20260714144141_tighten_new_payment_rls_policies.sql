-- Sawit CB - rapikan RLS tabel pembayaran baru.
--
-- Advisors menandai policy FOR ALL karena ikut berlaku untuk SELECT.
-- Kita pisahkan read policy dan write policy agar akses baca tidak dobel.

BEGIN;

DROP POLICY IF EXISTS "write_finance" ON public.pembayaran_pabrik_batch;
DROP POLICY IF EXISTS "insert_finance" ON public.pembayaran_pabrik_batch;
CREATE POLICY "insert_finance"
ON public.pembayaran_pabrik_batch
FOR INSERT TO authenticated
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

DROP POLICY IF EXISTS "update_finance" ON public.pembayaran_pabrik_batch;
CREATE POLICY "update_finance"
ON public.pembayaran_pabrik_batch
FOR UPDATE TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

DROP POLICY IF EXISTS "write_finance" ON public.pembayaran_pabrik_item;
DROP POLICY IF EXISTS "insert_finance" ON public.pembayaran_pabrik_item;
CREATE POLICY "insert_finance"
ON public.pembayaran_pabrik_item
FOR INSERT TO authenticated
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

DROP POLICY IF EXISTS "update_finance" ON public.pembayaran_pabrik_item;
CREATE POLICY "update_finance"
ON public.pembayaran_pabrik_item
FOR UPDATE TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

DROP POLICY IF EXISTS "write_finance" ON public.pembayaran_mitra_kwitansi_mitra;
DROP POLICY IF EXISTS "insert_finance" ON public.pembayaran_mitra_kwitansi_mitra;
CREATE POLICY "insert_finance"
ON public.pembayaran_mitra_kwitansi_mitra
FOR INSERT TO authenticated
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

DROP POLICY IF EXISTS "update_finance" ON public.pembayaran_mitra_kwitansi_mitra;
CREATE POLICY "update_finance"
ON public.pembayaran_mitra_kwitansi_mitra
FOR UPDATE TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

COMMIT;
