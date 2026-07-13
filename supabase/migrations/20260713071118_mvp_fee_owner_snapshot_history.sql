-- Sawit CB - MVP Fee Owner history + snapshot transaksi mitra
-- Non-destruktif: kolom lama `harga_harian` dan `total_kotor` tetap dipertahankan
-- untuk kompatibilitas MVP yang sudah berjalan.

BEGIN;

CREATE TABLE IF NOT EXISTS public.fee_owner_mitra_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  master_mitra_id uuid NOT NULL REFERENCES public.master_mitra(id),
  fee_per_kg numeric(12,2) NOT NULL DEFAULT 0 CHECK (fee_per_kg >= 0),
  berlaku_mulai date NOT NULL DEFAULT CURRENT_DATE,
  berlaku_sampai date,
  aktif boolean NOT NULL DEFAULT true,
  alasan_perubahan text,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT fee_owner_mitra_history_periode_check CHECK (
    berlaku_sampai IS NULL OR berlaku_sampai > berlaku_mulai
  ),
  CONSTRAINT fee_owner_mitra_history_unique_start UNIQUE (master_mitra_id, berlaku_mulai)
);

CREATE INDEX IF NOT EXISTS idx_fee_owner_mitra_history_mitra_mulai
ON public.fee_owner_mitra_history (master_mitra_id, berlaku_mulai DESC);

ALTER TABLE IF EXISTS public.fee_owner_mitra_history ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'fee_owner_mitra_history'
      AND policyname = 'Authenticated full access'
  ) THEN
    CREATE POLICY "Authenticated full access"
    ON public.fee_owner_mitra_history
    FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);
  END IF;
END $$;

INSERT INTO public.fee_owner_mitra_history (
  master_mitra_id,
  fee_per_kg,
  berlaku_mulai,
  alasan_perubahan
)
SELECT
  id,
  COALESCE(fee_per_kg, 0),
  CURRENT_DATE,
  'Snapshot awal Fee Owner dari master_mitra saat migration MVP'
FROM public.master_mitra
ON CONFLICT (master_mitra_id, berlaku_mulai) DO NOTHING;

ALTER TABLE IF EXISTS public.transaksi_mitra
  ADD COLUMN IF NOT EXISTS harga_pabrik_per_kg numeric(12,2),
  ADD COLUMN IF NOT EXISTS fee_owner_per_kg numeric(12,2),
  ADD COLUMN IF NOT EXISTS harga_bersih_per_kg numeric(12,2),
  ADD COLUMN IF NOT EXISTS total_fee_owner numeric(15,2),
  ADD COLUMN IF NOT EXISTS total_nilai_bersih numeric(15,2),
  ADD COLUMN IF NOT EXISTS fee_owner_history_id uuid REFERENCES public.fee_owner_mitra_history(id);

UPDATE public.transaksi_mitra
SET
  harga_bersih_per_kg = COALESCE(harga_bersih_per_kg, harga_harian),
  total_nilai_bersih = COALESCE(total_nilai_bersih, total_kotor)
WHERE harga_bersih_per_kg IS NULL
   OR total_nilai_bersih IS NULL;

CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_fee_owner_history
ON public.transaksi_mitra (fee_owner_history_id);

COMMIT;
