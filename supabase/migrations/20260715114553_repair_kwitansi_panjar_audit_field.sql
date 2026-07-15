-- panjar_mitra tidak memiliki updated_by; gunakan updated_at dari trigger tabel.

BEGIN;

DO $$
DECLARE
  v_definition text;
  v_old_fragment text := E'lunas_at = now(),\n      updated_by = v_actor';
BEGIN
  SELECT pg_get_functiondef(
    'public.create_pembayaran_mitra_kwitansi(uuid,date,date,text,text,uuid[],text)'::regprocedure
  ) INTO v_definition;

  IF position(v_old_fragment IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Pola updated_by panjar pada create_pembayaran_mitra_kwitansi tidak ditemukan.';
  END IF;

  v_definition := replace(v_definition, v_old_fragment, 'lunas_at = now()');
  EXECUTE v_definition;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pembayaran_mitra_kwitansi(
  uuid, date, date, text, text, uuid[], text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pembayaran_mitra_kwitansi(
  uuid, date, date, text, text, uuid[], text
) TO authenticated;

COMMIT;
