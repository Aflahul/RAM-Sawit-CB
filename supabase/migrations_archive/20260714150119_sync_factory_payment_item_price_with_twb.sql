-- Sawit CB - samakan snapshot data timbang pembayaran pabrik dengan harga TWB.
--
-- Perubahan ini tidak mengubah struktur tabel dan tidak menghapus data.
-- Pembayaran pabrik berikutnya akan menyimpan item cocokkan memakai harga TWB
-- yang dikirim dari form, bukan harga lama yang tersimpan pada transaksi timbang.

BEGIN;

CREATE OR REPLACE FUNCTION public.create_pembayaran_pabrik_batch(
  p_pabrik_id uuid,
  p_tanggal_bayar date,
  p_metode_bayar text DEFAULT 'transfer',
  p_tonase_pabrik numeric DEFAULT NULL,
  p_harga_pabrik_per_kg numeric DEFAULT NULL,
  p_nominal_diterima numeric DEFAULT NULL,
  p_rekening_kas_id uuid DEFAULT NULL,
  p_nomor_bukti text DEFAULT NULL,
  p_catatan text DEFAULT NULL,
  p_transaksi_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS public.pembayaran_pabrik_batch
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_ids uuid[] := '{}'::uuid[];
  v_expected_count integer := 0;
  v_found_count integer := 0;
  v_total_tonase_sistem numeric(15,2) := 0;
  v_total_nilai_sistem numeric(15,2) := 0;
  v_tonase_pabrik numeric(15,2) := round(COALESCE(p_tonase_pabrik, 0), 2);
  v_harga_pabrik numeric(15,2) := round(COALESCE(p_harga_pabrik_per_kg, 0), 2);
  v_total_nilai_pabrik numeric(15,2) := 0;
  v_nominal_diterima numeric(15,2);
  v_rekening_id uuid := p_rekening_kas_id;
  v_batch public.pembayaran_pabrik_batch%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
  v_allocated_total numeric(15,2) := 0;
  v_rounding_delta numeric(15,2) := 0;
  v_adjust_item_id uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat pembayaran pabrik.'
      USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT trx_id), '{}'::uuid[])
  INTO v_ids
  FROM unnest(COALESCE(p_transaksi_ids, '{}'::uuid[])) AS trx_id
  WHERE trx_id IS NOT NULL;

  v_expected_count := COALESCE(array_length(v_ids, 1), 0);

  IF v_tonase_pabrik <= 0 THEN
    RAISE EXCEPTION 'Tonase versi pabrik wajib lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF v_harga_pabrik <= 0 THEN
    RAISE EXCEPTION 'Harga pabrik per kg wajib lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF p_pabrik_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.pabrik WHERE id = p_pabrik_id AND COALESCE(aktif, true) = true
  ) THEN
    RAISE EXCEPTION 'Pabrik tujuan tidak ditemukan atau tidak aktif.'
      USING ERRCODE = 'P0002';
  END IF;

  IF p_metode_bayar NOT IN ('tunai', 'transfer', 'lainnya') THEN
    RAISE EXCEPTION 'Metode bayar tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  v_total_nilai_pabrik := round(v_tonase_pabrik * v_harga_pabrik, 0);
  v_nominal_diterima := round(COALESCE(p_nominal_diterima, v_total_nilai_pabrik), 2);

  IF v_nominal_diterima <= 0 THEN
    RAISE EXCEPTION 'Uang diterima dari pabrik harus lebih dari 0.'
      USING ERRCODE = '22023';
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

  IF v_expected_count > 0 THEN
    PERFORM 1
    FROM public.transaksi_mitra tm
    WHERE tm.id = ANY(v_ids)
    FOR UPDATE;

    SELECT
      count(*),
      round(COALESCE(sum(COALESCE(tm.tonase, 0)), 0), 2),
      round(COALESCE(sum(COALESCE(tm.tonase, 0) * v_harga_pabrik), 0), 2)
    INTO v_found_count, v_total_tonase_sistem, v_total_nilai_sistem
    FROM public.transaksi_mitra tm
    WHERE tm.id = ANY(v_ids);

    IF v_found_count <> v_expected_count THEN
      RAISE EXCEPTION 'Sebagian data timbang tidak ditemukan.'
        USING ERRCODE = 'P0002';
    END IF;

    IF v_total_nilai_sistem <= 0 THEN
      RAISE EXCEPTION 'Nilai catatan kita harus lebih dari 0 sebelum data bisa dicocokkan.'
        USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.transaksi_mitra tm
      WHERE tm.id = ANY(v_ids)
        AND tm.status = 'dibatalkan'
    ) THEN
      RAISE EXCEPTION 'Data timbang yang sudah dibatalkan tidak bisa dicocokkan dengan pembayaran pabrik.'
        USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.pembayaran_pabrik_item item
      JOIN public.pembayaran_pabrik_batch batch ON batch.id = item.pembayaran_id
      WHERE item.transaksi_mitra_id = ANY(v_ids)
        AND item.status <> 'dibatalkan'
        AND batch.status <> 'dibatalkan'
    ) THEN
      RAISE EXCEPTION 'Ada data timbang yang sudah dicocokkan dengan pembayaran pabrik.'
        USING ERRCODE = '23505';
    END IF;
  END IF;

  INSERT INTO public.pembayaran_pabrik_batch (
    pabrik_id,
    tanggal_bayar,
    metode_bayar,
    nomor_bukti,
    status,
    total_tonase,
    total_tonase_sistem,
    selisih_tonase,
    harga_pabrik_per_kg,
    total_nilai_pabrik,
    total_diterima,
    total_selisih,
    jumlah_transaksi,
    rekening_kas_id,
    catatan,
    created_by,
    updated_by
  )
  VALUES (
    p_pabrik_id,
    COALESCE(p_tanggal_bayar, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    p_metode_bayar,
    NULLIF(btrim(COALESCE(p_nomor_bukti, '')), ''),
    'diterima',
    v_tonase_pabrik,
    v_total_tonase_sistem,
    round(v_tonase_pabrik - v_total_tonase_sistem, 2),
    v_harga_pabrik,
    v_total_nilai_pabrik,
    v_nominal_diterima,
    round(v_total_nilai_pabrik - v_nominal_diterima, 2),
    v_found_count,
    v_rekening_id,
    NULLIF(btrim(COALESCE(p_catatan, '')), ''),
    v_actor,
    v_actor
  )
  RETURNING * INTO v_batch;

  IF v_expected_count > 0 THEN
    INSERT INTO public.pembayaran_pabrik_item (
      pembayaran_id,
      transaksi_mitra_id,
      master_mitra_id,
      tanggal,
      waktu_transaksi,
      mitra_label_snapshot,
      sopir_aktual_nama_snapshot,
      plat_nomor_snapshot,
      tonase_snapshot,
      harga_pabrik_per_kg_snapshot,
      total_nilai_pabrik_snapshot,
      jumlah_dialokasikan,
      status
    )
    SELECT
      v_batch.id,
      tm.id,
      tm.mitra_id,
      tm.tanggal,
      tm.created_at,
      COALESCE(mm.kode || ' - ' || mm.alamat, mm.kode, mm.nama, 'Tanpa mitra'),
      COALESCE(tm.sopir_aktual_nama, tm.sopir_default_nama),
      tm.plat_nomor,
      round(COALESCE(tm.tonase, 0), 2),
      v_harga_pabrik,
      round(COALESCE(tm.tonase, 0) * v_harga_pabrik, 2),
      round(
        v_nominal_diterima
        * (COALESCE(tm.tonase, 0) * v_harga_pabrik)
        / NULLIF(v_total_nilai_sistem, 0),
        2
      ),
      'aktif'
    FROM public.transaksi_mitra tm
    LEFT JOIN public.master_mitra mm ON mm.id = tm.mitra_id
    WHERE tm.id = ANY(v_ids);

    SELECT COALESCE(sum(jumlah_dialokasikan), 0), min(id)
    INTO v_allocated_total, v_adjust_item_id
    FROM public.pembayaran_pabrik_item
    WHERE pembayaran_id = v_batch.id
      AND status = 'aktif';

    v_rounding_delta := round(v_nominal_diterima - v_allocated_total, 2);

    IF v_rounding_delta <> 0 AND v_adjust_item_id IS NOT NULL THEN
      UPDATE public.pembayaran_pabrik_item
      SET jumlah_dialokasikan = jumlah_dialokasikan + v_rounding_delta
      WHERE id = v_adjust_item_id;
    END IF;
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
    v_batch.tanggal_bayar,
    'masuk',
    'pembayaran_pabrik',
    v_nominal_diterima,
    'pembayaran_pabrik_batch',
    v_batch.id,
    'pembayaran_pabrik_batch:' || v_batch.id::text,
    'Pembayaran pabrik '
      || COALESCE(NULLIF(v_batch.nomor_bukti, ''), v_batch.id::text)
      || ' tonase pabrik '
      || v_tonase_pabrik::text
      || ' kg',
    v_actor
  )
  RETURNING * INTO v_kas;

  UPDATE public.pembayaran_pabrik_batch
  SET kas_ledger_id = v_kas.id,
      updated_at = now(),
      updated_by = v_actor
  WHERE id = v_batch.id
  RETURNING * INTO v_batch;

  IF v_expected_count > 0 THEN
    UPDATE public.transaksi_mitra tm
    SET pembayaran_pabrik_batch_id = v_batch.id,
        pembayaran_pabrik_item_id = item.id,
        pembayaran_pabrik_status = 'dibayar',
        pembayaran_pabrik_at = v_batch.diterima_at,
        updated_at = now(),
        updated_by = v_actor
    FROM public.pembayaran_pabrik_item item
    WHERE item.pembayaran_id = v_batch.id
      AND item.transaksi_mitra_id = tm.id
      AND item.status = 'aktif';
  END IF;

  RETURN v_batch;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pembayaran_pabrik_batch(uuid, date, text, numeric, numeric, numeric, uuid, text, text, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_pembayaran_pabrik_batch(uuid, date, text, numeric, numeric, numeric, uuid, text, text, uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_pembayaran_pabrik_batch(uuid, date, text, numeric, numeric, numeric, uuid, text, text, uuid[]) TO authenticated;

COMMIT;
