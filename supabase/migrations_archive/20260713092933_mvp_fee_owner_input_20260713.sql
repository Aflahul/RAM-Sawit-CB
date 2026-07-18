-- Sawit CB - Input Fee Owner per 2026-07-13
--
-- Catatan keputusan:
-- - BL/ML muncul di daftar fee 20 dan fee 30; nilai final mengikuti daftar terakhir = 30.
-- - SL/IMN dari input diarahkan ke master_mitra SL/IMAN.
-- - SL/WND tidak ada di master_mitra saat input ini dibuat; tidak dibuat otomatis.

WITH fee(kode, fee_per_kg, catatan) AS (
  VALUES
    ('SL', 20::numeric, NULL::text),
    ('BL', 20::numeric, NULL::text),
    ('SL/NL', 20::numeric, NULL::text),
    ('SL/CHT', 20::numeric, NULL::text),
    ('SL/F', 30::numeric, NULL::text),
    ('SL/MLD', 30::numeric, 'Input SL/MLD muncul dua kali di daftar fee 30'),
    ('SL/BS', 30::numeric, NULL::text),
    ('SL/HB', 30::numeric, NULL::text),
    ('SL/SW', 30::numeric, NULL::text),
    ('SL/WRD', 30::numeric, NULL::text),
    ('SL/ANC', 30::numeric, NULL::text),
    ('SL/B', 30::numeric, NULL::text),
    ('SL/IMAN', 30::numeric, 'Alias dari input SL/IMN'),
    ('SL/NSL', 30::numeric, NULL::text),
    ('BL/P', 30::numeric, NULL::text),
    ('BL/ML', 30::numeric, 'BL/ML muncul di fee 20 dan fee 30; nilai final mengikuti daftar terakhir = 30')
),
updated AS (
  UPDATE public.master_mitra mm
  SET fee_per_kg = fee.fee_per_kg
  FROM fee
  WHERE upper(btrim(mm.kode)) = upper(fee.kode)
  RETURNING mm.id, fee.fee_per_kg, fee.catatan
)
INSERT INTO public.fee_owner_mitra_history (
  master_mitra_id,
  fee_per_kg,
  berlaku_mulai,
  alasan_perubahan
)
SELECT
  id,
  fee_per_kg,
  DATE '2026-07-13',
  concat_ws(' - ', 'Input Fee Owner sesuai daftar user 2026-07-13', catatan)
FROM updated
ON CONFLICT (master_mitra_id, berlaku_mulai) DO UPDATE
SET fee_per_kg = EXCLUDED.fee_per_kg,
    alasan_perubahan = EXCLUDED.alasan_perubahan;
