-- Armada CB: dana operasional satu kali jalan ditentukan oleh mitra penyewa.
-- Kolom biaya sopir lama dipertahankan sebagai kompatibilitas data historis.

BEGIN;

ALTER TABLE public.master_mitra
  ADD COLUMN IF NOT EXISTS dana_operasional_trip numeric(15,2) NOT NULL DEFAULT 0;

ALTER TABLE public.fee_owner_mitra_history
  ADD COLUMN IF NOT EXISTS dana_operasional_trip numeric(15,2) NOT NULL DEFAULT 0;

ALTER TABLE public.transaksi_mitra
  ADD COLUMN IF NOT EXISTS dana_operasional_trip_snapshot numeric(15,2) NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'master_mitra_dana_operasional_trip_nonnegative'
      AND conrelid = 'public.master_mitra'::regclass
  ) THEN
    ALTER TABLE public.master_mitra
      ADD CONSTRAINT master_mitra_dana_operasional_trip_nonnegative
      CHECK (dana_operasional_trip >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fee_history_dana_operasional_trip_nonnegative'
      AND conrelid = 'public.fee_owner_mitra_history'::regclass
  ) THEN
    ALTER TABLE public.fee_owner_mitra_history
      ADD CONSTRAINT fee_history_dana_operasional_trip_nonnegative
      CHECK (dana_operasional_trip >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transaksi_mitra_dana_operasional_trip_nonnegative'
      AND conrelid = 'public.transaksi_mitra'::regclass
  ) THEN
    ALTER TABLE public.transaksi_mitra
      ADD CONSTRAINT transaksi_mitra_dana_operasional_trip_nonnegative
      CHECK (dana_operasional_trip_snapshot >= 0);
  END IF;
END;
$$;

ALTER TABLE public.biaya_operasional
  DROP CONSTRAINT IF EXISTS biaya_operasional_kategori_check;
ALTER TABLE public.biaya_operasional
  ADD CONSTRAINT biaya_operasional_kategori_check
  CHECK (kategori = ANY (ARRAY[
    'solar'::text,
    'gaji_sopir'::text,
    'dana_operasional_trip'::text,
    'kuli'::text,
    'retribusi'::text,
    'perawatan'::text,
    'lainnya'::text
  ]));

COMMENT ON COLUMN public.master_mitra.dana_operasional_trip IS
  'Dana flat satu kali jalan Armada CB untuk mitra ini; mencakup solar, makan, uang jalan, dan bagian sopir.';
COMMENT ON COLUMN public.fee_owner_mitra_history.dana_operasional_trip IS
  'Riwayat dana operasional satu kali jalan Armada CB berdasarkan mitra dan tanggal berlaku.';
COMMENT ON COLUMN public.transaksi_mitra.dana_operasional_trip_snapshot IS
  'Snapshot dana operasional satu kali jalan saat pengiriman dibuat. Tidak dipecah menjadi gaji, solar, atau makan.';
COMMENT ON COLUMN public.transaksi_mitra.total_biaya_sopir_cb_snapshot IS
  'Field kompatibilitas. Untuk transaksi baru nilainya sama dengan dana_operasional_trip_snapshot.';
COMMENT ON COLUMN public.transaksi_mitra.upah_sopir_cb_snapshot IS
  'Field legacy. Tidak dipakai untuk transaksi baru karena bagian bersih sopir tidak diketahui.';
COMMENT ON COLUMN public.transaksi_mitra.uang_jalan_sopir_cb_snapshot IS
  'Field legacy. Tidak dipakai untuk transaksi baru karena dana satu kali jalan tidak dipecah.';

-- Tarif owner yang berlaku mulai 15 Juli 2026.
WITH tarif(kode, sewa_per_kg, dana_trip) AS (
  VALUES
    ('SL',     150::numeric, 800000::numeric),
    ('BL',     150::numeric, 750000::numeric),
    ('SL/F',   150::numeric, 750000::numeric),
    ('SL/BS',  150::numeric, 750000::numeric),
    ('SL/MLD', 150::numeric, 750000::numeric),
    ('BL/ML',  180::numeric, 900000::numeric)
)
UPDATE public.master_mitra mm
SET tarif_sewa_angkut_per_kg = tarif.sewa_per_kg,
    dana_operasional_trip = tarif.dana_trip
FROM tarif
WHERE upper(btrim(mm.kode)) = tarif.kode;

INSERT INTO public.fee_owner_mitra_history (
  master_mitra_id,
  fee_per_kg,
  tarif_sewa_angkut_per_kg,
  dana_operasional_trip,
  berlaku_mulai,
  aktif,
  alasan_perubahan
)
SELECT
  mm.id,
  COALESCE(mm.fee_per_kg, 0),
  mm.tarif_sewa_angkut_per_kg,
  mm.dana_operasional_trip,
  DATE '2026-07-15',
  true,
  'Tarif Armada CB berdasarkan konfirmasi owner 15 Juli 2026'
FROM public.master_mitra mm
WHERE upper(btrim(mm.kode)) IN ('SL', 'BL', 'SL/F', 'SL/BS', 'SL/MLD', 'BL/ML')
ON CONFLICT (master_mitra_id, berlaku_mulai) DO UPDATE
SET tarif_sewa_angkut_per_kg = EXCLUDED.tarif_sewa_angkut_per_kg,
    dana_operasional_trip = EXCLUDED.dana_operasional_trip,
    aktif = true,
    alasan_perubahan = EXCLUDED.alasan_perubahan;

-- Sumber kebenaran snapshot Armada CB untuk semua jalur insert/edit.
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
BEGIN
  SELECT * INTO v_sopir
  FROM public.sopir
  WHERE id = NEW.sopir_id;

  v_is_armada_cb := COALESCE(v_sopir.is_armada_cb, false);
  NEW.pakai_sewa_armada_bl := v_is_armada_cb;

  IF NEW.mitra_id IS NOT NULL THEN
    SELECT
      COALESCE(h.tarif_sewa_angkut_per_kg, mm.tarif_sewa_angkut_per_kg, 0),
      COALESCE(h.dana_operasional_trip, mm.dana_operasional_trip, 0)
    INTO v_tarif_sewa_mitra, v_dana_trip
    FROM public.master_mitra mm
    LEFT JOIN LATERAL (
      SELECT fh.tarif_sewa_angkut_per_kg, fh.dana_operasional_trip
      FROM public.fee_owner_mitra_history fh
      WHERE fh.master_mitra_id = mm.id
        AND fh.aktif = true
        AND fh.berlaku_mulai <= NEW.tanggal
        AND (fh.berlaku_sampai IS NULL OR fh.berlaku_sampai >= NEW.tanggal)
      ORDER BY fh.berlaku_mulai DESC, fh.created_at DESC
      LIMIT 1
    ) h ON true
    WHERE mm.id = NEW.mitra_id;
  END IF;

  v_berat_netto := GREATEST(COALESCE(NEW.berat_netto_pabrik_kg, NEW.tonase, 0), 0);
  v_tarif_sewa := GREATEST(COALESCE(
    NULLIF(NEW.tarif_sewa_angkut_per_kg_snapshot, 0),
    NULLIF(NEW.biaya_sewa_armada_per_kg, 0),
    v_tarif_sewa_mitra,
    0
  ), 0);

  IF v_is_armada_cb THEN
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

  v_refresh_snapshot := TG_OP = 'INSERT';
  IF TG_OP = 'UPDATE' THEN
    v_refresh_snapshot := OLD.biaya_sopir_dibayar_at IS NULL
      AND (
        OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
        OR OLD.mitra_id IS DISTINCT FROM NEW.mitra_id
        OR OLD.tanggal IS DISTINCT FROM NEW.tanggal
      );
  END IF;

  IF v_refresh_snapshot THEN
    IF v_is_armada_cb THEN
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
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS normalize_armada_cb ON public.transaksi_mitra;
CREATE TRIGGER normalize_armada_cb
  BEFORE INSERT OR UPDATE OF
    tanggal,
    sopir_id,
    mitra_id,
    berat_netto_pabrik_kg,
    tonase,
    tarif_sewa_angkut_per_kg_snapshot,
    biaya_sewa_armada_per_kg,
    pakai_sewa_armada_bl
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
  IF NEW.status = 'dibatalkan' THEN
    IF NEW.tagihan_sopir_ledger_id IS NOT NULL
       AND NEW.biaya_sopir_dibayar_at IS NULL THEN
      UPDATE public.hutang_ledger
      SET status = 'dibatalkan',
          alasan_batal = COALESCE(NEW.alasan_batal, 'Pengiriman dibatalkan'),
          dibatalkan_at = now(),
          dibatalkan_by = COALESCE(NEW.dibatalkan_by, v_actor)
      WHERE id = NEW.tagihan_sopir_ledger_id
        AND status = 'aktif';
    END IF;
    RETURN NEW;
  END IF;

  v_nominal := GREATEST(COALESCE(
    NULLIF(NEW.dana_operasional_trip_snapshot, 0),
    NEW.total_biaya_sopir_cb_snapshot,
    0
  ), 0);

  IF NOT NEW.pakai_sewa_armada_bl OR v_nominal <= 0 THEN
    RETURN NEW;
  END IF;

  IF NEW.tagihan_sopir_ledger_id IS NOT NULL THEN
    IF NEW.biaya_sopir_dibayar_at IS NULL THEN
      UPDATE public.hutang_ledger
      SET sumber = 'operasional',
          jumlah = v_nominal,
          keterangan = format(
            'Dana operasional trip Armada CB %s tanggal %s',
            COALESCE(NEW.plat_nomor, '-'),
            NEW.tanggal
          ),
          updated_at = now()
      WHERE id = NEW.tagihan_sopir_ledger_id
        AND status = 'aktif';
    END IF;
    RETURN NEW;
  END IF;

  SELECT * INTO v_tagihan
  FROM public.hutang_ledger
  WHERE legacy_source_table = 'tagihan_sopir_cb'
    AND legacy_source_id = NEW.id
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
      NEW.tanggal,
      'debit',
      'operasional',
      v_nominal,
      'tagihan_sopir_cb',
      NEW.id,
      format('Dana operasional trip Armada CB %s tanggal %s', COALESCE(NEW.plat_nomor, '-'), NEW.tanggal),
      v_actor
    )
    RETURNING * INTO v_tagihan;
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
    status,
    dana_operasional_trip_snapshot,
    total_biaya_sopir_cb_snapshot,
    tagihan_sopir_ledger_id
  ON public.transaksi_mitra
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_tagihan_sopir_cb();

CREATE OR REPLACE FUNCTION public.bayar_tagihan_sopir_cb(
  p_transaksi_mitra_id uuid,
  p_tanggal_bayar date DEFAULT NULL,
  p_rekening_kas_id uuid DEFAULT NULL
)
RETURNS public.transaksi_mitra
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_transaksi public.transaksi_mitra%ROWTYPE;
  v_tagihan public.hutang_ledger%ROWTYPE;
  v_pelunasan public.hutang_ledger%ROWTYPE;
  v_biaya public.biaya_operasional%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
  v_rekening_id uuid := p_rekening_kas_id;
  v_tanggal date := COALESCE(p_tanggal_bayar, (now() AT TIME ZONE 'Asia/Jakarta')::date);
  v_nominal numeric(15,2) := 0;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang membayar dana operasional trip.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_transaksi
  FROM public.transaksi_mitra
  WHERE id = p_transaksi_mitra_id
  FOR UPDATE;

  IF v_transaksi.id IS NULL THEN
    RAISE EXCEPTION 'Pengiriman tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF v_transaksi.status <> 'aktif' THEN
    RAISE EXCEPTION 'Pengiriman sudah dibatalkan.' USING ERRCODE = '22023';
  END IF;
  IF NOT v_transaksi.pakai_sewa_armada_bl THEN
    RAISE EXCEPTION 'Pengiriman ini bukan Armada CB.' USING ERRCODE = '22023';
  END IF;

  v_nominal := GREATEST(COALESCE(
    NULLIF(v_transaksi.dana_operasional_trip_snapshot, 0),
    v_transaksi.total_biaya_sopir_cb_snapshot,
    0
  ), 0);
  IF v_nominal <= 0 THEN
    RAISE EXCEPTION 'Dana operasional trip belum diatur untuk mitra ini.' USING ERRCODE = '22023';
  END IF;
  IF v_transaksi.biaya_sopir_dibayar_at IS NOT NULL
     OR v_transaksi.tagihan_sopir_bayar_ledger_id IS NOT NULL THEN
    RAISE EXCEPTION 'Dana operasional trip ini sudah dibayar.' USING ERRCODE = '23505';
  END IF;

  SELECT * INTO v_tagihan
  FROM public.hutang_ledger
  WHERE id = v_transaksi.tagihan_sopir_ledger_id
  FOR UPDATE;

  IF v_tagihan.id IS NULL OR v_tagihan.status <> 'aktif' THEN
    RAISE EXCEPTION 'Tagihan dana operasional trip tidak ditemukan atau sudah tidak aktif.' USING ERRCODE = 'P0002';
  END IF;

  IF v_rekening_id IS NULL THEN
    v_rekening_id := public.get_default_rekening_kas_id();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.rekening_kas WHERE id = v_rekening_id AND aktif = true) THEN
    RAISE EXCEPTION 'Rekening kas tidak ditemukan atau tidak aktif.' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.biaya_operasional (
    tanggal, kategori, jumlah, keterangan, tipe_biaya, status,
    rekening_kas_id, armada_sopir_id, transaksi_mitra_id, created_by
  ) VALUES (
    v_tanggal,
    'dana_operasional_trip',
    v_nominal,
    format(
      'Dana operasional trip %s, Armada CB %s, pengiriman %s',
      COALESCE(v_transaksi.sopir_aktual_nama, v_transaksi.sopir_default_nama, '-'),
      COALESCE(v_transaksi.plat_nomor, '-'),
      v_transaksi.tanggal
    ),
    'perusahaan_murni',
    'aktif',
    v_rekening_id,
    v_transaksi.sopir_id,
    v_transaksi.id,
    v_actor
  ) RETURNING * INTO v_biaya;

  INSERT INTO public.kas_ledger (
    rekening_kas_id, tanggal, tipe, sumber, jumlah, biaya_operasional_id,
    source_table, source_id, idempotency_key, keterangan, created_by
  ) VALUES (
    v_rekening_id,
    v_tanggal,
    'keluar',
    'biaya_operasional',
    v_nominal,
    v_biaya.id,
    'transaksi_mitra',
    v_transaksi.id,
    'tagihan_sopir_cb:' || v_transaksi.id::text,
    v_biaya.keterangan,
    v_actor
  ) RETURNING * INTO v_kas;

  UPDATE public.biaya_operasional
  SET kas_ledger_id = v_kas.id
  WHERE id = v_biaya.id
  RETURNING * INTO v_biaya;

  INSERT INTO public.hutang_ledger (
    pihak_type, petani_id, mitra_id, master_mitra_id, sopir_id, pihak_nama_manual,
    tanggal, tipe, sumber, jumlah, legacy_source_table, legacy_source_id,
    keterangan, rekening_kas_id, kas_ledger_id, created_by
  ) VALUES (
    v_tagihan.pihak_type,
    v_tagihan.petani_id,
    v_tagihan.mitra_id,
    v_tagihan.master_mitra_id,
    v_tagihan.sopir_id,
    v_tagihan.pihak_nama_manual,
    v_tanggal,
    'kredit',
    'bayar_tunai',
    v_tagihan.jumlah,
    'pembayaran_tagihan_sopir_cb',
    v_tagihan.id,
    format('Pembayaran dana operasional trip Armada CB %s', COALESCE(v_transaksi.plat_nomor, '-')),
    v_rekening_id,
    v_kas.id,
    v_actor
  ) RETURNING * INTO v_pelunasan;

  UPDATE public.kas_ledger SET hutang_ledger_id = v_pelunasan.id WHERE id = v_kas.id;

  UPDATE public.transaksi_mitra
  SET tagihan_sopir_bayar_ledger_id = v_pelunasan.id,
      biaya_sopir_operasional_id = v_biaya.id,
      biaya_sopir_dibayar_at = now()
  WHERE id = v_transaksi.id
  RETURNING * INTO v_transaksi;

  RETURN v_transaksi;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_dana_operasional_trip_mitra(
  p_mitra_id uuid,
  p_tanggal date
)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT GREATEST(COALESCE(
    (
      SELECT fh.dana_operasional_trip
      FROM public.fee_owner_mitra_history fh
      WHERE fh.master_mitra_id = p_mitra_id
        AND fh.aktif = true
        AND fh.berlaku_mulai <= p_tanggal
        AND (fh.berlaku_sampai IS NULL OR fh.berlaku_sampai >= p_tanggal)
      ORDER BY fh.berlaku_mulai DESC, fh.created_at DESC
      LIMIT 1
    ),
    (SELECT mm.dana_operasional_trip FROM public.master_mitra mm WHERE mm.id = p_mitra_id),
    0
  ), 0);
$$;

-- Nama RPC lama dipertahankan agar klien lama tetap bekerja, tetapi isinya kini
-- menerapkan Dana Operasional Trip berdasarkan Mitra Transaksi dan tanggal.
CREATE OR REPLACE FUNCTION public.sync_tarif_sopir_cb_period(
  p_date_from date,
  p_date_to date,
  p_armada_sopir_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_updated_count integer := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Tidak berwenang menyelaraskan dana operasional trip.' USING ERRCODE = '42501';
  END IF;
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Periode tidak valid.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.transaksi_mitra tm
  SET dana_operasional_trip_snapshot = public.resolve_dana_operasional_trip_mitra(tm.mitra_id, tm.tanggal),
      upah_sopir_cb_snapshot = 0,
      uang_jalan_sopir_cb_snapshot = 0,
      total_biaya_sopir_cb_snapshot = public.resolve_dana_operasional_trip_mitra(tm.mitra_id, tm.tanggal)
  FROM public.sopir s
  WHERE tm.sopir_id = s.id
    AND s.is_armada_cb = true
    AND tm.status = 'aktif'
    AND tm.biaya_sopir_dibayar_at IS NULL
    AND tm.tanggal BETWEEN p_date_from AND p_date_to
    AND (p_armada_sopir_id IS NULL OR tm.sopir_id = p_armada_sopir_id);

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  RETURN jsonb_build_object('updated_count', v_updated_count);
END;
$$;

-- Backfill hanya trip aktif yang belum dibayar. Trip yang sudah dibayar tetap beku.
UPDATE public.transaksi_mitra tm
SET dana_operasional_trip_snapshot = public.resolve_dana_operasional_trip_mitra(tm.mitra_id, tm.tanggal),
    upah_sopir_cb_snapshot = 0,
    uang_jalan_sopir_cb_snapshot = 0,
    total_biaya_sopir_cb_snapshot = public.resolve_dana_operasional_trip_mitra(tm.mitra_id, tm.tanggal)
FROM public.sopir s
WHERE tm.sopir_id = s.id
  AND s.is_armada_cb = true
  AND tm.status = 'aktif'
  AND tm.biaya_sopir_dibayar_at IS NULL;

REVOKE ALL ON FUNCTION public.normalize_transaksi_mitra_armada_cb() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_tagihan_sopir_cb() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resolve_dana_operasional_trip_mitra(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bayar_tagihan_sopir_cb(uuid, date, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bayar_tagihan_sopir_cb(uuid, date, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.sync_tarif_sopir_cb_period(date, date, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_tarif_sopir_cb_period(date, date, uuid) TO authenticated;

COMMIT;
