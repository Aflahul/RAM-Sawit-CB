-- Migration 20260718010011_p0_server_authoritative_snapshots.sql
-- Implementasi TASK-SEC-006: Server-Authoritative Snapshots untuk Kwitansi dan Transaksi Beli TBS

BEGIN;

-- 1. Trigger untuk transaksi_beli_tbs (Pembelian TBS Lokal)
CREATE OR REPLACE FUNCTION public.enforce_tbs_snapshot_calculation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_harga_lokal numeric;
BEGIN
  -- Dapatkan harga pabrik/tbs lokal jika ID tersedia
  IF NEW.harga_tbs_lokal_id IS NOT NULL THEN
    SELECT harga_per_kg INTO v_harga_lokal
    FROM public.harga_tbs_lokal
    WHERE id = NEW.harga_tbs_lokal_id;
    
    -- Paksa harga per kg sesuai snapshot dari server
    NEW.harga_per_kg := COALESCE(v_harga_lokal, 0);
  END IF;
  
  -- Hitung ulang berat bersih berdasarkan tipe potongan
  IF NEW.potongan_type = 'kg' THEN
     NEW.berat_bersih_kg := GREATEST(0, NEW.berat_kotor_kg - COALESCE(NEW.potongan_value, 0));
  ELSIF NEW.potongan_type = 'percent' THEN
     NEW.berat_bersih_kg := GREATEST(0, NEW.berat_kotor_kg - (NEW.berat_kotor_kg * (COALESCE(NEW.potongan_value, 0) / 100)));
  ELSE
     NEW.berat_bersih_kg := NEW.berat_kotor_kg;
  END IF;
  
  -- Hitung ulang total kotor (pembulatan karena total rupiah)
  NEW.total_harga := ROUND(NEW.berat_bersih_kg * NEW.harga_per_kg);
  
  -- Jika potongan_type nominal, terapkan langsung di total harga
  IF NEW.potongan_type = 'nominal' THEN
     NEW.total_harga := GREATEST(0, NEW.total_harga - COALESCE(NEW.potongan_value, 0));
  END IF;

  -- Hitung ulang total bayar tunai dengan memotong hutang
  NEW.total_bayar_tunai := GREATEST(0, NEW.total_harga - COALESCE(NEW.potongan_hutang, 0));
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_tbs_snapshot_calculation ON public.transaksi_beli_tbs;
CREATE TRIGGER enforce_tbs_snapshot_calculation
BEFORE INSERT OR UPDATE ON public.transaksi_beli_tbs
FOR EACH ROW
EXECUTE FUNCTION public.enforce_tbs_snapshot_calculation();


-- 2. Trigger untuk pembayaran_mitra_kwitansi
CREATE OR REPLACE FUNCTION public.enforce_kwitansi_aggregates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_total_nilai_bersih numeric := 0;
  v_total_sewa_armada numeric := 0;
  v_total_panjar numeric := 0;
  v_total_tonase numeric := 0;
  v_total_berat_netto numeric := 0;
  v_total_berat_dibayar numeric := 0;
  
  item jsonb;
BEGIN
  -- Sum up values from transaksi_snapshot_json
  IF NEW.transaksi_snapshot_json IS NOT NULL AND jsonb_typeof(NEW.transaksi_snapshot_json) = 'array' THEN
    FOR item IN SELECT * FROM jsonb_array_elements(NEW.transaksi_snapshot_json)
    LOOP
      v_total_nilai_bersih := v_total_nilai_bersih + COALESCE((item->>'nilai_bersih')::numeric, 0);
      v_total_sewa_armada := v_total_sewa_armada + COALESCE((item->>'sewa_armada')::numeric, 0);
      v_total_tonase := v_total_tonase + COALESCE((item->>'tonase')::numeric, 0);
      v_total_berat_netto := v_total_berat_netto + COALESCE((item->>'berat_netto_pabrik_kg')::numeric, 0);
      v_total_berat_dibayar := v_total_berat_dibayar + COALESCE((item->>'berat_dibayar_kg')::numeric, 0);
    END LOOP;
  END IF;

  -- Sum up values from panjar_snapshot_json
  IF NEW.panjar_snapshot_json IS NOT NULL AND jsonb_typeof(NEW.panjar_snapshot_json) = 'array' THEN
    FOR item IN SELECT * FROM jsonb_array_elements(NEW.panjar_snapshot_json)
    LOOP
      v_total_panjar := v_total_panjar + COALESCE((item->>'jumlah')::numeric, 0);
    END LOOP;
  END IF;

  -- Force overwrite top-level aggregates to prevent tampering
  NEW.total_nilai_bersih := v_total_nilai_bersih;
  NEW.total_sewa_armada := v_total_sewa_armada;
  NEW.total_panjar := v_total_panjar;
  NEW.total_tonase := v_total_tonase;
  NEW.total_berat_netto := v_total_berat_netto;
  NEW.total_berat_dibayar := v_total_berat_dibayar;
  
  -- The most critical field: nominal_dibayar
  NEW.nominal_dibayar := GREATEST(0, (v_total_nilai_bersih - v_total_sewa_armada) - v_total_panjar);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_kwitansi_aggregates ON public.pembayaran_mitra_kwitansi;
CREATE TRIGGER enforce_kwitansi_aggregates
BEFORE INSERT OR UPDATE ON public.pembayaran_mitra_kwitansi
FOR EACH ROW
EXECUTE FUNCTION public.enforce_kwitansi_aggregates();

COMMIT;
