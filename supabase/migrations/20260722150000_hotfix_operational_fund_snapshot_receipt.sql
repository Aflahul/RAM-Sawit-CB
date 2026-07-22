-- S1 hotfix: pastikan checkbox Dana Operasional Trip yang tetap aktif
-- memperbaiki snapshot nol saat transaksi belum dibayar, dan bekukan nominal
-- tersebut pada item kwitansi baru sebagai informasi biaya CB terpisah.

CREATE OR REPLACE FUNCTION public.repair_operational_fund_snapshot_on_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_dana_operasional numeric(15,2) := 0;
BEGIN
  IF COALESCE(NEW.status, 'aktif') = 'aktif'
     AND COALESCE(NEW.menggunakan_armada_cb_snapshot, false)
     AND COALESCE(NEW.catat_dana_operasional_trip, false)
     AND NEW.biaya_sopir_dibayar_at IS NULL
     AND COALESCE(NEW.dana_operasional_trip_snapshot, 0) <= 0 THEN
    v_dana_operasional := GREATEST(
      COALESCE(
        public.resolve_dana_operasional_trip_mitra(NEW.mitra_id, NEW.tanggal),
        0
      ),
      0
    );

    IF v_dana_operasional > 0 THEN
      NEW.dana_operasional_trip_snapshot := v_dana_operasional;
      NEW.upah_sopir_cb_snapshot := 0;
      NEW.uang_jalan_sopir_cb_snapshot := 0;
      NEW.total_biaya_sopir_cb_snapshot := v_dana_operasional;
      NEW.nominal_perongkosan_snapshot := 0;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.repair_operational_fund_snapshot_on_write() FROM PUBLIC;

DROP TRIGGER IF EXISTS zz_repair_operational_fund_snapshot
ON public.transaksi_mitra;

CREATE TRIGGER zz_repair_operational_fund_snapshot
BEFORE INSERT OR UPDATE OF
  tanggal,
  sopir_id,
  mitra_id,
  catat_dana_operasional_trip,
  dana_operasional_trip_snapshot
ON public.transaksi_mitra
FOR EACH ROW
EXECUTE FUNCTION public.repair_operational_fund_snapshot_on_write();

ALTER TABLE public.pembayaran_mitra_kwitansi_item
  ADD COLUMN IF NOT EXISTS dana_operasional_trip_snapshot numeric(15,2)
  NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.pembayaran_mitra_kwitansi_item'::regclass
      AND conname = 'pembayaran_mitra_item_dana_operasional_nonnegative'
  ) THEN
    ALTER TABLE public.pembayaran_mitra_kwitansi_item
      ADD CONSTRAINT pembayaran_mitra_item_dana_operasional_nonnegative
      CHECK (dana_operasional_trip_snapshot >= 0);
  END IF;
END;
$$;

COMMENT ON COLUMN public.pembayaran_mitra_kwitansi_item.dana_operasional_trip_snapshot IS
  'Snapshot Dana Operasional Trip untuk informasi kwitansi. Dibayar terpisah dan tidak mengurangi nominal hak mitra.';

CREATE OR REPLACE FUNCTION public.snapshot_kwitansi_operational_fund()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_transaksi public.transaksi_mitra%ROWTYPE;
BEGIN
  SELECT *
  INTO v_transaksi
  FROM public.transaksi_mitra
  WHERE id = NEW.transaksi_mitra_id;

  NEW.dana_operasional_trip_snapshot := CASE
    WHEN COALESCE(v_transaksi.menggunakan_armada_cb_snapshot, false)
      AND COALESCE(v_transaksi.catat_dana_operasional_trip, false)
    THEN GREATEST(
      COALESCE(
        NULLIF(v_transaksi.dana_operasional_trip_snapshot, 0),
        v_transaksi.total_biaya_sopir_cb_snapshot,
        0
      ),
      0
    )
    ELSE 0
  END;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.snapshot_kwitansi_operational_fund() FROM PUBLIC;

DROP TRIGGER IF EXISTS zz_snapshot_kwitansi_operational_fund
ON public.pembayaran_mitra_kwitansi_item;

CREATE TRIGGER zz_snapshot_kwitansi_operational_fund
BEFORE INSERT ON public.pembayaran_mitra_kwitansi_item
FOR EACH ROW
EXECUTE FUNCTION public.snapshot_kwitansi_operational_fund();

