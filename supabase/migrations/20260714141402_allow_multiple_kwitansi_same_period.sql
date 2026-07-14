-- Sawit CB - izinkan lebih dari satu kwitansi mitra dalam periode yang sama.
--
-- Alasan bisnis:
-- Mitra bisa mengirim dan langsung dibayar beberapa kali pada tanggal yang sama.
-- Kwitansi berikutnya harus hanya mengambil transaksi yang belum pernah masuk
-- item kwitansi aktif, bukan terkunci oleh kombinasi mitra + tanggal.

BEGIN;

DROP INDEX IF EXISTS public.idx_pembayaran_mitra_kwitansi_unique_active_period;

ALTER TABLE public.pembayaran_mitra_kwitansi
  ADD COLUMN IF NOT EXISTS mode_pembayaran text NOT NULL DEFAULT 'single',
  ADD COLUMN IF NOT EXISTS mitra_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
  ADD COLUMN IF NOT EXISTS penerima_label text,
  ADD COLUMN IF NOT EXISTS jumlah_mitra integer NOT NULL DEFAULT 1;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'pembayaran_mitra_kwitansi_mode_check'
      AND conrelid = 'public.pembayaran_mitra_kwitansi'::regclass
  ) THEN
    ALTER TABLE public.pembayaran_mitra_kwitansi
      ADD CONSTRAINT pembayaran_mitra_kwitansi_mode_check
      CHECK (mode_pembayaran IN ('single', 'gabungan'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'pembayaran_mitra_kwitansi_jumlah_mitra_check'
      AND conrelid = 'public.pembayaran_mitra_kwitansi'::regclass
  ) THEN
    ALTER TABLE public.pembayaran_mitra_kwitansi
      ADD CONSTRAINT pembayaran_mitra_kwitansi_jumlah_mitra_check
      CHECK (jumlah_mitra > 0);
  END IF;
END;
$$;

ALTER TABLE public.pembayaran_mitra_kwitansi_item
  ADD COLUMN IF NOT EXISTS master_mitra_id uuid REFERENCES public.master_mitra(id),
  ADD COLUMN IF NOT EXISTS mitra_label_snapshot text;

CREATE TABLE IF NOT EXISTS public.pembayaran_mitra_kwitansi_mitra (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pembayaran_id uuid NOT NULL REFERENCES public.pembayaran_mitra_kwitansi(id) ON DELETE CASCADE,
  master_mitra_id uuid NOT NULL REFERENCES public.master_mitra(id),
  mitra_label_snapshot text,
  total_tonase numeric(15,2) NOT NULL DEFAULT 0,
  total_nilai_bersih numeric(15,2) NOT NULL DEFAULT 0,
  jumlah_transaksi integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pembayaran_mitra_kwitansi_mitra_unique UNIQUE (pembayaran_id, master_mitra_id),
  CONSTRAINT pembayaran_mitra_kwitansi_mitra_total_check CHECK (
    total_tonase >= 0
    AND total_nilai_bersih >= 0
    AND jumlah_transaksi >= 0
  )
);

ALTER TABLE public.pembayaran_mitra_kwitansi_mitra ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "read_authenticated" ON public.pembayaran_mitra_kwitansi_mitra;
CREATE POLICY "read_authenticated"
ON public.pembayaran_mitra_kwitansi_mitra
FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS "write_finance" ON public.pembayaran_mitra_kwitansi_mitra;
CREATE POLICY "write_finance"
ON public.pembayaran_mitra_kwitansi_mitra
FOR ALL TO authenticated
USING (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']))
WITH CHECK (public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']));

GRANT SELECT, INSERT, UPDATE ON public.pembayaran_mitra_kwitansi_mitra TO authenticated;
REVOKE DELETE ON public.pembayaran_mitra_kwitansi_mitra FROM authenticated, anon;

CREATE INDEX IF NOT EXISTS idx_pembayaran_mitra_kwitansi_mitra_payment
ON public.pembayaran_mitra_kwitansi_mitra (pembayaran_id);

CREATE INDEX IF NOT EXISTS idx_pembayaran_mitra_kwitansi_mitra_mitra
ON public.pembayaran_mitra_kwitansi_mitra (master_mitra_id);

CREATE INDEX IF NOT EXISTS idx_pembayaran_mitra_kwitansi_mitra_ids_gin
ON public.pembayaran_mitra_kwitansi USING gin (mitra_ids);

CREATE INDEX IF NOT EXISTS idx_pembayaran_mitra_kwitansi_item_mitra
ON public.pembayaran_mitra_kwitansi_item (master_mitra_id, tanggal DESC);

UPDATE public.pembayaran_mitra_kwitansi pay
SET mitra_ids = ARRAY[pay.master_mitra_id],
    jumlah_mitra = 1,
    mode_pembayaran = 'single',
    penerima_label = COALESCE(pay.penerima_label, mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode)
FROM public.master_mitra mm
WHERE pay.master_mitra_id = mm.id
  AND (pay.mitra_ids = '{}'::uuid[] OR pay.penerima_label IS NULL);

UPDATE public.pembayaran_mitra_kwitansi_item item
SET master_mitra_id = tm.mitra_id,
    mitra_label_snapshot = COALESCE(mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode)
FROM public.transaksi_mitra tm
LEFT JOIN public.master_mitra mm ON mm.id = tm.mitra_id
WHERE item.transaksi_mitra_id = tm.id
  AND item.master_mitra_id IS NULL;

INSERT INTO public.pembayaran_mitra_kwitansi_mitra (
  pembayaran_id,
  master_mitra_id,
  mitra_label_snapshot,
  total_tonase,
  total_nilai_bersih,
  jumlah_transaksi
)
SELECT
  item.pembayaran_id,
  item.master_mitra_id,
  COALESCE(item.mitra_label_snapshot, mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode),
  COALESCE(SUM(item.tonase_snapshot), 0)::numeric(15,2),
  COALESCE(SUM(item.total_nilai_bersih_snapshot), 0)::numeric(15,2),
  COUNT(*)::integer
FROM public.pembayaran_mitra_kwitansi_item item
LEFT JOIN public.master_mitra mm ON mm.id = item.master_mitra_id
WHERE item.master_mitra_id IS NOT NULL
GROUP BY item.pembayaran_id, item.master_mitra_id, COALESCE(item.mitra_label_snapshot, mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode)
ON CONFLICT (pembayaran_id, master_mitra_id) DO NOTHING;

DROP FUNCTION IF EXISTS public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text);

CREATE OR REPLACE FUNCTION public.create_pembayaran_mitra_kwitansi(
  p_master_mitra_id uuid,
  p_periode_dari date,
  p_periode_sampai date,
  p_metode_bayar text DEFAULT 'tunai',
  p_catatan text DEFAULT NULL,
  p_master_mitra_ids uuid[] DEFAULT NULL,
  p_penerima_label text DEFAULT NULL
)
RETURNS public.pembayaran_mitra_kwitansi
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payment public.pembayaran_mitra_kwitansi%ROWTYPE;
  v_mitra_ids uuid[] := '{}'::uuid[];
  v_mitra_count integer := 0;
  v_found_mitra_count integer := 0;
  v_primary_mitra_id uuid;
  v_penerima_label text;
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
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat pembayaran mitra.'
      USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT mitra_id), '{}'::uuid[])
  INTO v_mitra_ids
  FROM (
    SELECT unnest(COALESCE(p_master_mitra_ids, '{}'::uuid[])) AS mitra_id
    UNION ALL
    SELECT p_master_mitra_id
  ) selected
  WHERE mitra_id IS NOT NULL;

  v_mitra_count := COALESCE(array_length(v_mitra_ids, 1), 0);

  IF v_mitra_count <= 0 THEN
    RAISE EXCEPTION 'Minimal satu mitra wajib dipilih.'
      USING ERRCODE = '22023';
  END IF;

  SELECT count(*)::integer
  INTO v_found_mitra_count
  FROM public.master_mitra
  WHERE id = ANY(v_mitra_ids)
    AND COALESCE(aktif, true) = true;

  IF v_found_mitra_count <> v_mitra_count THEN
    RAISE EXCEPTION 'Ada mitra yang tidak ditemukan atau sudah tidak aktif.'
      USING ERRCODE = 'P0002';
  END IF;

  v_primary_mitra_id := COALESCE(p_master_mitra_id, v_mitra_ids[1]);

  SELECT COALESCE(
    NULLIF(btrim(COALESCE(p_penerima_label, '')), ''),
    string_agg(COALESCE(mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode), ', ' ORDER BY mm.kode, mm.nama)
  )
  INTO v_penerima_label
  FROM public.master_mitra mm
  WHERE mm.id = ANY(v_mitra_ids);

  IF p_periode_dari IS NULL OR p_periode_sampai IS NULL OR p_periode_sampai < p_periode_dari THEN
    RAISE EXCEPTION 'Periode pembayaran tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  IF COALESCE(p_metode_bayar, 'tunai') NOT IN ('tunai', 'transfer', 'lainnya') THEN
    RAISE EXCEPTION 'Metode bayar tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  WITH trx AS (
    SELECT
      tm.id,
      tm.mitra_id,
      COALESCE(mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode) AS mitra_label,
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
    LEFT JOIN public.master_mitra mm ON mm.id = tm.mitra_id
    WHERE tm.mitra_id = ANY(v_mitra_ids)
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
        'master_mitra_id', mitra_id,
        'mitra_label', mitra_label,
        'tanggal', tanggal,
        'created_at', created_at,
        'sopir_aktual_nama', COALESCE(sopir_aktual_nama, sopir_default_nama),
        'plat_nomor', plat_nomor,
        'tonase', tonase,
        'harga_bersih_per_kg', harga_bersih_per_kg,
        'total_nilai_bersih', total_nilai_bersih,
        'status', status
      )
      ORDER BY mitra_label, tanggal, created_at
    ), '[]'::jsonb)
  INTO v_jumlah_transaksi, v_total_tonase, v_total_nilai_bersih, v_transaksi_snapshot
  FROM trx;

  IF v_jumlah_transaksi <= 0 THEN
    RAISE EXCEPTION 'Tidak ada transaksi baru yang belum dibayar pada periode ini.'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT
    COALESCE(SUM(pm.jumlah), 0)::numeric(15,2),
    COALESCE(array_agg(pm.id ORDER BY label.mitra_label, pm.tanggal, pm.created_at), '{}'::uuid[]),
    COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', pm.id,
        'master_mitra_id', pm.mitra_id,
        'mitra_label', label.mitra_label,
        'tanggal', pm.tanggal,
        'jumlah', pm.jumlah,
        'keterangan', pm.keterangan
      )
      ORDER BY label.mitra_label, pm.tanggal, pm.created_at
    ), '[]'::jsonb)
  INTO v_total_panjar, v_panjar_ids, v_panjar_snapshot
  FROM public.panjar_mitra pm
  LEFT JOIN LATERAL (
    SELECT COALESCE(mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode) AS mitra_label
    FROM public.master_mitra mm
    WHERE mm.id = pm.mitra_id
  ) label ON true
  WHERE pm.mitra_id = ANY(v_mitra_ids)
    AND pm.status = 'belum_lunas';

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
    mode_pembayaran,
    mitra_ids,
    penerima_label,
    jumlah_mitra,
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
    v_primary_mitra_id,
    p_periode_dari,
    p_periode_sampai,
    'dibayar',
    (now() AT TIME ZONE 'Asia/Jakarta')::date,
    now(),
    COALESCE(p_metode_bayar, 'tunai'),
    CASE WHEN v_mitra_count > 1 THEN 'gabungan' ELSE 'single' END,
    v_mitra_ids,
    v_penerima_label,
    v_mitra_count,
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
    master_mitra_id,
    mitra_label_snapshot,
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
    tm.mitra_id,
    COALESCE(mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode),
    tm.tanggal,
    tm.created_at,
    COALESCE(tm.sopir_aktual_nama, tm.sopir_default_nama),
    tm.plat_nomor,
    tm.tonase,
    COALESCE(tm.harga_bersih_per_kg, tm.harga_harian, 0),
    COALESCE(tm.total_nilai_bersih, tm.total_kotor, 0),
    COALESCE(tm.status, 'aktif')
  FROM public.transaksi_mitra tm
  LEFT JOIN public.master_mitra mm ON mm.id = tm.mitra_id
  WHERE tm.mitra_id = ANY(v_mitra_ids)
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
  ORDER BY COALESCE(mm.kode, mm.nama), tm.tanggal, tm.created_at;

  INSERT INTO public.pembayaran_mitra_kwitansi_mitra (
    pembayaran_id,
    master_mitra_id,
    mitra_label_snapshot,
    total_tonase,
    total_nilai_bersih,
    jumlah_transaksi
  )
  SELECT
    v_payment.id,
    item.master_mitra_id,
    item.mitra_label_snapshot,
    COALESCE(SUM(item.tonase_snapshot), 0)::numeric(15,2),
    COALESCE(SUM(item.total_nilai_bersih_snapshot), 0)::numeric(15,2),
    COUNT(*)::integer
  FROM public.pembayaran_mitra_kwitansi_item item
  WHERE item.pembayaran_id = v_payment.id
  GROUP BY item.master_mitra_id, item.mitra_label_snapshot;

  IF COALESCE(array_length(v_panjar_ids, 1), 0) > 0 THEN
    WITH inserted_hutang AS (
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
      SELECT
        'mitra',
        pm.mitra_id,
        v_payment.tanggal_bayar,
        'kredit',
        'potong_settlement',
        COALESCE(SUM(pm.jumlah), 0)::numeric(15,2),
        'pembayaran_mitra_kwitansi_panjar',
        v_payment.id,
        'Potong panjar pada pembayaran kwitansi',
        v_actor
      FROM public.panjar_mitra pm
      WHERE pm.id = ANY(v_panjar_ids)
      GROUP BY pm.mitra_id
      RETURNING id, master_mitra_id
    )
    UPDATE public.panjar_mitra pm
    SET status = 'lunas',
        settlement_hutang_ledger_id = inserted_hutang.id,
        lunas_at = now(),
        updated_at = now()
    FROM inserted_hutang
    WHERE pm.id = ANY(v_panjar_ids)
      AND pm.mitra_id = inserted_hutang.master_mitra_id;
  END IF;

  RETURN v_payment;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text, uuid[], text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text, uuid[], text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text, uuid[], text) TO authenticated;

COMMIT;
