CREATE OR REPLACE FUNCTION public.enforce_transaksi_mitra_financial_snapshots()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_harga_pabrik numeric;
  v_master_fee numeric;
  v_master_tarif_sewa numeric;
  v_master_dana_trip numeric;
  v_hist_id uuid;
  v_hist_fee numeric;
  v_hist_tarif_sewa numeric;
  v_hist_dana_trip numeric;
  v_hist_alasan text;
  v_final_fee numeric;
  v_final_tarif_sewa numeric;
  v_final_dana_trip numeric;
  v_final_history_id uuid;
  v_berat_netto numeric;
  v_potongan numeric;
  v_berat_dibayar numeric;
  v_is_initial boolean;
  v_has_stale_history_fee boolean;
  v_should_prefer_master boolean;
BEGIN
  IF NEW.tanggal IS NULL OR NEW.mitra_id IS NULL THEN
    RAISE EXCEPTION 'Tanggal dan mitra transaksi wajib diisi.' USING ERRCODE = '22023';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF OLD.status = 'dibatalkan' THEN
      RAISE EXCEPTION 'Transaksi yang sudah dibatalkan tidak dapat dihitung ulang.' USING ERRCODE = '22023';
    END IF;
    IF OLD.biaya_sopir_dibayar_at IS NOT NULL
       OR EXISTS (
         SELECT 1
         FROM public.pembayaran_mitra_kwitansi_item item
         JOIN public.pembayaran_mitra_kwitansi payment
           ON payment.id = item.pembayaran_id
         WHERE item.transaksi_mitra_id = OLD.id
           AND payment.status <> 'dibatalkan'
       )
       OR EXISTS (
         SELECT 1
         FROM public.pembayaran_pabrik_item item
         JOIN public.pembayaran_pabrik_batch payment
           ON payment.id = item.pembayaran_id
         WHERE item.transaksi_mitra_id = OLD.id
           AND payment.status <> 'dibatalkan'
       ) THEN
      RAISE EXCEPTION 'Transaksi yang sudah masuk pembayaran tidak dapat dihitung ulang; gunakan reversal.'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  v_berat_netto := COALESCE(NEW.berat_netto_pabrik_kg, NEW.tonase, 0);
  v_potongan := COALESCE(NEW.potongan_pabrik_kg, 0);
  IF v_berat_netto <= 0 OR v_potongan < 0 OR v_potongan > v_berat_netto THEN
    RAISE EXCEPTION 'Berat netto/potongan transaksi tidak valid.' USING ERRCODE = '22023';
  END IF;
  v_berat_dibayar := v_berat_netto - v_potongan;

  SELECT harga_per_kg
  INTO v_harga_pabrik
  FROM public.harga_tbs
  WHERE tanggal <= NEW.tanggal
  ORDER BY tanggal DESC
  LIMIT 1;

  IF v_harga_pabrik IS NULL OR v_harga_pabrik < 0 THEN
    RAISE EXCEPTION 'Harga Pabrik/TWB untuk tanggal transaksi belum tersedia.' USING ERRCODE = '22023';
  END IF;

  SELECT fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip
  INTO v_master_fee, v_master_tarif_sewa, v_master_dana_trip
  FROM public.master_mitra
  WHERE id = NEW.mitra_id
    AND aktif = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mitra transaksi tidak ditemukan atau tidak aktif.' USING ERRCODE = '22023';
  END IF;

  SELECT id, fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip, alasan_perubahan
  INTO v_hist_id, v_hist_fee, v_hist_tarif_sewa, v_hist_dana_trip, v_hist_alasan
  FROM public.fee_owner_mitra_history
  WHERE master_mitra_id = NEW.mitra_id
    AND aktif = true
    AND (berlaku_mulai IS NULL OR berlaku_mulai <= NEW.tanggal)
    AND (berlaku_sampai IS NULL OR berlaku_sampai >= NEW.tanggal)
  ORDER BY berlaku_mulai DESC NULLS LAST, created_at DESC
  LIMIT 1;

  v_is_initial := COALESCE(v_hist_alasan LIKE 'Snapshot awal Fee Owner%', false);
  v_has_stale_history_fee := v_hist_id IS NOT NULL
    AND COALESCE(v_master_fee, 0) > 0
    AND COALESCE(v_hist_fee, 0) = 0;
  v_should_prefer_master := COALESCE(v_master_fee, 0) > 0
    AND (
      v_hist_id IS NULL
      OR v_has_stale_history_fee
      OR (v_is_initial AND v_hist_fee IS DISTINCT FROM v_master_fee)
    );

  IF v_should_prefer_master THEN
    v_final_fee := COALESCE(v_master_fee, 0);
    v_final_tarif_sewa := COALESCE(v_master_tarif_sewa, 0);
    v_final_dana_trip := COALESCE(v_master_dana_trip, 0);
    v_final_history_id := CASE WHEN v_hist_fee = v_master_fee THEN v_hist_id END;
  ELSE
    v_final_fee := COALESCE(v_hist_fee, v_master_fee, 0);
    v_final_tarif_sewa := COALESCE(v_hist_tarif_sewa, v_master_tarif_sewa, 0);
    v_final_dana_trip := COALESCE(v_hist_dana_trip, v_master_dana_trip, 0);
    v_final_history_id := v_hist_id;
  END IF;

  IF COALESCE(NEW.menggunakan_armada_cb_snapshot, false)
     AND COALESCE(NEW.kenakan_sewa_armada_cb, false)
     AND v_final_tarif_sewa <= 0 THEN
    RAISE EXCEPTION 'Tarif sewa Armada CB untuk mitra belum diatur.' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(NEW.menggunakan_armada_cb_snapshot, false)
     AND COALESCE(NEW.catat_dana_operasional_trip, false)
     AND v_final_dana_trip <= 0 THEN
    RAISE EXCEPTION 'Dana Operasional Trip untuk mitra belum diatur.' USING ERRCODE = '22023';
  END IF;

  NEW.tonase := v_berat_netto;
  NEW.berat_netto_pabrik_kg := v_berat_netto;
  NEW.potongan_pabrik_kg := v_potongan;
  NEW.berat_dibayar_kg := v_berat_dibayar;
  NEW.harga_harian := v_harga_pabrik;
  NEW.harga_pabrik_per_kg := v_harga_pabrik;
  NEW.fee_owner_per_kg := v_final_fee;
  NEW.harga_bersih_per_kg := GREATEST(0, v_harga_pabrik - v_final_fee);
  NEW.fee_owner_history_id := v_final_history_id;
  NEW.total_kotor := round(v_berat_dibayar * v_harga_pabrik);
  NEW.total_fee_owner := round(v_berat_dibayar * v_final_fee);
  NEW.total_nilai_bersih := round(v_berat_dibayar * NEW.harga_bersih_per_kg);
  NEW.pakai_sewa_armada_bl := COALESCE(NEW.menggunakan_armada_cb_snapshot, false)
    AND COALESCE(NEW.kenakan_sewa_armada_cb, false);
  NEW.biaya_sewa_armada_per_kg := CASE WHEN NEW.pakai_sewa_armada_bl THEN v_final_tarif_sewa ELSE 0 END;
  NEW.tarif_sewa_angkut_per_kg_snapshot := NEW.biaya_sewa_armada_per_kg;
  NEW.nominal_perongkosan_snapshot := 0;
  NEW.biaya_sewa_armada_kotor := CASE
    WHEN NEW.pakai_sewa_armada_bl THEN round(v_berat_netto * v_final_tarif_sewa)
    ELSE 0
  END;
  NEW.biaya_sewa_armada_total := NEW.biaya_sewa_armada_kotor;
  NEW.dana_operasional_trip_snapshot := CASE
    WHEN COALESCE(NEW.menggunakan_armada_cb_snapshot, false)
      AND COALESCE(NEW.catat_dana_operasional_trip, false)
      THEN v_final_dana_trip
    ELSE 0
  END;
  NEW.upah_sopir_cb_snapshot := 0;
  NEW.uang_jalan_sopir_cb_snapshot := 0;
  NEW.total_biaya_sopir_cb_snapshot := NEW.dana_operasional_trip_snapshot;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_transaksi_mitra_financial_snapshots
ON public.transaksi_mitra;

CREATE TRIGGER enforce_transaksi_mitra_financial_snapshots
BEFORE INSERT OR UPDATE OF
  tanggal, mitra_id, tonase, berat_netto_pabrik_kg, potongan_pabrik_kg,
  berat_dibayar_kg, harga_harian, harga_pabrik_per_kg, fee_owner_per_kg,
  harga_bersih_per_kg, fee_owner_history_id, total_kotor, total_fee_owner,
  total_nilai_bersih, menggunakan_armada_cb_snapshot, pakai_sewa_armada_bl,
  kenakan_sewa_armada_cb, catat_dana_operasional_trip,
  biaya_sewa_armada_per_kg, tarif_sewa_angkut_per_kg_snapshot,
  nominal_perongkosan_snapshot, biaya_sewa_armada_kotor,
  biaya_sewa_armada_total, dana_operasional_trip_snapshot,
  upah_sopir_cb_snapshot, uang_jalan_sopir_cb_snapshot,
  total_biaya_sopir_cb_snapshot
ON public.transaksi_mitra
FOR EACH ROW
EXECUTE FUNCTION public.enforce_transaksi_mitra_financial_snapshots();

CREATE OR REPLACE FUNCTION public.save_transaksi_mitra_operational(payload jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_unknown_key text;
  v_row public.transaksi_mitra%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang membuat transaksi mitra.' USING ERRCODE = '42501';
  END IF;

  SELECT key
  INTO v_unknown_key
  FROM jsonb_object_keys(COALESCE(payload, '{}'::jsonb)) key
  WHERE key <> ALL (ARRAY[
    'tanggal', 'sopir_id', 'mitra_id', 'plat_nomor',
    'sopir_default_id', 'sopir_default_nama', 'sopir_aktual_id',
    'sopir_aktual_nama', 'sopir_aktual_no_hp', 'sopir_aktual_source',
    'sopir_diganti_dari_default', 'catatan_sopir',
    'berat_netto_pabrik_kg', 'potongan_pabrik_kg',
    'menggunakan_armada_cb_snapshot', 'kenakan_sewa_armada_cb',
    'catat_dana_operasional_trip', 'alasan_tanpa_sewa_armada_cb',
    'alasan_tanpa_dana_operasional_trip'
  ])
  LIMIT 1;

  IF v_unknown_key IS NOT NULL THEN
    RAISE EXCEPTION 'Field transaksi tidak diizinkan: %', v_unknown_key USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_row
  FROM public.save_transaksi_mitra_v2(payload);

  RETURN v_row.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_transaksi_mitra_operational(
  p_transaksi_id uuid,
  p_changes jsonb,
  p_alasan text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_unknown_key text;
  v_existing public.transaksi_mitra%ROWTYPE;
  v_row public.transaksi_mitra%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang mengoreksi transaksi mitra.' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(btrim(COALESCE(p_alasan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan koreksi wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_existing
  FROM public.transaksi_mitra
  WHERE id = p_transaksi_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaksi mitra tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  SELECT key
  INTO v_unknown_key
  FROM jsonb_object_keys(COALESCE(p_changes, '{}'::jsonb)) key
  WHERE key <> ALL (ARRAY[
    'tanggal', 'sopir_id', 'mitra_id', 'plat_nomor',
    'sopir_default_id', 'sopir_default_nama', 'sopir_aktual_id',
    'sopir_aktual_nama', 'sopir_aktual_no_hp', 'sopir_aktual_source',
    'sopir_diganti_dari_default', 'catatan_sopir',
    'tonase', 'berat_netto_pabrik_kg', 'potongan_pabrik_kg',
    'menggunakan_armada_cb_snapshot', 'kenakan_sewa_armada_cb',
    'catat_dana_operasional_trip', 'alasan_tanpa_sewa_armada_cb',
    'alasan_tanpa_dana_operasional_trip'
  ])
  LIMIT 1;

  IF v_unknown_key IS NOT NULL THEN
    RAISE EXCEPTION 'Field koreksi tidak diizinkan: %', v_unknown_key USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_row
  FROM public.update_transaksi_mitra_controlled(p_transaksi_id, p_changes, p_alasan);

  RETURN v_row.id;
END;
$$;

DROP VIEW IF EXISTS public.v_master_mitra_operasional;
DROP VIEW IF EXISTS public.v_transaksi_mitra_operasional;

CREATE VIEW public.v_master_mitra_operasional
WITH (security_barrier = true) AS
SELECT id, kode, nama, alamat, no_hp, aktif, tipe_mitra, created_at
FROM public.master_mitra
WHERE (SELECT public.has_app_role(
  ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']
));

CREATE VIEW public.v_transaksi_mitra_operasional
WITH (security_barrier = true) AS
SELECT
  id, tanggal, mitra_id, sopir_id, sopir_default_id, sopir_default_nama,
  plat_nomor, sopir_aktual_id, sopir_aktual_nama, sopir_aktual_no_hp,
  sopir_aktual_source, sopir_diganti_dari_default, catatan_sopir,
  tonase, berat_netto_pabrik_kg, potongan_pabrik_kg, berat_dibayar_kg,
  harga_bersih_per_kg, total_nilai_bersih,
  menggunakan_armada_cb_snapshot, pakai_sewa_armada_bl,
  kenakan_sewa_armada_cb, catat_dana_operasional_trip,
  alasan_tanpa_sewa_armada_cb, alasan_tanpa_dana_operasional_trip,
  armada_cb_perlu_review, alasan_review_armada_cb,
  status, created_at, updated_at, updated_by, alasan_edit,
  dibatalkan_at, dibatalkan_by, alasan_batal,
  tagihan_sopir_ledger_id, biaya_sopir_operasional_id, biaya_sopir_dibayar_at
FROM public.transaksi_mitra
WHERE (SELECT public.has_app_role(
  ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']
));

REVOKE ALL ON FUNCTION public.enforce_transaksi_mitra_financial_snapshots()
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.save_transaksi_mitra_v2(jsonb)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_transaksi_mitra_v2(jsonb)
TO service_role;

REVOKE ALL ON FUNCTION public.update_transaksi_mitra_controlled(uuid, jsonb, text)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_transaksi_mitra_controlled(uuid, jsonb, text)
TO service_role;

REVOKE ALL ON FUNCTION public.save_transaksi_mitra_operational(jsonb)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_transaksi_mitra_operational(jsonb)
TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.update_transaksi_mitra_operational(uuid, jsonb, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_transaksi_mitra_operational(uuid, jsonb, text)
TO authenticated, service_role;

REVOKE ALL ON public.v_master_mitra_operasional,
  public.v_transaksi_mitra_operasional
FROM PUBLIC, anon;
GRANT SELECT ON public.v_master_mitra_operasional,
  public.v_transaksi_mitra_operasional
TO authenticated, service_role;
