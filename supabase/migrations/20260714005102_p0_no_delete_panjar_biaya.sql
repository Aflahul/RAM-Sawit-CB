-- P0-0 security hardening: stop physical delete for panjar mitra and biaya.
-- Non-destructive: only adds cancellation metadata, relaxes status checks to
-- include dibatalkan, and revokes DELETE privileges from authenticated clients.

BEGIN;

-- ---------------------------------------------------------------------------
-- Panjar mitra: legacy MVP table, keep existing data and add cancel metadata.
-- ---------------------------------------------------------------------------

ALTER TABLE IF EXISTS public.panjar_mitra
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'belum_lunas',
  ADD COLUMN IF NOT EXISTS alasan_batal text,
  ADD COLUMN IF NOT EXISTS dibatalkan_at timestamptz,
  ADD COLUMN IF NOT EXISTS dibatalkan_by uuid REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT NOW();

DO $$
DECLARE
  c record;
BEGIN
  IF to_regclass('public.panjar_mitra') IS NOT NULL THEN
    UPDATE public.panjar_mitra
    SET status = 'belum_lunas'
    WHERE status IS NULL;

    FOR c IN
      SELECT conname
      FROM pg_constraint
      WHERE conrelid = to_regclass('public.panjar_mitra')
        AND contype = 'c'
        AND pg_get_constraintdef(oid) ILIKE '%status%'
    LOOP
      EXECUTE format('ALTER TABLE public.panjar_mitra DROP CONSTRAINT %I', c.conname);
    END LOOP;

    ALTER TABLE public.panjar_mitra
      ADD CONSTRAINT panjar_mitra_status_check
      CHECK (status IN ('belum_lunas', 'lunas', 'dibatalkan'));

    ALTER TABLE public.panjar_mitra ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "Authenticated full access" ON public.panjar_mitra;
    DROP POLICY IF EXISTS "read_authenticated" ON public.panjar_mitra;
    DROP POLICY IF EXISTS "write_finance" ON public.panjar_mitra;
    DROP POLICY IF EXISTS "insert_finance" ON public.panjar_mitra;
    DROP POLICY IF EXISTS "update_finance" ON public.panjar_mitra;
    DROP POLICY IF EXISTS "delete_finance" ON public.panjar_mitra;

    CREATE POLICY "read_authenticated"
    ON public.panjar_mitra
    FOR SELECT TO authenticated
    USING (true);

    CREATE POLICY "insert_finance"
    ON public.panjar_mitra
    FOR INSERT TO authenticated
    WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

    CREATE POLICY "update_finance"
    ON public.panjar_mitra
    FOR UPDATE TO authenticated
    USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
    WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

    GRANT SELECT, INSERT, UPDATE ON public.panjar_mitra TO authenticated;
    REVOKE DELETE ON public.panjar_mitra FROM authenticated;
    REVOKE DELETE ON public.panjar_mitra FROM anon;

    DROP TRIGGER IF EXISTS set_updated_at ON public.panjar_mitra;
    CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON public.panjar_mitra
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Biaya operasional: cancel with status instead of deleting rows.
-- ---------------------------------------------------------------------------

ALTER TABLE IF EXISTS public.biaya_operasional
  ADD COLUMN IF NOT EXISTS alasan_batal text,
  ADD COLUMN IF NOT EXISTS dibatalkan_at timestamptz,
  ADD COLUMN IF NOT EXISTS dibatalkan_by uuid REFERENCES public.users(id);

DO $$
DECLARE
  c record;
BEGIN
  IF to_regclass('public.biaya_operasional') IS NOT NULL THEN
    UPDATE public.biaya_operasional
    SET status = 'aktif'
    WHERE status IS NULL;

    FOR c IN
      SELECT conname
      FROM pg_constraint
      WHERE conrelid = to_regclass('public.biaya_operasional')
        AND contype = 'c'
        AND pg_get_constraintdef(oid) ILIKE '%status%'
    LOOP
      EXECUTE format('ALTER TABLE public.biaya_operasional DROP CONSTRAINT %I', c.conname);
    END LOOP;

    ALTER TABLE public.biaya_operasional
      ADD CONSTRAINT biaya_operasional_status_check
      CHECK (status IN ('aktif', 'dibatalkan', 'reversal'));

    DROP POLICY IF EXISTS "write_finance" ON public.biaya_operasional;
    DROP POLICY IF EXISTS "insert_finance" ON public.biaya_operasional;
    DROP POLICY IF EXISTS "update_finance" ON public.biaya_operasional;
    DROP POLICY IF EXISTS "delete_finance" ON public.biaya_operasional;

    CREATE POLICY "insert_finance"
    ON public.biaya_operasional
    FOR INSERT TO authenticated
    WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));

    CREATE POLICY "update_finance"
    ON public.biaya_operasional
    FOR UPDATE TO authenticated
    USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']))
    WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));

    GRANT SELECT, INSERT, UPDATE ON public.biaya_operasional TO authenticated;
    REVOKE DELETE ON public.biaya_operasional FROM authenticated;
    REVOKE DELETE ON public.biaya_operasional FROM anon;
  END IF;
END;
$$;

COMMIT;
