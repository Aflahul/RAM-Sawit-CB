BEGIN;

-- Older paid receipts stored the panjar id and amount but not its owner. Enrich
-- those immutable snapshots from the linked panjar row so grouped receipts can
-- always attach a deduction to the correct partner.
WITH rebuilt AS (
  SELECT
    payment.id,
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
    ) AS snapshot
  FROM public.pembayaran_mitra_kwitansi payment
  CROSS JOIN LATERAL jsonb_array_elements(payment.panjar_snapshot_json)
    WITH ORDINALITY AS item(value, ordinality)
  LEFT JOIN public.panjar_mitra panjar
    ON panjar.id = CASE
      WHEN COALESCE(item.value ->> 'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        THEN (item.value ->> 'id')::uuid
      ELSE NULL
    END
  LEFT JOIN public.master_mitra mitra ON mitra.id = panjar.mitra_id
  WHERE jsonb_typeof(payment.panjar_snapshot_json) = 'array'
    AND jsonb_array_length(payment.panjar_snapshot_json) > 0
  GROUP BY payment.id
)
UPDATE public.pembayaran_mitra_kwitansi payment
SET panjar_snapshot_json = rebuilt.snapshot,
    updated_at = now()
FROM rebuilt
WHERE payment.id = rebuilt.id
  AND payment.panjar_snapshot_json IS DISTINCT FROM rebuilt.snapshot;

CREATE OR REPLACE FUNCTION public.validate_kwitansi_deductions_per_mitra()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

REVOKE ALL ON FUNCTION public.validate_kwitansi_deductions_per_mitra() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS validate_kwitansi_deductions_per_mitra
  ON public.pembayaran_mitra_kwitansi;
CREATE TRIGGER validate_kwitansi_deductions_per_mitra
BEFORE INSERT OR UPDATE OF transaksi_snapshot_json, panjar_snapshot_json
ON public.pembayaran_mitra_kwitansi
FOR EACH ROW
EXECUTE FUNCTION public.validate_kwitansi_deductions_per_mitra();

COMMIT;
