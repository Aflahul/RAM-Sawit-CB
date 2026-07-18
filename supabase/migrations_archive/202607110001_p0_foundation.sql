-- Sawit CB - P0 foundation migration
-- Jalankan setelah schema awal lama bila database sudah pernah dipakai.
-- Migration ini tidak menghapus tabel lama; ia menambah struktur final secara bertahap.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Users and roles (Moved up for SQL function dependency)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nama varchar(100) NOT NULL,
  username varchar(50),
  role text NOT NULL DEFAULT 'admin_operasional',
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.current_app_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT role FROM public.users WHERE id = auth.uid()),
    'anonymous'
  );
$$;

CREATE OR REPLACE FUNCTION public.has_app_role(required_roles text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.current_app_role() = ANY(required_roles);
$$;

CREATE SEQUENCE IF NOT EXISTS public.transaksi_beli_tbs_no_struk_seq;

CREATE OR REPLACE FUNCTION public.next_no_struk_tbs(p_tanggal date DEFAULT CURRENT_DATE)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  next_value bigint;
BEGIN
  next_value := nextval('public.transaksi_beli_tbs_no_struk_seq');
  RETURN 'TBS-' || to_char(p_tanggal, 'YYYYMMDD') || '-' || lpad(next_value::text, 6, '0');
END;
$$;

ALTER TABLE public.users
  ALTER COLUMN role TYPE text,
  ALTER COLUMN role SET DEFAULT 'admin_operasional';

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT NOW();

UPDATE public.users
SET role = 'admin_operasional'
WHERE role = 'admin';

UPDATE public.users
SET role = 'admin_operasional'
WHERE role NOT IN ('owner', 'super_admin', 'admin_operasional', 'admin_keuangan');

DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.users'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%role%'
  LOOP
    EXECUTE format('ALTER TABLE public.users DROP CONSTRAINT %I', c.conname);
  END LOOP;
END;
$$;

ALTER TABLE public.users
  ADD CONSTRAINT users_role_check
  CHECK (role IN ('owner', 'super_admin', 'admin_operasional', 'admin_keuangan'));

-- ---------------------------------------------------------------------------
-- Master data
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.petani (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama varchar(100) NOT NULL,
  no_ktp varchar(30),
  no_hp varchar(30),
  alamat text,
  batas_hutang numeric(15,2) DEFAULT 0,
  aktif boolean DEFAULT true,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

ALTER TABLE public.petani
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT NOW();

CREATE TABLE IF NOT EXISTS public.mitra (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama varchar(150) NOT NULL,
  penanggung_jawab varchar(100),
  no_hp varchar(30),
  alamat text,
  rekening text,
  fee_per_kg numeric(12,2) DEFAULT 0,
  boleh_kasbon boolean DEFAULT false,
  batas_kasbon numeric(15,2) DEFAULT 0,
  persen_selisih_ditanggung_perusahaan numeric(5,2),
  persen_selisih_ditanggung_mitra numeric(5,2),
  aktif boolean DEFAULT true,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW(),
  CONSTRAINT mitra_persen_range_check CHECK (
    (persen_selisih_ditanggung_perusahaan IS NULL OR persen_selisih_ditanggung_perusahaan BETWEEN 0 AND 100)
    AND (persen_selisih_ditanggung_mitra IS NULL OR persen_selisih_ditanggung_mitra BETWEEN 0 AND 100)
  ),
  CONSTRAINT mitra_persen_total_check CHECK (
    persen_selisih_ditanggung_perusahaan IS NULL
    OR persen_selisih_ditanggung_mitra IS NULL
    OR persen_selisih_ditanggung_perusahaan + persen_selisih_ditanggung_mitra = 100
  )
);

CREATE TABLE IF NOT EXISTS public.pabrik (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama varchar(100) NOT NULL,
  alamat text,
  no_hp varchar(30),
  kontak varchar(100),
  harga_pabrik_per_kg numeric(12,2),
  pola_pembayaran text DEFAULT 'per_do',
  rekening_info text,
  aktif boolean DEFAULT true,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

ALTER TABLE public.pabrik
  ADD COLUMN IF NOT EXISTS kontak varchar(100),
  ADD COLUMN IF NOT EXISTS harga_pabrik_per_kg numeric(12,2),
  ADD COLUMN IF NOT EXISTS pola_pembayaran text DEFAULT 'per_do',
  ADD COLUMN IF NOT EXISTS rekening_info text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT NOW();

CREATE TABLE IF NOT EXISTS public.armada_perusahaan (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plat_nomor varchar(30) UNIQUE NOT NULL,
  jenis_kendaraan varchar(80),
  kapasitas_kg numeric(12,2),
  kepemilikan text DEFAULT 'sendiri' CHECK (kepemilikan IN ('sendiri', 'sewa')),
  tarif_default_per_km_per_ton numeric(15,2) DEFAULT 0,
  tarif_default_aktif boolean DEFAULT false,
  aktif boolean DEFAULT true,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

DO $$
BEGIN
  IF to_regclass('public.kendaraan') IS NOT NULL THEN
    EXECUTE '
      INSERT INTO public.armada_perusahaan (
        id, plat_nomor, jenis_kendaraan, kapasitas_kg, kepemilikan, aktif, created_at
      )
      SELECT
        k.id,
        k.plat_nomor,
        k.jenis,
        COALESCE(k.kapasitas_ton, 0) * 1000,
        k.kepemilikan,
        k.aktif,
        k.created_at
      FROM public.kendaraan k
      ON CONFLICT DO NOTHING;
    ';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.armada_mitra (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mitra_id uuid REFERENCES public.mitra(id),
  plat_kendaraan varchar(30),
  nama_sopir varchar(100),
  aktif boolean DEFAULT true,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

ALTER TABLE IF EXISTS public.sopir
  ADD COLUMN IF NOT EXISTS armada_perusahaan_id uuid REFERENCES public.armada_perusahaan(id),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT NOW();

DO $$
BEGIN
  IF to_regclass('public.sopir') IS NOT NULL THEN
    EXECUTE '
      UPDATE public.sopir
      SET armada_perusahaan_id = kendaraan_id
      WHERE armada_perusahaan_id IS NULL
        AND kendaraan_id IS NOT NULL;
    ';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Harga and business settings
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.harga_tbs_lokal (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  harga_per_kg numeric(12,2) NOT NULL CHECK (harga_per_kg >= 0),
  berlaku_mulai timestamptz NOT NULL,
  berlaku_sampai timestamptz,
  aktif boolean DEFAULT true,
  set_oleh uuid REFERENCES public.users(id),
  alasan_override text,
  legacy_harga_tbs_id uuid UNIQUE,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW(),
  CONSTRAINT harga_tbs_lokal_periode_check CHECK (
    berlaku_sampai IS NULL OR berlaku_sampai > berlaku_mulai
  )
);

DO $$
BEGIN
  IF to_regclass('public.harga_tbs') IS NOT NULL THEN
    EXECUTE '
      INSERT INTO public.harga_tbs_lokal (
        harga_per_kg, berlaku_mulai, aktif, set_oleh, legacy_harga_tbs_id, created_at
      )
      SELECT
        h.harga_per_kg,
        h.tanggal::timestamp AT TIME ZONE ''Asia/Jakarta'',
        true,
        h.set_oleh,
        h.id,
        h.created_at
      FROM public.harga_tbs h
      ON CONFLICT (legacy_harga_tbs_id) DO NOTHING;
    ';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.fee_mitra_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mitra_id uuid REFERENCES public.mitra(id),
  fee_per_kg numeric(12,2) NOT NULL DEFAULT 0 CHECK (fee_per_kg >= 0),
  berlaku_mulai timestamptz NOT NULL,
  berlaku_sampai timestamptz,
  aktif boolean DEFAULT true,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz DEFAULT NOW(),
  CONSTRAINT fee_mitra_history_periode_check CHECK (
    berlaku_sampai IS NULL OR berlaku_sampai > berlaku_mulai
  )
);

CREATE TABLE IF NOT EXISTS public.tarif_armada (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  armada_id uuid REFERENCES public.armada_perusahaan(id),
  tarif_per_km_per_ton numeric(15,2) NOT NULL DEFAULT 0 CHECK (tarif_per_km_per_ton >= 0),
  minimum_charge numeric(15,2) NOT NULL DEFAULT 0 CHECK (minimum_charge >= 0),
  berlaku_mulai timestamptz NOT NULL,
  berlaku_sampai timestamptz,
  aktif boolean DEFAULT true,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz DEFAULT NOW(),
  CONSTRAINT tarif_armada_periode_check CHECK (
    berlaku_sampai IS NULL OR berlaku_sampai > berlaku_mulai
  )
);

CREATE TABLE IF NOT EXISTS public.pengaturan_bisnis (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL,
  value_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  scope text NOT NULL DEFAULT 'global' CHECK (scope IN ('global', 'mitra', 'armada')),
  scope_id uuid,
  berlaku_mulai timestamptz DEFAULT NOW(),
  aktif boolean DEFAULT true,
  updated_by uuid REFERENCES public.users(id),
  updated_at timestamptz DEFAULT NOW(),
  created_at timestamptz DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pengaturan_bisnis_active_key_scope
ON public.pengaturan_bisnis (key, scope, COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::uuid))
WHERE aktif = true;

INSERT INTO public.pengaturan_bisnis (key, value_json, scope)
SELECT 'default_fee_per_kg_mitra', '{"amount":0}'::jsonb, 'global'
WHERE NOT EXISTS (
  SELECT 1 FROM public.pengaturan_bisnis
  WHERE key = 'default_fee_per_kg_mitra' AND scope = 'global' AND aktif = true
);

INSERT INTO public.pengaturan_bisnis (key, value_json, scope)
SELECT 'default_persen_selisih_perusahaan', '{"value":50}'::jsonb, 'global'
WHERE NOT EXISTS (
  SELECT 1 FROM public.pengaturan_bisnis
  WHERE key = 'default_persen_selisih_perusahaan' AND scope = 'global' AND aktif = true
);

INSERT INTO public.pengaturan_bisnis (key, value_json, scope)
SELECT 'default_persen_selisih_mitra', '{"value":50}'::jsonb, 'global'
WHERE NOT EXISTS (
  SELECT 1 FROM public.pengaturan_bisnis
  WHERE key = 'default_persen_selisih_mitra' AND scope = 'global' AND aktif = true
);

INSERT INTO public.pengaturan_bisnis (key, value_json, scope)
SELECT 'default_tindakan_kasbon_melebihi_limit', '{"value":"wajib_approval"}'::jsonb, 'global'
WHERE NOT EXISTS (
  SELECT 1 FROM public.pengaturan_bisnis
  WHERE key = 'default_tindakan_kasbon_melebihi_limit' AND scope = 'global' AND aktif = true
);

INSERT INTO public.pengaturan_bisnis (key, value_json, scope)
SELECT 'default_toleransi_anomali_tonase_kg', '{"value":0}'::jsonb, 'global'
WHERE NOT EXISTS (
  SELECT 1 FROM public.pengaturan_bisnis
  WHERE key = 'default_toleransi_anomali_tonase_kg' AND scope = 'global' AND aktif = true
);

INSERT INTO public.pengaturan_bisnis (key, value_json, scope)
SELECT 'dashboard_owner_primary_profit_metric', '{"value":"laba_bersih_kas"}'::jsonb, 'global'
WHERE NOT EXISTS (
  SELECT 1 FROM public.pengaturan_bisnis
  WHERE key = 'dashboard_owner_primary_profit_metric' AND scope = 'global' AND aktif = true
);

-- ---------------------------------------------------------------------------
-- Pembelian, stock, hutang
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.transaksi_beli_tbs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tanggal date NOT NULL,
  petani_id uuid REFERENCES public.petani(id),
  harga_tbs_lokal_id uuid REFERENCES public.harga_tbs_lokal(id),
  berat_kotor_kg numeric(14,2) NOT NULL CHECK (berat_kotor_kg >= 0),
  potongan_type text NOT NULL DEFAULT 'percent' CHECK (potongan_type IN ('percent', 'kg', 'nominal')),
  potongan_value numeric(14,2) NOT NULL DEFAULT 0 CHECK (potongan_value >= 0),
  berat_bersih_kg numeric(14,2) NOT NULL CHECK (berat_bersih_kg >= 0),
  harga_per_kg numeric(12,2) NOT NULL CHECK (harga_per_kg >= 0),
  total_harga numeric(15,2) NOT NULL DEFAULT 0 CHECK (total_harga >= 0),
  potongan_hutang numeric(15,2) NOT NULL DEFAULT 0 CHECK (potongan_hutang >= 0),
  total_bayar_tunai numeric(15,2) NOT NULL DEFAULT 0 CHECK (total_bayar_tunai >= 0),
  no_struk text UNIQUE DEFAULT public.next_no_struk_tbs(CURRENT_DATE),
  status text NOT NULL DEFAULT 'aktif' CHECK (status IN ('draft', 'aktif', 'dibatalkan', 'reversal')),
  reversal_of_id uuid REFERENCES public.transaksi_beli_tbs(id),
  keterangan text,
  legacy_transaksi_beli_id uuid UNIQUE,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

DO $$
BEGIN
  IF to_regclass('public.transaksi_beli') IS NOT NULL THEN
    EXECUTE '
      INSERT INTO public.transaksi_beli_tbs (
        id, tanggal, petani_id, berat_kotor_kg, potongan_type, potongan_value,
        berat_bersih_kg, harga_per_kg, total_harga, potongan_hutang,
        total_bayar_tunai, no_struk, status, keterangan,
        legacy_transaksi_beli_id, created_by, created_at
      )
      SELECT
        t.id,
        t.tanggal,
        t.petani_id,
        t.berat_kotor,
        ''percent'',
        COALESCE(t.persen_potongan, 0),
        t.berat_bersih,
        t.harga_per_kg,
        t.total_harga,
        COALESCE(t.potongan_hutang, 0),
        t.total_bayar_tunai,
        COALESCE(t.no_struk, public.next_no_struk_tbs(t.tanggal)),
        ''aktif'',
        t.keterangan,
        t.id,
        t.created_by,
        t.created_at
      FROM public.transaksi_beli t
      ON CONFLICT DO NOTHING;
    ';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.stok_tbs_lokal_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tanggal date NOT NULL,
  tipe text NOT NULL CHECK (tipe IN ('masuk', 'keluar', 'koreksi', 'reversal')),
  sumber text NOT NULL CHECK (sumber IN ('pembelian_petani', 'pengiriman_pabrik', 'koreksi_manual', 'reversal')),
  transaksi_beli_id uuid REFERENCES public.transaksi_beli_tbs(id),
  pengiriman_id uuid,
  berat_kg numeric(14,2) NOT NULL,
  keterangan text,
  related_ledger_id uuid REFERENCES public.stok_tbs_lokal_ledger(id),
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz DEFAULT NOW()
);

INSERT INTO public.stok_tbs_lokal_ledger (
  tanggal, tipe, sumber, transaksi_beli_id, berat_kg, keterangan, created_by, created_at
)
SELECT
  t.tanggal,
  'masuk',
  'pembelian_petani',
  t.id,
  t.berat_bersih_kg,
  'Migrasi dari transaksi_beli lama',
  t.created_by,
  t.created_at
FROM public.transaksi_beli_tbs t
WHERE NOT EXISTS (
  SELECT 1 FROM public.stok_tbs_lokal_ledger s
  WHERE s.transaksi_beli_id = t.id
    AND s.tipe = 'masuk'
    AND s.sumber = 'pembelian_petani'
);

CREATE TABLE IF NOT EXISTS public.pengiriman_lokal_detail (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pengiriman_id uuid NOT NULL,
  transaksi_beli_id uuid NOT NULL REFERENCES public.transaksi_beli_tbs(id),
  petani_id uuid REFERENCES public.petani(id),
  berat_alokasi_kg numeric(14,2) NOT NULL CHECK (berat_alokasi_kg > 0),
  created_at timestamptz DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.hutang_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pihak_type text NOT NULL CHECK (pihak_type IN ('petani', 'mitra')),
  petani_id uuid REFERENCES public.petani(id),
  mitra_id uuid REFERENCES public.mitra(id),
  tanggal date NOT NULL,
  tipe text NOT NULL CHECK (tipe IN ('debit', 'kredit')),
  sumber text NOT NULL CHECK (
    sumber IN ('kasbon', 'panjar', 'pupuk', 'lainnya', 'bayar_tunai', 'potong_tbs', 'potong_settlement', 'koreksi', 'reversal')
  ),
  jumlah numeric(15,2) NOT NULL CHECK (jumlah >= 0),
  transaksi_beli_id uuid REFERENCES public.transaksi_beli_tbs(id),
  settlement_id uuid,
  legacy_source_table text,
  legacy_source_id uuid,
  keterangan text,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz DEFAULT NOW(),
  CONSTRAINT hutang_ledger_pihak_check CHECK (
    (pihak_type = 'petani' AND petani_id IS NOT NULL AND mitra_id IS NULL)
    OR (pihak_type = 'mitra' AND mitra_id IS NOT NULL AND petani_id IS NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_hutang_ledger_legacy
ON public.hutang_ledger (legacy_source_table, legacy_source_id)
WHERE legacy_source_table IS NOT NULL AND legacy_source_id IS NOT NULL;

DO $$
BEGIN
  IF to_regclass('public.hutang') IS NOT NULL THEN
    EXECUTE '
      INSERT INTO public.hutang_ledger (
        pihak_type, petani_id, tanggal, tipe, sumber, jumlah,
        legacy_source_table, legacy_source_id, keterangan, created_by, created_at
      )
      SELECT
        ''petani'',
        h.petani_id,
        h.tanggal,
        ''debit'',
        h.jenis,
        h.jumlah,
        ''hutang'',
        h.id,
        h.keterangan,
        h.created_by,
        h.created_at
      FROM public.hutang h
      ON CONFLICT DO NOTHING;
    ';
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.hutang_log') IS NOT NULL THEN
    EXECUTE '
      INSERT INTO public.hutang_ledger (
        pihak_type, petani_id, tanggal, tipe, sumber, jumlah,
        transaksi_beli_id, legacy_source_table, legacy_source_id, keterangan, created_at
      )
      SELECT
        ''petani'',
        l.petani_id,
        l.tanggal,
        ''kredit'',
        l.sumber,
        l.jumlah_bayar,
        l.transaksi_beli_id,
        ''hutang_log'',
        l.id,
        l.keterangan,
        l.created_at
      FROM public.hutang_log l
      ON CONFLICT DO NOTHING;
    ';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Pengiriman and factory payments
-- ---------------------------------------------------------------------------

ALTER TABLE public.pengiriman
  ALTER COLUMN status TYPE text,
  ADD COLUMN IF NOT EXISTS sumber text DEFAULT 'lokal',
  ADD COLUMN IF NOT EXISTS mitra_id uuid REFERENCES public.mitra(id),
  ADD COLUMN IF NOT EXISTS nomor_do text,
  ADD COLUMN IF NOT EXISTS tonase_timbang_sumber numeric(14,2),
  ADD COLUMN IF NOT EXISTS tonase_pabrik numeric(14,2),
  ADD COLUMN IF NOT EXISTS tonase_dasar_settlement numeric(14,2),
  ADD COLUMN IF NOT EXISTS selisih_tonase numeric(14,2),
  ADD COLUMN IF NOT EXISTS nilai_selisih_tonase numeric(15,2),
  ADD COLUMN IF NOT EXISTS persen_selisih_ditanggung_perusahaan numeric(5,2),
  ADD COLUMN IF NOT EXISTS persen_selisih_ditanggung_mitra numeric(5,2),
  ADD COLUMN IF NOT EXISTS koreksi_selisih_dibayar_perusahaan numeric(15,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS potongan_sortasi_type text DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS potongan_sortasi_value numeric(14,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS potongan_sortasi_rupiah numeric(15,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS biaya_timbang numeric(15,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS potongan_pabrik_lain numeric(15,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_pembayaran_pabrik numeric(15,2),
  ADD COLUMN IF NOT EXISTS armada_type text DEFAULT 'perusahaan',
  ADD COLUMN IF NOT EXISTS armada_perusahaan_id uuid REFERENCES public.armada_perusahaan(id),
  ADD COLUMN IF NOT EXISTS kendaraan_mitra_text text,
  ADD COLUMN IF NOT EXISTS sopir_mitra_text text,
  ADD COLUMN IF NOT EXISTS jarak_armada_km numeric(12,2),
  ADD COLUMN IF NOT EXISTS tonase_muatan_armada_ton numeric(12,3),
  ADD COLUMN IF NOT EXISTS tarif_armada_per_km_per_ton numeric(15,2),
  ADD COLUMN IF NOT EXISTS tarif_armada_source text,
  ADD COLUMN IF NOT EXISTS alasan_override_tarif_armada text,
  ADD COLUMN IF NOT EXISTS biaya_armada_dibebankan_ke_mitra numeric(15,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS biaya_aktual_armada_perusahaan numeric(15,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS settlement_id uuid,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT NOW();

UPDATE public.pengiriman
SET nomor_do = COALESCE(nomor_do, no_do),
    tonase_timbang_sumber = COALESCE(tonase_timbang_sumber, tonase_kirim),
    tonase_pabrik = COALESCE(tonase_pabrik, tonase_kirim),
    tonase_dasar_settlement = COALESCE(tonase_dasar_settlement, tonase_kirim),
    total_pembayaran_pabrik = COALESCE(total_pembayaran_pabrik, total_harga_pabrik),
    sumber = COALESCE(sumber, 'lokal')
WHERE true;

DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.pengiriman'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.pengiriman DROP CONSTRAINT %I', c.conname);
  END LOOP;
END;
$$;

ALTER TABLE public.pengiriman
  DROP CONSTRAINT IF EXISTS pengiriman_sumber_check,
  DROP CONSTRAINT IF EXISTS pengiriman_sortasi_type_check,
  DROP CONSTRAINT IF EXISTS pengiriman_armada_type_check,
  DROP CONSTRAINT IF EXISTS pengiriman_tarif_armada_source_check;

ALTER TABLE public.pengiriman
  ADD CONSTRAINT pengiriman_status_check
  CHECK (
    status IN (
      'draft',
      'stok_siap_kirim',
      'dikirim',
      'diterima',
      'diterima_pabrik',
      'dibayar',
      'dibayar_pabrik',
      'selesai',
      'dibatalkan',
      'dikirim_mitra',
      'menunggu_pembayaran_pabrik',
      'sudah_dibayar_pabrik_ke_perusahaan',
      'menunggu_pembayaran_mitra',
      'pembayaran_mitra_sebagian_koreksi',
      'settlement_lunas'
    )
  );

ALTER TABLE public.pengiriman
  ADD CONSTRAINT pengiriman_sumber_check
  CHECK (sumber IN ('lokal', 'mitra'));

ALTER TABLE public.pengiriman
  ADD CONSTRAINT pengiriman_sortasi_type_check
  CHECK (potongan_sortasi_type IN ('none', 'kg', 'percent', 'nominal'));

ALTER TABLE public.pengiriman
  ADD CONSTRAINT pengiriman_armada_type_check
  CHECK (armada_type IN ('perusahaan', 'mitra'));

ALTER TABLE public.pengiriman
  ADD CONSTRAINT pengiriman_tarif_armada_source_check
  CHECK (tarif_armada_source IS NULL OR tarif_armada_source IN ('default', 'override'));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'idx_pengiriman_nomor_do_pabrik_unique'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.pengiriman
      WHERE nomor_do IS NOT NULL
        AND status <> 'draft'
        AND status <> 'dibatalkan'
      GROUP BY pabrik_id, nomor_do
      HAVING COUNT(*) > 1
    ) THEN
      EXECUTE '
        CREATE UNIQUE INDEX idx_pengiriman_nomor_do_pabrik_unique
        ON public.pengiriman (pabrik_id, nomor_do)
        WHERE nomor_do IS NOT NULL AND status <> ''draft'' AND status <> ''dibatalkan''
      ';
    ELSE
      RAISE NOTICE 'Skip unique DO index because duplicate DO data exists.';
    END IF;
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.pembayaran_pabrik (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pabrik_id uuid REFERENCES public.pabrik(id),
  tanggal_bayar date NOT NULL,
  total_bayar numeric(15,2) NOT NULL CHECK (total_bayar >= 0),
  metode text,
  rekening_tujuan text,
  referensi_transfer text,
  bukti_transfer_url text,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'teralokasi_sebagian', 'teralokasi_penuh', 'dibatalkan')),
  keterangan text,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.pembayaran_pabrik_detail (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pembayaran_pabrik_id uuid NOT NULL REFERENCES public.pembayaran_pabrik(id) ON DELETE CASCADE,
  pengiriman_id uuid NOT NULL REFERENCES public.pengiriman(id),
  nomor_do text,
  jumlah_dialokasikan numeric(15,2) NOT NULL CHECK (jumlah_dialokasikan >= 0),
  tonase_pabrik numeric(14,2),
  tonase_dasar_settlement numeric(14,2),
  harga_pabrik_per_kg numeric(12,2),
  potongan_sortasi_type text DEFAULT 'none' CHECK (potongan_sortasi_type IN ('none', 'kg', 'percent', 'nominal')),
  potongan_sortasi_value numeric(14,2) DEFAULT 0,
  potongan_sortasi_rupiah numeric(15,2) DEFAULT 0,
  biaya_timbang numeric(15,2) DEFAULT 0,
  potongan_pabrik_lain numeric(15,2) DEFAULT 0,
  created_at timestamptz DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Mitra settlement and payments
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.settlement_mitra (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mitra_id uuid NOT NULL REFERENCES public.mitra(id),
  pengiriman_id uuid NOT NULL REFERENCES public.pengiriman(id),
  nomor_do text,
  tanggal_settlement date,
  tonase_timbang_mitra numeric(14,2),
  tonase_pabrik numeric(14,2),
  tonase_dasar_settlement numeric(14,2),
  selisih_tonase numeric(14,2),
  nilai_selisih_tonase numeric(15,2),
  persen_selisih_ditanggung_perusahaan numeric(5,2),
  persen_selisih_ditanggung_mitra numeric(5,2),
  koreksi_selisih_dibayar_perusahaan numeric(15,2) DEFAULT 0,
  harga_pabrik_per_kg numeric(12,2),
  total_bruto_pabrik numeric(15,2),
  potongan_sortasi_type text DEFAULT 'none' CHECK (potongan_sortasi_type IN ('none', 'kg', 'percent', 'nominal')),
  potongan_sortasi_value numeric(14,2) DEFAULT 0,
  potongan_sortasi_rupiah numeric(15,2) DEFAULT 0,
  biaya_timbang numeric(15,2) DEFAULT 0,
  potongan_pabrik_lain numeric(15,2) DEFAULT 0,
  total_pembayaran_pabrik numeric(15,2),
  fee_per_kg numeric(12,2) DEFAULT 0,
  fee_perusahaan numeric(15,2) DEFAULT 0,
  potongan_armada numeric(15,2) DEFAULT 0,
  potongan_hutang_kasbon numeric(15,2) DEFAULT 0,
  potongan_lain numeric(15,2) DEFAULT 0,
  total_hak_mitra numeric(15,2) DEFAULT 0,
  total_dibayar numeric(15,2) DEFAULT 0,
  sisa_bayar numeric(15,2) DEFAULT 0,
  status text NOT NULL DEFAULT 'belum_dihitung' CHECK (
    status IN ('belum_dihitung', 'menunggu_pembayaran_pabrik', 'menunggu_bayar_mitra', 'sebagian_koreksi', 'lunas', 'dibatalkan')
  ),
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_settlement_mitra_pengiriman_unique
ON public.settlement_mitra (pengiriman_id)
WHERE status <> 'dibatalkan';

CREATE TABLE IF NOT EXISTS public.pembayaran_mitra (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_id uuid NOT NULL REFERENCES public.settlement_mitra(id),
  mitra_id uuid NOT NULL REFERENCES public.mitra(id),
  tanggal date NOT NULL,
  jumlah numeric(15,2) NOT NULL CHECK (jumlah >= 0),
  metode text,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'dibayar', 'sebagian_koreksi', 'dibatalkan')),
  keterangan text,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

ALTER TABLE public.hutang_ledger
  DROP CONSTRAINT IF EXISTS hutang_ledger_settlement_fk;

ALTER TABLE public.hutang_ledger
  ADD CONSTRAINT hutang_ledger_settlement_fk
  FOREIGN KEY (settlement_id) REFERENCES public.settlement_mitra(id);

-- ---------------------------------------------------------------------------
-- Biaya and proof files
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.biaya_operasional (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tanggal date NOT NULL,
  kategori text NOT NULL,
  jumlah numeric(15,2) NOT NULL,
  keterangan text,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

ALTER TABLE public.biaya_operasional
  ALTER COLUMN kategori TYPE text,
  ADD COLUMN IF NOT EXISTS tipe_biaya text DEFAULT 'perusahaan_murni',
  ADD COLUMN IF NOT EXISTS pengiriman_id uuid REFERENCES public.pengiriman(id),
  ADD COLUMN IF NOT EXISTS settlement_id uuid REFERENCES public.settlement_mitra(id),
  ADD COLUMN IF NOT EXISTS dibebankan_ke_mitra boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS jumlah_dibebankan_ke_mitra numeric(15,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'aktif',
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT NOW();

DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.biaya_operasional'::regclass
      AND contype = 'c'
      AND (
        pg_get_constraintdef(oid) ILIKE '%kategori%'
        OR pg_get_constraintdef(oid) ILIKE '%status%'
        OR pg_get_constraintdef(oid) ILIKE '%tipe_biaya%'
      )
  LOOP
    EXECUTE format('ALTER TABLE public.biaya_operasional DROP CONSTRAINT %I', c.conname);
  END LOOP;
END;
$$;

ALTER TABLE public.biaya_operasional
  ADD CONSTRAINT biaya_operasional_kategori_check
  CHECK (kategori IN ('solar', 'gaji_sopir', 'kuli', 'retribusi', 'perawatan', 'lainnya'));

ALTER TABLE public.biaya_operasional
  ADD CONSTRAINT biaya_operasional_tipe_check
  CHECK (tipe_biaya IN ('perusahaan_murni', 'bantuan_mitra'));

ALTER TABLE public.biaya_operasional
  ADD CONSTRAINT biaya_operasional_status_check
  CHECK (status IN ('aktif', 'dibatalkan', 'reversal'));

CREATE TABLE IF NOT EXISTS public.bukti_pembayaran (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipe text NOT NULL CHECK (tipe IN ('pembayaran_mitra', 'pembayaran_petani', 'pembayaran_pabrik')),
  nomor_bukti text UNIQUE NOT NULL,
  pembayaran_mitra_id uuid REFERENCES public.pembayaran_mitra(id),
  pembayaran_pabrik_id uuid REFERENCES public.pembayaran_pabrik(id),
  transaksi_beli_id uuid REFERENCES public.transaksi_beli_tbs(id),
  file_url text,
  format text NOT NULL CHECK (format IN ('pdf', 'image')),
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Audit log
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid REFERENCES public.users(id),
  actor_role text,
  entity_type text NOT NULL,
  entity_id uuid,
  action text NOT NULL CHECK (action IN ('create', 'update', 'delete', 'cancel', 'approve', 'export', 'override')),
  before_json jsonb,
  after_json jsonb,
  alasan text,
  approved_by uuid REFERENCES public.users(id),
  approved_at timestamptz,
  created_at timestamptz DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.write_audit_log(
  p_entity_type text,
  p_entity_id uuid,
  p_action text,
  p_before_json jsonb DEFAULT NULL,
  p_after_json jsonb DEFAULT NULL,
  p_alasan text DEFAULT NULL,
  p_approved_by uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_id uuid;
BEGIN
  INSERT INTO public.audit_log (
    actor_user_id, actor_role, entity_type, entity_id, action,
    before_json, after_json, alasan, approved_by, approved_at
  )
  VALUES (
    auth.uid(), public.current_app_role(), p_entity_type, p_entity_id, p_action,
    p_before_json, p_after_json, p_alasan, p_approved_by,
    CASE WHEN p_approved_by IS NULL THEN NULL ELSE NOW() END
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_petani_aktif_nama ON public.petani (aktif, nama);
CREATE INDEX IF NOT EXISTS idx_mitra_aktif_nama ON public.mitra (aktif, nama);
CREATE INDEX IF NOT EXISTS idx_harga_tbs_lokal_aktif_mulai ON public.harga_tbs_lokal (aktif, berlaku_mulai DESC);
CREATE INDEX IF NOT EXISTS idx_fee_mitra_history_mitra_mulai ON public.fee_mitra_history (mitra_id, berlaku_mulai DESC);
CREATE INDEX IF NOT EXISTS idx_tarif_armada_armada_mulai ON public.tarif_armada (armada_id, berlaku_mulai DESC);
CREATE INDEX IF NOT EXISTS idx_transaksi_beli_tbs_tanggal ON public.transaksi_beli_tbs (tanggal);
CREATE INDEX IF NOT EXISTS idx_transaksi_beli_tbs_petani ON public.transaksi_beli_tbs (petani_id);
CREATE INDEX IF NOT EXISTS idx_stok_tbs_lokal_tanggal ON public.stok_tbs_lokal_ledger (tanggal);
CREATE INDEX IF NOT EXISTS idx_stok_tbs_lokal_transaksi ON public.stok_tbs_lokal_ledger (transaksi_beli_id);
CREATE INDEX IF NOT EXISTS idx_pengiriman_sumber_tanggal ON public.pengiriman (sumber, tanggal);
CREATE INDEX IF NOT EXISTS idx_pengiriman_mitra ON public.pengiriman (mitra_id);
CREATE INDEX IF NOT EXISTS idx_pembayaran_pabrik_pabrik_tanggal ON public.pembayaran_pabrik (pabrik_id, tanggal_bayar);
CREATE INDEX IF NOT EXISTS idx_pembayaran_pabrik_detail_pengiriman ON public.pembayaran_pabrik_detail (pengiriman_id);
CREATE INDEX IF NOT EXISTS idx_settlement_mitra_mitra ON public.settlement_mitra (mitra_id);
CREATE INDEX IF NOT EXISTS idx_hutang_ledger_pihak ON public.hutang_ledger (pihak_type, petani_id, mitra_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON public.audit_log (entity_type, entity_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'users',
    'petani',
    'mitra',
    'pabrik',
    'armada_perusahaan',
    'armada_mitra',
    'harga_tbs_lokal',
    'pengaturan_bisnis',
    'transaksi_beli_tbs',
    'pengiriman',
    'pembayaran_pabrik',
    'settlement_mitra',
    'pembayaran_mitra',
    'biaya_operasional'
  ]
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS set_updated_at ON public.%I', table_name);
    EXECUTE format(
      'CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()',
      table_name
    );
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'users',
    'petani',
    'mitra',
    'pabrik',
    'armada_perusahaan',
    'armada_mitra',
    'sopir',
    'harga_tbs',
    'harga_tbs_lokal',
    'fee_mitra_history',
    'tarif_armada',
    'transaksi_beli',
    'transaksi_beli_tbs',
    'stok_tbs_lokal_ledger',
    'pengiriman_lokal_detail',
    'pengiriman',
    'hutang',
    'hutang_log',
    'hutang_ledger',
    'pembayaran_pabrik',
    'pembayaran_pabrik_detail',
    'settlement_mitra',
    'pembayaran_mitra',
    'biaya_operasional',
    'bukti_pembayaran',
    'pengaturan_bisnis',
    'audit_log'
  ]
  LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
      EXECUTE format('DROP POLICY IF EXISTS "Authenticated full access" ON public.%I', table_name);
      EXECUTE format('DROP POLICY IF EXISTS "read_authenticated" ON public.%I', table_name);
      EXECUTE format('DROP POLICY IF EXISTS "write_operations" ON public.%I', table_name);
      EXECUTE format('DROP POLICY IF EXISTS "write_finance" ON public.%I', table_name);
      EXECUTE format('DROP POLICY IF EXISTS "write_owner_super_admin" ON public.%I', table_name);
      EXECUTE format('DROP POLICY IF EXISTS "insert_authenticated" ON public.%I', table_name);
      EXECUTE format('DROP POLICY IF EXISTS "select_own_or_privileged" ON public.%I', table_name);
      EXECUTE format('DROP POLICY IF EXISTS "manage_users_super_admin" ON public.%I', table_name);
    END IF;
  END LOOP;
END;
$$;

CREATE POLICY "select_own_or_privileged"
ON public.users
FOR SELECT TO authenticated
USING (
  id = auth.uid()
  OR public.has_app_role(ARRAY['owner', 'super_admin'])
);

CREATE POLICY "manage_users_super_admin"
ON public.users
FOR ALL TO authenticated
USING (public.has_app_role(ARRAY['super_admin']))
WITH CHECK (public.has_app_role(ARRAY['super_admin']));

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'petani',
    'mitra',
    'pabrik',
    'armada_perusahaan',
    'armada_mitra',
    'sopir',
    'harga_tbs',
    'harga_tbs_lokal',
    'fee_mitra_history',
    'tarif_armada',
    'transaksi_beli',
    'transaksi_beli_tbs',
    'stok_tbs_lokal_ledger',
    'pengiriman_lokal_detail',
    'pengiriman'
  ]
  LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL THEN
      EXECUTE format(
        'CREATE POLICY "read_authenticated" ON public.%I
         FOR SELECT TO authenticated USING (true)',
        table_name
      );
      EXECUTE format(
        'CREATE POLICY "write_operations" ON public.%I
         FOR ALL TO authenticated
         USING (public.has_app_role(ARRAY[''owner'', ''super_admin'', ''admin_operasional'']))
         WITH CHECK (public.has_app_role(ARRAY[''owner'', ''super_admin'', ''admin_operasional'']))',
        table_name
      );
    END IF;
  END LOOP;
END;
$$;

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'hutang',
    'hutang_log',
    'hutang_ledger',
    'pembayaran_pabrik',
    'pembayaran_pabrik_detail',
    'settlement_mitra',
    'pembayaran_mitra',
    'bukti_pembayaran'
  ]
  LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL THEN
      EXECUTE format(
        'CREATE POLICY "read_authenticated" ON public.%I
         FOR SELECT TO authenticated USING (true)',
        table_name
      );
      EXECUTE format(
        'CREATE POLICY "write_finance" ON public.%I
         FOR ALL TO authenticated
         USING (public.has_app_role(ARRAY[''owner'', ''super_admin'', ''admin_keuangan'']))
         WITH CHECK (public.has_app_role(ARRAY[''owner'', ''super_admin'', ''admin_keuangan'']))',
        table_name
      );
    END IF;
  END LOOP;
END;
$$;

CREATE POLICY "read_authenticated"
ON public.biaya_operasional
FOR SELECT TO authenticated
USING (true);

CREATE POLICY "write_finance"
ON public.biaya_operasional
FOR ALL TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']));

CREATE POLICY "read_authenticated"
ON public.pengaturan_bisnis
FOR SELECT TO authenticated
USING (true);

CREATE POLICY "write_owner_super_admin"
ON public.pengaturan_bisnis
FOR ALL TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin']));

CREATE POLICY "read_authenticated"
ON public.audit_log
FOR SELECT TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin']));

CREATE POLICY "insert_authenticated"
ON public.audit_log
FOR INSERT TO authenticated
WITH CHECK (actor_user_id = auth.uid() OR actor_user_id IS NULL);

COMMIT;
