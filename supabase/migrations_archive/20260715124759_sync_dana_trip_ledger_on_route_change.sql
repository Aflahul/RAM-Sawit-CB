-- Perubahan mitra/tanggal/sopir dapat mengubah snapshot di BEFORE trigger.
-- AFTER trigger harus ikut berjalan agar tagihan yang belum dibayar sinkron.

BEGIN;

DROP TRIGGER IF EXISTS sync_tagihan_sopir_cb ON public.transaksi_mitra;
CREATE TRIGGER sync_tagihan_sopir_cb
  AFTER INSERT OR UPDATE OF
    tanggal,
    sopir_id,
    mitra_id,
    status,
    dana_operasional_trip_snapshot,
    total_biaya_sopir_cb_snapshot,
    tagihan_sopir_ledger_id
  ON public.transaksi_mitra
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_tagihan_sopir_cb();

COMMIT;
