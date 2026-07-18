-- Sawit CB - RPC sinkronisasi Fee Owner per periode yang sedang dibuka.
--
-- Masalah yang diperbaiki:
-- - master_mitra.fee_per_kg sudah benar, misalnya BL/LR = 30,
--   tetapi transaksi_mitra bisa telanjur menyimpan fee_owner_per_kg = 0.
-- - Pendapatan Owner Bruto, laporan mitra, dan kwitansi ikut salah jika
--   snapshot transaksi lama masih 0.
--
-- Prinsip keamanan:
-- - Migration ini TIDAK langsung mengubah transaksi lama.
-- - Perbaikan dilakukan hanya ketika owner/super_admin menjalankan RPC
--   untuk periode dan filter yang sedang dibuka.
-- - RPC hanya memperbaiki transaksi aktif yang fee-nya masih 0/kosong atau
--   nilai bersihnya jelas belum dipotong fee.

BEGIN;

CREATE OR REPLACE FUNCTION public.sync_fee_owner_mitra_period(
  p_date_from date,
  p_date_to date,
  p_master_mitra_id uuid DEFAULT NULL,
  p_tipe_mitra text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated_count integer := 0;
  v_total_fee_owner numeric := 0;
  v_total_nilai_bersih numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Tidak berwenang menyinkronkan Fee Owner.'
      USING ERRCODE = '42501';
  END IF;

  IF p_date_from IS NULL OR p_date_to IS NULL THEN
    RAISE EXCEPTION 'Periode sinkronisasi wajib diisi.'
      USING ERRCODE = '22023';
  END IF;

  IF p_date_to < p_date_from THEN
    RAISE EXCEPTION 'Tanggal akhir tidak boleh sebelum tanggal awal.'
      USING ERRCODE = '22023';
  END IF;

  WITH repair_candidates AS (
    SELECT
      tm.id AS transaksi_id,
      tm.tonase,
      COALESCE(tm.harga_pabrik_per_kg, tm.harga_harian, 0)::numeric(12,2) AS harga_pabrik_per_kg,
      COALESCE(mm.fee_per_kg, 0)::numeric(12,2) AS fee_per_kg,
      h.id AS fee_owner_history_id
    FROM public.transaksi_mitra tm
    JOIN public.master_mitra mm ON mm.id = tm.mitra_id
    LEFT JOIN LATERAL (
      SELECT fh.id
      FROM public.fee_owner_mitra_history fh
      WHERE fh.master_mitra_id = mm.id
        AND fh.aktif = true
        AND fh.fee_per_kg = COALESCE(mm.fee_per_kg, 0)
        AND fh.berlaku_mulai <= tm.tanggal
        AND (fh.berlaku_sampai IS NULL OR fh.berlaku_sampai >= tm.tanggal)
      ORDER BY fh.berlaku_mulai DESC, fh.created_at DESC
      LIMIT 1
    ) h ON true
    WHERE COALESCE(tm.status, 'aktif') <> 'dibatalkan'
      AND tm.tanggal >= p_date_from
      AND tm.tanggal <= p_date_to
      AND (p_master_mitra_id IS NULL OR tm.mitra_id = p_master_mitra_id)
      AND (p_tipe_mitra IS NULL OR COALESCE(mm.tipe_mitra, 'eksternal') = p_tipe_mitra)
      AND COALESCE(mm.fee_per_kg, 0) > 0
      AND COALESCE(tm.harga_pabrik_per_kg, tm.harga_harian, 0) > 0
      AND (
        COALESCE(tm.fee_owner_per_kg, 0) = 0
        OR COALESCE(tm.total_fee_owner, 0) = 0
        OR (
          tm.harga_pabrik_per_kg IS NOT NULL
          AND tm.harga_bersih_per_kg IS NOT NULL
          AND tm.harga_bersih_per_kg >= tm.harga_pabrik_per_kg
        )
      )
  ),
  updated_rows AS (
    UPDATE public.transaksi_mitra tm
    SET
      harga_pabrik_per_kg = repair.harga_pabrik_per_kg,
      harga_harian = repair.harga_pabrik_per_kg,
      fee_owner_per_kg = repair.fee_per_kg,
      harga_bersih_per_kg = GREATEST(repair.harga_pabrik_per_kg - repair.fee_per_kg, 0),
      total_kotor = ROUND(repair.tonase * repair.harga_pabrik_per_kg),
      total_fee_owner = ROUND(repair.tonase * repair.fee_per_kg),
      total_nilai_bersih = ROUND(repair.tonase * GREATEST(repair.harga_pabrik_per_kg - repair.fee_per_kg, 0)),
      fee_owner_history_id = repair.fee_owner_history_id
    FROM repair_candidates repair
    WHERE tm.id = repair.transaksi_id
    RETURNING tm.total_fee_owner, tm.total_nilai_bersih
  )
  SELECT
    COUNT(*)::integer,
    COALESCE(SUM(total_fee_owner), 0),
    COALESCE(SUM(total_nilai_bersih), 0)
  INTO v_updated_count, v_total_fee_owner, v_total_nilai_bersih
  FROM updated_rows;

  RETURN jsonb_build_object(
    'updated_count', v_updated_count,
    'total_fee_owner', v_total_fee_owner,
    'total_nilai_bersih', v_total_nilai_bersih,
    'date_from', p_date_from,
    'date_to', p_date_to,
    'master_mitra_id', p_master_mitra_id,
    'tipe_mitra', p_tipe_mitra
  );
END;
$$;

COMMENT ON FUNCTION public.sync_fee_owner_mitra_period(date, date, uuid, text)
IS 'Sinkronisasi snapshot Fee Owner transaksi mitra hanya untuk periode/filter yang sedang dibuka.';

REVOKE ALL ON FUNCTION public.sync_fee_owner_mitra_period(date, date, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_fee_owner_mitra_period(date, date, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.sync_fee_owner_mitra_period(date, date, uuid, text) TO authenticated;

COMMIT;
