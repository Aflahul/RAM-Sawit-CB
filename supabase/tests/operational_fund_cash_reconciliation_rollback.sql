-- Regresi keputusan Owner 23 Juli 2026:
-- 1. Dana Operasional Armada CB otomatis dianggap sudah dibayar Mitra.
-- 2. Sewa akhir = sewa kotor - Dana Operasional.
-- 3. Biaya/hutang Kas CB lama dibatalkan dan kas keluar dinetralkan reversal.
-- Seluruh fixture dibatalkan pada akhir pengujian.
BEGIN;

DO $test_setup$
BEGIN
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
  '00000000-0000-4000-8000-00000000f101',
  'authenticated', 'authenticated', 'cash-reconcile-owner@example.test', '', now(),
  '{}'::jsonb, '{}'::jsonb, now(), now()
);

INSERT INTO public.users (id, nama, username, role)
VALUES (
  '00000000-0000-4000-8000-00000000f101',
  'Owner Cash Reconcile Test', 'owner_cash_reconcile_test', 'owner'
);

INSERT INTO public.master_mitra (
  id, nama, kode, fee_per_kg, tarif_sewa_angkut_per_kg,
  dana_operasional_trip, aktif, status_verifikasi, dibuat_oleh
) VALUES (
  '00000000-0000-4000-8000-00000000f102',
  'Mitra Cash Reconcile Test', 'CASH-RECON', 30, 150,
  750000, true, 'terverifikasi', '00000000-0000-4000-8000-00000000f101'
);

INSERT INTO public.sopir (
  id, nama, plat_nomor, is_armada_cb, aktif, status_verifikasi, dibuat_oleh
) VALUES (
  '00000000-0000-4000-8000-00000000f103',
  'Sopir Cash Reconcile Test', 'TEST 751', true, true, 'terverifikasi',
  '00000000-0000-4000-8000-00000000f101'
);

INSERT INTO public.rekening_kas (
  id, nama, tipe, saldo_awal, aktif, is_default, created_by
) VALUES (
  '00000000-0000-4000-8000-00000000f104',
  'Kas Cash Reconcile Test', 'kas', 0, true, false,
  '00000000-0000-4000-8000-00000000f101'
);

-- Simulasikan transaksi production yang sempat memakai alur Kas CB lama.
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
  dana_operasional_dibayar_mitra, biaya_sopir_dibayar_at,
  created_by, updated_by
) VALUES (
  '00000000-0000-4000-8000-00000000f105', '2026-07-22',
  '00000000-0000-4000-8000-00000000f103',
  '00000000-0000-4000-8000-00000000f103', 'Sopir Cash Reconcile Test',
  '00000000-0000-4000-8000-00000000f103', 'Sopir Cash Reconcile Test',
  '00000000-0000-4000-8000-00000000f102', 'TEST 751',
  10930, 10930, 546, 10384,
  2940, 2940, 30, 2910,
  30528960, 311520, 30217440,
  true, true, true, true,
  150, 150, 1639500, 1639500,
  750000, 750000, null, now(),
  '00000000-0000-4000-8000-00000000f101',
  '00000000-0000-4000-8000-00000000f101'
);

INSERT INTO public.hutang_ledger (
  id, pihak_type, sopir_id, tanggal, tipe, sumber, jumlah,
  legacy_source_table, legacy_source_id, keterangan, created_by
) VALUES (
  '00000000-0000-4000-8000-00000000f106', 'sopir',
  '00000000-0000-4000-8000-00000000f103', '2026-07-22',
  'debit', 'operasional', 750000, 'tagihan_sopir_cb',
  '00000000-0000-4000-8000-00000000f105',
  'Tagihan Dana Trip lama', '00000000-0000-4000-8000-00000000f101'
);

INSERT INTO public.biaya_operasional (
  id, tanggal, kategori, jumlah, keterangan, tipe_biaya, status,
  rekening_kas_id, armada_sopir_id, transaksi_mitra_id, created_by
) VALUES (
  '00000000-0000-4000-8000-00000000f107', '2026-07-22',
  'dana_operasional_trip', 750000, 'Biaya Dana Trip lama',
  'perusahaan_murni', 'aktif',
  '00000000-0000-4000-8000-00000000f104',
  '00000000-0000-4000-8000-00000000f103',
  '00000000-0000-4000-8000-00000000f105',
  '00000000-0000-4000-8000-00000000f101'
);

INSERT INTO public.kas_ledger (
  id, rekening_kas_id, tanggal, tipe, sumber, jumlah,
  biaya_operasional_id, source_table, source_id,
  idempotency_key, keterangan, created_by
) VALUES (
  '00000000-0000-4000-8000-00000000f108',
  '00000000-0000-4000-8000-00000000f104', '2026-07-22',
  'keluar', 'biaya_operasional', 750000,
  '00000000-0000-4000-8000-00000000f107',
  'transaksi_mitra', '00000000-0000-4000-8000-00000000f105',
  'cash-reconcile-test:original', 'Kas keluar Dana Trip lama',
  '00000000-0000-4000-8000-00000000f101'
);

UPDATE public.biaya_operasional
SET kas_ledger_id = '00000000-0000-4000-8000-00000000f108'
WHERE id = '00000000-0000-4000-8000-00000000f107';

INSERT INTO public.hutang_ledger (
  id, pihak_type, sopir_id, tanggal, tipe, sumber, jumlah,
  legacy_source_table, legacy_source_id, keterangan,
  rekening_kas_id, kas_ledger_id, created_by
) VALUES (
  '00000000-0000-4000-8000-00000000f109', 'sopir',
  '00000000-0000-4000-8000-00000000f103', '2026-07-22',
  'kredit', 'bayar_tunai', 750000, 'pembayaran_tagihan_sopir_cb',
  '00000000-0000-4000-8000-00000000f106', 'Pelunasan Dana Trip lama',
  '00000000-0000-4000-8000-00000000f104',
  '00000000-0000-4000-8000-00000000f108',
  '00000000-0000-4000-8000-00000000f101'
);

UPDATE public.kas_ledger
SET hutang_ledger_id = '00000000-0000-4000-8000-00000000f109'
WHERE id = '00000000-0000-4000-8000-00000000f108';

UPDATE public.transaksi_mitra
SET tagihan_sopir_ledger_id = '00000000-0000-4000-8000-00000000f106',
    tagihan_sopir_bayar_ledger_id = '00000000-0000-4000-8000-00000000f109',
    biaya_sopir_operasional_id = '00000000-0000-4000-8000-00000000f107'
WHERE id = '00000000-0000-4000-8000-00000000f105';

SET LOCAL session_replication_role = origin;
SELECT set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-00000000f101',
  true
);

-- Menyalakan sumber dana Mitra memicu rekonsiliasi seluruh pencatatan lama.
UPDATE public.transaksi_mitra
SET dana_operasional_dibayar_mitra = true,
    updated_by = '00000000-0000-4000-8000-00000000f101'
WHERE id = '00000000-0000-4000-8000-00000000f105';

DO $test$
DECLARE
  v_row public.transaksi_mitra%ROWTYPE;
  v_count integer;
  v_net_cash numeric(15,2);
  v_owner_income numeric(15,2);
BEGIN
  SELECT * INTO v_row
  FROM public.transaksi_mitra
  WHERE id = '00000000-0000-4000-8000-00000000f105';

  IF v_row.dana_operasional_dibayar_mitra IS DISTINCT FROM true
     OR v_row.biaya_sewa_armada_kotor <> 1639500
     OR v_row.biaya_sewa_armada_total <> 889500 THEN
    RAISE EXCEPTION
      'REGRESSION: transaksi belum menjadi 1639500 - 750000 = 889500 (actual %, %, %).',
      v_row.biaya_sewa_armada_kotor,
      v_row.dana_operasional_trip_snapshot,
      v_row.biaya_sewa_armada_total;
  END IF;

  IF v_row.tagihan_sopir_ledger_id IS NOT NULL
     OR v_row.tagihan_sopir_bayar_ledger_id IS NOT NULL
     OR v_row.biaya_sopir_operasional_id IS NOT NULL
     OR v_row.biaya_sopir_dibayar_at IS NOT NULL THEN
    RAISE EXCEPTION 'REGRESSION: referensi pencatatan Kas CB lama belum dibersihkan.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.hutang_ledger
  WHERE id IN (
    '00000000-0000-4000-8000-00000000f106',
    '00000000-0000-4000-8000-00000000f109'
  )
    AND status = 'dibatalkan';

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'REGRESSION: tagihan dan pelunasan lama tidak seluruhnya dibatalkan.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.biaya_operasional
  WHERE id = '00000000-0000-4000-8000-00000000f107'
    AND status = 'dibatalkan';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'REGRESSION: biaya operasional CB lama masih aktif.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.kas_ledger
  WHERE reversal_of_id = '00000000-0000-4000-8000-00000000f108'
    AND tipe = 'masuk'
    AND sumber = 'reversal'
    AND jumlah = 750000
    AND status = 'aktif';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'REGRESSION: kas keluar Rp750.000 tidak memiliki satu transaksi balik aktif.';
  END IF;

  SELECT COALESCE(sum(
    CASE
      WHEN tipe IN ('masuk', 'transfer_masuk') THEN jumlah
      WHEN tipe IN ('keluar', 'transfer_keluar') THEN -jumlah
      ELSE 0
    END
  ), 0) INTO v_net_cash
  FROM public.kas_ledger
  WHERE status = 'aktif'
    AND (
      id = '00000000-0000-4000-8000-00000000f108'
      OR reversal_of_id = '00000000-0000-4000-8000-00000000f108'
    );

  IF v_net_cash <> 0 THEN
    RAISE EXCEPTION 'REGRESSION: dampak bersih kas Dana Trip masih %, expected 0.', v_net_cash;
  END IF;

  v_owner_income := v_row.total_fee_owner + v_row.biaya_sewa_armada_total;
  IF v_owner_income <> 1201020 THEN
    RAISE EXCEPTION
      'REGRESSION: pendapatan Owner %, expected fee 311520 + sewa 889500 = 1201020.',
      v_owner_income;
  END IF;

  -- Ulangi update untuk memastikan rekonsiliasi idempoten.
  UPDATE public.transaksi_mitra
  SET dana_operasional_dibayar_mitra = true
  WHERE id = v_row.id;

  SELECT count(*) INTO v_count
  FROM public.kas_ledger
  WHERE reversal_of_id = '00000000-0000-4000-8000-00000000f108'
    AND status <> 'dibatalkan';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'REGRESSION: rekonsiliasi ulang membuat reversal kas ganda.';
  END IF;
END;
$test$;

-- Transaksi baru harus otomatis TRUE walaupun pemanggil mengirim FALSE.
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
  dana_operasional_dibayar_mitra, created_by
) VALUES (
  '00000000-0000-4000-8000-00000000f110', '2026-07-23',
  '00000000-0000-4000-8000-00000000f103',
  '00000000-0000-4000-8000-00000000f103', 'Sopir Cash Reconcile Test',
  '00000000-0000-4000-8000-00000000f103', 'Sopir Cash Reconcile Test',
  '00000000-0000-4000-8000-00000000f102', 'TEST 751',
  10930, 10930, 546, 10384,
  2940, 2940, 30, 2910,
  30528960, 311520, 30217440,
  true, true, true, true,
  150, 150, 1639500, 1639500,
  750000, 750000, false,
  '00000000-0000-4000-8000-00000000f101'
);

DO $insert_test$
DECLARE
  v_row public.transaksi_mitra%ROWTYPE;
BEGIN
  SELECT * INTO v_row
  FROM public.transaksi_mitra
  WHERE id = '00000000-0000-4000-8000-00000000f110';

  IF v_row.dana_operasional_dibayar_mitra IS DISTINCT FROM true
     OR v_row.biaya_sewa_armada_total <> 889500
     OR v_row.biaya_sopir_dibayar_at IS NOT NULL THEN
    RAISE EXCEPTION
      'REGRESSION: transaksi baru tidak otomatis dibayar Mitra/final 889500.';
  END IF;
END;
$insert_test$;

ROLLBACK;
