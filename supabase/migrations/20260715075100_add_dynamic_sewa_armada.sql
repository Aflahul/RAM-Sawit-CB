-- 1. Tambah kolom tarif di master_mitra
ALTER TABLE public.master_mitra
  ADD COLUMN IF NOT EXISTS tarif_sewa_angkut_per_kg numeric(12,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS nominal_perongkosan numeric(15,2) DEFAULT 0;

COMMENT ON COLUMN public.master_mitra.tarif_sewa_angkut_per_kg IS 'Tarif sewa armada kotor per kg untuk mitra (jika menggunakan Armada CB)';
COMMENT ON COLUMN public.master_mitra.nominal_perongkosan IS 'Nominal flat (Rp) perongkosan per trip/transaksi yang mengurangi sewa armada kotor';

-- 2. Tambah kolom tarif di fee_owner_mitra_history
ALTER TABLE public.fee_owner_mitra_history
  ADD COLUMN IF NOT EXISTS tarif_sewa_angkut_per_kg numeric(12,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS nominal_perongkosan numeric(15,2) DEFAULT 0;

-- 3. Tambah kolom snapshot kotor & perongkosan di transaksi_mitra
-- Kolom biaya_sewa_armada_per_kg sudah ada, kita akan ubah maknanya atau biarkan.
-- Lebih aman tambah yang eksplisit kotor:
ALTER TABLE public.transaksi_mitra
  ADD COLUMN IF NOT EXISTS tarif_sewa_angkut_per_kg_snapshot numeric(12,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS nominal_perongkosan_snapshot numeric(15,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS biaya_sewa_armada_kotor numeric(15,2) DEFAULT 0;

COMMENT ON COLUMN public.transaksi_mitra.tarif_sewa_angkut_per_kg_snapshot IS 'Snapshot tarif_sewa_angkut_per_kg saat transaksi dibuat';
COMMENT ON COLUMN public.transaksi_mitra.nominal_perongkosan_snapshot IS 'Snapshot nominal_perongkosan saat transaksi dibuat';
COMMENT ON COLUMN public.transaksi_mitra.biaya_sewa_armada_kotor IS 'berat_netto_pabrik_kg * tarif_sewa_angkut_per_kg_snapshot';
-- Catatan: biaya_sewa_armada_total akan tetap menyimpan biaya akhir bersih (kotor - perongkosan)

-- 4. Set ulang riwayat tarif saat ini di fee_owner_mitra_history agar sinkron dengan master_mitra
UPDATE public.fee_owner_mitra_history h
SET 
  tarif_sewa_angkut_per_kg = m.tarif_sewa_angkut_per_kg,
  nominal_perongkosan = m.nominal_perongkosan
FROM public.master_mitra m
WHERE h.master_mitra_id = m.id AND h.aktif = true;

-- 5. Perbarui view atau fungsi terkait jika perlu
-- Supaya data riwayat lama (sebelum ini) tidak rusak:
UPDATE public.transaksi_mitra
SET 
  tarif_sewa_angkut_per_kg_snapshot = biaya_sewa_armada_per_kg,
  nominal_perongkosan_snapshot = 0,
  biaya_sewa_armada_kotor = biaya_sewa_armada_total
WHERE pakai_sewa_armada_bl = true AND tarif_sewa_angkut_per_kg_snapshot = 0;
