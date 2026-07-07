'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, formatNumber, getTodayISO } from '@/lib/utils';
import Link from 'next/link';

export default function DashboardPage() {
  const [stats, setStats] = useState({
    tbsMasukKg: 0,
    tbsMasukRp: 0,
    jumlahTransaksi: 0,
    hutangAktif: 0,
    jumlahPetaniHutang: 0,
    totalBiaya: 0,
    pengirimanPending: 0,
  });
  const [recentTransactions, setRecentTransactions] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadDashboard();
  }, []);

  async function loadDashboard() {
    try {
      const today = getTodayISO();

      // TBS masuk hari ini
      const { data: tbsData } = await supabase
        .from('transaksi_beli')
        .select('berat_bersih, total_harga')
        .eq('tanggal', today);

      const tbsMasukKg = tbsData?.reduce((sum, t) => sum + (t.berat_bersih || 0), 0) || 0;
      const tbsMasukRp = tbsData?.reduce((sum, t) => sum + (t.total_harga || 0), 0) || 0;

      // Hutang aktif - sum semua hutang dikurangi semua pembayaran
      const { data: hutangData } = await supabase
        .from('hutang')
        .select('jumlah, petani_id');

      const { data: hutangLogData } = await supabase
        .from('hutang_log')
        .select('jumlah_bayar');

      const totalHutang = hutangData?.reduce((sum, h) => sum + (h.jumlah || 0), 0) || 0;
      const totalBayar = hutangLogData?.reduce((sum, h) => sum + (h.jumlah_bayar || 0), 0) || 0;
      const hutangAktif = totalHutang - totalBayar;

      const uniquePetaniHutang = new Set(hutangData?.map(h => h.petani_id) || []);

      // Biaya hari ini
      const { data: biayaData } = await supabase
        .from('biaya_operasional')
        .select('jumlah')
        .eq('tanggal', today);

      const totalBiaya = biayaData?.reduce((sum, b) => sum + (b.jumlah || 0), 0) || 0;

      // Pengiriman pending
      const { count: pengirimanPending } = await supabase
        .from('pengiriman')
        .select('*', { count: 'exact', head: true })
        .in('status', ['dikirim', 'diterima']);

      // Transaksi terbaru
      const { data: recent } = await supabase
        .from('transaksi_beli')
        .select('*, petani:petani_id(nama)')
        .order('created_at', { ascending: false })
        .limit(5);

      setStats({
        tbsMasukKg,
        tbsMasukRp,
        jumlahTransaksi: tbsData?.length || 0,
        hutangAktif,
        jumlahPetaniHutang: uniquePetaniHutang.size,
        totalBiaya,
        pengirimanPending: pengirimanPending || 0,
      });

      setRecentTransactions(recent || []);
    } catch (err) {
      console.error('Error loading dashboard:', err);
    } finally {
      setLoading(false);
    }
  }

  return (
    <AppShell title="Dashboard" subtitle="Ringkasan operasional hari ini">
      {/* Stats Grid */}
      <div className="stats-grid">
        {/* TBS Masuk */}
        <div className="card">
          <div className="card-header">
            <span className="card-title">TBS Masuk Hari Ini</span>
            <div className="card-icon card-icon-green">📦</div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '60%', marginBottom: 8 }}></div>
          ) : (
            <>
              <div className="card-value">{formatNumber(stats.tbsMasukKg)} <span style={{ fontSize: 'var(--text-base)', fontWeight: 400 }}>kg</span></div>
              <div className="card-label">{formatRupiah(stats.tbsMasukRp)} • {stats.jumlahTransaksi} transaksi</div>
            </>
          )}
          <div className="card-footer">
            <Link href="/transaksi/beli" className="btn btn-ghost btn-sm">
              + Input TBS
            </Link>
          </div>
        </div>

        {/* Hutang Aktif */}
        <div className="card">
          <div className="card-header">
            <span className="card-title">Hutang Aktif Petani</span>
            <div className="card-icon card-icon-gold">💳</div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '70%', marginBottom: 8 }}></div>
          ) : (
            <>
              <div className="card-value">{formatRupiah(stats.hutangAktif)}</div>
              <div className="card-label">{stats.jumlahPetaniHutang} petani memiliki hutang</div>
            </>
          )}
          <div className="card-footer">
            <Link href="/keuangan/hutang" className="btn btn-ghost btn-sm">
              Lihat Detail →
            </Link>
          </div>
        </div>

        {/* Biaya Hari Ini */}
        <div className="card">
          <div className="card-header">
            <span className="card-title">Biaya Hari Ini</span>
            <div className="card-icon card-icon-red">🔧</div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '50%', marginBottom: 8 }}></div>
          ) : (
            <>
              <div className="card-value">{formatRupiah(stats.totalBiaya)}</div>
              <div className="card-label">Total pengeluaran operasional</div>
            </>
          )}
          <div className="card-footer">
            <Link href="/keuangan/biaya" className="btn btn-ghost btn-sm">
              + Input Biaya
            </Link>
          </div>
        </div>

        {/* Pengiriman Pending */}
        <div className="card">
          <div className="card-header">
            <span className="card-title">Pengiriman Pending</span>
            <div className="card-icon card-icon-blue">🚚</div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '30%', marginBottom: 8 }}></div>
          ) : (
            <>
              <div className="card-value">{stats.pengirimanPending}</div>
              <div className="card-label">Belum selesai / belum dibayar</div>
            </>
          )}
          <div className="card-footer">
            <Link href="/transaksi/kirim" className="btn btn-ghost btn-sm">
              Lihat Pengiriman →
            </Link>
          </div>
        </div>
      </div>

      {/* Recent Transactions */}
      <div className="card" style={{ marginTop: 'var(--space-lg)' }}>
        <div className="card-header">
          <span className="card-title">Transaksi Terakhir</span>
          <Link href="/transaksi/beli" className="btn btn-outline btn-sm">
            Lihat Semua
          </Link>
        </div>
        {loading ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {[1, 2, 3].map((i) => (
              <div key={i} className="skeleton" style={{ height: 44 }}></div>
            ))}
          </div>
        ) : recentTransactions.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-icon">📦</div>
            <div className="empty-state-title">Belum ada transaksi</div>
            <div className="empty-state-text">
              Mulai input pembelian TBS dari petani
            </div>
          </div>
        ) : (
          <div className="table-container" style={{ border: 'none' }}>
            <table className="table">
              <thead>
                <tr>
                  <th>No. Struk</th>
                  <th>Petani</th>
                  <th style={{ textAlign: 'right' }}>Berat (kg)</th>
                  <th style={{ textAlign: 'right' }}>Total</th>
                </tr>
              </thead>
              <tbody>
                {recentTransactions.map((t) => (
                  <tr key={t.id}>
                    <td className="table-mono">{t.no_struk || '-'}</td>
                    <td>{t.petani?.nama || '-'}</td>
                    <td className="table-mono" style={{ textAlign: 'right' }}>
                      {formatNumber(t.berat_bersih)}
                    </td>
                    <td className="table-mono" style={{ textAlign: 'right' }}>
                      {formatRupiah(t.total_harga)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Quick Actions */}
      <div style={{ marginTop: 'var(--space-xl)' }}>
        <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600, marginBottom: 'var(--space-md)', color: 'var(--text-secondary)' }}>
          Aksi Cepat
        </h3>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 'var(--space-md)' }}>
          <Link href="/transaksi/beli" className="card" style={{ textAlign: 'center', textDecoration: 'none', cursor: 'pointer' }}>
            <div style={{ fontSize: '2rem', marginBottom: 8 }}>📦</div>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Input TBS</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)' }}>Pembelian dari petani</div>
          </Link>
          <Link href="/keuangan/hutang" className="card" style={{ textAlign: 'center', textDecoration: 'none', cursor: 'pointer' }}>
            <div style={{ fontSize: '2rem', marginBottom: 8 }}>💳</div>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Kasbon Petani</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)' }}>Tambah hutang / panjar</div>
          </Link>
          <Link href="/transaksi/kirim" className="card" style={{ textAlign: 'center', textDecoration: 'none', cursor: 'pointer' }}>
            <div style={{ fontSize: '2rem', marginBottom: 8 }}>🚚</div>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Kirim ke Pabrik</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)' }}>Catat pengiriman TBS</div>
          </Link>
          <Link href="/keuangan/biaya" className="card" style={{ textAlign: 'center', textDecoration: 'none', cursor: 'pointer' }}>
            <div style={{ fontSize: '2rem', marginBottom: 8 }}>🔧</div>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Biaya Operasional</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)' }}>Solar, gaji, retribusi</div>
          </Link>
        </div>
      </div>
    </AppShell>
  );
}
