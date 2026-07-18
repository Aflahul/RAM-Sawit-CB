-- Sawit CB - Riwayat pengiriman mitra MVP
-- Tambah status dan metadata koreksi untuk edit/batal tanpa delete fisik.

BEGIN;

ALTER TABLE IF EXISTS public.transaksi_mitra
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'aktif',
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_by uuid REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS alasan_edit text,
  ADD COLUMN IF NOT EXISTS dibatalkan_at timestamptz,
  ADD COLUMN IF NOT EXISTS dibatalkan_by uuid REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS alasan_batal text;

UPDATE public.transaksi_mitra
SET status = 'aktif'
WHERE status IS NULL;

ALTER TABLE IF EXISTS public.transaksi_mitra
  DROP CONSTRAINT IF EXISTS transaksi_mitra_status_check;

ALTER TABLE IF EXISTS public.transaksi_mitra
  ADD CONSTRAINT transaksi_mitra_status_check
  CHECK (status IN ('aktif', 'dibatalkan'));

CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_status_tanggal
ON public.transaksi_mitra (status, tanggal DESC);

CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_dibatalkan
ON public.transaksi_mitra (dibatalkan_at DESC)
WHERE status = 'dibatalkan';

DO $$
BEGIN
  IF to_regprocedure('public.set_updated_at()') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS set_updated_at ON public.transaksi_mitra;
    CREATE TRIGGER set_updated_at
      BEFORE UPDATE ON public.transaksi_mitra
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

COMMIT;
