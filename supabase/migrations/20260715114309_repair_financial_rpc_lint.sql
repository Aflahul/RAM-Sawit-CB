-- Perbaiki dua error lint lama pada RPC finansial tanpa mengubah kontrak API.

BEGIN;

ALTER TABLE public.panjar_mitra
  ADD COLUMN IF NOT EXISTS pembayaran_mitra_kwitansi_id uuid
    REFERENCES public.pembayaran_mitra_kwitansi(id);

CREATE INDEX IF NOT EXISTS idx_panjar_mitra_kwitansi
  ON public.panjar_mitra (pembayaran_mitra_kwitansi_id)
  WHERE pembayaran_mitra_kwitansi_id IS NOT NULL;

COMMENT ON COLUMN public.panjar_mitra.pembayaran_mitra_kwitansi_id IS
  'Kwitansi yang menggunakan panjar ini sebagai potongan pembayaran mitra.';

-- Hubungkan panjar lama dari snapshot header yang sudah tersimpan.
UPDATE public.panjar_mitra panjar
SET pembayaran_mitra_kwitansi_id = payment.id,
    lunas_at = COALESCE(panjar.lunas_at, payment.dibayar_at)
FROM public.pembayaran_mitra_kwitansi payment
WHERE panjar.id = ANY(COALESCE(payment.panjar_ids, '{}'::uuid[]))
  AND payment.status <> 'dibatalkan'
  AND panjar.pembayaran_mitra_kwitansi_id IS NULL;

DO $$
DECLARE
  v_factory_definition text;
  v_kwitansi_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.create_pembayaran_pabrik_batch(uuid,date,text,numeric,numeric,numeric,uuid,text,text,uuid[])'::regprocedure
  ) INTO v_factory_definition;

  IF position('min(id)' IN v_factory_definition) = 0 THEN
    RAISE EXCEPTION 'Pola min(id) pada create_pembayaran_pabrik_batch tidak ditemukan.';
  END IF;

  v_factory_definition := replace(
    v_factory_definition,
    'min(id)',
    'min(id::text)::uuid'
  );
  EXECUTE v_factory_definition;

  SELECT pg_get_functiondef(
    'public.create_pembayaran_mitra_kwitansi(uuid,date,date,text,text,uuid[],text)'::regprocedure
  ) INTO v_kwitansi_definition;

  IF position('dilunasi_at = now()' IN v_kwitansi_definition) = 0 THEN
    RAISE EXCEPTION 'Pola dilunasi_at pada create_pembayaran_mitra_kwitansi tidak ditemukan.';
  END IF;

  v_kwitansi_definition := replace(
    v_kwitansi_definition,
    'dilunasi_at = now()',
    'lunas_at = now()'
  );
  EXECUTE v_kwitansi_definition;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pembayaran_pabrik_batch(
  uuid, date, text, numeric, numeric, numeric, uuid, text, text, uuid[]
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pembayaran_pabrik_batch(
  uuid, date, text, numeric, numeric, numeric, uuid, text, text, uuid[]
) TO authenticated;

REVOKE ALL ON FUNCTION public.create_pembayaran_mitra_kwitansi(
  uuid, date, date, text, text, uuid[], text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pembayaran_mitra_kwitansi(
  uuid, date, date, text, text, uuid[], text
) TO authenticated;

COMMIT;
