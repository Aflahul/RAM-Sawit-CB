-- Reconciled legacy advances must remain visible in the same document history
-- as new loans. The archive is documentary only and never mutates cash.

CREATE UNIQUE INDEX IF NOT EXISTS idx_piutang_dokumen_panjar_unique
  ON public.piutang_dokumen (panjar_mitra_id)
  WHERE panjar_mitra_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.archive_reconciled_legacy_panjar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_opening public.hutang_ledger%ROWTYPE;
  v_mitra public.master_mitra%ROWTYPE;
  v_actor uuid;
BEGIN
  IF NEW.hutang_ledger_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_opening
  FROM public.hutang_ledger
  WHERE id = NEW.hutang_ledger_id;

  IF v_opening.id IS NULL
     OR v_opening.legacy_source_table <> 'panjar_mitra_opening_reconciliation' THEN
    RETURN NEW;
  END IF;

  IF EXISTS (SELECT 1 FROM public.piutang_dokumen WHERE panjar_mitra_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_mitra FROM public.master_mitra WHERE id = NEW.mitra_id;
  v_actor := COALESCE(v_opening.created_by, NEW.created_by);
  IF v_actor IS NULL OR v_mitra.id IS NULL THEN
    RAISE EXCEPTION 'Arsip pinjaman lama tidak dapat dibuat karena pengguna atau Mitra sumber tidak ditemukan.';
  END IF;

  INSERT INTO public.piutang_dokumen (
    nomor_bukti, jenis_dokumen, pihak_type, master_mitra_id,
    pihak_nama_snapshot, pihak_kode_snapshot, pihak_kontak_snapshot,
    tanggal_pengajuan, jumlah, tujuan, metode_pelunasan, status,
    diajukan_oleh, disetujui_oleh, disetujui_at,
    nama_penerima, diserahkan_oleh, diserahkan_at,
    hutang_ledger_id, panjar_mitra_id, catatan
  ) VALUES (
    public.next_piutang_document_number('HIS'),
    'panjar_mitra', 'mitra', NEW.mitra_id,
    NULLIF(btrim(concat_ws(' - ', v_mitra.kode, v_mitra.nama)), ''),
    v_mitra.kode, v_mitra.no_hp,
    NEW.tanggal, NEW.jumlah,
    COALESCE(NULLIF(btrim(NEW.keterangan), ''), 'Panjar Mitra lama'),
    'potong_kwitansi_tbs',
    CASE WHEN NEW.status = 'lunas' THEN 'lunas' ELSE 'diserahkan' END,
    v_actor, v_actor, v_opening.created_at,
    NULLIF(btrim(concat_ws(' - ', v_mitra.kode, v_mitra.nama)), ''),
    v_actor, v_opening.created_at,
    v_opening.id, NEW.id,
    'Arsip hasil pencocokan data lama. Tidak membuat mutasi Buku Kas.'
  )
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS archive_reconciled_legacy_panjar ON public.panjar_mitra;
CREATE TRIGGER archive_reconciled_legacy_panjar
AFTER UPDATE OF hutang_ledger_id ON public.panjar_mitra
FOR EACH ROW EXECUTE FUNCTION public.archive_reconciled_legacy_panjar();

-- Fire the archive trigger for reconciliations completed before this migration.
UPDATE public.panjar_mitra panjar
SET hutang_ledger_id = panjar.hutang_ledger_id
FROM public.hutang_ledger opening
WHERE opening.id = panjar.hutang_ledger_id
  AND opening.legacy_source_table = 'panjar_mitra_opening_reconciliation'
  AND NOT EXISTS (
    SELECT 1 FROM public.piutang_dokumen document
    WHERE document.panjar_mitra_id = panjar.id
  );

REVOKE ALL ON FUNCTION public.archive_reconciled_legacy_panjar() FROM PUBLIC, anon, authenticated;
