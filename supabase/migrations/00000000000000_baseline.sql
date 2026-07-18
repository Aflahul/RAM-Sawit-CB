CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;



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


CREATE OR REPLACE FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") RETURNS "public"."transaksi_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_tanggal date;
  v_sopir_id uuid;
  v_mitra_id uuid;
  v_plat_nomor text;
  v_sopir_default_id uuid;
  v_sopir_default_nama text;
  v_sopir_aktual_id uuid;
  v_sopir_aktual_nama text;
  v_sopir_aktual_no_hp text;
  v_sopir_aktual_source text;
  v_sopir_diganti boolean;
  v_catatan_sopir text;

  v_berat_netto numeric;
  v_potongan numeric;
  v_berat_dibayar numeric;

  v_is_armada_cb boolean;
  v_kenakan_sewa boolean;
  v_catat_dana boolean;
  v_alasan_tanpa_sewa text;
  v_alasan_tanpa_dana text;

  v_harga_pabrik numeric;
  
  v_master_fee numeric;
  v_master_tarif_sewa numeric;
  v_master_dana_trip numeric;
  
  v_hist_id uuid;
  v_hist_fee numeric;
  v_hist_tarif_sewa numeric;
  v_hist_dana_trip numeric;
  v_hist_alasan text;
  
  v_is_initial boolean;
  v_has_stale_history_fee boolean;
  v_should_prefer_master boolean;
  
  v_final_fee numeric;
  v_final_tarif_sewa numeric;
  v_final_dana_trip numeric;
  v_final_history_id uuid;
  
  v_harga_bersih numeric;
  v_total_kotor numeric;
  v_total_fee_owner numeric;
  v_total_nilai_bersih numeric;
  
  v_pakai_sewa_armada boolean;
  v_biaya_sewa_kotor numeric;
  v_tarif_sewa_snapshot numeric;
  v_dana_trip_snapshot numeric;

  v_inserted_row public.transaksi_mitra;
BEGIN
  -- 1. Check Permissions
  IF NOT (SELECT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional', 'admin_keuangan'])) THEN
    RAISE EXCEPTION 'insufficient_privilege: Not authorized to save transaksi_mitra';
  END IF;

  -- 2. Extract operational payload
  v_tanggal := (payload->>'tanggal')::date;
  v_sopir_id := (payload->>'sopir_id')::uuid;
  v_mitra_id := (payload->>'mitra_id')::uuid;
  v_plat_nomor := payload->>'plat_nomor';
  v_sopir_default_id := (payload->>'sopir_default_id')::uuid;
  v_sopir_default_nama := payload->>'sopir_default_nama';
  v_sopir_aktual_id := (payload->>'sopir_aktual_id')::uuid;
  v_sopir_aktual_nama := payload->>'sopir_aktual_nama';
  v_sopir_aktual_no_hp := payload->>'sopir_aktual_no_hp';
  v_sopir_aktual_source := payload->>'sopir_aktual_source';
  v_sopir_diganti := COALESCE((payload->>'sopir_diganti_dari_default')::boolean, false);
  v_catatan_sopir := payload->>'catatan_sopir';

  v_berat_netto := COALESCE((payload->>'berat_netto_pabrik_kg')::numeric, 0);
  v_potongan := COALESCE((payload->>'potongan_pabrik_kg')::numeric, 0);
  
  v_is_armada_cb := COALESCE((payload->>'menggunakan_armada_cb_snapshot')::boolean, false);
  v_kenakan_sewa := COALESCE((payload->>'kenakan_sewa_armada_cb')::boolean, false);
  v_catat_dana := COALESCE((payload->>'catat_dana_operasional_trip')::boolean, false);
  v_alasan_tanpa_sewa := payload->>'alasan_tanpa_sewa_armada_cb';
  v_alasan_tanpa_dana := payload->>'alasan_tanpa_dana_operasional_trip';

  -- Validation
  IF v_berat_netto <= 0 THEN
    RAISE EXCEPTION 'Berat Netto harus lebih dari 0.';
  END IF;
  IF v_potongan < 0 THEN
    RAISE EXCEPTION 'Potongan tidak boleh negatif.';
  END IF;
  IF v_potongan > v_berat_netto THEN
    RAISE EXCEPTION 'Potongan tidak boleh lebih besar dari Berat Netto.';
  END IF;
  
  v_berat_dibayar := GREATEST(0, v_berat_netto - v_potongan);

  -- 3. Resolve Harga Pabrik
  SELECT harga_per_kg INTO v_harga_pabrik
  FROM public.harga_tbs
  WHERE tanggal <= v_tanggal
  ORDER BY tanggal DESC
  LIMIT 1;

  v_harga_pabrik := COALESCE(v_harga_pabrik, 0);

  -- 4. Resolve Fee & Tarif Mitra
  SELECT fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip
  INTO v_master_fee, v_master_tarif_sewa, v_master_dana_trip
  FROM public.master_mitra
  WHERE id = v_mitra_id;

  SELECT id, fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip, alasan_perubahan
  INTO v_hist_id, v_hist_fee, v_hist_tarif_sewa, v_hist_dana_trip, v_hist_alasan
  FROM public.fee_owner_mitra_history
  WHERE master_mitra_id = v_mitra_id
    AND aktif = true
    AND (berlaku_mulai IS NULL OR berlaku_mulai <= v_tanggal)
    AND (berlaku_sampai IS NULL OR berlaku_sampai >= v_tanggal)
  ORDER BY berlaku_mulai DESC NULLS LAST
  LIMIT 1;

  v_is_initial := v_hist_alasan LIKE 'Snapshot awal Fee Owner%';
  v_has_stale_history_fee := (v_hist_id IS NOT NULL AND v_master_fee > 0 AND v_hist_fee = 0);
  v_should_prefer_master := v_master_fee > 0 AND (v_hist_id IS NULL OR v_has_stale_history_fee OR (v_is_initial AND v_hist_fee <> v_master_fee));

  IF v_should_prefer_master THEN
    v_final_fee := v_master_fee;
    v_final_tarif_sewa := COALESCE(v_master_tarif_sewa, 0);
    v_final_dana_trip := COALESCE(v_master_dana_trip, 0);
    IF v_hist_fee = v_master_fee THEN
      v_final_history_id := v_hist_id;
    ELSE
      v_final_history_id := NULL;
    END IF;
  ELSE
    v_final_fee := COALESCE(v_hist_fee, v_master_fee, 0);
    v_final_tarif_sewa := COALESCE(v_hist_tarif_sewa, v_master_tarif_sewa, 0);
    v_final_dana_trip := COALESCE(v_hist_dana_trip, v_master_dana_trip, 0);
    v_final_history_id := v_hist_id;
  END IF;

  -- 5. Calculate Values
  v_harga_bersih := GREATEST(0, v_harga_pabrik - v_final_fee);
  v_total_kotor := ROUND(v_berat_dibayar * v_harga_pabrik);
  v_total_fee_owner := ROUND(v_berat_dibayar * v_final_fee);
  v_total_nilai_bersih := ROUND(v_berat_dibayar * v_harga_bersih);

  v_pakai_sewa_armada := v_is_armada_cb AND v_kenakan_sewa;
  IF v_pakai_sewa_armada THEN
    v_biaya_sewa_kotor := ROUND(v_berat_netto * v_final_tarif_sewa);
    v_tarif_sewa_snapshot := v_final_tarif_sewa;
  ELSE
    v_biaya_sewa_kotor := 0;
    v_tarif_sewa_snapshot := 0;
  END IF;

  IF v_is_armada_cb AND v_catat_dana THEN
    v_dana_trip_snapshot := v_final_dana_trip;
  ELSE
    v_dana_trip_snapshot := 0;
  END IF;

  -- Validation Sewa Armada CB
  IF v_is_armada_cb AND v_kenakan_sewa AND v_final_tarif_sewa <= 0 THEN
    RAISE EXCEPTION 'Tarif sewa Armada CB untuk mitra ini belum diatur.';
  END IF;
  IF v_is_armada_cb AND v_catat_dana AND v_final_dana_trip <= 0 THEN
    RAISE EXCEPTION 'Dana Operasional Trip untuk mitra ini belum diatur.';
  END IF;

  -- 6. Insert Transaksi
  INSERT INTO public.transaksi_mitra (
    tanggal, sopir_id, mitra_id, plat_nomor,
    sopir_default_id, sopir_default_nama,
    sopir_aktual_id, sopir_aktual_nama, sopir_aktual_no_hp,
    sopir_aktual_source, sopir_diganti_dari_default, catatan_sopir,
    
    tonase, berat_netto_pabrik_kg, potongan_pabrik_kg, berat_dibayar_kg,
    harga_harian, harga_pabrik_per_kg, fee_owner_per_kg, harga_bersih_per_kg, fee_owner_history_id,
    total_kotor, total_fee_owner, total_nilai_bersih,
    
    menggunakan_armada_cb_snapshot, kenakan_sewa_armada_cb, catat_dana_operasional_trip,
    alasan_tanpa_sewa_armada_cb, alasan_tanpa_dana_operasional_trip,
    pakai_sewa_armada_bl, tarif_sewa_angkut_per_kg_snapshot, nominal_perongkosan_snapshot,
    biaya_sewa_armada_kotor, biaya_sewa_armada_total,
    dana_operasional_trip_snapshot, upah_sopir_cb_snapshot, uang_jalan_sopir_cb_snapshot, total_biaya_sopir_cb_snapshot,
    dibuat_oleh
  ) VALUES (
    v_tanggal, v_sopir_id, v_mitra_id, v_plat_nomor,
    v_sopir_default_id, v_sopir_default_nama,
    v_sopir_aktual_id, v_sopir_aktual_nama, v_sopir_aktual_no_hp,
    v_sopir_aktual_source, v_sopir_diganti, v_catatan_sopir,
    
    v_berat_netto, v_berat_netto, v_potongan, v_berat_dibayar,
    v_harga_pabrik, v_harga_pabrik, v_final_fee, v_harga_bersih, v_final_history_id,
    v_total_kotor, v_total_fee_owner, v_total_nilai_bersih,
    
    v_is_armada_cb, v_kenakan_sewa, v_catat_dana,
    CASE WHEN v_kenakan_sewa THEN NULL ELSE v_alasan_tanpa_sewa END, 
    CASE WHEN v_catat_dana THEN NULL ELSE v_alasan_tanpa_dana END,
    v_pakai_sewa_armada, v_tarif_sewa_snapshot, 0,
    v_biaya_sewa_kotor, v_biaya_sewa_kotor,
    v_dana_trip_snapshot, 0, 0, v_dana_trip_snapshot,
    auth.uid()
  ) RETURNING * INTO v_inserted_row;

  RETURN v_inserted_row;
END;
$$;


ALTER FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."harga_tbs_lokal" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "harga_per_kg" numeric(12,2) NOT NULL,
    "berlaku_mulai" timestamp with time zone NOT NULL,
    "berlaku_sampai" timestamp with time zone,
    "aktif" boolean DEFAULT true,
    "set_oleh" "uuid",
    "alasan_override" "text",
    "legacy_harga_tbs_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "updated_by" "uuid",
    CONSTRAINT "harga_tbs_lokal_harga_per_kg_check" CHECK (("harga_per_kg" >= (0)::numeric)),
    CONSTRAINT "harga_tbs_lokal_periode_check" CHECK ((("berlaku_sampai" IS NULL) OR ("berlaku_sampai" > "berlaku_mulai")))
);


ALTER TABLE "public"."harga_tbs_lokal" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_harga_tbs_lokal"("p_harga_per_kg" numeric, "p_alasan_override" "text" DEFAULT NULL::"text") RETURNS "public"."harga_tbs_lokal"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_now timestamptz := now();
  v_harga public.harga_tbs_lokal%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat mengatur harga TBS lokal.' USING ERRCODE = '42501';
  END IF;
  IF p_harga_per_kg IS NULL OR p_harga_per_kg <= 0 THEN
    RAISE EXCEPTION 'Harga TBS lokal harus lebih dari 0.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.harga_tbs_lokal
  SET aktif = false,
      berlaku_sampai = COALESCE(berlaku_sampai, v_now),
      updated_at = v_now,
      updated_by = v_actor
  WHERE aktif = true AND (berlaku_sampai IS NULL OR berlaku_sampai > v_now);

  INSERT INTO public.harga_tbs_lokal (
    harga_per_kg, berlaku_mulai, aktif, set_oleh, alasan_override
  ) VALUES (
    round(p_harga_per_kg, 2), v_now, true, v_actor,
    NULLIF(btrim(COALESCE(p_alasan_override, '')), '')
  ) RETURNING * INTO v_harga;

  PERFORM public.write_audit_log(
    'harga_tbs_lokal', v_harga.id, 'create', NULL,
    to_jsonb(v_harga), p_alasan_override, v_actor
  );
  RETURN v_harga;
END;
$$;


ALTER FUNCTION "public"."set_harga_tbs_lokal"("p_harga_per_kg" numeric, "p_alasan_override" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_master_mitra_active"("p_id" "uuid", "p_active" boolean) RETURNS "public"."master_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.master_mitra%ROWTYPE;
  v_after public.master_mitra%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat mengubah status Mitra.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_before FROM public.master_mitra WHERE id = p_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'Mitra tidak ditemukan.' USING ERRCODE = 'P0002'; END IF;
  UPDATE public.master_mitra SET aktif = COALESCE(p_active, false)
  WHERE id = p_id RETURNING * INTO v_after;
  PERFORM public.write_audit_log('master_mitra', v_after.id,
    CASE WHEN v_after.aktif THEN 'activate' ELSE 'deactivate' END,
    to_jsonb(v_before), to_jsonb(v_after), NULL, v_actor);
  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."set_master_mitra_active"("p_id" "uuid", "p_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_pabrik_master_active"("p_id" "uuid", "p_active" boolean) RETURNS "public"."pabrik"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.pabrik%ROWTYPE;
  v_after public.pabrik%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat mengubah status Pabrik.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_before FROM public.pabrik WHERE id = p_id FOR UPDATE;
  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Pabrik tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.pabrik SET aktif = COALESCE(p_active, false)
  WHERE id = p_id RETURNING * INTO v_after;

  PERFORM public.write_audit_log(
    'pabrik', v_after.id,
    CASE WHEN v_after.aktif THEN 'activate' ELSE 'deactivate' END,
    to_jsonb(v_before), to_jsonb(v_after), NULL, v_actor
  );
  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."set_pabrik_master_active"("p_id" "uuid", "p_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_sopir_armada_active"("p_id" "uuid", "p_active" boolean) RETURNS "public"."sopir"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.sopir%ROWTYPE;
  v_after public.sopir%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat mengubah status Sopir/Armada.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_before FROM public.sopir WHERE id = p_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'Sopir/Armada tidak ditemukan.' USING ERRCODE = 'P0002'; END IF;
  UPDATE public.sopir SET aktif = COALESCE(p_active, false), updated_at = now()
  WHERE id = p_id RETURNING * INTO v_after;
  PERFORM public.write_audit_log('sopir_armada', v_after.id,
    CASE WHEN v_after.aktif THEN 'activate' ELSE 'deactivate' END,
    to_jsonb(v_before), to_jsonb(v_after), NULL, v_actor);
  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."set_sopir_armada_active"("p_id" "uuid", "p_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."settle_panjar_mitra_manual"("p_panjar_id" "uuid", "p_alasan" "text") RETURNS "public"."panjar_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_panjar public.panjar_mitra%ROWTYPE;
  v_hutang public.hutang_ledger%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_keuangan', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang melunasi panjar mitra.'
      USING ERRCODE = '42501';
  END IF;

  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan pelunasan manual wajib diisi.'
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
    RAISE EXCEPTION 'Panjar sudah tidak berstatus belum lunas.'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.hutang_ledger (
    pihak_type,
    master_mitra_id,
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
    'mitra',
    v_panjar.mitra_id,
    COALESCE(v_panjar.tanggal, (now() AT TIME ZONE 'Asia/Jakarta')::date),
    'kredit',
    'koreksi',
    v_panjar.jumlah,
    'panjar_mitra_manual_lunas',
    v_panjar.id,
    'Pelunasan manual panjar: ' || btrim(p_alasan),
    v_actor
  )
  RETURNING * INTO v_hutang;

  UPDATE public.panjar_mitra
  SET status = 'lunas',
      settlement_hutang_ledger_id = v_hutang.id,
      lunas_at = now(),
      updated_at = now()
  WHERE id = v_panjar.id
  RETURNING * INTO v_panjar;

  RETURN v_panjar;
END;
$$;


ALTER FUNCTION "public"."settle_panjar_mitra_manual"("p_panjar_id" "uuid", "p_alasan" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."snapshot_sewa_item_kwitansi"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_transaksi public.transaksi_mitra%ROWTYPE;
  v_berat_netto numeric(15,2) := 0;
  v_tarif numeric(12,2) := 0;
  v_sewa_ditagihkan numeric(15,2) := 0;
  v_sewa_standar numeric(15,2) := 0;
BEGIN
  SELECT * INTO v_transaksi
  FROM public.transaksi_mitra
  WHERE id = NEW.transaksi_mitra_id;

  IF v_transaksi.id IS NULL THEN
    RAISE EXCEPTION 'Transaksi sumber item kwitansi tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  IF NOT COALESCE(NEW.pakai_sewa_armada_snapshot, false) THEN
    NEW.tarif_sewa_angkut_per_kg_snapshot := 0;
    NEW.biaya_sewa_armada_standar_snapshot := 0;
    NEW.selisih_sewa_armada_historis_snapshot := 0;
    NEW.metode_sewa_armada_snapshot := 'tidak_ada';
    RETURN NEW;
  END IF;

  v_berat_netto := GREATEST(COALESCE(NEW.berat_netto_snapshot, NEW.tonase_snapshot, 0), 0);
  v_tarif := GREATEST(COALESCE(
    NULLIF(v_transaksi.tarif_sewa_angkut_per_kg_snapshot, 0),
    NULLIF(v_transaksi.biaya_sewa_armada_per_kg, 0),
    0
  ), 0);
  v_sewa_ditagihkan := GREATEST(COALESCE(NEW.biaya_sewa_armada_snapshot, 0), 0);
  v_sewa_standar := CASE
    WHEN v_berat_netto > 0 AND v_tarif > 0 THEN round(v_berat_netto * v_tarif, 2)
    ELSE v_sewa_ditagihkan
  END;

  NEW.tarif_sewa_angkut_per_kg_snapshot := v_tarif;
  NEW.biaya_sewa_armada_standar_snapshot := v_sewa_standar;
  NEW.selisih_sewa_armada_historis_snapshot := v_sewa_standar - v_sewa_ditagihkan;
  NEW.metode_sewa_armada_snapshot := CASE
    WHEN v_tarif > 0 AND abs(v_sewa_standar - v_sewa_ditagihkan) <= 0.01
      THEN 'netto_x_tarif'
    ELSE 'legacy_snapshot'
  END;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."snapshot_sewa_item_kwitansi"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_fee_owner_mitra_period"("p_date_from" "date", "p_date_to" "date", "p_master_mitra_id" "uuid" DEFAULT NULL::"uuid", "p_tipe_mitra" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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


ALTER FUNCTION "public"."sync_fee_owner_mitra_period"("p_date_from" "date", "p_date_to" "date", "p_master_mitra_id" "uuid", "p_tipe_mitra" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."sync_fee_owner_mitra_period"("p_date_from" "date", "p_date_to" "date", "p_master_mitra_id" "uuid", "p_tipe_mitra" "text") IS 'Sinkronisasi snapshot Fee Owner transaksi mitra hanya untuk periode/filter yang sedang dibuka.';



CREATE OR REPLACE FUNCTION "public"."sync_kwitansi_totals_from_item"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  PERFORM public.recalculate_kwitansi_totals(COALESCE(NEW.pembayaran_id, OLD.pembayaran_id));
  RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION "public"."sync_kwitansi_totals_from_item"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_kwitansi_totals_from_summary"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  PERFORM public.recalculate_kwitansi_totals(NEW.pembayaran_id);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_kwitansi_totals_from_summary"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_piutang_document_from_panjar"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.status = 'lunas' AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE public.piutang_dokumen SET status = 'lunas', updated_at = now()
    WHERE panjar_mitra_id = NEW.id AND status = 'diserahkan';
  ELSIF NEW.status = 'belum_lunas' AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE public.piutang_dokumen SET status = 'diserahkan', updated_at = now()
    WHERE panjar_mitra_id = NEW.id AND status = 'lunas';
  ELSIF NEW.status = 'dibatalkan' AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE public.piutang_dokumen SET status = 'dibatalkan', updated_at = now()
    WHERE panjar_mitra_id = NEW.id AND status <> 'dibatalkan';
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_piutang_document_from_panjar"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_tagihan_sopir_cb"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_tagihan public.hutang_ledger%ROWTYPE;
  v_pihak_type text;
  v_sopir_aktual_id uuid;
  v_pihak_nama text;
  v_nominal numeric(15,2) := 0;
BEGIN
  v_nominal := GREATEST(COALESCE(
    NULLIF(NEW.dana_operasional_trip_snapshot, 0),
    NEW.total_biaya_sopir_cb_snapshot,
    0
  ), 0);

  IF NEW.status = 'dibatalkan'
     OR NOT NEW.menggunakan_armada_cb_snapshot
     OR NOT NEW.catat_dana_operasional_trip
     OR v_nominal <= 0 THEN
    IF NEW.tagihan_sopir_ledger_id IS NOT NULL
       AND NEW.biaya_sopir_dibayar_at IS NULL THEN
      UPDATE public.hutang_ledger
      SET status = 'dibatalkan',
          alasan_batal = CASE
            WHEN NEW.status = 'dibatalkan' THEN COALESCE(NEW.alasan_batal, 'Pengiriman dibatalkan')
            ELSE 'Dana Operasional Trip dinonaktifkan pada pengiriman.'
          END,
          dibatalkan_at = now(),
          dibatalkan_by = COALESCE(NEW.dibatalkan_by, v_actor)
      WHERE id = NEW.tagihan_sopir_ledger_id
        AND status = 'aktif';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.tagihan_sopir_ledger_id IS NOT NULL THEN
    SELECT * INTO v_tagihan
    FROM public.hutang_ledger
    WHERE id = NEW.tagihan_sopir_ledger_id;

    IF v_tagihan.id IS NOT NULL AND v_tagihan.status = 'aktif' THEN
      IF NEW.biaya_sopir_dibayar_at IS NULL THEN
        UPDATE public.hutang_ledger
        SET sumber = 'operasional',
            jumlah = v_nominal,
            keterangan = format(
              'Dana operasional trip Armada CB %s tanggal %s',
              COALESCE(NEW.plat_nomor, '-'), NEW.tanggal
            ),
            updated_at = now()
        WHERE id = v_tagihan.id;
      END IF;
      RETURN NEW;
    END IF;
  END IF;

  SELECT * INTO v_tagihan
  FROM public.hutang_ledger
  WHERE legacy_source_table = 'tagihan_sopir_cb'
    AND legacy_source_id = NEW.id
    AND status = 'aktif'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_tagihan.id IS NULL THEN
    v_sopir_aktual_id := CASE
      WHEN NEW.sopir_aktual_source = 'manual' THEN NULL
      ELSE COALESCE(NEW.sopir_aktual_id, NEW.sopir_id)
    END;
    v_pihak_nama := NULLIF(btrim(COALESCE(NEW.sopir_aktual_nama, NEW.sopir_default_nama, '')), '');
    v_pihak_type := CASE WHEN v_sopir_aktual_id IS NULL THEN 'lainnya' ELSE 'sopir' END;

    INSERT INTO public.hutang_ledger (
      pihak_type, sopir_id, pihak_nama_manual, tanggal, tipe, sumber, jumlah,
      legacy_source_table, legacy_source_id, keterangan, created_by
    ) VALUES (
      v_pihak_type,
      CASE WHEN v_pihak_type = 'sopir' THEN v_sopir_aktual_id ELSE NULL END,
      CASE WHEN v_pihak_type = 'lainnya' THEN COALESCE(v_pihak_nama, 'Sopir pengganti') ELSE NULL END,
      NEW.tanggal, 'debit', 'operasional', v_nominal,
      'tagihan_sopir_cb', NEW.id,
      format('Dana operasional trip Armada CB %s tanggal %s', COALESCE(NEW.plat_nomor, '-'), NEW.tanggal),
      v_actor
    ) RETURNING * INTO v_tagihan;
  END IF;

  UPDATE public.transaksi_mitra
  SET tagihan_sopir_ledger_id = v_tagihan.id
  WHERE id = NEW.id
    AND tagihan_sopir_ledger_id IS DISTINCT FROM v_tagihan.id;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_tagihan_sopir_cb"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_tarif_sopir_cb_period"("p_date_from" "date", "p_date_to" "date", "p_armada_sopir_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_updated_count integer := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Tidak berwenang menyelaraskan Dana Operasional Trip.' USING ERRCODE = '42501';
  END IF;
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
    RAISE EXCEPTION 'Periode tidak valid.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.transaksi_mitra tm
  SET dana_operasional_trip_snapshot = public.resolve_dana_operasional_trip_mitra(tm.mitra_id, tm.tanggal),
      upah_sopir_cb_snapshot = 0,
      uang_jalan_sopir_cb_snapshot = 0,
      total_biaya_sopir_cb_snapshot = public.resolve_dana_operasional_trip_mitra(tm.mitra_id, tm.tanggal)
  WHERE tm.menggunakan_armada_cb_snapshot = true
    AND tm.catat_dana_operasional_trip = true
    AND tm.armada_cb_perlu_review = false
    AND tm.status = 'aktif'
    AND tm.biaya_sopir_dibayar_at IS NULL
    AND tm.tanggal BETWEEN p_date_from AND p_date_to
    AND (p_armada_sopir_id IS NULL OR tm.sopir_id = p_armada_sopir_id);

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  RETURN jsonb_build_object('updated_count', v_updated_count);
END;
$$;


ALTER FUNCTION "public"."sync_tarif_sopir_cb_period"("p_date_from" "date", "p_date_to" "date", "p_armada_sopir_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_transaksi_mitra_controlled"("p_transaksi_id" "uuid", "p_changes" "jsonb", "p_alasan" "text") RETURNS "public"."transaksi_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_before public.transaksi_mitra%ROWTYPE;
  v_candidate public.transaksi_mitra%ROWTYPE;
  v_after public.transaksi_mitra%ROWTYPE;
  v_unknown_key text;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin', 'admin_operasional']) THEN
    RAISE EXCEPTION 'Tidak berwenang mengoreksi pengiriman.' USING ERRCODE = '42501';
  END IF;
  IF p_alasan IS NULL OR length(btrim(p_alasan)) = 0 THEN
    RAISE EXCEPTION 'Alasan koreksi wajib diisi.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_before FROM public.transaksi_mitra WHERE id = p_transaksi_id FOR UPDATE;
  IF v_before.id IS NULL THEN
    RAISE EXCEPTION 'Pengiriman tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;
  IF v_before.status = 'dibatalkan' THEN
    RAISE EXCEPTION 'Pengiriman sudah dibatalkan.' USING ERRCODE = '22023';
  END IF;

  SELECT key INTO v_unknown_key
  FROM jsonb_object_keys(COALESCE(p_changes, '{}'::jsonb)) key
  WHERE key <> ALL (ARRAY[
    'tanggal', 'sopir_id', 'sopir_default_id', 'sopir_default_nama',
    'mitra_id', 'plat_nomor', 'sopir_aktual_id', 'sopir_aktual_nama',
    'sopir_aktual_no_hp', 'sopir_aktual_source', 'sopir_diganti_dari_default',
    'catatan_sopir', 'tonase', 'berat_netto_pabrik_kg',
    'potongan_pabrik_kg', 'berat_dibayar_kg', 'harga_harian',
    'harga_pabrik_per_kg', 'fee_owner_per_kg', 'harga_bersih_per_kg',
    'fee_owner_history_id', 'total_kotor', 'total_fee_owner',
    'total_nilai_bersih', 'pakai_sewa_armada_bl',
    'kenakan_sewa_armada_cb', 'catat_dana_operasional_trip',
    'alasan_tanpa_sewa_armada_cb', 'alasan_tanpa_dana_operasional_trip',
    'biaya_sewa_armada_per_kg', 'tarif_sewa_angkut_per_kg_snapshot',
    'biaya_sewa_armada_kotor', 'biaya_sewa_armada_total'
  ]) LIMIT 1;

  IF v_unknown_key IS NOT NULL THEN
    RAISE EXCEPTION 'Field koreksi tidak diizinkan: %', v_unknown_key USING ERRCODE = '22023';
  END IF;

  v_candidate := jsonb_populate_record(v_before, COALESCE(p_changes, '{}'::jsonb));

  UPDATE public.transaksi_mitra
  SET tanggal = v_candidate.tanggal,
      sopir_id = v_candidate.sopir_id,
      sopir_default_id = v_candidate.sopir_default_id,
      sopir_default_nama = v_candidate.sopir_default_nama,
      mitra_id = v_candidate.mitra_id,
      plat_nomor = v_candidate.plat_nomor,
      sopir_aktual_id = v_candidate.sopir_aktual_id,
      sopir_aktual_nama = v_candidate.sopir_aktual_nama,
      sopir_aktual_no_hp = v_candidate.sopir_aktual_no_hp,
      sopir_aktual_source = v_candidate.sopir_aktual_source,
      sopir_diganti_dari_default = v_candidate.sopir_diganti_dari_default,
      catatan_sopir = v_candidate.catatan_sopir,
      tonase = v_candidate.tonase,
      berat_netto_pabrik_kg = v_candidate.berat_netto_pabrik_kg,
      potongan_pabrik_kg = v_candidate.potongan_pabrik_kg,
      berat_dibayar_kg = v_candidate.berat_dibayar_kg,
      harga_harian = v_candidate.harga_harian,
      harga_pabrik_per_kg = v_candidate.harga_pabrik_per_kg,
      fee_owner_per_kg = v_candidate.fee_owner_per_kg,
      harga_bersih_per_kg = v_candidate.harga_bersih_per_kg,
      fee_owner_history_id = v_candidate.fee_owner_history_id,
      total_kotor = v_candidate.total_kotor,
      total_fee_owner = v_candidate.total_fee_owner,
      total_nilai_bersih = v_candidate.total_nilai_bersih,
      pakai_sewa_armada_bl = v_candidate.pakai_sewa_armada_bl,
      kenakan_sewa_armada_cb = v_candidate.kenakan_sewa_armada_cb,
      catat_dana_operasional_trip = v_candidate.catat_dana_operasional_trip,
      alasan_tanpa_sewa_armada_cb = v_candidate.alasan_tanpa_sewa_armada_cb,
      alasan_tanpa_dana_operasional_trip = v_candidate.alasan_tanpa_dana_operasional_trip,
      biaya_sewa_armada_per_kg = v_candidate.biaya_sewa_armada_per_kg,
      tarif_sewa_angkut_per_kg_snapshot = v_candidate.tarif_sewa_angkut_per_kg_snapshot,
      biaya_sewa_armada_kotor = v_candidate.biaya_sewa_armada_kotor,
      biaya_sewa_armada_total = v_candidate.biaya_sewa_armada_total,
      updated_by = v_actor,
      alasan_edit = btrim(p_alasan)
  WHERE id = v_before.id
  RETURNING * INTO v_after;

  PERFORM public.write_audit_log(
    'transaksi_mitra', v_before.id, 'update',
    to_jsonb(v_before), to_jsonb(v_after), p_alasan,
    CASE WHEN public.has_app_role(ARRAY['owner', 'super_admin']) THEN v_actor ELSE NULL END
  );
  RETURN v_after;
END;
$$;


ALTER FUNCTION "public"."update_transaksi_mitra_controlled"("p_transaksi_id" "uuid", "p_changes" "jsonb", "p_alasan" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_kwitansi_deductions_per_mitra"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
  v_invalid record;
BEGIN
  IF jsonb_typeof(NEW.transaksi_snapshot_json) <> 'array'
     OR jsonb_typeof(NEW.panjar_snapshot_json) <> 'array' THEN
    RAISE EXCEPTION 'Snapshot transaksi dan panjar kwitansi harus berupa daftar.'
      USING ERRCODE = '22023';
  END IF;

  WITH transaction_groups AS (
    SELECT
      CASE
        WHEN COALESCE(item ->> 'master_mitra_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          THEN (item ->> 'master_mitra_id')::uuid
        ELSE NULL
      END AS master_mitra_id,
      MAX(COALESCE(NULLIF(item ->> 'mitra_label', ''), 'Mitra')) AS mitra_label,
      SUM(COALESCE(NULLIF(item ->> 'total_nilai_bersih', ''), '0')::numeric) AS nilai_bersih,
      SUM(COALESCE(NULLIF(item ->> 'biaya_sewa_armada_total', ''), '0')::numeric) AS sewa_armada
    FROM jsonb_array_elements(NEW.transaksi_snapshot_json) item
    GROUP BY 1
  ),
  panjar_groups AS (
    SELECT
      COALESCE(
        CASE
          WHEN COALESCE(item ->> 'master_mitra_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
            THEN (item ->> 'master_mitra_id')::uuid
          ELSE NULL
        END,
        panjar.mitra_id
      ) AS master_mitra_id,
      MAX(COALESCE(NULLIF(item ->> 'mitra_label', ''), mitra.nama, mitra.kode, 'Mitra')) AS mitra_label,
      SUM(COALESCE(NULLIF(item ->> 'jumlah', ''), '0')::numeric) AS total_panjar
    FROM jsonb_array_elements(NEW.panjar_snapshot_json) item
    LEFT JOIN public.panjar_mitra panjar
      ON panjar.id = CASE
        WHEN COALESCE(item ->> 'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          THEN (item ->> 'id')::uuid
        ELSE NULL
      END
    LEFT JOIN public.master_mitra mitra ON mitra.id = panjar.mitra_id
    GROUP BY 1
  )
  SELECT
    COALESCE(transaction_groups.master_mitra_id, panjar_groups.master_mitra_id) AS master_mitra_id,
    COALESCE(transaction_groups.mitra_label, panjar_groups.mitra_label, 'Mitra') AS mitra_label,
    COALESCE(transaction_groups.nilai_bersih, 0) AS nilai_bersih,
    COALESCE(transaction_groups.sewa_armada, 0) AS sewa_armada,
    COALESCE(panjar_groups.total_panjar, 0) AS total_panjar
  INTO v_invalid
  FROM transaction_groups
  FULL JOIN panjar_groups USING (master_mitra_id)
  WHERE COALESCE(transaction_groups.master_mitra_id, panjar_groups.master_mitra_id) IS NULL
     OR transaction_groups.master_mitra_id IS NULL
     OR COALESCE(transaction_groups.nilai_bersih, 0)
        - COALESCE(transaction_groups.sewa_armada, 0)
        - COALESCE(panjar_groups.total_panjar, 0) < 0
  ORDER BY COALESCE(transaction_groups.mitra_label, panjar_groups.mitra_label, 'Mitra')
  LIMIT 1;

  IF FOUND THEN
    IF v_invalid.master_mitra_id IS NULL THEN
      RAISE EXCEPTION 'Ada panjar yang belum memiliki mitra. Lengkapi pemilik panjar sebelum membuat kwitansi.'
        USING ERRCODE = '22023';
    ELSIF v_invalid.nilai_bersih <= 0 THEN
      RAISE EXCEPTION 'Panjar % tidak memiliki transaksi TBS pada kwitansi ini.', v_invalid.mitra_label
        USING ERRCODE = '22023';
    ELSE
      RAISE EXCEPTION 'Panjar dan sewa armada % melebihi hak pembayaran mitra tersebut. Hak mitra lain tidak boleh digunakan.', v_invalid.mitra_label
        USING ERRCODE = '22023';
    END IF;
  END IF;

  RETURN NEW;
END;
$_$;


ALTER FUNCTION "public"."validate_kwitansi_deductions_per_mitra"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verify_master_mitra"("p_id" "uuid", "p_catatan" "text" DEFAULT NULL::"text") RETURNS "public"."master_mitra"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.master_mitra%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat memverifikasi Mitra.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.master_mitra
  SET status_verifikasi = 'terverifikasi',
      diverifikasi_oleh = v_actor,
      diverifikasi_at = now(),
      catatan_verifikasi = NULLIF(btrim(COALESCE(p_catatan, '')), '')
  WHERE id = p_id
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Mitra tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  PERFORM public.write_audit_log('master_mitra', v_row.id, 'verify', NULL, to_jsonb(v_row), p_catatan, v_actor);
  RETURN v_row;
END;
$$;


ALTER FUNCTION "public"."verify_master_mitra"("p_id" "uuid", "p_catatan" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verify_pabrik_master"("p_id" "uuid", "p_catatan" "text" DEFAULT NULL::"text") RETURNS "public"."pabrik"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.pabrik%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat memverifikasi Pabrik.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.pabrik
  SET status_verifikasi = 'terverifikasi',
      diverifikasi_oleh = v_actor,
      diverifikasi_at = now(),
      catatan_verifikasi = NULLIF(btrim(COALESCE(p_catatan, '')), '')
  WHERE id = p_id AND aktif = true
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Pabrik aktif tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  PERFORM public.write_audit_log('pabrik', v_row.id, 'verify', NULL, to_jsonb(v_row), p_catatan, v_actor);
  RETURN v_row;
END;
$$;


ALTER FUNCTION "public"."verify_pabrik_master"("p_id" "uuid", "p_catatan" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verify_sopir_armada"("p_id" "uuid", "p_catatan" "text" DEFAULT NULL::"text") RETURNS "public"."sopir"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.sopir%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.has_app_role(ARRAY['owner', 'super_admin']) THEN
    RAISE EXCEPTION 'Hanya Owner yang dapat memverifikasi Sopir/Armada.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.sopir
  SET status_verifikasi = 'terverifikasi',
      diverifikasi_oleh = v_actor,
      diverifikasi_at = now(),
      catatan_verifikasi = NULLIF(btrim(COALESCE(p_catatan, '')), ''),
      updated_at = now()
  WHERE id = p_id
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Sopir/Armada tidak ditemukan.' USING ERRCODE = 'P0002';
  END IF;

  PERFORM public.write_audit_log('sopir_armada', v_row.id, 'verify', NULL, to_jsonb(v_row), p_catatan, v_actor);
  RETURN v_row;
END;
$$;


ALTER FUNCTION "public"."verify_sopir_armada"("p_id" "uuid", "p_catatan" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."write_audit_log"("p_entity_type" "text", "p_entity_id" "uuid", "p_action" "text", "p_before_json" "jsonb" DEFAULT NULL::"jsonb", "p_after_json" "jsonb" DEFAULT NULL::"jsonb", "p_alasan" "text" DEFAULT NULL::"text", "p_approved_by" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_actor_role text;
  v_approved_by uuid := NULL;
  v_new_id uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Login diperlukan untuk mencatat audit.' USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_entity_type, '')), '') IS NULL
     OR NULLIF(btrim(COALESCE(p_action, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Jenis data dan aksi audit wajib diisi.' USING ERRCODE = '22023';
  END IF;

  v_actor_role := public.current_app_role();

  IF p_approved_by IS NOT NULL THEN
    IF p_approved_by <> v_actor THEN
      RAISE EXCEPTION 'Pemberi persetujuan harus sama dengan pengguna yang sedang login.'
        USING ERRCODE = '42501';
    END IF;

    IF v_actor_role IN ('owner', 'super_admin') THEN
      v_approved_by := v_actor;
    END IF;
  END IF;

  INSERT INTO public.audit_log (
    actor_user_id,
    actor_role,
    entity_type,
    entity_id,
    action,
    before_json,
    after_json,
    alasan,
    approved_by,
    approved_at
  ) VALUES (
    v_actor,
    v_actor_role,
    btrim(p_entity_type),
    p_entity_id,
    btrim(p_action),
    p_before_json,
    p_after_json,
    NULLIF(btrim(COALESCE(p_alasan, '')), ''),
    v_approved_by,
    CASE WHEN v_approved_by IS NULL THEN NULL ELSE now() END
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;


ALTER FUNCTION "public"."write_audit_log"("p_entity_type" "text", "p_entity_id" "uuid", "p_action" "text", "p_before_json" "jsonb", "p_after_json" "jsonb", "p_alasan" "text", "p_approved_by" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."armada_mitra" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "mitra_id" "uuid",
    "plat_kendaraan" character varying(30),
    "nama_sopir" character varying(100),
    "aktif" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."armada_mitra" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."armada_perusahaan" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "plat_nomor" character varying(30) NOT NULL,
    "jenis_kendaraan" character varying(80),
    "kapasitas_kg" numeric(12,2),
    "kepemilikan" "text" DEFAULT 'sendiri'::"text",
    "tarif_default_per_km_per_ton" numeric(15,2) DEFAULT 0,
    "tarif_default_aktif" boolean DEFAULT false,
    "aktif" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "armada_perusahaan_kepemilikan_check" CHECK (("kepemilikan" = ANY (ARRAY['sendiri'::"text", 'sewa'::"text"])))
);


ALTER TABLE "public"."armada_perusahaan" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "actor_user_id" "uuid",
    "actor_role" "text",
    "entity_type" "text" NOT NULL,
    "entity_id" "uuid",
    "action" "text" NOT NULL,
    "before_json" "jsonb",
    "after_json" "jsonb",
    "alasan" "text",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "audit_log_action_check" CHECK (("action" = ANY (ARRAY['create'::"text", 'update'::"text", 'delete'::"text", 'cancel'::"text", 'approve'::"text", 'export'::"text", 'override'::"text", 'verify'::"text", 'cancel_payment'::"text", 'reverse_manual_cash'::"text", 'reverse_dana_trip'::"text", 'create_request'::"text", 'setujui'::"text", 'tolak'::"text", 'disburse'::"text", 'repayment'::"text", 'reconcile_legacy_opening'::"text"])))
);


ALTER TABLE "public"."audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bukti_pembayaran" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tipe" "text" NOT NULL,
    "nomor_bukti" "text" NOT NULL,
    "pembayaran_mitra_id" "uuid",
    "pembayaran_pabrik_id" "uuid",
    "transaksi_beli_id" "uuid",
    "file_url" "text",
    "format" "text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "bukti_pembayaran_format_check" CHECK (("format" = ANY (ARRAY['pdf'::"text", 'image'::"text"]))),
    CONSTRAINT "bukti_pembayaran_tipe_check" CHECK (("tipe" = ANY (ARRAY['pembayaran_mitra'::"text", 'pembayaran_petani'::"text", 'pembayaran_pabrik'::"text"])))
);


ALTER TABLE "public"."bukti_pembayaran" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fee_mitra_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "mitra_id" "uuid",
    "fee_per_kg" numeric(12,2) DEFAULT 0 NOT NULL,
    "berlaku_mulai" timestamp with time zone NOT NULL,
    "berlaku_sampai" timestamp with time zone,
    "aktif" boolean DEFAULT true,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "fee_mitra_history_fee_per_kg_check" CHECK (("fee_per_kg" >= (0)::numeric)),
    CONSTRAINT "fee_mitra_history_periode_check" CHECK ((("berlaku_sampai" IS NULL) OR ("berlaku_sampai" > "berlaku_mulai")))
);


ALTER TABLE "public"."fee_mitra_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fee_owner_mitra_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "master_mitra_id" "uuid" NOT NULL,
    "fee_per_kg" numeric(12,2) DEFAULT 0 NOT NULL,
    "berlaku_mulai" "date" DEFAULT CURRENT_DATE NOT NULL,
    "berlaku_sampai" "date",
    "aktif" boolean DEFAULT true NOT NULL,
    "alasan_perubahan" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tarif_sewa_angkut_per_kg" numeric(12,2) DEFAULT 0,
    "nominal_perongkosan" numeric(15,2) DEFAULT 0,
    "dana_operasional_trip" numeric(15,2) DEFAULT 0 NOT NULL,
    CONSTRAINT "fee_history_dana_operasional_trip_nonnegative" CHECK (("dana_operasional_trip" >= (0)::numeric)),
    CONSTRAINT "fee_owner_mitra_history_fee_per_kg_check" CHECK (("fee_per_kg" >= (0)::numeric)),
    CONSTRAINT "fee_owner_mitra_history_periode_check" CHECK ((("berlaku_sampai" IS NULL) OR ("berlaku_sampai" >= "berlaku_mulai")))
);


ALTER TABLE "public"."fee_owner_mitra_history" OWNER TO "postgres";


COMMENT ON COLUMN "public"."fee_owner_mitra_history"."dana_operasional_trip" IS 'Riwayat dana operasional satu kali jalan Armada CB berdasarkan mitra dan tanggal berlaku.';



CREATE TABLE IF NOT EXISTS "public"."harga_tbs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tanggal" "date" NOT NULL,
    "harga_per_kg" numeric(10,2) NOT NULL,
    "set_oleh" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."harga_tbs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hutang" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "petani_id" "uuid",
    "tanggal" "date" NOT NULL,
    "jenis" character varying(20) NOT NULL,
    "jumlah" numeric(15,2) NOT NULL,
    "keterangan" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "hutang_jenis_check" CHECK ((("jenis")::"text" = ANY ((ARRAY['kasbon'::character varying, 'panjar'::character varying, 'pupuk'::character varying, 'lainnya'::character varying])::"text"[])))
);


ALTER TABLE "public"."hutang" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hutang_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "petani_id" "uuid",
    "tanggal" "date" NOT NULL,
    "jumlah_bayar" numeric(15,2) NOT NULL,
    "sumber" character varying(20) NOT NULL,
    "transaksi_beli_id" "uuid",
    "keterangan" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "hutang_log_sumber_check" CHECK ((("sumber")::"text" = ANY ((ARRAY['potong_tbs'::character varying, 'bayar_tunai'::character varying])::"text"[])))
);


ALTER TABLE "public"."hutang_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kendaraan" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "plat_nomor" character varying(20) NOT NULL,
    "jenis" character varying(50),
    "kapasitas_ton" numeric(6,2),
    "kepemilikan" character varying(10) DEFAULT 'sendiri'::character varying,
    "aktif" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "kendaraan_kepemilikan_check" CHECK ((("kepemilikan")::"text" = ANY ((ARRAY['sendiri'::character varying, 'sewa'::character varying])::"text"[])))
);


ALTER TABLE "public"."kendaraan" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mitra" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nama" character varying(150) NOT NULL,
    "penanggung_jawab" character varying(100),
    "no_hp" character varying(30),
    "alamat" "text",
    "rekening" "text",
    "fee_per_kg" numeric(12,2) DEFAULT 0,
    "boleh_kasbon" boolean DEFAULT false,
    "batas_kasbon" numeric(15,2) DEFAULT 0,
    "persen_selisih_ditanggung_perusahaan" numeric(5,2),
    "persen_selisih_ditanggung_mitra" numeric(5,2),
    "aktif" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "mitra_persen_range_check" CHECK (((("persen_selisih_ditanggung_perusahaan" IS NULL) OR (("persen_selisih_ditanggung_perusahaan" >= (0)::numeric) AND ("persen_selisih_ditanggung_perusahaan" <= (100)::numeric))) AND (("persen_selisih_ditanggung_mitra" IS NULL) OR (("persen_selisih_ditanggung_mitra" >= (0)::numeric) AND ("persen_selisih_ditanggung_mitra" <= (100)::numeric))))),
    CONSTRAINT "mitra_persen_total_check" CHECK ((("persen_selisih_ditanggung_perusahaan" IS NULL) OR ("persen_selisih_ditanggung_mitra" IS NULL) OR (("persen_selisih_ditanggung_perusahaan" + "persen_selisih_ditanggung_mitra") = (100)::numeric)))
);


ALTER TABLE "public"."mitra" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pembayaran_mitra" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "settlement_id" "uuid" NOT NULL,
    "mitra_id" "uuid" NOT NULL,
    "tanggal" "date" NOT NULL,
    "jumlah" numeric(15,2) NOT NULL,
    "metode" "text",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "keterangan" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "pembayaran_mitra_jumlah_check" CHECK (("jumlah" >= (0)::numeric)),
    CONSTRAINT "pembayaran_mitra_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'dibayar'::"text", 'sebagian_koreksi'::"text", 'dibatalkan'::"text"])))
);


ALTER TABLE "public"."pembayaran_mitra" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pembayaran_mitra_kwitansi_item" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pembayaran_id" "uuid" NOT NULL,
    "transaksi_mitra_id" "uuid" NOT NULL,
    "tanggal" "date" NOT NULL,
    "waktu_transaksi" timestamp with time zone,
    "sopir_aktual_nama" "text",
    "plat_nomor" "text",
    "tonase_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "harga_bersih_per_kg_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_nilai_bersih_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "status_transaksi_snapshot" "text" DEFAULT 'aktif'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "master_mitra_id" "uuid",
    "mitra_label_snapshot" "text",
    "berat_netto_snapshot" numeric(12,2),
    "potongan_snapshot" numeric(12,2) DEFAULT 0 NOT NULL,
    "berat_dibayar_snapshot" numeric(12,2),
    "pakai_sewa_armada_snapshot" boolean DEFAULT false NOT NULL,
    "biaya_sewa_armada_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "tarif_sewa_angkut_per_kg_snapshot" numeric(12,2) DEFAULT 0 NOT NULL,
    "biaya_sewa_armada_standar_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "selisih_sewa_armada_historis_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "metode_sewa_armada_snapshot" "text" DEFAULT 'tidak_ada'::"text" NOT NULL,
    CONSTRAINT "pembayaran_mitra_item_metode_sewa_check" CHECK (("metode_sewa_armada_snapshot" = ANY (ARRAY['tidak_ada'::"text", 'netto_x_tarif'::"text", 'legacy_snapshot'::"text"])))
);


ALTER TABLE "public"."pembayaran_mitra_kwitansi_item" OWNER TO "postgres";


COMMENT ON COLUMN "public"."pembayaran_mitra_kwitansi_item"."biaya_sewa_armada_snapshot" IS 'Nominal sewa yang benar-benar ditagihkan pada kwitansi. Snapshot finansial ini tidak boleh mengikuti perubahan transaksi live.';



COMMENT ON COLUMN "public"."pembayaran_mitra_kwitansi_item"."tarif_sewa_angkut_per_kg_snapshot" IS 'Tarif sewa per kg saat kwitansi diterbitkan.';



COMMENT ON COLUMN "public"."pembayaran_mitra_kwitansi_item"."biaya_sewa_armada_standar_snapshot" IS 'Sewa standar saat kwitansi diterbitkan: berat netto snapshot dikali tarif snapshot.';



COMMENT ON COLUMN "public"."pembayaran_mitra_kwitansi_item"."selisih_sewa_armada_historis_snapshot" IS 'Sewa standar dikurangi sewa yang ditagihkan. Positif berarti kwitansi lama menagihkan lebih kecil.';



COMMENT ON COLUMN "public"."pembayaran_mitra_kwitansi_item"."metode_sewa_armada_snapshot" IS 'netto_x_tarif untuk rumus aktif; legacy_snapshot jika nominal historis berbeda atau dasar tarif lama tidak lengkap.';



CREATE TABLE IF NOT EXISTS "public"."pembayaran_mitra_kwitansi_mitra" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pembayaran_id" "uuid" NOT NULL,
    "master_mitra_id" "uuid" NOT NULL,
    "mitra_label_snapshot" "text",
    "total_tonase" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_nilai_bersih" numeric(15,2) DEFAULT 0 NOT NULL,
    "jumlah_transaksi" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "total_berat_netto" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_berat_dibayar" numeric(15,2) DEFAULT 0 NOT NULL,
    CONSTRAINT "pembayaran_mitra_kwitansi_mitra_total_check" CHECK ((("total_tonase" >= (0)::numeric) AND ("total_nilai_bersih" >= (0)::numeric) AND ("jumlah_transaksi" >= 0)))
);


ALTER TABLE "public"."pembayaran_mitra_kwitansi_mitra" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pembayaran_pabrik" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pabrik_id" "uuid",
    "tanggal_bayar" "date" NOT NULL,
    "total_bayar" numeric(15,2) NOT NULL,
    "metode" "text",
    "rekening_tujuan" "text",
    "referensi_transfer" "text",
    "bukti_transfer_url" "text",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "keterangan" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "rekening_kas_id" "uuid",
    "kas_ledger_id" "uuid",
    CONSTRAINT "pembayaran_pabrik_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'teralokasi_sebagian'::"text", 'teralokasi_penuh'::"text", 'dibatalkan'::"text"]))),
    CONSTRAINT "pembayaran_pabrik_total_bayar_check" CHECK (("total_bayar" >= (0)::numeric))
);


ALTER TABLE "public"."pembayaran_pabrik" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pembayaran_pabrik_detail" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pembayaran_pabrik_id" "uuid" NOT NULL,
    "pengiriman_id" "uuid" NOT NULL,
    "nomor_do" "text",
    "jumlah_dialokasikan" numeric(15,2) NOT NULL,
    "tonase_pabrik" numeric(14,2),
    "tonase_dasar_settlement" numeric(14,2),
    "harga_pabrik_per_kg" numeric(12,2),
    "potongan_sortasi_type" "text" DEFAULT 'none'::"text",
    "potongan_sortasi_value" numeric(14,2) DEFAULT 0,
    "potongan_sortasi_rupiah" numeric(15,2) DEFAULT 0,
    "biaya_timbang" numeric(15,2) DEFAULT 0,
    "potongan_pabrik_lain" numeric(15,2) DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "pembayaran_pabrik_detail_jumlah_dialokasikan_check" CHECK (("jumlah_dialokasikan" >= (0)::numeric)),
    CONSTRAINT "pembayaran_pabrik_detail_potongan_sortasi_type_check" CHECK (("potongan_sortasi_type" = ANY (ARRAY['none'::"text", 'kg'::"text", 'percent'::"text", 'nominal'::"text"])))
);


ALTER TABLE "public"."pembayaran_pabrik_detail" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pembayaran_pabrik_item" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pembayaran_id" "uuid" NOT NULL,
    "transaksi_mitra_id" "uuid" NOT NULL,
    "master_mitra_id" "uuid",
    "tanggal" "date" NOT NULL,
    "waktu_transaksi" timestamp with time zone,
    "mitra_label_snapshot" "text",
    "sopir_aktual_nama_snapshot" "text",
    "plat_nomor_snapshot" "text",
    "tonase_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "harga_pabrik_per_kg_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_nilai_pabrik_snapshot" numeric(15,2) DEFAULT 0 NOT NULL,
    "jumlah_dialokasikan" numeric(15,2) DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'aktif'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "berat_netto_snapshot" numeric(12,2),
    "berat_dibayar_snapshot" numeric(12,2),
    CONSTRAINT "pembayaran_pabrik_item_nominal_check" CHECK ((("tonase_snapshot" >= (0)::numeric) AND ("harga_pabrik_per_kg_snapshot" >= (0)::numeric) AND ("total_nilai_pabrik_snapshot" >= (0)::numeric) AND ("jumlah_dialokasikan" >= (0)::numeric))),
    CONSTRAINT "pembayaran_pabrik_item_status_check" CHECK (("status" = ANY (ARRAY['aktif'::"text", 'dibatalkan'::"text"])))
);


ALTER TABLE "public"."pembayaran_pabrik_item" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pengaturan_bisnis" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "value_json" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "scope" "text" DEFAULT 'global'::"text" NOT NULL,
    "scope_id" "uuid",
    "berlaku_mulai" timestamp with time zone DEFAULT "now"(),
    "aktif" boolean DEFAULT true,
    "updated_by" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "pengaturan_bisnis_scope_check" CHECK (("scope" = ANY (ARRAY['global'::"text", 'mitra'::"text", 'armada'::"text"])))
);


ALTER TABLE "public"."pengaturan_bisnis" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pengiriman_lokal_detail" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pengiriman_id" "uuid" NOT NULL,
    "transaksi_beli_id" "uuid" NOT NULL,
    "petani_id" "uuid",
    "berat_alokasi_kg" numeric(14,2) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "pengiriman_lokal_detail_berat_alokasi_kg_check" CHECK (("berat_alokasi_kg" > (0)::numeric))
);


ALTER TABLE "public"."pengiriman_lokal_detail" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."petani" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nama" character varying(100) NOT NULL,
    "no_ktp" character varying(20),
    "no_hp" character varying(20),
    "alamat" "text",
    "batas_hutang" numeric(15,2) DEFAULT 0,
    "aktif" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."petani" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."piutang_document_number_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."piutang_document_number_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rekening_kas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nama" "text" NOT NULL,
    "tipe" "text" DEFAULT 'kas'::"text" NOT NULL,
    "nomor_rekening" "text",
    "pemilik_rekening" "text",
    "saldo_awal" numeric(15,2) DEFAULT 0 NOT NULL,
    "aktif" boolean DEFAULT true NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "catatan" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "rekening_kas_saldo_awal_check" CHECK (("saldo_awal" >= (0)::numeric)),
    CONSTRAINT "rekening_kas_tipe_check" CHECK (("tipe" = ANY (ARRAY['kas'::"text", 'bank'::"text", 'e_wallet'::"text", 'lainnya'::"text"])))
);


ALTER TABLE "public"."rekening_kas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."settlement_mitra" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "mitra_id" "uuid" NOT NULL,
    "pengiriman_id" "uuid" NOT NULL,
    "nomor_do" "text",
    "tanggal_settlement" "date",
    "tonase_timbang_mitra" numeric(14,2),
    "tonase_pabrik" numeric(14,2),
    "tonase_dasar_settlement" numeric(14,2),
    "selisih_tonase" numeric(14,2),
    "nilai_selisih_tonase" numeric(15,2),
    "persen_selisih_ditanggung_perusahaan" numeric(5,2),
    "persen_selisih_ditanggung_mitra" numeric(5,2),
    "koreksi_selisih_dibayar_perusahaan" numeric(15,2) DEFAULT 0,
    "harga_pabrik_per_kg" numeric(12,2),
    "total_bruto_pabrik" numeric(15,2),
    "potongan_sortasi_type" "text" DEFAULT 'none'::"text",
    "potongan_sortasi_value" numeric(14,2) DEFAULT 0,
    "potongan_sortasi_rupiah" numeric(15,2) DEFAULT 0,
    "biaya_timbang" numeric(15,2) DEFAULT 0,
    "potongan_pabrik_lain" numeric(15,2) DEFAULT 0,
    "total_pembayaran_pabrik" numeric(15,2),
    "fee_per_kg" numeric(12,2) DEFAULT 0,
    "fee_perusahaan" numeric(15,2) DEFAULT 0,
    "potongan_armada" numeric(15,2) DEFAULT 0,
    "potongan_hutang_kasbon" numeric(15,2) DEFAULT 0,
    "potongan_lain" numeric(15,2) DEFAULT 0,
    "total_hak_mitra" numeric(15,2) DEFAULT 0,
    "total_dibayar" numeric(15,2) DEFAULT 0,
    "sisa_bayar" numeric(15,2) DEFAULT 0,
    "status" "text" DEFAULT 'belum_dihitung'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "settlement_mitra_potongan_sortasi_type_check" CHECK (("potongan_sortasi_type" = ANY (ARRAY['none'::"text", 'kg'::"text", 'percent'::"text", 'nominal'::"text"]))),
    CONSTRAINT "settlement_mitra_status_check" CHECK (("status" = ANY (ARRAY['belum_dihitung'::"text", 'menunggu_pembayaran_pabrik'::"text", 'menunggu_bayar_mitra'::"text", 'sebagian_koreksi'::"text", 'lunas'::"text", 'dibatalkan'::"text"])))
);


ALTER TABLE "public"."settlement_mitra" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."stok_tbs_lokal_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tanggal" "date" NOT NULL,
    "tipe" "text" NOT NULL,
    "sumber" "text" NOT NULL,
    "transaksi_beli_id" "uuid",
    "pengiriman_id" "uuid",
    "berat_kg" numeric(14,2) NOT NULL,
    "keterangan" "text",
    "related_ledger_id" "uuid",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "stok_tbs_lokal_ledger_sumber_check" CHECK (("sumber" = ANY (ARRAY['pembelian_petani'::"text", 'pengiriman_pabrik'::"text", 'koreksi_manual'::"text", 'reversal'::"text"]))),
    CONSTRAINT "stok_tbs_lokal_ledger_tipe_check" CHECK (("tipe" = ANY (ARRAY['masuk'::"text", 'keluar'::"text", 'koreksi'::"text", 'reversal'::"text"])))
);


ALTER TABLE "public"."stok_tbs_lokal_ledger" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tarif_armada" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "armada_id" "uuid",
    "tarif_per_km_per_ton" numeric(15,2) DEFAULT 0 NOT NULL,
    "minimum_charge" numeric(15,2) DEFAULT 0 NOT NULL,
    "berlaku_mulai" timestamp with time zone NOT NULL,
    "berlaku_sampai" timestamp with time zone,
    "aktif" boolean DEFAULT true,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "tarif_armada_minimum_charge_check" CHECK (("minimum_charge" >= (0)::numeric)),
    CONSTRAINT "tarif_armada_periode_check" CHECK ((("berlaku_sampai" IS NULL) OR ("berlaku_sampai" > "berlaku_mulai"))),
    CONSTRAINT "tarif_armada_tarif_per_km_per_ton_check" CHECK (("tarif_per_km_per_ton" >= (0)::numeric))
);


ALTER TABLE "public"."tarif_armada" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."transaksi_beli" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tanggal" "date" NOT NULL,
    "petani_id" "uuid",
    "berat_kotor" numeric(10,2) NOT NULL,
    "persen_potongan" numeric(5,2) DEFAULT 2.00,
    "berat_bersih" numeric(10,2) NOT NULL,
    "harga_per_kg" numeric(10,2) NOT NULL,
    "total_harga" numeric(15,2) NOT NULL,
    "potongan_hutang" numeric(15,2) DEFAULT 0,
    "total_bayar_tunai" numeric(15,2) NOT NULL,
    "keterangan" "text",
    "no_struk" character varying(20),
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."transaksi_beli" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."transaksi_beli_tbs_no_struk_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."transaksi_beli_tbs_no_struk_seq" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "nama" character varying(100) NOT NULL,
    "username" character varying(50),
    "role" "text" DEFAULT 'admin_operasional'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "users_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text", 'admin_keuangan'::"text"])))
);


ALTER TABLE "public"."users" OWNER TO "postgres";


ALTER TABLE ONLY "public"."armada_mitra"
    ADD CONSTRAINT "armada_mitra_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."armada_perusahaan"
    ADD CONSTRAINT "armada_perusahaan_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."armada_perusahaan"
    ADD CONSTRAINT "armada_perusahaan_plat_nomor_key" UNIQUE ("plat_nomor");



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."biaya_operasional"
    ADD CONSTRAINT "biaya_operasional_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bukti_pembayaran"
    ADD CONSTRAINT "bukti_pembayaran_nomor_bukti_key" UNIQUE ("nomor_bukti");



ALTER TABLE ONLY "public"."bukti_pembayaran"
    ADD CONSTRAINT "bukti_pembayaran_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fee_mitra_history"
    ADD CONSTRAINT "fee_mitra_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fee_owner_mitra_history"
    ADD CONSTRAINT "fee_owner_mitra_history_no_overlap" EXCLUDE USING "gist" ("master_mitra_id" WITH =, "daterange"("berlaku_mulai", COALESCE("berlaku_sampai", 'infinity'::"date"), '[]'::"text") WITH &&) WHERE (("aktif" = true));



ALTER TABLE ONLY "public"."fee_owner_mitra_history"
    ADD CONSTRAINT "fee_owner_mitra_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fee_owner_mitra_history"
    ADD CONSTRAINT "fee_owner_mitra_history_unique_start" UNIQUE ("master_mitra_id", "berlaku_mulai");



ALTER TABLE ONLY "public"."harga_tbs_lokal"
    ADD CONSTRAINT "harga_tbs_lokal_legacy_harga_tbs_id_key" UNIQUE ("legacy_harga_tbs_id");



ALTER TABLE ONLY "public"."harga_tbs_lokal"
    ADD CONSTRAINT "harga_tbs_lokal_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."harga_tbs"
    ADD CONSTRAINT "harga_tbs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."harga_tbs"
    ADD CONSTRAINT "harga_tbs_tanggal_key" UNIQUE ("tanggal");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hutang_log"
    ADD CONSTRAINT "hutang_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hutang"
    ADD CONSTRAINT "hutang_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kendaraan"
    ADD CONSTRAINT "kendaraan_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kendaraan"
    ADD CONSTRAINT "kendaraan_plat_nomor_key" UNIQUE ("plat_nomor");



ALTER TABLE ONLY "public"."master_mitra"
    ADD CONSTRAINT "master_mitra_kode_key" UNIQUE ("kode");



ALTER TABLE ONLY "public"."master_mitra"
    ADD CONSTRAINT "master_mitra_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mitra"
    ADD CONSTRAINT "mitra_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pabrik"
    ADD CONSTRAINT "pabrik_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."panjar_mitra"
    ADD CONSTRAINT "panjar_mitra_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi_item"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_item_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi_item"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_item_unique_payment_trx" UNIQUE ("pembayaran_id", "transaksi_mitra_id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi_mitra"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_mitra_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi_mitra"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_mitra_unique" UNIQUE ("pembayaran_id", "master_mitra_id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pembayaran_mitra"
    ADD CONSTRAINT "pembayaran_mitra_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_batch"
    ADD CONSTRAINT "pembayaran_pabrik_batch_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_detail"
    ADD CONSTRAINT "pembayaran_pabrik_detail_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_item"
    ADD CONSTRAINT "pembayaran_pabrik_item_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_item"
    ADD CONSTRAINT "pembayaran_pabrik_item_unique_payment_trx" UNIQUE ("pembayaran_id", "transaksi_mitra_id");



ALTER TABLE ONLY "public"."pembayaran_pabrik"
    ADD CONSTRAINT "pembayaran_pabrik_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pengaturan_bisnis"
    ADD CONSTRAINT "pengaturan_bisnis_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pengiriman_lokal_detail"
    ADD CONSTRAINT "pengiriman_lokal_detail_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pengiriman"
    ADD CONSTRAINT "pengiriman_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."petani"
    ADD CONSTRAINT "petani_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_nomor_bukti_key" UNIQUE ("nomor_bukti");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."piutang_pelunasan"
    ADD CONSTRAINT "piutang_pelunasan_nomor_bukti_key" UNIQUE ("nomor_bukti");



ALTER TABLE ONLY "public"."piutang_pelunasan"
    ADD CONSTRAINT "piutang_pelunasan_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rekening_kas"
    ADD CONSTRAINT "rekening_kas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."settlement_mitra"
    ADD CONSTRAINT "settlement_mitra_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sopir"
    ADD CONSTRAINT "sopir_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stok_tbs_lokal_ledger"
    ADD CONSTRAINT "stok_tbs_lokal_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tarif_armada"
    ADD CONSTRAINT "tarif_armada_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."transaksi_beli"
    ADD CONSTRAINT "transaksi_beli_no_struk_key" UNIQUE ("no_struk");



ALTER TABLE ONLY "public"."transaksi_beli"
    ADD CONSTRAINT "transaksi_beli_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."transaksi_beli_tbs"
    ADD CONSTRAINT "transaksi_beli_tbs_legacy_transaksi_beli_id_key" UNIQUE ("legacy_transaksi_beli_id");



ALTER TABLE ONLY "public"."transaksi_beli_tbs"
    ADD CONSTRAINT "transaksi_beli_tbs_no_struk_key" UNIQUE ("no_struk");



ALTER TABLE ONLY "public"."transaksi_beli_tbs"
    ADD CONSTRAINT "transaksi_beli_tbs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_audit_log_entity" ON "public"."audit_log" USING "btree" ("entity_type", "entity_id", "created_at" DESC);



CREATE INDEX "idx_biaya_operasional_armada_tanggal" ON "public"."biaya_operasional" USING "btree" ("armada_sopir_id", "tanggal" DESC) WHERE (("armada_sopir_id" IS NOT NULL) AND ("status" <> 'dibatalkan'::"text"));



CREATE INDEX "idx_biaya_operasional_kas" ON "public"."biaya_operasional" USING "btree" ("kas_ledger_id");



CREATE INDEX "idx_biaya_operasional_transaksi_mitra" ON "public"."biaya_operasional" USING "btree" ("transaksi_mitra_id") WHERE ("transaksi_mitra_id" IS NOT NULL);



CREATE INDEX "idx_biaya_tanggal" ON "public"."biaya_operasional" USING "btree" ("tanggal");



CREATE INDEX "idx_fee_mitra_history_mitra_mulai" ON "public"."fee_mitra_history" USING "btree" ("mitra_id", "berlaku_mulai" DESC);



CREATE INDEX "idx_fee_owner_mitra_history_mitra_mulai" ON "public"."fee_owner_mitra_history" USING "btree" ("master_mitra_id", "berlaku_mulai" DESC);



CREATE INDEX "idx_harga_tbs_lokal_aktif_mulai" ON "public"."harga_tbs_lokal" USING "btree" ("aktif", "berlaku_mulai" DESC);



CREATE INDEX "idx_hutang_ledger_kas" ON "public"."hutang_ledger" USING "btree" ("kas_ledger_id");



CREATE UNIQUE INDEX "idx_hutang_ledger_legacy" ON "public"."hutang_ledger" USING "btree" ("legacy_source_table", "legacy_source_id") WHERE (("legacy_source_table" IS NOT NULL) AND ("legacy_source_id" IS NOT NULL));



CREATE INDEX "idx_hutang_ledger_master_mitra" ON "public"."hutang_ledger" USING "btree" ("master_mitra_id");



CREATE INDEX "idx_hutang_ledger_pihak" ON "public"."hutang_ledger" USING "btree" ("pihak_type", "petani_id", "mitra_id");



CREATE INDEX "idx_hutang_ledger_sopir" ON "public"."hutang_ledger" USING "btree" ("sopir_id");



CREATE INDEX "idx_hutang_ledger_status_tanggal" ON "public"."hutang_ledger" USING "btree" ("status", "tanggal" DESC);



CREATE INDEX "idx_hutang_log_petani" ON "public"."hutang_log" USING "btree" ("petani_id");



CREATE INDEX "idx_hutang_petani" ON "public"."hutang" USING "btree" ("petani_id");



CREATE UNIQUE INDEX "idx_kas_ledger_idempotency_key" ON "public"."kas_ledger" USING "btree" ("idempotency_key") WHERE ("idempotency_key" IS NOT NULL);



CREATE INDEX "idx_kas_ledger_rekening_tanggal" ON "public"."kas_ledger" USING "btree" ("rekening_kas_id", "tanggal" DESC);



CREATE INDEX "idx_kas_ledger_source" ON "public"."kas_ledger" USING "btree" ("source_table", "source_id");



CREATE INDEX "idx_kas_ledger_status" ON "public"."kas_ledger" USING "btree" ("status");



CREATE INDEX "idx_kas_ledger_tanggal" ON "public"."kas_ledger" USING "btree" ("tanggal" DESC, "created_at" DESC);



CREATE INDEX "idx_kwitansi_item_transaksi" ON "public"."pembayaran_mitra_kwitansi_item" USING "btree" ("transaksi_mitra_id", "pembayaran_id");



CREATE INDEX "idx_master_mitra_tipe_mitra" ON "public"."master_mitra" USING "btree" ("tipe_mitra");



CREATE INDEX "idx_master_mitra_verifikasi" ON "public"."master_mitra" USING "btree" ("status_verifikasi", "aktif", "created_at" DESC);



CREATE INDEX "idx_mitra_aktif_nama" ON "public"."mitra" USING "btree" ("aktif", "nama");



CREATE INDEX "idx_panjar_mitra_kas" ON "public"."panjar_mitra" USING "btree" ("kas_ledger_id");



CREATE INDEX "idx_panjar_mitra_kwitansi" ON "public"."panjar_mitra" USING "btree" ("pembayaran_mitra_kwitansi_id") WHERE ("pembayaran_mitra_kwitansi_id" IS NOT NULL);



CREATE INDEX "idx_panjar_mitra_mitra" ON "public"."panjar_mitra" USING "btree" ("mitra_id");



CREATE INDEX "idx_pembayaran_mitra_kwitansi_item_mitra" ON "public"."pembayaran_mitra_kwitansi_item" USING "btree" ("master_mitra_id", "tanggal" DESC);



CREATE INDEX "idx_pembayaran_mitra_kwitansi_item_payment" ON "public"."pembayaran_mitra_kwitansi_item" USING "btree" ("pembayaran_id");



CREATE INDEX "idx_pembayaran_mitra_kwitansi_kas" ON "public"."pembayaran_mitra_kwitansi" USING "btree" ("kas_ledger_id");



CREATE INDEX "idx_pembayaran_mitra_kwitansi_mitra_ids_gin" ON "public"."pembayaran_mitra_kwitansi" USING "gin" ("mitra_ids");



CREATE INDEX "idx_pembayaran_mitra_kwitansi_mitra_mitra" ON "public"."pembayaran_mitra_kwitansi_mitra" USING "btree" ("master_mitra_id");



CREATE INDEX "idx_pembayaran_mitra_kwitansi_mitra_payment" ON "public"."pembayaran_mitra_kwitansi_mitra" USING "btree" ("pembayaran_id");



CREATE INDEX "idx_pembayaran_mitra_kwitansi_mitra_period" ON "public"."pembayaran_mitra_kwitansi" USING "btree" ("master_mitra_id", "periode_dari" DESC, "periode_sampai" DESC);



CREATE INDEX "idx_pembayaran_mitra_kwitansi_status_bayar" ON "public"."pembayaran_mitra_kwitansi" USING "btree" ("status", "tanggal_bayar" DESC);



CREATE INDEX "idx_pembayaran_pabrik_batch_kas" ON "public"."pembayaran_pabrik_batch" USING "btree" ("kas_ledger_id");



CREATE INDEX "idx_pembayaran_pabrik_batch_pabrik_tanggal" ON "public"."pembayaran_pabrik_batch" USING "btree" ("pabrik_id", "tanggal_bayar" DESC);



CREATE INDEX "idx_pembayaran_pabrik_batch_status" ON "public"."pembayaran_pabrik_batch" USING "btree" ("status", "tanggal_bayar" DESC);



CREATE INDEX "idx_pembayaran_pabrik_batch_tanggal" ON "public"."pembayaran_pabrik_batch" USING "btree" ("tanggal_bayar" DESC, "created_at" DESC);



CREATE INDEX "idx_pembayaran_pabrik_detail_pengiriman" ON "public"."pembayaran_pabrik_detail" USING "btree" ("pengiriman_id");



CREATE INDEX "idx_pembayaran_pabrik_item_mitra" ON "public"."pembayaran_pabrik_item" USING "btree" ("master_mitra_id", "tanggal" DESC);



CREATE INDEX "idx_pembayaran_pabrik_item_payment" ON "public"."pembayaran_pabrik_item" USING "btree" ("pembayaran_id");



CREATE UNIQUE INDEX "idx_pembayaran_pabrik_item_unique_active_trx" ON "public"."pembayaran_pabrik_item" USING "btree" ("transaksi_mitra_id") WHERE ("status" <> 'dibatalkan'::"text");



CREATE INDEX "idx_pembayaran_pabrik_kas" ON "public"."pembayaran_pabrik" USING "btree" ("kas_ledger_id");



CREATE INDEX "idx_pembayaran_pabrik_pabrik_tanggal" ON "public"."pembayaran_pabrik" USING "btree" ("pabrik_id", "tanggal_bayar");



CREATE UNIQUE INDEX "idx_pengaturan_bisnis_active_key_scope" ON "public"."pengaturan_bisnis" USING "btree" ("key", "scope", COALESCE("scope_id", '00000000-0000-0000-0000-000000000000'::"uuid")) WHERE ("aktif" = true);



CREATE INDEX "idx_pengiriman_kas" ON "public"."pengiriman" USING "btree" ("kas_ledger_id");



CREATE INDEX "idx_pengiriman_mitra" ON "public"."pengiriman" USING "btree" ("mitra_id");



CREATE UNIQUE INDEX "idx_pengiriman_nomor_do_pabrik_unique" ON "public"."pengiriman" USING "btree" ("pabrik_id", "nomor_do") WHERE (("nomor_do" IS NOT NULL) AND ("status" <> 'draft'::"text") AND ("status" <> 'dibatalkan'::"text"));



CREATE INDEX "idx_pengiriman_status" ON "public"."pengiriman" USING "btree" ("status");



CREATE INDEX "idx_pengiriman_sumber_tanggal" ON "public"."pengiriman" USING "btree" ("sumber", "tanggal");



CREATE INDEX "idx_pengiriman_tanggal" ON "public"."pengiriman" USING "btree" ("tanggal");



CREATE INDEX "idx_petani_aktif_nama" ON "public"."petani" USING "btree" ("aktif", "nama");



CREATE UNIQUE INDEX "idx_piutang_dokumen_panjar_unique" ON "public"."piutang_dokumen" USING "btree" ("panjar_mitra_id") WHERE ("panjar_mitra_id" IS NOT NULL);



CREATE INDEX "idx_piutang_dokumen_party" ON "public"."piutang_dokumen" USING "btree" ("pihak_type", "master_mitra_id", "sopir_id", "petani_id");



CREATE INDEX "idx_piutang_dokumen_status_date" ON "public"."piutang_dokumen" USING "btree" ("status", "tanggal_pengajuan" DESC);



CREATE INDEX "idx_piutang_pelunasan_document" ON "public"."piutang_pelunasan" USING "btree" ("piutang_dokumen_id", "status", "tanggal" DESC);



CREATE INDEX "idx_rekening_kas_aktif" ON "public"."rekening_kas" USING "btree" ("aktif", "is_default" DESC, "nama");



CREATE UNIQUE INDEX "idx_rekening_kas_default_active" ON "public"."rekening_kas" USING "btree" ("is_default") WHERE (("is_default" = true) AND ("aktif" = true));



CREATE INDEX "idx_settlement_mitra_mitra" ON "public"."settlement_mitra" USING "btree" ("mitra_id");



CREATE UNIQUE INDEX "idx_settlement_mitra_pengiriman_unique" ON "public"."settlement_mitra" USING "btree" ("pengiriman_id") WHERE ("status" <> 'dibatalkan'::"text");



CREATE INDEX "idx_sopir_armada_cb_aktif" ON "public"."sopir" USING "btree" ("aktif", "nama") WHERE ("is_armada_cb" = true);



CREATE INDEX "idx_sopir_plat_normalized" ON "public"."sopir" USING "btree" ("public"."normalize_plat_nomor"(("plat_nomor")::"text")) WHERE ((COALESCE("aktif", true) = true) AND (NULLIF("btrim"((COALESCE("plat_nomor", ''::character varying))::"text"), ''::"text") IS NOT NULL));



CREATE INDEX "idx_sopir_verifikasi" ON "public"."sopir" USING "btree" ("status_verifikasi", "aktif", "created_at" DESC);



CREATE INDEX "idx_stok_tbs_lokal_tanggal" ON "public"."stok_tbs_lokal_ledger" USING "btree" ("tanggal");



CREATE INDEX "idx_stok_tbs_lokal_transaksi" ON "public"."stok_tbs_lokal_ledger" USING "btree" ("transaksi_beli_id");



CREATE INDEX "idx_tarif_armada_armada_mulai" ON "public"."tarif_armada" USING "btree" ("armada_id", "berlaku_mulai" DESC);



CREATE INDEX "idx_transaksi_beli_petani" ON "public"."transaksi_beli" USING "btree" ("petani_id");



CREATE INDEX "idx_transaksi_beli_tanggal" ON "public"."transaksi_beli" USING "btree" ("tanggal");



CREATE INDEX "idx_transaksi_beli_tbs_kas" ON "public"."transaksi_beli_tbs" USING "btree" ("kas_ledger_id");



CREATE INDEX "idx_transaksi_beli_tbs_petani" ON "public"."transaksi_beli_tbs" USING "btree" ("petani_id");



CREATE INDEX "idx_transaksi_beli_tbs_tanggal" ON "public"."transaksi_beli_tbs" USING "btree" ("tanggal");



CREATE INDEX "idx_transaksi_mitra_armada_cb_review" ON "public"."transaksi_mitra" USING "btree" ("tanggal", "created_at") WHERE (("armada_cb_perlu_review" = true) AND ("status" = 'aktif'::"text"));



CREATE INDEX "idx_transaksi_mitra_armada_cb_trip" ON "public"."transaksi_mitra" USING "btree" ("tanggal", "sopir_id") WHERE (("menggunakan_armada_cb_snapshot" = true) AND ("status" = 'aktif'::"text"));



CREATE INDEX "idx_transaksi_mitra_berat_dibayar" ON "public"."transaksi_mitra" USING "btree" ("berat_dibayar_kg") WHERE ("berat_dibayar_kg" IS NOT NULL);



CREATE INDEX "idx_transaksi_mitra_biaya_sopir" ON "public"."transaksi_mitra" USING "btree" ("biaya_sopir_operasional_id") WHERE ("biaya_sopir_operasional_id" IS NOT NULL);



CREATE INDEX "idx_transaksi_mitra_dibatalkan" ON "public"."transaksi_mitra" USING "btree" ("dibatalkan_at" DESC) WHERE ("status" = 'dibatalkan'::"text");



CREATE INDEX "idx_transaksi_mitra_fee_owner_history" ON "public"."transaksi_mitra" USING "btree" ("fee_owner_history_id");



CREATE INDEX "idx_transaksi_mitra_mitra" ON "public"."transaksi_mitra" USING "btree" ("mitra_id");



CREATE INDEX "idx_transaksi_mitra_pakai_sewa_armada" ON "public"."transaksi_mitra" USING "btree" ("pakai_sewa_armada_bl") WHERE ("pakai_sewa_armada_bl" = true);



CREATE INDEX "idx_transaksi_mitra_pembayaran_pabrik_batch" ON "public"."transaksi_mitra" USING "btree" ("pembayaran_pabrik_batch_id");



CREATE INDEX "idx_transaksi_mitra_pembayaran_pabrik_status" ON "public"."transaksi_mitra" USING "btree" ("pembayaran_pabrik_status", "tanggal" DESC);



CREATE INDEX "idx_transaksi_mitra_sopir_aktual" ON "public"."transaksi_mitra" USING "btree" ("sopir_aktual_id");



CREATE INDEX "idx_transaksi_mitra_sopir_diganti" ON "public"."transaksi_mitra" USING "btree" ("sopir_diganti_dari_default") WHERE ("sopir_diganti_dari_default" = true);



CREATE INDEX "idx_transaksi_mitra_status_tanggal" ON "public"."transaksi_mitra" USING "btree" ("status", "tanggal" DESC);



CREATE INDEX "idx_transaksi_mitra_tagihan_sopir" ON "public"."transaksi_mitra" USING "btree" ("tagihan_sopir_ledger_id") WHERE ("tagihan_sopir_ledger_id" IS NOT NULL);



CREATE INDEX "idx_transaksi_mitra_tanggal" ON "public"."transaksi_mitra" USING "btree" ("tanggal");



CREATE INDEX "idx_transaksi_mitra_tanggal_created_at" ON "public"."transaksi_mitra" USING "btree" ("tanggal" DESC, "created_at" DESC);



CREATE OR REPLACE TRIGGER "a_enrich_kwitansi_panjar_snapshot_owner" BEFORE INSERT OR UPDATE OF "panjar_snapshot_json" ON "public"."pembayaran_mitra_kwitansi" FOR EACH ROW EXECUTE FUNCTION "public"."enrich_kwitansi_panjar_snapshot_owner"();



CREATE OR REPLACE TRIGGER "archive_reconciled_legacy_panjar" AFTER UPDATE OF "hutang_ledger_id" ON "public"."panjar_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."archive_reconciled_legacy_panjar"();



CREATE OR REPLACE TRIGGER "flag_kwitansi_after_system_change" AFTER UPDATE ON "public"."transaksi_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."flag_kwitansi_after_system_change"();



CREATE OR REPLACE TRIGGER "guard_master_mitra_sensitive_changes" BEFORE INSERT OR UPDATE ON "public"."master_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."guard_master_mitra_sensitive_changes"();



CREATE OR REPLACE TRIGGER "guard_paid_transaksi_mitra_changes" BEFORE UPDATE ON "public"."transaksi_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."guard_paid_transaksi_mitra_changes"();



CREATE OR REPLACE TRIGGER "guard_sopir_armada_verification" BEFORE INSERT OR UPDATE ON "public"."sopir" FOR EACH ROW EXECUTE FUNCTION "public"."guard_sopir_armada_verification"();



CREATE OR REPLACE TRIGGER "normalize_armada_cb" BEFORE INSERT OR UPDATE OF "tanggal", "sopir_id", "mitra_id", "berat_netto_pabrik_kg", "tonase", "tarif_sewa_angkut_per_kg_snapshot", "biaya_sewa_armada_per_kg", "pakai_sewa_armada_bl", "kenakan_sewa_armada_cb", "catat_dana_operasional_trip", "alasan_tanpa_sewa_armada_cb", "alasan_tanpa_dana_operasional_trip" ON "public"."transaksi_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."normalize_transaksi_mitra_armada_cb"();



CREATE OR REPLACE TRIGGER "prevent_kwitansi_item_snapshot_update" BEFORE UPDATE ON "public"."pembayaran_mitra_kwitansi_item" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_kwitansi_item_snapshot_update"();



CREATE OR REPLACE TRIGGER "require_factory_payment_proof" BEFORE INSERT OR UPDATE OF "metode_bayar", "nomor_bukti" ON "public"."pembayaran_pabrik_batch" FOR EACH ROW EXECUTE FUNCTION "public"."require_factory_payment_proof"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."armada_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."armada_perusahaan" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."biaya_operasional" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."harga_tbs_lokal" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."hutang_ledger" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."kas_ledger" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."mitra" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."pabrik" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."panjar_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."pembayaran_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."pembayaran_mitra_kwitansi" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."pembayaran_pabrik" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."pembayaran_pabrik_batch" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."pengaturan_bisnis" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."pengiriman" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."petani" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."rekening_kas" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."settlement_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."transaksi_beli_tbs" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."transaksi_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "snapshot_sewa_item_kwitansi" BEFORE INSERT ON "public"."pembayaran_mitra_kwitansi_item" FOR EACH ROW EXECUTE FUNCTION "public"."snapshot_sewa_item_kwitansi"();



CREATE OR REPLACE TRIGGER "sync_kwitansi_totals_from_item" AFTER INSERT OR DELETE ON "public"."pembayaran_mitra_kwitansi_item" FOR EACH ROW EXECUTE FUNCTION "public"."sync_kwitansi_totals_from_item"();



CREATE OR REPLACE TRIGGER "sync_kwitansi_totals_from_summary" AFTER INSERT ON "public"."pembayaran_mitra_kwitansi_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."sync_kwitansi_totals_from_summary"();



CREATE OR REPLACE TRIGGER "sync_piutang_document_from_panjar" AFTER UPDATE OF "status" ON "public"."panjar_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."sync_piutang_document_from_panjar"();



CREATE OR REPLACE TRIGGER "sync_tagihan_sopir_cb" AFTER INSERT OR UPDATE OF "tanggal", "sopir_id", "mitra_id", "status", "menggunakan_armada_cb_snapshot", "catat_dana_operasional_trip", "dana_operasional_trip_snapshot", "total_biaya_sopir_cb_snapshot", "tagihan_sopir_ledger_id" ON "public"."transaksi_mitra" FOR EACH ROW EXECUTE FUNCTION "public"."sync_tagihan_sopir_cb"();



CREATE OR REPLACE TRIGGER "validate_kwitansi_deductions_per_mitra" BEFORE INSERT OR UPDATE OF "transaksi_snapshot_json", "panjar_snapshot_json" ON "public"."pembayaran_mitra_kwitansi" FOR EACH ROW EXECUTE FUNCTION "public"."validate_kwitansi_deductions_per_mitra"();



ALTER TABLE ONLY "public"."armada_mitra"
    ADD CONSTRAINT "armada_mitra_mitra_id_fkey" FOREIGN KEY ("mitra_id") REFERENCES "public"."mitra"("id");



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."biaya_operasional"
    ADD CONSTRAINT "biaya_operasional_armada_sopir_id_fkey" FOREIGN KEY ("armada_sopir_id") REFERENCES "public"."sopir"("id");



ALTER TABLE ONLY "public"."biaya_operasional"
    ADD CONSTRAINT "biaya_operasional_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."biaya_operasional"
    ADD CONSTRAINT "biaya_operasional_dibatalkan_by_fkey" FOREIGN KEY ("dibatalkan_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."biaya_operasional"
    ADD CONSTRAINT "biaya_operasional_kas_ledger_id_fkey" FOREIGN KEY ("kas_ledger_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."biaya_operasional"
    ADD CONSTRAINT "biaya_operasional_pengiriman_id_fkey" FOREIGN KEY ("pengiriman_id") REFERENCES "public"."pengiriman"("id");



ALTER TABLE ONLY "public"."biaya_operasional"
    ADD CONSTRAINT "biaya_operasional_rekening_kas_id_fkey" FOREIGN KEY ("rekening_kas_id") REFERENCES "public"."rekening_kas"("id");



ALTER TABLE ONLY "public"."biaya_operasional"
    ADD CONSTRAINT "biaya_operasional_settlement_id_fkey" FOREIGN KEY ("settlement_id") REFERENCES "public"."settlement_mitra"("id");



ALTER TABLE ONLY "public"."biaya_operasional"
    ADD CONSTRAINT "biaya_operasional_transaksi_mitra_id_fkey" FOREIGN KEY ("transaksi_mitra_id") REFERENCES "public"."transaksi_mitra"("id");



ALTER TABLE ONLY "public"."bukti_pembayaran"
    ADD CONSTRAINT "bukti_pembayaran_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."bukti_pembayaran"
    ADD CONSTRAINT "bukti_pembayaran_pembayaran_mitra_id_fkey" FOREIGN KEY ("pembayaran_mitra_id") REFERENCES "public"."pembayaran_mitra"("id");



ALTER TABLE ONLY "public"."bukti_pembayaran"
    ADD CONSTRAINT "bukti_pembayaran_pembayaran_pabrik_id_fkey" FOREIGN KEY ("pembayaran_pabrik_id") REFERENCES "public"."pembayaran_pabrik"("id");



ALTER TABLE ONLY "public"."bukti_pembayaran"
    ADD CONSTRAINT "bukti_pembayaran_transaksi_beli_id_fkey" FOREIGN KEY ("transaksi_beli_id") REFERENCES "public"."transaksi_beli_tbs"("id");



ALTER TABLE ONLY "public"."fee_mitra_history"
    ADD CONSTRAINT "fee_mitra_history_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."fee_mitra_history"
    ADD CONSTRAINT "fee_mitra_history_mitra_id_fkey" FOREIGN KEY ("mitra_id") REFERENCES "public"."mitra"("id");



ALTER TABLE ONLY "public"."fee_owner_mitra_history"
    ADD CONSTRAINT "fee_owner_mitra_history_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."fee_owner_mitra_history"
    ADD CONSTRAINT "fee_owner_mitra_history_master_mitra_id_fkey" FOREIGN KEY ("master_mitra_id") REFERENCES "public"."master_mitra"("id");



ALTER TABLE ONLY "public"."harga_tbs_lokal"
    ADD CONSTRAINT "harga_tbs_lokal_set_oleh_fkey" FOREIGN KEY ("set_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."harga_tbs_lokal"
    ADD CONSTRAINT "harga_tbs_lokal_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."harga_tbs"
    ADD CONSTRAINT "harga_tbs_set_oleh_fkey" FOREIGN KEY ("set_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."hutang"
    ADD CONSTRAINT "hutang_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_dibatalkan_by_fkey" FOREIGN KEY ("dibatalkan_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_kas_ledger_id_fkey" FOREIGN KEY ("kas_ledger_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_master_mitra_id_fkey" FOREIGN KEY ("master_mitra_id") REFERENCES "public"."master_mitra"("id");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_mitra_id_fkey" FOREIGN KEY ("mitra_id") REFERENCES "public"."mitra"("id");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_petani_id_fkey" FOREIGN KEY ("petani_id") REFERENCES "public"."petani"("id");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_rekening_kas_id_fkey" FOREIGN KEY ("rekening_kas_id") REFERENCES "public"."rekening_kas"("id");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_reversal_of_id_fkey" FOREIGN KEY ("reversal_of_id") REFERENCES "public"."hutang_ledger"("id");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_settlement_fk" FOREIGN KEY ("settlement_id") REFERENCES "public"."settlement_mitra"("id");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_sopir_id_fkey" FOREIGN KEY ("sopir_id") REFERENCES "public"."sopir"("id");



ALTER TABLE ONLY "public"."hutang_ledger"
    ADD CONSTRAINT "hutang_ledger_transaksi_beli_id_fkey" FOREIGN KEY ("transaksi_beli_id") REFERENCES "public"."transaksi_beli_tbs"("id");



ALTER TABLE ONLY "public"."hutang_log"
    ADD CONSTRAINT "hutang_log_petani_id_fkey" FOREIGN KEY ("petani_id") REFERENCES "public"."petani"("id");



ALTER TABLE ONLY "public"."hutang_log"
    ADD CONSTRAINT "hutang_log_transaksi_beli_id_fkey" FOREIGN KEY ("transaksi_beli_id") REFERENCES "public"."transaksi_beli"("id");



ALTER TABLE ONLY "public"."hutang"
    ADD CONSTRAINT "hutang_petani_id_fkey" FOREIGN KEY ("petani_id") REFERENCES "public"."petani"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_biaya_operasional_id_fkey" FOREIGN KEY ("biaya_operasional_id") REFERENCES "public"."biaya_operasional"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_dibatalkan_by_fkey" FOREIGN KEY ("dibatalkan_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_hutang_ledger_id_fkey" FOREIGN KEY ("hutang_ledger_id") REFERENCES "public"."hutang_ledger"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_panjar_mitra_id_fkey" FOREIGN KEY ("panjar_mitra_id") REFERENCES "public"."panjar_mitra"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_pembayaran_mitra_kwitansi_id_fkey" FOREIGN KEY ("pembayaran_mitra_kwitansi_id") REFERENCES "public"."pembayaran_mitra_kwitansi"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_pembayaran_pabrik_id_fkey" FOREIGN KEY ("pembayaran_pabrik_id") REFERENCES "public"."pembayaran_pabrik"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_pengiriman_id_fkey" FOREIGN KEY ("pengiriman_id") REFERENCES "public"."pengiriman"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_rekening_kas_id_fkey" FOREIGN KEY ("rekening_kas_id") REFERENCES "public"."rekening_kas"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_reversal_of_id_fkey" FOREIGN KEY ("reversal_of_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_reversed_by_fkey" FOREIGN KEY ("reversed_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."kas_ledger"
    ADD CONSTRAINT "kas_ledger_transaksi_beli_id_fkey" FOREIGN KEY ("transaksi_beli_id") REFERENCES "public"."transaksi_beli_tbs"("id");



ALTER TABLE ONLY "public"."master_mitra"
    ADD CONSTRAINT "master_mitra_dibuat_oleh_fkey" FOREIGN KEY ("dibuat_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."master_mitra"
    ADD CONSTRAINT "master_mitra_diverifikasi_oleh_fkey" FOREIGN KEY ("diverifikasi_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pabrik"
    ADD CONSTRAINT "pabrik_dibuat_oleh_fkey" FOREIGN KEY ("dibuat_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pabrik"
    ADD CONSTRAINT "pabrik_diverifikasi_oleh_fkey" FOREIGN KEY ("diverifikasi_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."panjar_mitra"
    ADD CONSTRAINT "panjar_mitra_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."panjar_mitra"
    ADD CONSTRAINT "panjar_mitra_dibatalkan_by_fkey" FOREIGN KEY ("dibatalkan_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."panjar_mitra"
    ADD CONSTRAINT "panjar_mitra_hutang_ledger_id_fkey" FOREIGN KEY ("hutang_ledger_id") REFERENCES "public"."hutang_ledger"("id");



ALTER TABLE ONLY "public"."panjar_mitra"
    ADD CONSTRAINT "panjar_mitra_kas_ledger_id_fkey" FOREIGN KEY ("kas_ledger_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."panjar_mitra"
    ADD CONSTRAINT "panjar_mitra_mitra_id_fkey" FOREIGN KEY ("mitra_id") REFERENCES "public"."master_mitra"("id");



ALTER TABLE ONLY "public"."panjar_mitra"
    ADD CONSTRAINT "panjar_mitra_pembayaran_mitra_kwitansi_id_fkey" FOREIGN KEY ("pembayaran_mitra_kwitansi_id") REFERENCES "public"."pembayaran_mitra_kwitansi"("id");



ALTER TABLE ONLY "public"."panjar_mitra"
    ADD CONSTRAINT "panjar_mitra_rekening_kas_id_fkey" FOREIGN KEY ("rekening_kas_id") REFERENCES "public"."rekening_kas"("id");



ALTER TABLE ONLY "public"."panjar_mitra"
    ADD CONSTRAINT "panjar_mitra_settlement_hutang_ledger_id_fkey" FOREIGN KEY ("settlement_hutang_ledger_id") REFERENCES "public"."hutang_ledger"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra"
    ADD CONSTRAINT "pembayaran_mitra_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_dibatalkan_by_fkey" FOREIGN KEY ("dibatalkan_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi_item"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_item_master_mitra_id_fkey" FOREIGN KEY ("master_mitra_id") REFERENCES "public"."master_mitra"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi_item"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_item_pembayaran_id_fkey" FOREIGN KEY ("pembayaran_id") REFERENCES "public"."pembayaran_mitra_kwitansi"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi_item"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_item_transaksi_mitra_id_fkey" FOREIGN KEY ("transaksi_mitra_id") REFERENCES "public"."transaksi_mitra"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_kas_ledger_id_fkey" FOREIGN KEY ("kas_ledger_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_master_mitra_id_fkey" FOREIGN KEY ("master_mitra_id") REFERENCES "public"."master_mitra"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi_mitra"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_mitra_master_mitra_id_fkey" FOREIGN KEY ("master_mitra_id") REFERENCES "public"."master_mitra"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi_mitra"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_mitra_pembayaran_id_fkey" FOREIGN KEY ("pembayaran_id") REFERENCES "public"."pembayaran_mitra_kwitansi"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_rekening_kas_id_fkey" FOREIGN KEY ("rekening_kas_id") REFERENCES "public"."rekening_kas"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_reversal_kas_ledger_id_fkey" FOREIGN KEY ("reversal_kas_ledger_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra_kwitansi"
    ADD CONSTRAINT "pembayaran_mitra_kwitansi_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra"
    ADD CONSTRAINT "pembayaran_mitra_mitra_id_fkey" FOREIGN KEY ("mitra_id") REFERENCES "public"."mitra"("id");



ALTER TABLE ONLY "public"."pembayaran_mitra"
    ADD CONSTRAINT "pembayaran_mitra_settlement_id_fkey" FOREIGN KEY ("settlement_id") REFERENCES "public"."settlement_mitra"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_batch"
    ADD CONSTRAINT "pembayaran_pabrik_batch_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_batch"
    ADD CONSTRAINT "pembayaran_pabrik_batch_dibatalkan_by_fkey" FOREIGN KEY ("dibatalkan_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_batch"
    ADD CONSTRAINT "pembayaran_pabrik_batch_kas_ledger_id_fkey" FOREIGN KEY ("kas_ledger_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_batch"
    ADD CONSTRAINT "pembayaran_pabrik_batch_pabrik_id_fkey" FOREIGN KEY ("pabrik_id") REFERENCES "public"."pabrik"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_batch"
    ADD CONSTRAINT "pembayaran_pabrik_batch_rekening_kas_id_fkey" FOREIGN KEY ("rekening_kas_id") REFERENCES "public"."rekening_kas"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_batch"
    ADD CONSTRAINT "pembayaran_pabrik_batch_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik"
    ADD CONSTRAINT "pembayaran_pabrik_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_detail"
    ADD CONSTRAINT "pembayaran_pabrik_detail_pembayaran_pabrik_id_fkey" FOREIGN KEY ("pembayaran_pabrik_id") REFERENCES "public"."pembayaran_pabrik"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pembayaran_pabrik_detail"
    ADD CONSTRAINT "pembayaran_pabrik_detail_pengiriman_id_fkey" FOREIGN KEY ("pengiriman_id") REFERENCES "public"."pengiriman"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_item"
    ADD CONSTRAINT "pembayaran_pabrik_item_master_mitra_id_fkey" FOREIGN KEY ("master_mitra_id") REFERENCES "public"."master_mitra"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik_item"
    ADD CONSTRAINT "pembayaran_pabrik_item_pembayaran_id_fkey" FOREIGN KEY ("pembayaran_id") REFERENCES "public"."pembayaran_pabrik_batch"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pembayaran_pabrik_item"
    ADD CONSTRAINT "pembayaran_pabrik_item_transaksi_mitra_id_fkey" FOREIGN KEY ("transaksi_mitra_id") REFERENCES "public"."transaksi_mitra"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik"
    ADD CONSTRAINT "pembayaran_pabrik_kas_ledger_id_fkey" FOREIGN KEY ("kas_ledger_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik"
    ADD CONSTRAINT "pembayaran_pabrik_pabrik_id_fkey" FOREIGN KEY ("pabrik_id") REFERENCES "public"."pabrik"("id");



ALTER TABLE ONLY "public"."pembayaran_pabrik"
    ADD CONSTRAINT "pembayaran_pabrik_rekening_kas_id_fkey" FOREIGN KEY ("rekening_kas_id") REFERENCES "public"."rekening_kas"("id");



ALTER TABLE ONLY "public"."pengaturan_bisnis"
    ADD CONSTRAINT "pengaturan_bisnis_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pengiriman"
    ADD CONSTRAINT "pengiriman_armada_perusahaan_id_fkey" FOREIGN KEY ("armada_perusahaan_id") REFERENCES "public"."armada_perusahaan"("id");



ALTER TABLE ONLY "public"."pengiriman"
    ADD CONSTRAINT "pengiriman_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."pengiriman"
    ADD CONSTRAINT "pengiriman_kas_ledger_id_fkey" FOREIGN KEY ("kas_ledger_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."pengiriman"
    ADD CONSTRAINT "pengiriman_kendaraan_id_fkey" FOREIGN KEY ("kendaraan_id") REFERENCES "public"."kendaraan"("id");



ALTER TABLE ONLY "public"."pengiriman_lokal_detail"
    ADD CONSTRAINT "pengiriman_lokal_detail_petani_id_fkey" FOREIGN KEY ("petani_id") REFERENCES "public"."petani"("id");



ALTER TABLE ONLY "public"."pengiriman_lokal_detail"
    ADD CONSTRAINT "pengiriman_lokal_detail_transaksi_beli_id_fkey" FOREIGN KEY ("transaksi_beli_id") REFERENCES "public"."transaksi_beli_tbs"("id");



ALTER TABLE ONLY "public"."pengiriman"
    ADD CONSTRAINT "pengiriman_mitra_id_fkey" FOREIGN KEY ("mitra_id") REFERENCES "public"."mitra"("id");



ALTER TABLE ONLY "public"."pengiriman"
    ADD CONSTRAINT "pengiriman_pabrik_id_fkey" FOREIGN KEY ("pabrik_id") REFERENCES "public"."pabrik"("id");



ALTER TABLE ONLY "public"."pengiriman"
    ADD CONSTRAINT "pengiriman_pembayaran_pabrik_id_fkey" FOREIGN KEY ("pembayaran_pabrik_id") REFERENCES "public"."pembayaran_pabrik"("id");



ALTER TABLE ONLY "public"."pengiriman"
    ADD CONSTRAINT "pengiriman_rekening_kas_id_fkey" FOREIGN KEY ("rekening_kas_id") REFERENCES "public"."rekening_kas"("id");



ALTER TABLE ONLY "public"."pengiriman"
    ADD CONSTRAINT "pengiriman_sopir_id_fkey" FOREIGN KEY ("sopir_id") REFERENCES "public"."sopir"("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_diajukan_oleh_fkey" FOREIGN KEY ("diajukan_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_dibatalkan_oleh_fkey" FOREIGN KEY ("dibatalkan_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_diserahkan_oleh_fkey" FOREIGN KEY ("diserahkan_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_disetujui_oleh_fkey" FOREIGN KEY ("disetujui_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_hutang_ledger_id_fkey" FOREIGN KEY ("hutang_ledger_id") REFERENCES "public"."hutang_ledger"("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_kas_ledger_id_fkey" FOREIGN KEY ("kas_ledger_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_master_mitra_id_fkey" FOREIGN KEY ("master_mitra_id") REFERENCES "public"."master_mitra"("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_panjar_mitra_id_fkey" FOREIGN KEY ("panjar_mitra_id") REFERENCES "public"."panjar_mitra"("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_petani_id_fkey" FOREIGN KEY ("petani_id") REFERENCES "public"."petani"("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_rekening_kas_id_fkey" FOREIGN KEY ("rekening_kas_id") REFERENCES "public"."rekening_kas"("id");



ALTER TABLE ONLY "public"."piutang_dokumen"
    ADD CONSTRAINT "piutang_dokumen_sopir_id_fkey" FOREIGN KEY ("sopir_id") REFERENCES "public"."sopir"("id");



ALTER TABLE ONLY "public"."piutang_pelunasan"
    ADD CONSTRAINT "piutang_pelunasan_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."piutang_pelunasan"
    ADD CONSTRAINT "piutang_pelunasan_hutang_ledger_id_fkey" FOREIGN KEY ("hutang_ledger_id") REFERENCES "public"."hutang_ledger"("id");



ALTER TABLE ONLY "public"."piutang_pelunasan"
    ADD CONSTRAINT "piutang_pelunasan_kas_ledger_id_fkey" FOREIGN KEY ("kas_ledger_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."piutang_pelunasan"
    ADD CONSTRAINT "piutang_pelunasan_piutang_dokumen_id_fkey" FOREIGN KEY ("piutang_dokumen_id") REFERENCES "public"."piutang_dokumen"("id");



ALTER TABLE ONLY "public"."rekening_kas"
    ADD CONSTRAINT "rekening_kas_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."settlement_mitra"
    ADD CONSTRAINT "settlement_mitra_mitra_id_fkey" FOREIGN KEY ("mitra_id") REFERENCES "public"."mitra"("id");



ALTER TABLE ONLY "public"."settlement_mitra"
    ADD CONSTRAINT "settlement_mitra_pengiriman_id_fkey" FOREIGN KEY ("pengiriman_id") REFERENCES "public"."pengiriman"("id");



ALTER TABLE ONLY "public"."sopir"
    ADD CONSTRAINT "sopir_armada_perusahaan_id_fkey" FOREIGN KEY ("armada_perusahaan_id") REFERENCES "public"."armada_perusahaan"("id");



ALTER TABLE ONLY "public"."sopir"
    ADD CONSTRAINT "sopir_dibuat_oleh_fkey" FOREIGN KEY ("dibuat_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."sopir"
    ADD CONSTRAINT "sopir_diverifikasi_oleh_fkey" FOREIGN KEY ("diverifikasi_oleh") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."sopir"
    ADD CONSTRAINT "sopir_kendaraan_id_fkey" FOREIGN KEY ("kendaraan_id") REFERENCES "public"."kendaraan"("id");



ALTER TABLE ONLY "public"."sopir"
    ADD CONSTRAINT "sopir_mitra_id_fkey" FOREIGN KEY ("mitra_id") REFERENCES "public"."master_mitra"("id");



ALTER TABLE ONLY "public"."stok_tbs_lokal_ledger"
    ADD CONSTRAINT "stok_tbs_lokal_ledger_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."stok_tbs_lokal_ledger"
    ADD CONSTRAINT "stok_tbs_lokal_ledger_related_ledger_id_fkey" FOREIGN KEY ("related_ledger_id") REFERENCES "public"."stok_tbs_lokal_ledger"("id");



ALTER TABLE ONLY "public"."stok_tbs_lokal_ledger"
    ADD CONSTRAINT "stok_tbs_lokal_ledger_transaksi_beli_id_fkey" FOREIGN KEY ("transaksi_beli_id") REFERENCES "public"."transaksi_beli_tbs"("id");



ALTER TABLE ONLY "public"."tarif_armada"
    ADD CONSTRAINT "tarif_armada_armada_id_fkey" FOREIGN KEY ("armada_id") REFERENCES "public"."armada_perusahaan"("id");



ALTER TABLE ONLY "public"."tarif_armada"
    ADD CONSTRAINT "tarif_armada_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."transaksi_beli"
    ADD CONSTRAINT "transaksi_beli_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."transaksi_beli"
    ADD CONSTRAINT "transaksi_beli_petani_id_fkey" FOREIGN KEY ("petani_id") REFERENCES "public"."petani"("id");



ALTER TABLE ONLY "public"."transaksi_beli_tbs"
    ADD CONSTRAINT "transaksi_beli_tbs_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."transaksi_beli_tbs"
    ADD CONSTRAINT "transaksi_beli_tbs_harga_tbs_lokal_id_fkey" FOREIGN KEY ("harga_tbs_lokal_id") REFERENCES "public"."harga_tbs_lokal"("id");



ALTER TABLE ONLY "public"."transaksi_beli_tbs"
    ADD CONSTRAINT "transaksi_beli_tbs_kas_ledger_id_fkey" FOREIGN KEY ("kas_ledger_id") REFERENCES "public"."kas_ledger"("id");



ALTER TABLE ONLY "public"."transaksi_beli_tbs"
    ADD CONSTRAINT "transaksi_beli_tbs_petani_id_fkey" FOREIGN KEY ("petani_id") REFERENCES "public"."petani"("id");



ALTER TABLE ONLY "public"."transaksi_beli_tbs"
    ADD CONSTRAINT "transaksi_beli_tbs_rekening_kas_id_fkey" FOREIGN KEY ("rekening_kas_id") REFERENCES "public"."rekening_kas"("id");



ALTER TABLE ONLY "public"."transaksi_beli_tbs"
    ADD CONSTRAINT "transaksi_beli_tbs_reversal_of_id_fkey" FOREIGN KEY ("reversal_of_id") REFERENCES "public"."transaksi_beli_tbs"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_biaya_sopir_operasional_id_fkey" FOREIGN KEY ("biaya_sopir_operasional_id") REFERENCES "public"."biaya_operasional"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_dibatalkan_by_fkey" FOREIGN KEY ("dibatalkan_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_fee_owner_history_id_fkey" FOREIGN KEY ("fee_owner_history_id") REFERENCES "public"."fee_owner_mitra_history"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_mitra_id_fkey" FOREIGN KEY ("mitra_id") REFERENCES "public"."master_mitra"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_pembayaran_pabrik_batch_id_fkey" FOREIGN KEY ("pembayaran_pabrik_batch_id") REFERENCES "public"."pembayaran_pabrik_batch"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_pembayaran_pabrik_item_id_fkey" FOREIGN KEY ("pembayaran_pabrik_item_id") REFERENCES "public"."pembayaran_pabrik_item"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_sopir_aktual_id_fkey" FOREIGN KEY ("sopir_aktual_id") REFERENCES "public"."sopir"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_sopir_default_id_fkey" FOREIGN KEY ("sopir_default_id") REFERENCES "public"."sopir"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_sopir_id_fkey" FOREIGN KEY ("sopir_id") REFERENCES "public"."sopir"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_tagihan_sopir_bayar_ledger_id_fkey" FOREIGN KEY ("tagihan_sopir_bayar_ledger_id") REFERENCES "public"."hutang_ledger"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_tagihan_sopir_ledger_id_fkey" FOREIGN KEY ("tagihan_sopir_ledger_id") REFERENCES "public"."hutang_ledger"("id");



ALTER TABLE ONLY "public"."transaksi_mitra"
    ADD CONSTRAINT "transaksi_mitra_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "public"."armada_mitra" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."armada_perusahaan" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."audit_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."biaya_operasional" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bukti_pembayaran" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fee_mitra_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fee_owner_mitra_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."harga_tbs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."harga_tbs_lokal" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."hutang" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."hutang_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."hutang_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "insert_business_settings" ON "public"."harga_tbs" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text"]));



CREATE POLICY "insert_finance" ON "public"."panjar_mitra" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "insert_finance" ON "public"."pembayaran_mitra_kwitansi_mitra" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "insert_finance" ON "public"."pembayaran_pabrik_item" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "insert_finance" ON "public"."rekening_kas" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "insert_operations" ON "public"."kendaraan" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "insert_operations" ON "public"."transaksi_mitra" FOR INSERT TO "authenticated" WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "insert_via_controlled_function" ON "public"."audit_log" FOR INSERT TO "authenticated" WITH CHECK ((("actor_user_id" = "auth"."uid"()) AND ("actor_role" = "public"."current_app_role"())));



ALTER TABLE "public"."kas_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."kendaraan" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "manage_users_super_admin" ON "public"."users" TO "authenticated" USING ("public"."has_app_role"(ARRAY['super_admin'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['super_admin'::"text"]));



ALTER TABLE "public"."master_mitra" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."mitra" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pabrik" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."panjar_mitra" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pembayaran_mitra" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pembayaran_mitra_kwitansi" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pembayaran_mitra_kwitansi_item" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pembayaran_mitra_kwitansi_mitra" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pembayaran_pabrik" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pembayaran_pabrik_batch" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pembayaran_pabrik_detail" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pembayaran_pabrik_item" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pengaturan_bisnis" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pengiriman" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pengiriman_lokal_detail" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."petani" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."piutang_dokumen" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."piutang_pelunasan" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "read_authenticated" ON "public"."armada_mitra" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."armada_perusahaan" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."audit_log" FOR SELECT TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text"]));



CREATE POLICY "read_authenticated" ON "public"."biaya_operasional" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."bukti_pembayaran" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."fee_mitra_history" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."fee_owner_mitra_history" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."harga_tbs" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."harga_tbs_lokal" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."hutang" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."hutang_ledger" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."hutang_log" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."kendaraan" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."master_mitra" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."mitra" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pabrik" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."panjar_mitra" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pembayaran_mitra" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pembayaran_mitra_kwitansi" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pembayaran_mitra_kwitansi_item" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pembayaran_mitra_kwitansi_mitra" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pembayaran_pabrik" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pembayaran_pabrik_batch" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pembayaran_pabrik_detail" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pembayaran_pabrik_item" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pengaturan_bisnis" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pengiriman" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."pengiriman_lokal_detail" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."petani" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."piutang_dokumen" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."piutang_pelunasan" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."settlement_mitra" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."sopir" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."stok_tbs_lokal_ledger" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."tarif_armada" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."transaksi_beli" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."transaksi_beli_tbs" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_authenticated" ON "public"."transaksi_mitra" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_finance" ON "public"."kas_ledger" FOR SELECT TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "read_finance" ON "public"."rekening_kas" FOR SELECT TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text", 'admin_operasional'::"text"]));



ALTER TABLE "public"."rekening_kas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "select_own_or_privileged" ON "public"."users" FOR SELECT TO "authenticated" USING ((("id" = "auth"."uid"()) OR "public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text"])));



ALTER TABLE "public"."settlement_mitra" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sopir" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."stok_tbs_lokal_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tarif_armada" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."transaksi_beli" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."transaksi_beli_tbs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."transaksi_mitra" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "update_business_settings" ON "public"."harga_tbs" FOR UPDATE TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text"]));



CREATE POLICY "update_finance" ON "public"."panjar_mitra" FOR UPDATE TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "update_finance" ON "public"."pembayaran_mitra_kwitansi_mitra" FOR UPDATE TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "update_finance" ON "public"."pembayaran_pabrik_item" FOR UPDATE TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "update_finance" ON "public"."rekening_kas" FOR UPDATE TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "update_operations" ON "public"."kendaraan" FOR UPDATE TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "write_finance" ON "public"."bukti_pembayaran" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "write_finance" ON "public"."hutang" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "write_finance" ON "public"."hutang_log" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "write_finance" ON "public"."pembayaran_mitra" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "write_finance" ON "public"."pembayaran_pabrik" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "write_finance" ON "public"."pembayaran_pabrik_detail" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "write_finance" ON "public"."settlement_mitra" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_keuangan'::"text"]));



CREATE POLICY "write_operations" ON "public"."armada_mitra" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "write_operations" ON "public"."armada_perusahaan" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "write_operations" ON "public"."fee_mitra_history" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "write_operations" ON "public"."mitra" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "write_operations" ON "public"."pengiriman" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "write_operations" ON "public"."pengiriman_lokal_detail" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "write_operations" ON "public"."petani" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "write_operations" ON "public"."stok_tbs_lokal_ledger" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "write_operations" ON "public"."tarif_armada" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "write_operations" ON "public"."transaksi_beli" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "write_operations" ON "public"."transaksi_beli_tbs" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text", 'admin_operasional'::"text"]));



CREATE POLICY "write_owner" ON "public"."fee_owner_mitra_history" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text"]));



CREATE POLICY "write_owner_super_admin" ON "public"."pengaturan_bisnis" TO "authenticated" USING ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text"])) WITH CHECK ("public"."has_app_role"(ARRAY['owner'::"text", 'super_admin'::"text"]));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."archive_reconciled_legacy_panjar"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."archive_reconciled_legacy_panjar"() TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."transaksi_mitra" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."transaksi_mitra" TO "authenticated";
GRANT ALL ON TABLE "public"."transaksi_mitra" TO "service_role";



REVOKE ALL ON FUNCTION "public"."bayar_tagihan_sopir_cb"("p_transaksi_mitra_id" "uuid", "p_tanggal_bayar" "date", "p_rekening_kas_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."bayar_tagihan_sopir_cb"("p_transaksi_mitra_id" "uuid", "p_tanggal_bayar" "date", "p_rekening_kas_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bayar_tagihan_sopir_cb"("p_transaksi_mitra_id" "uuid", "p_tanggal_bayar" "date", "p_rekening_kas_id" "uuid") TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."biaya_operasional" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."biaya_operasional" TO "authenticated";
GRANT ALL ON TABLE "public"."biaya_operasional" TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_biaya_operasional_kas"("p_biaya_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_biaya_operasional_kas"("p_biaya_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_biaya_operasional_kas"("p_biaya_id" "uuid", "p_alasan" "text") TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."hutang_ledger" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."hutang_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."hutang_ledger" TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_hutang_ledger"("p_hutang_ledger_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_hutang_ledger"("p_hutang_ledger_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_hutang_ledger"("p_hutang_ledger_id" "uuid", "p_alasan" "text") TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."kas_ledger" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."kas_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."kas_ledger" TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_kas_mutasi_manual"("p_kas_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_kas_mutasi_manual"("p_kas_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_kas_mutasi_manual"("p_kas_id" "uuid", "p_alasan" "text") TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."panjar_mitra" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."panjar_mitra" TO "authenticated";
GRANT ALL ON TABLE "public"."panjar_mitra" TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_panjar_mitra_kas"("p_panjar_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_panjar_mitra_kas"("p_panjar_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_panjar_mitra_kas"("p_panjar_id" "uuid", "p_alasan" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_pembayaran_dana_trip"("p_transaksi_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_pembayaran_dana_trip"("p_transaksi_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_pembayaran_dana_trip"("p_transaksi_id" "uuid", "p_alasan" "text") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."pembayaran_mitra_kwitansi" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."pembayaran_mitra_kwitansi" TO "authenticated";
GRANT ALL ON TABLE "public"."pembayaran_mitra_kwitansi" TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_pembayaran_mitra_kwitansi"("p_pembayaran_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_pembayaran_mitra_kwitansi"("p_pembayaran_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_pembayaran_mitra_kwitansi"("p_pembayaran_id" "uuid", "p_alasan" "text") TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pembayaran_pabrik_batch" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pembayaran_pabrik_batch" TO "authenticated";
GRANT ALL ON TABLE "public"."pembayaran_pabrik_batch" TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_pembayaran_pabrik_batch"("p_pembayaran_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_pembayaran_pabrik_batch"("p_pembayaran_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_pembayaran_pabrik_batch"("p_pembayaran_id" "uuid", "p_alasan" "text") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."piutang_dokumen" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."piutang_dokumen" TO "authenticated";
GRANT ALL ON TABLE "public"."piutang_dokumen" TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_piutang_document"("p_document_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_piutang_document"("p_document_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_piutang_document"("p_document_id" "uuid", "p_alasan" "text") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."piutang_pelunasan" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."piutang_pelunasan" TO "authenticated";
GRANT ALL ON TABLE "public"."piutang_pelunasan" TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_piutang_repayment"("p_payment_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_piutang_repayment"("p_payment_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_piutang_repayment"("p_payment_id" "uuid", "p_alasan" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."next_no_struk_tbs"("p_tanggal" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."next_no_struk_tbs"("p_tanggal" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."next_no_struk_tbs"("p_tanggal" "date") TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."transaksi_beli_tbs" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."transaksi_beli_tbs" TO "authenticated";
GRANT ALL ON TABLE "public"."transaksi_beli_tbs" TO "service_role";



GRANT ALL ON FUNCTION "public"."cancel_transaksi_beli_tbs"("p_transaksi_id" "uuid", "p_alasan" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."cancel_transaksi_beli_tbs"("p_transaksi_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_transaksi_beli_tbs"("p_transaksi_id" "uuid", "p_alasan" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_transaksi_mitra_controlled"("p_transaksi_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_transaksi_mitra_controlled"("p_transaksi_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_transaksi_mitra_controlled"("p_transaksi_id" "uuid", "p_alasan" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_biaya_operasional_armada_kas"("p_tanggal" "date", "p_kategori" "text", "p_jumlah" numeric, "p_armada_sopir_id" "uuid", "p_keterangan" "text", "p_rekening_kas_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_biaya_operasional_armada_kas"("p_tanggal" "date", "p_kategori" "text", "p_jumlah" numeric, "p_armada_sopir_id" "uuid", "p_keterangan" "text", "p_rekening_kas_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_biaya_operasional_armada_kas"("p_tanggal" "date", "p_kategori" "text", "p_jumlah" numeric, "p_armada_sopir_id" "uuid", "p_keterangan" "text", "p_rekening_kas_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_biaya_operasional_kas"("p_tanggal" "date", "p_kategori" "text", "p_jumlah" numeric, "p_keterangan" "text", "p_rekening_kas_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_biaya_operasional_kas"("p_tanggal" "date", "p_kategori" "text", "p_jumlah" numeric, "p_keterangan" "text", "p_rekening_kas_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_biaya_operasional_kas"("p_tanggal" "date", "p_kategori" "text", "p_jumlah" numeric, "p_keterangan" "text", "p_rekening_kas_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_hutang_pihak"("p_pihak_type" "text", "p_tipe" "text", "p_sumber" "text", "p_jumlah" numeric, "p_tanggal" "date", "p_petani_id" "uuid", "p_master_mitra_id" "uuid", "p_sopir_id" "uuid", "p_pihak_nama_manual" "text", "p_keterangan" "text", "p_rekening_kas_id" "uuid", "p_catat_kas" boolean, "p_legacy_source_table" "text", "p_legacy_source_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_hutang_pihak"("p_pihak_type" "text", "p_tipe" "text", "p_sumber" "text", "p_jumlah" numeric, "p_tanggal" "date", "p_petani_id" "uuid", "p_master_mitra_id" "uuid", "p_sopir_id" "uuid", "p_pihak_nama_manual" "text", "p_keterangan" "text", "p_rekening_kas_id" "uuid", "p_catat_kas" boolean, "p_legacy_source_table" "text", "p_legacy_source_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_hutang_pihak"("p_pihak_type" "text", "p_tipe" "text", "p_sumber" "text", "p_jumlah" numeric, "p_tanggal" "date", "p_petani_id" "uuid", "p_master_mitra_id" "uuid", "p_sopir_id" "uuid", "p_pihak_nama_manual" "text", "p_keterangan" "text", "p_rekening_kas_id" "uuid", "p_catat_kas" boolean, "p_legacy_source_table" "text", "p_legacy_source_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_kas_mutasi"("p_tanggal" "date", "p_tipe" "text", "p_sumber" "text", "p_jumlah" numeric, "p_rekening_kas_id" "uuid", "p_keterangan" "text", "p_source_table" "text", "p_source_id" "uuid", "p_idempotency_key" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_kas_mutasi"("p_tanggal" "date", "p_tipe" "text", "p_sumber" "text", "p_jumlah" numeric, "p_rekening_kas_id" "uuid", "p_keterangan" "text", "p_source_table" "text", "p_source_id" "uuid", "p_idempotency_key" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_kas_mutasi"("p_tanggal" "date", "p_tipe" "text", "p_sumber" "text", "p_jumlah" numeric, "p_rekening_kas_id" "uuid", "p_keterangan" "text", "p_source_table" "text", "p_source_id" "uuid", "p_idempotency_key" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_panjar_mitra_kas"("p_mitra_id" "uuid", "p_tanggal" "date", "p_jumlah" numeric, "p_keterangan" "text", "p_rekening_kas_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_panjar_mitra_kas"("p_mitra_id" "uuid", "p_tanggal" "date", "p_jumlah" numeric, "p_keterangan" "text", "p_rekening_kas_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_panjar_mitra_kas"("p_mitra_id" "uuid", "p_tanggal" "date", "p_jumlah" numeric, "p_keterangan" "text", "p_rekening_kas_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_pembayaran_mitra_kwitansi"("p_master_mitra_id" "uuid", "p_periode_dari" "date", "p_periode_sampai" "date", "p_metode_bayar" "text", "p_catatan" "text", "p_master_mitra_ids" "uuid"[], "p_penerima_label" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_pembayaran_mitra_kwitansi"("p_master_mitra_id" "uuid", "p_periode_dari" "date", "p_periode_sampai" "date", "p_metode_bayar" "text", "p_catatan" "text", "p_master_mitra_ids" "uuid"[], "p_penerima_label" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_pembayaran_mitra_kwitansi"("p_master_mitra_id" "uuid", "p_periode_dari" "date", "p_periode_sampai" "date", "p_metode_bayar" "text", "p_catatan" "text", "p_master_mitra_ids" "uuid"[], "p_penerima_label" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_pembayaran_pabrik_batch"("p_pabrik_id" "uuid", "p_tanggal_bayar" "date", "p_metode_bayar" "text", "p_tonase_pabrik" numeric, "p_harga_pabrik_per_kg" numeric, "p_nominal_diterima" numeric, "p_rekening_kas_id" "uuid", "p_nomor_bukti" "text", "p_catatan" "text", "p_transaksi_ids" "uuid"[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_pembayaran_pabrik_batch"("p_pabrik_id" "uuid", "p_tanggal_bayar" "date", "p_metode_bayar" "text", "p_tonase_pabrik" numeric, "p_harga_pabrik_per_kg" numeric, "p_nominal_diterima" numeric, "p_rekening_kas_id" "uuid", "p_nomor_bukti" "text", "p_catatan" "text", "p_transaksi_ids" "uuid"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_pembayaran_pabrik_batch"("p_pabrik_id" "uuid", "p_tanggal_bayar" "date", "p_metode_bayar" "text", "p_tonase_pabrik" numeric, "p_harga_pabrik_per_kg" numeric, "p_nominal_diterima" numeric, "p_rekening_kas_id" "uuid", "p_nomor_bukti" "text", "p_catatan" "text", "p_transaksi_ids" "uuid"[]) TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pengiriman" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pengiriman" TO "authenticated";
GRANT ALL ON TABLE "public"."pengiriman" TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_pengiriman_lokal"("p_tanggal" "date", "p_pabrik_id" "uuid", "p_tonase_kirim_kg" numeric, "p_nomor_do" "text", "p_sopir_id" "uuid", "p_kendaraan_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_pengiriman_lokal"("p_tanggal" "date", "p_pabrik_id" "uuid", "p_tonase_kirim_kg" numeric, "p_nomor_do" "text", "p_sopir_id" "uuid", "p_kendaraan_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_pengiriman_lokal"("p_tanggal" "date", "p_pabrik_id" "uuid", "p_tonase_kirim_kg" numeric, "p_nomor_do" "text", "p_sopir_id" "uuid", "p_kendaraan_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_pengiriman_lokal"("p_tanggal" "date", "p_pabrik_id" "uuid", "p_tonase_kirim_kg" numeric, "p_nomor_do" "text", "p_sopir_id" "uuid", "p_kendaraan_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_piutang_request"("p_pihak_type" "text", "p_jumlah" numeric, "p_tujuan" "text", "p_metode_pelunasan" "text", "p_tanggal" "date", "p_tanggal_jatuh_tempo" "date", "p_petani_id" "uuid", "p_master_mitra_id" "uuid", "p_sopir_id" "uuid", "p_pihak_nama_manual" "text", "p_catatan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_piutang_request"("p_pihak_type" "text", "p_jumlah" numeric, "p_tujuan" "text", "p_metode_pelunasan" "text", "p_tanggal" "date", "p_tanggal_jatuh_tempo" "date", "p_petani_id" "uuid", "p_master_mitra_id" "uuid", "p_sopir_id" "uuid", "p_pihak_nama_manual" "text", "p_catatan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_piutang_request"("p_pihak_type" "text", "p_jumlah" numeric, "p_tujuan" "text", "p_metode_pelunasan" "text", "p_tanggal" "date", "p_tanggal_jatuh_tempo" "date", "p_petani_id" "uuid", "p_master_mitra_id" "uuid", "p_sopir_id" "uuid", "p_pihak_nama_manual" "text", "p_catatan" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_transaksi_beli_tbs"("p_petani_id" "uuid", "p_berat_kotor_kg" numeric, "p_potongan_percent" numeric, "p_potongan_hutang" numeric, "p_keterangan" "text", "p_tanggal" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_transaksi_beli_tbs"("p_petani_id" "uuid", "p_berat_kotor_kg" numeric, "p_potongan_percent" numeric, "p_potongan_hutang" numeric, "p_keterangan" "text", "p_tanggal" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_transaksi_beli_tbs"("p_petani_id" "uuid", "p_berat_kotor_kg" numeric, "p_potongan_percent" numeric, "p_potongan_hutang" numeric, "p_keterangan" "text", "p_tanggal" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."current_app_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_app_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_app_role"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."disburse_piutang_document"("p_document_id" "uuid", "p_metode_penyerahan" "text", "p_nama_penerima" "text", "p_rekening_kas_id" "uuid", "p_nomor_identitas" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."disburse_piutang_document"("p_document_id" "uuid", "p_metode_penyerahan" "text", "p_nama_penerima" "text", "p_rekening_kas_id" "uuid", "p_nomor_identitas" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."disburse_piutang_document"("p_document_id" "uuid", "p_metode_penyerahan" "text", "p_nama_penerima" "text", "p_rekening_kas_id" "uuid", "p_nomor_identitas" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."enrich_kwitansi_panjar_snapshot_owner"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."enrich_kwitansi_panjar_snapshot_owner"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."flag_kwitansi_after_system_change"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."flag_kwitansi_after_system_change"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_dashboard_pending_summary"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_dashboard_pending_summary"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dashboard_pending_summary"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_default_rekening_kas_id"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_default_rekening_kas_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_default_rekening_kas_id"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_kas_summary"("p_rekening_kas_id" "uuid", "p_date_from" "date", "p_date_to" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_kas_summary"("p_rekening_kas_id" "uuid", "p_date_from" "date", "p_date_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_kas_summary"("p_rekening_kas_id" "uuid", "p_date_from" "date", "p_date_to" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_master_mitra_sensitive_changes"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_master_mitra_sensitive_changes"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_paid_transaksi_mitra_changes"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_paid_transaksi_mitra_changes"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."guard_sopir_armada_verification"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."guard_sopir_armada_verification"() TO "service_role";



GRANT ALL ON FUNCTION "public"."has_app_role"("required_roles" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."has_app_role"("required_roles" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_app_role"("required_roles" "text"[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."next_piutang_document_number"("p_prefix" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."next_piutang_document_number"("p_prefix" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_plat_nomor"("p_plat" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_plat_nomor"("p_plat" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_plat_nomor"("p_plat" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."normalize_transaksi_mitra_armada_cb"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."normalize_transaksi_mitra_armada_cb"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."prevent_kwitansi_item_snapshot_update"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prevent_kwitansi_item_snapshot_update"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."recalculate_kwitansi_totals"("p_pembayaran_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."recalculate_kwitansi_totals"("p_pembayaran_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."reconcile_legacy_panjar_opening"("p_panjar_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reconcile_legacy_panjar_opening"("p_panjar_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reconcile_legacy_panjar_opening"("p_panjar_id" "uuid", "p_alasan" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_pengiriman_lokal_status"("p_pengiriman_id" "uuid", "p_status" "text", "p_tonase_pabrik" numeric, "p_harga_pabrik_per_kg" numeric, "p_potongan_sortasi_type" "text", "p_potongan_sortasi_value" numeric, "p_biaya_timbang" numeric, "p_potongan_pabrik_lain" numeric, "p_tanggal_bayar" "date", "p_rekening_kas_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_pengiriman_lokal_status"("p_pengiriman_id" "uuid", "p_status" "text", "p_tonase_pabrik" numeric, "p_harga_pabrik_per_kg" numeric, "p_potongan_sortasi_type" "text", "p_potongan_sortasi_value" numeric, "p_biaya_timbang" numeric, "p_potongan_pabrik_lain" numeric, "p_tanggal_bayar" "date", "p_rekening_kas_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_pengiriman_lokal_status"("p_pengiriman_id" "uuid", "p_status" "text", "p_tonase_pabrik" numeric, "p_harga_pabrik_per_kg" numeric, "p_potongan_sortasi_type" "text", "p_potongan_sortasi_value" numeric, "p_biaya_timbang" numeric, "p_potongan_pabrik_lain" numeric, "p_tanggal_bayar" "date", "p_rekening_kas_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."record_piutang_repayment"("p_document_id" "uuid", "p_jumlah" numeric, "p_metode" "text", "p_tanggal" "date", "p_keterangan" "text", "p_rekening_kas_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_piutang_repayment"("p_document_id" "uuid", "p_jumlah" numeric, "p_metode" "text", "p_tanggal" "date", "p_keterangan" "text", "p_rekening_kas_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_piutang_repayment"("p_document_id" "uuid", "p_jumlah" numeric, "p_metode" "text", "p_tanggal" "date", "p_keterangan" "text", "p_rekening_kas_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."require_factory_payment_proof"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."require_factory_payment_proof"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."resolve_dana_operasional_trip_mitra"("p_mitra_id" "uuid", "p_tanggal" "date") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_dana_operasional_trip_mitra"("p_mitra_id" "uuid", "p_tanggal" "date") TO "service_role";



REVOKE ALL ON FUNCTION "public"."review_piutang_request"("p_document_id" "uuid", "p_action" "text", "p_catatan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."review_piutang_request"("p_document_id" "uuid", "p_action" "text", "p_catatan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."review_piutang_request"("p_document_id" "uuid", "p_action" "text", "p_catatan" "text") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."master_mitra" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."master_mitra" TO "authenticated";
GRANT ALL ON TABLE "public"."master_mitra" TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_master_mitra"("p_id" "uuid", "p_kode" "text", "p_nama" "text", "p_penanggung_jawab" "text", "p_no_hp" "text", "p_alamat" "text", "p_tipe_mitra" "text", "p_fee_per_kg" numeric, "p_tarif_sewa_angkut_per_kg" numeric, "p_dana_operasional_trip" numeric, "p_berlaku_mulai" "date", "p_alasan_perubahan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_master_mitra"("p_id" "uuid", "p_kode" "text", "p_nama" "text", "p_penanggung_jawab" "text", "p_no_hp" "text", "p_alamat" "text", "p_tipe_mitra" "text", "p_fee_per_kg" numeric, "p_tarif_sewa_angkut_per_kg" numeric, "p_dana_operasional_trip" numeric, "p_berlaku_mulai" "date", "p_alasan_perubahan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_master_mitra"("p_id" "uuid", "p_kode" "text", "p_nama" "text", "p_penanggung_jawab" "text", "p_no_hp" "text", "p_alamat" "text", "p_tipe_mitra" "text", "p_fee_per_kg" numeric, "p_tarif_sewa_angkut_per_kg" numeric, "p_dana_operasional_trip" numeric, "p_berlaku_mulai" "date", "p_alasan_perubahan" "text") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."pabrik" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."pabrik" TO "authenticated";
GRANT ALL ON TABLE "public"."pabrik" TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_pabrik_master"("p_id" "uuid", "p_nama" "text", "p_alamat" "text", "p_no_hp" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_pabrik_master"("p_id" "uuid", "p_nama" "text", "p_alamat" "text", "p_no_hp" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_pabrik_master"("p_id" "uuid", "p_nama" "text", "p_alamat" "text", "p_no_hp" "text") TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."sopir" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."sopir" TO "authenticated";
GRANT ALL ON TABLE "public"."sopir" TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_sopir_armada"("p_id" "uuid", "p_nama" "text", "p_no_hp" "text", "p_mitra_id" "uuid", "p_plat_nomor" "text", "p_is_armada_cb" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_sopir_armada"("p_id" "uuid", "p_nama" "text", "p_no_hp" "text", "p_mitra_id" "uuid", "p_plat_nomor" "text", "p_is_armada_cb" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_sopir_armada"("p_id" "uuid", "p_nama" "text", "p_no_hp" "text", "p_mitra_id" "uuid", "p_plat_nomor" "text", "p_is_armada_cb" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") TO "service_role";
GRANT ALL ON FUNCTION "public"."save_transaksi_mitra_v2"("payload" "jsonb") TO "authenticated";



GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."harga_tbs_lokal" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."harga_tbs_lokal" TO "authenticated";
GRANT ALL ON TABLE "public"."harga_tbs_lokal" TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_harga_tbs_lokal"("p_harga_per_kg" numeric, "p_alasan_override" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_harga_tbs_lokal"("p_harga_per_kg" numeric, "p_alasan_override" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_harga_tbs_lokal"("p_harga_per_kg" numeric, "p_alasan_override" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_master_mitra_active"("p_id" "uuid", "p_active" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_master_mitra_active"("p_id" "uuid", "p_active" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_master_mitra_active"("p_id" "uuid", "p_active" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_pabrik_master_active"("p_id" "uuid", "p_active" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_pabrik_master_active"("p_id" "uuid", "p_active" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_pabrik_master_active"("p_id" "uuid", "p_active" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."set_sopir_armada_active"("p_id" "uuid", "p_active" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."set_sopir_armada_active"("p_id" "uuid", "p_active" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_sopir_armada_active"("p_id" "uuid", "p_active" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."settle_panjar_mitra_manual"("p_panjar_id" "uuid", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."settle_panjar_mitra_manual"("p_panjar_id" "uuid", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."settle_panjar_mitra_manual"("p_panjar_id" "uuid", "p_alasan" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."snapshot_sewa_item_kwitansi"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."snapshot_sewa_item_kwitansi"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."sync_fee_owner_mitra_period"("p_date_from" "date", "p_date_to" "date", "p_master_mitra_id" "uuid", "p_tipe_mitra" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sync_fee_owner_mitra_period"("p_date_from" "date", "p_date_to" "date", "p_master_mitra_id" "uuid", "p_tipe_mitra" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_fee_owner_mitra_period"("p_date_from" "date", "p_date_to" "date", "p_master_mitra_id" "uuid", "p_tipe_mitra" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."sync_kwitansi_totals_from_item"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sync_kwitansi_totals_from_item"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."sync_kwitansi_totals_from_summary"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sync_kwitansi_totals_from_summary"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."sync_piutang_document_from_panjar"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sync_piutang_document_from_panjar"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."sync_tagihan_sopir_cb"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sync_tagihan_sopir_cb"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."sync_tarif_sopir_cb_period"("p_date_from" "date", "p_date_to" "date", "p_armada_sopir_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sync_tarif_sopir_cb_period"("p_date_from" "date", "p_date_to" "date", "p_armada_sopir_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_tarif_sopir_cb_period"("p_date_from" "date", "p_date_to" "date", "p_armada_sopir_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_transaksi_mitra_controlled"("p_transaksi_id" "uuid", "p_changes" "jsonb", "p_alasan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_transaksi_mitra_controlled"("p_transaksi_id" "uuid", "p_changes" "jsonb", "p_alasan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_transaksi_mitra_controlled"("p_transaksi_id" "uuid", "p_changes" "jsonb", "p_alasan" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."validate_kwitansi_deductions_per_mitra"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."validate_kwitansi_deductions_per_mitra"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."verify_master_mitra"("p_id" "uuid", "p_catatan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."verify_master_mitra"("p_id" "uuid", "p_catatan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."verify_master_mitra"("p_id" "uuid", "p_catatan" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."verify_pabrik_master"("p_id" "uuid", "p_catatan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."verify_pabrik_master"("p_id" "uuid", "p_catatan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."verify_pabrik_master"("p_id" "uuid", "p_catatan" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."verify_sopir_armada"("p_id" "uuid", "p_catatan" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."verify_sopir_armada"("p_id" "uuid", "p_catatan" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."verify_sopir_armada"("p_id" "uuid", "p_catatan" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."write_audit_log"("p_entity_type" "text", "p_entity_id" "uuid", "p_action" "text", "p_before_json" "jsonb", "p_after_json" "jsonb", "p_alasan" "text", "p_approved_by" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."write_audit_log"("p_entity_type" "text", "p_entity_id" "uuid", "p_action" "text", "p_before_json" "jsonb", "p_after_json" "jsonb", "p_alasan" "text", "p_approved_by" "uuid") TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."armada_mitra" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."armada_mitra" TO "authenticated";
GRANT ALL ON TABLE "public"."armada_mitra" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."armada_perusahaan" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."armada_perusahaan" TO "authenticated";
GRANT ALL ON TABLE "public"."armada_perusahaan" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."audit_log" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_log" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."bukti_pembayaran" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."bukti_pembayaran" TO "authenticated";
GRANT ALL ON TABLE "public"."bukti_pembayaran" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."fee_mitra_history" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."fee_mitra_history" TO "authenticated";
GRANT ALL ON TABLE "public"."fee_mitra_history" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."fee_owner_mitra_history" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."fee_owner_mitra_history" TO "authenticated";
GRANT ALL ON TABLE "public"."fee_owner_mitra_history" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."harga_tbs" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."harga_tbs" TO "authenticated";
GRANT ALL ON TABLE "public"."harga_tbs" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."hutang" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."hutang" TO "authenticated";
GRANT ALL ON TABLE "public"."hutang" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."hutang_log" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."hutang_log" TO "authenticated";
GRANT ALL ON TABLE "public"."hutang_log" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."kendaraan" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."kendaraan" TO "authenticated";
GRANT ALL ON TABLE "public"."kendaraan" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."mitra" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."mitra" TO "authenticated";
GRANT ALL ON TABLE "public"."mitra" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pembayaran_mitra" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pembayaran_mitra" TO "authenticated";
GRANT ALL ON TABLE "public"."pembayaran_mitra" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."pembayaran_mitra_kwitansi_item" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."pembayaran_mitra_kwitansi_item" TO "authenticated";
GRANT ALL ON TABLE "public"."pembayaran_mitra_kwitansi_item" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."pembayaran_mitra_kwitansi_mitra" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,MAINTAIN ON TABLE "public"."pembayaran_mitra_kwitansi_mitra" TO "authenticated";
GRANT ALL ON TABLE "public"."pembayaran_mitra_kwitansi_mitra" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pembayaran_pabrik" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pembayaran_pabrik" TO "authenticated";
GRANT ALL ON TABLE "public"."pembayaran_pabrik" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pembayaran_pabrik_detail" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pembayaran_pabrik_detail" TO "authenticated";
GRANT ALL ON TABLE "public"."pembayaran_pabrik_detail" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pembayaran_pabrik_item" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pembayaran_pabrik_item" TO "authenticated";
GRANT ALL ON TABLE "public"."pembayaran_pabrik_item" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pengaturan_bisnis" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pengaturan_bisnis" TO "authenticated";
GRANT ALL ON TABLE "public"."pengaturan_bisnis" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pengiriman_lokal_detail" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."pengiriman_lokal_detail" TO "authenticated";
GRANT ALL ON TABLE "public"."pengiriman_lokal_detail" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."petani" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."petani" TO "authenticated";
GRANT ALL ON TABLE "public"."petani" TO "service_role";



GRANT ALL ON SEQUENCE "public"."piutang_document_number_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."piutang_document_number_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."piutang_document_number_seq" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."rekening_kas" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."rekening_kas" TO "authenticated";
GRANT ALL ON TABLE "public"."rekening_kas" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."settlement_mitra" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."settlement_mitra" TO "authenticated";
GRANT ALL ON TABLE "public"."settlement_mitra" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."stok_tbs_lokal_ledger" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."stok_tbs_lokal_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."stok_tbs_lokal_ledger" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."tarif_armada" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."tarif_armada" TO "authenticated";
GRANT ALL ON TABLE "public"."tarif_armada" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."transaksi_beli" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."transaksi_beli" TO "authenticated";
GRANT ALL ON TABLE "public"."transaksi_beli" TO "service_role";



GRANT ALL ON SEQUENCE "public"."transaksi_beli_tbs_no_struk_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."transaksi_beli_tbs_no_struk_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."transaksi_beli_tbs_no_struk_seq" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."users" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,MAINTAIN,UPDATE ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







