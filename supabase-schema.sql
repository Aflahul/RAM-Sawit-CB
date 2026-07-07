-- =============================================
-- SAWIT CB — Database Schema
-- Jalankan SQL ini di Supabase SQL Editor
-- (Dashboard → SQL Editor → New Query)
-- =============================================

-- 1. Tabel Users (terhubung dengan Supabase Auth)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nama VARCHAR(100) NOT NULL,
  username VARCHAR(50),
  role VARCHAR(10) NOT NULL DEFAULT 'admin' CHECK (role IN ('owner', 'admin')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Tabel Petani / Mitra
CREATE TABLE IF NOT EXISTS petani (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nama VARCHAR(100) NOT NULL,
  no_ktp VARCHAR(20),
  no_hp VARCHAR(20),
  alamat TEXT,
  batas_hutang DECIMAL(15,2) DEFAULT 0,
  aktif BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Tabel Harga TBS Harian
CREATE TABLE IF NOT EXISTS harga_tbs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tanggal DATE UNIQUE NOT NULL,
  harga_per_kg DECIMAL(10,2) NOT NULL,
  set_oleh UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Tabel Kendaraan
CREATE TABLE IF NOT EXISTS kendaraan (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plat_nomor VARCHAR(20) UNIQUE NOT NULL,
  jenis VARCHAR(50),
  kapasitas_ton DECIMAL(6,2),
  kepemilikan VARCHAR(10) DEFAULT 'sendiri' CHECK (kepemilikan IN ('sendiri', 'sewa')),
  aktif BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Tabel Sopir
CREATE TABLE IF NOT EXISTS sopir (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nama VARCHAR(100) NOT NULL,
  no_hp VARCHAR(20),
  kendaraan_id UUID REFERENCES kendaraan(id),
  aktif BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Tabel Pabrik
CREATE TABLE IF NOT EXISTS pabrik (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nama VARCHAR(100) NOT NULL,
  alamat TEXT,
  no_hp VARCHAR(20),
  aktif BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Tabel Transaksi Beli TBS (INTI)
CREATE TABLE IF NOT EXISTS transaksi_beli (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tanggal DATE NOT NULL,
  petani_id UUID REFERENCES petani(id),
  berat_kotor DECIMAL(10,2) NOT NULL,
  persen_potongan DECIMAL(5,2) DEFAULT 2.00,
  berat_bersih DECIMAL(10,2) NOT NULL,
  harga_per_kg DECIMAL(10,2) NOT NULL,
  total_harga DECIMAL(15,2) NOT NULL,
  potongan_hutang DECIMAL(15,2) DEFAULT 0,
  total_bayar_tunai DECIMAL(15,2) NOT NULL,
  keterangan TEXT,
  no_struk VARCHAR(20) UNIQUE,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Tabel Hutang
CREATE TABLE IF NOT EXISTS hutang (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  petani_id UUID REFERENCES petani(id),
  tanggal DATE NOT NULL,
  jenis VARCHAR(20) NOT NULL CHECK (jenis IN ('kasbon', 'panjar', 'pupuk', 'lainnya')),
  jumlah DECIMAL(15,2) NOT NULL,
  keterangan TEXT,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Tabel Hutang Log (Riwayat Pembayaran)
CREATE TABLE IF NOT EXISTS hutang_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  petani_id UUID REFERENCES petani(id),
  tanggal DATE NOT NULL,
  jumlah_bayar DECIMAL(15,2) NOT NULL,
  sumber VARCHAR(20) NOT NULL CHECK (sumber IN ('potong_tbs', 'bayar_tunai')),
  transaksi_beli_id UUID REFERENCES transaksi_beli(id),
  keterangan TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Tabel Pengiriman
CREATE TABLE IF NOT EXISTS pengiriman (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tanggal DATE NOT NULL,
  sopir_id UUID REFERENCES sopir(id),
  kendaraan_id UUID REFERENCES kendaraan(id),
  pabrik_id UUID REFERENCES pabrik(id),
  tonase_kirim DECIMAL(10,2) NOT NULL,
  no_do VARCHAR(50),
  status VARCHAR(10) DEFAULT 'dikirim' CHECK (status IN ('dikirim', 'diterima', 'dibayar')),
  harga_pabrik_per_kg DECIMAL(10,2),
  total_harga_pabrik DECIMAL(15,2),
  tanggal_bayar DATE,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. Tabel Biaya Operasional
CREATE TABLE IF NOT EXISTS biaya_operasional (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tanggal DATE NOT NULL,
  kategori VARCHAR(20) NOT NULL CHECK (kategori IN ('solar', 'gaji_sopir', 'kuli', 'retribusi', 'perawatan', 'lainnya')),
  jumlah DECIMAL(15,2) NOT NULL,
  keterangan TEXT,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- INDEX untuk performa query
-- =============================================

CREATE INDEX IF NOT EXISTS idx_transaksi_beli_tanggal ON transaksi_beli(tanggal);
CREATE INDEX IF NOT EXISTS idx_transaksi_beli_petani ON transaksi_beli(petani_id);
CREATE INDEX IF NOT EXISTS idx_hutang_petani ON hutang(petani_id);
CREATE INDEX IF NOT EXISTS idx_hutang_log_petani ON hutang_log(petani_id);
CREATE INDEX IF NOT EXISTS idx_pengiriman_tanggal ON pengiriman(tanggal);
CREATE INDEX IF NOT EXISTS idx_pengiriman_status ON pengiriman(status);
CREATE INDEX IF NOT EXISTS idx_biaya_tanggal ON biaya_operasional(tanggal);

-- =============================================
-- Row Level Security (RLS)
-- Aktifkan RLS tapi beri akses penuh ke authenticated users
-- =============================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE petani ENABLE ROW LEVEL SECURITY;
ALTER TABLE harga_tbs ENABLE ROW LEVEL SECURITY;
ALTER TABLE kendaraan ENABLE ROW LEVEL SECURITY;
ALTER TABLE sopir ENABLE ROW LEVEL SECURITY;
ALTER TABLE pabrik ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaksi_beli ENABLE ROW LEVEL SECURITY;
ALTER TABLE hutang ENABLE ROW LEVEL SECURITY;
ALTER TABLE hutang_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE pengiriman ENABLE ROW LEVEL SECURITY;
ALTER TABLE biaya_operasional ENABLE ROW LEVEL SECURITY;

-- Policy: Authenticated users bisa baca & tulis semua data
-- (Karena hanya 1-2 user, kita beri akses penuh)

CREATE POLICY "Authenticated full access" ON users FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON petani FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON harga_tbs FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON kendaraan FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON sopir FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON pabrik FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON transaksi_beli FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON hutang FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON hutang_log FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON pengiriman FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated full access" ON biaya_operasional FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- =============================================
-- INSERT User Owner pertama
-- (Jalankan SETELAH membuat akun di Supabase Auth)
-- Ganti 'YOUR_AUTH_USER_ID' dengan ID dari Authentication → Users
-- =============================================

-- INSERT INTO users (id, nama, username, role)
-- VALUES ('YOUR_AUTH_USER_ID', 'Nama Owner', 'owner', 'owner');
