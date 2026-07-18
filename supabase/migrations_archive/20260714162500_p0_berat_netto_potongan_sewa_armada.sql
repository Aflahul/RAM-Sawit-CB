-- Sawit CB - P0: Berat Netto, Potongan Pabrik, Berat Dibayar, dan Sewa Armada BL/SL
--
-- Rumus bisnis:
--   berat_dibayar       = berat_netto_pabrik_kg - potongan_pabrik_kg
--   total_kotor         = berat_dibayar x harga_pabrik_per_kg
--   total_nilai_bersih  = berat_dibayar x (harga_pabrik - fee_owner)
--   total_fee_owner     = berat_dibayar x fee_owner_per_kg
--   biaya_sewa_armada   = berat_netto_pabrik_kg x Rp150   (pakai NETTO, bukan dibayar)
--
-- Keputusan implementasi:
--   - Kolom tonase TIDAK dihapus agar data lama dan RPC lama tidak rusak.
--   - tonase dibaca sebagai berat_netto_pabrik_kg selama masa transisi.
--   - Backfill aman: netto = tonase, potongan = 0, dibayar = tonase, sewa = 0.
--   - Sewa armada berlaku jika mitra transaksi bukan BL/SL tapi armada/sopir dari BL/SL.
--   - Tarif Rp150/kg hardcode sebagai konstanta MVP (TODO: pindah ke tabel tarif).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. transaksi_mitra — tambah kolom berat baru dan sewa armada
-- ---------------------------------------------------------------------------

ALTER TABLE public.transaksi_mitra
  ADD COLUMN IF NOT EXISTS berat_netto_pabrik_kg    numeric(12,2),
  ADD COLUMN IF NOT EXISTS potongan_pabrik_kg        numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS berat_dibayar_kg          numeric(12,2),
  ADD COLUMN IF NOT EXISTS pakai_sewa_armada_bl      boolean       NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS biaya_sewa_armada_per_kg  numeric(10,2),
  ADD COLUMN IF NOT EXISTS biaya_sewa_armada_total   numeric(15,2) NOT NULL DEFAULT 0;

-- Backfill data lama secara aman
UPDATE public.transaksi_mitra
SET
  berat_netto_pabrik_kg  = COALESCE(tonase, 0),
  berat_dibayar_kg       = COALESCE(tonase, 0),
  biaya_sewa_armada_total = 0
WHERE berat_netto_pabrik_kg IS NULL;

-- Constraint integritas berat
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_potongan_tidak_negatif'
      AND conrelid = 'public.transaksi_mitra'::regclass
  ) THEN
    ALTER TABLE public.transaksi_mitra
      ADD CONSTRAINT chk_potongan_tidak_negatif
        CHECK (potongan_pabrik_kg >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_potongan_tidak_melebihi_netto'
      AND conrelid = 'public.transaksi_mitra'::regclass
  ) THEN
    ALTER TABLE public.transaksi_mitra
      ADD CONSTRAINT chk_potongan_tidak_melebihi_netto
        CHECK (
          berat_netto_pabrik_kg IS NULL
          OR potongan_pabrik_kg <= berat_netto_pabrik_kg
        );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_biaya_sewa_armada_tidak_negatif'
      AND conrelid = 'public.transaksi_mitra'::regclass
  ) THEN
    ALTER TABLE public.transaksi_mitra
      ADD CONSTRAINT chk_biaya_sewa_armada_tidak_negatif
        CHECK (biaya_sewa_armada_total >= 0);
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. pembayaran_mitra_kwitansi_item — tambah snapshot berat baru dan sewa armada
-- ---------------------------------------------------------------------------

ALTER TABLE public.pembayaran_mitra_kwitansi_item
  ADD COLUMN IF NOT EXISTS berat_netto_snapshot       numeric(12,2),
  ADD COLUMN IF NOT EXISTS potongan_snapshot           numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS berat_dibayar_snapshot      numeric(12,2),
  ADD COLUMN IF NOT EXISTS pakai_sewa_armada_snapshot  boolean       NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS biaya_sewa_armada_snapshot  numeric(15,2) NOT NULL DEFAULT 0;

-- Backfill snapshot lama: netto = tonase_snapshot, potongan = 0, dibayar = tonase_snapshot
UPDATE public.pembayaran_mitra_kwitansi_item
SET
  berat_netto_snapshot  = COALESCE(tonase_snapshot, 0),
  berat_dibayar_snapshot = COALESCE(tonase_snapshot, 0)
WHERE berat_netto_snapshot IS NULL;

-- ---------------------------------------------------------------------------
-- 3. pembayaran_pabrik_item — tambah snapshot berat baru
-- ---------------------------------------------------------------------------

ALTER TABLE public.pembayaran_pabrik_item
  ADD COLUMN IF NOT EXISTS berat_netto_snapshot   numeric(12,2),
  ADD COLUMN IF NOT EXISTS berat_dibayar_snapshot numeric(12,2);

-- Backfill snapshot lama
UPDATE public.pembayaran_pabrik_item
SET
  berat_netto_snapshot   = COALESCE(tonase_snapshot, 0),
  berat_dibayar_snapshot = COALESCE(tonase_snapshot, 0)
WHERE berat_netto_snapshot IS NULL;

-- ---------------------------------------------------------------------------
-- 4. pembayaran_mitra_kwitansi — tambah total sewa armada di header kwitansi
-- ---------------------------------------------------------------------------

ALTER TABLE public.pembayaran_mitra_kwitansi
  ADD COLUMN IF NOT EXISTS total_sewa_armada numeric(15,2) NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- Indeks ringan untuk query laporan berat (opsional, non-blocking)
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_berat_dibayar
  ON public.transaksi_mitra (berat_dibayar_kg)
  WHERE berat_dibayar_kg IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_pakai_sewa_armada
  ON public.transaksi_mitra (pakai_sewa_armada_bl)
  WHERE pakai_sewa_armada_bl = true;

COMMIT;
