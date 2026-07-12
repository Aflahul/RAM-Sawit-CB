-- Sawit CB - P0A harga and pembelian RPC helpers

BEGIN;

CREATE OR REPLACE FUNCTION public.set_harga_tbs_lokal(
  p_harga_per_kg numeric,
  p_alasan_override text DEFAULT NULL
)
RETURNS public.harga_tbs_lokal
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_now timestamptz := NOW();
  v_harga public.harga_tbs_lokal%ROWTYPE;
BEGIN
  IF NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak punya akses untuk mengatur harga TBS lokal';
  END IF;

  IF p_harga_per_kg IS NULL OR p_harga_per_kg <= 0 THEN
    RAISE EXCEPTION 'Harga TBS lokal harus lebih dari 0';
  END IF;

  UPDATE public.harga_tbs_lokal
  SET aktif = false,
      berlaku_sampai = COALESCE(berlaku_sampai, v_now),
      updated_at = v_now,
      updated_by = v_actor
  WHERE aktif = true
    AND (berlaku_sampai IS NULL OR berlaku_sampai > v_now);

  INSERT INTO public.harga_tbs_lokal (
    harga_per_kg,
    berlaku_mulai,
    aktif,
    set_oleh,
    alasan_override
  )
  VALUES (
    round(p_harga_per_kg, 2),
    v_now,
    true,
    v_actor,
    p_alasan_override
  )
  RETURNING * INTO v_harga;

  PERFORM public.write_audit_log(
    'harga_tbs_lokal',
    v_harga.id,
    'create',
    NULL,
    to_jsonb(v_harga),
    p_alasan_override
  );

  RETURN v_harga;
END;
$$;

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
  v_tanggal date := COALESCE(p_tanggal, (NOW() AT TIME ZONE 'Asia/Jakarta')::date);
  v_harga public.harga_tbs_lokal%ROWTYPE;
  v_saldo_hutang numeric(15,2) := 0;
  v_berat_bersih numeric(14,2);
  v_total_harga numeric(15,2);
  v_potongan_hutang numeric(15,2);
  v_transaksi public.transaksi_beli_tbs%ROWTYPE;
BEGIN
  IF NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']) THEN
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
    AND berlaku_mulai <= NOW()
    AND (berlaku_sampai IS NULL OR berlaku_sampai > NOW())
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
    AND petani_id = p_petani_id;

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
  IF NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
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
      updated_at = NOW()
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

COMMIT;
