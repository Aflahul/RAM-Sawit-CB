-- Keputusan Owner 23 Juli 2026:
-- Dana Operasional Armada CB selalu dibayar langsung oleh Mitra kepada sopir
-- sebelum berangkat. Dana ini mengurangi sewa kotor dan bukan biaya/kas keluar CB.

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
  v_kenakan_sewa boolean := false;
  v_has_issued_receipt boolean := false;
  v_actor uuid := auth.uid();
  v_biaya public.biaya_operasional%ROWTYPE;
  v_original_kas public.kas_ledger%ROWTYPE;
  v_kas_id uuid;
  v_reason text := 'Rekonsiliasi keputusan Owner: Dana Operasional dibayar langsung oleh Mitra ke sopir sebelum berangkat.';
BEGIN
  IF TG_OP = 'UPDATE' THEN
    v_actor := COALESCE(v_actor, NEW.updated_by, OLD.updated_by, OLD.created_by);
    SELECT EXISTS (
      SELECT 1
      FROM public.pembayaran_mitra_kwitansi_item item
      JOIN public.pembayaran_mitra_kwitansi payment
        ON payment.id = item.pembayaran_id
      WHERE item.transaksi_mitra_id = OLD.id
        AND payment.status <> 'dibatalkan'
    ) INTO v_has_issued_receipt;
  ELSE
    v_actor := COALESCE(v_actor, NEW.updated_by, NEW.created_by);
  END IF;

  -- Kwitansi yang sudah terbit tetap memakai snapshot-nya. Semua transaksi
  -- aktif lain dengan Armada CB + Dana Operasional mengikuti sumber dana Mitra.
  IF COALESCE(NEW.status, 'aktif') = 'aktif'
     AND COALESCE(NEW.menggunakan_armada_cb_snapshot, false)
     AND COALESCE(NEW.catat_dana_operasional_trip, false)
     AND NOT (
       v_has_issued_receipt
       AND TG_OP = 'UPDATE'
       AND OLD.dana_operasional_dibayar_mitra IS DISTINCT FROM true
     ) THEN
    NEW.dana_operasional_dibayar_mitra := true;
  END IF;

  v_kenakan_sewa := COALESCE(NEW.menggunakan_armada_cb_snapshot, false)
    AND COALESCE(NEW.kenakan_sewa_armada_cb, NEW.pakai_sewa_armada_bl, false);

  IF v_kenakan_sewa THEN
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
  END IF;

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

  IF NEW.dana_operasional_dibayar_mitra IS TRUE THEN
    NEW.biaya_sewa_armada_total := GREATEST(v_sewa_kotor - v_dana_operasional, 0);

    -- Perbaiki pencatatan skema lama tanpa menghapus jejak audit. Kas keluar
    -- lama tetap ada dan dinetralkan oleh transaksi balik dengan nominal sama.
    IF TG_OP = 'UPDATE'
       AND NOT v_has_issued_receipt
       AND (
         OLD.tagihan_sopir_ledger_id IS NOT NULL
         OR OLD.tagihan_sopir_bayar_ledger_id IS NOT NULL
         OR OLD.biaya_sopir_operasional_id IS NOT NULL
         OR OLD.biaya_sopir_dibayar_at IS NOT NULL
       ) THEN
      IF OLD.biaya_sopir_operasional_id IS NOT NULL THEN
        SELECT * INTO v_biaya
        FROM public.biaya_operasional
        WHERE id = OLD.biaya_sopir_operasional_id
        FOR UPDATE;

        v_kas_id := v_biaya.kas_ledger_id;
      END IF;

      IF v_kas_id IS NULL AND OLD.tagihan_sopir_bayar_ledger_id IS NOT NULL THEN
        SELECT kas_ledger_id INTO v_kas_id
        FROM public.hutang_ledger
        WHERE id = OLD.tagihan_sopir_bayar_ledger_id;
      END IF;

      IF v_kas_id IS NOT NULL THEN
        SELECT * INTO v_original_kas
        FROM public.kas_ledger
        WHERE id = v_kas_id
        FOR UPDATE;

        IF v_original_kas.id IS NOT NULL
           AND v_original_kas.tipe = 'keluar'
           AND v_original_kas.status <> 'dibatalkan'
           AND NOT EXISTS (
             SELECT 1
             FROM public.kas_ledger reversal
             WHERE reversal.reversal_of_id = v_original_kas.id
               AND reversal.status <> 'dibatalkan'
           ) THEN
          INSERT INTO public.kas_ledger (
            rekening_kas_id, tanggal, tipe, sumber, jumlah,
            biaya_operasional_id, hutang_ledger_id,
            source_table, source_id, reversal_of_id,
            idempotency_key, keterangan, created_by
          ) VALUES (
            v_original_kas.rekening_kas_id,
            (now() AT TIME ZONE 'Asia/Jakarta')::date,
            'masuk', 'reversal', v_original_kas.jumlah,
            v_biaya.id, OLD.tagihan_sopir_bayar_ledger_id,
            'transaksi_mitra', OLD.id, v_original_kas.id,
            'dana_trip:' || OLD.id::text || ':reversal:direct_mitra',
            v_reason, v_actor
          );
        END IF;

        UPDATE public.kas_ledger
        SET reversed_at = COALESCE(reversed_at, now()),
            reversed_by = COALESCE(reversed_by, v_actor),
            reversal_reason = COALESCE(reversal_reason, v_reason),
            updated_at = now()
        WHERE id = v_original_kas.id;
      END IF;

      IF v_biaya.id IS NOT NULL THEN
        UPDATE public.biaya_operasional
        SET status = 'dibatalkan',
            alasan_batal = v_reason,
            dibatalkan_at = COALESCE(dibatalkan_at, now()),
            dibatalkan_by = COALESCE(dibatalkan_by, v_actor),
            updated_at = now()
        WHERE id = v_biaya.id
          AND status = 'aktif';
      END IF;

      UPDATE public.hutang_ledger
      SET status = 'dibatalkan',
          alasan_batal = v_reason,
          dibatalkan_at = COALESCE(dibatalkan_at, now()),
          dibatalkan_by = COALESCE(dibatalkan_by, v_actor),
          updated_at = now()
      WHERE id IN (OLD.tagihan_sopir_ledger_id, OLD.tagihan_sopir_bayar_ledger_id)
        AND status = 'aktif';

      NEW.tagihan_sopir_ledger_id := NULL;
      NEW.tagihan_sopir_bayar_ledger_id := NULL;
      NEW.biaya_sopir_operasional_id := NULL;
      NEW.biaya_sopir_dibayar_at := NULL;
    END IF;
  ELSE
    NEW.biaya_sewa_armada_total := v_sewa_kotor;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_direct_operational_fund_on_write() FROM PUBLIC;

DROP TRIGGER IF EXISTS zzz_apply_direct_operational_fund
ON public.transaksi_mitra;

CREATE TRIGGER zzz_apply_direct_operational_fund
BEFORE INSERT OR UPDATE OF
  status,
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
  dana_operasional_dibayar_mitra,
  tagihan_sopir_ledger_id,
  tagihan_sopir_bayar_ledger_id,
  biaya_sopir_operasional_id,
  biaya_sopir_dibayar_at
ON public.transaksi_mitra
FOR EACH ROW
EXECUTE FUNCTION public.apply_direct_operational_fund_on_write();

-- Rekonsiliasi hanya transaksi aktif yang belum masuk kwitansi. Trigger di
-- atas sekaligus menghitung sewa akhir dan menetralkan pencatatan Kas CB lama.
UPDATE public.transaksi_mitra tm
SET dana_operasional_dibayar_mitra = true
WHERE COALESCE(tm.status, 'aktif') = 'aktif'
  AND COALESCE(tm.menggunakan_armada_cb_snapshot, false)
  AND COALESCE(tm.catat_dana_operasional_trip, false)
  AND GREATEST(COALESCE(
    NULLIF(tm.dana_operasional_trip_snapshot, 0),
    NULLIF(tm.total_biaya_sopir_cb_snapshot, 0),
    0
  ), 0) > 0
  AND NOT EXISTS (
    SELECT 1
    FROM public.pembayaran_mitra_kwitansi_item item
    JOIN public.pembayaran_mitra_kwitansi payment
      ON payment.id = item.pembayaran_id
    WHERE item.transaksi_mitra_id = tm.id
      AND payment.status <> 'dibatalkan'
  );

ALTER TABLE public.transaksi_mitra
  ALTER COLUMN dana_operasional_dibayar_mitra SET DEFAULT true;

COMMENT ON COLUMN public.transaksi_mitra.dana_operasional_dibayar_mitra IS
  'TRUE untuk transaksi aktif Armada CB: Dana Operasional sudah dibayar langsung oleh Mitra kepada sopir sebelum berangkat. Nilai lama hanya dipertahankan pada snapshot kwitansi yang telah terbit.';
