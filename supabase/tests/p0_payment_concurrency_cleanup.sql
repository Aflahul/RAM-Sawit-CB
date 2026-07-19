-- Cleanup for the committed synthetic payment concurrency fixture.

BEGIN;

DELETE FROM public.pembayaran_mitra_kwitansi_item
WHERE master_mitra_id = '21000000-0000-4000-8000-000000000001';

DELETE FROM public.pembayaran_mitra_kwitansi_mitra
WHERE master_mitra_id = '21000000-0000-4000-8000-000000000001';

UPDATE public.panjar_mitra
SET pembayaran_mitra_kwitansi_id = NULL,
    status = 'belum_lunas',
    lunas_at = NULL
WHERE pembayaran_mitra_kwitansi_id IN (
  SELECT id FROM public.pembayaran_mitra_kwitansi
  WHERE master_mitra_id = '21000000-0000-4000-8000-000000000001'
);

UPDATE public.pembayaran_mitra_kwitansi
SET kas_ledger_id = NULL,
    reversal_kas_ledger_id = NULL,
    rekening_kas_id = NULL
WHERE master_mitra_id = '21000000-0000-4000-8000-000000000001';

DELETE FROM public.kas_ledger
WHERE created_by IN (
  '11000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000002'
);

DELETE FROM public.pembayaran_mitra_kwitansi
WHERE master_mitra_id = '21000000-0000-4000-8000-000000000001';

DELETE FROM public.transaksi_mitra
WHERE mitra_id = '21000000-0000-4000-8000-000000000001';

DELETE FROM public.rekening_kas
WHERE created_by IN (
  '11000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000002'
)
AND NOT EXISTS (
  SELECT 1 FROM public.kas_ledger WHERE rekening_kas_id = rekening_kas.id
);

DELETE FROM public.harga_tbs
WHERE id = '41000000-0000-0000-0000-000000000001';

DELETE FROM public.sopir
WHERE id = '31000000-0000-0000-0000-000000000001';

DELETE FROM public.master_mitra
WHERE id = '21000000-0000-4000-8000-000000000001';

DELETE FROM public.users
WHERE id IN (
  '11000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000002'
);

DELETE FROM auth.users
WHERE id IN (
  '11000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000002'
);

COMMIT;
