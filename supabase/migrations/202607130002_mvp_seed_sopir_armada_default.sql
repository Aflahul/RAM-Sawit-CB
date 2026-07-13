-- Sawit CB - Seed sopir/armada default MVP mitra
-- Jalankan setelah migration 202607130001_mvp_sopir_aktual_transaksi_mitra.sql.
--
-- Catatan mapping:
-- - SL/IMN dari data lapangan diarahkan ke master_mitra SL/IMAN.
-- - SL/MLO dari data lapangan diarahkan ke master_mitra SL/MLD.
-- - SL/MD dan SL/BL tidak diberi default mitra karena belum ada kode master yang cocok
--   atau merupakan armada bersama. Operator wajib memilih Mitra Transaksi saat input DO.
--
-- Catatan Supabase SQL Editor:
-- Jangan pakai TEMP TABLE di sini karena SQL Editor bisa menjalankan statement dengan
-- transaksi/koneksi berbeda. Seed ini memakai DO block agar aman dicopy-paste.

ALTER TABLE IF EXISTS public.sopir
  ADD COLUMN IF NOT EXISTS mitra_id uuid REFERENCES public.master_mitra(id),
  ADD COLUMN IF NOT EXISTS plat_nomor varchar(30);

DO $$
DECLARE
  seed_item record;
  target_mitra_id uuid;
  normalized_nama text;
  normalized_plat text;
  matched_rows integer;
BEGIN
  FOR seed_item IN
    SELECT *
    FROM (
      VALUES
        ('SL/BS (Mitra bismillah)', 'SL/BS', 'Samsul', 'DW 8785 BS', NULL),
        ('SL/BS (Mitra bismillah)', 'SL/BS', 'Andi', 'DP 8199 GM', NULL),
        ('SL/BS (Mitra bismillah)', 'SL/BS', 'Sulfikar', 'DP 8653 HK', NULL),
        ('SL/BS (Mitra bismillah)', 'SL/BS', 'Resa', 'DT 8119 DH', NULL),
        ('SL/BS (Mitra bismillah)', 'SL/BS', 'P. Kaco', 'DP 8203 DL', NULL),
        ('SL/BS (Mitra bismillah)', 'SL/BS', 'Wandi', 'DC 8423 PD', NULL),
        ('BL/LR', 'BL/LR', 'Ali', 'DD 8831 XX', NULL),
        ('BL/LR', 'BL/LR', 'Agus', 'DP 8925 HA', NULL),
        ('BL/LR', 'BL/LR', 'Agu', 'DP 8547 HK', NULL),
        ('BL/LR', 'BL/LR', 'Sandi', 'DW 8831 AJ', NULL),
        ('BL/LR', 'BL/LR', 'Ekki', 'DW 8952 HA', NULL),
        ('SL/IMN', 'SL/IMAN', 'Vick', 'KT 8492 EG', 'Alias SL/IMN -> SL/IMAN'),
        ('SL/IMN', 'SL/IMAN', 'Amir', 'DD 8850 QW', 'Alias SL/IMN -> SL/IMAN'),
        ('BL/P', 'BL/P', 'Anris', 'DP 8061 HK', NULL),
        ('BL/P', 'BL/P', 'Sulfi', 'DP 8905 HK', NULL),
        ('BL/P', 'BL/P', 'Jumardi', 'PB 8656 ME', NULL),
        ('SL/MD', NULL, 'Chanra', 'DP 8827 HB', 'Belum ada kode master_mitra yang cocok'),
        ('SL/B', 'SL/B', 'Rahman', 'DP 8497 HZ', NULL),
        ('SL/B', 'SL/B', 'Fadil', 'DP 8460 HK', NULL),
        ('SL/B', 'SL/B', 'Bahar', 'DP 8150 HK', NULL),
        ('SL/B', 'SL/B', 'Samson', 'DW 8614 BV', NULL),
        ('SL/WRD', 'SL/WRD', 'Aldi', 'DP 8477 HS', NULL),
        ('SL/HB (Mitra Habibi)', 'SL/HB', 'ullah', 'DD 8719 QZ', NULL),
        ('SL/HB (Mitra Habibi)', 'SL/HB', 'Andri', 'DP 8514 TE', NULL),
        ('SL/HB (Mitra Habibi)', 'SL/HB', 'Habibi', 'DP 8398 HI', NULL),
        ('SL/HB (Mitra Habibi)', 'SL/HB', 'Anis', 'DW 8790 CI', NULL),
        ('SL/HB (Mitra Habibi)', 'SL/HB', 'EDI', 'DD 8174 KP', NULL),
        ('SL/CHT (Mitra Risti CHT)', 'SL/CHT', 'Reza', 'DP 8590 HJ', NULL),
        ('SL/CHT (Mitra Risti CHT)', 'SL/CHT', 'Noyo', 'DN 8821 NY', NULL),
        ('SL/CHT (Mitra Risti CHT)', 'SL/CHT', 'Suwandi', 'DP 8741 HF', NULL),
        ('SL/CHT (Mitra Risti CHT)', 'SL/CHT', 'Budi', 'DT 8524 HE', NULL),
        ('SL/F (Mitra Faisal)', 'SL/F', 'Efendi', 'DP 8687 HK', NULL),
        ('SL/F (Mitra Faisal)', 'SL/F', 'Tola', 'DP 8291 HJ', NULL),
        ('SL/F (Mitra Faisal)', 'SL/F', 'Dekwi', 'DP 8633 HC', NULL),
        ('SL/F (Mitra Faisal)', 'SL/F', 'Randi', 'DP 8260 HF', NULL),
        ('SL/F (Mitra Faisal)', 'SL/F', 'Agustinus', 'DB 8347 QC', NULL),
        ('SL/F (Mitra Faisal)', 'SL/F', 'Rion', 'DP 8716 HK', NULL),
        ('SL/F (Mitra Faisal)', 'SL/F', 'Sumardi', 'KT 8793 MS', NULL),
        ('SL/BL (Mobil CB.)', NULL, 'AKBAR', 'DD 8013 LW', 'Armada bersama/pool Mobil CB'),
        ('SL/BL (Mobil CB.)', NULL, 'Aspar', 'KT 8491 BJ', 'Armada bersama/pool Mobil CB'),
        ('SL/BL (Mobil CB.)', NULL, 'Bahtiar', 'DP 8098 HJ', 'Armada bersama/pool Mobil CB'),
        ('SL/BL (Mobil CB.)', NULL, 'IRsan', 'DP 8098 HS', 'Armada bersama/pool Mobil CB'),
        ('SL/BL (Mobil CB.)', NULL, 'Awi', 'DP 8404 HI', 'Armada bersama/pool Mobil CB'),
        ('SL/BL (Mobil CB.)', NULL, 'Ferdi', 'DP 8871 HJ', 'Armada bersama/pool Mobil CB'),
        ('SL/BL (Mobil CB.)', NULL, 'Yudi', 'DP 8891 BC', 'Armada bersama/pool Mobil CB'),
        ('SL/BL (Mobil CB.)', NULL, 'Agung', 'B 9233 TIW', 'Armada bersama/pool Mobil CB'),
        ('SL/BL (Mobil CB.)', NULL, 'Wawan', 'B 9233 TI', 'Armada bersama/pool Mobil CB'),
        ('SL/BL (Mobil CB.)', NULL, 'Subair', 'B 9233 KI', 'Armada bersama/pool Mobil CB'),
        ('SL/BL (Mobil CB.)', NULL, 'Bagong', 'DD 9894 PA', 'Armada bersama/pool Mobil CB'),
        ('SL/MLO (Mobil Muliyadi)', 'SL/MLD', 'Alang', 'DD 8874 HA', 'Alias SL/MLO -> SL/MLD'),
        ('SL/MLO (Mobil Muliyadi)', 'SL/MLD', 'Madi', 'DP 8452 HJ', 'Alias SL/MLO -> SL/MLD'),
        ('SL/MLO (Mobil Muliyadi)', 'SL/MLD', 'Rijal', 'DP 8959 HD', 'Alias SL/MLO -> SL/MLD'),
        ('SL/MLO (Mobil Muliyadi)', 'SL/MLD', 'Fendi', 'DD 8369 SH', 'Alias SL/MLO -> SL/MLD'),
        ('SL/MLO (Mobil Muliyadi)', 'SL/MLD', 'Rusli', 'DP 8438 HE', 'Alias SL/MLO -> SL/MLD'),
        ('SL/MLO (Mobil Muliyadi)', 'SL/MLD', 'Lalang', 'DP 8030 GJ', 'Alias SL/MLO -> SL/MLD')
    ) AS v(source_grup, mitra_kode, nama, plat_nomor, catatan)
  LOOP
    normalized_nama := btrim(seed_item.nama);
    normalized_plat := upper(regexp_replace(btrim(seed_item.plat_nomor), '[[:space:]]+', ' ', 'g'));

    SELECT id
    INTO target_mitra_id
    FROM public.master_mitra
    WHERE kode = seed_item.mitra_kode;

    UPDATE public.sopir s
    SET
      plat_nomor = CASE
        WHEN NULLIF(btrim(s.plat_nomor), '') IS NULL THEN normalized_plat
        ELSE s.plat_nomor
      END,
      mitra_id = COALESCE(s.mitra_id, target_mitra_id),
      aktif = true
    WHERE lower(btrim(s.nama)) = lower(normalized_nama)
      AND (
        NULLIF(btrim(s.plat_nomor), '') IS NULL
        OR upper(regexp_replace(btrim(s.plat_nomor), '[[:space:]]+', ' ', 'g')) = normalized_plat
      );

    GET DIAGNOSTICS matched_rows = ROW_COUNT;

    IF matched_rows = 0 AND NOT EXISTS (
      SELECT 1
      FROM public.sopir s
      WHERE lower(btrim(s.nama)) = lower(normalized_nama)
        AND upper(regexp_replace(btrim(COALESCE(s.plat_nomor, '')), '[[:space:]]+', ' ', 'g')) = normalized_plat
    ) THEN
      INSERT INTO public.sopir (nama, no_hp, mitra_id, plat_nomor, aktif)
      VALUES (normalized_nama, NULL, target_mitra_id, normalized_plat, true);
    END IF;
  END LOOP;
END $$;

SELECT 'Seed sopir/armada selesai. Cek Owner > Master Data > Armada & Sopir.' AS status;
