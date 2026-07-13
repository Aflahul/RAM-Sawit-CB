-- Sawit CB - MVP sopir aktual untuk transaksi mitra
-- Non-destructive: hanya menambah kolom yang dibutuhkan alur MVP live.

BEGIN;

ALTER TABLE IF EXISTS public.sopir
  ADD COLUMN IF NOT EXISTS plat_nomor varchar(30);

ALTER TABLE IF EXISTS public.transaksi_mitra
  ADD COLUMN IF NOT EXISTS sopir_default_id uuid REFERENCES public.sopir(id),
  ADD COLUMN IF NOT EXISTS sopir_default_nama varchar(100),
  ADD COLUMN IF NOT EXISTS sopir_aktual_id uuid REFERENCES public.sopir(id),
  ADD COLUMN IF NOT EXISTS sopir_aktual_nama varchar(100),
  ADD COLUMN IF NOT EXISTS sopir_aktual_no_hp varchar(30),
  ADD COLUMN IF NOT EXISTS sopir_aktual_source text DEFAULT 'master',
  ADD COLUMN IF NOT EXISTS sopir_diganti_dari_default boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS catatan_sopir text;

UPDATE public.transaksi_mitra tm
SET
  sopir_default_id = COALESCE(tm.sopir_default_id, tm.sopir_id),
  sopir_aktual_id = COALESCE(tm.sopir_aktual_id, tm.sopir_id),
  sopir_default_nama = COALESCE(tm.sopir_default_nama, s.nama),
  sopir_aktual_nama = COALESCE(tm.sopir_aktual_nama, s.nama),
  sopir_aktual_no_hp = COALESCE(tm.sopir_aktual_no_hp, s.no_hp),
  sopir_aktual_source = COALESCE(tm.sopir_aktual_source, 'master'),
  sopir_diganti_dari_default = COALESCE(tm.sopir_diganti_dari_default, false)
FROM public.sopir s
WHERE tm.sopir_id = s.id;

ALTER TABLE IF EXISTS public.transaksi_mitra
  DROP CONSTRAINT IF EXISTS transaksi_mitra_sopir_aktual_source_check;

ALTER TABLE IF EXISTS public.transaksi_mitra
  ADD CONSTRAINT transaksi_mitra_sopir_aktual_source_check
  CHECK (sopir_aktual_source IN ('master', 'manual'));

CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_sopir_aktual
ON public.transaksi_mitra (sopir_aktual_id);

CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_sopir_diganti
ON public.transaksi_mitra (sopir_diganti_dari_default)
WHERE sopir_diganti_dari_default = true;

COMMIT;
