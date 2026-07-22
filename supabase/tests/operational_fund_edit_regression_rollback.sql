-- Regresi S1: edit transaksi dengan checkbox Dana Trip tetap aktif harus
-- memperbaiki snapshot Rp750.000 yang sebelumnya tersimpan sebagai nol.
-- Seluruh fixture dibatalkan pada akhir pengujian.
BEGIN;

DO $test_setup$
BEGIN
  -- Local P0 mempunyai trigger tambahan yang belum ada pada production main.
  -- Nonaktifkan dalam transaksi ini agar tes mereproduksi jalur production.
  IF EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'public.transaksi_mitra'::regclass
      AND tgname = 'enforce_transaksi_mitra_financial_snapshots'
  ) THEN
    EXECUTE 'ALTER TABLE public.transaksi_mitra DISABLE TRIGGER enforce_transaksi_mitra_financial_snapshots';
  END IF;
END;
$test_setup$;

SET LOCAL session_replication_role = replica;

INSERT INTO auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES (
  '00000000-0000-4000-8000-00000000f001',
  'authenticated', 'authenticated', 'hotfix-owner@example.test', '', now(),
  '{}'::jsonb, '{}'::jsonb, now(), now()
);

INSERT INTO public.users (id, nama, username, role)
VALUES (
  '00000000-0000-4000-8000-00000000f001',
  'Owner Hotfix Test', 'owner_hotfix_test', 'owner'
);

INSERT INTO public.master_mitra (
  id, nama, kode, fee_per_kg, tarif_sewa_angkut_per_kg,
  dana_operasional_trip, aktif, status_verifikasi, dibuat_oleh
) VALUES (
  '00000000-0000-4000-8000-00000000f002',
  'Mitra Hotfix Test', 'HOTFIX-TRIP', 30, 150,
  750000, true, 'terverifikasi', '00000000-0000-4000-8000-00000000f001'
);

INSERT INTO public.sopir (
  id, nama, plat_nomor, is_armada_cb, aktif, status_verifikasi, dibuat_oleh
) VALUES (
  '00000000-0000-4000-8000-00000000f003',
  'Sopir Hotfix Test', 'TEST 750', true, true, 'terverifikasi',
  '00000000-0000-4000-8000-00000000f001'
);

-- Simulasikan data bermasalah di production: checkbox aktif tetapi snapshot nol.
INSERT INTO public.transaksi_mitra (
  id, tanggal, sopir_id, sopir_default_id, sopir_default_nama,
  sopir_aktual_id, sopir_aktual_nama, mitra_id, plat_nomor,
  tonase, berat_netto_pabrik_kg, potongan_pabrik_kg, berat_dibayar_kg,
  harga_harian, harga_pabrik_per_kg, fee_owner_per_kg, harga_bersih_per_kg,
  total_kotor, total_fee_owner, total_nilai_bersih,
  menggunakan_armada_cb_snapshot, pakai_sewa_armada_bl,
  kenakan_sewa_armada_cb, catat_dana_operasional_trip,
  tarif_sewa_angkut_per_kg_snapshot, biaya_sewa_armada_per_kg,
  biaya_sewa_armada_kotor, biaya_sewa_armada_total,
  dana_operasional_trip_snapshot, total_biaya_sopir_cb_snapshot,
  created_by
) VALUES (
  '00000000-0000-4000-8000-00000000f004', '2026-07-22',
  '00000000-0000-4000-8000-00000000f003',
  '00000000-0000-4000-8000-00000000f003', 'Sopir Hotfix Test',
  '00000000-0000-4000-8000-00000000f003', 'Sopir Hotfix Test',
  '00000000-0000-4000-8000-00000000f002', 'TEST 750',
  10930, 10930, 546, 10384,
  2940, 2940, 30, 2910,
  30528960, 311520, 30217440,
  true, true, true, true,
  150, 150, 1639500, 1639500,
  0, 0,
  '00000000-0000-4000-8000-00000000f001'
);

SET LOCAL session_replication_role = origin;
SELECT set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-00000000f001',
  true
);

DO $test$
DECLARE
  v_row public.transaksi_mitra;
  v_tagihan numeric;
BEGIN
  SELECT * INTO v_row
  FROM public.update_transaksi_mitra_controlled(
    '00000000-0000-4000-8000-00000000f004',
    jsonb_build_object(
      'catat_dana_operasional_trip', true,
      'catatan_sopir', 'Regresi snapshot Dana Trip Rp750.000'
    ),
    'Perbaiki Dana Operasional Trip yang tidak tersimpan saat edit'
  );

  IF v_row.dana_operasional_trip_snapshot <> 750000
     OR v_row.total_biaya_sopir_cb_snapshot <> 750000 THEN
    RAISE EXCEPTION
      'REGRESSION: checkbox aktif tetapi snapshot Dana Trip tetap %, expected 750000.',
      v_row.dana_operasional_trip_snapshot;
  END IF;

  SELECT jumlah INTO v_tagihan
  FROM public.hutang_ledger
  WHERE id = v_row.tagihan_sopir_ledger_id
    AND status = 'aktif';

  IF v_tagihan <> 750000 THEN
    RAISE EXCEPTION
      'REGRESSION: tagihan Dana Trip %, expected 750000.',
      COALESCE(v_tagihan, 0);
  END IF;

  INSERT INTO public.pembayaran_mitra_kwitansi (
    id, master_mitra_id, periode_dari, periode_sampai,
    transaksi_snapshot_json, panjar_snapshot_json, created_by
  ) VALUES (
    '00000000-0000-4000-8000-00000000f005',
    '00000000-0000-4000-8000-00000000f002',
    '2026-07-22', '2026-07-22', '[]'::jsonb, '[]'::jsonb,
    '00000000-0000-4000-8000-00000000f001'
  );

  INSERT INTO public.pembayaran_mitra_kwitansi_item (
    pembayaran_id, transaksi_mitra_id, master_mitra_id, tanggal,
    tonase_snapshot, berat_netto_snapshot, potongan_snapshot,
    berat_dibayar_snapshot, pakai_sewa_armada_snapshot,
    biaya_sewa_armada_snapshot, harga_bersih_per_kg_snapshot,
    total_nilai_bersih_snapshot
  ) VALUES (
    '00000000-0000-4000-8000-00000000f005',
    '00000000-0000-4000-8000-00000000f004',
    '00000000-0000-4000-8000-00000000f002', '2026-07-22',
    10930, 10930, 546, 10384, true, 1639500, 2910, 30217440
  );

  SELECT dana_operasional_trip_snapshot INTO v_tagihan
  FROM public.pembayaran_mitra_kwitansi_item
  WHERE pembayaran_id = '00000000-0000-4000-8000-00000000f005'
    AND transaksi_mitra_id = '00000000-0000-4000-8000-00000000f004';

  IF v_tagihan <> 750000 THEN
    RAISE EXCEPTION
      'REGRESSION: snapshot Dana Trip pada item kwitansi %, expected 750000.',
      COALESCE(v_tagihan, 0);
  END IF;
END;
$test$;

ROLLBACK;
