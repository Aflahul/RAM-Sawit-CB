-- Sawit CB - Fase 2 kas ledger dan hutang/panjar universal.
-- Non-destruktif: menambah fondasi kas, memperluas hutang_ledger lintas pihak,
-- lalu mengarahkan transaksi uang utama ke RPC agar ledger tercatat atomik.

BEGIN;

-- ---------------------------------------------------------------------------
-- Rekening kas dan kas ledger
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.rekening_kas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama text NOT NULL,
  tipe text NOT NULL DEFAULT 'kas' CHECK (tipe IN ('kas', 'bank', 'e_wallet', 'lainnya')),
  nomor_rekening text,
  pemilik_rekening text,
  saldo_awal numeric(15,2) NOT NULL DEFAULT 0 CHECK (saldo_awal >= 0),
  aktif boolean NOT NULL DEFAULT true,
  is_default boolean NOT NULL DEFAULT false,
  catatan text,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_rekening_kas_default_active
ON public.rekening_kas (is_default)
WHERE is_default = true AND aktif = true;

INSERT INTO public.rekening_kas (nama, tipe, is_default, catatan)
SELECT 'Kas Utama', 'kas', true, 'Rekening kas default Fase 2'
WHERE NOT EXISTS (SELECT 1 FROM public.rekening_kas);

CREATE TABLE IF NOT EXISTS public.kas_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rekening_kas_id uuid NOT NULL REFERENCES public.rekening_kas(id),
  tanggal date NOT NULL,
  tipe text NOT NULL CHECK (tipe IN ('masuk', 'keluar', 'transfer_masuk', 'transfer_keluar', 'koreksi', 'reversal')),
  sumber text NOT NULL CHECK (
    sumber IN (
      'modal_awal',
      'pembayaran_pabrik',
      'pembayaran_mitra',
      'pembayaran_petani',
      'pembelian_tbs',
      'hutang_pencairan',
      'hutang_pelunasan',
      'panjar_mitra',
      'biaya_operasional',
      'transfer_kas',
      'koreksi',
      'reversal',
      'lainnya'
    )
  ),
  jumlah numeric(15,2) NOT NULL CHECK (jumlah > 0),
  status text NOT NULL DEFAULT 'aktif' CHECK (status IN ('aktif', 'dibatalkan', 'reversal')),
  source_table text,
  source_id uuid,
  transaksi_beli_id uuid REFERENCES public.transaksi_beli_tbs(id),
  pengiriman_id uuid REFERENCES public.pengiriman(id),
  pembayaran_pabrik_id uuid REFERENCES public.pembayaran_pabrik(id),
  pembayaran_mitra_kwitansi_id uuid REFERENCES public.pembayaran_mitra_kwitansi(id),
  hutang_ledger_id uuid REFERENCES public.hutang_ledger(id),
  biaya_operasional_id uuid REFERENCES public.biaya_operasional(id),
  panjar_mitra_id uuid,
  reversal_of_id uuid REFERENCES public.kas_ledger(id),
  idempotency_key text,
  keterangan text,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  dibatalkan_at timestamptz,
  dibatalkan_by uuid REFERENCES public.users(id),
  alasan_batal text
);

DO $$
BEGIN
  IF to_regclass('public.panjar_mitra') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM pg_constraint
       WHERE conname = 'kas_ledger_panjar_mitra_id_fkey'
         AND conrelid = 'public.kas_ledger'::regclass
     ) THEN
    ALTER TABLE public.kas_ledger
      ADD CONSTRAINT kas_ledger_panjar_mitra_id_fkey
      FOREIGN KEY (panjar_mitra_id) REFERENCES public.panjar_mitra(id);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_rekening_kas_aktif ON public.rekening_kas (aktif, is_default DESC, nama);
CREATE INDEX IF NOT EXISTS idx_kas_ledger_tanggal ON public.kas_ledger (tanggal DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_kas_ledger_rekening_tanggal ON public.kas_ledger (rekening_kas_id, tanggal DESC);
CREATE INDEX IF NOT EXISTS idx_kas_ledger_source ON public.kas_ledger (source_table, source_id);
CREATE INDEX IF NOT EXISTS idx_kas_ledger_status ON public.kas_ledger (status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_kas_ledger_idempotency_key
ON public.kas_ledger (idempotency_key)
WHERE idempotency_key IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Perluasan hutang ledger menjadi hutang/panjar universal
-- ---------------------------------------------------------------------------

ALTER TABLE public.hutang_ledger
  ADD COLUMN IF NOT EXISTS master_mitra_id uuid,
  ADD COLUMN IF NOT EXISTS sopir_id uuid,
  ADD COLUMN IF NOT EXISTS pihak_nama_manual text,
  ADD COLUMN IF NOT EXISTS pihak_ref_id uuid,
  ADD COLUMN IF NOT EXISTS rekening_kas_id uuid REFERENCES public.rekening_kas(id),
  ADD COLUMN IF NOT EXISTS kas_ledger_id uuid REFERENCES public.kas_ledger(id),
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'aktif',
  ADD COLUMN IF NOT EXISTS reversal_of_id uuid REFERENCES public.hutang_ledger(id),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS alasan_batal text,
  ADD COLUMN IF NOT EXISTS dibatalkan_at timestamptz,
  ADD COLUMN IF NOT EXISTS dibatalkan_by uuid REFERENCES public.users(id);

DO $$
BEGIN
  IF to_regclass('public.master_mitra') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM pg_constraint
       WHERE conname = 'hutang_ledger_master_mitra_id_fkey'
         AND conrelid = 'public.hutang_ledger'::regclass
     ) THEN
    ALTER TABLE public.hutang_ledger
      ADD CONSTRAINT hutang_ledger_master_mitra_id_fkey
      FOREIGN KEY (master_mitra_id) REFERENCES public.master_mitra(id);
  END IF;

  IF to_regclass('public.sopir') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM pg_constraint
       WHERE conname = 'hutang_ledger_sopir_id_fkey'
         AND conrelid = 'public.hutang_ledger'::regclass
     ) THEN
    ALTER TABLE public.hutang_ledger
      ADD CONSTRAINT hutang_ledger_sopir_id_fkey
      FOREIGN KEY (sopir_id) REFERENCES public.sopir(id);
  END IF;
END;
$$;

ALTER TABLE public.hutang_ledger
  DROP CONSTRAINT IF EXISTS hutang_ledger_pihak_check,
  DROP CONSTRAINT IF EXISTS hutang_ledger_pihak_type_check,
  DROP CONSTRAINT IF EXISTS hutang_ledger_sumber_check,
  DROP CONSTRAINT IF EXISTS hutang_ledger_status_check;

ALTER TABLE public.hutang_ledger
  ADD CONSTRAINT hutang_ledger_pihak_type_check
  CHECK (pihak_type IN ('petani', 'mitra', 'sopir', 'karyawan', 'lainnya'));

ALTER TABLE public.hutang_ledger
  ADD CONSTRAINT hutang_ledger_sumber_check
  CHECK (
    sumber IN (
      'kasbon',
      'panjar',
      'pupuk',
      'lainnya',
      'bayar_tunai',
      'potong_tbs',
      'potong_settlement',
      'koreksi',
      'reversal',
      'peminjaman',
      'uang_jalan',
      'gaji',
      'operasional',
      'pembayaran_mitra',
      'pembayaran_petani',
      'pencairan_kas',
      'pelunasan_kas'
    )
  );

ALTER TABLE public.hutang_ledger
  ADD CONSTRAINT hutang_ledger_status_check
  CHECK (status IN ('aktif', 'dibatalkan', 'reversal'));

ALTER TABLE public.hutang_ledger
  ADD CONSTRAINT hutang_ledger_pihak_check
  CHECK (
    (
      pihak_type = 'petani'
      AND petani_id IS NOT NULL
      AND mitra_id IS NULL
      AND master_mitra_id IS NULL
      AND sopir_id IS NULL
    )
    OR (
      pihak_type = 'mitra'
      AND (mitra_id IS NOT NULL OR master_mitra_id IS NOT NULL)
      AND petani_id IS NULL
      AND sopir_id IS NULL
    )
    OR (
      pihak_type = 'sopir'
      AND sopir_id IS NOT NULL
      AND petani_id IS NULL
      AND mitra_id IS NULL
      AND master_mitra_id IS NULL
    )
    OR (
      pihak_type IN ('karyawan', 'lainnya')
      AND NULLIF(btrim(COALESCE(pihak_nama_manual, '')), '') IS NOT NULL
      AND petani_id IS NULL
      AND mitra_id IS NULL
      AND master_mitra_id IS NULL
      AND sopir_id IS NULL
    )
  );

CREATE INDEX IF NOT EXISTS idx_hutang_ledger_master_mitra ON public.hutang_ledger (master_mitra_id);
CREATE INDEX IF NOT EXISTS idx_hutang_ledger_sopir ON public.hutang_ledger (sopir_id);
CREATE INDEX IF NOT EXISTS idx_hutang_ledger_status_tanggal ON public.hutang_ledger (status, tanggal DESC);
CREATE INDEX IF NOT EXISTS idx_hutang_ledger_kas ON public.hutang_ledger (kas_ledger_id);

-- ---------------------------------------------------------------------------
-- Kolom kas pada tabel transaksi yang sudah ada
-- ---------------------------------------------------------------------------

ALTER TABLE IF EXISTS public.transaksi_beli_tbs
  ADD COLUMN IF NOT EXISTS rekening_kas_id uuid REFERENCES public.rekening_kas(id),
  ADD COLUMN IF NOT EXISTS kas_ledger_id uuid REFERENCES public.kas_ledger(id);

ALTER TABLE IF EXISTS public.pengiriman
  ADD COLUMN IF NOT EXISTS pembayaran_pabrik_id uuid REFERENCES public.pembayaran_pabrik(id),
  ADD COLUMN IF NOT EXISTS rekening_kas_id uuid REFERENCES public.rekening_kas(id),
  ADD COLUMN IF NOT EXISTS kas_ledger_id uuid REFERENCES public.kas_ledger(id);

ALTER TABLE IF EXISTS public.pembayaran_pabrik
  ADD COLUMN IF NOT EXISTS rekening_kas_id uuid REFERENCES public.rekening_kas(id),
  ADD COLUMN IF NOT EXISTS kas_ledger_id uuid REFERENCES public.kas_ledger(id);

ALTER TABLE IF EXISTS public.biaya_operasional
  ADD COLUMN IF NOT EXISTS rekening_kas_id uuid REFERENCES public.rekening_kas(id),
  ADD COLUMN IF NOT EXISTS kas_ledger_id uuid REFERENCES public.kas_ledger(id);

ALTER TABLE IF EXISTS public.pembayaran_mitra_kwitansi
  ADD COLUMN IF NOT EXISTS rekening_kas_id uuid REFERENCES public.rekening_kas(id),
  ADD COLUMN IF NOT EXISTS kas_ledger_id uuid REFERENCES public.kas_ledger(id);

ALTER TABLE IF EXISTS public.panjar_mitra
  ADD COLUMN IF NOT EXISTS rekening_kas_id uuid REFERENCES public.rekening_kas(id),
  ADD COLUMN IF NOT EXISTS kas_ledger_id uuid REFERENCES public.kas_ledger(id),
  ADD COLUMN IF NOT EXISTS hutang_ledger_id uuid REFERENCES public.hutang_ledger(id),
  ADD COLUMN IF NOT EXISTS settlement_hutang_ledger_id uuid REFERENCES public.hutang_ledger(id),
  ADD COLUMN IF NOT EXISTS lunas_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_transaksi_beli_tbs_kas ON public.transaksi_beli_tbs (kas_ledger_id);
CREATE INDEX IF NOT EXISTS idx_pengiriman_kas ON public.pengiriman (kas_ledger_id);
CREATE INDEX IF NOT EXISTS idx_pembayaran_pabrik_kas ON public.pembayaran_pabrik (kas_ledger_id);
CREATE INDEX IF NOT EXISTS idx_biaya_operasional_kas ON public.biaya_operasional (kas_ledger_id);
CREATE INDEX IF NOT EXISTS idx_pembayaran_mitra_kwitansi_kas ON public.pembayaran_mitra_kwitansi (kas_ledger_id);
CREATE INDEX IF NOT EXISTS idx_panjar_mitra_kas ON public.panjar_mitra (kas_ledger_id);

-- ---------------------------------------------------------------------------
-- RLS dan privilege
-- ---------------------------------------------------------------------------

ALTER TABLE public.rekening_kas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kas_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "read_finance" ON public.rekening_kas;
DROP POLICY IF EXISTS "write_finance" ON public.rekening_kas;
DROP POLICY IF EXISTS "insert_finance" ON public.rekening_kas;
DROP POLICY IF EXISTS "update_finance" ON public.rekening_kas;
DROP POLICY IF EXISTS "delete_finance" ON public.rekening_kas;

CREATE POLICY "read_finance"
ON public.rekening_kas
FOR SELECT TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));

CREATE POLICY "insert_finance"
ON public.rekening_kas
FOR INSERT TO authenticated
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

CREATE POLICY "update_finance"
ON public.rekening_kas
FOR UPDATE TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

DROP POLICY IF EXISTS "read_finance" ON public.kas_ledger;
DROP POLICY IF EXISTS "insert_finance" ON public.kas_ledger;
DROP POLICY IF EXISTS "update_finance" ON public.kas_ledger;
DROP POLICY IF EXISTS "delete_finance" ON public.kas_ledger;

CREATE POLICY "read_finance"
ON public.kas_ledger
FOR SELECT TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

CREATE POLICY "insert_finance"
ON public.kas_ledger
FOR INSERT TO authenticated
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

CREATE POLICY "update_finance"
ON public.kas_ledger
FOR UPDATE TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

DROP POLICY IF EXISTS "write_finance" ON public.hutang_ledger;
DROP POLICY IF EXISTS "insert_finance" ON public.hutang_ledger;
DROP POLICY IF EXISTS "update_finance" ON public.hutang_ledger;
DROP POLICY IF EXISTS "delete_finance" ON public.hutang_ledger;

CREATE POLICY "insert_finance"
ON public.hutang_ledger
FOR INSERT TO authenticated
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

CREATE POLICY "update_finance"
ON public.hutang_ledger
FOR UPDATE TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

DROP POLICY IF EXISTS "delete_finance" ON public.pembayaran_mitra_kwitansi;
DROP POLICY IF EXISTS "delete_finance" ON public.pembayaran_mitra_kwitansi_item;

GRANT SELECT, INSERT, UPDATE ON public.rekening_kas TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.kas_ledger TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.hutang_ledger TO authenticated;
REVOKE DELETE ON public.rekening_kas FROM authenticated, anon;
REVOKE DELETE ON public.kas_ledger FROM authenticated, anon;
REVOKE DELETE ON public.hutang_ledger FROM authenticated, anon;
REVOKE DELETE ON public.pembayaran_mitra_kwitansi FROM authenticated, anon;
REVOKE DELETE ON public.pembayaran_mitra_kwitansi_item FROM authenticated, anon;

DROP TRIGGER IF EXISTS set_updated_at ON public.rekening_kas;
CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.rekening_kas
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at ON public.kas_ledger;
CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.kas_ledger
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at ON public.hutang_ledger;
CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.hutang_ledger
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Helper kas
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_default_rekening_kas_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rekening_id uuid;
BEGIN
  SELECT id
  INTO v_rekening_id
  FROM public.rekening_kas
  WHERE aktif = true
  ORDER BY is_default DESC, created_at ASC
  LIMIT 1;

  IF v_rekening_id IS NULL THEN
    INSERT INTO public.rekening_kas (nama, tipe, is_default, catatan, created_by)
    VALUES ('Kas Utama', 'kas', true, 'Dibuat otomatis saat transaksi kas pertama', auth.uid())
    RETURNING id INTO v_rekening_id;
  END IF;

  RETURN v_rekening_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_kas_mutasi(
  p_tanggal date,
  p_tipe text,
  p_sumber text,
  p_jumlah numeric,
  p_rekening_kas_id uuid DEFAULT NULL,
  p_keterangan text DEFAULT NULL,
  p_source_table text DEFAULT NULL,
  p_source_id uuid DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
)
RETURNS public.kas_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_rekening_id uuid := p_rekening_kas_id;
  v_existing public.kas_ledger%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat mutasi kas.'
      USING ERRCODE = '42501';
  END IF;

  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
    RAISE EXCEPTION 'Jumlah mutasi kas harus lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF p_tipe NOT IN ('masuk', 'keluar', 'transfer_masuk', 'transfer_keluar', 'koreksi', 'reversal') THEN
    RAISE EXCEPTION 'Tipe mutasi kas tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  IF p_sumber NOT IN (
    'modal_awal',
    'pembayaran_pabrik',
    'pembayaran_mitra',
    'pembayaran_petani',
    'pembelian_tbs',
    'hutang_pencairan',
    'hutang_pelunasan',
    'panjar_mitra',
    'biaya_operasional',
    'transfer_kas',
    'koreksi',
    'reversal',
    'lainnya'
  ) THEN
    RAISE EXCEPTION 'Sumber mutasi kas tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT *
    INTO v_existing
    FROM public.kas_ledger
    WHERE idempotency_key = p_idempotency_key
      AND status <> 'dibatalkan'
    LIMIT 1;

    IF v_existing.id IS NOT NULL THEN
      RETURN v_existing;
    END IF;
  END IF;

  IF v_rekening_id IS NULL THEN
    v_rekening_id := public.get_default_rekening_kas_id();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.rekening_kas WHERE id = v_rekening_id AND aktif = true
  ) THEN
    RAISE EXCEPTION 'Rekening kas tidak ditemukan atau tidak aktif.'
      USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.kas_ledger (
    rekening_kas_id,
    tanggal,
    tipe,
    sumber,
    jumlah,
    source_table,
    source_id,
    idempotency_key,
    keterangan,
    created_by
  )
  VALUES (
    v_rekening_id,
    COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    p_tipe,
    p_sumber,
    round(p_jumlah, 2),
    NULLIF(btrim(COALESCE(p_source_table, '')), ''),
    p_source_id,
    NULLIF(btrim(COALESCE(p_idempotency_key, '')), ''),
    NULLIF(btrim(COALESCE(p_keterangan, '')), ''),
    v_actor
  )
  RETURNING * INTO v_kas;

  RETURN v_kas;
END;
$$;

-- ---------------------------------------------------------------------------
-- Hutang/panjar universal
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_hutang_pihak(
  p_pihak_type text,
  p_tipe text,
  p_sumber text,
  p_jumlah numeric,
  p_tanggal date DEFAULT NULL,
  p_petani_id uuid DEFAULT NULL,
  p_master_mitra_id uuid DEFAULT NULL,
  p_sopir_id uuid DEFAULT NULL,
  p_pihak_nama_manual text DEFAULT NULL,
  p_keterangan text DEFAULT NULL,
  p_rekening_kas_id uuid DEFAULT NULL,
  p_catat_kas boolean DEFAULT true,
  p_legacy_source_table text DEFAULT NULL,
  p_legacy_source_id uuid DEFAULT NULL
)
RETURNS public.hutang_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_tanggal date := COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date);
  v_hutang public.hutang_ledger%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
  v_kas_tipe text;
  v_kas_sumber text;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat hutang/panjar.'
      USING ERRCODE = '42501';
  END IF;

  IF p_pihak_type NOT IN ('petani', 'mitra', 'sopir', 'karyawan', 'lainnya') THEN
    RAISE EXCEPTION 'Jenis pihak hutang tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  IF p_tipe NOT IN ('debit', 'kredit') THEN
    RAISE EXCEPTION 'Tipe hutang harus debit atau kredit.'
      USING ERRCODE = '22023';
  END IF;

  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
    RAISE EXCEPTION 'Jumlah hutang/panjar harus lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF p_pihak_type = 'petani' AND p_petani_id IS NULL THEN
    RAISE EXCEPTION 'Petani wajib dipilih.'
      USING ERRCODE = '22023';
  ELSIF p_pihak_type = 'mitra' AND p_master_mitra_id IS NULL THEN
    RAISE EXCEPTION 'Mitra wajib dipilih.'
      USING ERRCODE = '22023';
  ELSIF p_pihak_type = 'sopir' AND p_sopir_id IS NULL THEN
    RAISE EXCEPTION 'Sopir wajib dipilih.'
      USING ERRCODE = '22023';
  ELSIF p_pihak_type IN ('karyawan', 'lainnya') AND NULLIF(btrim(COALESCE(p_pihak_nama_manual, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Nama pihak wajib diisi.'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.hutang_ledger (
    pihak_type,
    petani_id,
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
    created_by
  )
  VALUES (
    p_pihak_type,
    CASE WHEN p_pihak_type = 'petani' THEN p_petani_id ELSE NULL END,
    CASE WHEN p_pihak_type = 'mitra' THEN p_master_mitra_id ELSE NULL END,
    CASE WHEN p_pihak_type = 'sopir' THEN p_sopir_id ELSE NULL END,
    CASE WHEN p_pihak_type IN ('karyawan', 'lainnya') THEN NULLIF(btrim(COALESCE(p_pihak_nama_manual, '')), '') ELSE NULL END,
    v_tanggal,
    p_tipe,
    COALESCE(NULLIF(btrim(p_sumber), ''), 'lainnya'),
    round(p_jumlah, 2),
    NULLIF(btrim(COALESCE(p_legacy_source_table, '')), ''),
    p_legacy_source_id,
    NULLIF(btrim(COALESCE(p_keterangan, '')), ''),
    v_actor
  )
  RETURNING * INTO v_hutang;

  IF p_catat_kas THEN
    v_kas_tipe := CASE WHEN p_tipe = 'debit' THEN 'keluar' ELSE 'masuk' END;
    v_kas_sumber := CASE
      WHEN p_tipe = 'debit' AND p_sumber = 'panjar' THEN 'panjar_mitra'
      WHEN p_tipe = 'debit' THEN 'hutang_pencairan'
      ELSE 'hutang_pelunasan'
    END;

    SELECT *
    INTO v_kas
    FROM public.create_kas_mutasi(
      v_tanggal,
      v_kas_tipe,
      v_kas_sumber,
      p_jumlah,
      p_rekening_kas_id,
      COALESCE(NULLIF(btrim(p_keterangan), ''), 'Mutasi hutang/panjar'),
      'hutang_ledger',
      v_hutang.id,
      'hutang_ledger:' || v_hutang.id::text || ':' || v_kas_tipe
    );

    UPDATE public.kas_ledger
    SET hutang_ledger_id = v_hutang.id
    WHERE id = v_kas.id;

    UPDATE public.hutang_ledger
    SET rekening_kas_id = v_kas.rekening_kas_id,
        kas_ledger_id = v_kas.id
    WHERE id = v_hutang.id
    RETURNING * INTO v_hutang;
  END IF;

  RETURN v_hutang;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_hutang_ledger(
  p_hutang_ledger_id uuid,
  p_alasan text
)
RETURNS public.hutang_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.hutang_ledger%ROWTYPE;
  v_after public.hutang_ledger%ROWTYPE;
  v_reversal public.hutang_ledger%ROWTYPE;
  v_kas_reversal public.kas_ledger%ROWTYPE;
  v_kas_tipe text;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang membatalkan hutang/panjar.'
      USING ERRCODE = '42501';
  END IF;

  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_before
  FROM public.hutang_ledger
  WHERE id = p_hutang_ledger_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Data hutang/panjar tidak ditemukan.'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_before.status <> 'aktif' THEN
    RAISE EXCEPTION 'Data hutang/panjar sudah tidak aktif.'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.hutang_ledger (
    pihak_type,
    petani_id,
    mitra_id,
    master_mitra_id,
    sopir_id,
    pihak_nama_manual,
    pihak_ref_id,
    tanggal,
    tipe,
    sumber,
    jumlah,
    transaksi_beli_id,
    settlement_id,
    keterangan,
    status,
    reversal_of_id,
    created_by
  )
  VALUES (
    v_before.pihak_type,
    v_before.petani_id,
    v_before.mitra_id,
    v_before.master_mitra_id,
    v_before.sopir_id,
    v_before.pihak_nama_manual,
    v_before.pihak_ref_id,
    v_before.tanggal,
    CASE WHEN v_before.tipe = 'debit' THEN 'kredit' ELSE 'debit' END,
    'reversal',
    v_before.jumlah,
    v_before.transaksi_beli_id,
    v_before.settlement_id,
    'Reversal: ' || btrim(p_alasan),
    'reversal',
    v_before.id,
    v_actor
  )
  RETURNING * INTO v_reversal;

  IF v_before.kas_ledger_id IS NOT NULL THEN
    v_kas_tipe := CASE WHEN v_before.tipe = 'debit' THEN 'masuk' ELSE 'keluar' END;

    SELECT *
    INTO v_kas_reversal
    FROM public.create_kas_mutasi(
      v_before.tanggal,
      v_kas_tipe,
      'reversal',
      v_before.jumlah,
      v_before.rekening_kas_id,
      'Reversal hutang/panjar: ' || btrim(p_alasan),
      'hutang_ledger',
      v_before.id,
      'hutang_ledger:' || v_before.id::text || ':reversal'
    );

    UPDATE public.kas_ledger
    SET hutang_ledger_id = v_reversal.id,
        reversal_of_id = v_before.kas_ledger_id
    WHERE id = v_kas_reversal.id;

    UPDATE public.hutang_ledger
    SET rekening_kas_id = v_kas_reversal.rekening_kas_id,
        kas_ledger_id = v_kas_reversal.id
    WHERE id = v_reversal.id;
  END IF;

  UPDATE public.hutang_ledger
  SET status = 'dibatalkan',
      alasan_batal = btrim(p_alasan),
      dibatalkan_at = now(),
      dibatalkan_by = v_actor
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  RETURN v_after;
END;
$$;

-- ---------------------------------------------------------------------------
-- Panjar mitra tetap kompatibel dengan kwitansi lama, tetapi juga masuk hutang/kas.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_panjar_mitra_kas(
  p_mitra_id uuid,
  p_tanggal date,
  p_jumlah numeric,
  p_keterangan text DEFAULT NULL,
  p_rekening_kas_id uuid DEFAULT NULL
)
RETURNS public.panjar_mitra
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_panjar public.panjar_mitra%ROWTYPE;
  v_hutang public.hutang_ledger%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat panjar mitra.'
      USING ERRCODE = '42501';
  END IF;

  IF p_mitra_id IS NULL THEN
    RAISE EXCEPTION 'Mitra wajib dipilih.'
      USING ERRCODE = '22023';
  END IF;

  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
    RAISE EXCEPTION 'Jumlah panjar harus lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.panjar_mitra (
    tanggal,
    mitra_id,
    jumlah,
    keterangan,
    status,
    created_by
  )
  VALUES (
    COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    p_mitra_id,
    round(p_jumlah, 2),
    NULLIF(btrim(COALESCE(p_keterangan, '')), ''),
    'belum_lunas',
    v_actor
  )
  RETURNING * INTO v_panjar;

  SELECT *
  INTO v_hutang
  FROM public.create_hutang_pihak(
    'mitra',
    'debit',
    'panjar',
    v_panjar.jumlah,
    v_panjar.tanggal,
    NULL,
    p_mitra_id,
    NULL,
    NULL,
    COALESCE(v_panjar.keterangan, 'Panjar mitra'),
    p_rekening_kas_id,
    true,
    'panjar_mitra',
    v_panjar.id
  );

  UPDATE public.panjar_mitra
  SET rekening_kas_id = v_hutang.rekening_kas_id,
      kas_ledger_id = v_hutang.kas_ledger_id,
      hutang_ledger_id = v_hutang.id
  WHERE id = v_panjar.id
  RETURNING * INTO v_panjar;

  RETURN v_panjar;
END;
$$;

CREATE OR REPLACE FUNCTION public.settle_panjar_mitra_manual(
  p_panjar_id uuid,
  p_alasan text
)
RETURNS public.panjar_mitra
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_panjar public.panjar_mitra%ROWTYPE;
  v_hutang public.hutang_ledger%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang melunasi panjar mitra.'
      USING ERRCODE = '42501';
  END IF;

  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pelunasan manual wajib diisi.'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_panjar
  FROM public.panjar_mitra
  WHERE id = p_panjar_id
  FOR UPDATE;

  IF v_panjar.id IS NULL THEN
    RAISE EXCEPTION 'Panjar tidak ditemukan.'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_panjar.status <> 'belum_lunas' THEN
    RAISE EXCEPTION 'Panjar sudah tidak berstatus belum lunas.'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.hutang_ledger (
    pihak_type,
    master_mitra_id,
    tanggal,
    tipe,
    sumber,
    jumlah,
    legacy_source_table,
    legacy_source_id,
    keterangan,
    created_by
  )
  VALUES (
    'mitra',
    v_panjar.mitra_id,
    COALESCE(v_panjar.tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    'kredit',
    'koreksi',
    v_panjar.jumlah,
    'panjar_mitra_manual_lunas',
    v_panjar.id,
    'Pelunasan manual panjar: ' || btrim(p_alasan),
    v_actor
  )
  RETURNING * INTO v_hutang;

  UPDATE public.panjar_mitra
  SET status = 'lunas',
      settlement_hutang_ledger_id = v_hutang.id,
      lunas_at = now(),
      updated_at = now()
  WHERE id = v_panjar.id
  RETURNING * INTO v_panjar;

  RETURN v_panjar;
END;
$$;

-- ---------------------------------------------------------------------------
-- Biaya operasional masuk kas ledger
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_biaya_operasional_kas(
  p_tanggal date,
  p_kategori text,
  p_jumlah numeric,
  p_keterangan text DEFAULT NULL,
  p_rekening_kas_id uuid DEFAULT NULL
)
RETURNS public.biaya_operasional
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_biaya public.biaya_operasional%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
  v_rekening_id uuid := p_rekening_kas_id;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat biaya operasional.'
      USING ERRCODE = '42501';
  END IF;

  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
    RAISE EXCEPTION 'Jumlah biaya harus lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF v_rekening_id IS NULL THEN
    v_rekening_id := public.get_default_rekening_kas_id();
  END IF;

  INSERT INTO public.biaya_operasional (
    tanggal,
    kategori,
    jumlah,
    keterangan,
    status,
    rekening_kas_id,
    created_by
  )
  VALUES (
    COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    p_kategori,
    round(p_jumlah, 2),
    NULLIF(btrim(COALESCE(p_keterangan, '')), ''),
    'aktif',
    v_rekening_id,
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
  )
  VALUES (
    v_rekening_id,
    v_biaya.tanggal,
    'keluar',
    'biaya_operasional',
    v_biaya.jumlah,
    v_biaya.id,
    'biaya_operasional',
    v_biaya.id,
    'biaya_operasional:' || v_biaya.id::text,
    COALESCE(v_biaya.keterangan, 'Biaya operasional'),
    v_actor
  )
  RETURNING * INTO v_kas;

  UPDATE public.biaya_operasional
  SET kas_ledger_id = v_kas.id
  WHERE id = v_biaya.id
  RETURNING * INTO v_biaya;

  RETURN v_biaya;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_biaya_operasional_kas(
  p_biaya_id uuid,
  p_alasan text
)
RETURNS public.biaya_operasional
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.biaya_operasional%ROWTYPE;
  v_after public.biaya_operasional%ROWTYPE;
  v_reversal public.kas_ledger%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang membatalkan biaya operasional.'
      USING ERRCODE = '42501';
  END IF;

  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_before
  FROM public.biaya_operasional
  WHERE id = p_biaya_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Biaya operasional tidak ditemukan.'
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_before.status, 'aktif') <> 'aktif' THEN
    RAISE EXCEPTION 'Biaya operasional sudah tidak aktif.'
      USING ERRCODE = '22023';
  END IF;

  IF v_before.kas_ledger_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.kas_ledger
       WHERE reversal_of_id = v_before.kas_ledger_id
         AND status = 'aktif'
     ) THEN
    INSERT INTO public.kas_ledger (
      rekening_kas_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      biaya_operasional_id,
      source_table,
      source_id,
      reversal_of_id,
      idempotency_key,
      keterangan,
      created_by
    )
    VALUES (
      COALESCE(v_before.rekening_kas_id, public.get_default_rekening_kas_id()),
      v_before.tanggal,
      'masuk',
      'reversal',
      v_before.jumlah,
      v_before.id,
      'biaya_operasional',
      v_before.id,
      v_before.kas_ledger_id,
      'biaya_operasional:' || v_before.id::text || ':reversal',
      'Reversal biaya: ' || btrim(p_alasan),
      v_actor
    )
    RETURNING * INTO v_reversal;
  END IF;

  UPDATE public.biaya_operasional
  SET status = 'dibatalkan',
      alasan_batal = btrim(p_alasan),
      dibatalkan_at = now(),
      dibatalkan_by = v_actor
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  RETURN v_after;
END;
$$;

-- ---------------------------------------------------------------------------
-- Pembelian TBS lokal masuk kas ledger.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_transaksi_beli_tbs(
  p_petani_id uuid,
  p_berat_kotor_kg numeric,
  p_potongan_percent numeric DEFAULT 0,
  p_potongan_hutang numeric DEFAULT 0,
  p_keterangan text DEFAULT NULL,
  p_tanggal date DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  tanggal date,
  petani_id uuid,
  petani_nama text,
  berat_kotor_kg numeric,
  potongan_type text,
  potongan_value numeric,
  berat_bersih_kg numeric,
  harga_per_kg numeric,
  total_harga numeric,
  potongan_hutang numeric,
  total_bayar_tunai numeric,
  no_struk text,
  status text,
  keterangan text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_tanggal date := COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date);
  v_harga public.harga_tbs_lokal%ROWTYPE;
  v_saldo_hutang numeric(15,2) := 0;
  v_berat_bersih numeric(14,2);
  v_total_harga numeric(15,2);
  v_potongan_hutang numeric(15,2);
  v_transaksi public.transaksi_beli_tbs%ROWTYPE;
  v_rekening_kas_id uuid;
  v_kas_ledger_id uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak punya akses untuk input pembelian TBS';
  END IF;

  IF p_petani_id IS NULL THEN
    RAISE EXCEPTION 'Petani wajib dipilih';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.petani
    WHERE public.petani.id = p_petani_id
      AND public.petani.aktif = true
  ) THEN
    RAISE EXCEPTION 'Petani tidak ditemukan atau tidak aktif';
  END IF;

  IF p_berat_kotor_kg IS NULL OR p_berat_kotor_kg <= 0 THEN
    RAISE EXCEPTION 'Berat kotor harus lebih dari 0';
  END IF;

  IF p_potongan_percent IS NULL OR p_potongan_percent < 0 OR p_potongan_percent > 100 THEN
    RAISE EXCEPTION 'Potongan persen harus berada di antara 0 sampai 100';
  END IF;

  SELECT *
  INTO v_harga
  FROM public.harga_tbs_lokal
  WHERE aktif = true
    AND berlaku_mulai <= now()
    AND (berlaku_sampai IS NULL OR berlaku_sampai > now())
  ORDER BY berlaku_mulai DESC
  LIMIT 1;

  IF v_harga.id IS NULL THEN
    RAISE EXCEPTION 'Harga TBS lokal aktif belum diset';
  END IF;

  SELECT COALESCE(
    SUM(CASE WHEN tipe = 'debit' THEN jumlah ELSE -jumlah END),
    0
  )
  INTO v_saldo_hutang
  FROM public.hutang_ledger
  WHERE pihak_type = 'petani'
    AND petani_id = p_petani_id
    AND status <> 'dibatalkan';

  v_berat_bersih := round(p_berat_kotor_kg * (1 - (p_potongan_percent / 100)), 2);
  v_total_harga := round(v_berat_bersih * v_harga.harga_per_kg, 0);
  v_potongan_hutang := LEAST(
    GREATEST(COALESCE(p_potongan_hutang, 0), 0),
    GREATEST(v_saldo_hutang, 0),
    v_total_harga
  );

  INSERT INTO public.transaksi_beli_tbs (
    tanggal,
    petani_id,
    harga_tbs_lokal_id,
    berat_kotor_kg,
    potongan_type,
    potongan_value,
    berat_bersih_kg,
    harga_per_kg,
    total_harga,
    potongan_hutang,
    total_bayar_tunai,
    no_struk,
    status,
    keterangan,
    created_by
  )
  VALUES (
    v_tanggal,
    p_petani_id,
    v_harga.id,
    round(p_berat_kotor_kg, 2),
    'percent',
    round(p_potongan_percent, 2),
    v_berat_bersih,
    v_harga.harga_per_kg,
    v_total_harga,
    v_potongan_hutang,
    v_total_harga - v_potongan_hutang,
    public.next_no_struk_tbs(v_tanggal),
    'aktif',
    p_keterangan,
    v_actor
  )
  RETURNING * INTO v_transaksi;

  INSERT INTO public.stok_tbs_lokal_ledger (
    tanggal,
    tipe,
    sumber,
    transaksi_beli_id,
    berat_kg,
    keterangan,
    created_by
  )
  VALUES (
    v_tanggal,
    'masuk',
    'pembelian_petani',
    v_transaksi.id,
    v_transaksi.berat_bersih_kg,
    'Masuk dari ' || v_transaksi.no_struk,
    v_actor
  );

  IF v_potongan_hutang > 0 THEN
    INSERT INTO public.hutang_ledger (
      pihak_type,
      petani_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      transaksi_beli_id,
      keterangan,
      created_by
    )
    VALUES (
      'petani',
      p_petani_id,
      v_tanggal,
      'kredit',
      'potong_tbs',
      v_potongan_hutang,
      v_transaksi.id,
      'Potong dari ' || v_transaksi.no_struk,
      v_actor
    );
  END IF;

  IF v_transaksi.total_bayar_tunai > 0 THEN
    v_rekening_kas_id := public.get_default_rekening_kas_id();

    INSERT INTO public.kas_ledger (
      rekening_kas_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      transaksi_beli_id,
      source_table,
      source_id,
      idempotency_key,
      keterangan,
      created_by
    )
    VALUES (
      v_rekening_kas_id,
      v_tanggal,
      'keluar',
      'pembelian_tbs',
      v_transaksi.total_bayar_tunai,
      v_transaksi.id,
      'transaksi_beli_tbs',
      v_transaksi.id,
      'transaksi_beli_tbs:' || v_transaksi.id::text,
      'Bayar tunai ' || v_transaksi.no_struk,
      v_actor
    )
    RETURNING id INTO v_kas_ledger_id;

    UPDATE public.transaksi_beli_tbs
    SET rekening_kas_id = v_rekening_kas_id,
        kas_ledger_id = v_kas_ledger_id
    WHERE public.transaksi_beli_tbs.id = v_transaksi.id
    RETURNING * INTO v_transaksi;
  END IF;

  PERFORM public.write_audit_log(
    'transaksi_beli_tbs',
    v_transaksi.id,
    'create',
    NULL,
    to_jsonb(v_transaksi),
    p_keterangan
  );

  RETURN QUERY
  SELECT
    t.id,
    t.tanggal,
    t.petani_id,
    p.nama::text AS petani_nama,
    t.berat_kotor_kg,
    t.potongan_type,
    t.potongan_value,
    t.berat_bersih_kg,
    t.harga_per_kg,
    t.total_harga,
    t.potongan_hutang,
    t.total_bayar_tunai,
    t.no_struk,
    t.status,
    t.keterangan,
    t.created_at
  FROM public.transaksi_beli_tbs t
  LEFT JOIN public.petani p ON p.id = t.petani_id
  WHERE t.id = v_transaksi.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_transaksi_beli_tbs(
  p_transaksi_id uuid,
  p_alasan text
)
RETURNS public.transaksi_beli_tbs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.transaksi_beli_tbs%ROWTYPE;
  v_after public.transaksi_beli_tbs%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Pembatalan transaksi wajib dilakukan owner atau super admin';
  END IF;

  IF p_alasan IS NULL OR length(trim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi';
  END IF;

  SELECT *
  INTO v_before
  FROM public.transaksi_beli_tbs
  WHERE id = p_transaksi_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Transaksi tidak ditemukan';
  END IF;

  IF v_before.status = 'dibatalkan' THEN
    RAISE EXCEPTION 'Transaksi sudah dibatalkan';
  END IF;

  UPDATE public.transaksi_beli_tbs
  SET status = 'dibatalkan',
      keterangan = concat_ws(E'\n', keterangan, 'Dibatalkan: ' || p_alasan),
      updated_at = now()
  WHERE id = p_transaksi_id
  RETURNING * INTO v_after;

  INSERT INTO public.stok_tbs_lokal_ledger (
    tanggal,
    tipe,
    sumber,
    transaksi_beli_id,
    berat_kg,
    keterangan,
    created_by
  )
  VALUES (
    v_before.tanggal,
    'reversal',
    'reversal',
    v_before.id,
    -v_before.berat_bersih_kg,
    'Reversal batal ' || v_before.no_struk || ': ' || p_alasan,
    v_actor
  );

  IF v_before.potongan_hutang > 0 THEN
    INSERT INTO public.hutang_ledger (
      pihak_type,
      petani_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      transaksi_beli_id,
      keterangan,
      created_by
    )
    VALUES (
      'petani',
      v_before.petani_id,
      v_before.tanggal,
      'debit',
      'reversal',
      v_before.potongan_hutang,
      v_before.id,
      'Reversal potong hutang ' || v_before.no_struk || ': ' || p_alasan,
      v_actor
    );
  END IF;

  IF v_before.kas_ledger_id IS NOT NULL
     AND v_before.total_bayar_tunai > 0
     AND NOT EXISTS (
       SELECT 1
       FROM public.kas_ledger
       WHERE reversal_of_id = v_before.kas_ledger_id
         AND status = 'aktif'
     ) THEN
    INSERT INTO public.kas_ledger (
      rekening_kas_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      transaksi_beli_id,
      source_table,
      source_id,
      reversal_of_id,
      idempotency_key,
      keterangan,
      created_by
    )
    VALUES (
      COALESCE(v_before.rekening_kas_id, public.get_default_rekening_kas_id()),
      v_before.tanggal,
      'masuk',
      'reversal',
      v_before.total_bayar_tunai,
      v_before.id,
      'transaksi_beli_tbs',
      v_before.id,
      v_before.kas_ledger_id,
      'transaksi_beli_tbs:' || v_before.id::text || ':reversal',
      'Reversal bayar tunai ' || v_before.no_struk || ': ' || p_alasan,
      v_actor
    );
  END IF;

  PERFORM public.write_audit_log(
    'transaksi_beli_tbs',
    v_before.id,
    'cancel',
    to_jsonb(v_before),
    to_jsonb(v_after),
    p_alasan
  );

  RETURN v_after;
END;
$$;

-- ---------------------------------------------------------------------------
-- Pengiriman lokal dan pembayaran pabrik dasar.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_pengiriman_lokal_status(
  p_pengiriman_id uuid,
  p_status text,
  p_tonase_pabrik numeric,
  p_harga_pabrik_per_kg numeric DEFAULT NULL,
  p_potongan_sortasi_type text DEFAULT 'none',
  p_potongan_sortasi_value numeric DEFAULT 0,
  p_biaya_timbang numeric DEFAULT 0,
  p_potongan_pabrik_lain numeric DEFAULT 0,
  p_tanggal_bayar date DEFAULT NULL,
  p_rekening_kas_id uuid DEFAULT NULL
)
RETURNS public.pengiriman
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_pengiriman public.pengiriman%ROWTYPE;
  v_after public.pengiriman%ROWTYPE;
  v_tonase_dasar numeric(14,2);
  v_bruto numeric(15,2) := 0;
  v_sortasi_rupiah numeric(15,2) := 0;
  v_total_pembayaran numeric(15,2) := 0;
  v_rekening_id uuid := p_rekening_kas_id;
  v_pembayaran_id uuid;
  v_kas_id uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang memperbarui pengiriman lokal.'
      USING ERRCODE = '42501';
  END IF;

  IF p_status NOT IN ('diterima_pabrik', 'dibayar_pabrik') THEN
    RAISE EXCEPTION 'Status pengiriman tidak valid untuk aksi ini.'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_pengiriman
  FROM public.pengiriman
  WHERE id = p_pengiriman_id
  FOR UPDATE;

  IF v_pengiriman.id IS NULL THEN
    RAISE EXCEPTION 'Pengiriman tidak ditemukan.'
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_pengiriman.status, '') IN ('dibayar_pabrik', 'dibayar', 'selesai', 'dibatalkan') THEN
    RAISE EXCEPTION 'Pengiriman sudah final atau dibatalkan.'
      USING ERRCODE = '22023';
  END IF;

  IF p_tonase_pabrik IS NULL OR p_tonase_pabrik <= 0 THEN
    RAISE EXCEPTION 'Tonase pabrik wajib lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF p_potongan_sortasi_type NOT IN ('none', 'kg', 'percent', 'nominal') THEN
    RAISE EXCEPTION 'Tipe potongan sortasi tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  v_tonase_dasar := CASE
    WHEN p_potongan_sortasi_type = 'kg' THEN GREATEST(p_tonase_pabrik - COALESCE(p_potongan_sortasi_value, 0), 0)
    ELSE p_tonase_pabrik
  END;

  IF p_status = 'dibayar_pabrik' THEN
    IF p_harga_pabrik_per_kg IS NULL OR p_harga_pabrik_per_kg <= 0 THEN
      RAISE EXCEPTION 'Harga pabrik wajib lebih dari 0 saat status dibayar.'
        USING ERRCODE = '22023';
    END IF;

    IF v_rekening_id IS NULL THEN
      v_rekening_id := public.get_default_rekening_kas_id();
    END IF;

    v_bruto := round(v_tonase_dasar * p_harga_pabrik_per_kg, 0);
    v_sortasi_rupiah := CASE
      WHEN p_potongan_sortasi_type = 'percent' THEN round(v_bruto * (COALESCE(p_potongan_sortasi_value, 0) / 100), 0)
      WHEN p_potongan_sortasi_type = 'nominal' THEN round(COALESCE(p_potongan_sortasi_value, 0), 0)
      ELSE 0
    END;
    v_total_pembayaran := GREATEST(
      v_bruto - v_sortasi_rupiah - COALESCE(p_biaya_timbang, 0) - COALESCE(p_potongan_pabrik_lain, 0),
      0
    );

    IF v_total_pembayaran <= 0 THEN
      RAISE EXCEPTION 'Total pembayaran pabrik harus lebih dari 0.'
        USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.pembayaran_pabrik (
      pabrik_id,
      tanggal_bayar,
      total_bayar,
      metode,
      status,
      keterangan,
      rekening_kas_id,
      created_by
    )
    VALUES (
      v_pengiriman.pabrik_id,
      COALESCE(p_tanggal_bayar, (now() AT TIME ZONE 'Asia/Jakarta')::date),
      v_total_pembayaran,
      'transfer/tunai',
      'teralokasi_penuh',
      'Pembayaran pabrik untuk DO ' || COALESCE(v_pengiriman.nomor_do, v_pengiriman.no_do, v_pengiriman.id::text),
      v_rekening_id,
      v_actor
    )
    RETURNING id INTO v_pembayaran_id;

    INSERT INTO public.pembayaran_pabrik_detail (
      pembayaran_pabrik_id,
      pengiriman_id,
      nomor_do,
      jumlah_dialokasikan,
      tonase_pabrik,
      tonase_dasar_settlement,
      harga_pabrik_per_kg,
      potongan_sortasi_type,
      potongan_sortasi_value,
      potongan_sortasi_rupiah,
      biaya_timbang,
      potongan_pabrik_lain
    )
    VALUES (
      v_pembayaran_id,
      v_pengiriman.id,
      COALESCE(v_pengiriman.nomor_do, v_pengiriman.no_do),
      v_total_pembayaran,
      round(p_tonase_pabrik, 2),
      v_tonase_dasar,
      p_harga_pabrik_per_kg,
      p_potongan_sortasi_type,
      COALESCE(p_potongan_sortasi_value, 0),
      v_sortasi_rupiah,
      COALESCE(p_biaya_timbang, 0),
      COALESCE(p_potongan_pabrik_lain, 0)
    );

    INSERT INTO public.kas_ledger (
      rekening_kas_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      pengiriman_id,
      pembayaran_pabrik_id,
      source_table,
      source_id,
      idempotency_key,
      keterangan,
      created_by
    )
    VALUES (
      v_rekening_id,
      COALESCE(p_tanggal_bayar, (now() AT TIME ZONE 'Asia/Jakarta')::date),
      'masuk',
      'pembayaran_pabrik',
      v_total_pembayaran,
      v_pengiriman.id,
      v_pembayaran_id,
      'pengiriman',
      v_pengiriman.id,
      'pengiriman:' || v_pengiriman.id::text || ':pembayaran_pabrik',
      'Pembayaran pabrik DO ' || COALESCE(v_pengiriman.nomor_do, v_pengiriman.no_do, '-'),
      v_actor
    )
    RETURNING id INTO v_kas_id;

    UPDATE public.pembayaran_pabrik
    SET kas_ledger_id = v_kas_id
    WHERE id = v_pembayaran_id;
  END IF;

  UPDATE public.pengiriman
  SET status = p_status,
      tonase_pabrik = round(p_tonase_pabrik, 2),
      tonase_dasar_settlement = v_tonase_dasar,
      harga_pabrik_per_kg = CASE WHEN p_status = 'dibayar_pabrik' THEN p_harga_pabrik_per_kg ELSE harga_pabrik_per_kg END,
      potongan_sortasi_type = CASE WHEN p_status = 'dibayar_pabrik' THEN p_potongan_sortasi_type ELSE potongan_sortasi_type END,
      potongan_sortasi_value = CASE WHEN p_status = 'dibayar_pabrik' THEN COALESCE(p_potongan_sortasi_value, 0) ELSE potongan_sortasi_value END,
      potongan_sortasi_rupiah = CASE WHEN p_status = 'dibayar_pabrik' THEN v_sortasi_rupiah ELSE potongan_sortasi_rupiah END,
      biaya_timbang = CASE WHEN p_status = 'dibayar_pabrik' THEN COALESCE(p_biaya_timbang, 0) ELSE biaya_timbang END,
      potongan_pabrik_lain = CASE WHEN p_status = 'dibayar_pabrik' THEN COALESCE(p_potongan_pabrik_lain, 0) ELSE potongan_pabrik_lain END,
      total_pembayaran_pabrik = CASE WHEN p_status = 'dibayar_pabrik' THEN v_total_pembayaran ELSE total_pembayaran_pabrik END,
      total_harga_pabrik = CASE WHEN p_status = 'dibayar_pabrik' THEN v_total_pembayaran ELSE total_harga_pabrik END,
      tanggal_bayar = CASE WHEN p_status = 'dibayar_pabrik' THEN COALESCE(p_tanggal_bayar, (now() AT TIME ZONE 'Asia/Jakarta')::date) ELSE tanggal_bayar END,
      pembayaran_pabrik_id = CASE WHEN p_status = 'dibayar_pabrik' THEN v_pembayaran_id ELSE pembayaran_pabrik_id END,
      rekening_kas_id = CASE WHEN p_status = 'dibayar_pabrik' THEN v_rekening_id ELSE rekening_kas_id END,
      kas_ledger_id = CASE WHEN p_status = 'dibayar_pabrik' THEN v_kas_id ELSE kas_ledger_id END,
      updated_at = now()
  WHERE id = v_pengiriman.id
  RETURNING * INTO v_after;

  RETURN v_after;
END;
$$;

-- ---------------------------------------------------------------------------
-- Pembayaran kwitansi mitra masuk kas ledger dan menutup panjar di hutang ledger.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_pembayaran_mitra_kwitansi(
  p_master_mitra_id uuid,
  p_periode_dari date,
  p_periode_sampai date,
  p_metode_bayar text DEFAULT 'tunai',
  p_catatan text DEFAULT NULL
)
RETURNS public.pembayaran_mitra_kwitansi
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payment public.pembayaran_mitra_kwitansi%ROWTYPE;
  v_jumlah_transaksi integer := 0;
  v_total_tonase numeric(15,2) := 0;
  v_total_nilai_bersih numeric(15,2) := 0;
  v_total_panjar numeric(15,2) := 0;
  v_nominal_dibayar numeric(15,2) := 0;
  v_panjar_ids uuid[] := '{}'::uuid[];
  v_panjar_snapshot jsonb := '[]'::jsonb;
  v_transaksi_snapshot jsonb := '[]'::jsonb;
  v_actor uuid := auth.uid();
  v_rekening_kas_id uuid;
  v_kas_ledger_id uuid;
  v_panjar_hutang_id uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat pembayaran mitra.'
      USING ERRCODE = '42501';
  END IF;

  IF p_master_mitra_id IS NULL THEN
    RAISE EXCEPTION 'Mitra wajib dipilih.'
      USING ERRCODE = '22023';
  END IF;

  IF p_periode_dari IS NULL OR p_periode_sampai IS NULL OR p_periode_sampai < p_periode_dari THEN
    RAISE EXCEPTION 'Periode pembayaran tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  IF COALESCE(p_metode_bayar, 'tunai') NOT IN ('tunai', 'transfer', 'lainnya') THEN
    RAISE EXCEPTION 'Metode bayar tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.pembayaran_mitra_kwitansi pmk
    WHERE pmk.master_mitra_id = p_master_mitra_id
      AND pmk.periode_dari = p_periode_dari
      AND pmk.periode_sampai = p_periode_sampai
      AND pmk.status <> 'dibatalkan'
  ) THEN
    RAISE EXCEPTION 'Kwitansi periode ini sudah ditandai dibayar.'
      USING ERRCODE = '23505';
  END IF;

  WITH trx AS (
    SELECT
      tm.id,
      tm.tanggal,
      tm.created_at,
      tm.sopir_aktual_nama,
      tm.sopir_default_nama,
      tm.plat_nomor,
      tm.tonase,
      COALESCE(tm.harga_bersih_per_kg, tm.harga_harian, 0) AS harga_bersih_per_kg,
      COALESCE(tm.total_nilai_bersih, tm.total_kotor, 0) AS total_nilai_bersih,
      tm.status
    FROM public.transaksi_mitra tm
    WHERE tm.mitra_id = p_master_mitra_id
      AND tm.tanggal >= p_periode_dari
      AND tm.tanggal <= p_periode_sampai
      AND COALESCE(tm.status, 'aktif') <> 'dibatalkan'
      AND NOT EXISTS (
        SELECT 1
        FROM public.pembayaran_mitra_kwitansi_item item
        JOIN public.pembayaran_mitra_kwitansi pay ON pay.id = item.pembayaran_id
        WHERE item.transaksi_mitra_id = tm.id
          AND pay.status <> 'dibatalkan'
      )
  )
  SELECT
    COUNT(*)::integer,
    COALESCE(SUM(tonase), 0)::numeric(15,2),
    COALESCE(SUM(total_nilai_bersih), 0)::numeric(15,2),
    COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', id,
        'tanggal', tanggal,
        'created_at', created_at,
        'sopir_aktual_nama', COALESCE(sopir_aktual_nama, sopir_default_nama),
        'plat_nomor', plat_nomor,
        'tonase', tonase,
        'harga_bersih_per_kg', harga_bersih_per_kg,
        'total_nilai_bersih', total_nilai_bersih,
        'status', status
      )
      ORDER BY tanggal, created_at
    ), '[]'::jsonb)
  INTO v_jumlah_transaksi, v_total_tonase, v_total_nilai_bersih, v_transaksi_snapshot
  FROM trx;

  IF v_jumlah_transaksi <= 0 THEN
    RAISE EXCEPTION 'Tidak ada transaksi aktif yang bisa dibayar pada periode ini.'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT
    COALESCE(SUM(jumlah), 0)::numeric(15,2),
    COALESCE(array_agg(id ORDER BY tanggal, created_at), '{}'::uuid[]),
    COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', id,
        'tanggal', tanggal,
        'jumlah', jumlah,
        'keterangan', keterangan
      )
      ORDER BY tanggal, created_at
    ), '[]'::jsonb)
  INTO v_total_panjar, v_panjar_ids, v_panjar_snapshot
  FROM public.panjar_mitra
  WHERE mitra_id = p_master_mitra_id
    AND status = 'belum_lunas';

  IF v_total_panjar > v_total_nilai_bersih THEN
    RAISE EXCEPTION 'Total panjar melebihi nilai bersih kwitansi. Koreksi panjar dulu sebelum menandai dibayar.'
      USING ERRCODE = '22023';
  END IF;

  v_nominal_dibayar := v_total_nilai_bersih - v_total_panjar;

  INSERT INTO public.pembayaran_mitra_kwitansi (
    master_mitra_id,
    periode_dari,
    periode_sampai,
    status,
    tanggal_bayar,
    dibayar_at,
    metode_bayar,
    total_tonase,
    total_nilai_bersih,
    total_panjar,
    nominal_dibayar,
    jumlah_transaksi,
    panjar_ids,
    panjar_snapshot_json,
    transaksi_snapshot_json,
    catatan,
    created_by,
    updated_by
  )
  VALUES (
    p_master_mitra_id,
    p_periode_dari,
    p_periode_sampai,
    'dibayar',
    (now() AT TIME ZONE 'Asia/Jakarta')::date,
    now(),
    COALESCE(p_metode_bayar, 'tunai'),
    v_total_tonase,
    v_total_nilai_bersih,
    v_total_panjar,
    v_nominal_dibayar,
    v_jumlah_transaksi,
    v_panjar_ids,
    v_panjar_snapshot,
    v_transaksi_snapshot,
    NULLIF(btrim(COALESCE(p_catatan, '')), ''),
    v_actor,
    v_actor
  )
  RETURNING * INTO v_payment;

  IF v_nominal_dibayar > 0 THEN
    v_rekening_kas_id := public.get_default_rekening_kas_id();

    INSERT INTO public.kas_ledger (
      rekening_kas_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      pembayaran_mitra_kwitansi_id,
      source_table,
      source_id,
      idempotency_key,
      keterangan,
      created_by
    )
    VALUES (
      v_rekening_kas_id,
      v_payment.tanggal_bayar,
      'keluar',
      'pembayaran_mitra',
      v_nominal_dibayar,
      v_payment.id,
      'pembayaran_mitra_kwitansi',
      v_payment.id,
      'pembayaran_mitra_kwitansi:' || v_payment.id::text,
      'Pembayaran kwitansi mitra periode ' || p_periode_dari::text || ' s/d ' || p_periode_sampai::text,
      v_actor
    )
    RETURNING id INTO v_kas_ledger_id;

    UPDATE public.pembayaran_mitra_kwitansi
    SET rekening_kas_id = v_rekening_kas_id,
        kas_ledger_id = v_kas_ledger_id
    WHERE id = v_payment.id
    RETURNING * INTO v_payment;
  END IF;

  INSERT INTO public.pembayaran_mitra_kwitansi_item (
    pembayaran_id,
    transaksi_mitra_id,
    tanggal,
    waktu_transaksi,
    sopir_aktual_nama,
    plat_nomor,
    tonase_snapshot,
    harga_bersih_per_kg_snapshot,
    total_nilai_bersih_snapshot,
    status_transaksi_snapshot
  )
  SELECT
    v_payment.id,
    tm.id,
    tm.tanggal,
    tm.created_at,
    COALESCE(tm.sopir_aktual_nama, tm.sopir_default_nama),
    tm.plat_nomor,
    tm.tonase,
    COALESCE(tm.harga_bersih_per_kg, tm.harga_harian, 0),
    COALESCE(tm.total_nilai_bersih, tm.total_kotor, 0),
    COALESCE(tm.status, 'aktif')
  FROM public.transaksi_mitra tm
  WHERE tm.mitra_id = p_master_mitra_id
    AND tm.tanggal >= p_periode_dari
    AND tm.tanggal <= p_periode_sampai
    AND COALESCE(tm.status, 'aktif') <> 'dibatalkan'
    AND NOT EXISTS (
      SELECT 1
      FROM public.pembayaran_mitra_kwitansi_item item
      WHERE item.transaksi_mitra_id = tm.id
    )
  ORDER BY tm.tanggal, tm.created_at;

  IF COALESCE(array_length(v_panjar_ids, 1), 0) > 0 THEN
    INSERT INTO public.hutang_ledger (
      pihak_type,
      master_mitra_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      legacy_source_table,
      legacy_source_id,
      keterangan,
      created_by
    )
    VALUES (
      'mitra',
      p_master_mitra_id,
      v_payment.tanggal_bayar,
      'kredit',
      'potong_settlement',
      v_total_panjar,
      'pembayaran_mitra_kwitansi_panjar',
      v_payment.id,
      'Potong panjar pada pembayaran kwitansi',
      v_actor
    )
    RETURNING id INTO v_panjar_hutang_id;

    UPDATE public.panjar_mitra
    SET status = 'lunas',
        settlement_hutang_ledger_id = v_panjar_hutang_id,
        lunas_at = now(),
        updated_at = now()
    WHERE id = ANY(v_panjar_ids);
  END IF;

  RETURN v_payment;
END;
$$;

-- ---------------------------------------------------------------------------
-- Privilege fungsi
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.get_default_rekening_kas_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_default_rekening_kas_id() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_default_rekening_kas_id() TO authenticated;

REVOKE ALL ON FUNCTION public.create_kas_mutasi(date, text, text, numeric, uuid, text, text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_kas_mutasi(date, text, text, numeric, uuid, text, text, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_kas_mutasi(date, text, text, numeric, uuid, text, text, uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.create_hutang_pihak(text, text, text, numeric, date, uuid, uuid, uuid, text, text, uuid, boolean, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_hutang_pihak(text, text, text, numeric, date, uuid, uuid, uuid, text, text, uuid, boolean, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_hutang_pihak(text, text, text, numeric, date, uuid, uuid, uuid, text, text, uuid, boolean, text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.cancel_hutang_ledger(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_hutang_ledger(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.cancel_hutang_ledger(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.create_panjar_mitra_kas(uuid, date, numeric, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_panjar_mitra_kas(uuid, date, numeric, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_panjar_mitra_kas(uuid, date, numeric, text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.settle_panjar_mitra_manual(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.settle_panjar_mitra_manual(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.settle_panjar_mitra_manual(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.create_biaya_operasional_kas(date, text, numeric, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_biaya_operasional_kas(date, text, numeric, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_biaya_operasional_kas(date, text, numeric, text, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.cancel_biaya_operasional_kas(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_biaya_operasional_kas(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.cancel_biaya_operasional_kas(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.record_pengiriman_lokal_status(uuid, text, numeric, numeric, text, numeric, numeric, numeric, date, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_pengiriman_lokal_status(uuid, text, numeric, numeric, text, numeric, numeric, numeric, date, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_pengiriman_lokal_status(uuid, text, numeric, numeric, text, numeric, numeric, numeric, date, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text) TO authenticated;

COMMIT;
