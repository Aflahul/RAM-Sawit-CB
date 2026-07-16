BEGIN;

CREATE OR REPLACE FUNCTION public.enrich_kwitansi_panjar_snapshot_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.enrich_kwitansi_panjar_snapshot_owner()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS a_enrich_kwitansi_panjar_snapshot_owner
  ON public.pembayaran_mitra_kwitansi;
CREATE TRIGGER a_enrich_kwitansi_panjar_snapshot_owner
BEFORE INSERT OR UPDATE OF panjar_snapshot_json
ON public.pembayaran_mitra_kwitansi
FOR EACH ROW
EXECUTE FUNCTION public.enrich_kwitansi_panjar_snapshot_owner();

COMMIT;
