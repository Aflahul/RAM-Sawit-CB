-- Armada CB: koreksi sewa, snapshot biaya sopir, tagihan, dan pembayaran tunai.
-- Non-destruktif: field legacy tetap dipertahankan untuk kompatibilitas.

BEGIN;

-- ---------------------------------------------------------------------------
-- Master tarif dan snapshot transaksi
-- ---------------------------------------------------------------------------

ALTER TABLE public.sopir
  ADD COLUMN IF NOT EXISTS upah_sopir_per_trip_override numeric(15,2),
  ADD COLUMN IF NOT EXISTS uang_jalan_per_trip_override numeric(15,2);

ALTER TABLE public.transaksi_mitra
  ADD COLUMN IF NOT EXISTS upah_sopir_cb_snapshot numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS uang_jalan_sopir_cb_snapshot numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_biaya_sopir_cb_snapshot numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tagihan_sopir_ledger_id uuid,
  ADD COLUMN IF NOT EXISTS tagihan_sopir_bayar_ledger_id uuid,
  ADD COLUMN IF NOT EXISTS biaya_sopir_operasional_id uuid,
  ADD COLUMN IF NOT EXISTS biaya_sopir_dibayar_at timestamptz;

ALTER TABLE public.biaya_operasional
  ADD COLUMN IF NOT EXISTS armada_sopir_id uuid,
  ADD COLUMN IF NOT EXISTS transaksi_mitra_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sopir_upah_per_trip_nonnegative'
      AND conrelid = 'public.sopir'::regclass
  ) THEN
    ALTER TABLE public.sopir
      ADD CONSTRAINT sopir_upah_per_trip_nonnegative
      CHECK (upah_sopir_per_trip_override IS NULL OR upah_sopir_per_trip_override >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'sopir_uang_jalan_per_trip_nonnegative'
      AND conrelid = 'public.sopir'::regclass
  ) THEN
    ALTER TABLE public.sopir
      ADD CONSTRAINT sopir_uang_jalan_per_trip_nonnegative
      CHECK (uang_jalan_per_trip_override IS NULL OR uang_jalan_per_trip_override >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transaksi_mitra_biaya_sopir_nonnegative'
      AND conrelid = 'public.transaksi_mitra'::regclass
  ) THEN
    ALTER TABLE public.transaksi_mitra
      ADD CONSTRAINT transaksi_mitra_biaya_sopir_nonnegative
      CHECK (
        upah_sopir_cb_snapshot >= 0
        AND uang_jalan_sopir_cb_snapshot >= 0
        AND total_biaya_sopir_cb_snapshot >= 0
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transaksi_mitra_tagihan_sopir_ledger_id_fkey'
      AND conrelid = 'public.transaksi_mitra'::regclass
  ) THEN
    ALTER TABLE public.transaksi_mitra
      ADD CONSTRAINT transaksi_mitra_tagihan_sopir_ledger_id_fkey
      FOREIGN KEY (tagihan_sopir_ledger_id) REFERENCES public.hutang_ledger(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transaksi_mitra_tagihan_sopir_bayar_ledger_id_fkey'
      AND conrelid = 'public.transaksi_mitra'::regclass
  ) THEN
    ALTER TABLE public.transaksi_mitra
      ADD CONSTRAINT transaksi_mitra_tagihan_sopir_bayar_ledger_id_fkey
      FOREIGN KEY (tagihan_sopir_bayar_ledger_id) REFERENCES public.hutang_ledger(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transaksi_mitra_biaya_sopir_operasional_id_fkey'
      AND conrelid = 'public.transaksi_mitra'::regclass
  ) THEN
    ALTER TABLE public.transaksi_mitra
      ADD CONSTRAINT transaksi_mitra_biaya_sopir_operasional_id_fkey
      FOREIGN KEY (biaya_sopir_operasional_id) REFERENCES public.biaya_operasional(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'biaya_operasional_armada_sopir_id_fkey'
      AND conrelid = 'public.biaya_operasional'::regclass
  ) THEN
    ALTER TABLE public.biaya_operasional
      ADD CONSTRAINT biaya_operasional_armada_sopir_id_fkey
      FOREIGN KEY (armada_sopir_id) REFERENCES public.sopir(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'biaya_operasional_transaksi_mitra_id_fkey'
      AND conrelid = 'public.biaya_operasional'::regclass
  ) THEN
    ALTER TABLE public.biaya_operasional
      ADD CONSTRAINT biaya_operasional_transaksi_mitra_id_fkey
      FOREIGN KEY (transaksi_mitra_id) REFERENCES public.transaksi_mitra(id);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_sopir_armada_cb_aktif
  ON public.sopir (aktif, nama)
  WHERE is_armada_cb = true;

CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_tagihan_sopir
  ON public.transaksi_mitra (tagihan_sopir_ledger_id)
  WHERE tagihan_sopir_ledger_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_biaya_sopir
  ON public.transaksi_mitra (biaya_sopir_operasional_id)
  WHERE biaya_sopir_operasional_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_biaya_operasional_armada_tanggal
  ON public.biaya_operasional (armada_sopir_id, tanggal DESC)
  WHERE armada_sopir_id IS NOT NULL AND status <> 'dibatalkan';

CREATE INDEX IF NOT EXISTS idx_biaya_operasional_transaksi_mitra
  ON public.biaya_operasional (transaksi_mitra_id)
  WHERE transaksi_mitra_id IS NOT NULL;

INSERT INTO public.pengaturan_bisnis (key, value_json, scope, aktif)
SELECT
  'armada_cb_biaya_sopir',
  '{"upah_sopir_per_trip":0,"uang_jalan_per_trip":0}'::jsonb,
  'global',
  true
WHERE NOT EXISTS (
  SELECT 1
  FROM public.pengaturan_bisnis
  WHERE key = 'armada_cb_biaya_sopir'
    AND scope = 'global'
    AND aktif = true
);

COMMENT ON COLUMN public.sopir.upah_sopir_per_trip_override IS
  'Tarif upah per trip khusus unit ini. NULL berarti memakai pengaturan global Armada CB.';
COMMENT ON COLUMN public.sopir.uang_jalan_per_trip_override IS
  'Uang jalan per trip khusus unit ini. NULL berarti memakai pengaturan global Armada CB.';
COMMENT ON COLUMN public.transaksi_mitra.nominal_perongkosan_snapshot IS
  'Field legacy. Tidak digunakan sebagai pengurang sewa Armada CB; uang jalan disimpan di uang_jalan_sopir_cb_snapshot.';
COMMENT ON COLUMN public.transaksi_mitra.total_biaya_sopir_cb_snapshot IS
  'Upah flat per trip ditambah uang jalan untuk trip Armada CB.';

-- ---------------------------------------------------------------------------
-- Koreksi P0: sewa Armada CB tidak dikurangi uang jalan/perongkosan.
-- ---------------------------------------------------------------------------

UPDATE public.transaksi_mitra
SET biaya_sewa_armada_kotor = CASE
      WHEN COALESCE(berat_netto_pabrik_kg, tonase, 0) > 0
       AND COALESCE(tarif_sewa_angkut_per_kg_snapshot, biaya_sewa_armada_per_kg, 0) > 0
        THEN round(
          COALESCE(berat_netto_pabrik_kg, tonase, 0)
          * COALESCE(tarif_sewa_angkut_per_kg_snapshot, biaya_sewa_armada_per_kg, 0)
        )
      ELSE COALESCE(biaya_sewa_armada_kotor, biaya_sewa_armada_total, 0)
    END,
    biaya_sewa_armada_total = CASE
      WHEN COALESCE(berat_netto_pabrik_kg, tonase, 0) > 0
       AND COALESCE(tarif_sewa_angkut_per_kg_snapshot, biaya_sewa_armada_per_kg, 0) > 0
        THEN round(
          COALESCE(berat_netto_pabrik_kg, tonase, 0)
          * COALESCE(tarif_sewa_angkut_per_kg_snapshot, biaya_sewa_armada_per_kg, 0)
        )
      ELSE COALESCE(biaya_sewa_armada_kotor, biaya_sewa_armada_total, 0)
    END
WHERE pakai_sewa_armada_bl = true;

-- Trigger ini menjadi pagar konsistensi untuk insert/edit dari semua halaman.
CREATE OR REPLACE FUNCTION public.normalize_transaksi_mitra_armada_cb()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sopir public.sopir%ROWTYPE;
  v_settings jsonb := '{}'::jsonb;
  v_is_armada_cb boolean := false;
  v_berat_netto numeric(15,2) := 0;
  v_tarif_sewa numeric(15,2) := 0;
  v_upah numeric(15,2) := 0;
  v_uang_jalan numeric(15,2) := 0;
  v_refresh_snapshot boolean := false;
BEGIN
  SELECT * INTO v_sopir
  FROM public.sopir
  WHERE id = NEW.sopir_id;

  v_is_armada_cb := COALESCE(v_sopir.is_armada_cb, false);
  NEW.pakai_sewa_armada_bl := v_is_armada_cb;

  v_berat_netto := GREATEST(COALESCE(NEW.berat_netto_pabrik_kg, NEW.tonase, 0), 0);
  v_tarif_sewa := GREATEST(COALESCE(
    NEW.tarif_sewa_angkut_per_kg_snapshot,
    NEW.biaya_sewa_armada_per_kg,
    0
  ), 0);

  IF v_is_armada_cb THEN
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
    v_refresh_snapshot := OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
      AND OLD.biaya_sopir_dibayar_at IS NULL;
  END IF;

  IF v_refresh_snapshot THEN
    SELECT value_json INTO v_settings
    FROM public.pengaturan_bisnis
    WHERE key = 'armada_cb_biaya_sopir'
      AND scope = 'global'
      AND aktif = true
    ORDER BY berlaku_mulai DESC NULLS LAST, updated_at DESC NULLS LAST
    LIMIT 1;

    IF v_is_armada_cb THEN
      v_upah := GREATEST(COALESCE(
        v_sopir.upah_sopir_per_trip_override,
        (v_settings ->> 'upah_sopir_per_trip')::numeric,
        0
      ), 0);
      v_uang_jalan := GREATEST(COALESCE(
        v_sopir.uang_jalan_per_trip_override,
        (v_settings ->> 'uang_jalan_per_trip')::numeric,
        0
      ), 0);

      NEW.upah_sopir_cb_snapshot := v_upah;
      NEW.uang_jalan_sopir_cb_snapshot := v_uang_jalan;
      NEW.total_biaya_sopir_cb_snapshot := v_upah + v_uang_jalan;
      NEW.nominal_perongkosan_snapshot := 0;
    ELSE
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
    sopir_id,
    berat_netto_pabrik_kg,
    tonase,
    tarif_sewa_angkut_per_kg_snapshot,
    biaya_sewa_armada_per_kg,
    pakai_sewa_armada_bl
  ON public.transaksi_mitra
  FOR EACH ROW
  EXECUTE FUNCTION public.normalize_transaksi_mitra_armada_cb();

-- ---------------------------------------------------------------------------
-- Tagihan sopir otomatis, tetapi kas belum berkurang.
-- ---------------------------------------------------------------------------

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

  IF NOT NEW.pakai_sewa_armada_bl
     OR COALESCE(NEW.total_biaya_sopir_cb_snapshot, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  IF NEW.tagihan_sopir_ledger_id IS NOT NULL THEN
    IF NEW.biaya_sopir_dibayar_at IS NULL THEN
      UPDATE public.hutang_ledger
      SET jumlah = NEW.total_biaya_sopir_cb_snapshot,
          keterangan = format(
            'Trip Armada CB %s: upah %s + uang jalan %s',
            COALESCE(NEW.plat_nomor, '-'),
            NEW.upah_sopir_cb_snapshot,
            NEW.uang_jalan_sopir_cb_snapshot
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
      pihak_type,
      sopir_id,
      pihak_nama_manual,
      tanggal,
      tipe,
      sumber,
      jumlah,
      legacy_source_table,
      legacy_source_id,
      keterangan,
      created_by
    ) VALUES (
      v_pihak_type,
      CASE WHEN v_pihak_type = 'sopir' THEN v_sopir_aktual_id ELSE NULL END,
      CASE WHEN v_pihak_type = 'lainnya' THEN COALESCE(v_pihak_nama, 'Sopir pengganti') ELSE NULL END,
      NEW.tanggal,
      'debit',
      'gaji',
      NEW.total_biaya_sopir_cb_snapshot,
      'tagihan_sopir_cb',
      NEW.id,
      format(
        'Trip Armada CB %s: upah %s + uang jalan %s',
        COALESCE(NEW.plat_nomor, '-'),
        NEW.upah_sopir_cb_snapshot,
        NEW.uang_jalan_sopir_cb_snapshot
      ),
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
    total_biaya_sopir_cb_snapshot,
    upah_sopir_cb_snapshot,
    uang_jalan_sopir_cb_snapshot,
    tagihan_sopir_ledger_id
  ON public.transaksi_mitra
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_tagihan_sopir_cb();

-- ---------------------------------------------------------------------------
-- Bayar Tunai Sopir: tagihan lunas, biaya dan kas keluar tercatat atomik.
-- ---------------------------------------------------------------------------

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
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang membayar tagihan sopir.' USING ERRCODE = '42501';
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
  IF COALESCE(v_transaksi.total_biaya_sopir_cb_snapshot, 0) <= 0 THEN
    RAISE EXCEPTION 'Upah dan uang jalan belum diatur untuk trip ini.' USING ERRCODE = '22023';
  END IF;
  IF v_transaksi.biaya_sopir_dibayar_at IS NOT NULL
     OR v_transaksi.tagihan_sopir_bayar_ledger_id IS NOT NULL THEN
    RAISE EXCEPTION 'Tagihan sopir untuk trip ini sudah dibayar.' USING ERRCODE = '23505';
  END IF;

  SELECT * INTO v_tagihan
  FROM public.hutang_ledger
  WHERE id = v_transaksi.tagihan_sopir_ledger_id
  FOR UPDATE;

  IF v_tagihan.id IS NULL OR v_tagihan.status <> 'aktif' THEN
    RAISE EXCEPTION 'Tagihan sopir tidak ditemukan atau sudah tidak aktif.' USING ERRCODE = 'P0002';
  END IF;

  IF v_rekening_id IS NULL THEN
    v_rekening_id := public.get_default_rekening_kas_id();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.rekening_kas
    WHERE id = v_rekening_id AND aktif = true
  ) THEN
    RAISE EXCEPTION 'Rekening kas tidak ditemukan atau tidak aktif.' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.biaya_operasional (
    tanggal,
    kategori,
    jumlah,
    keterangan,
    tipe_biaya,
    status,
    rekening_kas_id,
    armada_sopir_id,
    transaksi_mitra_id,
    created_by
  ) VALUES (
    v_tanggal,
    'gaji_sopir',
    v_transaksi.total_biaya_sopir_cb_snapshot,
    format(
      'Sopir %s, Armada CB %s, trip %s',
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
  )
  RETURNING * INTO v_biaya;

  INSERT INTO public.kas_ledger (
    rekening_kas_id,
    tanggal,
    tipe,
    sumber,
    jumlah,
    biaya_operasional_id,
    source_table,
    source_id,
    idempotency_key,
    keterangan,
    created_by
  ) VALUES (
    v_rekening_id,
    v_tanggal,
    'keluar',
    'biaya_operasional',
    v_transaksi.total_biaya_sopir_cb_snapshot,
    v_biaya.id,
    'transaksi_mitra',
    v_transaksi.id,
    'tagihan_sopir_cb:' || v_transaksi.id::text,
    v_biaya.keterangan,
    v_actor
  )
  RETURNING * INTO v_kas;

  UPDATE public.biaya_operasional
  SET kas_ledger_id = v_kas.id
  WHERE id = v_biaya.id
  RETURNING * INTO v_biaya;

  INSERT INTO public.hutang_ledger (
    pihak_type,
    petani_id,
    mitra_id,
    master_mitra_id,
    sopir_id,
    pihak_nama_manual,
    tanggal,
    tipe,
    sumber,
    jumlah,
    legacy_source_table,
    legacy_source_id,
    keterangan,
    rekening_kas_id,
    kas_ledger_id,
    created_by
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
    format('Pembayaran tunai trip Armada CB %s', COALESCE(v_transaksi.plat_nomor, '-')),
    v_rekening_id,
    v_kas.id,
    v_actor
  )
  RETURNING * INTO v_pelunasan;

  UPDATE public.kas_ledger
  SET hutang_ledger_id = v_pelunasan.id
  WHERE id = v_kas.id;

  UPDATE public.transaksi_mitra
  SET tagihan_sopir_bayar_ledger_id = v_pelunasan.id,
      biaya_sopir_operasional_id = v_biaya.id,
      biaya_sopir_dibayar_at = now()
  WHERE id = v_transaksi.id
  RETURNING * INTO v_transaksi;

  RETURN v_transaksi;
END;
$$;

-- Biaya seperti oli/solar dapat diarahkan ke satu Armada CB untuk laporan margin.
CREATE OR REPLACE FUNCTION public.create_biaya_operasional_armada_kas(
  p_tanggal date,
  p_kategori text,
  p_jumlah numeric,
  p_armada_sopir_id uuid,
  p_keterangan text DEFAULT NULL,
  p_rekening_kas_id uuid DEFAULT NULL
)
RETURNS public.biaya_operasional
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_biaya public.biaya_operasional%ROWTYPE;
BEGIN
  IF p_armada_sopir_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.sopir
    WHERE id = p_armada_sopir_id
      AND aktif = true
      AND is_armada_cb = true
  ) THEN
    RAISE EXCEPTION 'Armada CB tidak ditemukan atau tidak aktif.' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_biaya
  FROM public.create_biaya_operasional_kas(
    p_tanggal,
    p_kategori,
    p_jumlah,
    p_keterangan,
    p_rekening_kas_id
  );

  UPDATE public.biaya_operasional
  SET armada_sopir_id = p_armada_sopir_id
  WHERE id = v_biaya.id
  RETURNING * INTO v_biaya;

  RETURN v_biaya;
END;
$$;

-- Terapkan tarif saat ini ke trip lama yang belum dibayar, atas tindakan owner.
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
  v_settings jsonb := '{}'::jsonb;
  v_updated_count integer := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Tidak berwenang menyinkronkan tarif sopir.' USING ERRCODE = '42501';
  END IF;
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Periode tidak valid.' USING ERRCODE = '22023';
  END IF;

  SELECT value_json INTO v_settings
  FROM public.pengaturan_bisnis
  WHERE key = 'armada_cb_biaya_sopir'
    AND scope = 'global'
    AND aktif = true
  ORDER BY berlaku_mulai DESC NULLS LAST, updated_at DESC NULLS LAST
  LIMIT 1;

  UPDATE public.transaksi_mitra tm
  SET upah_sopir_cb_snapshot = GREATEST(COALESCE(
        s.upah_sopir_per_trip_override,
        (v_settings ->> 'upah_sopir_per_trip')::numeric,
        0
      ), 0),
      uang_jalan_sopir_cb_snapshot = GREATEST(COALESCE(
        s.uang_jalan_per_trip_override,
        (v_settings ->> 'uang_jalan_per_trip')::numeric,
        0
      ), 0),
      total_biaya_sopir_cb_snapshot = GREATEST(COALESCE(
        s.upah_sopir_per_trip_override,
        (v_settings ->> 'upah_sopir_per_trip')::numeric,
        0
      ), 0) + GREATEST(COALESCE(
        s.uang_jalan_per_trip_override,
        (v_settings ->> 'uang_jalan_per_trip')::numeric,
        0
      ), 0)
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

REVOKE ALL ON FUNCTION public.normalize_transaksi_mitra_armada_cb() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.normalize_transaksi_mitra_armada_cb() FROM anon;
REVOKE ALL ON FUNCTION public.normalize_transaksi_mitra_armada_cb() FROM authenticated;

REVOKE ALL ON FUNCTION public.sync_tagihan_sopir_cb() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_tagihan_sopir_cb() FROM anon;
REVOKE ALL ON FUNCTION public.sync_tagihan_sopir_cb() FROM authenticated;

REVOKE ALL ON FUNCTION public.bayar_tagihan_sopir_cb(uuid, date, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bayar_tagihan_sopir_cb(uuid, date, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.bayar_tagihan_sopir_cb(uuid, date, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.create_biaya_operasional_armada_kas(date, text, numeric, uuid, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_biaya_operasional_armada_kas(date, text, numeric, uuid, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_biaya_operasional_armada_kas(date, text, numeric, uuid, text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.sync_tarif_sopir_cb_period(date, date, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_tarif_sopir_cb_period(date, date, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.sync_tarif_sopir_cb_period(date, date, uuid) TO authenticated;

COMMIT;
