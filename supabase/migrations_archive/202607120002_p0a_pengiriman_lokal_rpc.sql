BEGIN;

CREATE OR REPLACE FUNCTION public.create_pengiriman_lokal(
  p_tanggal date,
  p_pabrik_id uuid,
  p_tonase_kirim_kg numeric,
  p_nomor_do text DEFAULT NULL,
  p_sopir_id uuid DEFAULT NULL,
  p_kendaraan_id uuid DEFAULT NULL
)
RETURNS public.pengiriman
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_pengiriman public.pengiriman%ROWTYPE;
  v_total_stok numeric(14,2);
  v_sisa_alokasi numeric(14,2);
  v_alokasi numeric(14,2);
  v_nomor_do text := NULLIF(BTRIM(p_nomor_do), '');
  r record;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'User belum login';
  END IF;

  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal pengiriman wajib diisi';
  END IF;

  IF p_pabrik_id IS NULL THEN
    RAISE EXCEPTION 'Pabrik tujuan wajib diisi';
  END IF;

  IF p_tonase_kirim_kg IS NULL OR p_tonase_kirim_kg <= 0 THEN
    RAISE EXCEPTION 'Tonase kirim harus lebih besar dari 0';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.pabrik
    WHERE id = p_pabrik_id
      AND COALESCE(aktif, true) = true
  ) THEN
    RAISE EXCEPTION 'Pabrik tidak aktif atau tidak ditemukan';
  END IF;

  IF v_nomor_do IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.pengiriman
    WHERE pabrik_id = p_pabrik_id
      AND nomor_do = v_nomor_do
      AND status NOT IN ('draft', 'dibatalkan')
  ) THEN
    RAISE EXCEPTION 'Nomor DO sudah dipakai untuk pabrik ini';
  END IF;

  SELECT COALESCE(SUM(
    CASE
      WHEN tipe = 'masuk' THEN ABS(berat_kg)
      WHEN tipe = 'keluar' THEN -ABS(berat_kg)
      ELSE berat_kg
    END
  ), 0)
  INTO v_total_stok
  FROM public.stok_tbs_lokal_ledger;

  IF v_total_stok < p_tonase_kirim_kg THEN
    RAISE EXCEPTION 'Stok lokal tidak cukup. Sisa stok: %, tonase diminta: %', v_total_stok, p_tonase_kirim_kg;
  END IF;

  INSERT INTO public.pengiriman (
    tanggal,
    sopir_id,
    kendaraan_id,
    pabrik_id,
    tonase_kirim,
    no_do,
    status,
    created_by,
    sumber,
    nomor_do,
    tonase_timbang_sumber,
    armada_type,
    updated_at
  )
  VALUES (
    p_tanggal,
    p_sopir_id,
    p_kendaraan_id,
    p_pabrik_id,
    p_tonase_kirim_kg,
    v_nomor_do,
    'dikirim',
    v_actor,
    'lokal',
    v_nomor_do,
    p_tonase_kirim_kg,
    'perusahaan',
    NOW()
  )
  RETURNING * INTO v_pengiriman;

  v_sisa_alokasi := p_tonase_kirim_kg;

  FOR r IN
    SELECT
      t.id,
      t.petani_id,
      t.no_struk,
      t.berat_bersih_kg,
      (
        t.berat_bersih_kg
        - COALESCE((
          SELECT SUM(d.berat_alokasi_kg)
          FROM public.pengiriman_lokal_detail d
          JOIN public.pengiriman p ON p.id = d.pengiriman_id
          WHERE d.transaksi_beli_id = t.id
            AND p.status <> 'dibatalkan'
        ), 0)
      ) AS sisa_transaksi_kg
    FROM public.transaksi_beli_tbs t
    WHERE t.status = 'aktif'
    ORDER BY t.tanggal ASC, t.created_at ASC, t.id ASC
    FOR UPDATE OF t
  LOOP
    EXIT WHEN v_sisa_alokasi <= 0;
    CONTINUE WHEN r.sisa_transaksi_kg <= 0;

    v_alokasi := LEAST(v_sisa_alokasi, r.sisa_transaksi_kg);

    INSERT INTO public.pengiriman_lokal_detail (
      pengiriman_id,
      transaksi_beli_id,
      petani_id,
      berat_alokasi_kg
    )
    VALUES (
      v_pengiriman.id,
      r.id,
      r.petani_id,
      v_alokasi
    );

    INSERT INTO public.stok_tbs_lokal_ledger (
      tanggal,
      tipe,
      sumber,
      transaksi_beli_id,
      pengiriman_id,
      berat_kg,
      keterangan,
      created_by
    )
    VALUES (
      p_tanggal,
      'keluar',
      'pengiriman_pabrik',
      r.id,
      v_pengiriman.id,
      v_alokasi,
      'Alokasi FIFO ke DO ' || COALESCE(v_nomor_do, v_pengiriman.id::text),
      v_actor
    );

    v_sisa_alokasi := v_sisa_alokasi - v_alokasi;
  END LOOP;

  IF v_sisa_alokasi > 0 THEN
    RAISE EXCEPTION 'Stok transaksi belum cukup untuk alokasi FIFO. Sisa belum teralokasi: %', v_sisa_alokasi;
  END IF;

  PERFORM public.write_audit_log(
    'pengiriman',
    v_pengiriman.id,
    'create',
    NULL,
    to_jsonb(v_pengiriman),
    'Pengiriman lokal dibuat dengan alokasi FIFO'
  );

  RETURN v_pengiriman;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pengiriman_lokal(date, uuid, numeric, text, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_pengiriman_lokal(date, uuid, numeric, text, uuid, uuid) TO authenticated;

COMMIT;
