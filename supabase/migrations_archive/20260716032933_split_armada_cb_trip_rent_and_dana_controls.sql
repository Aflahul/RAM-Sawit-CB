-- Separate the physical use of an Armada CB from two independent financial
-- decisions: charging rent to the mitra and creating Dana Operasional Trip.

ALTER TABLE public.transaksi_mitra
  ADD COLUMN IF NOT EXISTS menggunakan_armada_cb_snapshot boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS kenakan_sewa_armada_cb boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS catat_dana_operasional_trip boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS alasan_tanpa_sewa_armada_cb text,
  ADD COLUMN IF NOT EXISTS alasan_tanpa_dana_operasional_trip text,
  ADD COLUMN IF NOT EXISTS armada_cb_perlu_review boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS alasan_review_armada_cb text;

COMMENT ON COLUMN public.transaksi_mitra.menggunakan_armada_cb_snapshot IS
  'Snapshot fakta bahwa pengiriman memakai Armada CB. Menjadi dasar hitungan trip dan muatan armada.';
COMMENT ON COLUMN public.transaksi_mitra.kenakan_sewa_armada_cb IS
  'Jika true, sewa Armada CB dipotong dari hak mitra dan menjadi pendapatan CB.';
COMMENT ON COLUMN public.transaksi_mitra.catat_dana_operasional_trip IS
  'Jika true, pengiriman membuat tagihan Dana Operasional Trip.';
COMMENT ON COLUMN public.transaksi_mitra.armada_cb_perlu_review IS
  'Penanda data lama/ambigu yang perlu ditetapkan perlakuan Armada CB-nya.';

-- Preserve old financial meaning. Rows that only become identifiable as CB
-- from the current master are classified as trips, but receive no new charge.
UPDATE public.transaksi_mitra transaction
SET menggunakan_armada_cb_snapshot = COALESCE(driver.is_armada_cb, false)
      OR COALESCE(transaction.pakai_sewa_armada_bl, false),
    kenakan_sewa_armada_cb = COALESCE(transaction.pakai_sewa_armada_bl, false),
    catat_dana_operasional_trip = COALESCE(transaction.pakai_sewa_armada_bl, false),
    alasan_tanpa_sewa_armada_cb = CASE
      WHEN COALESCE(driver.is_armada_cb, false) AND NOT COALESCE(transaction.pakai_sewa_armada_bl, false)
        THEN 'Data lama: potongan sewa belum pernah ditetapkan.'
      ELSE NULL
    END,
    alasan_tanpa_dana_operasional_trip = CASE
      WHEN COALESCE(driver.is_armada_cb, false) AND NOT COALESCE(transaction.pakai_sewa_armada_bl, false)
        THEN 'Data lama: Dana Operasional Trip belum pernah ditetapkan.'
      ELSE NULL
    END,
    armada_cb_perlu_review = transaction.status = 'aktif'
      AND COALESCE(driver.is_armada_cb, false)
      AND NOT COALESCE(transaction.pakai_sewa_armada_bl, false),
    alasan_review_armada_cb = CASE
      WHEN transaction.status = 'aktif'
        AND COALESCE(driver.is_armada_cb, false)
        AND NOT COALESCE(transaction.pakai_sewa_armada_bl, false)
        THEN 'Armada pada master sekarang berstatus CB, tetapi transaksi lama belum memiliki keputusan sewa dan Dana Trip.'
      ELSE NULL
    END
FROM public.sopir driver
WHERE driver.id = transaction.sopir_id;

UPDATE public.transaksi_mitra
SET menggunakan_armada_cb_snapshot = COALESCE(pakai_sewa_armada_bl, false),
    kenakan_sewa_armada_cb = COALESCE(pakai_sewa_armada_bl, false),
    catat_dana_operasional_trip = COALESCE(pakai_sewa_armada_bl, false)
WHERE sopir_id IS NULL;

ALTER TABLE public.transaksi_mitra
  ADD CONSTRAINT transaksi_mitra_sewa_requires_armada_cb
    CHECK (NOT kenakan_sewa_armada_cb OR menggunakan_armada_cb_snapshot) NOT VALID,
  ADD CONSTRAINT transaksi_mitra_dana_requires_armada_cb
    CHECK (NOT catat_dana_operasional_trip OR menggunakan_armada_cb_snapshot) NOT VALID,
  ADD CONSTRAINT transaksi_mitra_reason_without_rent
    CHECK (
      NOT menggunakan_armada_cb_snapshot
      OR kenakan_sewa_armada_cb
      OR NULLIF(btrim(COALESCE(alasan_tanpa_sewa_armada_cb, '')), '') IS NOT NULL
    ) NOT VALID,
  ADD CONSTRAINT transaksi_mitra_reason_without_trip_fund
    CHECK (
      NOT menggunakan_armada_cb_snapshot
      OR catat_dana_operasional_trip
      OR NULLIF(btrim(COALESCE(alasan_tanpa_dana_operasional_trip, '')), '') IS NOT NULL
    ) NOT VALID;

ALTER TABLE public.transaksi_mitra VALIDATE CONSTRAINT transaksi_mitra_sewa_requires_armada_cb;
ALTER TABLE public.transaksi_mitra VALIDATE CONSTRAINT transaksi_mitra_dana_requires_armada_cb;
ALTER TABLE public.transaksi_mitra VALIDATE CONSTRAINT transaksi_mitra_reason_without_rent;
ALTER TABLE public.transaksi_mitra VALIDATE CONSTRAINT transaksi_mitra_reason_without_trip_fund;

CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_armada_cb_trip
  ON public.transaksi_mitra (tanggal, sopir_id)
  WHERE menggunakan_armada_cb_snapshot = true AND status = 'aktif';
CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_armada_cb_review
  ON public.transaksi_mitra (tanggal, created_at)
  WHERE armada_cb_perlu_review = true AND status = 'aktif';

CREATE OR REPLACE FUNCTION public.normalize_transaksi_mitra_armada_cb()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sopir public.sopir%ROWTYPE;
  v_is_armada_cb boolean := false;
  v_berat_netto numeric(15,2) := 0;
  v_tarif_sewa numeric(15,2) := 0;
  v_tarif_sewa_mitra numeric(15,2) := 0;
  v_dana_trip numeric(15,2) := 0;
  v_refresh_snapshot boolean := false;
  v_control_changed boolean := false;
BEGIN
  SELECT * INTO v_sopir
  FROM public.sopir
  WHERE id = NEW.sopir_id;

  v_is_armada_cb := COALESCE(v_sopir.is_armada_cb, false);

  IF TG_OP = 'INSERT' THEN
    NEW.menggunakan_armada_cb_snapshot := v_is_armada_cb;
    NEW.armada_cb_perlu_review := false;
    NEW.alasan_review_armada_cb := NULL;
  ELSIF OLD.sopir_id IS DISTINCT FROM NEW.sopir_id THEN
    NEW.menggunakan_armada_cb_snapshot := v_is_armada_cb;
  END IF;

  v_control_changed := TG_OP = 'UPDATE' AND (
    OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
    OR OLD.kenakan_sewa_armada_cb IS DISTINCT FROM NEW.kenakan_sewa_armada_cb
    OR OLD.catat_dana_operasional_trip IS DISTINCT FROM NEW.catat_dana_operasional_trip
    OR OLD.alasan_tanpa_sewa_armada_cb IS DISTINCT FROM NEW.alasan_tanpa_sewa_armada_cb
    OR OLD.alasan_tanpa_dana_operasional_trip IS DISTINCT FROM NEW.alasan_tanpa_dana_operasional_trip
  );

  IF v_control_changed THEN
    NEW.armada_cb_perlu_review := false;
    NEW.alasan_review_armada_cb := NULL;
  END IF;

  IF NOT NEW.menggunakan_armada_cb_snapshot THEN
    NEW.kenakan_sewa_armada_cb := false;
    NEW.catat_dana_operasional_trip := false;
    NEW.alasan_tanpa_sewa_armada_cb := NULL;
    NEW.alasan_tanpa_dana_operasional_trip := NULL;
    NEW.armada_cb_perlu_review := false;
    NEW.alasan_review_armada_cb := NULL;
  ELSE
    IF NOT NEW.kenakan_sewa_armada_cb
       AND NULLIF(btrim(COALESCE(NEW.alasan_tanpa_sewa_armada_cb, '')), '') IS NULL THEN
      RAISE EXCEPTION 'Alasan tidak mengenakan sewa Armada CB wajib diisi.' USING ERRCODE = '22023';
    END IF;
    IF NOT NEW.catat_dana_operasional_trip
       AND NULLIF(btrim(COALESCE(NEW.alasan_tanpa_dana_operasional_trip, '')), '') IS NULL THEN
      RAISE EXCEPTION 'Alasan tidak membuat Dana Operasional Trip wajib diisi.' USING ERRCODE = '22023';
    END IF;
    IF NEW.kenakan_sewa_armada_cb THEN
      NEW.alasan_tanpa_sewa_armada_cb := NULL;
    END IF;
    IF NEW.catat_dana_operasional_trip THEN
      NEW.alasan_tanpa_dana_operasional_trip := NULL;
    END IF;
  END IF;

  -- Legacy compatibility: this field now means rent is charged, not trip use.
  NEW.pakai_sewa_armada_bl := NEW.menggunakan_armada_cb_snapshot
    AND NEW.kenakan_sewa_armada_cb;

  v_refresh_snapshot := TG_OP = 'INSERT';
  IF TG_OP = 'UPDATE' THEN
    v_refresh_snapshot := OLD.biaya_sopir_dibayar_at IS NULL AND (
      OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
      OR OLD.mitra_id IS DISTINCT FROM NEW.mitra_id
      OR OLD.tanggal IS DISTINCT FROM NEW.tanggal
      OR OLD.kenakan_sewa_armada_cb IS DISTINCT FROM NEW.kenakan_sewa_armada_cb
      OR OLD.catat_dana_operasional_trip IS DISTINCT FROM NEW.catat_dana_operasional_trip
    );
  END IF;

  IF NEW.mitra_id IS NOT NULL THEN
    SELECT
      COALESCE(history.tarif_sewa_angkut_per_kg, mitra.tarif_sewa_angkut_per_kg, 0),
      COALESCE(history.dana_operasional_trip, mitra.dana_operasional_trip, 0)
    INTO v_tarif_sewa_mitra, v_dana_trip
    FROM public.master_mitra mitra
    LEFT JOIN LATERAL (
      SELECT fee.tarif_sewa_angkut_per_kg, fee.dana_operasional_trip
      FROM public.fee_owner_mitra_history fee
      WHERE fee.master_mitra_id = mitra.id
        AND fee.aktif = true
        AND fee.berlaku_mulai <= NEW.tanggal
        AND (fee.berlaku_sampai IS NULL OR fee.berlaku_sampai >= NEW.tanggal)
      ORDER BY fee.berlaku_mulai DESC, fee.created_at DESC
      LIMIT 1
    ) history ON true
    WHERE mitra.id = NEW.mitra_id;
  END IF;

  v_berat_netto := GREATEST(COALESCE(NEW.berat_netto_pabrik_kg, NEW.tonase, 0), 0);
  IF v_refresh_snapshot THEN
    v_tarif_sewa := GREATEST(COALESCE(v_tarif_sewa_mitra, 0), 0);
  ELSE
    v_tarif_sewa := GREATEST(COALESCE(
      NULLIF(NEW.tarif_sewa_angkut_per_kg_snapshot, 0),
      NULLIF(NEW.biaya_sewa_armada_per_kg, 0),
      v_tarif_sewa_mitra,
      0
    ), 0);
  END IF;

  IF NEW.menggunakan_armada_cb_snapshot AND NEW.kenakan_sewa_armada_cb THEN
    NEW.tarif_sewa_angkut_per_kg_snapshot := v_tarif_sewa;
    NEW.biaya_sewa_armada_per_kg := v_tarif_sewa;
    NEW.biaya_sewa_armada_kotor := round(v_berat_netto * v_tarif_sewa, 2);
    NEW.biaya_sewa_armada_total := NEW.biaya_sewa_armada_kotor;
  ELSE
    NEW.tarif_sewa_angkut_per_kg_snapshot := 0;
    NEW.biaya_sewa_armada_per_kg := 0;
    NEW.biaya_sewa_armada_kotor := 0;
    NEW.biaya_sewa_armada_total := 0;
  END IF;

  IF v_refresh_snapshot THEN
    IF NEW.menggunakan_armada_cb_snapshot AND NEW.catat_dana_operasional_trip THEN
      NEW.dana_operasional_trip_snapshot := GREATEST(COALESCE(v_dana_trip, 0), 0);
      NEW.upah_sopir_cb_snapshot := 0;
      NEW.uang_jalan_sopir_cb_snapshot := 0;
      NEW.total_biaya_sopir_cb_snapshot := NEW.dana_operasional_trip_snapshot;
      NEW.nominal_perongkosan_snapshot := 0;
    ELSE
      NEW.dana_operasional_trip_snapshot := 0;
      NEW.upah_sopir_cb_snapshot := 0;
      NEW.uang_jalan_sopir_cb_snapshot := 0;
      NEW.total_biaya_sopir_cb_snapshot := 0;
    END IF;
  ELSIF NOT NEW.catat_dana_operasional_trip THEN
    NEW.dana_operasional_trip_snapshot := 0;
    NEW.upah_sopir_cb_snapshot := 0;
    NEW.uang_jalan_sopir_cb_snapshot := 0;
    NEW.total_biaya_sopir_cb_snapshot := 0;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS normalize_armada_cb ON public.transaksi_mitra;
CREATE TRIGGER normalize_armada_cb
  BEFORE INSERT OR UPDATE OF
    tanggal, sopir_id, mitra_id, berat_netto_pabrik_kg, tonase,
    tarif_sewa_angkut_per_kg_snapshot, biaya_sewa_armada_per_kg,
    pakai_sewa_armada_bl, kenakan_sewa_armada_cb,
    catat_dana_operasional_trip, alasan_tanpa_sewa_armada_cb,
    alasan_tanpa_dana_operasional_trip
  ON public.transaksi_mitra
  FOR EACH ROW
  EXECUTE FUNCTION public.normalize_transaksi_mitra_armada_cb();

CREATE OR REPLACE FUNCTION public.sync_tagihan_sopir_cb()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_tagihan public.hutang_ledger%ROWTYPE;
  v_pihak_type text;
  v_sopir_aktual_id uuid;
  v_pihak_nama text;
  v_nominal numeric(15,2) := 0;
BEGIN
  v_nominal := GREATEST(COALESCE(
    NULLIF(NEW.dana_operasional_trip_snapshot, 0),
    NEW.total_biaya_sopir_cb_snapshot,
    0
  ), 0);

  IF NEW.status = 'dibatalkan'
     OR NOT NEW.menggunakan_armada_cb_snapshot
     OR NOT NEW.catat_dana_operasional_trip
     OR v_nominal <= 0 THEN
    IF NEW.tagihan_sopir_ledger_id IS NOT NULL
       AND NEW.biaya_sopir_dibayar_at IS NULL THEN
      UPDATE public.hutang_ledger
      SET status = 'dibatalkan',
          alasan_batal = CASE
            WHEN NEW.status = 'dibatalkan' THEN COALESCE(NEW.alasan_batal, 'Pengiriman dibatalkan')
            ELSE 'Dana Operasional Trip dinonaktifkan pada pengiriman.'
          END,
          dibatalkan_at = now(),
          dibatalkan_by = COALESCE(NEW.dibatalkan_by, v_actor)
      WHERE id = NEW.tagihan_sopir_ledger_id
        AND status = 'aktif';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.tagihan_sopir_ledger_id IS NOT NULL THEN
    SELECT * INTO v_tagihan
    FROM public.hutang_ledger
    WHERE id = NEW.tagihan_sopir_ledger_id;

    IF v_tagihan.id IS NOT NULL AND v_tagihan.status = 'aktif' THEN
      IF NEW.biaya_sopir_dibayar_at IS NULL THEN
        UPDATE public.hutang_ledger
        SET sumber = 'operasional',
            jumlah = v_nominal,
            keterangan = format(
              'Dana operasional trip Armada CB %s tanggal %s',
              COALESCE(NEW.plat_nomor, '-'), NEW.tanggal
            ),
            updated_at = now()
        WHERE id = v_tagihan.id;
      END IF;
      RETURN NEW;
    END IF;
  END IF;

  SELECT * INTO v_tagihan
  FROM public.hutang_ledger
  WHERE legacy_source_table = 'tagihan_sopir_cb'
    AND legacy_source_id = NEW.id
    AND status = 'aktif'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_tagihan.id IS NULL THEN
    v_sopir_aktual_id := CASE
      WHEN NEW.sopir_aktual_source = 'manual' THEN NULL
      ELSE COALESCE(NEW.sopir_aktual_id, NEW.sopir_id)
    END;
    v_pihak_nama := NULLIF(btrim(COALESCE(NEW.sopir_aktual_nama, NEW.sopir_default_nama, '')), '');
    v_pihak_type := CASE WHEN v_sopir_aktual_id IS NULL THEN 'lainnya' ELSE 'sopir' END;

    INSERT INTO public.hutang_ledger (
      pihak_type, sopir_id, pihak_nama_manual, tanggal, tipe, sumber, jumlah,
      legacy_source_table, legacy_source_id, keterangan, created_by
    ) VALUES (
      v_pihak_type,
      CASE WHEN v_pihak_type = 'sopir' THEN v_sopir_aktual_id ELSE NULL END,
      CASE WHEN v_pihak_type = 'lainnya' THEN COALESCE(v_pihak_nama, 'Sopir pengganti') ELSE NULL END,
      NEW.tanggal, 'debit', 'operasional', v_nominal,
      'tagihan_sopir_cb', NEW.id,
      format('Dana operasional trip Armada CB %s tanggal %s', COALESCE(NEW.plat_nomor, '-'), NEW.tanggal),
      v_actor
    ) RETURNING * INTO v_tagihan;
  END IF;

  UPDATE public.transaksi_mitra
  SET tagihan_sopir_ledger_id = v_tagihan.id
  WHERE id = NEW.id
    AND tagihan_sopir_ledger_id IS DISTINCT FROM v_tagihan.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_tagihan_sopir_cb ON public.transaksi_mitra;
CREATE TRIGGER sync_tagihan_sopir_cb
  AFTER INSERT OR UPDATE OF
    tanggal, sopir_id, mitra_id, status, menggunakan_armada_cb_snapshot,
    catat_dana_operasional_trip, dana_operasional_trip_snapshot,
    total_biaya_sopir_cb_snapshot, tagihan_sopir_ledger_id
  ON public.transaksi_mitra
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_tagihan_sopir_cb();

CREATE OR REPLACE FUNCTION public.guard_paid_transaksi_mitra_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_material_change boolean;
  v_armada_change boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  v_material_change :=
    OLD.tanggal IS DISTINCT FROM NEW.tanggal
    OR OLD.mitra_id IS DISTINCT FROM NEW.mitra_id
    OR OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
    OR OLD.sopir_aktual_id IS DISTINCT FROM NEW.sopir_aktual_id
    OR OLD.sopir_aktual_nama IS DISTINCT FROM NEW.sopir_aktual_nama
    OR OLD.plat_nomor IS DISTINCT FROM NEW.plat_nomor
    OR OLD.tonase IS DISTINCT FROM NEW.tonase
    OR OLD.berat_netto_pabrik_kg IS DISTINCT FROM NEW.berat_netto_pabrik_kg
    OR OLD.potongan_pabrik_kg IS DISTINCT FROM NEW.potongan_pabrik_kg
    OR OLD.berat_dibayar_kg IS DISTINCT FROM NEW.berat_dibayar_kg
    OR OLD.harga_pabrik_per_kg IS DISTINCT FROM NEW.harga_pabrik_per_kg
    OR OLD.fee_owner_per_kg IS DISTINCT FROM NEW.fee_owner_per_kg
    OR OLD.total_nilai_bersih IS DISTINCT FROM NEW.total_nilai_bersih
    OR OLD.pakai_sewa_armada_bl IS DISTINCT FROM NEW.pakai_sewa_armada_bl
    OR OLD.kenakan_sewa_armada_cb IS DISTINCT FROM NEW.kenakan_sewa_armada_cb
    OR OLD.biaya_sewa_armada_total IS DISTINCT FROM NEW.biaya_sewa_armada_total
    OR OLD.status IS DISTINCT FROM NEW.status;

  v_armada_change :=
    OLD.tanggal IS DISTINCT FROM NEW.tanggal
    OR OLD.mitra_id IS DISTINCT FROM NEW.mitra_id
    OR OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
    OR OLD.sopir_aktual_id IS DISTINCT FROM NEW.sopir_aktual_id
    OR OLD.plat_nomor IS DISTINCT FROM NEW.plat_nomor
    OR OLD.menggunakan_armada_cb_snapshot IS DISTINCT FROM NEW.menggunakan_armada_cb_snapshot
    OR OLD.catat_dana_operasional_trip IS DISTINCT FROM NEW.catat_dana_operasional_trip
    OR OLD.dana_operasional_trip_snapshot IS DISTINCT FROM NEW.dana_operasional_trip_snapshot
    OR OLD.status IS DISTINCT FROM NEW.status;

  IF v_material_change AND EXISTS (
    SELECT 1
    FROM public.pembayaran_mitra_kwitansi_item item
    JOIN public.pembayaran_mitra_kwitansi payment ON payment.id = item.pembayaran_id
    WHERE item.transaksi_mitra_id = OLD.id AND payment.status <> 'dibatalkan'
  ) THEN
    RAISE EXCEPTION 'Transaksi sudah masuk kwitansi. Batalkan kwitansi melalui menu Kwitansi sebelum mengoreksi transaksi.'
      USING ERRCODE = '55000';
  END IF;

  IF v_material_change AND EXISTS (
    SELECT 1
    FROM public.pembayaran_pabrik_item item
    JOIN public.pembayaran_pabrik_batch payment ON payment.id = item.pembayaran_id
    WHERE item.transaksi_mitra_id = OLD.id AND payment.status <> 'dibatalkan'
  ) THEN
    RAISE EXCEPTION 'Transaksi sudah dicocokkan dengan pembayaran pabrik. Batalkan pembayaran pabrik sebelum mengoreksi transaksi.'
      USING ERRCODE = '55000';
  END IF;

  IF v_armada_change AND OLD.biaya_sopir_dibayar_at IS NOT NULL THEN
    RAISE EXCEPTION 'Dana Operasional Trip sudah dibayar. Koreksi pembayaran Dana Trip terlebih dahulu.'
      USING ERRCODE = '55000';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_transaksi_mitra_controlled(
  p_transaksi_id uuid,
  p_changes jsonb,
  p_alasan text
)
RETURNS public.transaksi_mitra
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.transaksi_mitra%ROWTYPE;
  v_candidate public.transaksi_mitra%ROWTYPE;
  v_after public.transaksi_mitra%ROWTYPE;
  v_unknown_key text;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang mengoreksi pengiriman.' USING ERRCODE = '42501';
  END IF;
  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan koreksi wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before FROM public.transaksi_mitra WHERE id = p_transaksi_id FOR UPDATE;
  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Pengiriman tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF v_before.status = 'dibatalkan' THEN
    RAISE EXCEPTION 'Pengiriman sudah dibatalkan.' USING ERRCODE = '22023';
  END IF;

  SELECT key INTO v_unknown_key
  FROM jsonb_object_keys(COALESCE(p_changes, '{}'::jsonb)) key
  WHERE key <> ALL (ARRAY[
    'tanggal', 'sopir_id', 'sopir_default_id', 'sopir_default_nama',
    'mitra_id', 'plat_nomor', 'sopir_aktual_id', 'sopir_aktual_nama',
    'sopir_aktual_no_hp', 'sopir_aktual_source', 'sopir_diganti_dari_default',
    'catatan_sopir', 'tonase', 'berat_netto_pabrik_kg',
    'potongan_pabrik_kg', 'berat_dibayar_kg', 'harga_harian',
    'harga_pabrik_per_kg', 'fee_owner_per_kg', 'harga_bersih_per_kg',
    'fee_owner_history_id', 'total_kotor', 'total_fee_owner',
    'total_nilai_bersih', 'pakai_sewa_armada_bl',
    'kenakan_sewa_armada_cb', 'catat_dana_operasional_trip',
    'alasan_tanpa_sewa_armada_cb', 'alasan_tanpa_dana_operasional_trip',
    'biaya_sewa_armada_per_kg', 'tarif_sewa_angkut_per_kg_snapshot',
    'biaya_sewa_armada_kotor', 'biaya_sewa_armada_total'
  ]) LIMIT 1;

  IF v_unknown_key IS NOT NULL THEN
    RAISE EXCEPTION 'Field koreksi tidak diizinkan: %', v_unknown_key USING ERRCODE = '22023';
  END IF;

  v_candidate := jsonb_populate_record(v_before, COALESCE(p_changes, '{}'::jsonb));

  UPDATE public.transaksi_mitra
  SET tanggal = v_candidate.tanggal,
      sopir_id = v_candidate.sopir_id,
      sopir_default_id = v_candidate.sopir_default_id,
      sopir_default_nama = v_candidate.sopir_default_nama,
      mitra_id = v_candidate.mitra_id,
      plat_nomor = v_candidate.plat_nomor,
      sopir_aktual_id = v_candidate.sopir_aktual_id,
      sopir_aktual_nama = v_candidate.sopir_aktual_nama,
      sopir_aktual_no_hp = v_candidate.sopir_aktual_no_hp,
      sopir_aktual_source = v_candidate.sopir_aktual_source,
      sopir_diganti_dari_default = v_candidate.sopir_diganti_dari_default,
      catatan_sopir = v_candidate.catatan_sopir,
      tonase = v_candidate.tonase,
      berat_netto_pabrik_kg = v_candidate.berat_netto_pabrik_kg,
      potongan_pabrik_kg = v_candidate.potongan_pabrik_kg,
      berat_dibayar_kg = v_candidate.berat_dibayar_kg,
      harga_harian = v_candidate.harga_harian,
      harga_pabrik_per_kg = v_candidate.harga_pabrik_per_kg,
      fee_owner_per_kg = v_candidate.fee_owner_per_kg,
      harga_bersih_per_kg = v_candidate.harga_bersih_per_kg,
      fee_owner_history_id = v_candidate.fee_owner_history_id,
      total_kotor = v_candidate.total_kotor,
      total_fee_owner = v_candidate.total_fee_owner,
      total_nilai_bersih = v_candidate.total_nilai_bersih,
      pakai_sewa_armada_bl = v_candidate.pakai_sewa_armada_bl,
      kenakan_sewa_armada_cb = v_candidate.kenakan_sewa_armada_cb,
      catat_dana_operasional_trip = v_candidate.catat_dana_operasional_trip,
      alasan_tanpa_sewa_armada_cb = v_candidate.alasan_tanpa_sewa_armada_cb,
      alasan_tanpa_dana_operasional_trip = v_candidate.alasan_tanpa_dana_operasional_trip,
      biaya_sewa_armada_per_kg = v_candidate.biaya_sewa_armada_per_kg,
      tarif_sewa_angkut_per_kg_snapshot = v_candidate.tarif_sewa_angkut_per_kg_snapshot,
      biaya_sewa_armada_kotor = v_candidate.biaya_sewa_armada_kotor,
      biaya_sewa_armada_total = v_candidate.biaya_sewa_armada_total,
      updated_by = v_actor,
      alasan_edit = btrim(p_alasan)
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  PERFORM public.write_audit_log(
    'transaksi_mitra', v_before.id, 'update',
    to_jsonb(v_before), to_jsonb(v_after), p_alasan,
    CASE WHEN public.has_app_role(ARRAY['owner', 'super_admin']) THEN v_actor ELSE NULL END
  );
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_dashboard_pending_summary()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_unpaid_mitra bigint := 0;
  v_unpaid_weight numeric := 0;
  v_review bigint := 0;
  v_pending_mitra bigint := 0;
  v_pending_armada bigint := 0;
  v_pending_armada_trip bigint := 0;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang melihat antrian dashboard.' USING ERRCODE = '42501';
  END IF;

  SELECT count(DISTINCT transaction.mitra_id),
         COALESCE(sum(COALESCE(transaction.berat_dibayar_kg, transaction.tonase)), 0)
  INTO v_unpaid_mitra, v_unpaid_weight
  FROM public.transaksi_mitra transaction
  WHERE transaction.status <> 'dibatalkan'
    AND NOT EXISTS (
      SELECT 1 FROM public.pembayaran_mitra_kwitansi_item item
      JOIN public.pembayaran_mitra_kwitansi payment ON payment.id = item.pembayaran_id
      WHERE item.transaksi_mitra_id = transaction.id AND payment.status <> 'dibatalkan'
    );

  SELECT count(*) INTO v_review FROM public.pembayaran_mitra_kwitansi WHERE status = 'perlu_review';
  SELECT count(*) INTO v_pending_mitra FROM public.master_mitra WHERE status_verifikasi = 'perlu_verifikasi';
  SELECT count(*) INTO v_pending_armada FROM public.sopir WHERE aktif = true AND status_verifikasi = 'perlu_verifikasi';
  SELECT count(*) INTO v_pending_armada_trip
  FROM public.transaksi_mitra
  WHERE status = 'aktif' AND armada_cb_perlu_review = true;

  RETURN jsonb_build_object(
    'kwitansi_belum_dibayar', v_unpaid_mitra,
    'kwitansi_belum_dibayar_kg', v_unpaid_weight,
    'kwitansi_perlu_review', v_review,
    'mitra_perlu_verifikasi', v_pending_mitra,
    'armada_perlu_verifikasi', v_pending_armada,
    'trip_armada_cb_perlu_review', v_pending_armada_trip
  );
END;
$$;

REVOKE ALL ON FUNCTION public.normalize_transaksi_mitra_armada_cb() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_tagihan_sopir_cb() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_paid_transaksi_mitra_changes() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_transaksi_mitra_controlled(uuid, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_transaksi_mitra_controlled(uuid, jsonb, text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_dashboard_pending_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_dashboard_pending_summary() TO authenticated;
