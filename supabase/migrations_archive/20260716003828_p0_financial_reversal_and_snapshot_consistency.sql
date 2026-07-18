-- P0 financial controls: immutable paid transactions, explicit receipt
-- reversal, separate weight meanings, non-overlapping tariff periods, and
-- auditable manual-cash reversal.

ALTER TABLE public.pembayaran_mitra_kwitansi
  ADD COLUMN IF NOT EXISTS total_berat_netto numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_berat_dibayar numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS nomor_bukti text,
  ADD COLUMN IF NOT EXISTS alasan_batal text,
  ADD COLUMN IF NOT EXISTS dibatalkan_at timestamptz,
  ADD COLUMN IF NOT EXISTS dibatalkan_by uuid REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS reversal_kas_ledger_id uuid REFERENCES public.kas_ledger(id);

ALTER TABLE public.pembayaran_mitra_kwitansi_mitra
  ADD COLUMN IF NOT EXISTS total_berat_netto numeric(15,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_berat_dibayar numeric(15,2) NOT NULL DEFAULT 0;

ALTER TABLE public.kas_ledger
  ADD COLUMN IF NOT EXISTS nomor_bukti text,
  ADD COLUMN IF NOT EXISTS reversed_at timestamptz,
  ADD COLUMN IF NOT EXISTS reversed_by uuid REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS reversal_reason text;

-- A cancelled receipt may issue a new item for the same transaction. The RPC
-- prevents two active receipts, while the per-payment unique key remains.
ALTER TABLE public.pembayaran_mitra_kwitansi_item
  DROP CONSTRAINT IF EXISTS pembayaran_mitra_kwitansi_item_unique_trx;

CREATE INDEX IF NOT EXISTS idx_kwitansi_item_transaksi
  ON public.pembayaran_mitra_kwitansi_item (transaksi_mitra_id, pembayaran_id);

CREATE OR REPLACE FUNCTION public.recalculate_kwitansi_totals(p_pembayaran_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_netto numeric(15,2);
  v_dibayar numeric(15,2);
BEGIN
  SELECT
    COALESCE(SUM(COALESCE(berat_netto_snapshot, tonase_snapshot)), 0)::numeric(15,2),
    COALESCE(SUM(COALESCE(berat_dibayar_snapshot, tonase_snapshot)), 0)::numeric(15,2)
  INTO v_netto, v_dibayar
  FROM public.pembayaran_mitra_kwitansi_item
  WHERE pembayaran_id = p_pembayaran_id;

  UPDATE public.pembayaran_mitra_kwitansi
  SET total_berat_netto = v_netto,
      total_berat_dibayar = v_dibayar,
      total_tonase = v_dibayar,
      updated_at = now()
  WHERE id = p_pembayaran_id;

  UPDATE public.pembayaran_mitra_kwitansi_mitra summary
  SET total_berat_netto = aggregate.total_netto,
      total_berat_dibayar = aggregate.total_dibayar,
      total_tonase = aggregate.total_dibayar
  FROM (
    SELECT
      master_mitra_id,
      COALESCE(SUM(COALESCE(berat_netto_snapshot, tonase_snapshot)), 0)::numeric(15,2) total_netto,
      COALESCE(SUM(COALESCE(berat_dibayar_snapshot, tonase_snapshot)), 0)::numeric(15,2) total_dibayar
    FROM public.pembayaran_mitra_kwitansi_item
    WHERE pembayaran_id = p_pembayaran_id
    GROUP BY master_mitra_id
  ) aggregate
  WHERE summary.pembayaran_id = p_pembayaran_id
    AND summary.master_mitra_id = aggregate.master_mitra_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_kwitansi_totals_from_item()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.recalculate_kwitansi_totals(COALESCE(NEW.pembayaran_id, OLD.pembayaran_id));
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sync_kwitansi_totals_from_item ON public.pembayaran_mitra_kwitansi_item;
CREATE TRIGGER sync_kwitansi_totals_from_item
AFTER INSERT OR DELETE ON public.pembayaran_mitra_kwitansi_item
FOR EACH ROW EXECUTE FUNCTION public.sync_kwitansi_totals_from_item();

-- The payment RPC inserts item rows before the per-mitra summary row. Re-run
-- the calculation after each summary insert so newly created receipts are
-- correct immediately, not only after a later backfill.
CREATE OR REPLACE FUNCTION public.sync_kwitansi_totals_from_summary()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.recalculate_kwitansi_totals(NEW.pembayaran_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_kwitansi_totals_from_summary ON public.pembayaran_mitra_kwitansi_mitra;
CREATE TRIGGER sync_kwitansi_totals_from_summary
AFTER INSERT ON public.pembayaran_mitra_kwitansi_mitra
FOR EACH ROW EXECUTE FUNCTION public.sync_kwitansi_totals_from_summary();

DO $$
DECLARE
  v_payment record;
BEGIN
  FOR v_payment IN SELECT id FROM public.pembayaran_mitra_kwitansi LOOP
    PERFORM public.recalculate_kwitansi_totals(v_payment.id);
  END LOOP;
END $$;

-- Repair old tariff ranges deterministically, then prevent future overlap.
-- Multiple edits can exist on the same effective date in legacy data. Keep
-- the newest one active and retain older rows as inactive audit history.
ALTER TABLE public.fee_owner_mitra_history
  DROP CONSTRAINT IF EXISTS fee_owner_mitra_history_periode_check;

WITH ranked_same_day AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY master_mitra_id, berlaku_mulai
      ORDER BY created_at DESC, id DESC
    ) AS revision_number
  FROM public.fee_owner_mitra_history
  WHERE aktif = true
)
UPDATE public.fee_owner_mitra_history history
SET aktif = false,
    berlaku_sampai = history.berlaku_mulai,
    alasan_perubahan = concat_ws(' | ', nullif(history.alasan_perubahan, ''), 'Digantikan revisi lain pada tanggal yang sama')
FROM ranked_same_day ranked
WHERE history.id = ranked.id
  AND ranked.revision_number > 1;

WITH ordered AS (
  SELECT
    id,
    lead(berlaku_mulai) OVER (
      PARTITION BY master_mitra_id
      ORDER BY berlaku_mulai, created_at, id
    ) next_start
  FROM public.fee_owner_mitra_history
  WHERE aktif = true
)
UPDATE public.fee_owner_mitra_history history
SET berlaku_sampai = CASE WHEN ordered.next_start IS NULL THEN NULL ELSE ordered.next_start - 1 END
FROM ordered
WHERE history.id = ordered.id;

ALTER TABLE public.fee_owner_mitra_history
  ADD CONSTRAINT fee_owner_mitra_history_periode_check
  CHECK (berlaku_sampai IS NULL OR berlaku_sampai >= berlaku_mulai);

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fee_owner_mitra_history_no_overlap'
  ) THEN
    ALTER TABLE public.fee_owner_mitra_history
      ADD CONSTRAINT fee_owner_mitra_history_no_overlap
      EXCLUDE USING gist (
        master_mitra_id WITH =,
        daterange(berlaku_mulai, COALESCE(berlaku_sampai, 'infinity'::date), '[]') WITH &&
      ) WHERE (aktif = true);
  END IF;
END $$;

-- Paid receipt and factory snapshots are immutable from normal edit forms.
CREATE OR REPLACE FUNCTION public.guard_paid_transaksi_mitra_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_material_change boolean;
  v_armada_change boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  v_material_change :=
    OLD.tanggal IS DISTINCT FROM NEW.tanggal
    OR OLD.mitra_id IS DISTINCT FROM NEW.mitra_id
    OR OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
    OR OLD.sopir_aktual_id IS DISTINCT FROM NEW.sopir_aktual_id
    OR OLD.sopir_aktual_nama IS DISTINCT FROM NEW.sopir_aktual_nama
    OR OLD.plat_nomor IS DISTINCT FROM NEW.plat_nomor
    OR OLD.tonase IS DISTINCT FROM NEW.tonase
    OR OLD.berat_netto_pabrik_kg IS DISTINCT FROM NEW.berat_netto_pabrik_kg
    OR OLD.potongan_pabrik_kg IS DISTINCT FROM NEW.potongan_pabrik_kg
    OR OLD.berat_dibayar_kg IS DISTINCT FROM NEW.berat_dibayar_kg
    OR OLD.harga_pabrik_per_kg IS DISTINCT FROM NEW.harga_pabrik_per_kg
    OR OLD.fee_owner_per_kg IS DISTINCT FROM NEW.fee_owner_per_kg
    OR OLD.total_nilai_bersih IS DISTINCT FROM NEW.total_nilai_bersih
    OR OLD.pakai_sewa_armada_bl IS DISTINCT FROM NEW.pakai_sewa_armada_bl
    OR OLD.biaya_sewa_armada_total IS DISTINCT FROM NEW.biaya_sewa_armada_total
    OR OLD.status IS DISTINCT FROM NEW.status;

  v_armada_change :=
    OLD.tanggal IS DISTINCT FROM NEW.tanggal
    OR OLD.mitra_id IS DISTINCT FROM NEW.mitra_id
    OR OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
    OR OLD.sopir_aktual_id IS DISTINCT FROM NEW.sopir_aktual_id
    OR OLD.plat_nomor IS DISTINCT FROM NEW.plat_nomor
    OR OLD.dana_operasional_trip_snapshot IS DISTINCT FROM NEW.dana_operasional_trip_snapshot
    OR OLD.status IS DISTINCT FROM NEW.status;

  IF v_material_change AND EXISTS (
    SELECT 1
    FROM public.pembayaran_mitra_kwitansi_item item
    JOIN public.pembayaran_mitra_kwitansi payment ON payment.id = item.pembayaran_id
    WHERE item.transaksi_mitra_id = OLD.id
      AND payment.status <> 'dibatalkan'
  ) THEN
    RAISE EXCEPTION 'Transaksi sudah masuk kwitansi. Batalkan kwitansi melalui menu Kwitansi sebelum mengoreksi transaksi.'
      USING ERRCODE = '55000';
  END IF;

  IF v_material_change AND EXISTS (
    SELECT 1
    FROM public.pembayaran_pabrik_item item
    JOIN public.pembayaran_pabrik_batch payment ON payment.id = item.pembayaran_id
    WHERE item.transaksi_mitra_id = OLD.id
      AND payment.status <> 'dibatalkan'
  ) THEN
    RAISE EXCEPTION 'Transaksi sudah dicocokkan dengan pembayaran pabrik. Batalkan pembayaran pabrik sebelum mengoreksi transaksi.'
      USING ERRCODE = '55000';
  END IF;

  IF v_armada_change AND OLD.biaya_sopir_dibayar_at IS NOT NULL THEN
    RAISE EXCEPTION 'Dana Operasional Trip sudah dibayar. Koreksi pembayaran Dana Trip terlebih dahulu.'
      USING ERRCODE = '55000';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_paid_transaksi_mitra_changes ON public.transaksi_mitra;
CREATE TRIGGER guard_paid_transaksi_mitra_changes
BEFORE UPDATE ON public.transaksi_mitra
FOR EACH ROW EXECUTE FUNCTION public.guard_paid_transaksi_mitra_changes();

CREATE OR REPLACE FUNCTION public.flag_kwitansi_after_system_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.tanggal IS DISTINCT FROM NEW.tanggal
     OR OLD.mitra_id IS DISTINCT FROM NEW.mitra_id
     OR OLD.tonase IS DISTINCT FROM NEW.tonase
     OR OLD.berat_netto_pabrik_kg IS DISTINCT FROM NEW.berat_netto_pabrik_kg
     OR OLD.potongan_pabrik_kg IS DISTINCT FROM NEW.potongan_pabrik_kg
     OR OLD.berat_dibayar_kg IS DISTINCT FROM NEW.berat_dibayar_kg
     OR OLD.total_nilai_bersih IS DISTINCT FROM NEW.total_nilai_bersih
     OR OLD.biaya_sewa_armada_total IS DISTINCT FROM NEW.biaya_sewa_armada_total
     OR OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE public.pembayaran_mitra_kwitansi payment
    SET status = 'perlu_review',
        review_reason = 'Data sumber transaksi berubah setelah kwitansi dibuat.',
        updated_at = now()
    WHERE payment.id IN (
      SELECT item.pembayaran_id
      FROM public.pembayaran_mitra_kwitansi_item item
      WHERE item.transaksi_mitra_id = NEW.id
    )
      AND payment.status <> 'dibatalkan';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS flag_kwitansi_after_system_change ON public.transaksi_mitra;
CREATE TRIGGER flag_kwitansi_after_system_change
AFTER UPDATE ON public.transaksi_mitra
FOR EACH ROW EXECUTE FUNCTION public.flag_kwitansi_after_system_change();

-- Existing invalid relation is preserved for audit and exposed as a review
-- case. It is not silently reversed by a migration.
UPDATE public.pembayaran_mitra_kwitansi payment
SET status = 'perlu_review',
    review_reason = 'Ada transaksi dalam kwitansi yang sudah dibatalkan. Lakukan pembatalan kwitansi dan terbitkan ulang.',
    updated_at = now()
WHERE payment.status <> 'dibatalkan'
  AND EXISTS (
    SELECT 1
    FROM public.pembayaran_mitra_kwitansi_item item
    JOIN public.transaksi_mitra transaksi ON transaksi.id = item.transaksi_mitra_id
    WHERE item.pembayaran_id = payment.id
      AND transaksi.status = 'dibatalkan'
  );

CREATE OR REPLACE FUNCTION public.cancel_pembayaran_mitra_kwitansi(
  p_pembayaran_id uuid,
  p_alasan text
)
RETURNS public.pembayaran_mitra_kwitansi
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.pembayaran_mitra_kwitansi%ROWTYPE;
  v_after public.pembayaran_mitra_kwitansi%ROWTYPE;
  v_original_kas public.kas_ledger%ROWTYPE;
  v_reversal_id uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat membatalkan pembayaran mitra.' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_alasan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before
  FROM public.pembayaran_mitra_kwitansi
  WHERE id = p_pembayaran_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Kwitansi pembayaran tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  IF v_before.status = 'dibatalkan' THEN
    RAISE EXCEPTION 'Kwitansi pembayaran sudah dibatalkan.' USING ERRCODE = '22023';
  END IF;

  IF v_before.kas_ledger_id IS NOT NULL THEN
    SELECT * INTO v_original_kas
    FROM public.kas_ledger
    WHERE id = v_before.kas_ledger_id
    FOR UPDATE;

    SELECT id INTO v_reversal_id
    FROM public.kas_ledger
    WHERE reversal_of_id = v_original_kas.id
      AND status <> 'dibatalkan'
    LIMIT 1;

    IF v_reversal_id IS NULL THEN
      INSERT INTO public.kas_ledger (
        rekening_kas_id, tanggal, tipe, sumber, jumlah,
        pembayaran_mitra_kwitansi_id, source_table, source_id,
        reversal_of_id, idempotency_key, keterangan, created_by, status
      ) VALUES (
        v_original_kas.rekening_kas_id,
        (now() AT TIME ZONE 'Asia/Jakarta')::date,
        'masuk', 'reversal', v_original_kas.jumlah,
        v_before.id, 'pembayaran_mitra_kwitansi', v_before.id,
        v_original_kas.id,
        'pembayaran_mitra_kwitansi:' || v_before.id::text || ':reversal',
        'Pembatalan kwitansi mitra: ' || btrim(p_alasan),
        v_actor, 'reversal'
      ) RETURNING id INTO v_reversal_id;

      UPDATE public.kas_ledger
      SET reversed_at = now(), reversed_by = v_actor, reversal_reason = btrim(p_alasan)
      WHERE id = v_original_kas.id;
    END IF;
  END IF;

  UPDATE public.panjar_mitra
  SET status = 'belum_lunas',
      pembayaran_mitra_kwitansi_id = NULL,
      lunas_at = NULL,
      updated_at = now()
  WHERE pembayaran_mitra_kwitansi_id = v_before.id
    AND status = 'lunas';

  UPDATE public.pembayaran_mitra_kwitansi
  SET status = 'dibatalkan',
      alasan_batal = btrim(p_alasan),
      dibatalkan_at = now(),
      dibatalkan_by = v_actor,
      reversal_kas_ledger_id = v_reversal_id,
      review_reason = NULL,
      updated_by = v_actor,
      updated_at = now()
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  PERFORM public.write_audit_log(
    'pembayaran_mitra_kwitansi', v_after.id, 'cancel_payment',
    to_jsonb(v_before), to_jsonb(v_after), p_alasan, v_actor
  );

  RETURN v_after;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_pembayaran_mitra_kwitansi(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_pembayaran_mitra_kwitansi(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_kas_mutasi_manual(p_kas_id uuid, p_alasan text)
RETURNS public.kas_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.kas_ledger%ROWTYPE;
  v_reversal public.kas_ledger%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat membalik mutasi kas manual.' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_alasan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan pembalikan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before FROM public.kas_ledger WHERE id = p_kas_id FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Mutasi kas tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  IF v_before.source_table IS NOT NULL
     OR v_before.pembayaran_pabrik_id IS NOT NULL
     OR v_before.pembayaran_mitra_kwitansi_id IS NOT NULL
     OR v_before.biaya_operasional_id IS NOT NULL
     OR v_before.hutang_ledger_id IS NOT NULL
     OR v_before.panjar_mitra_id IS NOT NULL THEN
    RAISE EXCEPTION 'Mutasi ini berasal dari modul lain. Batalkan dari halaman sumbernya.' USING ERRCODE = '55000';
  END IF;

  IF v_before.reversed_at IS NOT NULL OR v_before.sumber = 'reversal' THEN
    RAISE EXCEPTION 'Mutasi kas ini sudah dibalik.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.kas_ledger (
    rekening_kas_id, tanggal, tipe, sumber, jumlah, status,
    source_table, source_id, reversal_of_id, idempotency_key,
    keterangan, created_by
  ) VALUES (
    v_before.rekening_kas_id,
    (now() AT TIME ZONE 'Asia/Jakarta')::date,
    CASE WHEN v_before.tipe IN ('masuk', 'transfer_masuk') THEN 'keluar' ELSE 'masuk' END,
    'reversal', v_before.jumlah, 'reversal',
    'kas_manual', v_before.id, v_before.id,
    'kas_manual:' || v_before.id::text || ':reversal',
    'Pembalikan kas manual: ' || btrim(p_alasan), v_actor
  ) RETURNING * INTO v_reversal;

  UPDATE public.kas_ledger
  SET reversed_at = now(), reversed_by = v_actor, reversal_reason = btrim(p_alasan)
  WHERE id = v_before.id;

  PERFORM public.write_audit_log('kas_ledger', v_before.id, 'reverse_manual_cash', to_jsonb(v_before), to_jsonb(v_reversal), p_alasan, v_actor);
  RETURN v_reversal;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_kas_mutasi_manual(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_kas_mutasi_manual(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_kas_summary(
  p_rekening_kas_id uuid DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_saldo_awal numeric := 0;
  v_mutasi_sebelum numeric := 0;
  v_masuk numeric := 0;
  v_keluar numeric := 0;
  v_saldo_pembuka numeric := 0;
  v_saldo_akhir numeric := 0;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang melihat ringkasan kas.' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(SUM(saldo_awal), 0)
  INTO v_saldo_awal
  FROM public.rekening_kas
  WHERE aktif = true
    AND (p_rekening_kas_id IS NULL OR id = p_rekening_kas_id);

  SELECT COALESCE(SUM(
    CASE
      WHEN tipe IN ('masuk', 'transfer_masuk') THEN jumlah
      WHEN tipe IN ('keluar', 'transfer_keluar') THEN -jumlah
      ELSE 0
    END
  ), 0)
  INTO v_mutasi_sebelum
  FROM public.kas_ledger
  WHERE status <> 'dibatalkan'
    AND (p_rekening_kas_id IS NULL OR rekening_kas_id = p_rekening_kas_id)
    AND p_date_from IS NOT NULL
    AND tanggal < p_date_from;

  SELECT
    COALESCE(SUM(CASE WHEN tipe IN ('masuk', 'transfer_masuk') THEN jumlah ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN tipe IN ('keluar', 'transfer_keluar') THEN jumlah ELSE 0 END), 0)
  INTO v_masuk, v_keluar
  FROM public.kas_ledger
  WHERE status <> 'dibatalkan'
    AND (p_rekening_kas_id IS NULL OR rekening_kas_id = p_rekening_kas_id)
    AND (p_date_from IS NULL OR tanggal >= p_date_from)
    AND (p_date_to IS NULL OR tanggal <= p_date_to);

  v_saldo_pembuka := v_saldo_awal + v_mutasi_sebelum;
  v_saldo_akhir := v_saldo_pembuka + v_masuk - v_keluar;

  RETURN jsonb_build_object(
    'saldo_awal_rekening', v_saldo_awal,
    'saldo_pembuka', v_saldo_pembuka,
    'kas_masuk', v_masuk,
    'kas_keluar', v_keluar,
    'mutasi_bersih', v_masuk - v_keluar,
    'saldo_akhir', v_saldo_akhir
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_kas_summary(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_kas_summary(uuid, date, date) TO authenticated;

-- Transfer payments must carry an external proof/reference.
CREATE OR REPLACE FUNCTION public.require_factory_payment_proof()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF COALESCE(NEW.metode_bayar, '') = 'transfer'
     AND NULLIF(btrim(COALESCE(NEW.nomor_bukti, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Nomor bukti transfer wajib diisi.' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS require_factory_payment_proof ON public.pembayaran_pabrik_batch;
CREATE TRIGGER require_factory_payment_proof
BEFORE INSERT OR UPDATE OF metode_bayar, nomor_bukti ON public.pembayaran_pabrik_batch
FOR EACH ROW EXECUTE FUNCTION public.require_factory_payment_proof();

-- Fee repair must never mutate transactions already represented by an active
-- receipt snapshot.
DO $$
DECLARE
  v_oid oid;
  v_definition text;
  v_old text := 'AND COALESCE(tm.status, ''aktif'') <> ''dibatalkan''';
  v_new text := 'AND COALESCE(tm.status, ''aktif'') <> ''dibatalkan''
      AND NOT EXISTS (
        SELECT 1
        FROM public.pembayaran_mitra_kwitansi_item locked_item
        JOIN public.pembayaran_mitra_kwitansi locked_payment ON locked_payment.id = locked_item.pembayaran_id
        WHERE locked_item.transaksi_mitra_id = tm.id
          AND locked_payment.status <> ''dibatalkan''
      )';
BEGIN
  SELECT p.oid INTO v_oid
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'sync_fee_owner_mitra_period'
    AND p.prokind = 'f'
  LIMIT 1;

  IF v_oid IS NOT NULL THEN
    v_definition := pg_get_functiondef(v_oid);
    IF position(v_new IN v_definition) = 0 THEN
      v_definition := replace(v_definition, v_old, v_new);
      EXECUTE v_definition;
    END IF;
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.recalculate_kwitansi_totals(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_kwitansi_totals_from_item() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_kwitansi_totals_from_summary() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_paid_transaksi_mitra_changes() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.flag_kwitansi_after_system_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.require_factory_payment_proof() FROM PUBLIC, anon, authenticated;
