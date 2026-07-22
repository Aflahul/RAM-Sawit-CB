-- Keep kwitansi header aggregates aligned with the canonical snapshot keys
-- emitted by create_pembayaran_mitra_kwitansi. Legacy aliases remain readable.
CREATE OR REPLACE FUNCTION public.enforce_kwitansi_aggregates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_total_nilai_bersih numeric := 0;
  v_total_sewa_armada numeric := 0;
  v_total_panjar numeric := 0;
  v_total_tonase numeric := 0;
  v_total_berat_netto numeric := 0;
  v_total_berat_dibayar numeric := 0;
  item jsonb;
BEGIN
  IF NEW.transaksi_snapshot_json IS NOT NULL
     AND pg_catalog.jsonb_typeof(NEW.transaksi_snapshot_json) = 'array' THEN
    FOR item IN
      SELECT value
      FROM pg_catalog.jsonb_array_elements(NEW.transaksi_snapshot_json)
    LOOP
      v_total_nilai_bersih := v_total_nilai_bersih + COALESCE(
        NULLIF(item ->> 'total_nilai_bersih', '')::numeric,
        NULLIF(item ->> 'nilai_bersih', '')::numeric,
        0
      );
      v_total_sewa_armada := v_total_sewa_armada + COALESCE(
        NULLIF(item ->> 'biaya_sewa_armada_total', '')::numeric,
        NULLIF(item ->> 'sewa_armada', '')::numeric,
        0
      );
      v_total_tonase := v_total_tonase
        + COALESCE(NULLIF(item ->> 'tonase', '')::numeric, 0);
      v_total_berat_netto := v_total_berat_netto
        + COALESCE(NULLIF(item ->> 'berat_netto_pabrik_kg', '')::numeric, 0);
      v_total_berat_dibayar := v_total_berat_dibayar
        + COALESCE(NULLIF(item ->> 'berat_dibayar_kg', '')::numeric, 0);
    END LOOP;
  END IF;

  IF NEW.panjar_snapshot_json IS NOT NULL
     AND pg_catalog.jsonb_typeof(NEW.panjar_snapshot_json) = 'array' THEN
    FOR item IN
      SELECT value
      FROM pg_catalog.jsonb_array_elements(NEW.panjar_snapshot_json)
    LOOP
      v_total_panjar := v_total_panjar
        + COALESCE(NULLIF(item ->> 'jumlah', '')::numeric, 0);
    END LOOP;
  END IF;

  NEW.total_nilai_bersih := v_total_nilai_bersih;
  NEW.total_sewa_armada := v_total_sewa_armada;
  NEW.total_panjar := v_total_panjar;
  NEW.total_tonase := v_total_tonase;
  NEW.total_berat_netto := v_total_berat_netto;
  NEW.total_berat_dibayar := v_total_berat_dibayar;
  NEW.nominal_dibayar := GREATEST(
    0,
    (v_total_nilai_bersih - v_total_sewa_armada) - v_total_panjar
  );

  RETURN NEW;
END;
$function$;
