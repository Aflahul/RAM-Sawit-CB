-- Sawit CB - MVP klasifikasi mitra eksternal vs unit internal owner
-- Non-destruktif: menambah kolom tipe_mitra di master_mitra.
-- Kode BL/SL dan turunannya ditandai internal_owner karena merupakan timbangan/grup milik owner.

BEGIN;

ALTER TABLE IF EXISTS public.master_mitra
  ADD COLUMN IF NOT EXISTS tipe_mitra text NOT NULL DEFAULT 'eksternal';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'master_mitra_tipe_mitra_check'
      AND conrelid = 'public.master_mitra'::regclass
  ) THEN
    ALTER TABLE public.master_mitra
      ADD CONSTRAINT master_mitra_tipe_mitra_check
      CHECK (tipe_mitra IN ('eksternal', 'internal_owner'));
  END IF;
END $$;

UPDATE public.master_mitra
SET tipe_mitra = 'internal_owner'
WHERE upper(btrim(kode)) IN ('BL', 'SL')
   OR upper(btrim(kode)) LIKE 'BL/%'
   OR upper(btrim(kode)) LIKE 'SL/%';

CREATE INDEX IF NOT EXISTS idx_master_mitra_tipe_mitra
ON public.master_mitra (tipe_mitra);

COMMIT;
