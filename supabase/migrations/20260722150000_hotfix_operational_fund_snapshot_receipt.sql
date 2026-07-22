-- S1 hotfix keputusan Owner 22 Juli 2026:
-- Dana Operasional Trip dibayar langsung oleh Mitra kepada sopir.
-- Potongan akhir sewa = (berat netto x tarif sewa Mitra/kg) - Dana Operasional.
-- Dana tersebut bukan pengeluaran, utang, atau arus kas CB.

ALTER TABLE public.transaksi_mitra
  ADD COLUMN IF NOT EXISTS dana_operasional_dibayar_mitra boolean;

ALTER TABLE public.transaksi_mitra
  ALTER COLUMN dana_operasional_dibayar_mitra SET DEFAULT true;

COMMENT ON COLUMN public.transaksi_mitra.dana_operasional_dibayar_mitra IS
  'TRUE jika Dana Operasional diserahkan langsung oleh Mitra ke sopir dan mengurangi sewa kotor. NULL mempertahankan skema historis sebelum keputusan Owner.';

-- Hentikan pembuatan tagihan Dana Trip baru. Fungsi lama dipertahankan hanya
-- agar riwayat dan prosedur pembatalan transaksi lama tetap dapat diaudit.
DROP TRIGGER IF EXISTS sync_tagihan_sopir_cb ON public.transaksi_mitra;
REVOKE EXECUTE ON FUNCTION public.bayar_tagihan_sopir_cb(uuid, date, uuid)
  FROM anon, authenticated;

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

CREATE OR REPLACE FUNCTION public.apply_direct_operational_fund_on_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_berat_netto numeric(15,2) := 0;
  v_tarif_sewa numeric(12,2) := 0;
  v_sewa_kotor numeric(15,2) := 0;
  v_dana_operasional numeric(15,2) := 0;
  v_actor uuid := auth.uid();
BEGIN
  IF NOT COALESCE(NEW.menggunakan_armada_cb_snapshot, false)
     OR NOT COALESCE(NEW.kenakan_sewa_armada_cb, NEW.pakai_sewa_armada_bl, false) THEN
    NEW.biaya_sewa_armada_kotor := 0;
    NEW.biaya_sewa_armada_total := 0;
    RETURN NEW;
  END IF;

  v_berat_netto := GREATEST(COALESCE(NEW.berat_netto_pabrik_kg, NEW.tonase, 0), 0);
  v_tarif_sewa := GREATEST(COALESCE(
    NULLIF(NEW.tarif_sewa_angkut_per_kg_snapshot, 0),
    NULLIF(NEW.biaya_sewa_armada_per_kg, 0),
    0
  ), 0);
  v_sewa_kotor := CASE
    WHEN v_berat_netto > 0 AND v_tarif_sewa > 0
      THEN round(v_berat_netto * v_tarif_sewa, 2)
    ELSE GREATEST(COALESCE(NEW.biaya_sewa_armada_kotor, NEW.biaya_sewa_armada_total, 0), 0)
  END;
  v_dana_operasional := CASE
    WHEN COALESCE(NEW.catat_dana_operasional_trip, false)
      THEN GREATEST(COALESCE(
        NULLIF(NEW.dana_operasional_trip_snapshot, 0),
        NULLIF(NEW.total_biaya_sopir_cb_snapshot, 0),
        0
      ), 0)
    ELSE 0
  END;

  NEW.biaya_sewa_armada_kotor := v_sewa_kotor;

  IF NEW.dana_operasional_dibayar_mitra IS TRUE
     AND NEW.biaya_sopir_dibayar_at IS NULL THEN
    NEW.biaya_sewa_armada_total := GREATEST(v_sewa_kotor - v_dana_operasional, 0);

    IF TG_OP = 'UPDATE'
       AND OLD.tagihan_sopir_ledger_id IS NOT NULL THEN
      UPDATE public.hutang_ledger
      SET status = 'dibatalkan',
          alasan_batal = 'Keputusan Owner: Dana Operasional dibayar langsung oleh Mitra ke sopir.',
          dibatalkan_at = now(),
          dibatalkan_by = COALESCE(v_actor, NEW.updated_by, OLD.updated_by, OLD.created_by),
          updated_at = now()
      WHERE id = OLD.tagihan_sopir_ledger_id
        AND status = 'aktif';
    END IF;

    NEW.tagihan_sopir_ledger_id := NULL;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_direct_operational_fund_on_write() FROM PUBLIC;

DROP TRIGGER IF EXISTS zzz_apply_direct_operational_fund
ON public.transaksi_mitra;

CREATE TRIGGER zzz_apply_direct_operational_fund
BEFORE INSERT OR UPDATE OF
  berat_netto_pabrik_kg,
  tonase,
  pakai_sewa_armada_bl,
  menggunakan_armada_cb_snapshot,
  kenakan_sewa_armada_cb,
  catat_dana_operasional_trip,
  biaya_sewa_armada_per_kg,
  tarif_sewa_angkut_per_kg_snapshot,
  biaya_sewa_armada_kotor,
  biaya_sewa_armada_total,
  dana_operasional_trip_snapshot,
  total_biaya_sopir_cb_snapshot,
  dana_operasional_dibayar_mitra
ON public.transaksi_mitra
FOR EACH ROW
EXECUTE FUNCTION public.apply_direct_operational_fund_on_write();

-- Terapkan keputusan baru hanya pada transaksi aktif yang belum masuk
-- kwitansi dan belum pernah dibayar melalui Kas CB. Dokumen lama tidak diubah.
UPDATE public.transaksi_mitra tm
SET dana_operasional_dibayar_mitra = true,
    dana_operasional_trip_snapshot = tm.dana_operasional_trip_snapshot
WHERE COALESCE(tm.status, 'aktif') = 'aktif'
  AND COALESCE(tm.menggunakan_armada_cb_snapshot, false)
  AND COALESCE(tm.catat_dana_operasional_trip, false)
  AND tm.biaya_sopir_dibayar_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.pembayaran_mitra_kwitansi_item item
    JOIN public.pembayaran_mitra_kwitansi payment
      ON payment.id = item.pembayaran_id
    WHERE item.transaksi_mitra_id = tm.id
      AND payment.status <> 'dibatalkan'
  );

ALTER TABLE public.pembayaran_mitra_kwitansi_item
  ADD COLUMN IF NOT EXISTS dana_operasional_trip_snapshot numeric(15,2)
  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dana_operasional_dibayar_mitra_snapshot boolean
  NOT NULL DEFAULT false;

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
  'Snapshot Dana Operasional yang telah dibayar langsung oleh Mitra kepada sopir.';

COMMENT ON COLUMN public.pembayaran_mitra_kwitansi_item.dana_operasional_dibayar_mitra_snapshot IS
  'Snapshot sumber Dana Operasional. FALSE mempertahankan dokumen historis sebelum keputusan Owner.';

ALTER TABLE public.pembayaran_mitra_kwitansi_item
  DROP CONSTRAINT IF EXISTS pembayaran_mitra_item_metode_sewa_check;

ALTER TABLE public.pembayaran_mitra_kwitansi_item
  ADD CONSTRAINT pembayaran_mitra_item_metode_sewa_check
  CHECK (metode_sewa_armada_snapshot IN (
    'tidak_ada',
    'netto_x_tarif',
    'legacy_snapshot',
    'netto_x_tarif_minus_operasional'
  ));

CREATE OR REPLACE FUNCTION public.snapshot_kwitansi_operational_fund()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_transaksi public.transaksi_mitra%ROWTYPE;
  v_dana_operasional numeric(15,2) := 0;
  v_sewa_kotor numeric(15,2) := 0;
BEGIN
  SELECT *
  INTO v_transaksi
  FROM public.transaksi_mitra
  WHERE id = NEW.transaksi_mitra_id;

  IF v_transaksi.id IS NULL THEN
    RAISE EXCEPTION 'Transaksi sumber item kwitansi tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  v_dana_operasional := CASE
    WHEN COALESCE(v_transaksi.menggunakan_armada_cb_snapshot, false)
      AND COALESCE(v_transaksi.catat_dana_operasional_trip, false)
    THEN GREATEST(COALESCE(
      NULLIF(v_transaksi.dana_operasional_trip_snapshot, 0),
      NULLIF(v_transaksi.total_biaya_sopir_cb_snapshot, 0),
      0
    ), 0)
    ELSE 0
  END;

  v_sewa_kotor := CASE
    WHEN COALESCE(NEW.pakai_sewa_armada_snapshot, false)
      THEN GREATEST(COALESCE(
        NULLIF(v_transaksi.biaya_sewa_armada_kotor, 0),
        NULLIF(NEW.biaya_sewa_armada_standar_snapshot, 0),
        NEW.biaya_sewa_armada_snapshot,
        0
      ), 0)
    ELSE 0
  END;

  NEW.dana_operasional_trip_snapshot := v_dana_operasional;
  NEW.dana_operasional_dibayar_mitra_snapshot :=
    COALESCE(v_transaksi.dana_operasional_dibayar_mitra, false);

  IF NEW.dana_operasional_dibayar_mitra_snapshot THEN
    NEW.biaya_sewa_armada_snapshot := GREATEST(v_sewa_kotor - v_dana_operasional, 0);
    NEW.biaya_sewa_armada_standar_snapshot := v_sewa_kotor;
    NEW.selisih_sewa_armada_historis_snapshot := v_dana_operasional;
    NEW.metode_sewa_armada_snapshot := 'netto_x_tarif_minus_operasional';
  END IF;

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
