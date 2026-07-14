-- Sawit CB - DB lint fixes after Fase 2 foundation.

BEGIN;

ALTER TABLE IF EXISTS public.harga_tbs_lokal
  ADD COLUMN IF NOT EXISTS updated_by uuid REFERENCES public.users(id);

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
    SELECT 1 FROM public.petani p
    WHERE p.id = p_petani_id
      AND p.aktif = true
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
  FROM public.harga_tbs_lokal h
  WHERE h.aktif = true
    AND h.berlaku_mulai <= now()
    AND (h.berlaku_sampai IS NULL OR h.berlaku_sampai > now())
  ORDER BY h.berlaku_mulai DESC
  LIMIT 1;

  IF v_harga.id IS NULL THEN
    RAISE EXCEPTION 'Harga TBS lokal aktif belum diset';
  END IF;

  SELECT COALESCE(
    SUM(CASE WHEN hl.tipe = 'debit' THEN hl.jumlah ELSE -hl.jumlah END),
    0
  )
  INTO v_saldo_hutang
  FROM public.hutang_ledger hl
  WHERE hl.pihak_type = 'petani'
    AND hl.petani_id = p_petani_id
    AND hl.status <> 'dibatalkan';

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

REVOKE ALL ON FUNCTION public.create_transaksi_beli_tbs(uuid, numeric, numeric, numeric, text, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_transaksi_beli_tbs(uuid, numeric, numeric, numeric, text, date) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_transaksi_beli_tbs(uuid, numeric, numeric, numeric, text, date) TO authenticated;

COMMIT;
