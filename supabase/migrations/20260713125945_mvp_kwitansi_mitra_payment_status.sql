-- Sawit CB - Status pembayaran kwitansi mitra MVP
-- Mencatat kwitansi yang sudah dibayar owner ke mitra sebagai batch pembayaran.

BEGIN;

CREATE TABLE IF NOT EXISTS public.pembayaran_mitra_kwitansi (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  master_mitra_id uuid NOT NULL REFERENCES public.master_mitra(id),
  periode_dari date NOT NULL,
  periode_sampai date NOT NULL,
  status text NOT NULL DEFAULT 'dibayar' CHECK (status IN ('dibayar', 'perlu_review', 'dibatalkan')),
  tanggal_bayar date NOT NULL DEFAULT CURRENT_DATE,
  dibayar_at timestamptz NOT NULL DEFAULT now(),
  metode_bayar text NOT NULL DEFAULT 'tunai' CHECK (metode_bayar IN ('tunai', 'transfer', 'lainnya')),
  total_tonase numeric(15,2) NOT NULL DEFAULT 0,
  total_nilai_bersih numeric(15,2) NOT NULL DEFAULT 0,
  total_panjar numeric(15,2) NOT NULL DEFAULT 0,
  nominal_dibayar numeric(15,2) NOT NULL DEFAULT 0,
  jumlah_transaksi integer NOT NULL DEFAULT 0,
  panjar_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
  panjar_snapshot_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  transaksi_snapshot_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  catatan text,
  review_reason text,
  created_by uuid REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES public.users(id),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pembayaran_mitra_kwitansi_periode_check CHECK (periode_sampai >= periode_dari)
);

CREATE TABLE IF NOT EXISTS public.pembayaran_mitra_kwitansi_item (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pembayaran_id uuid NOT NULL REFERENCES public.pembayaran_mitra_kwitansi(id) ON DELETE CASCADE,
  transaksi_mitra_id uuid NOT NULL REFERENCES public.transaksi_mitra(id),
  tanggal date NOT NULL,
  waktu_transaksi timestamptz,
  sopir_aktual_nama text,
  plat_nomor text,
  tonase_snapshot numeric(15,2) NOT NULL DEFAULT 0,
  harga_bersih_per_kg_snapshot numeric(15,2) NOT NULL DEFAULT 0,
  total_nilai_bersih_snapshot numeric(15,2) NOT NULL DEFAULT 0,
  status_transaksi_snapshot text NOT NULL DEFAULT 'aktif',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pembayaran_mitra_kwitansi_item_unique_payment_trx UNIQUE (pembayaran_id, transaksi_mitra_id),
  CONSTRAINT pembayaran_mitra_kwitansi_item_unique_trx UNIQUE (transaksi_mitra_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pembayaran_mitra_kwitansi_unique_active_period
ON public.pembayaran_mitra_kwitansi (master_mitra_id, periode_dari, periode_sampai)
WHERE status <> 'dibatalkan';

CREATE INDEX IF NOT EXISTS idx_pembayaran_mitra_kwitansi_mitra_period
ON public.pembayaran_mitra_kwitansi (master_mitra_id, periode_dari DESC, periode_sampai DESC);

CREATE INDEX IF NOT EXISTS idx_pembayaran_mitra_kwitansi_status_bayar
ON public.pembayaran_mitra_kwitansi (status, tanggal_bayar DESC);

CREATE INDEX IF NOT EXISTS idx_pembayaran_mitra_kwitansi_item_payment
ON public.pembayaran_mitra_kwitansi_item (pembayaran_id);

ALTER TABLE public.pembayaran_mitra_kwitansi ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pembayaran_mitra_kwitansi_item ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "read_authenticated" ON public.pembayaran_mitra_kwitansi;
CREATE POLICY "read_authenticated"
ON public.pembayaran_mitra_kwitansi
FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS "write_finance" ON public.pembayaran_mitra_kwitansi;
CREATE POLICY "write_finance"
ON public.pembayaran_mitra_kwitansi
FOR ALL TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

DROP POLICY IF EXISTS "read_authenticated" ON public.pembayaran_mitra_kwitansi_item;
CREATE POLICY "read_authenticated"
ON public.pembayaran_mitra_kwitansi_item
FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS "write_finance" ON public.pembayaran_mitra_kwitansi_item;
CREATE POLICY "write_finance"
ON public.pembayaran_mitra_kwitansi_item
FOR ALL TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pembayaran_mitra_kwitansi TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pembayaran_mitra_kwitansi_item TO authenticated;

DROP TRIGGER IF EXISTS set_updated_at ON public.pembayaran_mitra_kwitansi;
CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.pembayaran_mitra_kwitansi
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

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
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
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
    CURRENT_DATE,
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
    auth.uid(),
    auth.uid()
  )
  RETURNING * INTO v_payment;

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
    UPDATE public.panjar_mitra
    SET status = 'lunas'
    WHERE id = ANY(v_panjar_ids);
  END IF;

  RETURN v_payment;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text) TO authenticated;

COMMIT;
