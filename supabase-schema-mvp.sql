-- =============================================
-- SAWIT CB — Database Schema (ADDENDUM MVP)
-- Jalankan SQL ini di Supabase SQL Editor
-- =============================================

-- 1. Tabel Master Mitra
CREATE TABLE IF NOT EXISTS master_mitra (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kode VARCHAR(20) UNIQUE,
  nama VARCHAR(100) NOT NULL,
  penanggung_jawab VARCHAR(100),
  no_hp VARCHAR(20),
  alamat TEXT,
  fee_per_kg DECIMAL(10,2) DEFAULT 0,
  aktif BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Modifikasi Tabel Sopir
-- (Sopir terhubung dengan Mitra)
ALTER TABLE sopir ADD COLUMN IF NOT EXISTS mitra_id UUID REFERENCES master_mitra(id);

-- 3. Tabel Transaksi Mitra (Input Timbangan MVP)
CREATE TABLE IF NOT EXISTS transaksi_mitra (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tanggal DATE NOT NULL,
  sopir_id UUID REFERENCES sopir(id),
  mitra_id UUID REFERENCES master_mitra(id),
  plat_nomor VARCHAR(20),
  tonase DECIMAL(10,2) NOT NULL,
  harga_harian DECIMAL(10,2) NOT NULL,
  total_kotor DECIMAL(15,2) NOT NULL,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Tabel Panjar Mitra
CREATE TABLE IF NOT EXISTS panjar_mitra (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tanggal DATE NOT NULL,
  mitra_id UUID REFERENCES master_mitra(id),
  jumlah DECIMAL(15,2) NOT NULL,
  keterangan TEXT,
  status VARCHAR(20) DEFAULT 'belum_lunas' CHECK (status IN ('belum_lunas', 'lunas')),
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- INDEX
-- =============================================
CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_tanggal ON transaksi_mitra(tanggal);
CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_mitra ON transaksi_mitra(mitra_id);
CREATE INDEX IF NOT EXISTS idx_panjar_mitra_mitra ON panjar_mitra(mitra_id);

-- =============================================
-- Row Level Security (RLS)
-- =============================================
ALTER TABLE master_mitra ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaksi_mitra ENABLE ROW LEVEL SECURITY;
ALTER TABLE panjar_mitra ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated full access" ON master_mitra FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON transaksi_mitra FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON panjar_mitra FOR ALL TO authenticated USING (true) WITH CHECK (true);
