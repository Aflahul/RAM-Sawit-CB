-- 20260718010013_p0_feature_gate_coming_soon.sql

-- 1. Blokir Fungsi RPC Pembelian Lokal (Coming Soon)
CREATE OR REPLACE FUNCTION public.block_frozen_module() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  RAISE EXCEPTION 'Modul ini dibekukan sementara (Coming Soon).' USING ERRCODE = 'P0000';
END;
$$;

-- 2. Tambahkan Gate pada RPC transaksi beli
CREATE OR REPLACE FUNCTION public.create_transaksi_beli_tbs(p_petani_id uuid, p_berat_kotor_kg numeric, p_potongan_percent numeric DEFAULT 0, p_potongan_hutang numeric DEFAULT 0, p_keterangan text DEFAULT NULL::text, p_tanggal date DEFAULT NULL::date)
RETURNS TABLE(id uuid, tanggal date, petani_id uuid, petani_nama text, berat_kotor_kg numeric, potongan_type text, potongan_value numeric, berat_bersih_kg numeric, harga_per_kg numeric, total_harga numeric, potongan_hutang numeric, total_bayar_tunai numeric, no_struk text, status text, keterangan text, created_at timestamp with time zone)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  RAISE EXCEPTION 'Modul Pembelian Petani Lokal dibekukan sementara (Coming Soon).' USING ERRCODE = 'P0000';
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_transaksi_beli_tbs(p_transaksi_id uuid, p_alasan text)
RETURNS public.transaksi_beli_tbs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  RAISE EXCEPTION 'Modul Pembelian Petani Lokal dibekukan sementara (Coming Soon).' USING ERRCODE = 'P0000';
END;
$$;

REVOKE ALL ON FUNCTION public.block_frozen_module()
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.create_transaksi_beli_tbs(uuid, numeric, numeric, numeric, text, date)
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.cancel_transaksi_beli_tbs(uuid, text)
FROM PUBLIC, anon, authenticated;

-- 3. Tambahkan Trigger Penolakan Mutasi Data (Tabel Petani & Stok Lokal)
DROP TRIGGER IF EXISTS block_petani_mutation ON public.petani;
CREATE TRIGGER block_petani_mutation
BEFORE INSERT OR UPDATE OR DELETE ON public.petani
FOR EACH STATEMENT EXECUTE FUNCTION public.block_frozen_module();

DROP TRIGGER IF EXISTS block_stok_lokal_mutation ON public.stok_tbs_lokal_ledger;
CREATE TRIGGER block_stok_lokal_mutation
BEFORE INSERT OR UPDATE OR DELETE ON public.stok_tbs_lokal_ledger
FOR EACH STATEMENT EXECUTE FUNCTION public.block_frozen_module();
