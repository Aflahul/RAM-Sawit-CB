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
  tipe_mitra TEXT NOT NULL DEFAULT 'eksternal' CHECK (tipe_mitra IN ('eksternal', 'internal_owner')),
  fee_per_kg DECIMAL(10,2) DEFAULT 0,
  aktif BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Modifikasi Tabel Sopir
-- (Sopir terhubung dengan Mitra)
ALTER TABLE sopir ADD COLUMN IF NOT EXISTS mitra_id UUID REFERENCES master_mitra(id);
ALTER TABLE sopir ADD COLUMN IF NOT EXISTS plat_nomor VARCHAR(30);

-- 3. Tabel Transaksi Mitra (Input Timbangan MVP)
CREATE TABLE IF NOT EXISTS transaksi_mitra (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tanggal DATE NOT NULL,
  sopir_id UUID REFERENCES sopir(id),
  mitra_id UUID REFERENCES master_mitra(id),
  plat_nomor VARCHAR(20),
  sopir_default_id UUID REFERENCES sopir(id),
  sopir_default_nama VARCHAR(100),
  sopir_aktual_id UUID REFERENCES sopir(id),
  sopir_aktual_nama VARCHAR(100),
  sopir_aktual_no_hp VARCHAR(30),
  sopir_aktual_source TEXT DEFAULT 'master' CHECK (sopir_aktual_source IN ('master', 'manual')),
  sopir_diganti_dari_default BOOLEAN DEFAULT FALSE,
  catatan_sopir TEXT,
  tonase DECIMAL(10,2) NOT NULL,
  harga_harian DECIMAL(10,2) NOT NULL,
  total_kotor DECIMAL(15,2) NOT NULL,
  harga_pabrik_per_kg DECIMAL(12,2),
  fee_owner_per_kg DECIMAL(12,2),
  harga_bersih_per_kg DECIMAL(12,2),
  total_fee_owner DECIMAL(15,2),
  total_nilai_bersih DECIMAL(15,2),
  fee_owner_history_id UUID,
  status TEXT NOT NULL DEFAULT 'aktif' CHECK (status IN ('aktif', 'dibatalkan')),
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  updated_by UUID REFERENCES users(id),
  alasan_edit TEXT,
  dibatalkan_at TIMESTAMPTZ,
  dibatalkan_by UUID REFERENCES users(id),
  alasan_batal TEXT
);

CREATE TABLE IF NOT EXISTS fee_owner_mitra_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  master_mitra_id UUID NOT NULL REFERENCES master_mitra(id),
  fee_per_kg DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (fee_per_kg >= 0),
  berlaku_mulai DATE NOT NULL DEFAULT CURRENT_DATE,
  berlaku_sampai DATE,
  aktif BOOLEAN NOT NULL DEFAULT TRUE,
  alasan_perubahan TEXT,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fee_owner_mitra_history_periode_check CHECK (
    berlaku_sampai IS NULL OR berlaku_sampai > berlaku_mulai
  ),
  CONSTRAINT fee_owner_mitra_history_unique_start UNIQUE (master_mitra_id, berlaku_mulai)
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
CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_sopir_aktual ON transaksi_mitra(sopir_aktual_id);
CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_sopir_diganti ON transaksi_mitra(sopir_diganti_dari_default) WHERE sopir_diganti_dari_default = TRUE;
CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_status_tanggal ON transaksi_mitra(status, tanggal DESC);
CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_dibatalkan ON transaksi_mitra(dibatalkan_at DESC) WHERE status = 'dibatalkan';
CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_fee_owner_history ON transaksi_mitra(fee_owner_history_id);
CREATE INDEX IF NOT EXISTS idx_fee_owner_mitra_history_mitra_mulai ON fee_owner_mitra_history(master_mitra_id, berlaku_mulai DESC);
CREATE INDEX IF NOT EXISTS idx_master_mitra_tipe_mitra ON master_mitra(tipe_mitra);
CREATE INDEX IF NOT EXISTS idx_panjar_mitra_mitra ON panjar_mitra(mitra_id);

-- =============================================
-- Row Level Security (RLS)
-- =============================================
ALTER TABLE master_mitra ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaksi_mitra ENABLE ROW LEVEL SECURITY;
ALTER TABLE fee_owner_mitra_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE panjar_mitra ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated full access" ON master_mitra FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON transaksi_mitra FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON fee_owner_mitra_history FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON panjar_mitra FOR ALL TO authenticated USING (true) WITH CHECK (true);
