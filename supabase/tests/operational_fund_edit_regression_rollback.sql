-- Regresi S1: Dana Operasional Rp750.000 dibayar langsung oleh Mitra.
-- Potongan akhir sewa harus Rp1.639.500 - Rp750.000 = Rp889.500,
-- tanpa utang, biaya operasional, atau arus kas CB baru.
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
  dana_operasional_dibayar_mitra,
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
  0, 0, true,
  '00000000-0000-4000-8000-00000000f001'
);

INSERT INTO public.hutang_ledger (
  id, pihak_type, sopir_id, tanggal, tipe, sumber, jumlah,
  legacy_source_table, legacy_source_id, keterangan, created_by
) VALUES (
  '00000000-0000-4000-8000-00000000f006', 'sopir',
  '00000000-0000-4000-8000-00000000f003', '2026-07-22',
  'debit', 'operasional', 750000, 'tagihan_sopir_cb',
  '00000000-0000-4000-8000-00000000f004',
  'Tagihan lama yang harus dibatalkan oleh keputusan Owner',
  '00000000-0000-4000-8000-00000000f001'
);

UPDATE public.transaksi_mitra
SET tagihan_sopir_ledger_id = '00000000-0000-4000-8000-00000000f006'
WHERE id = '00000000-0000-4000-8000-00000000f004';

SET LOCAL session_replication_role = origin;
SELECT set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-00000000f001',
  true
);

DO $test$
DECLARE
  v_row public.transaksi_mitra;
  v_payment public.pembayaran_mitra_kwitansi;
  v_item public.pembayaran_mitra_kwitansi_item%ROWTYPE;
  v_kas_amount numeric(15,2);
  v_count integer;
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

  IF v_row.dana_operasional_dibayar_mitra IS DISTINCT FROM true
     OR v_row.biaya_sewa_armada_kotor <> 1639500
     OR v_row.biaya_sewa_armada_total <> 889500 THEN
    RAISE EXCEPTION
      'REGRESSION: sewa kotor %, Dana %, potongan akhir %, expected 1639500 - 750000 = 889500.',
      v_row.biaya_sewa_armada_kotor,
      v_row.dana_operasional_trip_snapshot,
      v_row.biaya_sewa_armada_total;
  END IF;

  IF v_row.tagihan_sopir_ledger_id IS NOT NULL THEN
    RAISE EXCEPTION 'REGRESSION: transaksi masih memiliki tagihan Dana Trip %.', v_row.tagihan_sopir_ledger_id;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.hutang_ledger
  WHERE legacy_source_table = 'tagihan_sopir_cb'
    AND legacy_source_id = v_row.id
    AND status = 'aktif';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'REGRESSION: tagihan Dana Trip aktif masih tersisa.';
  END IF;

  SELECT * INTO v_payment
  FROM public.create_pembayaran_mitra_kwitansi(
    '00000000-0000-4000-8000-00000000f002',
    '2026-07-22',
    '2026-07-22',
    'tunai',
    'Regresi sumber Dana Operasional langsung dari Mitra',
    null,
    null
  );

  IF v_payment.total_sewa_armada <> 889500
     OR v_payment.nominal_dibayar <> 29327940 THEN
    RAISE EXCEPTION
      'REGRESSION: total kwitansi salah (sewa akhir %, kas keluar %), expected 889500 dan 29327940.',
      v_payment.total_sewa_armada,
      v_payment.nominal_dibayar;
  END IF;

  SELECT * INTO v_item
  FROM public.pembayaran_mitra_kwitansi_item
  WHERE pembayaran_id = v_payment.id
    AND transaksi_mitra_id = '00000000-0000-4000-8000-00000000f004';

  IF v_item.dana_operasional_trip_snapshot <> 750000
     OR v_item.dana_operasional_dibayar_mitra_snapshot IS DISTINCT FROM true
     OR v_item.biaya_sewa_armada_standar_snapshot <> 1639500
     OR v_item.biaya_sewa_armada_snapshot <> 889500 THEN
    RAISE EXCEPTION
      'REGRESSION: snapshot kwitansi salah (kotor %, Dana %, akhir %).',
      v_item.biaya_sewa_armada_standar_snapshot,
      v_item.dana_operasional_trip_snapshot,
      v_item.biaya_sewa_armada_snapshot;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.biaya_operasional
  WHERE transaksi_mitra_id = v_row.id
    AND kategori = 'dana_operasional_trip'
    AND status <> 'dibatalkan';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'REGRESSION: Dana Operasional langsung tercatat sebagai biaya Kas CB.';
  END IF;

  SELECT jumlah INTO v_kas_amount
  FROM public.kas_ledger
  WHERE pembayaran_mitra_kwitansi_id = v_payment.id
    AND status = 'aktif';

  IF v_kas_amount <> 29327940 THEN
    RAISE EXCEPTION
      'REGRESSION: Kas CB keluar %, expected hanya pembayaran Mitra 29327940.',
      COALESCE(v_kas_amount, 0);
  END IF;
END;
$test$;

ROLLBACK;
