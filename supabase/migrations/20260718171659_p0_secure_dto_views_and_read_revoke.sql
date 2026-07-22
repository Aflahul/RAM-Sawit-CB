BEGIN;

-- 1. Cabut hak baca (SELECT) admin_operasional dari tabel-tabel sensitif
DO $$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'master_mitra',
    'transaksi_mitra',
    'fee_mitra_history',
    'fee_owner_mitra_history',
    'pabrik',
    'pengaturan_bisnis'
  ]
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS read_authenticated ON public.%I',
      v_table
    );
    EXECUTE format(
      'CREATE POLICY read_authenticated ON public.%I
       FOR SELECT TO authenticated
       USING ((SELECT public.has_app_role(
         ARRAY[''owner'', ''super_admin'', ''admin_keuangan'']
      )))',
      v_table
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE VIEW public.v_master_mitra_operasional
WITH (security_barrier = true) AS
SELECT
    id,
    kode,
    nama,
    alamat,
    no_hp,
    aktif,
    tipe_mitra,
    created_at
FROM public.master_mitra
WHERE (SELECT public.has_app_role(
  ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']
));

CREATE OR REPLACE VIEW public.v_transaksi_mitra_operasional
WITH (security_barrier = true) AS
SELECT
    id,
    tanggal,
    mitra_id,
    sopir_id,
    sopir_default_id,
    sopir_default_nama,
    plat_nomor,
    sopir_aktual_id,
    sopir_aktual_nama,
    sopir_aktual_no_hp,
    sopir_aktual_source,
    sopir_diganti_dari_default,
    catatan_sopir,
    tonase,
    berat_netto_pabrik_kg,
    potongan_pabrik_kg,
    berat_dibayar_kg,
    harga_harian,
    harga_bersih_per_kg,
    total_kotor,
    total_nilai_bersih,
    pakai_sewa_armada_bl,
    kenakan_sewa_armada_cb,
    catat_dana_operasional_trip,
    alasan_tanpa_sewa_armada_cb,
    alasan_tanpa_dana_operasional_trip,
    armada_cb_perlu_review,
    alasan_review_armada_cb,
    status,
    created_at,
    updated_at,
    updated_by,
    alasan_edit,
    dibatalkan_at,
    dibatalkan_by,
    alasan_batal,
    tagihan_sopir_ledger_id,
    biaya_sopir_operasional_id,
    biaya_sopir_dibayar_at,
    menggunakan_armada_cb_snapshot,
    upah_sopir_cb_snapshot,
    uang_jalan_sopir_cb_snapshot,
    total_biaya_sopir_cb_snapshot
FROM public.transaksi_mitra
WHERE (SELECT public.has_app_role(
  ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']
));

GRANT SELECT ON public.v_master_mitra_operasional TO authenticated;
GRANT SELECT ON public.v_transaksi_mitra_operasional TO authenticated;
GRANT SELECT ON public.v_master_mitra_operasional TO service_role;
GRANT SELECT ON public.v_transaksi_mitra_operasional TO service_role;

COMMIT;
