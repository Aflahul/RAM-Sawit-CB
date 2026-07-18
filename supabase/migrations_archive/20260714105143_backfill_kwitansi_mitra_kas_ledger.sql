-- Backfill pembayaran mitra yang sudah terlanjur berstatus dibayar sebelum
-- fungsi create_pembayaran_mitra_kwitansi membuat mutasi kas_ledger.
-- Idempotent: aman dijalankan ulang karena memakai idempotency_key dan link
-- ke source pembayaran_mitra_kwitansi yang sama.

BEGIN;

WITH target_payments AS (
  SELECT
    pmk.id,
    pmk.tanggal_bayar,
    pmk.dibayar_at,
    pmk.created_at,
    pmk.periode_dari,
    pmk.periode_sampai,
    pmk.nominal_dibayar,
    pmk.created_by,
    pmk.updated_by
  FROM public.pembayaran_mitra_kwitansi pmk
  WHERE pmk.status = 'dibayar'
    AND COALESCE(pmk.nominal_dibayar, 0) > 0
    AND pmk.kas_ledger_id IS NULL
),
existing_ledgers AS (
  SELECT DISTINCT ON (target.id)
    target.id AS payment_id,
    ledger.id AS kas_ledger_id,
    ledger.rekening_kas_id
  FROM target_payments target
  JOIN public.kas_ledger ledger
    ON ledger.status <> 'dibatalkan'
   AND (
     ledger.pembayaran_mitra_kwitansi_id = target.id
     OR (
       ledger.source_table = 'pembayaran_mitra_kwitansi'
       AND ledger.source_id = target.id
     )
     OR ledger.idempotency_key = 'pembayaran_mitra_kwitansi:' || target.id::text
   )
  ORDER BY target.id, ledger.created_at DESC
),
payments_to_insert AS (
  SELECT target.*
  FROM target_payments target
  LEFT JOIN existing_ledgers existing ON existing.payment_id = target.id
  WHERE existing.payment_id IS NULL
),
inserted_ledgers AS (
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
  SELECT
    public.get_default_rekening_kas_id(),
    COALESCE(
      payment.tanggal_bayar,
      (payment.dibayar_at AT TIME ZONE 'Asia/Jakarta')::date,
      (payment.created_at AT TIME ZONE 'Asia/Jakarta')::date,
      CURRENT_DATE
    ),
    'keluar',
    'pembayaran_mitra',
    payment.nominal_dibayar,
    payment.id,
    'pembayaran_mitra_kwitansi',
    payment.id,
    'pembayaran_mitra_kwitansi:' || payment.id::text,
    'Backfill kas keluar pembayaran kwitansi mitra periode '
      || payment.periode_dari::text || ' s/d ' || payment.periode_sampai::text,
    COALESCE(payment.created_by, payment.updated_by)
  FROM payments_to_insert payment
  ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING
  RETURNING
    pembayaran_mitra_kwitansi_id AS payment_id,
    id AS kas_ledger_id,
    rekening_kas_id
),
ledger_links AS (
  SELECT * FROM existing_ledgers
  UNION ALL
  SELECT * FROM inserted_ledgers
)
UPDATE public.pembayaran_mitra_kwitansi pmk
SET
  rekening_kas_id = ledger_links.rekening_kas_id,
  kas_ledger_id = ledger_links.kas_ledger_id,
  updated_at = now()
FROM ledger_links
WHERE pmk.id = ledger_links.payment_id
  AND pmk.kas_ledger_id IS NULL;

COMMIT;
