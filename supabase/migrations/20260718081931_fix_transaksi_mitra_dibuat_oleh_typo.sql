 IF NOT EXISTS btree_gist WITH SCHEMA extensions;



SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."archive_reconciled_legacy_panjar"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."archive_reconciled_legacy_panjar"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."transaksi_mitra" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tanggal" "date" NOT NULL,
    "sopir_id" "uuid",
    "mitra_id" "uuid",
    "plat_nomor" character varying(20),
    "tonase" numeric(10,2) NOT NULL,
    "harga_harian" numeric(10,2) NOT NULL,
    "total_kotor" numeric(15,2) NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "sopir_default_id" "uuid",
    "sopir_default_nama" character varying(100),
    "sopir_aktual_id" "uuid",
    "sopir_aktual_nama" character varying(100),
    "sopir_aktual_no_hp" character varying(30),
    "sopir_aktual_source" "text" DEFAULT 'master'::"text",
    "sopir_diganti_dari_default" boolean DEFAULT false,
    "catatan_sopir" "text",
    "status" "text" DEFAULT 'aktif'::"text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "updated_by" "uuid",
    "alasan_edit" "text",
    "dibatalkan_at" timestamp with time zone,
    "dibatalkan_by" "uuid",
    "alasan_batal" "text",
    "harga_pabrik_per_kg" numeric(12,2),
    "fee_owner_per_kg" numeric(12,2),
    "harga_bersih_per_kg" numeric(12,2),
    "total_fee_owner" numeric(15,2),
    "total_nilai_bersih" numeric(15,2),
    "fee_owner_history_id" "uuid",
    "pembayaran_pabrik_batch_id" "uuid",
    "pembayaran_pabrik_item_id" "uuid",
    "pembayaran_pabrik_status" "text" DEFAULT 'belum_dibayar'::"text" NOT NULL,
    "pembayaran_pabrik_at" timestamp with time zone,
    "berat_netto_pabrik_kg" numeric(12,2),
    "potongan_pabrik_kg" numeric(12,2) DEFAULT 0 NOT NULL,
    "berat_dibayar_kg" numeric(12,2),
    "pakai_sewa_armada_bl" boolean DEFAULT false NOT NULL,
    "biaya_sewa_armada_per_kg" numeric(10,2),
    "biaya_sewa_armada_total" numeric(15,2) DEFAULT 0 NOT NULL,
    "tarif_sewa_angkut_per_kg_snapshot" numeric(12,2) DEFAULT 0,
    "nominal_perongkosan_snapshot" numeric(15,2) DEFAULT 0,
    "biaya_sewa_armada_kotor" numeric(15,2) DEFAULT 0,
    "upah_sopir_cb_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "uang_jalan_sopir_cb_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_biaya_sopir_cb_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "tagihan_sopir_ledger_id" "uuid",
    "tagihan_sopir_bayar_ledger_id" "uuid",
    "biaya_sopir_operasional_id" "uuid",
    "biaya_sopir_dibayar_at" timestamp with time zone,
    "dana_operasional_trip_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "menggunakan_armada_cb_snapshot" boolean DEFAULT false NOT NULL,
    "kenakan_sewa_armada_cb" boolean DEFAULT true NOT NULL,
    "catat_dana_operasional_trip" boolean DEFAULT true NOT NULL,
    "alasan_tanpa_sewa_armada_cb" "text",
    "alasan_tanpa_dana_operasional_trip" "text",
    "armada_cb_perlu_review" boolean DEFAULT false NOT NULL,
    "alasan_review_armada_cb" "text",
    CONSTRAINT "chk_biaya_sewa_armada_tidak_negatif" CHECK (("biaya_sewa_armada_total" >= (0)::numeric)),
    CONSTRAINT "chk_potongan_tidak_melebihi_netto" CHECK ((("berat_netto_pabrik_kg" IS NULL) OR ("potongan_pabrik_kg" <= "berat_netto_pabrik_kg"))),
    CONSTRAINT "chk_potongan_tidak_negatif" CHECK (("potongan_pabrik_kg" >= (0)::numeric)),
    CONSTRAINT "transaksi_mitra_biaya_sopir_nonnegative" CHECK ((("upah_sopir_cb_snapshot" >= (0)::numeric) AND ("uang_jalan_sopir_cb_snapshot" >= (0)::numeric) AND ("total_biaya_sopir_cb_snapshot" >= (0)::numeric))),
    CONSTRAINT "transaksi_mitra_dana_operasional_trip_nonnegative" CHECK (("dana_operasional_trip_snapshot" >= (0)::numeric)),
    CONSTRAINT "transaksi_mitra_dana_requires_armada_cb" CHECK (((NOT "catat_dana_operasional_trip") OR "menggunakan_armada_cb_snapshot")),
    CONSTRAINT "transaksi_mitra_pembayaran_pabrik_status_check" CHECK (("pembayaran_pabrik_status" = ANY (ARRAY['belum_dibayar'::"text", 'dibayar'::"text", 'perlu_review'::"text", 'dibatalkan'::"text"]))),
    CONSTRAINT "transaksi_mitra_reason_without_rent" CHECK (((NOT "menggunakan_armada_cb_snapshot") OR "kenakan_sewa_armada_cb" OR (NULLIF("btrim"(COALESCE("alasan_tanpa_sewa_armada_cb", ''::"text")), ''::"text") IS NOT NULL))),
    CONSTRAINT "transaksi_mitra_reason_without_trip_fund" CHECK (((NOT "menggunakan_armada_cb_snapshot") OR "catat_dana_operasional_trip" OR (NULLIF("btrim"(COALESCE("alasan_tanpa_dana_operasional_trip", ''::"text")), ''::"text") IS NOT NULL))),
    CONSTRAINT "transaksi_mitra_sewa_requires_armada_cb" CHECK (((NOT "kenakan_sewa_armada_cb") OR "menggunakan_armada_cb_snapshot")),
    CONSTRAINT "transaksi_mitra_sopir_aktual_source_check" CHECK (("sopir_aktual_source" = ANY (ARRAY['master'::"text", 'manual'::"text"]))),
    CONSTRAINT "transaksi_mitra_status_check" CHECK (("status" = ANY (ARRAY['aktif'::"text", 'dibatalkan'::"text"])))
);


ALTER TABLE "public"."transaksi_mitra" OWNER TO "postgres";


COMMENT ON COLUMN "public"."transaksi_mitra"."tarif_sewa_angkut_per_kg_snapshot" IS 'Snapshot tarif_sewa_angkut_per_kg saat transaksi dibuat';



COMMENT ON COLUMN "public"."transaksi_mitra"."nominal_perongkosan_snapshot" IS 'Field legacy. Tidak digunakan sebagai pengurang sewa Armada CB; uang jalan disimpan di uang_jalan_sopir_cb_snapshot.';



COMMENT ON COLUMN "public"."transaksi_mitra"."biaya_sewa_armada_kotor" IS 'berat_netto_pabrik_kg * tarif_sewa_angkut_per_kg_snapshot';



COMMENT ON COLUMN "public"."transaksi_mitra"."upah_sopir_cb_snapshot" IS 'Field legacy. Tidak dipakai untuk transaksi baru karena bagian bersih sopir tidak diketahui.';



COMMENT ON COLUMN "public"."transaksi_mitra"."uang_jalan_sopir_cb_snapshot" IS 'Field legacy. Tidak dipakai untuk transaksi baru karena dana satu kali jalan tidak dipecah.';



COMMENT ON COLUMN "public"."transaksi_mitra"."total_biaya_sopir_cb_snapshot" IS 'Field kompatibilitas. Untuk transaksi baru nilainya sama dengan dana_operasional_trip_snapshot.';



COMMENT ON COLUMN "public"."transaksi_mitra"."dana_operasional_trip_snapshot" IS 'Snapshot dana operasional satu kali jalan saat pengiriman dibuat. Tidak dipecah menjadi gaji, solar, atau makan.';



COMMENT ON COLUMN "public"."transaksi_mitra"."menggunakan_armada_cb_snapshot" IS 'Snapshot fakta bahwa pengiriman memakai Armada CB. Menjadi dasar hitungan trip dan muatan armada.';



COMMENT ON COLUMN "public"."transaksi_mitra"."kenakan_sewa_armada_cb" IS 'Jika true, sewa Armada CB dipotong dari hak mitra dan menjadi pendapatan CB.';



COMMENT ON COLUMN "public"."transaksi_mitra"."catat_dana_operasional_trip" IS 'Jika true, pengiriman membuat tagihan Dana Operasional Trip.';



COMMENT ON COLUMN "public"."transaksi_mitra"."armada_cb_perlu_review" IS 'Penanda data lama/ambigu yang perlu ditetapkan perlakuan Armada CB-nya.';



CREATE OR REPLACE FUNCTION "public"."bayar_tagihan_sopir_cb"("p_transaksi_mitra_id" "uuid", "p_tanggal_bayar" "date" DEFAULT NULL::"date", "p_rekening_kas_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."transaksi_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_transaksi public.transaksi_mitra%ROWTYPE;
  v_tagihan public.hutang_ledger%ROWTYPE;
  v_pelunasan public.hutang_ledger%ROWTYPE;
  v_biaya public.biaya_operasional%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
  v_rekening_id uuid := p_rekening_kas_id;
  v_tanggal date := COALESCE(p_tanggal_bayar, (now() AT TIME ZONE 'Asia/Jakarta')::date);
  v_nominal numeric(15,2) := 0;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang membayar dana operasional trip.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_transaksi
  FROM public.transaksi_mitra
  WHERE id = p_transaksi_mitra_id
  FOR UPDATE;

  IF v_transaksi.id IS NULL THEN
    RAISE EXCEPTION 'Pengiriman tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF v_transaksi.status <> 'aktif' THEN
    RAISE EXCEPTION 'Pengiriman sudah dibatalkan.' USING ERRCODE = '22023';
  END IF;
  IF NOT v_transaksi.pakai_sewa_armada_bl THEN
    RAISE EXCEPTION 'Pengiriman ini bukan Armada CB.' USING ERRCODE = '22023';
  END IF;

  v_nominal := GREATEST(COALESCE(
    NULLIF(v_transaksi.dana_operasional_trip_snapshot, 0),
    v_transaksi.total_biaya_sopir_cb_snapshot,
    0
  ), 0);
  IF v_nominal <= 0 THEN
    RAISE EXCEPTION 'Dana operasional trip belum diatur untuk mitra ini.' USING ERRCODE = '22023';
  END IF;
  IF v_transaksi.biaya_sopir_dibayar_at IS NOT NULL
     OR v_transaksi.tagihan_sopir_bayar_ledger_id IS NOT NULL THEN
    RAISE EXCEPTION 'Dana operasional trip ini sudah dibayar.' USING ERRCODE = '23505';
  END IF;

  SELECT * INTO v_tagihan
  FROM public.hutang_ledger
  WHERE id = v_transaksi.tagihan_sopir_ledger_id
  FOR UPDATE;

  IF v_tagihan.id IS NULL OR v_tagihan.status <> 'aktif' THEN
    RAISE EXCEPTION 'Tagihan dana operasional trip tidak ditemukan atau sudah tidak aktif.' USING ERRCODE = 'P0002';
  END IF;

  IF v_rekening_id IS NULL THEN
    v_rekening_id := public.get_default_rekening_kas_id();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.rekening_kas WHERE id = v_rekening_id AND aktif = true) THEN
    RAISE EXCEPTION 'Rekening kas tidak ditemukan atau tidak aktif.' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.biaya_operasional (
    tanggal, kategori, jumlah, keterangan, tipe_biaya, status,
    rekening_kas_id, armada_sopir_id, transaksi_mitra_id, created_by
  ) VALUES (
    v_tanggal,
    'dana_operasional_trip',
    v_nominal,
    format(
      'Dana operasional trip %s, Armada CB %s, pengiriman %s',
      COALESCE(v_transaksi.sopir_aktual_nama, v_transaksi.sopir_default_nama, '-'),
      COALESCE(v_transaksi.plat_nomor, '-'),
      v_transaksi.tanggal
    ),
    'perusahaan_murni',
    'aktif',
    v_rekening_id,
    v_transaksi.sopir_id,
    v_transaksi.id,
    v_actor
  ) RETURNING * INTO v_biaya;

  INSERT INTO public.kas_ledger (
    rekening_kas_id, tanggal, tipe, sumber, jumlah, biaya_operasional_id,
    source_table, source_id, idempotency_key, keterangan, created_by
  ) VALUES (
    v_rekening_id,
    v_tanggal,
    'keluar',
    'biaya_operasional',
    v_nominal,
    v_biaya.id,
    'transaksi_mitra',
    v_transaksi.id,
    'tagihan_sopir_cb:' || v_transaksi.id::text,
    v_biaya.keterangan,
    v_actor
  ) RETURNING * INTO v_kas;

  UPDATE public.biaya_operasional
  SET kas_ledger_id = v_kas.id
  WHERE id = v_biaya.id
  RETURNING * INTO v_biaya;

  INSERT INTO public.hutang_ledger (
    pihak_type, petani_id, mitra_id, master_mitra_id, sopir_id, pihak_nama_manual,
    tanggal, tipe, sumber, jumlah, legacy_source_table, legacy_source_id,
    keterangan, rekening_kas_id, kas_ledger_id, created_by
  ) VALUES (
    v_tagihan.pihak_type,
    v_tagihan.petani_id,
    v_tagihan.mitra_id,
    v_tagihan.master_mitra_id,
    v_tagihan.sopir_id,
    v_tagihan.pihak_nama_manual,
    v_tanggal,
    'kredit',
    'bayar_tunai',
    v_tagihan.jumlah,
    'pembayaran_tagihan_sopir_cb',
    v_tagihan.id,
    format('Pembayaran dana operasional trip Armada CB %s', COALESCE(v_transaksi.plat_nomor, '-')),
    v_rekening_id,
    v_kas.id,
    v_actor
  ) RETURNING * INTO v_pelunasan;

  UPDATE public.kas_ledger SET hutang_ledger_id = v_pelunasan.id WHERE id = v_kas.id;

  UPDATE public.transaksi_mitra
  SET tagihan_sopir_bayar_ledger_id = v_pelunasan.id,
      biaya_sopir_operasional_id = v_biaya.id,
      biaya_sopir_dibayar_at = now()
  WHERE id = v_transaksi.id
  RETURNING * INTO v_transaksi;

  RETURN v_transaksi;
END;
$$;


ALTER FUNCTION "public"."bayar_tagihan_sopir_cb"("p_transaksi_mitra_id" "uuid", "p_tanggal_bayar" "date", "p_rekening_kas_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."biaya_operasional" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tanggal" "date" NOT NULL,
    "kategori" "text" NOT NULL,
    "jumlah" numeric(15,2) NOT NULL,
    "keterangan" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "tipe_biaya" "text" DEFAULT 'perusahaan_murni'::"text",
    "pengiriman_id" "uuid",
    "settlement_id" "uuid",
    "dibebankan_ke_mitra" boolean DEFAULT false,
    "jumlah_dibebankan_ke_mitra" numeric(15,2) DEFAULT 0,
    "status" "text" DEFAULT 'aktif'::"text",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "alasan_batal" "text",
    "dibatalkan_at" timestamp with time zone,
    "dibatalkan_by" "uuid",
    "rekening_kas_id" "uuid",
    "kas_ledger_id" "uuid",
    "armada_sopir_id" "uuid",
    "transaksi_mitra_id" "uuid",
    CONSTRAINT "biaya_operasional_kategori_check" CHECK (("kategori" = ANY (ARRAY['solar'::"text", 'gaji_sopir'::"text", 'dana_operasional_trip'::"text", 'kuli'::"text", 'retribusi'::"text", 'perawatan'::"text", 'lainnya'::"text"]))),
    CONSTRAINT "biaya_operasional_status_check" CHECK (("status" = ANY (ARRAY['aktif'::"text", 'dibatalkan'::"text", 'reversal'::"text"]))),
    CONSTRAINT "biaya_operasional_tipe_check" CHECK (("tipe_biaya" = ANY (ARRAY['perusahaan_murni'::"text", 'bantuan_mitra'::"text"])))
);


ALTER TABLE "public"."biaya_operasional" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_biaya_operasional_kas"("p_biaya_id" "uuid", "p_alasan" "text") RETURNS "public"."biaya_operasional"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.biaya_operasional%ROWTYPE;
  v_after public.biaya_operasional%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Tidak berwenang membatalkan biaya operasional.' USING ERRCODE = '42501';
  END IF;

  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before
  FROM public.biaya_operasional
  WHERE id = p_biaya_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Biaya operasional tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_before.status, 'aktif') <> 'aktif' THEN
    RAISE EXCEPTION 'Biaya operasional sudah tidak aktif.' USING ERRCODE = '22023';
  END IF;

  IF v_before.kas_ledger_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.kas_ledger
       WHERE reversal_of_id = v_before.kas_ledger_id
         AND status = 'aktif'
     ) THEN
    INSERT INTO public.kas_ledger (
      rekening_kas_id, tanggal, tipe, sumber, jumlah,
      biaya_operasional_id, source_table, source_id, reversal_of_id,
      idempotency_key, keterangan, created_by
    ) VALUES (
      COALESCE(v_before.rekening_kas_id, public.get_default_rekening_kas_id()),
      v_before.tanggal, 'masuk', 'reversal', v_before.jumlah,
      v_before.id, 'biaya_operasional', v_before.id, v_before.kas_ledger_id,
      'biaya_operasional:' || v_before.id::text || ':reversal',
      'Reversal biaya: ' || btrim(p_alasan), v_actor
    );
  END IF;

  UPDATE public.biaya_operasional
  SET status = 'dibatalkan',
      alasan_batal = btrim(p_alasan),
      dibatalkan_at = now(),
      dibatalkan_by = v_actor
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."cancel_biaya_operasional_kas"("p_biaya_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hutang_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pihak_type" "text" NOT NULL,
    "petani_id" "uuid",
    "mitra_id" "uuid",
    "tanggal" "date" NOT NULL,
    "tipe" "text" NOT NULL,
    "sumber" "text" NOT NULL,
    "jumlah" numeric(15,2) NOT NULL,
    "transaksi_beli_id" "uuid",
    "settlement_id" "uuid",
    "legacy_source_table" "text",
    "legacy_source_id" "uuid",
    "keterangan" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "master_mitra_id" "uuid",
    "sopir_id" "uuid",
    "pihak_nama_manual" "text",
    "pihak_ref_id" "uuid",
    "rekening_kas_id" "uuid",
    "kas_ledger_id" "uuid",
    "status" "text" DEFAULT 'aktif'::"text" NOT NULL,
    "reversal_of_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "alasan_batal" "text",
    "dibatalkan_at" timestamp with time zone,
    "dibatalkan_by" "uuid",
    CONSTRAINT "hutang_ledger_jumlah_check" CHECK (("jumlah" >= (0)::numeric)),
    CONSTRAINT "hutang_ledger_pihak_check" CHECK (((("pihak_type" = 'petani'::"text") AND ("petani_id" IS NOT NULL) AND ("mitra_id" IS NULL) AND ("master_mitra_id" IS NULL) AND ("sopir_id" IS NULL)) OR (("pihak_type" = 'mitra'::"text") AND (("mitra_id" IS NOT NULL) OR ("master_mitra_id" IS NOT NULL)) AND ("petani_id" IS NULL) AND ("sopir_id" IS NULL)) OR (("pihak_type" = 'sopir'::"text") AND ("sopir_id" IS NOT NULL) AND ("petani_id" IS NULL) AND ("mitra_id" IS NULL) AND ("master_mitra_id" IS NULL)) OR (("pihak_type" = ANY (ARRAY['karyawan'::"text", 'lainnya'::"text"])) AND (NULLIF("btrim"(COALESCE("pihak_nama_manual", ''::"text")), ''::"text") IS NOT NULL) AND ("petani_id" IS NULL) AND ("mitra_id" IS NULL) AND ("master_mitra_id" IS NULL) AND ("sopir_id" IS NULL)))),
    CONSTRAINT "hutang_ledger_pihak_type_check" CHECK (("pihak_type" = ANY (ARRAY['petani'::"text", 'mitra'::"text", 'sopir'::"text", 'karyawan'::"text", 'lainnya'::"text"]))),
    CONSTRAINT "hutang_ledger_status_check" CHECK (("status" = ANY (ARRAY['aktif'::"text", 'dibatalkan'::"text", 'reversal'::"text"]))),
    CONSTRAINT "hutang_ledger_sumber_check" CHECK (("sumber" = ANY (ARRAY['kasbon'::"text", 'panjar'::"text", 'pupuk'::"text", 'lainnya'::"text", 'bayar_tunai'::"text", 'potong_tbs'::"text", 'potong_settlement'::"text", 'potong_gaji'::"text", 'potong_upah'::"text", 'koreksi'::"text", 'reversal'::"text", 'peminjaman'::"text", 'uang_jalan'::"text", 'gaji'::"text", 'operasional'::"text", 'pembayaran_mitra'::"text", 'pembayaran_petani'::"text", 'pencairan_kas'::"text", 'pelunasan_kas'::"text"]))),
    CONSTRAINT "hutang_ledger_tipe_check" CHECK (("tipe" = ANY (ARRAY['debit'::"text", 'kredit'::"text"])))
);


ALTER TABLE "public"."hutang_ledger" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_hutang_ledger"("p_hutang_ledger_id" "uuid", "p_alasan" "text") RETURNS "public"."hutang_ledger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.hutang_ledger%ROWTYPE;
  v_after public.hutang_ledger%ROWTYPE;
  v_reversal public.hutang_ledger%ROWTYPE;
  v_kas_reversal public.kas_ledger%ROWTYPE;
  v_kas_tipe text;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Tidak berwenang membatalkan hutang/panjar.'
      USING ERRCODE = '42501';
  END IF;

  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_before
  FROM public.hutang_ledger
  WHERE id = p_hutang_ledger_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Data hutang/panjar tidak ditemukan.'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_before.status <> 'aktif' THEN
    RAISE EXCEPTION 'Data hutang/panjar sudah tidak aktif.'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.hutang_ledger (
    pihak_type,
    petani_id,
    mitra_id,
    master_mitra_id,
    sopir_id,
    pihak_nama_manual,
    pihak_ref_id,
    tanggal,
    tipe,
    sumber,
    jumlah,
    transaksi_beli_id,
    settlement_id,
    keterangan,
    status,
    reversal_of_id,
    created_by
  )
  VALUES (
    v_before.pihak_type,
    v_before.petani_id,
    v_before.mitra_id,
    v_before.master_mitra_id,
    v_before.sopir_id,
    v_before.pihak_nama_manual,
    v_before.pihak_ref_id,
    v_before.tanggal,
    CASE WHEN v_before.tipe = 'debit' THEN 'kredit' ELSE 'debit' END,
    'reversal',
    v_before.jumlah,
    v_before.transaksi_beli_id,
    v_before.settlement_id,
    'Reversal: ' || btrim(p_alasan),
    'reversal',
    v_before.id,
    v_actor
  )
  RETURNING * INTO v_reversal;

  IF v_before.kas_ledger_id IS NOT NULL THEN
    v_kas_tipe := CASE WHEN v_before.tipe = 'debit' THEN 'masuk' ELSE 'keluar' END;

    SELECT *
    INTO v_kas_reversal
    FROM public.create_kas_mutasi(
      v_before.tanggal,
      v_kas_tipe,
      'reversal',
      v_before.jumlah,
      v_before.rekening_kas_id,
      'Reversal hutang/panjar: ' || btrim(p_alasan),
      'hutang_ledger',
      v_before.id,
      'hutang_ledger:' || v_before.id::text || ':reversal'
    );

    UPDATE public.kas_ledger
    SET hutang_ledger_id = v_reversal.id,
        reversal_of_id = v_before.kas_ledger_id
    WHERE id = v_kas_reversal.id;

    UPDATE public.hutang_ledger
    SET rekening_kas_id = v_kas_reversal.rekening_kas_id,
        kas_ledger_id = v_kas_reversal.id
    WHERE id = v_reversal.id;
  END IF;

  UPDATE public.hutang_ledger
  SET status = 'dibatalkan',
      alasan_batal = btrim(p_alasan),
      dibatalkan_at = now(),
      dibatalkan_by = v_actor
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."cancel_hutang_ledger"("p_hutang_ledger_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kas_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rekening_kas_id" "uuid" NOT NULL,
    "tanggal" "date" NOT NULL,
    "tipe" "text" NOT NULL,
    "sumber" "text" NOT NULL,
    "jumlah" numeric(15,2) NOT NULL,
    "status" "text" DEFAULT 'aktif'::"text" NOT NULL,
    "source_table" "text",
    "source_id" "uuid",
    "transaksi_beli_id" "uuid",
    "pengiriman_id" "uuid",
    "pembayaran_pabrik_id" "uuid",
    "pembayaran_mitra_kwitansi_id" "uuid",
    "hutang_ledger_id" "uuid",
    "biaya_operasional_id" "uuid",
    "panjar_mitra_id" "uuid",
    "reversal_of_id" "uuid",
    "idempotency_key" "text",
    "keterangan" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "dibatalkan_at" timestamp with time zone,
    "dibatalkan_by" "uuid",
    "alasan_batal" "text",
    "nomor_bukti" "text",
    "reversed_at" timestamp with time zone,
    "reversed_by" "uuid",
    "reversal_reason" "text",
    CONSTRAINT "kas_ledger_jumlah_check" CHECK (("jumlah" > (0)::numeric)),
    CONSTRAINT "kas_ledger_status_check" CHECK (("status" = ANY (ARRAY['aktif'::"text", 'dibatalkan'::"text", 'reversal'::"text"]))),
    CONSTRAINT "kas_ledger_sumber_check" CHECK (("sumber" = ANY (ARRAY['modal_awal'::"text", 'pembayaran_pabrik'::"text", 'pembayaran_mitra'::"text", 'pembayaran_petani'::"text", 'pembelian_tbs'::"text", 'hutang_pencairan'::"text", 'hutang_pelunasan'::"text", 'panjar_mitra'::"text", 'biaya_operasional'::"text", 'transfer_kas'::"text", 'koreksi'::"text", 'reversal'::"text", 'lainnya'::"text"]))),
    CONSTRAINT "kas_ledger_tipe_check" CHECK (("tipe" = ANY (ARRAY['masuk'::"text", 'keluar'::"text", 'transfer_masuk'::"text", 'transfer_keluar'::"text", 'koreksi'::"text", 'reversal'::"text"])))
);


ALTER TABLE "public"."kas_ledger" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_kas_mutasi_manual"("p_kas_id" "uuid", "p_alasan" "text") RETURNS "public"."kas_ledger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."cancel_kas_mutasi_manual"("p_kas_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."panjar_mitra" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tanggal" "date" NOT NULL,
    "mitra_id" "uuid",
    "jumlah" numeric(15,2) NOT NULL,
    "keterangan" "text",
    "status" character varying(20) DEFAULT 'belum_lunas'::character varying,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "alasan_batal" "text",
    "dibatalkan_at" timestamp with time zone,
    "dibatalkan_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "rekening_kas_id" "uuid",
    "kas_ledger_id" "uuid",
    "hutang_ledger_id" "uuid",
    "settlement_hutang_ledger_id" "uuid",
    "lunas_at" timestamp with time zone,
    "pembayaran_mitra_kwitansi_id" "uuid",
    CONSTRAINT "panjar_mitra_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['belum_lunas'::character varying, 'lunas'::character varying, 'dibatalkan'::character varying])::"text"[])))
);


ALTER TABLE "public"."panjar_mitra" OWNER TO "postgres";


COMMENT ON COLUMN "public"."panjar_mitra"."pembayaran_mitra_kwitansi_id" IS 'Kwitansi yang menggunakan panjar ini sebagai potongan pembayaran mitra.';



CREATE OR REPLACE FUNCTION "public"."cancel_panjar_mitra_kas"("p_panjar_id" "uuid", "p_alasan" "text") RETURNS "public"."panjar_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_panjar public.panjar_mitra%ROWTYPE;
  v_after public.panjar_mitra%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Tidak berwenang membatalkan panjar mitra.'
      USING ERRCODE = '42501';
  END IF;

  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan panjar wajib diisi.'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_panjar
  FROM public.panjar_mitra
  WHERE id = p_panjar_id
  FOR UPDATE;

  IF v_panjar.id IS NULL THEN
    RAISE EXCEPTION 'Panjar tidak ditemukan.'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_panjar.status <> 'belum_lunas' THEN
    RAISE EXCEPTION 'Hanya panjar belum lunas yang bisa dibatalkan.'
      USING ERRCODE = '22023';
  END IF;

  IF v_panjar.hutang_ledger_id IS NOT NULL THEN
    PERFORM public.cancel_hutang_ledger(v_panjar.hutang_ledger_id, p_alasan);
  END IF;

  UPDATE public.panjar_mitra
  SET status = 'dibatalkan',
      alasan_batal = btrim(p_alasan),
      dibatalkan_at = now(),
      dibatalkan_by = v_actor,
      updated_at = now()
  WHERE id = v_panjar.id
  RETURNING * INTO v_after;

  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."cancel_panjar_mitra_kas"("p_panjar_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_pembayaran_dana_trip"("p_transaksi_id" "uuid", "p_alasan" "text") RETURNS "public"."transaksi_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_transaksi public.transaksi_mitra%ROWTYPE;
  v_biaya public.biaya_operasional%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
  v_pelunasan public.hutang_ledger%ROWTYPE;
  v_kas_reversal_id uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat membatalkan Dana Trip.' USING ERRCODE = '42501';
  END IF;
  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_transaksi
  FROM public.transaksi_mitra
  WHERE id = p_transaksi_id
  FOR UPDATE;

  IF v_transaksi.id IS NULL THEN
    RAISE EXCEPTION 'Pengiriman tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF v_transaksi.biaya_sopir_dibayar_at IS NULL
     OR v_transaksi.biaya_sopir_operasional_id IS NULL
     OR v_transaksi.tagihan_sopir_bayar_ledger_id IS NULL THEN
    RAISE EXCEPTION 'Dana Trip belum dibayar atau referensinya tidak lengkap.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_biaya
  FROM public.biaya_operasional
  WHERE id = v_transaksi.biaya_sopir_operasional_id
  FOR UPDATE;

  SELECT * INTO v_pelunasan
  FROM public.hutang_ledger
  WHERE id = v_transaksi.tagihan_sopir_bayar_ledger_id
  FOR UPDATE;

  SELECT * INTO v_kas
  FROM public.kas_ledger
  WHERE id = COALESCE(v_biaya.kas_ledger_id, v_pelunasan.kas_ledger_id)
  FOR UPDATE;

  IF v_kas.id IS NULL THEN
    RAISE EXCEPTION 'Kas keluar Dana Trip tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM public.kas_ledger WHERE reversal_of_id = v_kas.id AND status <> 'dibatalkan') THEN
    RAISE EXCEPTION 'Dana Trip ini sudah memiliki transaksi balik.' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.kas_ledger (
    rekening_kas_id, tanggal, tipe, sumber, jumlah,
    biaya_operasional_id, hutang_ledger_id, source_table, source_id,
    reversal_of_id, idempotency_key, keterangan, created_by
  ) VALUES (
    v_kas.rekening_kas_id, (now() AT TIME ZONE 'Asia/Jakarta')::date,
    'masuk', 'reversal', v_kas.jumlah,
    v_biaya.id, v_pelunasan.id, 'transaksi_mitra', v_transaksi.id,
    v_kas.id, 'dana_trip:' || v_transaksi.id::text || ':reversal',
    'Pembalikan Dana Trip: ' || btrim(p_alasan), v_actor
  ) RETURNING id INTO v_kas_reversal_id;

  INSERT INTO public.hutang_ledger (
    pihak_type, petani_id, mitra_id, master_mitra_id, sopir_id,
    pihak_nama_manual, pihak_ref_id, tanggal, tipe, sumber, jumlah,
    transaksi_beli_id, settlement_id, keterangan, status,
    reversal_of_id, rekening_kas_id, kas_ledger_id, created_by
  ) VALUES (
    v_pelunasan.pihak_type, v_pelunasan.petani_id, v_pelunasan.mitra_id,
    v_pelunasan.master_mitra_id, v_pelunasan.sopir_id,
    v_pelunasan.pihak_nama_manual, v_pelunasan.pihak_ref_id,
    (now() AT TIME ZONE 'Asia/Jakarta')::date, 'debit', 'reversal',
    v_pelunasan.jumlah, v_pelunasan.transaksi_beli_id,
    v_pelunasan.settlement_id, 'Pembalikan Dana Trip: ' || btrim(p_alasan),
    'reversal', v_pelunasan.id, v_kas.rekening_kas_id,
    v_kas_reversal_id, v_actor
  );

  UPDATE public.kas_ledger
  SET reversed_at = now(), reversed_by = v_actor, reversal_reason = btrim(p_alasan)
  WHERE id = v_kas.id;

  UPDATE public.biaya_operasional
  SET status = 'dibatalkan', alasan_batal = btrim(p_alasan),
      dibatalkan_at = now(), dibatalkan_by = v_actor
  WHERE id = v_biaya.id;

  UPDATE public.transaksi_mitra
  SET tagihan_sopir_bayar_ledger_id = NULL,
      biaya_sopir_operasional_id = NULL,
      biaya_sopir_dibayar_at = NULL,
      updated_by = v_actor,
      alasan_edit = 'Pembayaran Dana Trip dibatalkan: ' || btrim(p_alasan)
  WHERE id = v_transaksi.id
  RETURNING * INTO v_transaksi;

  PERFORM public.write_audit_log('transaksi_mitra', v_transaksi.id, 'reverse_dana_trip', NULL, to_jsonb(v_transaksi), p_alasan, v_actor);
  RETURN v_transaksi;
END;
$$;


ALTER FUNCTION "public"."cancel_pembayaran_dana_trip"("p_transaksi_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pembayaran_mitra_kwitansi" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "master_mitra_id" "uuid" NOT NULL,
    "periode_dari" "date" NOT NULL,
    "periode_sampai" "date" NOT NULL,
    "status" "text" DEFAULT 'dibayar'::"text" NOT NULL,
    "tanggal_bayar" "date" DEFAULT CURRENT_DATE NOT NULL,
    "dibayar_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "metode_bayar" "text" DEFAULT 'tunai'::"text" NOT NULL,
    "total_tonase" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_nilai_bersih" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_panjar" numeric(15,2) DEFAULT 0 NOT NULL,
    "nominal_dibayar" numeric(15,2) DEFAULT 0 NOT NULL,
    "jumlah_transaksi" integer DEFAULT 0 NOT NULL,
    "panjar_ids" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "panjar_snapshot_json" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "transaksi_snapshot_json" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "catatan" "text",
    "review_reason" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "rekening_kas_id" "uuid",
    "kas_ledger_id" "uuid",
    "mode_pembayaran" "text" DEFAULT 'single'::"text" NOT NULL,
    "mitra_ids" "uuid"[] DEFAULT '{}'::"uuid"[] NOT NULL,
    "penerima_label" "text",
    "jumlah_mitra" integer DEFAULT 1 NOT NULL,
    "total_sewa_armada" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_berat_netto" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_berat_dibayar" numeric(15,2) DEFAULT 0 NOT NULL,
    "nomor_bukti" "text",
    "alasan_batal" "text",
    "dibatalkan_at" timestamp with time zone,
    "dibatalkan_by" "uuid",
    "reversal_kas_ledger_id" "uuid",
    CONSTRAINT "pembayaran_mitra_kwitansi_jumlah_mitra_check" CHECK (("jumlah_mitra" > 0)),
    CONSTRAINT "pembayaran_mitra_kwitansi_metode_bayar_check" CHECK (("metode_bayar" = ANY (ARRAY['tunai'::"text", 'transfer'::"text", 'lainnya'::"text"]))),
    CONSTRAINT "pembayaran_mitra_kwitansi_mode_check" CHECK (("mode_pembayaran" = ANY (ARRAY['single'::"text", 'gabungan'::"text"]))),
    CONSTRAINT "pembayaran_mitra_kwitansi_periode_check" CHECK (("periode_sampai" >= "periode_dari")),
    CONSTRAINT "pembayaran_mitra_kwitansi_status_check" CHECK (("status" = ANY (ARRAY['dibayar'::"text", 'perlu_review'::"text", 'dibatalkan'::"text"])))
);


ALTER TABLE "public"."pembayaran_mitra_kwitansi" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_pembayaran_mitra_kwitansi"("p_pembayaran_id" "uuid", "p_alasan" "text") RETURNS "public"."pembayaran_mitra_kwitansi"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."cancel_pembayaran_mitra_kwitansi"("p_pembayaran_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pembayaran_pabrik_batch" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pabrik_id" "uuid" NOT NULL,
    "tanggal_bayar" "date" DEFAULT CURRENT_DATE NOT NULL,
    "diterima_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "metode_bayar" "text" DEFAULT 'transfer'::"text" NOT NULL,
    "nomor_bukti" "text",
    "status" "text" DEFAULT 'diterima'::"text" NOT NULL,
    "total_tonase" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_tonase_sistem" numeric(15,2) DEFAULT 0 NOT NULL,
    "selisih_tonase" numeric(15,2) DEFAULT 0 NOT NULL,
    "harga_pabrik_per_kg" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_nilai_pabrik" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_diterima" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_selisih" numeric(15,2) DEFAULT 0 NOT NULL,
    "jumlah_transaksi" integer DEFAULT 0 NOT NULL,
    "rekening_kas_id" "uuid",
    "kas_ledger_id" "uuid",
    "catatan" "text",
    "alasan_batal" "text",
    "dibatalkan_at" timestamp with time zone,
    "dibatalkan_by" "uuid",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "pembayaran_pabrik_batch_metode_check" CHECK (("metode_bayar" = ANY (ARRAY['tunai'::"text", 'transfer'::"text", 'lainnya'::"text"]))),
    CONSTRAINT "pembayaran_pabrik_batch_nominal_check" CHECK ((("total_diterima" >= (0)::numeric) AND ("total_nilai_pabrik" >= (0)::numeric) AND ("total_tonase" >= (0)::numeric) AND ("total_tonase_sistem" >= (0)::numeric) AND ("harga_pabrik_per_kg" >= (0)::numeric))),
    CONSTRAINT "pembayaran_pabrik_batch_status_check" CHECK (("status" = ANY (ARRAY['diterima'::"text", 'perlu_review'::"text", 'dibatalkan'::"text"])))
);


ALTER TABLE "public"."pembayaran_pabrik_batch" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_pembayaran_pabrik_batch"("p_pembayaran_id" "uuid", "p_alasan" "text") RETURNS "public"."pembayaran_pabrik_batch"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_batch public.pembayaran_pabrik_batch%ROWTYPE;
  v_after public.pembayaran_pabrik_batch%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Tidak berwenang membatalkan pembayaran pabrik.'
      USING ERRCODE = '42501';
  END IF;

  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan pembayaran pabrik wajib diisi.'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_batch
  FROM public.pembayaran_pabrik_batch
  WHERE id = p_pembayaran_id
  FOR UPDATE;

  IF v_batch.id IS NULL THEN
    RAISE EXCEPTION 'Pembayaran pabrik tidak ditemukan.'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_batch.status = 'dibatalkan' THEN
    RAISE EXCEPTION 'Pembayaran pabrik sudah dibatalkan.'
      USING ERRCODE = '22023';
  END IF;

  IF v_batch.kas_ledger_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.kas_ledger
       WHERE reversal_of_id = v_batch.kas_ledger_id
         AND status = 'aktif'
     ) THEN
    INSERT INTO public.kas_ledger (
      rekening_kas_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      source_table,
      source_id,
      reversal_of_id,
      idempotency_key,
      keterangan,
      created_by
    )
    VALUES (
      COALESCE(v_batch.rekening_kas_id, public.get_default_rekening_kas_id()),
      v_batch.tanggal_bayar,
      'keluar',
      'reversal',
      v_batch.total_diterima,
      'pembayaran_pabrik_batch',
      v_batch.id,
      v_batch.kas_ledger_id,
      'pembayaran_pabrik_batch:' || v_batch.id::text || ':reversal',
      'Reversal pembayaran pabrik '
        || COALESCE(NULLIF(v_batch.nomor_bukti, ''), v_batch.id::text)
        || ': '
        || btrim(p_alasan),
      v_actor
    );
  END IF;

  UPDATE public.pembayaran_pabrik_item
  SET status = 'dibatalkan'
  WHERE pembayaran_id = v_batch.id
    AND status <> 'dibatalkan';

  UPDATE public.transaksi_mitra
  SET pembayaran_pabrik_batch_id = NULL,
      pembayaran_pabrik_item_id = NULL,
      pembayaran_pabrik_status = 'belum_dibayar',
      pembayaran_pabrik_at = NULL,
      updated_at = now(),
      updated_by = v_actor
  WHERE pembayaran_pabrik_batch_id = v_batch.id;

  UPDATE public.pembayaran_pabrik_batch
  SET status = 'dibatalkan',
      alasan_batal = btrim(p_alasan),
      dibatalkan_at = now(),
      dibatalkan_by = v_actor,
      updated_at = now(),
      updated_by = v_actor
  WHERE id = v_batch.id
  RETURNING * INTO v_after;

  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."cancel_pembayaran_pabrik_batch"("p_pembayaran_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."piutang_dokumen" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nomor_bukti" "text" NOT NULL,
    "jenis_dokumen" "text" NOT NULL,
    "pihak_type" "text" NOT NULL,
    "petani_id" "uuid",
    "master_mitra_id" "uuid",
    "sopir_id" "uuid",
    "pihak_nama_manual" "text",
    "pihak_nama_snapshot" "text" NOT NULL,
    "pihak_kode_snapshot" "text",
    "pihak_kontak_snapshot" "text",
    "tanggal_pengajuan" "date" NOT NULL,
    "tanggal_jatuh_tempo" "date",
    "jumlah" numeric(15,2) NOT NULL,
    "tujuan" "text" NOT NULL,
    "metode_pelunasan" "text" NOT NULL,
    "status" "text" DEFAULT 'menunggu_persetujuan'::"text" NOT NULL,
    "diajukan_oleh" "uuid" NOT NULL,
    "disetujui_oleh" "uuid",
    "disetujui_at" timestamp with time zone,
    "alasan_penolakan" "text",
    "rekening_kas_id" "uuid",
    "metode_penyerahan" "text",
    "nama_penerima" "text",
    "nomor_identitas_penerima" "text",
    "diserahkan_oleh" "uuid",
    "diserahkan_at" timestamp with time zone,
    "hutang_ledger_id" "uuid",
    "kas_ledger_id" "uuid",
    "panjar_mitra_id" "uuid",
    "bukti_tanda_tangan_url" "text",
    "catatan" "text",
    "alasan_batal" "text",
    "dibatalkan_oleh" "uuid",
    "dibatalkan_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "piutang_dokumen_jenis_dokumen_check" CHECK (("jenis_dokumen" = ANY (ARRAY['panjar_mitra'::"text", 'panjar_petani'::"text", 'kasbon_sopir'::"text", 'kasbon_karyawan'::"text", 'piutang_lainnya'::"text"]))),
    CONSTRAINT "piutang_dokumen_jumlah_check" CHECK (("jumlah" > (0)::numeric)),
    CONSTRAINT "piutang_dokumen_metode_pelunasan_check" CHECK (("metode_pelunasan" = ANY (ARRAY['potong_kwitansi_tbs'::"text", 'potong_gaji'::"text", 'potong_upah'::"text", 'tunai_transfer'::"text"]))),
    CONSTRAINT "piutang_dokumen_metode_penyerahan_check" CHECK (("metode_penyerahan" = ANY (ARRAY['tunai'::"text", 'transfer'::"text"]))),
    CONSTRAINT "piutang_dokumen_party_check" CHECK (((("pihak_type" = 'petani'::"text") AND ("petani_id" IS NOT NULL) AND ("master_mitra_id" IS NULL) AND ("sopir_id" IS NULL)) OR (("pihak_type" = 'mitra'::"text") AND ("master_mitra_id" IS NOT NULL) AND ("petani_id" IS NULL) AND ("sopir_id" IS NULL)) OR (("pihak_type" = 'sopir'::"text") AND ("sopir_id" IS NOT NULL) AND ("petani_id" IS NULL) AND ("master_mitra_id" IS NULL)) OR (("pihak_type" = ANY (ARRAY['karyawan'::"text", 'lainnya'::"text"])) AND (NULLIF("btrim"(COALESCE("pihak_nama_manual", ''::"text")), ''::"text") IS NOT NULL) AND ("petani_id" IS NULL) AND ("master_mitra_id" IS NULL) AND ("sopir_id" IS NULL)))),
    CONSTRAINT "piutang_dokumen_pihak_type_check" CHECK (("pihak_type" = ANY (ARRAY['petani'::"text", 'mitra'::"text", 'sopir'::"text", 'karyawan'::"text", 'lainnya'::"text"]))),
    CONSTRAINT "piutang_dokumen_status_check" CHECK (("status" = ANY (ARRAY['menunggu_persetujuan'::"text", 'disetujui'::"text", 'ditolak'::"text", 'diserahkan'::"text", 'lunas'::"text", 'dibatalkan'::"text"])))
);


ALTER TABLE "public"."piutang_dokumen" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_piutang_document"("p_document_id" "uuid", "p_alasan" "text") RETURNS "public"."piutang_dokumen"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."cancel_piutang_document"("p_document_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."piutang_pelunasan" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "piutang_dokumen_id" "uuid" NOT NULL,
    "tanggal" "date" NOT NULL,
    "jumlah" numeric(15,2) NOT NULL,
    "metode" "text" NOT NULL,
    "hutang_ledger_id" "uuid" NOT NULL,
    "kas_ledger_id" "uuid",
    "nomor_bukti" "text" NOT NULL,
    "keterangan" "text",
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "text" DEFAULT 'aktif'::"text" NOT NULL,
    CONSTRAINT "piutang_pelunasan_jumlah_check" CHECK (("jumlah" > (0)::numeric)),
    CONSTRAINT "piutang_pelunasan_metode_check" CHECK (("metode" = ANY (ARRAY['tunai'::"text", 'transfer'::"text", 'potong_gaji'::"text", 'potong_upah'::"text"]))),
    CONSTRAINT "piutang_pelunasan_status_check" CHECK (("status" = ANY (ARRAY['aktif'::"text", 'dibatalkan'::"text"])))
);


ALTER TABLE "public"."piutang_pelunasan" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_piutang_repayment"("p_payment_id" "uuid", "p_alasan" "text") RETURNS "public"."piutang_pelunasan"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.piutang_pelunasan%ROWTYPE;
  v_after public.piutang_pelunasan%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR public.current_app_role() NOT IN ('owner', 'super_admin') THEN
    RAISE EXCEPTION 'Hanya Owner atau Super Admin yang dapat membatalkan pengembalian.' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(btrim(COALESCE(p_alasan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before FROM public.piutang_pelunasan WHERE id = p_payment_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'Pengembalian tidak ditemukan.' USING ERRCODE = 'P0002'; END IF;
  IF v_before.status <> 'aktif' THEN RAISE EXCEPTION 'Pengembalian ini sudah dibatalkan.' USING ERRCODE = '22023'; END IF;

  PERFORM public.cancel_hutang_ledger(v_before.hutang_ledger_id, p_alasan);
  UPDATE public.piutang_pelunasan SET status = 'dibatalkan' WHERE id = v_before.id RETURNING * INTO v_after;
  UPDATE public.piutang_dokumen SET status = 'diserahkan', updated_at = now()
  WHERE id = v_before.piutang_dokumen_id AND status = 'lunas';

  PERFORM public.write_audit_log(
    'piutang_pelunasan', v_after.id, 'cancel', to_jsonb(v_before), to_jsonb(v_after), p_alasan, v_actor
  );
  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."cancel_piutang_repayment"("p_payment_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."next_no_struk_tbs"("p_tanggal" "date" DEFAULT CURRENT_DATE) RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  next_value bigint;
BEGIN
  next_value := nextval('public.transaksi_beli_tbs_no_struk_seq');
  RETURN 'TBS-' || to_char(p_tanggal, 'YYYYMMDD') || '-' || lpad(next_value::text, 6, '0');
END;
$$;


ALTER FUNCTION "public"."next_no_struk_tbs"("p_tanggal" "date") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."transaksi_beli_tbs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tanggal" "date" NOT NULL,
    "petani_id" "uuid",
    "harga_tbs_lokal_id" "uuid",
    "berat_kotor_kg" numeric(14,2) NOT NULL,
    "potongan_type" "text" DEFAULT 'percent'::"text" NOT NULL,
    "potongan_value" numeric(14,2) DEFAULT 0 NOT NULL,
    "berat_bersih_kg" numeric(14,2) NOT NULL,
    "harga_per_kg" numeric(12,2) NOT NULL,
    "total_harga" numeric(15,2) DEFAULT 0 NOT NULL,
    "potongan_hutang" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_bayar_tunai" numeric(15,2) DEFAULT 0 NOT NULL,
    "no_struk" "text" DEFAULT "public"."next_no_struk_tbs"(CURRENT_DATE),
    "status" "text" DEFAULT 'aktif'::"text" NOT NULL,
    "reversal_of_id" "uuid",
    "keterangan" "text",
    "legacy_transaksi_beli_id" "uuid",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "rekening_kas_id" "uuid",
    "kas_ledger_id" "uuid",
    CONSTRAINT "transaksi_beli_tbs_berat_bersih_kg_check" CHECK (("berat_bersih_kg" >= (0)::numeric)),
    CONSTRAINT "transaksi_beli_tbs_berat_kotor_kg_check" CHECK (("berat_kotor_kg" >= (0)::numeric)),
    CONSTRAINT "transaksi_beli_tbs_harga_per_kg_check" CHECK (("harga_per_kg" >= (0)::numeric)),
    CONSTRAINT "transaksi_beli_tbs_potongan_hutang_check" CHECK (("potongan_hutang" >= (0)::numeric)),
    CONSTRAINT "transaksi_beli_tbs_potongan_type_check" CHECK (("potongan_type" = ANY (ARRAY['percent'::"text", 'kg'::"text", 'nominal'::"text"]))),
    CONSTRAINT "transaksi_beli_tbs_potongan_value_check" CHECK (("potongan_value" >= (0)::numeric)),
    CONSTRAINT "transaksi_beli_tbs_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'aktif'::"text", 'dibatalkan'::"text", 'reversal'::"text"]))),
    CONSTRAINT "transaksi_beli_tbs_total_bayar_tunai_check" CHECK (("total_bayar_tunai" >= (0)::numeric)),
    CONSTRAINT "transaksi_beli_tbs_total_harga_check" CHECK (("total_harga" >= (0)::numeric))
);


ALTER TABLE "public"."transaksi_beli_tbs" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_transaksi_beli_tbs"("p_transaksi_id" "uuid", "p_alasan" "text") RETURNS "public"."transaksi_beli_tbs"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.transaksi_beli_tbs%ROWTYPE;
  v_after public.transaksi_beli_tbs%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Pembatalan transaksi wajib dilakukan owner atau super admin';
  END IF;

  IF p_alasan IS NULL OR length(trim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi';
  END IF;

  SELECT *
  INTO v_before
  FROM public.transaksi_beli_tbs
  WHERE id = p_transaksi_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Transaksi tidak ditemukan';
  END IF;

  IF v_before.status = 'dibatalkan' THEN
    RAISE EXCEPTION 'Transaksi sudah dibatalkan';
  END IF;

  UPDATE public.transaksi_beli_tbs
  SET status = 'dibatalkan',
      keterangan = concat_ws(E'\n', keterangan, 'Dibatalkan: ' || p_alasan),
      updated_at = now()
  WHERE id = p_transaksi_id
  RETURNING * INTO v_after;

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
    v_before.tanggal,
    'reversal',
    'reversal',
    v_before.id,
    -v_before.berat_bersih_kg,
    'Reversal batal ' || v_before.no_struk || ': ' || p_alasan,
    v_actor
  );

  IF v_before.potongan_hutang > 0 THEN
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
      v_before.petani_id,
      v_before.tanggal,
      'debit',
      'reversal',
      v_before.potongan_hutang,
      v_before.id,
      'Reversal potong hutang ' || v_before.no_struk || ': ' || p_alasan,
      v_actor
    );
  END IF;

  IF v_before.kas_ledger_id IS NOT NULL
     AND v_before.total_bayar_tunai > 0
     AND NOT EXISTS (
       SELECT 1
       FROM public.kas_ledger
       WHERE reversal_of_id = v_before.kas_ledger_id
         AND status = 'aktif'
     ) THEN
    INSERT INTO public.kas_ledger (
      rekening_kas_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      transaksi_beli_id,
      source_table,
      source_id,
      reversal_of_id,
      idempotency_key,
      keterangan,
      created_by
    )
    VALUES (
      COALESCE(v_before.rekening_kas_id, public.get_default_rekening_kas_id()),
      v_before.tanggal,
      'masuk',
      'reversal',
      v_before.total_bayar_tunai,
      v_before.id,
      'transaksi_beli_tbs',
      v_before.id,
      v_before.kas_ledger_id,
      'transaksi_beli_tbs:' || v_before.id::text || ':reversal',
      'Reversal bayar tunai ' || v_before.no_struk || ': ' || p_alasan,
      v_actor
    );
  END IF;

  PERFORM public.write_audit_log(
    'transaksi_beli_tbs',
    v_before.id,
    'cancel',
    to_jsonb(v_before),
    to_jsonb(v_after),
    p_alasan
  );

  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."cancel_transaksi_beli_tbs"("p_transaksi_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_transaksi_mitra_controlled"("p_transaksi_id" "uuid", "p_alasan" "text") RETURNS "public"."transaksi_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.transaksi_mitra%ROWTYPE;
  v_after public.transaksi_mitra%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang membatalkan pengiriman.' USING ERRCODE = '42501';
  END IF;
  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before
  FROM public.transaksi_mitra
  WHERE id = p_transaksi_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Pengiriman tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF v_before.status = 'dibatalkan' THEN
    RAISE EXCEPTION 'Pengiriman sudah dibatalkan.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.transaksi_mitra
  SET status = 'dibatalkan',
      dibatalkan_at = now(),
      dibatalkan_by = v_actor,
      alasan_batal = btrim(p_alasan),
      updated_by = v_actor,
      alasan_edit = 'Dibatalkan: ' || btrim(p_alasan)
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  PERFORM public.write_audit_log('transaksi_mitra', v_before.id, 'cancel', to_jsonb(v_before), to_jsonb(v_after), p_alasan, v_actor);
  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."cancel_transaksi_mitra_controlled"("p_transaksi_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_biaya_operasional_armada_kas"("p_tanggal" "date", "p_kategori" "text", "p_jumlah" numeric, "p_armada_sopir_id" "uuid", "p_keterangan" "text" DEFAULT NULL::"text", "p_rekening_kas_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."biaya_operasional"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_biaya public.biaya_operasional%ROWTYPE;
BEGIN
  IF p_armada_sopir_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.sopir
    WHERE id = p_armada_sopir_id
      AND aktif = true
      AND is_armada_cb = true
  ) THEN
    RAISE EXCEPTION 'Armada CB tidak ditemukan atau tidak aktif.' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_biaya
  FROM public.create_biaya_operasional_kas(
    p_tanggal,
    p_kategori,
    p_jumlah,
    p_keterangan,
    p_rekening_kas_id
  );

  UPDATE public.biaya_operasional
  SET armada_sopir_id = p_armada_sopir_id
  WHERE id = v_biaya.id
  RETURNING * INTO v_biaya;

  RETURN v_biaya;
END;
$$;


ALTER FUNCTION "public"."create_biaya_operasional_armada_kas"("p_tanggal" "date", "p_kategori" "text", "p_jumlah" numeric, "p_armada_sopir_id" "uuid", "p_keterangan" "text", "p_rekening_kas_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_biaya_operasional_kas"("p_tanggal" "date", "p_kategori" "text", "p_jumlah" numeric, "p_keterangan" "text" DEFAULT NULL::"text", "p_rekening_kas_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."biaya_operasional"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_biaya public.biaya_operasional%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
  v_rekening_id uuid := p_rekening_kas_id;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat biaya operasional.'
      USING ERRCODE = '42501';
  END IF;

  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
    RAISE EXCEPTION 'Jumlah biaya harus lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF v_rekening_id IS NULL THEN
    v_rekening_id := public.get_default_rekening_kas_id();
  END IF;

  INSERT INTO public.biaya_operasional (
    tanggal,
    kategori,
    jumlah,
    keterangan,
    status,
    rekening_kas_id,
    created_by
  )
  VALUES (
    COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    p_kategori,
    round(p_jumlah, 2),
    NULLIF(btrim(COALESCE(p_keterangan, '')), ''),
    'aktif',
    v_rekening_id,
    v_actor
  )
  RETURNING * INTO v_biaya;

  INSERT INTO public.kas_ledger (
    rekening_kas_id,
    tanggal,
    tipe,
    sumber,
    jumlah,
    biaya_operasional_id,
    source_table,
    source_id,
    idempotency_key,
    keterangan,
    created_by
  )
  VALUES (
    v_rekening_id,
    v_biaya.tanggal,
    'keluar',
    'biaya_operasional',
    v_biaya.jumlah,
    v_biaya.id,
    'biaya_operasional',
    v_biaya.id,
    'biaya_operasional:' || v_biaya.id::text,
    COALESCE(v_biaya.keterangan, 'Biaya operasional'),
    v_actor
  )
  RETURNING * INTO v_kas;

  UPDATE public.biaya_operasional
  SET kas_ledger_id = v_kas.id
  WHERE id = v_biaya.id
  RETURNING * INTO v_biaya;

  RETURN v_biaya;
END;
$$;


ALTER FUNCTION "public"."create_biaya_operasional_kas"("p_tanggal" "date", "p_kategori" "text", "p_jumlah" numeric, "p_keterangan" "text", "p_rekening_kas_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_hutang_pihak"("p_pihak_type" "text", "p_tipe" "text", "p_sumber" "text", "p_jumlah" numeric, "p_tanggal" "date" DEFAULT NULL::"date", "p_petani_id" "uuid" DEFAULT NULL::"uuid", "p_master_mitra_id" "uuid" DEFAULT NULL::"uuid", "p_sopir_id" "uuid" DEFAULT NULL::"uuid", "p_pihak_nama_manual" "text" DEFAULT NULL::"text", "p_keterangan" "text" DEFAULT NULL::"text", "p_rekening_kas_id" "uuid" DEFAULT NULL::"uuid", "p_catat_kas" boolean DEFAULT true, "p_legacy_source_table" "text" DEFAULT NULL::"text", "p_legacy_source_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."hutang_ledger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_tanggal date := COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date);
  v_hutang public.hutang_ledger%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
  v_kas_tipe text;
  v_kas_sumber text;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat hutang/panjar.'
      USING ERRCODE = '42501';
  END IF;

  IF p_pihak_type NOT IN ('petani', 'mitra', 'sopir', 'karyawan', 'lainnya') THEN
    RAISE EXCEPTION 'Jenis pihak hutang tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  IF p_tipe NOT IN ('debit', 'kredit') THEN
    RAISE EXCEPTION 'Tipe hutang harus debit atau kredit.'
      USING ERRCODE = '22023';
  END IF;

  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
    RAISE EXCEPTION 'Jumlah hutang/panjar harus lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF p_pihak_type = 'petani' AND p_petani_id IS NULL THEN
    RAISE EXCEPTION 'Petani wajib dipilih.'
      USING ERRCODE = '22023';
  ELSIF p_pihak_type = 'mitra' AND p_master_mitra_id IS NULL THEN
    RAISE EXCEPTION 'Mitra wajib dipilih.'
      USING ERRCODE = '22023';
  ELSIF p_pihak_type = 'sopir' AND p_sopir_id IS NULL THEN
    RAISE EXCEPTION 'Sopir wajib dipilih.'
      USING ERRCODE = '22023';
  ELSIF p_pihak_type IN ('karyawan', 'lainnya') AND NULLIF(btrim(COALESCE(p_pihak_nama_manual, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Nama pihak wajib diisi.'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.hutang_ledger (
    pihak_type,
    petani_id,
    master_mitra_id,
    sopir_id,
    pihak_nama_manual,
    tanggal,
    tipe,
    sumber,
    jumlah,
    legacy_source_table,
    legacy_source_id,
    keterangan,
    created_by
  )
  VALUES (
    p_pihak_type,
    CASE WHEN p_pihak_type = 'petani' THEN p_petani_id ELSE NULL END,
    CASE WHEN p_pihak_type = 'mitra' THEN p_master_mitra_id ELSE NULL END,
    CASE WHEN p_pihak_type = 'sopir' THEN p_sopir_id ELSE NULL END,
    CASE WHEN p_pihak_type IN ('karyawan', 'lainnya') THEN NULLIF(btrim(COALESCE(p_pihak_nama_manual, '')), '') ELSE NULL END,
    v_tanggal,
    p_tipe,
    COALESCE(NULLIF(btrim(p_sumber), ''), 'lainnya'),
    round(p_jumlah, 2),
    NULLIF(btrim(COALESCE(p_legacy_source_table, '')), ''),
    p_legacy_source_id,
    NULLIF(btrim(COALESCE(p_keterangan, '')), ''),
    v_actor
  )
  RETURNING * INTO v_hutang;

  IF p_catat_kas THEN
    v_kas_tipe := CASE WHEN p_tipe = 'debit' THEN 'keluar' ELSE 'masuk' END;
    v_kas_sumber := CASE
      WHEN p_tipe = 'debit' AND p_sumber = 'panjar' THEN 'panjar_mitra'
      WHEN p_tipe = 'debit' THEN 'hutang_pencairan'
      ELSE 'hutang_pelunasan'
    END;

    SELECT *
    INTO v_kas
    FROM public.create_kas_mutasi(
      v_tanggal,
      v_kas_tipe,
      v_kas_sumber,
      p_jumlah,
      p_rekening_kas_id,
      COALESCE(NULLIF(btrim(p_keterangan), ''), 'Mutasi hutang/panjar'),
      'hutang_ledger',
      v_hutang.id,
      'hutang_ledger:' || v_hutang.id::text || ':' || v_kas_tipe
    );

    UPDATE public.kas_ledger
    SET hutang_ledger_id = v_hutang.id
    WHERE id = v_kas.id;

    UPDATE public.hutang_ledger
    SET rekening_kas_id = v_kas.rekening_kas_id,
        kas_ledger_id = v_kas.id
    WHERE id = v_hutang.id
    RETURNING * INTO v_hutang;
  END IF;

  RETURN v_hutang;
END;
$$;


ALTER FUNCTION "public"."create_hutang_pihak"("p_pihak_type" "text", "p_tipe" "text", "p_sumber" "text", "p_jumlah" numeric, "p_tanggal" "date", "p_petani_id" "uuid", "p_master_mitra_id" "uuid", "p_sopir_id" "uuid", "p_pihak_nama_manual" "text", "p_keterangan" "text", "p_rekening_kas_id" "uuid", "p_catat_kas" boolean, "p_legacy_source_table" "text", "p_legacy_source_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_kas_mutasi"("p_tanggal" "date", "p_tipe" "text", "p_sumber" "text", "p_jumlah" numeric, "p_rekening_kas_id" "uuid" DEFAULT NULL::"uuid", "p_keterangan" "text" DEFAULT NULL::"text", "p_source_table" "text" DEFAULT NULL::"text", "p_source_id" "uuid" DEFAULT NULL::"uuid", "p_idempotency_key" "text" DEFAULT NULL::"text") RETURNS "public"."kas_ledger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_rekening_id uuid := p_rekening_kas_id;
  v_existing public.kas_ledger%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat mutasi kas.'
      USING ERRCODE = '42501';
  END IF;

  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
    RAISE EXCEPTION 'Jumlah mutasi kas harus lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF p_tipe NOT IN ('masuk', 'keluar', 'transfer_masuk', 'transfer_keluar', 'koreksi', 'reversal') THEN
    RAISE EXCEPTION 'Tipe mutasi kas tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  IF p_sumber NOT IN (
    'modal_awal',
    'pembayaran_pabrik',
    'pembayaran_mitra',
    'pembayaran_petani',
    'pembelian_tbs',
    'hutang_pencairan',
    'hutang_pelunasan',
    'panjar_mitra',
    'biaya_operasional',
    'transfer_kas',
    'koreksi',
    'reversal',
    'lainnya'
  ) THEN
    RAISE EXCEPTION 'Sumber mutasi kas tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT *
    INTO v_existing
    FROM public.kas_ledger
    WHERE idempotency_key = p_idempotency_key
      AND status <> 'dibatalkan'
    LIMIT 1;

    IF v_existing.id IS NOT NULL THEN
      RETURN v_existing;
    END IF;
  END IF;

  IF v_rekening_id IS NULL THEN
    v_rekening_id := public.get_default_rekening_kas_id();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.rekening_kas WHERE id = v_rekening_id AND aktif = true
  ) THEN
    RAISE EXCEPTION 'Rekening kas tidak ditemukan atau tidak aktif.'
      USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.kas_ledger (
    rekening_kas_id,
    tanggal,
    tipe,
    sumber,
    jumlah,
    source_table,
    source_id,
    idempotency_key,
    keterangan,
    created_by
  )
  VALUES (
    v_rekening_id,
    COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    p_tipe,
    p_sumber,
    round(p_jumlah, 2),
    NULLIF(btrim(COALESCE(p_source_table, '')), ''),
    p_source_id,
    NULLIF(btrim(COALESCE(p_idempotency_key, '')), ''),
    NULLIF(btrim(COALESCE(p_keterangan, '')), ''),
    v_actor
  )
  RETURNING * INTO v_kas;

  RETURN v_kas;
END;
$$;


ALTER FUNCTION "public"."create_kas_mutasi"("p_tanggal" "date", "p_tipe" "text", "p_sumber" "text", "p_jumlah" numeric, "p_rekening_kas_id" "uuid", "p_keterangan" "text", "p_source_table" "text", "p_source_id" "uuid", "p_idempotency_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_panjar_mitra_kas"("p_mitra_id" "uuid", "p_tanggal" "date", "p_jumlah" numeric, "p_keterangan" "text" DEFAULT NULL::"text", "p_rekening_kas_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."panjar_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_panjar public.panjar_mitra%ROWTYPE;
  v_hutang public.hutang_ledger%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat panjar mitra.'
      USING ERRCODE = '42501';
  END IF;

  IF p_mitra_id IS NULL THEN
    RAISE EXCEPTION 'Mitra wajib dipilih.'
      USING ERRCODE = '22023';
  END IF;

  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
    RAISE EXCEPTION 'Jumlah panjar harus lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.panjar_mitra (
    tanggal,
    mitra_id,
    jumlah,
    keterangan,
    status,
    created_by
  )
  VALUES (
    COALESCE(p_tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    p_mitra_id,
    round(p_jumlah, 2),
    NULLIF(btrim(COALESCE(p_keterangan, '')), ''),
    'belum_lunas',
    v_actor
  )
  RETURNING * INTO v_panjar;

  SELECT *
  INTO v_hutang
  FROM public.create_hutang_pihak(
    'mitra',
    'debit',
    'panjar',
    v_panjar.jumlah,
    v_panjar.tanggal,
    NULL,
    p_mitra_id,
    NULL,
    NULL,
    COALESCE(v_panjar.keterangan, 'Panjar mitra'),
    p_rekening_kas_id,
    true,
    'panjar_mitra',
    v_panjar.id
  );

  UPDATE public.panjar_mitra
  SET rekening_kas_id = v_hutang.rekening_kas_id,
      kas_ledger_id = v_hutang.kas_ledger_id,
      hutang_ledger_id = v_hutang.id
  WHERE id = v_panjar.id
  RETURNING * INTO v_panjar;

  RETURN v_panjar;
END;
$$;


ALTER FUNCTION "public"."create_panjar_mitra_kas"("p_mitra_id" "uuid", "p_tanggal" "date", "p_jumlah" numeric, "p_keterangan" "text", "p_rekening_kas_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_pembayaran_mitra_kwitansi"("p_master_mitra_id" "uuid", "p_periode_dari" "date", "p_periode_sampai" "date", "p_metode_bayar" "text" DEFAULT 'tunai'::"text", "p_catatan" "text" DEFAULT NULL::"text", "p_master_mitra_ids" "uuid"[] DEFAULT NULL::"uuid"[], "p_penerima_label" "text" DEFAULT NULL::"text") RETURNS "public"."pembayaran_mitra_kwitansi"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_payment public.pembayaran_mitra_kwitansi%ROWTYPE;
  v_mitra_ids uuid[] := '{}'::uuid[];
  v_mitra_count integer := 0;
  v_found_mitra_count integer := 0;
  v_primary_mitra_id uuid;
  v_penerima_label text;
  v_jumlah_transaksi integer := 0;
  v_total_tonase numeric(15,2) := 0;
  v_total_nilai_bersih numeric(15,2) := 0;
  v_total_panjar numeric(15,2) := 0;
  v_total_sewa_armada numeric(15,2) := 0;
  v_nominal_dibayar numeric(15,2) := 0;
  v_panjar_ids uuid[] := '{}'::uuid[];
  v_panjar_snapshot jsonb := '[]'::jsonb;
  v_transaksi_snapshot jsonb := '[]'::jsonb;
  v_actor uuid := auth.uid();
  v_rekening_kas_id uuid;
  v_kas_ledger_id uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat pembayaran mitra.'
      USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT mitra_id), '{}'::uuid[])
  INTO v_mitra_ids
  FROM (
    SELECT unnest(COALESCE(p_master_mitra_ids, '{}'::uuid[])) AS mitra_id
    UNION ALL
    SELECT p_master_mitra_id
  ) selected
  WHERE mitra_id IS NOT NULL;

  v_mitra_count := COALESCE(array_length(v_mitra_ids, 1), 0);

  IF v_mitra_count <= 0 THEN
    RAISE EXCEPTION 'Minimal satu mitra wajib dipilih.'
      USING ERRCODE = '22023';
  END IF;

  SELECT count(*)::integer
  INTO v_found_mitra_count
  FROM public.master_mitra
  WHERE id = ANY(v_mitra_ids)
    AND COALESCE(aktif, true) = true;

  IF v_found_mitra_count <> v_mitra_count THEN
    RAISE EXCEPTION 'Ada mitra yang tidak ditemukan atau sudah tidak aktif.'
      USING ERRCODE = 'P0002';
  END IF;

  v_primary_mitra_id := COALESCE(p_master_mitra_id, v_mitra_ids[1]);

  SELECT COALESCE(
    NULLIF(btrim(COALESCE(p_penerima_label, '')), ''),
    string_agg(COALESCE(mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode), ', ' ORDER BY mm.kode, mm.nama)
  )
  INTO v_penerima_label
  FROM public.master_mitra mm
  WHERE mm.id = ANY(v_mitra_ids);

  IF p_periode_dari IS NULL OR p_periode_sampai IS NULL OR p_periode_sampai < p_periode_dari THEN
    RAISE EXCEPTION 'Periode pembayaran tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  IF COALESCE(p_metode_bayar, 'tunai') NOT IN ('tunai', 'transfer', 'lainnya') THEN
    RAISE EXCEPTION 'Metode bayar tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  WITH trx AS (
    SELECT
      tm.id,
      tm.mitra_id,
      COALESCE(mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode) AS mitra_label,
      tm.tanggal,
      tm.created_at,
      tm.sopir_aktual_nama,
      tm.sopir_default_nama,
      tm.plat_nomor,
      tm.tonase,
      tm.berat_netto_pabrik_kg,
      tm.potongan_pabrik_kg,
      tm.berat_dibayar_kg,
      tm.pakai_sewa_armada_bl,
      tm.biaya_sewa_armada_total,
      COALESCE(tm.harga_bersih_per_kg, tm.harga_harian, 0) AS harga_bersih_per_kg,
      COALESCE(tm.total_nilai_bersih, tm.total_kotor, 0) AS total_nilai_bersih,
      tm.status
    FROM public.transaksi_mitra tm
    LEFT JOIN public.master_mitra mm ON mm.id = tm.mitra_id
    WHERE tm.mitra_id = ANY(v_mitra_ids)
      AND tm.tanggal >= p_periode_dari
      AND tm.tanggal <= p_periode_sampai
      AND COALESCE(tm.status, 'aktif') <> 'dibatalkan'
      AND NOT EXISTS (
        SELECT 1
        FROM public.pembayaran_mitra_kwitansi_item item
        JOIN public.pembayaran_mitra_kwitansi pay ON pay.id = item.pembayaran_id
        WHERE item.transaksi_mitra_id = tm.id
          AND pay.status <> 'dibatalkan'
      )
  )
  SELECT
    COUNT(*)::integer,
    COALESCE(SUM(tonase), 0)::numeric(15,2),
    COALESCE(SUM(total_nilai_bersih), 0)::numeric(15,2),
    COALESCE(SUM(biaya_sewa_armada_total), 0)::numeric(15,2),
    COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', id,
        'master_mitra_id', mitra_id,
        'mitra_label', mitra_label,
        'tanggal', tanggal,
        'created_at', created_at,
        'sopir_aktual_nama', COALESCE(sopir_aktual_nama, sopir_default_nama),
        'plat_nomor', plat_nomor,
        'tonase', tonase,
        'berat_netto_pabrik_kg', berat_netto_pabrik_kg,
        'potongan_pabrik_kg', potongan_pabrik_kg,
        'berat_dibayar_kg', berat_dibayar_kg,
        'pakai_sewa_armada_bl', pakai_sewa_armada_bl,
        'biaya_sewa_armada_total', biaya_sewa_armada_total,
        'harga_bersih_per_kg', harga_bersih_per_kg,
        'total_nilai_bersih', total_nilai_bersih,
        'status', status
      )
      ORDER BY mitra_label, tanggal, created_at
    ), '[]'::jsonb)
  INTO v_jumlah_transaksi, v_total_tonase, v_total_nilai_bersih, v_total_sewa_armada, v_transaksi_snapshot
  FROM trx;

  IF v_jumlah_transaksi <= 0 THEN
    RAISE EXCEPTION 'Tidak ada transaksi baru yang belum dibayar pada periode ini.'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT
    COALESCE(SUM(pm.jumlah), 0)::numeric(15,2),
    COALESCE(array_agg(pm.id ORDER BY label.mitra_label, pm.tanggal, pm.created_at), '{}'::uuid[]),
    COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', pm.id,
        'master_mitra_id', pm.mitra_id,
        'mitra_label', label.mitra_label,
        'tanggal', pm.tanggal,
        'jumlah', pm.jumlah,
        'keterangan', pm.keterangan
      )
      ORDER BY label.mitra_label, pm.tanggal, pm.created_at
    ), '[]'::jsonb)
  INTO v_total_panjar, v_panjar_ids, v_panjar_snapshot
  FROM public.panjar_mitra pm
  LEFT JOIN LATERAL (
    SELECT COALESCE(mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode) AS mitra_label
    FROM public.master_mitra mm
    WHERE mm.id = pm.mitra_id
  ) label ON true
  WHERE pm.mitra_id = ANY(v_mitra_ids)
    AND pm.status = 'belum_lunas';

  IF v_total_panjar > v_total_nilai_bersih THEN
    RAISE EXCEPTION 'Total panjar melebihi nilai bersih kwitansi. Koreksi panjar dulu sebelum menandai dibayar.'
      USING ERRCODE = '22023';
  END IF;

  v_nominal_dibayar := v_total_nilai_bersih - v_total_panjar - v_total_sewa_armada;

  IF v_nominal_dibayar < 0 THEN
    RAISE EXCEPTION 'Nominal dibayar tidak boleh negatif (Panjar + Sewa Armada melebihi Nilai Bersih).'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.pembayaran_mitra_kwitansi (
    master_mitra_id,
    periode_dari,
    periode_sampai,
    status,
    tanggal_bayar,
    dibayar_at,
    metode_bayar,
    mode_pembayaran,
    mitra_ids,
    penerima_label,
    jumlah_mitra,
    total_tonase,
    total_nilai_bersih,
    total_panjar,
    total_sewa_armada,
    nominal_dibayar,
    jumlah_transaksi,
    panjar_ids,
    panjar_snapshot_json,
    transaksi_snapshot_json,
    catatan,
    created_by,
    updated_by
  )
  VALUES (
    v_primary_mitra_id,
    p_periode_dari,
    p_periode_sampai,
    'dibayar',
    (now() AT TIME ZONE 'Asia/Jakarta')::date,
    now(),
    COALESCE(p_metode_bayar, 'tunai'),
    CASE WHEN v_mitra_count > 1 THEN 'gabungan' ELSE 'single' END,
    v_mitra_ids,
    v_penerima_label,
    v_mitra_count,
    v_total_tonase,
    v_total_nilai_bersih,
    v_total_panjar,
    v_total_sewa_armada,
    v_nominal_dibayar,
    v_jumlah_transaksi,
    v_panjar_ids,
    v_panjar_snapshot,
    v_transaksi_snapshot,
    NULLIF(btrim(COALESCE(p_catatan, '')), ''),
    v_actor,
    v_actor
  )
  RETURNING * INTO v_payment;

  IF v_nominal_dibayar > 0 THEN
    v_rekening_kas_id := public.get_default_rekening_kas_id();

    INSERT INTO public.kas_ledger (
      rekening_kas_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      pembayaran_mitra_kwitansi_id,
      source_table,
      source_id,
      idempotency_key,
      keterangan,
      created_by
    )
    VALUES (
      v_rekening_kas_id,
      v_payment.tanggal_bayar,
      'keluar',
      'pembayaran_mitra',
      v_nominal_dibayar,
      v_payment.id,
      'pembayaran_mitra_kwitansi',
      v_payment.id,
      'pembayaran_mitra_kwitansi:' || v_payment.id::text,
      'Pembayaran kwitansi mitra periode ' || p_periode_dari::text || ' s/d ' || p_periode_sampai::text,
      v_actor
    )
    RETURNING id INTO v_kas_ledger_id;

    UPDATE public.pembayaran_mitra_kwitansi
    SET rekening_kas_id = v_rekening_kas_id,
        kas_ledger_id = v_kas_ledger_id
    WHERE id = v_payment.id
    RETURNING * INTO v_payment;
  END IF;

  INSERT INTO public.pembayaran_mitra_kwitansi_item (
    pembayaran_id,
    transaksi_mitra_id,
    master_mitra_id,
    mitra_label_snapshot,
    tanggal,
    waktu_transaksi,
    sopir_aktual_nama,
    plat_nomor,
    tonase_snapshot,
    berat_netto_snapshot,
    potongan_snapshot,
    berat_dibayar_snapshot,
    pakai_sewa_armada_snapshot,
    biaya_sewa_armada_snapshot,
    harga_bersih_per_kg_snapshot,
    total_nilai_bersih_snapshot,
    status_transaksi_snapshot
  )
  SELECT
    v_payment.id,
    tm.id,
    tm.mitra_id,
    COALESCE(mm.kode || ' - ' || COALESCE(mm.alamat, mm.nama), mm.nama, mm.kode),
    tm.tanggal,
    tm.created_at,
    COALESCE(tm.sopir_aktual_nama, tm.sopir_default_nama),
    tm.plat_nomor,
    tm.tonase,
    tm.berat_netto_pabrik_kg,
    tm.potongan_pabrik_kg,
    tm.berat_dibayar_kg,
    tm.pakai_sewa_armada_bl,
    tm.biaya_sewa_armada_total,
    COALESCE(tm.harga_bersih_per_kg, tm.harga_harian, 0),
    COALESCE(tm.total_nilai_bersih, tm.total_kotor, 0),
    COALESCE(tm.status, 'aktif')
  FROM public.transaksi_mitra tm
  LEFT JOIN public.master_mitra mm ON mm.id = tm.mitra_id
  WHERE tm.mitra_id = ANY(v_mitra_ids)
    AND tm.tanggal >= p_periode_dari
    AND tm.tanggal <= p_periode_sampai
    AND COALESCE(tm.status, 'aktif') <> 'dibatalkan'
    AND NOT EXISTS (
      SELECT 1
      FROM public.pembayaran_mitra_kwitansi_item item
      JOIN public.pembayaran_mitra_kwitansi pay ON pay.id = item.pembayaran_id
      WHERE item.transaksi_mitra_id = tm.id
        AND pay.status <> 'dibatalkan'
    )
  ORDER BY COALESCE(mm.kode, mm.nama), tm.tanggal, tm.created_at;

  INSERT INTO public.pembayaran_mitra_kwitansi_mitra (
    pembayaran_id,
    master_mitra_id,
    mitra_label_snapshot,
    total_tonase,
    total_nilai_bersih,
    jumlah_transaksi
  )
  SELECT
    v_payment.id,
    item.master_mitra_id,
    item.mitra_label_snapshot,
    COALESCE(SUM(item.tonase_snapshot), 0)::numeric(15,2),
    COALESCE(SUM(item.total_nilai_bersih_snapshot), 0)::numeric(15,2),
    COUNT(*)::integer
  FROM public.pembayaran_mitra_kwitansi_item item
  WHERE item.pembayaran_id = v_payment.id
  GROUP BY item.master_mitra_id, item.mitra_label_snapshot;

  UPDATE public.panjar_mitra
  SET status = 'lunas',
      pembayaran_mitra_kwitansi_id = v_payment.id,
      lunas_at = now()
  WHERE id = ANY(v_panjar_ids);

  RETURN v_payment;
END;
$$;


ALTER FUNCTION "public"."create_pembayaran_mitra_kwitansi"("p_master_mitra_id" "uuid", "p_periode_dari" "date", "p_periode_sampai" "date", "p_metode_bayar" "text", "p_catatan" "text", "p_master_mitra_ids" "uuid"[], "p_penerima_label" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_pembayaran_pabrik_batch"("p_pabrik_id" "uuid", "p_tanggal_bayar" "date", "p_metode_bayar" "text" DEFAULT 'transfer'::"text", "p_tonase_pabrik" numeric DEFAULT NULL::numeric, "p_harga_pabrik_per_kg" numeric DEFAULT NULL::numeric, "p_nominal_diterima" numeric DEFAULT NULL::numeric, "p_rekening_kas_id" "uuid" DEFAULT NULL::"uuid", "p_nomor_bukti" "text" DEFAULT NULL::"text", "p_catatan" "text" DEFAULT NULL::"text", "p_transaksi_ids" "uuid"[] DEFAULT '{}'::"uuid"[]) RETURNS "public"."pembayaran_pabrik_batch"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_ids uuid[] := '{}'::uuid[];
  v_expected_count integer := 0;
  v_found_count integer := 0;
  v_total_tonase_sistem numeric(15,2) := 0;
  v_total_nilai_sistem numeric(15,2) := 0;
  v_tonase_pabrik numeric(15,2) := round(COALESCE(p_tonase_pabrik, 0), 2);
  v_harga_pabrik numeric(15,2) := round(COALESCE(p_harga_pabrik_per_kg, 0), 2);
  v_total_nilai_pabrik numeric(15,2) := 0;
  v_nominal_diterima numeric(15,2);
  v_rekening_id uuid := p_rekening_kas_id;
  v_batch public.pembayaran_pabrik_batch%ROWTYPE;
  v_kas public.kas_ledger%ROWTYPE;
  v_allocated_total numeric(15,2) := 0;
  v_rounding_delta numeric(15,2) := 0;
  v_adjust_item_id uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang mencatat pembayaran pabrik.'
      USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT trx_id), '{}'::uuid[])
  INTO v_ids
  FROM unnest(COALESCE(p_transaksi_ids, '{}'::uuid[])) AS trx_id
  WHERE trx_id IS NOT NULL;

  v_expected_count := COALESCE(array_length(v_ids, 1), 0);

  IF v_tonase_pabrik <= 0 THEN
    RAISE EXCEPTION 'Tonase versi pabrik wajib lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF v_harga_pabrik <= 0 THEN
    RAISE EXCEPTION 'Harga pabrik per kg wajib lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF p_pabrik_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.pabrik WHERE id = p_pabrik_id AND COALESCE(aktif, true) = true
  ) THEN
    RAISE EXCEPTION 'Pabrik tujuan tidak ditemukan atau tidak aktif.'
      USING ERRCODE = 'P0002';
  END IF;

  IF p_metode_bayar NOT IN ('tunai', 'transfer', 'lainnya') THEN
    RAISE EXCEPTION 'Metode bayar tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  v_total_nilai_pabrik := round(v_tonase_pabrik * v_harga_pabrik, 0);
  v_nominal_diterima := round(COALESCE(p_nominal_diterima, v_total_nilai_pabrik), 2);

  IF v_nominal_diterima <= 0 THEN
    RAISE EXCEPTION 'Uang diterima dari pabrik harus lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF v_rekening_id IS NULL THEN
    v_rekening_id := public.get_default_rekening_kas_id();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.rekening_kas WHERE id = v_rekening_id AND aktif = true
  ) THEN
    RAISE EXCEPTION 'Rekening kas tidak ditemukan atau tidak aktif.'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_expected_count > 0 THEN
    PERFORM 1
    FROM public.transaksi_mitra tm
    WHERE tm.id = ANY(v_ids)
    FOR UPDATE;

    -- P0: gunakan berat_netto_pabrik_kg jika ada, fallback ke tonase lama.
    -- Total sistem dihitung dari berat netto (sisi pabrik), bukan berat dibayar.
    SELECT
      count(*),
      round(COALESCE(sum(COALESCE(tm.berat_netto_pabrik_kg, tm.tonase, 0)), 0), 2),
      round(COALESCE(sum(COALESCE(tm.berat_netto_pabrik_kg, tm.tonase, 0) * v_harga_pabrik), 0), 2)
    INTO v_found_count, v_total_tonase_sistem, v_total_nilai_sistem
    FROM public.transaksi_mitra tm
    WHERE tm.id = ANY(v_ids);

    IF v_found_count <> v_expected_count THEN
      RAISE EXCEPTION 'Sebagian data timbang tidak ditemukan.'
        USING ERRCODE = 'P0002';
    END IF;

    IF v_total_nilai_sistem <= 0 THEN
      RAISE EXCEPTION 'Nilai catatan kita harus lebih dari 0 sebelum data bisa dicocokkan.'
        USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.transaksi_mitra tm
      WHERE tm.id = ANY(v_ids)
        AND tm.status = 'dibatalkan'
    ) THEN
      RAISE EXCEPTION 'Data timbang yang sudah dibatalkan tidak bisa dicocokkan dengan pembayaran pabrik.'
        USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.pembayaran_pabrik_item item
      JOIN public.pembayaran_pabrik_batch batch ON batch.id = item.pembayaran_id
      WHERE item.transaksi_mitra_id = ANY(v_ids)
        AND item.status <> 'dibatalkan'
        AND batch.status <> 'dibatalkan'
    ) THEN
      RAISE EXCEPTION 'Ada data timbang yang sudah dicocokkan dengan pembayaran pabrik.'
        USING ERRCODE = '23505';
    END IF;
  END IF;

  INSERT INTO public.pembayaran_pabrik_batch (
    pabrik_id,
    tanggal_bayar,
    metode_bayar,
    nomor_bukti,
    status,
    total_tonase,
    total_tonase_sistem,
    selisih_tonase,
    harga_pabrik_per_kg,
    total_nilai_pabrik,
    total_diterima,
    total_selisih,
    jumlah_transaksi,
    rekening_kas_id,
    catatan,
    created_by,
    updated_by
  )
  VALUES (
    p_pabrik_id,
    COALESCE(p_tanggal_bayar, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    p_metode_bayar,
    NULLIF(btrim(COALESCE(p_nomor_bukti, '')), ''),
    'diterima',
    v_tonase_pabrik,
    v_total_tonase_sistem,
    round(v_tonase_pabrik - v_total_tonase_sistem, 2),
    v_harga_pabrik,
    v_total_nilai_pabrik,
    v_nominal_diterima,
    round(v_total_nilai_pabrik - v_nominal_diterima, 2),
    v_found_count,
    v_rekening_id,
    NULLIF(btrim(COALESCE(p_catatan, '')), ''),
    v_actor,
    v_actor
  )
  RETURNING * INTO v_batch;

  IF v_expected_count > 0 THEN
    -- P0: simpan berat_netto_snapshot dan berat_dibayar_snapshot per item.
    INSERT INTO public.pembayaran_pabrik_item (
      pembayaran_id,
      transaksi_mitra_id,
      master_mitra_id,
      tanggal,
      waktu_transaksi,
      mitra_label_snapshot,
      sopir_aktual_nama_snapshot,
      plat_nomor_snapshot,
      tonase_snapshot,
      berat_netto_snapshot,
      berat_dibayar_snapshot,
      harga_pabrik_per_kg_snapshot,
      total_nilai_pabrik_snapshot,
      jumlah_dialokasikan,
      status
    )
    SELECT
      v_batch.id,
      tm.id,
      tm.mitra_id,
      tm.tanggal,
      tm.created_at,
      COALESCE(mm.kode || ' - ' || mm.alamat, mm.kode, mm.nama, 'Tanpa mitra'),
      COALESCE(tm.sopir_aktual_nama, tm.sopir_default_nama),
      tm.plat_nomor,
      -- tonase_snapshot: berat netto dari pabrik (backward-compat label tetap "tonase")
      round(COALESCE(tm.berat_netto_pabrik_kg, tm.tonase, 0), 2),
      -- berat_netto_snapshot: eksplisit berat netto
      round(COALESCE(tm.berat_netto_pabrik_kg, tm.tonase, 0), 2),
      -- berat_dibayar_snapshot: berat setelah potongan
      round(COALESCE(tm.berat_dibayar_kg, tm.berat_netto_pabrik_kg, tm.tonase, 0), 2),
      v_harga_pabrik,
      -- nilai pabrik dihitung dari berat NETTO (ini yang dibayar pabrik ke owner)
      round(COALESCE(tm.berat_netto_pabrik_kg, tm.tonase, 0) * v_harga_pabrik, 2),
      round(
        v_nominal_diterima
        * (COALESCE(tm.berat_netto_pabrik_kg, tm.tonase, 0) * v_harga_pabrik)
        / NULLIF(v_total_nilai_sistem, 0),
        2
      ),
      'aktif'
    FROM public.transaksi_mitra tm
    LEFT JOIN public.master_mitra mm ON mm.id = tm.mitra_id
    WHERE tm.id = ANY(v_ids);

    SELECT COALESCE(sum(jumlah_dialokasikan), 0), min(id::text)::uuid
    INTO v_allocated_total, v_adjust_item_id
    FROM public.pembayaran_pabrik_item
    WHERE pembayaran_id = v_batch.id
      AND status = 'aktif';

    v_rounding_delta := round(v_nominal_diterima - v_allocated_total, 2);

    IF v_rounding_delta <> 0 AND v_adjust_item_id IS NOT NULL THEN
      UPDATE public.pembayaran_pabrik_item
      SET jumlah_dialokasikan = jumlah_dialokasikan + v_rounding_delta
      WHERE id = v_adjust_item_id;
    END IF;
  END IF;

  INSERT INTO public.kas_ledger (
    rekening_kas_id,
    tanggal,
    tipe,
    sumber,
    jumlah,
    source_table,
    source_id,
    idempotency_key,
    keterangan,
    created_by
  )
  VALUES (
    v_rekening_id,
    v_batch.tanggal_bayar,
    'masuk',
    'pembayaran_pabrik',
    v_nominal_diterima,
    'pembayaran_pabrik_batch',
    v_batch.id,
    'pembayaran_pabrik_batch:' || v_batch.id::text,
    'Pembayaran pabrik '
      || COALESCE(NULLIF(v_batch.nomor_bukti, ''), v_batch.id::text)
      || ' tonase pabrik '
      || v_tonase_pabrik::text
      || ' kg',
    v_actor
  )
  RETURNING * INTO v_kas;

  UPDATE public.pembayaran_pabrik_batch
  SET kas_ledger_id = v_kas.id,
      updated_at = now(),
      updated_by = v_actor
  WHERE id = v_batch.id
  RETURNING * INTO v_batch;

  IF v_expected_count > 0 THEN
    UPDATE public.transaksi_mitra tm
    SET pembayaran_pabrik_batch_id = v_batch.id,
        pembayaran_pabrik_item_id = item.id,
        pembayaran_pabrik_status = 'dibayar',
        pembayaran_pabrik_at = v_batch.diterima_at,
        updated_at = now(),
        updated_by = v_actor
    FROM public.pembayaran_pabrik_item item
    WHERE item.pembayaran_id = v_batch.id
      AND item.transaksi_mitra_id = tm.id
      AND item.status = 'aktif';
  END IF;

  RETURN v_batch;
END;
$$;


ALTER FUNCTION "public"."create_pembayaran_pabrik_batch"("p_pabrik_id" "uuid", "p_tanggal_bayar" "date", "p_metode_bayar" "text", "p_tonase_pabrik" numeric, "p_harga_pabrik_per_kg" numeric, "p_nominal_diterima" numeric, "p_rekening_kas_id" "uuid", "p_nomor_bukti" "text", "p_catatan" "text", "p_transaksi_ids" "uuid"[]) OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pengiriman" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tanggal" "date" NOT NULL,
    "sopir_id" "uuid",
    "kendaraan_id" "uuid",
    "pabrik_id" "uuid",
    "tonase_kirim" numeric(10,2) NOT NULL,
    "no_do" character varying(50),
    "status" "text" DEFAULT 'dikirim'::character varying,
    "harga_pabrik_per_kg" numeric(10,2),
    "total_harga_pabrik" numeric(15,2),
    "tanggal_bayar" "date",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "sumber" "text" DEFAULT 'lokal'::"text",
    "mitra_id" "uuid",
    "nomor_do" "text",
    "tonase_timbang_sumber" numeric(14,2),
    "tonase_pabrik" numeric(14,2),
    "tonase_dasar_settlement" numeric(14,2),
    "selisih_tonase" numeric(14,2),
    "nilai_selisih_tonase" numeric(15,2),
    "persen_selisih_ditanggung_perusahaan" numeric(5,2),
    "persen_selisih_ditanggung_mitra" numeric(5,2),
    "koreksi_selisih_dibayar_perusahaan" numeric(15,2) DEFAULT 0,
    "potongan_sortasi_type" "text" DEFAULT 'none'::"text",
    "potongan_sortasi_value" numeric(14,2) DEFAULT 0,
    "potongan_sortasi_rupiah" numeric(15,2) DEFAULT 0,
    "biaya_timbang" numeric(15,2) DEFAULT 0,
    "potongan_pabrik_lain" numeric(15,2) DEFAULT 0,
    "total_pembayaran_pabrik" numeric(15,2),
    "armada_type" "text" DEFAULT 'perusahaan'::"text",
    "armada_perusahaan_id" "uuid",
    "kendaraan_mitra_text" "text",
    "sopir_mitra_text" "text",
    "jarak_armada_km" numeric(12,2),
    "tonase_muatan_armada_ton" numeric(12,3),
    "tarif_armada_per_km_per_ton" numeric(15,2),
    "tarif_armada_source" "text",
    "alasan_override_tarif_armada" "text",
    "biaya_armada_dibebankan_ke_mitra" numeric(15,2) DEFAULT 0,
    "biaya_aktual_armada_perusahaan" numeric(15,2) DEFAULT 0,
    "settlement_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "pembayaran_pabrik_id" "uuid",
    "rekening_kas_id" "uuid",
    "kas_ledger_id" "uuid",
    CONSTRAINT "pengiriman_armada_type_check" CHECK (("armada_type" = ANY (ARRAY['perusahaan'::"text", 'mitra'::"text"]))),
    CONSTRAINT "pengiriman_sortasi_type_check" CHECK (("potongan_sortasi_type" = ANY (ARRAY['none'::"text", 'kg'::"text", 'percent'::"text", 'nominal'::"text"]))),
    CONSTRAINT "pengiriman_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'stok_siap_kirim'::"text", 'dikirim'::"text", 'diterima'::"text", 'diterima_pabrik'::"text", 'dibayar'::"text", 'dibayar_pabrik'::"text", 'selesai'::"text", 'dibatalkan'::"text", 'dikirim_mitra'::"text", 'menunggu_pembayaran_pabrik'::"text", 'sudah_dibayar_pabrik_ke_perusahaan'::"text", 'menunggu_pembayaran_mitra'::"text", 'pembayaran_mitra_sebagian_koreksi'::"text", 'settlement_lunas'::"text"]))),
    CONSTRAINT "pengiriman_sumber_check" CHECK (("sumber" = ANY (ARRAY['lokal'::"text", 'mitra'::"text"]))),
    CONSTRAINT "pengiriman_tarif_armada_source_check" CHECK ((("tarif_armada_source" IS NULL) OR ("tarif_armada_source" = ANY (ARRAY['default'::"text", 'override'::"text"]))))
);


ALTER TABLE "public"."pengiriman" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_pengiriman_lokal"("p_tanggal" "date", "p_pabrik_id" "uuid", "p_tonase_kirim_kg" numeric, "p_nomor_do" "text" DEFAULT NULL::"text", "p_sopir_id" "uuid" DEFAULT NULL::"uuid", "p_kendaraan_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."pengiriman"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_pengiriman public.pengiriman%ROWTYPE;
  v_total_stok numeric(14,2);
  v_sisa_alokasi numeric(14,2);
  v_alokasi numeric(14,2);
  v_nomor_do text := NULLIF(BTRIM(p_nomor_do), '');
  r record;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'User belum login';
  END IF;

  IF p_tanggal IS NULL THEN
    RAISE EXCEPTION 'Tanggal pengiriman wajib diisi';
  END IF;

  IF p_pabrik_id IS NULL THEN
    RAISE EXCEPTION 'Pabrik tujuan wajib diisi';
  END IF;

  IF p_tonase_kirim_kg IS NULL OR p_tonase_kirim_kg <= 0 THEN
    RAISE EXCEPTION 'Tonase kirim harus lebih besar dari 0';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.pabrik
    WHERE id = p_pabrik_id
      AND COALESCE(aktif, true) = true
  ) THEN
    RAISE EXCEPTION 'Pabrik tidak aktif atau tidak ditemukan';
  END IF;

  IF v_nomor_do IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.pengiriman
    WHERE pabrik_id = p_pabrik_id
      AND nomor_do = v_nomor_do
      AND status NOT IN ('draft', 'dibatalkan')
  ) THEN
    RAISE EXCEPTION 'Nomor DO sudah dipakai untuk pabrik ini';
  END IF;

  SELECT COALESCE(SUM(
    CASE
      WHEN tipe = 'masuk' THEN ABS(berat_kg)
      WHEN tipe = 'keluar' THEN -ABS(berat_kg)
      ELSE berat_kg
    END
  ), 0)
  INTO v_total_stok
  FROM public.stok_tbs_lokal_ledger;

  IF v_total_stok < p_tonase_kirim_kg THEN
    RAISE EXCEPTION 'Stok lokal tidak cukup. Sisa stok: %, tonase diminta: %', v_total_stok, p_tonase_kirim_kg;
  END IF;

  INSERT INTO public.pengiriman (
    tanggal,
    sopir_id,
    kendaraan_id,
    pabrik_id,
    tonase_kirim,
    no_do,
    status,
    created_by,
    sumber,
    nomor_do,
    tonase_timbang_sumber,
    armada_type,
    updated_at
  )
  VALUES (
    p_tanggal,
    p_sopir_id,
    p_kendaraan_id,
    p_pabrik_id,
    p_tonase_kirim_kg,
    v_nomor_do,
    'dikirim',
    v_actor,
    'lokal',
    v_nomor_do,
    p_tonase_kirim_kg,
    'perusahaan',
    NOW()
  )
  RETURNING * INTO v_pengiriman;

  v_sisa_alokasi := p_tonase_kirim_kg;

  FOR r IN
    SELECT
      t.id,
      t.petani_id,
      t.no_struk,
      t.berat_bersih_kg,
      (
        t.berat_bersih_kg
        - COALESCE((
          SELECT SUM(d.berat_alokasi_kg)
          FROM public.pengiriman_lokal_detail d
          JOIN public.pengiriman p ON p.id = d.pengiriman_id
          WHERE d.transaksi_beli_id = t.id
            AND p.status <> 'dibatalkan'
        ), 0)
      ) AS sisa_transaksi_kg
    FROM public.transaksi_beli_tbs t
    WHERE t.status = 'aktif'
    ORDER BY t.tanggal ASC, t.created_at ASC, t.id ASC
    FOR UPDATE OF t
  LOOP
    EXIT WHEN v_sisa_alokasi <= 0;
    CONTINUE WHEN r.sisa_transaksi_kg <= 0;

    v_alokasi := LEAST(v_sisa_alokasi, r.sisa_transaksi_kg);

    INSERT INTO public.pengiriman_lokal_detail (
      pengiriman_id,
      transaksi_beli_id,
      petani_id,
      berat_alokasi_kg
    )
    VALUES (
      v_pengiriman.id,
      r.id,
      r.petani_id,
      v_alokasi
    );

    INSERT INTO public.stok_tbs_lokal_ledger (
      tanggal,
      tipe,
      sumber,
      transaksi_beli_id,
      pengiriman_id,
      berat_kg,
      keterangan,
      created_by
    )
    VALUES (
      p_tanggal,
      'keluar',
      'pengiriman_pabrik',
      r.id,
      v_pengiriman.id,
      v_alokasi,
      'Alokasi FIFO ke DO ' || COALESCE(v_nomor_do, v_pengiriman.id::text),
      v_actor
    );

    v_sisa_alokasi := v_sisa_alokasi - v_alokasi;
  END LOOP;

  IF v_sisa_alokasi > 0 THEN
    RAISE EXCEPTION 'Stok transaksi belum cukup untuk alokasi FIFO. Sisa belum teralokasi: %', v_sisa_alokasi;
  END IF;

  PERFORM public.write_audit_log(
    'pengiriman',
    v_pengiriman.id,
    'create',
    NULL,
    to_jsonb(v_pengiriman),
    'Pengiriman lokal dibuat dengan alokasi FIFO'
  );

  RETURN v_pengiriman;
END;
$$;


ALTER FUNCTION "public"."create_pengiriman_lokal"("p_tanggal" "date", "p_pabrik_id" "uuid", "p_tonase_kirim_kg" numeric, "p_nomor_do" "text", "p_sopir_id" "uuid", "p_kendaraan_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_piutang_request"("p_pihak_type" "text", "p_jumlah" numeric, "p_tujuan" "text", "p_metode_pelunasan" "text", "p_tanggal" "date" DEFAULT NULL::"date", "p_tanggal_jatuh_tempo" "date" DEFAULT NULL::"date", "p_petani_id" "uuid" DEFAULT NULL::"uuid", "p_master_mitra_id" "uuid" DEFAULT NULL::"uuid", "p_sopir_id" "uuid" DEFAULT NULL::"uuid", "p_pihak_nama_manual" "text" DEFAULT NULL::"text", "p_catatan" "text" DEFAULT NULL::"text") RETURNS "public"."piutang_dokumen"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."create_piutang_request"("p_pihak_type" "text", "p_jumlah" numeric, "p_tujuan" "text", "p_metode_pelunasan" "text", "p_tanggal" "date", "p_tanggal_jatuh_tempo" "date", "p_petani_id" "uuid", "p_master_mitra_id" "uuid", "p_sopir_id" "uuid", "p_pihak_nama_manual" "text", "p_catatan" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_transaksi_beli_tbs"("p_petani_id" "uuid", "p_berat_kotor_kg" numeric, "p_potongan_percent" numeric DEFAULT 0, "p_potongan_hutang" numeric DEFAULT 0, "p_keterangan" "text" DEFAULT NULL::"text", "p_tanggal" "date" DEFAULT NULL::"date") RETURNS TABLE("id" "uuid", "tanggal" "date", "petani_id" "uuid", "petani_nama" "text", "berat_kotor_kg" numeric, "potongan_type" "text", "potongan_value" numeric, "berat_bersih_kg" numeric, "harga_per_kg" numeric, "total_harga" numeric, "potongan_hutang" numeric, "total_bayar_tunai" numeric, "no_struk" "text", "status" "text", "keterangan" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
#variable_conflict use_column
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
    RETURNING public.kas_ledger.id INTO v_kas_ledger_id;

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


ALTER FUNCTION "public"."create_transaksi_beli_tbs"("p_petani_id" "uuid", "p_berat_kotor_kg" numeric, "p_potongan_percent" numeric, "p_potongan_hutang" numeric, "p_keterangan" "text", "p_tanggal" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_app_role"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE(
    (SELECT role FROM public.users WHERE id = auth.uid()),
    'anonymous'
  );
$$;


ALTER FUNCTION "public"."current_app_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."disburse_piutang_document"("p_document_id" "uuid", "p_metode_penyerahan" "text", "p_nama_penerima" "text", "p_rekening_kas_id" "uuid" DEFAULT NULL::"uuid", "p_nomor_identitas" "text" DEFAULT NULL::"text") RETURNS "public"."piutang_dokumen"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."disburse_piutang_document"("p_document_id" "uuid", "p_metode_penyerahan" "text", "p_nama_penerima" "text", "p_rekening_kas_id" "uuid", "p_nomor_identitas" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enrich_kwitansi_panjar_snapshot_owner"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
BEGIN
  IF jsonb_typeof(NEW.panjar_snapshot_json) <> 'array' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      CASE
        WHEN panjar.mitra_id IS NOT NULL THEN
          item.value || jsonb_build_object(
            'master_mitra_id', panjar.mitra_id,
            'mitra_label', COALESCE(
              NULLIF(item.value ->> 'mitra_label', ''),
              NULLIF(concat_ws(' - ', mitra.kode, COALESCE(mitra.alamat, mitra.nama)), ''),
              mitra.nama,
              mitra.kode,
              'Mitra'
            )
          )
        ELSE item.value
      END
      ORDER BY item.ordinality
    ),
    '[]'::jsonb
  )
  INTO NEW.panjar_snapshot_json
  FROM jsonb_array_elements(NEW.panjar_snapshot_json)
    WITH ORDINALITY AS item(value, ordinality)
  LEFT JOIN public.panjar_mitra panjar
    ON panjar.id = CASE
      WHEN COALESCE(item.value ->> 'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        THEN (item.value ->> 'id')::uuid
      ELSE NULL
    END
  LEFT JOIN public.master_mitra mitra ON mitra.id = panjar.mitra_id;

  RETURN NEW;
END;
$_$;


ALTER FUNCTION "public"."enrich_kwitansi_panjar_snapshot_owner"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."flag_kwitansi_after_system_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."flag_kwitansi_after_system_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dashboard_pending_summary"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_unpaid_mitra bigint := 0;
  v_unpaid_weight numeric := 0;
  v_review bigint := 0;
  v_pending_mitra bigint := 0;
  v_pending_armada bigint := 0;
  v_pending_armada_trip bigint := 0;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional', 'admin_keuangan']) THEN
    RAISE EXCEPTION 'Tidak berwenang melihat antrian dashboard.' USING ERRCODE = '42501';
  END IF;

  SELECT count(DISTINCT transaction.mitra_id),
         COALESCE(sum(COALESCE(transaction.berat_dibayar_kg, transaction.tonase)), 0)
  INTO v_unpaid_mitra, v_unpaid_weight
  FROM public.transaksi_mitra transaction
  WHERE transaction.status <> 'dibatalkan'
    AND NOT EXISTS (
      SELECT 1 FROM public.pembayaran_mitra_kwitansi_item item
      JOIN public.pembayaran_mitra_kwitansi payment ON payment.id = item.pembayaran_id
      WHERE item.transaksi_mitra_id = transaction.id AND payment.status <> 'dibatalkan'
    );

  SELECT count(*) INTO v_review FROM public.pembayaran_mitra_kwitansi WHERE status = 'perlu_review';
  SELECT count(*) INTO v_pending_mitra FROM public.master_mitra WHERE status_verifikasi = 'perlu_verifikasi';
  SELECT count(*) INTO v_pending_armada FROM public.sopir WHERE aktif = true AND status_verifikasi = 'perlu_verifikasi';
  SELECT count(*) INTO v_pending_armada_trip
  FROM public.transaksi_mitra
  WHERE status = 'aktif' AND armada_cb_perlu_review = true;

  RETURN jsonb_build_object(
    'kwitansi_belum_dibayar', v_unpaid_mitra,
    'kwitansi_belum_dibayar_kg', v_unpaid_weight,
    'kwitansi_perlu_review', v_review,
    'mitra_perlu_verifikasi', v_pending_mitra,
    'armada_perlu_verifikasi', v_pending_armada,
    'trip_armada_cb_perlu_review', v_pending_armada_trip
  );
END;
$$;


ALTER FUNCTION "public"."get_dashboard_pending_summary"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_default_rekening_kas_id"() RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_rekening_id uuid;
BEGIN
  SELECT id
  INTO v_rekening_id
  FROM public.rekening_kas
  WHERE aktif = true
  ORDER BY is_default DESC, created_at ASC
  LIMIT 1;

  IF v_rekening_id IS NULL THEN
    INSERT INTO public.rekening_kas (nama, tipe, is_default, catatan, created_by)
    VALUES ('Kas Utama', 'kas', true, 'Dibuat otomatis saat transaksi kas pertama', auth.uid())
    RETURNING id INTO v_rekening_id;
  END IF;

  RETURN v_rekening_id;
END;
$$;


ALTER FUNCTION "public"."get_default_rekening_kas_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_kas_summary"("p_rekening_kas_id" "uuid" DEFAULT NULL::"uuid", "p_date_from" "date" DEFAULT NULL::"date", "p_date_to" "date" DEFAULT CURRENT_DATE) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."get_kas_summary"("p_rekening_kas_id" "uuid", "p_date_from" "date", "p_date_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_master_mitra_sensitive_changes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role text := public.current_app_role();
BEGIN
  IF auth.uid() IS NULL OR v_role IN ('owner', 'super_admin') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF COALESCE(NEW.fee_per_kg, 0) <> 0
       OR COALESCE(NEW.tarif_sewa_angkut_per_kg, 0) <> 0
       OR COALESCE(NEW.dana_operasional_trip, 0) <> 0 THEN
      RAISE EXCEPTION 'Tarif Mitra baru diisi oleh Owner setelah verifikasi.' USING ERRCODE = '42501';
    END IF;
    NEW.status_verifikasi := 'perlu_verifikasi';
    NEW.diverifikasi_oleh := NULL;
    NEW.diverifikasi_at := NULL;
    NEW.dibuat_oleh := auth.uid();
    RETURN NEW;
  END IF;

  IF OLD.aktif IS DISTINCT FROM NEW.aktif THEN
    RAISE EXCEPTION 'Penonaktifan Mitra memerlukan Owner.' USING ERRCODE = '42501';
  END IF;

  IF OLD.fee_per_kg IS DISTINCT FROM NEW.fee_per_kg
     OR OLD.tarif_sewa_angkut_per_kg IS DISTINCT FROM NEW.tarif_sewa_angkut_per_kg
     OR OLD.dana_operasional_trip IS DISTINCT FROM NEW.dana_operasional_trip THEN
    RAISE EXCEPTION 'Perubahan tarif memerlukan Owner.' USING ERRCODE = '42501';
  END IF;

  NEW.status_verifikasi := 'perlu_verifikasi';
  NEW.diverifikasi_oleh := NULL;
  NEW.diverifikasi_at := NULL;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."guard_master_mitra_sensitive_changes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_paid_transaksi_mitra_changes"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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
    OR OLD.kenakan_sewa_armada_cb IS DISTINCT FROM NEW.kenakan_sewa_armada_cb
    OR OLD.biaya_sewa_armada_total IS DISTINCT FROM NEW.biaya_sewa_armada_total
    OR OLD.status IS DISTINCT FROM NEW.status;

  v_armada_change :=
    OLD.tanggal IS DISTINCT FROM NEW.tanggal
    OR OLD.mitra_id IS DISTINCT FROM NEW.mitra_id
    OR OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
    OR OLD.sopir_aktual_id IS DISTINCT FROM NEW.sopir_aktual_id
    OR OLD.plat_nomor IS DISTINCT FROM NEW.plat_nomor
    OR OLD.menggunakan_armada_cb_snapshot IS DISTINCT FROM NEW.menggunakan_armada_cb_snapshot
    OR OLD.catat_dana_operasional_trip IS DISTINCT FROM NEW.catat_dana_operasional_trip
    OR OLD.dana_operasional_trip_snapshot IS DISTINCT FROM NEW.dana_operasional_trip_snapshot
    OR OLD.status IS DISTINCT FROM NEW.status;

  IF v_material_change AND EXISTS (
    SELECT 1
    FROM public.pembayaran_mitra_kwitansi_item item
    JOIN public.pembayaran_mitra_kwitansi payment ON payment.id = item.pembayaran_id
    WHERE item.transaksi_mitra_id = OLD.id AND payment.status <> 'dibatalkan'
  ) THEN
    RAISE EXCEPTION 'Transaksi sudah masuk kwitansi. Batalkan kwitansi melalui menu Kwitansi sebelum mengoreksi transaksi.'
      USING ERRCODE = '55000';
  END IF;

  IF v_material_change AND EXISTS (
    SELECT 1
    FROM public.pembayaran_pabrik_item item
    JOIN public.pembayaran_pabrik_batch payment ON payment.id = item.pembayaran_id
    WHERE item.transaksi_mitra_id = OLD.id AND payment.status <> 'dibatalkan'
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


ALTER FUNCTION "public"."guard_paid_transaksi_mitra_changes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_sopir_armada_verification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role text := public.current_app_role();
BEGIN
  IF auth.uid() IS NULL OR v_role IN ('owner', 'super_admin') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.status_verifikasi := 'perlu_verifikasi';
    NEW.diverifikasi_oleh := NULL;
    NEW.diverifikasi_at := NULL;
    NEW.dibuat_oleh := auth.uid();
    RETURN NEW;
  END IF;

  IF OLD.aktif IS DISTINCT FROM NEW.aktif THEN
    RAISE EXCEPTION 'Penonaktifan Sopir/Armada memerlukan Owner.' USING ERRCODE = '42501';
  END IF;

  NEW.status_verifikasi := 'perlu_verifikasi';
  NEW.diverifikasi_oleh := NULL;
  NEW.diverifikasi_at := NULL;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."guard_sopir_armada_verification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_app_role"("required_roles" "text"[]) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT public.current_app_role() = ANY(required_roles);
$$;


ALTER FUNCTION "public"."has_app_role"("required_roles" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."next_piutang_document_number"("p_prefix" "text" DEFAULT 'BPU'::"text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."next_piutang_document_number"("p_prefix" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_plat_nomor"("p_plat" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE PARALLEL SAFE
    AS $$
  SELECT upper(regexp_replace(COALESCE(p_plat, ''), '[^A-Za-z0-9]', '', 'g'));
$$;


ALTER FUNCTION "public"."normalize_plat_nomor"("p_plat" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_transaksi_mitra_armada_cb"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_sopir public.sopir%ROWTYPE;
  v_is_armada_cb boolean := false;
  v_berat_netto numeric(15,2) := 0;
  v_tarif_sewa numeric(15,2) := 0;
  v_tarif_sewa_mitra numeric(15,2) := 0;
  v_dana_trip numeric(15,2) := 0;
  v_refresh_snapshot boolean := false;
  v_control_changed boolean := false;
BEGIN
  SELECT * INTO v_sopir
  FROM public.sopir
  WHERE id = NEW.sopir_id;

  v_is_armada_cb := COALESCE(v_sopir.is_armada_cb, false);

  IF TG_OP = 'INSERT' THEN
    NEW.menggunakan_armada_cb_snapshot := v_is_armada_cb;
    NEW.armada_cb_perlu_review := false;
    NEW.alasan_review_armada_cb := NULL;
  ELSIF OLD.sopir_id IS DISTINCT FROM NEW.sopir_id THEN
    NEW.menggunakan_armada_cb_snapshot := v_is_armada_cb;
  END IF;

  v_control_changed := TG_OP = 'UPDATE' AND (
    OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
    OR OLD.kenakan_sewa_armada_cb IS DISTINCT FROM NEW.kenakan_sewa_armada_cb
    OR OLD.catat_dana_operasional_trip IS DISTINCT FROM NEW.catat_dana_operasional_trip
    OR OLD.alasan_tanpa_sewa_armada_cb IS DISTINCT FROM NEW.alasan_tanpa_sewa_armada_cb
    OR OLD.alasan_tanpa_dana_operasional_trip IS DISTINCT FROM NEW.alasan_tanpa_dana_operasional_trip
  );

  IF v_control_changed THEN
    NEW.armada_cb_perlu_review := false;
    NEW.alasan_review_armada_cb := NULL;
  END IF;

  IF NOT NEW.menggunakan_armada_cb_snapshot THEN
    NEW.kenakan_sewa_armada_cb := false;
    NEW.catat_dana_operasional_trip := false;
    NEW.alasan_tanpa_sewa_armada_cb := NULL;
    NEW.alasan_tanpa_dana_operasional_trip := NULL;
    NEW.armada_cb_perlu_review := false;
    NEW.alasan_review_armada_cb := NULL;
  ELSE
    IF NOT NEW.kenakan_sewa_armada_cb
       AND NULLIF(btrim(COALESCE(NEW.alasan_tanpa_sewa_armada_cb, '')), '') IS NULL THEN
      RAISE EXCEPTION 'Alasan tidak mengenakan sewa Armada CB wajib diisi.' USING ERRCODE = '22023';
    END IF;
    IF NOT NEW.catat_dana_operasional_trip
       AND NULLIF(btrim(COALESCE(NEW.alasan_tanpa_dana_operasional_trip, '')), '') IS NULL THEN
      RAISE EXCEPTION 'Alasan tidak membuat Dana Operasional Trip wajib diisi.' USING ERRCODE = '22023';
    END IF;
    IF NEW.kenakan_sewa_armada_cb THEN
      NEW.alasan_tanpa_sewa_armada_cb := NULL;
    END IF;
    IF NEW.catat_dana_operasional_trip THEN
      NEW.alasan_tanpa_dana_operasional_trip := NULL;
    END IF;
  END IF;

  -- Legacy compatibility: this field now means rent is charged, not trip use.
  NEW.pakai_sewa_armada_bl := NEW.menggunakan_armada_cb_snapshot
    AND NEW.kenakan_sewa_armada_cb;

  v_refresh_snapshot := TG_OP = 'INSERT';
  IF TG_OP = 'UPDATE' THEN
    v_refresh_snapshot := OLD.biaya_sopir_dibayar_at IS NULL AND (
      OLD.sopir_id IS DISTINCT FROM NEW.sopir_id
      OR OLD.mitra_id IS DISTINCT FROM NEW.mitra_id
      OR OLD.tanggal IS DISTINCT FROM NEW.tanggal
      OR OLD.kenakan_sewa_armada_cb IS DISTINCT FROM NEW.kenakan_sewa_armada_cb
      OR OLD.catat_dana_operasional_trip IS DISTINCT FROM NEW.catat_dana_operasional_trip
    );
  END IF;

  IF NEW.mitra_id IS NOT NULL THEN
    SELECT
      COALESCE(history.tarif_sewa_angkut_per_kg, mitra.tarif_sewa_angkut_per_kg, 0),
      COALESCE(history.dana_operasional_trip, mitra.dana_operasional_trip, 0)
    INTO v_tarif_sewa_mitra, v_dana_trip
    FROM public.master_mitra mitra
    LEFT JOIN LATERAL (
      SELECT fee.tarif_sewa_angkut_per_kg, fee.dana_operasional_trip
      FROM public.fee_owner_mitra_history fee
      WHERE fee.master_mitra_id = mitra.id
        AND fee.aktif = true
        AND fee.berlaku_mulai <= NEW.tanggal
        AND (fee.berlaku_sampai IS NULL OR fee.berlaku_sampai >= NEW.tanggal)
      ORDER BY fee.berlaku_mulai DESC, fee.created_at DESC
      LIMIT 1
    ) history ON true
    WHERE mitra.id = NEW.mitra_id;
  END IF;

  v_berat_netto := GREATEST(COALESCE(NEW.berat_netto_pabrik_kg, NEW.tonase, 0), 0);
  IF v_refresh_snapshot THEN
    v_tarif_sewa := GREATEST(COALESCE(v_tarif_sewa_mitra, 0), 0);
  ELSE
    v_tarif_sewa := GREATEST(COALESCE(
      NULLIF(NEW.tarif_sewa_angkut_per_kg_snapshot, 0),
      NULLIF(NEW.biaya_sewa_armada_per_kg, 0),
      v_tarif_sewa_mitra,
      0
    ), 0);
  END IF;

  IF NEW.menggunakan_armada_cb_snapshot AND NEW.kenakan_sewa_armada_cb THEN
    NEW.tarif_sewa_angkut_per_kg_snapshot := v_tarif_sewa;
    NEW.biaya_sewa_armada_per_kg := v_tarif_sewa;
    NEW.biaya_sewa_armada_kotor := round(v_berat_netto * v_tarif_sewa, 2);
    NEW.biaya_sewa_armada_total := NEW.biaya_sewa_armada_kotor;
  ELSE
    NEW.tarif_sewa_angkut_per_kg_snapshot := 0;
    NEW.biaya_sewa_armada_per_kg := 0;
    NEW.biaya_sewa_armada_kotor := 0;
    NEW.biaya_sewa_armada_total := 0;
  END IF;

  IF v_refresh_snapshot THEN
    IF NEW.menggunakan_armada_cb_snapshot AND NEW.catat_dana_operasional_trip THEN
      NEW.dana_operasional_trip_snapshot := GREATEST(COALESCE(v_dana_trip, 0), 0);
      NEW.upah_sopir_cb_snapshot := 0;
      NEW.uang_jalan_sopir_cb_snapshot := 0;
      NEW.total_biaya_sopir_cb_snapshot := NEW.dana_operasional_trip_snapshot;
      NEW.nominal_perongkosan_snapshot := 0;
    ELSE
      NEW.dana_operasional_trip_snapshot := 0;
      NEW.upah_sopir_cb_snapshot := 0;
      NEW.uang_jalan_sopir_cb_snapshot := 0;
      NEW.total_biaya_sopir_cb_snapshot := 0;
    END IF;
  ELSIF NOT NEW.catat_dana_operasional_trip THEN
    NEW.dana_operasional_trip_snapshot := 0;
    NEW.upah_sopir_cb_snapshot := 0;
    NEW.uang_jalan_sopir_cb_snapshot := 0;
    NEW.total_biaya_sopir_cb_snapshot := 0;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."normalize_transaksi_mitra_armada_cb"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_kwitansi_item_snapshot_update"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'Detail kwitansi yang sudah terbit tidak dapat diubah. Batalkan kwitansi dan terbitkan yang baru.'
      USING ERRCODE = '55000';
  END IF;
  RETURN OLD;
END;
$$;


ALTER FUNCTION "public"."prevent_kwitansi_item_snapshot_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recalculate_kwitansi_totals"("p_pembayaran_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."recalculate_kwitansi_totals"("p_pembayaran_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reconcile_legacy_panjar_opening"("p_panjar_id" "uuid", "p_alasan" "text") RETURNS "public"."hutang_ledger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.panjar_mitra%ROWTYPE;
  v_after public.panjar_mitra%ROWTYPE;
  v_settlement public.hutang_ledger%ROWTYPE;
  v_opening public.hutang_ledger%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR public.current_app_role() NOT IN ('owner', 'super_admin') THEN
    RAISE EXCEPTION 'Hanya Owner atau Super Admin yang dapat mencocokkan data lama.' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(btrim(COALESCE(p_alasan, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Dasar pencocokan wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before
  FROM public.panjar_mitra
  WHERE id = p_panjar_id
  FOR UPDATE;

  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Panjar lama tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF v_before.hutang_ledger_id IS NOT NULL THEN
    RAISE EXCEPTION 'Catatan pemberian pinjaman awal sudah tersedia.' USING ERRCODE = '22023';
  END IF;
  IF v_before.settlement_hutang_ledger_id IS NULL THEN
    RAISE EXCEPTION 'Panjar ini tidak memiliki catatan potongan kwitansi untuk dicocokkan.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_settlement
  FROM public.hutang_ledger
  WHERE id = v_before.settlement_hutang_ledger_id
  FOR UPDATE;

  IF v_settlement.id IS NULL
     OR v_settlement.status <> 'aktif'
     OR v_settlement.tipe <> 'kredit'
     OR v_settlement.master_mitra_id IS DISTINCT FROM v_before.mitra_id
     OR v_settlement.jumlah < v_before.jumlah THEN
    RAISE EXCEPTION 'Catatan potongan kwitansi tidak sesuai dengan panjar. Periksa kwitansi sebelum melanjutkan.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_opening
  FROM public.create_hutang_pihak(
    'mitra',
    'debit',
    'panjar',
    v_before.jumlah,
    v_before.tanggal,
    NULL,
    v_before.mitra_id,
    NULL,
    NULL,
    'Saldo awal pinjaman lama: ' || COALESCE(NULLIF(btrim(v_before.keterangan), ''), 'Panjar Mitra'),
    NULL,
    false,
    'panjar_mitra_opening_reconciliation',
    v_before.id
  );

  UPDATE public.panjar_mitra
  SET hutang_ledger_id = v_opening.id,
      updated_at = now()
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  PERFORM public.write_audit_log(
    'panjar_mitra',
    v_before.id,
    'reconcile_legacy_opening',
    to_jsonb(v_before),
    to_jsonb(v_after) || jsonb_build_object('opening_hutang_ledger_id', v_opening.id),
    btrim(p_alasan) || ' (tanpa mutasi Buku Kas)',
    v_actor
  );

  RETURN v_opening;
END;
$$;


ALTER FUNCTION "public"."reconcile_legacy_panjar_opening"("p_panjar_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_pengiriman_lokal_status"("p_pengiriman_id" "uuid", "p_status" "text", "p_tonase_pabrik" numeric, "p_harga_pabrik_per_kg" numeric DEFAULT NULL::numeric, "p_potongan_sortasi_type" "text" DEFAULT 'none'::"text", "p_potongan_sortasi_value" numeric DEFAULT 0, "p_biaya_timbang" numeric DEFAULT 0, "p_potongan_pabrik_lain" numeric DEFAULT 0, "p_tanggal_bayar" "date" DEFAULT NULL::"date", "p_rekening_kas_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."pengiriman"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_pengiriman public.pengiriman%ROWTYPE;
  v_after public.pengiriman%ROWTYPE;
  v_tonase_dasar numeric(14,2);
  v_bruto numeric(15,2) := 0;
  v_sortasi_rupiah numeric(15,2) := 0;
  v_total_pembayaran numeric(15,2) := 0;
  v_rekening_id uuid := p_rekening_kas_id;
  v_pembayaran_id uuid;
  v_kas_id uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang memperbarui pengiriman lokal.'
      USING ERRCODE = '42501';
  END IF;

  IF p_status NOT IN ('diterima_pabrik', 'dibayar_pabrik') THEN
    RAISE EXCEPTION 'Status pengiriman tidak valid untuk aksi ini.'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_pengiriman
  FROM public.pengiriman
  WHERE id = p_pengiriman_id
  FOR UPDATE;

  IF v_pengiriman.id IS NULL THEN
    RAISE EXCEPTION 'Pengiriman tidak ditemukan.'
      USING ERRCODE = 'P0002';
  END IF;

  IF COALESCE(v_pengiriman.status, '') IN ('dibayar_pabrik', 'dibayar', 'selesai', 'dibatalkan') THEN
    RAISE EXCEPTION 'Pengiriman sudah final atau dibatalkan.'
      USING ERRCODE = '22023';
  END IF;

  IF p_tonase_pabrik IS NULL OR p_tonase_pabrik <= 0 THEN
    RAISE EXCEPTION 'Tonase pabrik wajib lebih dari 0.'
      USING ERRCODE = '22023';
  END IF;

  IF p_potongan_sortasi_type NOT IN ('none', 'kg', 'percent', 'nominal') THEN
    RAISE EXCEPTION 'Tipe potongan sortasi tidak valid.'
      USING ERRCODE = '22023';
  END IF;

  v_tonase_dasar := CASE
    WHEN p_potongan_sortasi_type = 'kg' THEN GREATEST(p_tonase_pabrik - COALESCE(p_potongan_sortasi_value, 0), 0)
    ELSE p_tonase_pabrik
  END;

  IF p_status = 'dibayar_pabrik' THEN
    IF p_harga_pabrik_per_kg IS NULL OR p_harga_pabrik_per_kg <= 0 THEN
      RAISE EXCEPTION 'Harga pabrik wajib lebih dari 0 saat status dibayar.'
        USING ERRCODE = '22023';
    END IF;

    IF v_rekening_id IS NULL THEN
      v_rekening_id := public.get_default_rekening_kas_id();
    END IF;

    v_bruto := round(v_tonase_dasar * p_harga_pabrik_per_kg, 0);
    v_sortasi_rupiah := CASE
      WHEN p_potongan_sortasi_type = 'percent' THEN round(v_bruto * (COALESCE(p_potongan_sortasi_value, 0) / 100), 0)
      WHEN p_potongan_sortasi_type = 'nominal' THEN round(COALESCE(p_potongan_sortasi_value, 0), 0)
      ELSE 0
    END;
    v_total_pembayaran := GREATEST(
      v_bruto - v_sortasi_rupiah - COALESCE(p_biaya_timbang, 0) - COALESCE(p_potongan_pabrik_lain, 0),
      0
    );

    IF v_total_pembayaran <= 0 THEN
      RAISE EXCEPTION 'Total pembayaran pabrik harus lebih dari 0.'
        USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.pembayaran_pabrik (
      pabrik_id,
      tanggal_bayar,
      total_bayar,
      metode,
      status,
      keterangan,
      rekening_kas_id,
      created_by
    )
    VALUES (
      v_pengiriman.pabrik_id,
      COALESCE(p_tanggal_bayar, (now() AT TIME ZONE 'Asia/Jakarta')::date),
      v_total_pembayaran,
      'transfer/tunai',
      'teralokasi_penuh',
      'Pembayaran pabrik untuk DO ' || COALESCE(v_pengiriman.nomor_do, v_pengiriman.no_do, v_pengiriman.id::text),
      v_rekening_id,
      v_actor
    )
    RETURNING id INTO v_pembayaran_id;

    INSERT INTO public.pembayaran_pabrik_detail (
      pembayaran_pabrik_id,
      pengiriman_id,
      nomor_do,
      jumlah_dialokasikan,
      tonase_pabrik,
      tonase_dasar_settlement,
      harga_pabrik_per_kg,
      potongan_sortasi_type,
      potongan_sortasi_value,
      potongan_sortasi_rupiah,
      biaya_timbang,
      potongan_pabrik_lain
    )
    VALUES (
      v_pembayaran_id,
      v_pengiriman.id,
      COALESCE(v_pengiriman.nomor_do, v_pengiriman.no_do),
      v_total_pembayaran,
      round(p_tonase_pabrik, 2),
      v_tonase_dasar,
      p_harga_pabrik_per_kg,
      p_potongan_sortasi_type,
      COALESCE(p_potongan_sortasi_value, 0),
      v_sortasi_rupiah,
      COALESCE(p_biaya_timbang, 0),
      COALESCE(p_potongan_pabrik_lain, 0)
    );

    INSERT INTO public.kas_ledger (
      rekening_kas_id,
      tanggal,
      tipe,
      sumber,
      jumlah,
      pengiriman_id,
      pembayaran_pabrik_id,
      source_table,
      source_id,
      idempotency_key,
      keterangan,
      created_by
    )
    VALUES (
      v_rekening_id,
      COALESCE(p_tanggal_bayar, (now() AT TIME ZONE 'Asia/Jakarta')::date),
      'masuk',
      'pembayaran_pabrik',
      v_total_pembayaran,
      v_pengiriman.id,
      v_pembayaran_id,
      'pengiriman',
      v_pengiriman.id,
      'pengiriman:' || v_pengiriman.id::text || ':pembayaran_pabrik',
      'Pembayaran pabrik DO ' || COALESCE(v_pengiriman.nomor_do, v_pengiriman.no_do, '-'),
      v_actor
    )
    RETURNING id INTO v_kas_id;

    UPDATE public.pembayaran_pabrik
    SET kas_ledger_id = v_kas_id
    WHERE id = v_pembayaran_id;
  END IF;

  UPDATE public.pengiriman
  SET status = p_status,
      tonase_pabrik = round(p_tonase_pabrik, 2),
      tonase_dasar_settlement = v_tonase_dasar,
      harga_pabrik_per_kg = CASE WHEN p_status = 'dibayar_pabrik' THEN p_harga_pabrik_per_kg ELSE harga_pabrik_per_kg END,
      potongan_sortasi_type = CASE WHEN p_status = 'dibayar_pabrik' THEN p_potongan_sortasi_type ELSE potongan_sortasi_type END,
      potongan_sortasi_value = CASE WHEN p_status = 'dibayar_pabrik' THEN COALESCE(p_potongan_sortasi_value, 0) ELSE potongan_sortasi_value END,
      potongan_sortasi_rupiah = CASE WHEN p_status = 'dibayar_pabrik' THEN v_sortasi_rupiah ELSE potongan_sortasi_rupiah END,
      biaya_timbang = CASE WHEN p_status = 'dibayar_pabrik' THEN COALESCE(p_biaya_timbang, 0) ELSE biaya_timbang END,
      potongan_pabrik_lain = CASE WHEN p_status = 'dibayar_pabrik' THEN COALESCE(p_potongan_pabrik_lain, 0) ELSE potongan_pabrik_lain END,
      total_pembayaran_pabrik = CASE WHEN p_status = 'dibayar_pabrik' THEN v_total_pembayaran ELSE total_pembayaran_pabrik END,
      total_harga_pabrik = CASE WHEN p_status = 'dibayar_pabrik' THEN v_total_pembayaran ELSE total_harga_pabrik END,
      tanggal_bayar = CASE WHEN p_status = 'dibayar_pabrik' THEN COALESCE(p_tanggal_bayar, (now() AT TIME ZONE 'Asia/Jakarta')::date) ELSE tanggal_bayar END,
      pembayaran_pabrik_id = CASE WHEN p_status = 'dibayar_pabrik' THEN v_pembayaran_id ELSE pembayaran_pabrik_id END,
      rekening_kas_id = CASE WHEN p_status = 'dibayar_pabrik' THEN v_rekening_id ELSE rekening_kas_id END,
      kas_ledger_id = CASE WHEN p_status = 'dibayar_pabrik' THEN v_kas_id ELSE kas_ledger_id END,
      updated_at = now()
  WHERE id = v_pengiriman.id
  RETURNING * INTO v_after;

  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."record_pengiriman_lokal_status"("p_pengiriman_id" "uuid", "p_status" "text", "p_tonase_pabrik" numeric, "p_harga_pabrik_per_kg" numeric, "p_potongan_sortasi_type" "text", "p_potongan_sortasi_value" numeric, "p_biaya_timbang" numeric, "p_potongan_pabrik_lain" numeric, "p_tanggal_bayar" "date", "p_rekening_kas_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_piutang_repayment"("p_document_id" "uuid", "p_jumlah" numeric, "p_metode" "text", "p_tanggal" "date" DEFAULT NULL::"date", "p_keterangan" "text" DEFAULT NULL::"text", "p_rekening_kas_id" "uuid" DEFAULT NULL::"uuid") RETURNS "public"."piutang_pelunasan"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."record_piutang_repayment"("p_document_id" "uuid", "p_jumlah" numeric, "p_metode" "text", "p_tanggal" "date", "p_keterangan" "text", "p_rekening_kas_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."require_factory_payment_proof"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF COALESCE(NEW.metode_bayar, '') = 'transfer'
     AND NULLIF(btrim(COALESCE(NEW.nomor_bukti, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Nomor bukti transfer wajib diisi.' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."require_factory_payment_proof"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_dana_operasional_trip_mitra"("p_mitra_id" "uuid", "p_tanggal" "date") RETURNS numeric
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
  SELECT GREATEST(COALESCE(
    (
      SELECT fh.dana_operasional_trip
      FROM public.fee_owner_mitra_history fh
      WHERE fh.master_mitra_id = p_mitra_id
        AND fh.aktif = true
        AND fh.berlaku_mulai <= p_tanggal
        AND (fh.berlaku_sampai IS NULL OR fh.berlaku_sampai >= p_tanggal)
      ORDER BY fh.berlaku_mulai DESC, fh.created_at DESC
      LIMIT 1
    ),
    (SELECT mm.dana_operasional_trip FROM public.master_mitra mm WHERE mm.id = p_mitra_id),
    0
  ), 0);
$$;


ALTER FUNCTION "public"."resolve_dana_operasional_trip_mitra"("p_mitra_id" "uuid", "p_tanggal" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."review_piutang_request"("p_document_id" "uuid", "p_action" "text", "p_catatan" "text" DEFAULT NULL::"text") RETURNS "public"."piutang_dokumen"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."review_piutang_request"("p_document_id" "uuid", "p_action" "text", "p_catatan" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."master_mitra" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nama" character varying(100) NOT NULL,
    "penanggung_jawab" character varying(100),
    "no_hp" character varying(20),
    "alamat" "text",
    "fee_per_kg" numeric(10,2) DEFAULT 0,
    "aktif" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "kode" character varying(20),
    "tipe_mitra" "text" DEFAULT 'eksternal'::"text" NOT NULL,
    "tarif_sewa_angkut_per_kg" numeric(12,2) DEFAULT 0,
    "nominal_perongkosan" numeric(15,2) DEFAULT 0,
    "dana_operasional_trip" numeric(15,2) DEFAULT 0 NOT NULL,
    "status_verifikasi" "text" DEFAULT 'terverifikasi'::"text" NOT NULL,
    "dibuat_oleh" "uuid",
    "diverifikasi_oleh" "uuid",
    "diverifikasi_at" timestamp with time zone,
    "catatan_verifikasi" "text",
    CONSTRAINT "master_mitra_dana_operasional_trip_nonnegative" CHECK (("dana_operasional_trip" >= (0)::numeric)),
    CONSTRAINT "master_mitra_status_verifikasi_check" CHECK (("status_verifikasi" = ANY (ARRAY['perlu_verifikasi'::"text", 'terverifikasi'::"text"]))),
    CONSTRAINT "master_mitra_tipe_mitra_check" CHECK (("tipe_mitra" = ANY (ARRAY['eksternal'::"text", 'internal_owner'::"text"])))
);


ALTER TABLE "public"."master_mitra" OWNER TO "postgres";


COMMENT ON COLUMN "public"."master_mitra"."tarif_sewa_angkut_per_kg" IS 'Tarif sewa armada kotor per kg untuk mitra (jika menggunakan Armada CB)';



COMMENT ON COLUMN "public"."master_mitra"."nominal_perongkosan" IS 'Nominal flat (Rp) perongkosan per trip/transaksi yang mengurangi sewa armada kotor';



COMMENT ON COLUMN "public"."master_mitra"."dana_operasional_trip" IS 'Dana flat satu kali jalan Armada CB untuk mitra ini; mencakup solar, makan, uang jalan, dan bagian sopir.';



CREATE OR REPLACE FUNCTION "public"."save_master_mitra"("p_id" "uuid" DEFAULT NULL::"uuid", "p_kode" "text" DEFAULT NULL::"text", "p_nama" "text" DEFAULT NULL::"text", "p_penanggung_jawab" "text" DEFAULT NULL::"text", "p_no_hp" "text" DEFAULT NULL::"text", "p_alamat" "text" DEFAULT NULL::"text", "p_tipe_mitra" "text" DEFAULT 'eksternal'::"text", "p_fee_per_kg" numeric DEFAULT 0, "p_tarif_sewa_angkut_per_kg" numeric DEFAULT 0, "p_dana_operasional_trip" numeric DEFAULT 0, "p_berlaku_mulai" "date" DEFAULT CURRENT_DATE, "p_alasan_perubahan" "text" DEFAULT NULL::"text") RETURNS "public"."master_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_role text := public.current_app_role();
  v_before public.master_mitra%ROWTYPE;
  v_after public.master_mitra%ROWTYPE;
  v_can_set_tariff boolean;
  v_fee numeric := GREATEST(COALESCE(p_fee_per_kg, 0), 0);
  v_sewa numeric := GREATEST(COALESCE(p_tarif_sewa_angkut_per_kg, 0), 0);
  v_dana numeric := GREATEST(COALESCE(p_dana_operasional_trip, 0), 0);
  v_next_start date;
BEGIN
  IF v_actor IS NULL OR v_role NOT IN ('owner', 'super_admin', 'admin_operasional') THEN
    RAISE EXCEPTION 'Tidak berwenang menyimpan Mitra.' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_kode, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_nama, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Kode dan nama Mitra wajib diisi.' USING ERRCODE = '22023';
  END IF;

  IF COALESCE(p_tipe_mitra, 'eksternal') NOT IN ('eksternal', 'internal_owner') THEN
    RAISE EXCEPTION 'Tipe Mitra tidak valid.' USING ERRCODE = '22023';
  END IF;

  v_can_set_tariff := v_role IN ('owner', 'super_admin');

  IF p_id IS NOT NULL THEN
    SELECT * INTO v_before FROM public.master_mitra WHERE id = p_id FOR UPDATE;
    IF v_before.id IS NULL THEN
      RAISE EXCEPTION 'Mitra tidak ditemukan.' USING ERRCODE = 'P0002';
    END IF;

    IF NOT v_can_set_tariff AND (
      round(v_fee, 2) IS DISTINCT FROM round(COALESCE(v_before.fee_per_kg, 0), 2)
      OR round(v_sewa, 2) IS DISTINCT FROM round(COALESCE(v_before.tarif_sewa_angkut_per_kg, 0), 2)
      OR round(v_dana, 2) IS DISTINCT FROM round(COALESCE(v_before.dana_operasional_trip, 0), 2)
    ) THEN
      RAISE EXCEPTION 'Perubahan tarif hanya dapat dilakukan Owner.' USING ERRCODE = '42501';
    END IF;

    UPDATE public.master_mitra
    SET kode = upper(btrim(p_kode)),
        nama = btrim(p_nama),
        penanggung_jawab = NULLIF(btrim(COALESCE(p_penanggung_jawab, '')), ''),
        no_hp = NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
        alamat = NULLIF(btrim(COALESCE(p_alamat, '')), ''),
        tipe_mitra = COALESCE(p_tipe_mitra, 'eksternal'),
        fee_per_kg = CASE WHEN v_can_set_tariff THEN v_fee ELSE fee_per_kg END,
        tarif_sewa_angkut_per_kg = CASE WHEN v_can_set_tariff THEN v_sewa ELSE tarif_sewa_angkut_per_kg END,
        dana_operasional_trip = CASE WHEN v_can_set_tariff THEN v_dana ELSE dana_operasional_trip END,
        status_verifikasi = CASE WHEN v_can_set_tariff THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
        diverifikasi_oleh = CASE WHEN v_can_set_tariff THEN v_actor ELSE NULL END,
        diverifikasi_at = CASE WHEN v_can_set_tariff THEN now() ELSE NULL END
    WHERE id = p_id
    RETURNING * INTO v_after;
  ELSE
    IF NOT v_can_set_tariff AND (v_fee > 0 OR v_sewa > 0 OR v_dana > 0) THEN
      RAISE EXCEPTION 'Admin dapat membuat Mitra baru dengan tarif Rp0. Owner mengisi tarif setelah verifikasi.'
        USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.master_mitra (
      kode, nama, penanggung_jawab, no_hp, alamat, tipe_mitra,
      fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip,
      aktif, dibuat_oleh, status_verifikasi, diverifikasi_oleh, diverifikasi_at
    ) VALUES (
      upper(btrim(p_kode)), btrim(p_nama),
      NULLIF(btrim(COALESCE(p_penanggung_jawab, '')), ''),
      NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
      NULLIF(btrim(COALESCE(p_alamat, '')), ''),
      COALESCE(p_tipe_mitra, 'eksternal'),
      CASE WHEN v_can_set_tariff THEN v_fee ELSE 0 END,
      CASE WHEN v_can_set_tariff THEN v_sewa ELSE 0 END,
      CASE WHEN v_can_set_tariff THEN v_dana ELSE 0 END,
      true, v_actor,
      CASE WHEN v_can_set_tariff THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
      CASE WHEN v_can_set_tariff THEN v_actor ELSE NULL END,
      CASE WHEN v_can_set_tariff THEN now() ELSE NULL END
    )
    RETURNING * INTO v_after;
  END IF;

  IF v_can_set_tariff THEN
    SELECT min(berlaku_mulai)
    INTO v_next_start
    FROM public.fee_owner_mitra_history
    WHERE master_mitra_id = v_after.id
      AND aktif = true
      AND berlaku_mulai > COALESCE(p_berlaku_mulai, CURRENT_DATE);

    UPDATE public.fee_owner_mitra_history
    SET berlaku_sampai = COALESCE(p_berlaku_mulai, CURRENT_DATE) - 1
    WHERE master_mitra_id = v_after.id
      AND aktif = true
      AND berlaku_mulai < COALESCE(p_berlaku_mulai, CURRENT_DATE)
      AND (berlaku_sampai IS NULL OR berlaku_sampai >= COALESCE(p_berlaku_mulai, CURRENT_DATE));

    INSERT INTO public.fee_owner_mitra_history (
      master_mitra_id, fee_per_kg, tarif_sewa_angkut_per_kg,
      dana_operasional_trip, berlaku_mulai, berlaku_sampai,
      aktif, alasan_perubahan, created_by
    ) VALUES (
      v_after.id, v_fee, v_sewa, v_dana,
      COALESCE(p_berlaku_mulai, CURRENT_DATE),
      CASE WHEN v_next_start IS NULL THEN NULL ELSE v_next_start - 1 END,
      true,
      COALESCE(NULLIF(btrim(COALESCE(p_alasan_perubahan, '')), ''), 'Perubahan tarif dari Master Mitra'),
      v_actor
    )
    ON CONFLICT (master_mitra_id, berlaku_mulai)
    DO UPDATE SET
      fee_per_kg = EXCLUDED.fee_per_kg,
      tarif_sewa_angkut_per_kg = EXCLUDED.tarif_sewa_angkut_per_kg,
      dana_operasional_trip = EXCLUDED.dana_operasional_trip,
      berlaku_sampai = EXCLUDED.berlaku_sampai,
      aktif = true,
      alasan_perubahan = EXCLUDED.alasan_perubahan;
  END IF;

  PERFORM public.write_audit_log(
    'master_mitra', v_after.id,
    CASE WHEN p_id IS NULL THEN 'create' ELSE 'update' END,
    CASE WHEN p_id IS NULL THEN NULL ELSE to_jsonb(v_before) END,
    to_jsonb(v_after),
    p_alasan_perubahan,
    CASE WHEN v_can_set_tariff THEN v_actor ELSE NULL END
  );

  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."save_master_mitra"("p_id" "uuid", "p_kode" "text", "p_nama" "text", "p_penanggung_jawab" "text", "p_no_hp" "text", "p_alamat" "text", "p_tipe_mitra" "text", "p_fee_per_kg" numeric, "p_tarif_sewa_angkut_per_kg" numeric, "p_dana_operasional_trip" numeric, "p_berlaku_mulai" "date", "p_alasan_perubahan" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pabrik" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nama" character varying(100) NOT NULL,
    "alamat" "text",
    "no_hp" character varying(20),
    "aktif" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "kontak" character varying(100),
    "harga_pabrik_per_kg" numeric(12,2),
    "pola_pembayaran" "text" DEFAULT 'per_do'::"text",
    "rekening_info" "text",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "dibuat_oleh" "uuid",
    "status_verifikasi" "text" DEFAULT 'terverifikasi'::"text" NOT NULL,
    "diverifikasi_oleh" "uuid",
    "diverifikasi_at" timestamp with time zone,
    "catatan_verifikasi" "text",
    CONSTRAINT "pabrik_status_verifikasi_check" CHECK (("status_verifikasi" = ANY (ARRAY['perlu_verifikasi'::"text", 'terverifikasi'::"text"])))
);


ALTER TABLE "public"."pabrik" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_pabrik_master"("p_id" "uuid" DEFAULT NULL::"uuid", "p_nama" "text" DEFAULT NULL::"text", "p_alamat" "text" DEFAULT NULL::"text", "p_no_hp" "text" DEFAULT NULL::"text") RETURNS "public"."pabrik"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_role text := public.current_app_role();
  v_before public.pabrik%ROWTYPE;
  v_after public.pabrik%ROWTYPE;
  v_is_approver boolean := v_role IN ('owner', 'super_admin');
BEGIN
  IF v_actor IS NULL OR v_role NOT IN ('owner', 'super_admin', 'admin_operasional') THEN
    RAISE EXCEPTION 'Tidak berwenang menyimpan Pabrik.' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_nama, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Nama Pabrik wajib diisi.' USING ERRCODE = '22023';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.pabrik (
      nama, alamat, no_hp, aktif, dibuat_oleh,
      status_verifikasi, diverifikasi_oleh, diverifikasi_at
    ) VALUES (
      btrim(p_nama),
      NULLIF(btrim(COALESCE(p_alamat, '')), ''),
      NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
      true,
      v_actor,
      CASE WHEN v_is_approver THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
      CASE WHEN v_is_approver THEN v_actor ELSE NULL END,
      CASE WHEN v_is_approver THEN now() ELSE NULL END
    )
    RETURNING * INTO v_after;
  ELSE
    SELECT * INTO v_before FROM public.pabrik WHERE id = p_id FOR UPDATE;
    IF v_before.id IS NULL THEN
      RAISE EXCEPTION 'Pabrik tidak ditemukan.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.pabrik
    SET nama = btrim(p_nama),
        alamat = NULLIF(btrim(COALESCE(p_alamat, '')), ''),
        no_hp = NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
        status_verifikasi = CASE WHEN v_is_approver THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
        diverifikasi_oleh = CASE WHEN v_is_approver THEN v_actor ELSE NULL END,
        diverifikasi_at = CASE WHEN v_is_approver THEN now() ELSE NULL END,
        catatan_verifikasi = NULL
    WHERE id = p_id
    RETURNING * INTO v_after;
  END IF;

  PERFORM public.write_audit_log(
    'pabrik', v_after.id,
    CASE WHEN p_id IS NULL THEN 'create' ELSE 'update' END,
    CASE WHEN p_id IS NULL THEN NULL ELSE to_jsonb(v_before) END,
    to_jsonb(v_after),
    CASE WHEN v_is_approver THEN NULL ELSE 'Menunggu verifikasi Owner' END,
    CASE WHEN v_is_approver THEN v_actor ELSE NULL END
  );

  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."save_pabrik_master"("p_id" "uuid", "p_nama" "text", "p_alamat" "text", "p_no_hp" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sopir" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nama" character varying(100) NOT NULL,
    "no_hp" character varying(20),
    "kendaraan_id" "uuid",
    "aktif" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "armada_perusahaan_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "mitra_id" "uuid",
    "plat_nomor" character varying(30),
    "is_armada_cb" boolean DEFAULT false,
    "upah_sopir_per_trip_override" numeric(15,2),
    "uang_jalan_per_trip_override" numeric(15,2),
    "status_verifikasi" "text" DEFAULT 'terverifikasi'::"text" NOT NULL,
    "dibuat_oleh" "uuid",
    "diverifikasi_oleh" "uuid",
    "diverifikasi_at" timestamp with time zone,
    "catatan_verifikasi" "text",
    CONSTRAINT "sopir_status_verifikasi_check" CHECK (("status_verifikasi" = ANY (ARRAY['perlu_verifikasi'::"text", 'terverifikasi'::"text"]))),
    CONSTRAINT "sopir_uang_jalan_per_trip_nonnegative" CHECK ((("uang_jalan_per_trip_override" IS NULL) OR ("uang_jalan_per_trip_override" >= (0)::numeric))),
    CONSTRAINT "sopir_upah_per_trip_nonnegative" CHECK ((("upah_sopir_per_trip_override" IS NULL) OR ("upah_sopir_per_trip_override" >= (0)::numeric)))
);


ALTER TABLE "public"."sopir" OWNER TO "postgres";


COMMENT ON COLUMN "public"."sopir"."is_armada_cb" IS 'Menandakan apakah armada ini milik internal owner (Armada CB). Jika true, akan dikenakan tarif sewa armada ke mitra.';



COMMENT ON COLUMN "public"."sopir"."upah_sopir_per_trip_override" IS 'Tarif upah per trip khusus unit ini. NULL berarti memakai pengaturan global Armada CB.';



COMMENT ON COLUMN "public"."sopir"."uang_jalan_per_trip_override" IS 'Uang jalan per trip khusus unit ini. NULL berarti memakai pengaturan global Armada CB.';



CREATE OR REPLACE FUNCTION "public"."save_sopir_armada"("p_id" "uuid" DEFAULT NULL::"uuid", "p_nama" "text" DEFAULT NULL::"text", "p_no_hp" "text" DEFAULT NULL::"text", "p_mitra_id" "uuid" DEFAULT NULL::"uuid", "p_plat_nomor" "text" DEFAULT NULL::"text", "p_is_armada_cb" boolean DEFAULT false) RETURNS "public"."sopir"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_role text := public.current_app_role();
  v_before public.sopir%ROWTYPE;
  v_after public.sopir%ROWTYPE;
  v_plat text := upper(regexp_replace(btrim(COALESCE(p_plat_nomor, '')), '\s+', ' ', 'g'));
BEGIN
  IF v_actor IS NULL OR v_role NOT IN ('owner', 'super_admin', 'admin_operasional') THEN
    RAISE EXCEPTION 'Tidak berwenang menyimpan Sopir/Armada.' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_nama, '')), '') IS NULL OR NULLIF(v_plat, '') IS NULL THEN
    RAISE EXCEPTION 'Nama sopir/unit dan plat nomor wajib diisi.' USING ERRCODE = '22023';
  END IF;

  IF p_mitra_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.master_mitra WHERE id = p_mitra_id AND COALESCE(aktif, true) = true
  ) THEN
    RAISE EXCEPTION 'Mitra default tidak ditemukan atau sudah tidak aktif.' USING ERRCODE = 'P0002';
  END IF;

  IF p_id IS NOT NULL THEN
    SELECT * INTO v_before FROM public.sopir WHERE id = p_id FOR UPDATE;
    IF v_before.id IS NULL THEN
      RAISE EXCEPTION 'Sopir/Armada tidak ditemukan.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.sopir
    SET nama = btrim(p_nama),
        no_hp = NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
        mitra_id = p_mitra_id,
        plat_nomor = v_plat,
        is_armada_cb = COALESCE(p_is_armada_cb, false),
        status_verifikasi = CASE WHEN v_role IN ('owner', 'super_admin') THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
        diverifikasi_oleh = CASE WHEN v_role IN ('owner', 'super_admin') THEN v_actor ELSE NULL END,
        diverifikasi_at = CASE WHEN v_role IN ('owner', 'super_admin') THEN now() ELSE NULL END,
        updated_at = now()
    WHERE id = p_id
    RETURNING * INTO v_after;
  ELSE
    INSERT INTO public.sopir (
      nama, no_hp, mitra_id, plat_nomor, is_armada_cb, aktif,
      dibuat_oleh, status_verifikasi, diverifikasi_oleh, diverifikasi_at
    ) VALUES (
      btrim(p_nama), NULLIF(btrim(COALESCE(p_no_hp, '')), ''),
      p_mitra_id, v_plat, COALESCE(p_is_armada_cb, false), true,
      v_actor,
      CASE WHEN v_role IN ('owner', 'super_admin') THEN 'terverifikasi' ELSE 'perlu_verifikasi' END,
      CASE WHEN v_role IN ('owner', 'super_admin') THEN v_actor ELSE NULL END,
      CASE WHEN v_role IN ('owner', 'super_admin') THEN now() ELSE NULL END
    )
    RETURNING * INTO v_after;
  END IF;

  PERFORM public.write_audit_log(
    'sopir_armada', v_after.id,
    CASE WHEN p_id IS NULL THEN 'create' ELSE 'update' END,
    CASE WHEN p_id IS NULL THEN NULL ELSE to_jsonb(v_before) END,
    to_jsonb(v_after), NULL,
    CASE WHEN v_role IN ('owner', 'super_admin') THEN v_actor ELSE NULL END
  );

  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."save_sopir_armada"("p_id" "uuid", "p_nama" "text", "p_no_hp" "text", "p_mitra_id" "uuid", "p_plat_nomor" "text", "p_is_armada_cb" boolean) OWNER TO "postgres";




REVOKE ALL ON FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") TO "authenticated";
