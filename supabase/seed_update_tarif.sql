UPDATE public.master_mitra SET nominal_perongkosan = 800000, tarif_sewa_angkut_per_kg = 150 WHERE kode = 'SL';
UPDATE public.master_mitra SET nominal_perongkosan = 750000, tarif_sewa_angkut_per_kg = 150 WHERE kode = 'BL';
UPDATE public.master_mitra SET nominal_perongkosan = 750000, tarif_sewa_angkut_per_kg = 150 WHERE kode = 'SL/F';
UPDATE public.master_mitra SET nominal_perongkosan = 750000, tarif_sewa_angkut_per_kg = 150 WHERE kode = 'SL/BS';
UPDATE public.master_mitra SET nominal_perongkosan = 750000, tarif_sewa_angkut_per_kg = 150 WHERE kode = 'SL/MLD';
UPDATE public.master_mitra SET nominal_perongkosan = 900000, tarif_sewa_angkut_per_kg = 180 WHERE kode = 'BL/ML';

-- Setelah update master, kita update history yang masih aktif agar sinkron
UPDATE public.fee_owner_mitra_history h
SET 
  nominal_perongkosan = m.nominal_perongkosan,
  tarif_sewa_angkut_per_kg = m.tarif_sewa_angkut_per_kg
FROM public.master_mitra m
WHERE h.master_mitra_id = m.id AND h.aktif = true;
