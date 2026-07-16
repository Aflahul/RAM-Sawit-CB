-- P0 financial control: approval, disbursement proof, and settlement allocation
-- for partner advances and receivables from employees, drivers, and other parties.

CREATE SEQUENCE IF NOT EXISTS public.piutang_document_number_seq;

ALTER TABLE public.hutang_ledger
  DROP CONSTRAINT IF EXISTS hutang_ledger_sumber_check;

ALTER TABLE public.hutang_ledger
  ADD CONSTRAINT hutang_ledger_sumber_check
  CHECK (
    sumber IN (
      'kasbon', 'panjar', 'pupuk', 'lainnya', 'bayar_tunai', 'potong_tbs',
      'potong_settlement', 'potong_gaji', 'potong_upah', 'koreksi', 'reversal',
      'peminjaman', 'uang_jalan', 'gaji', 'operasional', 'pembayaran_mitra',
      'pembayaran_petani', 'pencairan_kas', 'pelunasan_kas'
    )
  );

CREATE TABLE IF NOT EXISTS public.piutang_dokumen (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nomor_bukti text NOT NULL UNIQUE,
  jenis_dokumen text NOT NULL CHECK (
    jenis_dokumen IN (
      'panjar_mitra', 'panjar_petani', 'kasbon_sopir',
      'kasbon_karyawan', 'piutang_lainnya'
    )
  ),
  pihak_type text NOT NULL CHECK (
    pihak_type IN ('petani', 'mitra', 'sopir', 'karyawan', 'lainnya')
  ),
  petani_id uuid REFERENCES public.petani(id),
  master_mitra_id uuid REFERENCES public.master_mitra(id),
  sopir_id uuid REFERENCES public.sopir(id),
  pihak_nama_manual text,
  pihak_nama_snapshot text NOT NULL,
  pihak_kode_snapshot text,
  pihak_kontak_snapshot text,
  tanggal_pengajuan date NOT NULL,
  tanggal_jatuh_tempo date,
  jumlah numeric(15,2) NOT NULL CHECK (jumlah > 0),
  tujuan text NOT NULL,
  metode_pelunasan text NOT NULL CHECK (
    metode_pelunasan IN ('potong_kwitansi_tbs', 'potong_gaji', 'potong_upah', 'tunai_transfer')
  ),
  status text NOT NULL DEFAULT 'menunggu_persetujuan' CHECK (
    status IN (
      'menunggu_persetujuan', 'disetujui', 'ditolak', 'diserahkan',
      'lunas', 'dibatalkan'
    )
  ),
  diajukan_oleh uuid NOT NULL REFERENCES public.users(id),
  disetujui_oleh uuid REFERENCES public.users(id),
  disetujui_at timestamptz,
  alasan_penolakan text,
  rekening_kas_id uuid REFERENCES public.rekening_kas(id),
  metode_penyerahan text CHECK (metode_penyerahan IN ('tunai', 'transfer')),
  nama_penerima text,
  nomor_identitas_penerima text,
  diserahkan_oleh uuid REFERENCES public.users(id),
  diserahkan_at timestamptz,
  hutang_ledger_id uuid REFERENCES public.hutang_ledger(id),
  kas_ledger_id uuid REFERENCES public.kas_ledger(id),
  panjar_mitra_id uuid REFERENCES public.panjar_mitra(id),
  bukti_tanda_tangan_url text,
  catatan text,
  alasan_batal text,
  dibatalkan_oleh uuid REFERENCES public.users(id),
  dibatalkan_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT piutang_dokumen_party_check CHECK (
    (pihak_type = 'petani' AND petani_id IS NOT NULL AND master_mitra_id IS NULL AND sopir_id IS NULL)
    OR (pihak_type = 'mitra' AND master_mitra_id IS NOT NULL AND petani_id IS NULL AND sopir_id IS NULL)
    OR (pihak_type = 'sopir' AND sopir_id IS NOT NULL AND petani_id IS NULL AND master_mitra_id IS NULL)
    OR (pihak_type IN ('karyawan', 'lainnya') AND NULLIF(btrim(COALESCE(pihak_nama_manual, '')), '') IS NOT NULL
        AND petani_id IS NULL AND master_mitra_id IS NULL AND sopir_id IS NULL)
  )
);

CREATE TABLE IF NOT EXISTS public.piutang_pelunasan (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  piutang_dokumen_id uuid NOT NULL REFERENCES public.piutang_dokumen(id),
  tanggal date NOT NULL,
  jumlah numeric(15,2) NOT NULL CHECK (jumlah > 0),
  metode text NOT NULL CHECK (metode IN ('tunai', 'transfer', 'potong_gaji', 'potong_upah')),
  hutang_ledger_id uuid NOT NULL REFERENCES public.hutang_ledger(id),
  kas_ledger_id uuid REFERENCES public.kas_ledger(id),
  nomor_bukti text NOT NULL UNIQUE,
  keterangan text,
  created_by uuid NOT NULL REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'aktif' CHECK (status IN ('aktif', 'dibatalkan'))
);

CREATE INDEX IF NOT EXISTS idx_piutang_dokumen_status_date
  ON public.piutang_dokumen (status, tanggal_pengajuan DESC);
CREATE INDEX IF NOT EXISTS idx_piutang_dokumen_party
  ON public.piutang_dokumen (pihak_type, master_mitra_id, sopir_id, petani_id);
CREATE INDEX IF NOT EXISTS idx_piutang_pelunasan_document
  ON public.piutang_pelunasan (piutang_dokumen_id, status, tanggal DESC);

ALTER TABLE public.piutang_dokumen ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.piutang_pelunasan ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS read_authenticated ON public.piutang_dokumen;
CREATE POLICY read_authenticated ON public.piutang_dokumen
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS read_authenticated ON public.piutang_pelunasan;
CREATE POLICY read_authenticated ON public.piutang_pelunasan
  FOR SELECT TO authenticated USING (true);

REVOKE INSERT, UPDATE, DELETE ON public.piutang_dokumen FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.piutang_pelunasan FROM anon, authenticated;
GRANT SELECT ON public.piutang_dokumen, public.piutang_pelunasan TO authenticated;

CREATE OR REPLACE FUNCTION public.next_piutang_document_number(p_prefix text DEFAULT 'BPU')
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_next bigint;
BEGIN
  v_next := nextval('public.piutang_document_number_seq');
  RETURN upper(COALESCE(NULLIF(btrim(p_prefix), ''), 'BPU'))
    || '-' || to_char(now() AT TIME ZONE 'Asia/Jakarta', 'YYYYMMDD')
    || '-' || lpad(v_next::text, 6, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.create_piutang_request(
  p_pihak_type text,
  p_jumlah numeric,
  p_tujuan text,
  p_metode_pelunasan text,
  p_tanggal date DEFAULT NULL,
  p_tanggal_jatuh_tempo date DEFAULT NULL,
  p_petani_id uuid DEFAULT NULL,
  p_master_mitra_id uuid DEFAULT NULL,
  p_sopir_id uuid DEFAULT NULL,
  p_pihak_nama_manual text DEFAULT NULL,
  p_catatan text DEFAULT NULL
)
RETURNS public.piutang_dokumen
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_role text := public.current_app_role();
  v_row public.piutang_dokumen%ROWTYPE;
  v_name text;
  v_code text;
  v_contact text;
  v_kind text;
  v_expected_method text;
  v_prefix text;
BEGIN
  IF v_actor IS NULL OR v_role NOT IN ('owner', 'super_admin', 'admin_keuangan', 'admin_operasional') THEN
    RAISE EXCEPTION 'Tidak berwenang mengajukan panjar atau kasbon.' USING ERRCODE = '42501';
  END IF;
  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
    RAISE EXCEPTION 'Jumlah harus lebih dari 0.' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(btrim(COALESCE(p_tujuan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Keperluan pemberian uang wajib diisi.' USING ERRCODE = '22023';
  END IF;

  CASE p_pihak_type
    WHEN 'mitra' THEN
      SELECT NULLIF(btrim(concat_ws(' - ', kode, nama)), ''), kode, no_hp
      INTO v_name, v_code, v_contact FROM public.master_mitra WHERE id = p_master_mitra_id AND aktif = true;
      v_kind := 'panjar_mitra'; v_expected_method := 'potong_kwitansi_tbs'; v_prefix := 'BPM';
    WHEN 'petani' THEN
      SELECT nama, NULL, no_hp INTO v_name, v_code, v_contact FROM public.petani WHERE id = p_petani_id AND aktif = true;
      v_kind := 'panjar_petani'; v_expected_method := p_metode_pelunasan; v_prefix := 'BPP';
    WHEN 'sopir' THEN
      SELECT NULLIF(btrim(concat_ws(' - ', nama, plat_nomor)), ''), plat_nomor, no_hp
      INTO v_name, v_code, v_contact FROM public.sopir WHERE id = p_sopir_id AND aktif = true;
      v_kind := 'kasbon_sopir'; v_expected_method := p_metode_pelunasan; v_prefix := 'BKS';
    WHEN 'karyawan' THEN
      v_name := NULLIF(btrim(COALESCE(p_pihak_nama_manual, '')), '');
      v_kind := 'kasbon_karyawan'; v_expected_method := p_metode_pelunasan; v_prefix := 'BKK';
    WHEN 'lainnya' THEN
      v_name := NULLIF(btrim(COALESCE(p_pihak_nama_manual, '')), '');
      v_kind := 'piutang_lainnya'; v_expected_method := 'tunai_transfer'; v_prefix := 'BPL';
    ELSE
      RAISE EXCEPTION 'Jenis penerima tidak valid.' USING ERRCODE = '22023';
  END CASE;

  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Penerima tidak ditemukan atau belum aktif.' USING ERRCODE = '22023';
  END IF;
  IF v_expected_method NOT IN ('potong_kwitansi_tbs', 'potong_gaji', 'potong_upah', 'tunai_transfer') THEN
    RAISE EXCEPTION 'Cara pengembalian tidak sesuai dengan jenis penerima.' USING ERRCODE = '22023';
  END IF;
  IF p_pihak_type = 'sopir' AND v_expected_method NOT IN ('potong_upah', 'tunai_transfer') THEN
    RAISE EXCEPTION 'Kasbon sopir hanya dapat dipotong dari upah atau dikembalikan tunai/transfer.' USING ERRCODE = '22023';
  END IF;
  IF p_pihak_type = 'karyawan' AND v_expected_method NOT IN ('potong_gaji', 'tunai_transfer') THEN
    RAISE EXCEPTION 'Kasbon karyawan hanya dapat dipotong dari gaji atau dikembalikan tunai/transfer.' USING ERRCODE = '22023';
  END IF;
  IF p_tanggal_jatuh_tempo IS NOT NULL
     AND p_tanggal_jatuh_tempo < COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date) THEN
    RAISE EXCEPTION 'Tanggal target pengembalian tidak boleh sebelum tanggal pengajuan.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.piutang_dokumen (
    nomor_bukti, jenis_dokumen, pihak_type, petani_id, master_mitra_id, sopir_id,
    pihak_nama_manual, pihak_nama_snapshot, pihak_kode_snapshot, pihak_kontak_snapshot,
    tanggal_pengajuan, tanggal_jatuh_tempo, jumlah, tujuan, metode_pelunasan,
    status, diajukan_oleh, disetujui_oleh, disetujui_at, catatan
  ) VALUES (
    public.next_piutang_document_number(v_prefix), v_kind, p_pihak_type,
    CASE WHEN p_pihak_type = 'petani' THEN p_petani_id END,
    CASE WHEN p_pihak_type = 'mitra' THEN p_master_mitra_id END,
    CASE WHEN p_pihak_type = 'sopir' THEN p_sopir_id END,
    CASE WHEN p_pihak_type IN ('karyawan', 'lainnya') THEN v_name END,
    v_name, v_code, v_contact,
    COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date), p_tanggal_jatuh_tempo,
    round(p_jumlah, 2), btrim(p_tujuan), v_expected_method,
    CASE WHEN v_role IN ('owner', 'super_admin') THEN 'disetujui' ELSE 'menunggu_persetujuan' END,
    v_actor,
    CASE WHEN v_role IN ('owner', 'super_admin') THEN v_actor END,
    CASE WHEN v_role IN ('owner', 'super_admin') THEN now() END,
    NULLIF(btrim(COALESCE(p_catatan, '')), '')
  ) RETURNING * INTO v_row;

  PERFORM public.write_audit_log(
    'piutang_dokumen', v_row.id, 'create_request', NULL, to_jsonb(v_row),
    'Pengajuan ' || replace(v_kind, '_', ' '),
    CASE WHEN v_role IN ('owner', 'super_admin') THEN v_actor END
  );
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_piutang_request(
  p_document_id uuid,
  p_action text,
  p_catatan text DEFAULT NULL
)
RETURNS public.piutang_dokumen
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.piutang_dokumen%ROWTYPE;
  v_after public.piutang_dokumen%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR public.current_app_role() NOT IN ('owner', 'super_admin') THEN
    RAISE EXCEPTION 'Hanya Owner atau Super Admin yang dapat memberi persetujuan.' USING ERRCODE = '42501';
  END IF;
  IF p_action NOT IN ('setujui', 'tolak') THEN
    RAISE EXCEPTION 'Pilihan persetujuan tidak valid.' USING ERRCODE = '22023';
  END IF;
  IF p_action = 'tolak' AND NULLIF(btrim(COALESCE(p_catatan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan penolakan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before FROM public.piutang_dokumen WHERE id = p_document_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'Pengajuan tidak ditemukan.' USING ERRCODE = 'P0002'; END IF;
  IF v_before.status <> 'menunggu_persetujuan' THEN
    RAISE EXCEPTION 'Pengajuan ini sudah diproses.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.piutang_dokumen
  SET status = CASE WHEN p_action = 'setujui' THEN 'disetujui' ELSE 'ditolak' END,
      disetujui_oleh = CASE WHEN p_action = 'setujui' THEN v_actor END,
      disetujui_at = CASE WHEN p_action = 'setujui' THEN now() END,
      alasan_penolakan = CASE WHEN p_action = 'tolak' THEN btrim(p_catatan) END,
      updated_at = now()
  WHERE id = v_before.id RETURNING * INTO v_after;

  PERFORM public.write_audit_log(
    'piutang_dokumen', v_after.id, p_action, to_jsonb(v_before), to_jsonb(v_after),
    NULLIF(btrim(COALESCE(p_catatan, '')), ''), v_actor
  );
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.disburse_piutang_document(
  p_document_id uuid,
  p_metode_penyerahan text,
  p_nama_penerima text,
  p_rekening_kas_id uuid DEFAULT NULL,
  p_nomor_identitas text DEFAULT NULL
)
RETURNS public.piutang_dokumen
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.piutang_dokumen%ROWTYPE;
  v_after public.piutang_dokumen%ROWTYPE;
  v_ledger public.hutang_ledger%ROWTYPE;
  v_panjar public.panjar_mitra%ROWTYPE;
  v_source text;
BEGIN
  IF v_actor IS NULL OR public.current_app_role() NOT IN ('owner', 'super_admin', 'admin_keuangan', 'admin_operasional') THEN
    RAISE EXCEPTION 'Tidak berwenang menyerahkan panjar atau kasbon.' USING ERRCODE = '42501';
  END IF;
  IF p_metode_penyerahan NOT IN ('tunai', 'transfer') THEN
    RAISE EXCEPTION 'Metode penyerahan harus tunai atau transfer.' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(btrim(COALESCE(p_nama_penerima, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Nama penerima uang wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before FROM public.piutang_dokumen WHERE id = p_document_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'Dokumen tidak ditemukan.' USING ERRCODE = 'P0002'; END IF;
  IF v_before.status <> 'disetujui' THEN
    RAISE EXCEPTION 'Uang hanya dapat diserahkan setelah pengajuan disetujui.' USING ERRCODE = '22023';
  END IF;

  IF v_before.jenis_dokumen = 'panjar_mitra' THEN
    SELECT * INTO v_panjar FROM public.create_panjar_mitra_kas(
      v_before.master_mitra_id, v_before.tanggal_pengajuan, v_before.jumlah,
      v_before.tujuan, p_rekening_kas_id
    );
    SELECT * INTO v_ledger FROM public.hutang_ledger WHERE id = v_panjar.hutang_ledger_id;
  ELSE
    v_source := CASE
      WHEN v_before.jenis_dokumen IN ('kasbon_sopir', 'kasbon_karyawan') THEN 'kasbon'
      WHEN v_before.jenis_dokumen = 'panjar_petani' THEN 'panjar'
      ELSE 'peminjaman'
    END;
    SELECT * INTO v_ledger FROM public.create_hutang_pihak(
      v_before.pihak_type, 'debit', v_source, v_before.jumlah, v_before.tanggal_pengajuan,
      v_before.petani_id, v_before.master_mitra_id, v_before.sopir_id,
      v_before.pihak_nama_manual, v_before.tujuan, p_rekening_kas_id, true,
      'piutang_dokumen', v_before.id
    );
  END IF;

  UPDATE public.piutang_dokumen
  SET status = 'diserahkan', rekening_kas_id = v_ledger.rekening_kas_id,
      metode_penyerahan = p_metode_penyerahan,
      nama_penerima = btrim(p_nama_penerima),
      nomor_identitas_penerima = NULLIF(btrim(COALESCE(p_nomor_identitas, '')), ''),
      diserahkan_oleh = v_actor, diserahkan_at = now(),
      hutang_ledger_id = v_ledger.id, kas_ledger_id = v_ledger.kas_ledger_id,
      panjar_mitra_id = v_panjar.id, updated_at = now()
  WHERE id = v_before.id RETURNING * INTO v_after;

  PERFORM public.write_audit_log(
    'piutang_dokumen', v_after.id, 'disburse', to_jsonb(v_before), to_jsonb(v_after),
    'Uang diserahkan melalui ' || p_metode_penyerahan, NULL
  );
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_piutang_repayment(
  p_document_id uuid,
  p_jumlah numeric,
  p_metode text,
  p_tanggal date DEFAULT NULL,
  p_keterangan text DEFAULT NULL,
  p_rekening_kas_id uuid DEFAULT NULL
)
RETURNS public.piutang_pelunasan
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_doc public.piutang_dokumen%ROWTYPE;
  v_ledger public.hutang_ledger%ROWTYPE;
  v_payment public.piutang_pelunasan%ROWTYPE;
  v_paid numeric(15,2);
  v_payment_id uuid := gen_random_uuid();
  v_source text;
  v_cash boolean;
BEGIN
  IF v_actor IS NULL OR public.current_app_role() NOT IN ('owner', 'super_admin', 'admin_keuangan', 'admin_operasional') THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat pengembalian.' USING ERRCODE = '42501';
  END IF;
  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN RAISE EXCEPTION 'Jumlah pengembalian harus lebih dari 0.' USING ERRCODE = '22023'; END IF;
  IF p_metode NOT IN ('tunai', 'transfer', 'potong_gaji', 'potong_upah') THEN
    RAISE EXCEPTION 'Metode pengembalian tidak valid.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_doc FROM public.piutang_dokumen WHERE id = p_document_id FOR UPDATE;
  IF v_doc.id IS NULL THEN RAISE EXCEPTION 'Dokumen tidak ditemukan.' USING ERRCODE = 'P0002'; END IF;
  IF v_doc.jenis_dokumen = 'panjar_mitra' THEN
    RAISE EXCEPTION 'Panjar mitra dipotong melalui Kwitansi Pembayaran TBS.' USING ERRCODE = '22023';
  END IF;
  IF v_doc.status NOT IN ('diserahkan') THEN
    RAISE EXCEPTION 'Hanya uang yang sudah diserahkan yang dapat dikembalikan.' USING ERRCODE = '22023';
  END IF;
  SELECT COALESCE(sum(jumlah), 0) INTO v_paid FROM public.piutang_pelunasan
    WHERE piutang_dokumen_id = v_doc.id AND status = 'aktif';
  IF p_jumlah > v_doc.jumlah - v_paid THEN
    RAISE EXCEPTION 'Jumlah pengembalian melebihi sisa piutang.' USING ERRCODE = '22023';
  END IF;
  IF p_metode = 'potong_gaji' AND v_doc.metode_pelunasan <> 'potong_gaji' THEN
    RAISE EXCEPTION 'Dokumen ini tidak disepakati untuk dipotong dari gaji.' USING ERRCODE = '22023';
  END IF;
  IF p_metode = 'potong_upah' AND v_doc.metode_pelunasan <> 'potong_upah' THEN
    RAISE EXCEPTION 'Dokumen ini tidak disepakati untuk dipotong dari upah.' USING ERRCODE = '22023';
  END IF;

  v_cash := p_metode IN ('tunai', 'transfer');
  v_source := CASE WHEN p_metode = 'potong_gaji' THEN 'potong_gaji'
                   WHEN p_metode = 'potong_upah' THEN 'potong_upah'
                   ELSE 'bayar_tunai' END;

  SELECT * INTO v_ledger FROM public.create_hutang_pihak(
    v_doc.pihak_type, 'kredit', v_source, p_jumlah,
    COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    v_doc.petani_id, v_doc.master_mitra_id, v_doc.sopir_id, v_doc.pihak_nama_manual,
    COALESCE(NULLIF(btrim(COALESCE(p_keterangan, '')), ''), 'Pengembalian ' || v_doc.nomor_bukti),
    p_rekening_kas_id, v_cash, 'piutang_pelunasan', v_payment_id
  );

  INSERT INTO public.piutang_pelunasan (
    id, piutang_dokumen_id, tanggal, jumlah, metode, hutang_ledger_id,
    kas_ledger_id, nomor_bukti, keterangan, created_by
  ) VALUES (
    v_payment_id, v_doc.id, COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    round(p_jumlah, 2), p_metode, v_ledger.id, v_ledger.kas_ledger_id,
    public.next_piutang_document_number('KPU'),
    NULLIF(btrim(COALESCE(p_keterangan, '')), ''), v_actor
  ) RETURNING * INTO v_payment;

  IF v_paid + p_jumlah >= v_doc.jumlah THEN
    UPDATE public.piutang_dokumen SET status = 'lunas', updated_at = now() WHERE id = v_doc.id;
  END IF;
  PERFORM public.write_audit_log('piutang_dokumen', v_doc.id, 'repayment', to_jsonb(v_doc), to_jsonb(v_payment), p_keterangan, NULL);
  RETURN v_payment;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_piutang_document(p_document_id uuid, p_alasan text)
RETURNS public.piutang_dokumen
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.piutang_dokumen%ROWTYPE;
  v_after public.piutang_dokumen%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR public.current_app_role() NOT IN ('owner', 'super_admin') THEN
    RAISE EXCEPTION 'Hanya Owner atau Super Admin yang dapat membatalkan.' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(btrim(COALESCE(p_alasan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_before FROM public.piutang_dokumen WHERE id = p_document_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'Dokumen tidak ditemukan.' USING ERRCODE = 'P0002'; END IF;
  IF v_before.status IN ('lunas', 'ditolak', 'dibatalkan') THEN
    RAISE EXCEPTION 'Dokumen ini tidak dapat dibatalkan.' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.piutang_pelunasan WHERE piutang_dokumen_id = v_before.id AND status = 'aktif') THEN
    RAISE EXCEPTION 'Batalkan pengembalian yang terkait terlebih dahulu.' USING ERRCODE = '22023';
  END IF;

  IF v_before.status = 'diserahkan' THEN
    IF v_before.panjar_mitra_id IS NOT NULL THEN
      PERFORM public.cancel_panjar_mitra_kas(v_before.panjar_mitra_id, p_alasan);
    ELSIF v_before.hutang_ledger_id IS NOT NULL THEN
      PERFORM public.cancel_hutang_ledger(v_before.hutang_ledger_id, p_alasan);
    END IF;
  END IF;

  UPDATE public.piutang_dokumen
  SET status = 'dibatalkan', alasan_batal = btrim(p_alasan),
      dibatalkan_oleh = v_actor, dibatalkan_at = now(), updated_at = now()
  WHERE id = v_before.id RETURNING * INTO v_after;
  PERFORM public.write_audit_log('piutang_dokumen', v_after.id, 'cancel', to_jsonb(v_before), to_jsonb(v_after), p_alasan, v_actor);
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_piutang_document_from_panjar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'lunas' AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE public.piutang_dokumen SET status = 'lunas', updated_at = now()
    WHERE panjar_mitra_id = NEW.id AND status = 'diserahkan';
  ELSIF NEW.status = 'dibatalkan' AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE public.piutang_dokumen SET status = 'dibatalkan', updated_at = now()
    WHERE panjar_mitra_id = NEW.id AND status <> 'dibatalkan';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_piutang_document_from_panjar ON public.panjar_mitra;
CREATE TRIGGER sync_piutang_document_from_panjar
AFTER UPDATE OF status ON public.panjar_mitra
FOR EACH ROW EXECUTE FUNCTION public.sync_piutang_document_from_panjar();

REVOKE ALL ON FUNCTION public.next_piutang_document_number(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_piutang_request(text, numeric, text, text, date, date, uuid, uuid, uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.review_piutang_request(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.disburse_piutang_document(uuid, text, text, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_piutang_repayment(uuid, numeric, text, date, text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_piutang_document(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sync_piutang_document_from_panjar() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_piutang_request(text, numeric, text, text, date, date, uuid, uuid, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_piutang_request(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disburse_piutang_document(uuid, text, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_piutang_repayment(uuid, numeric, text, date, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_piutang_document(uuid, text) TO authenticated;
