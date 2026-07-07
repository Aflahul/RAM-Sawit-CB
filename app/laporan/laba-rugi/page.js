'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah } from '@/lib/utils';

export default function LabaRugiPage() {
  const [periode, setPeriode] = useState('bulanan');
  const [bulan, setBulan] = useState(new Date().getMonth() + 1);
  const [tahun, setTahun] = useState(new Date().getFullYear());
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [userRole, setUserRole] = useState(null);

  useEffect(() => {
    checkRole();
  }, []);

  useEffect(() => {
    if (userRole === 'owner') loadData();
  }, [bulan, tahun, periode, userRole]);

  async function checkRole() {
    const { data: { session } } = await supabase.auth.getSession();
    if (session) {
      const { data: user } = await supabase.from('users').select('role').eq('id', session.user.id).single();
      setUserRole(user?.role || 'admin');
    }
  }

  async function loadData() {
    setLoading(true);

    let startDate, endDate;
    if (periode === 'bulanan') {
      startDate = `${tahun}-${bulan.toString().padStart(2, '0')}-01`;
      const lastDay = new Date(tahun, bulan, 0).getDate();
      endDate = `${tahun}-${bulan.toString().padStart(2, '0')}-${lastDay}`;
    } else {
      startDate = `${tahun}-01-01`;
      endDate = `${tahun}-12-31`;
    }

    // Pendapatan: Pengiriman yang sudah dibayar
    const { data: pendapatan } = await supabase
      .from('pengiriman')
      .select('total_harga_pabrik')
      .eq('status', 'dibayar')
      .gte('tanggal_bayar', startDate)
      .lte('tanggal_bayar', endDate);

    const totalPendapatan = (pendapatan || []).reduce((s, p) => s + (p.total_harga_pabrik || 0), 0);

    // Pengeluaran: Pembelian TBS
    const { data: pembelian } = await supabase
      .from('transaksi_beli')
      .select('total_harga')
      .gte('tanggal', startDate)
      .lte('tanggal', endDate);

    const totalPembelian = (pembelian || []).reduce((s, t) => s + (t.total_harga || 0), 0);

    // Pengeluaran: Biaya Operasional
    const { data: biaya } = await supabase
      .from('biaya_operasional')
      .select('kategori, jumlah')
      .gte('tanggal', startDate)
      .lte('tanggal', endDate);

    const biayaPerKategori = {};
    (biaya || []).forEach(b => {
      biayaPerKategori[b.kategori] = (biayaPerKategori[b.kategori] || 0) + (b.jumlah || 0);
    });
    const totalBiaya = (biaya || []).reduce((s, b) => s + (b.jumlah || 0), 0);

    const totalPengeluaran = totalPembelian + totalBiaya;
    const labaBersih = totalPendapatan - totalPengeluaran;

    setData({
      totalPendapatan,
      totalPembelian,
      biayaPerKategori,
      totalBiaya,
      totalPengeluaran,
      labaBersih,
      jumlahTxPendapatan: pendapatan?.length || 0,
      jumlahTxPembelian: pembelian?.length || 0,
    });

    setLoading(false);
  }

  const kategoriLabel = {
    solar: '⛽ Solar / BBM', gaji_sopir: '👤 Gaji Sopir', kuli: '💪 Kuli Bongkar',
    retribusi: '📋 Retribusi', perawatan: '🔧 Perawatan', lainnya: '📦 Lainnya',
  };

  const bulanNama = [
    '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  // Block admin
  if (userRole === 'admin') {
    return (
      <AppShell title="Laba / Rugi" subtitle="Akses terbatas">
        <div className="empty-state" style={{ marginTop: 'var(--space-3xl)' }}>
          <div className="empty-state-icon">🔒</div>
          <div className="empty-state-title">Akses Ditolak</div>
          <div className="empty-state-text">
            Halaman Laba/Rugi hanya dapat diakses oleh Owner.
            Hubungi pemilik untuk informasi keuangan.
          </div>
        </div>
      </AppShell>
    );
  }

  if (userRole === null) {
    return (
      <AppShell title="Laba / Rugi">
        <div style={{ textAlign: 'center', padding: 'var(--space-3xl)' }}>
          <div className="spinner spinner-lg" style={{ margin: '0 auto' }}></div>
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title="Laba / Rugi" subtitle="Laporan keuangan — Owner Only">
      <div className="page-header">
        <div>
          <h2 className="page-title">💰 Laporan Laba / Rugi</h2>
          <p className="page-description">
            {periode === 'bulanan' ? `${bulanNama[bulan]} ${tahun}` : `Tahun ${tahun}`}
          </p>
        </div>
        <div className="flex gap-sm items-center" style={{ flexWrap: 'wrap' }}>
          <select className="form-input form-select" value={periode} onChange={e => setPeriode(e.target.value)} style={{ width: 140 }}>
            <option value="bulanan">Bulanan</option>
            <option value="tahunan">Tahunan</option>
          </select>
          {periode === 'bulanan' && (
            <select className="form-input form-select" value={bulan} onChange={e => setBulan(parseInt(e.target.value))} style={{ width: 150 }}>
              {bulanNama.slice(1).map((n, i) => <option key={i + 1} value={i + 1}>{n}</option>)}
            </select>
          )}
          <select className="form-input form-select" value={tahun} onChange={e => setTahun(parseInt(e.target.value))} style={{ width: 100 }}>
            {[2024, 2025, 2026, 2027].map(y => <option key={y} value={y}>{y}</option>)}
          </select>
        </div>
      </div>

      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          {[1, 2, 3].map(i => <div key={i} className="skeleton" style={{ height: 100 }}></div>)}
        </div>
      ) : !data ? null : (
        <>
          {/* Summary Cards */}
          <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(3, 1fr)' }}>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Pendapatan</span>
                <div className="card-icon card-icon-green">📈</div>
              </div>
              <div className="card-value" style={{ color: 'var(--color-success)' }}>{formatRupiah(data.totalPendapatan)}</div>
              <div className="card-label">{data.jumlahTxPendapatan} pengiriman dibayar</div>
            </div>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Pengeluaran</span>
                <div className="card-icon card-icon-red">📉</div>
              </div>
              <div className="card-value" style={{ color: 'var(--color-danger)' }}>{formatRupiah(data.totalPengeluaran)}</div>
              <div className="card-label">Pembelian TBS + Biaya Ops</div>
            </div>
            <div className="card" style={{ border: data.labaBersih >= 0 ? '1px solid rgba(46,204,113,0.3)' : '1px solid rgba(231,76,60,0.3)' }}>
              <div className="card-header">
                <span className="card-title">{data.labaBersih >= 0 ? 'LABA BERSIH' : 'RUGI BERSIH'}</span>
                <div className={`card-icon ${data.labaBersih >= 0 ? 'card-icon-green' : 'card-icon-red'}`}>
                  {data.labaBersih >= 0 ? '🎉' : '⚠️'}
                </div>
              </div>
              <div className="card-value" style={{ color: data.labaBersih >= 0 ? 'var(--color-success)' : 'var(--color-danger)' }}>
                {formatRupiah(Math.abs(data.labaBersih))}
              </div>
              <div className="card-label">Pendapatan - Pengeluaran</div>
            </div>
          </div>

          {/* Detail Breakdown */}
          <div className="card" style={{ marginTop: 'var(--space-lg)' }}>
            <div className="card-header">
              <span className="card-title">Rincian</span>
            </div>

            {/* Pendapatan */}
            <div style={{ marginBottom: 'var(--space-lg)' }}>
              <h4 style={{ fontSize: 'var(--text-sm)', fontWeight: 600, color: 'var(--color-success)', marginBottom: 'var(--space-sm)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                📈 PENDAPATAN
              </h4>
              <div className="calc-result" style={{ background: 'var(--color-success-bg)', borderColor: 'rgba(46,204,113,0.2)' }}>
                <div className="calc-result-row">
                  <span className="calc-result-label">Penjualan ke Pabrik ({data.jumlahTxPendapatan} pengiriman)</span>
                  <span className="calc-result-value text-success">{formatRupiah(data.totalPendapatan)}</span>
                </div>
              </div>
            </div>

            {/* Pengeluaran */}
            <div>
              <h4 style={{ fontSize: 'var(--text-sm)', fontWeight: 600, color: 'var(--color-danger)', marginBottom: 'var(--space-sm)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                📉 PENGELUARAN
              </h4>
              <div className="calc-result" style={{ background: 'var(--color-danger-bg)', borderColor: 'rgba(231,76,60,0.2)' }}>
                <div className="calc-result-row">
                  <span className="calc-result-label">Pembelian TBS ({data.jumlahTxPembelian} transaksi)</span>
                  <span className="calc-result-value text-danger">{formatRupiah(data.totalPembelian)}</span>
                </div>
                {Object.entries(data.biayaPerKategori).map(([kat, jml]) => (
                  <div key={kat} className="calc-result-row">
                    <span className="calc-result-label">{kategoriLabel[kat] || kat}</span>
                    <span className="calc-result-value text-danger">{formatRupiah(jml)}</span>
                  </div>
                ))}
                <div className="calc-result-row" style={{ fontWeight: 700, borderTop: '2px solid rgba(231,76,60,0.2)', paddingTop: 12 }}>
                  <span className="calc-result-label" style={{ fontWeight: 700 }}>Total Pengeluaran</span>
                  <span className="calc-result-value text-danger">{formatRupiah(data.totalPengeluaran)}</span>
                </div>
              </div>
            </div>

            {/* LABA BERSIH FINAL */}
            <div style={{
              marginTop: 'var(--space-xl)', padding: 'var(--space-lg)',
              background: data.labaBersih >= 0
                ? 'linear-gradient(135deg, rgba(46,204,113,0.1), rgba(46,204,113,0.03))'
                : 'linear-gradient(135deg, rgba(231,76,60,0.1), rgba(231,76,60,0.03))',
              borderRadius: 'var(--radius-lg)',
              border: `1px solid ${data.labaBersih >= 0 ? 'rgba(46,204,113,0.3)' : 'rgba(231,76,60,0.3)'}`,
              textAlign: 'center',
            }}>
              <div style={{ fontSize: 'var(--text-sm)', fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 4 }}>
                {data.labaBersih >= 0 ? '🎉 LABA BERSIH' : '⚠️ RUGI BERSIH'}
              </div>
              <div className="text-mono" style={{
                fontSize: 'var(--text-4xl)', fontWeight: 800,
                color: data.labaBersih >= 0 ? 'var(--color-success)' : 'var(--color-danger)',
              }}>
                {data.labaBersih >= 0 ? '+' : '-'} {formatRupiah(Math.abs(data.labaBersih))}
              </div>
            </div>
          </div>
        </>
      )}
    </AppShell>
  );
}
