-- Serialize payment creation per transaction snapshot so concurrent requests
-- cannot pay the same transaksi_mitra twice before either request commits.
CREATE OR REPLACE FUNCTION public.prevent_duplicate_active_kwitansi_transactions()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_transaction_id uuid;
BEGIN
  FOR v_transaction_id IN
    SELECT DISTINCT (item ->> 'id')::uuid
    FROM jsonb_array_elements(COALESCE(NEW.transaksi_snapshot_json, '[]'::jsonb)) item
    WHERE COALESCE(item ->> 'id', '')
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    ORDER BY 1
  LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_transaction_id::text, 20260719231734)
    );
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(COALESCE(NEW.transaksi_snapshot_json, '[]'::jsonb)) item
    JOIN public.pembayaran_mitra_kwitansi_item payment_item
      ON payment_item.transaksi_mitra_id = (item ->> 'id')::uuid
    JOIN public.pembayaran_mitra_kwitansi payment
      ON payment.id = payment_item.pembayaran_id
    WHERE COALESCE(item ->> 'id', '')
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      AND payment.status <> 'dibatalkan'
  ) THEN
    RAISE EXCEPTION 'Satu atau lebih transaksi sudah masuk kwitansi pembayaran aktif.'
      USING ERRCODE = '23505';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.prevent_duplicate_active_kwitansi_transactions()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS prevent_duplicate_active_kwitansi_transactions
ON public.pembayaran_mitra_kwitansi;

CREATE TRIGGER prevent_duplicate_active_kwitansi_transactions
BEFORE INSERT OR UPDATE OF transaksi_snapshot_json
ON public.pembayaran_mitra_kwitansi
FOR EACH ROW
EXECUTE FUNCTION public.prevent_duplicate_active_kwitansi_transactions();
