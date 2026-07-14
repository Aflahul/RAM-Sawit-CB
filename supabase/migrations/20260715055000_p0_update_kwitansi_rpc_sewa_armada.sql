BEGIN;

-- P0: Update create_pembayaran_mitra_kwitansi untuk memperhitungkan biaya_sewa_armada_total
-- dari transaksi_mitra saat membuat kwitansi, dan memotong nominal dibayar ke mitra.

DROP FUNCTION IF EXISTS public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text, uuid[], text);

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
  v_total_sewa_armada numeric(15,2) := 0;
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
      tm.berat_netto_pabrik_kg,
      tm.potongan_pabrik_kg,
      tm.berat_dibayar_kg,
      tm.pakai_sewa_armada_bl,
      tm.biaya_sewa_armada_total,
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
    COALESCE(SUM(biaya_sewa_armada_total), 0)::numeric(15,2),
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
        'berat_netto_pabrik_kg', berat_netto_pabrik_kg,
        'potongan_pabrik_kg', potongan_pabrik_kg,
        'berat_dibayar_kg', berat_dibayar_kg,
        'pakai_sewa_armada_bl', pakai_sewa_armada_bl,
        'biaya_sewa_armada_total', biaya_sewa_armada_total,
        'harga_bersih_per_kg', harga_bersih_per_kg,
        'total_nilai_bersih', total_nilai_bersih,
        'status', status
      )
      ORDER BY mitra_label, tanggal, created_at
    ), '[]'::jsonb)
  INTO v_jumlah_transaksi, v_total_tonase, v_total_nilai_bersih, v_total_sewa_armada, v_transaksi_snapshot
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

  v_nominal_dibayar := v_total_nilai_bersih - v_total_panjar - v_total_sewa_armada;

  IF v_nominal_dibayar < 0 THEN
    RAISE EXCEPTION 'Nominal dibayar tidak boleh negatif (Panjar + Sewa Armada melebihi Nilai Bersih).'
      USING ERRCODE = '22023';
  END IF;

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
    total_sewa_armada,
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
    v_total_sewa_armada,
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
    berat_netto_snapshot,
    potongan_snapshot,
    berat_dibayar_snapshot,
    pakai_sewa_armada_snapshot,
    biaya_sewa_armada_snapshot,
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
    tm.berat_netto_pabrik_kg,
    tm.potongan_pabrik_kg,
    tm.berat_dibayar_kg,
    tm.pakai_sewa_armada_bl,
    tm.biaya_sewa_armada_total,
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

  UPDATE public.panjar_mitra
  SET status = 'lunas',
      pembayaran_mitra_kwitansi_id = v_payment.id,
      dilunasi_at = now(),
      updated_by = v_actor
  WHERE id = ANY(v_panjar_ids);

  RETURN v_payment;
END;
$$;

-- Berikan permission
REVOKE ALL ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text, uuid[], text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text, uuid[], text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_pembayaran_mitra_kwitansi(uuid, date, date, text, text, uuid[], text) TO authenticated;

COMMIT;
