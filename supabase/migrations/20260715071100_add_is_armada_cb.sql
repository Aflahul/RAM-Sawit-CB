-- Migrasi untuk menambahkan flag is_armada_cb pada tabel sopir
-- Agar Armada CB tidak perlu dibuat sebagai Mitra fiktif.

ALTER TABLE IF EXISTS public.sopir
  ADD COLUMN IF NOT EXISTS is_armada_cb BOOLEAN DEFAULT false;

COMMENT ON COLUMN public.sopir.is_armada_cb IS 'Menandakan apakah armada ini milik internal owner (Armada CB). Jika true, akan dikenakan tarif sewa armada ke mitra.';
