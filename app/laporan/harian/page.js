'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, formatNumber, getTodayISO } from '@/lib/utils';
import { exportLaporanHarian } from '@/lib/export';

export default function LaporanHarianPage() {
  const [tanggal, setTanggal] = useState(getTodayISO());
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => { loadLaporan(); }, [tanggal]);

  async function loadLaporan() {
    setLoading(true);

    const [{ data: tbs }, { data: biaya }, { data: pengiriman }, { data: harga }] = await Promise.all([
      supabase.from('transaksi_beli').select('*, petani:petani_id(nama)').eq('tanggal', tanggal).order('created_at'),
      supabase.from('biaya_operasional').select('*').eq('tanggal', tanggal).order('created_at'),
      supabase.from('pengiriman').select('*, pabrik:pabrik_id(nama), sopir:sopir_id(nama)').eq('tanggal', tanggal),
      supabase.from('harga_tbs').select('*').eq('tanggal', tanggal).single(),
    ]);

    const totalTBSKg = (tbs || []).reduce((s, t) => s + (t.berat_bersih || 0), 0);
    const totalTBSRp = (tbs || []).reduce((s, t) => s + (t.total_harga || 0), 0);
    const totalBayarTunai = (tbs || []).reduce((s, t) => s + (t.total_bayar_tunai || 0), 0);
    const totalPotongHutang = (tbs || []).reduce((s, t) => s + (t.potongan_hutang || 0), 0);
    const totalBiaya = (biaya || []).reduce((s, b) => s + (b.jumlah || 0), 0);

    setData({
      tbs: tbs || [], biaya: biaya || [], pengiriman: pengiriman || [],
      harga: harga?.harga_per_kg || 0,
      totalTBSKg, totalTBSRp, totalBayarTunai, totalPotongHutang, totalBiaya,
      totalKeluar: totalBayarTunai + totalBiaya,
    });
    setLoading(false);
  }

  const kategoriLabel = {
    solar: '⛽ Solar', gaji_sopir: '👤 Gaji Sopir', kuli: '💪 Kuli',
    retribusi: '📋 Retribusi', perawatan: '🔧 Perawatan', lainnya: '📦 Lainnya',
  };

  return (
    <AppShell title="Laporan Harian" subtitle="Rekap operasional per hari">
      <div className="page-header">
        <h2 className="page-title">📊 Laporan Harian</h2>
        <div className="flex gap-sm items-center">
          <input type="date" className="form-input" style={{ maxWidth: 200 }}
            value={tanggal} onChange={e => setTanggal(e.target.value)} />
          {data && (
            <button className="btn btn-outline btn-sm" onClick={() => exportLaporanHarian(tanggal, data)}>
              📥 Export Excel
            </button>
          )}
        </div>
      </div>

      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          {[1, 2, 3, 4].map(i => <div key={i} className="skeleton" style={{ height: 80 }}></div>)}
        </div>
      ) : !data ? null : (
        <>
          {/* Summary Cards */}
          <div className="stats-grid">
            <div className="card">
              <div className="card-header">
                <span className="card-title">TBS Masuk</span>
                <div className="card-icon card-icon-green">📦</div>
              </div>
              <div className="card-value">{formatNumber(data.totalTBSKg)} <span style={{ fontSize: 'var(--text-sm)', fontWeight: 400 }}>kg</span></div>
              <div className="card-label">{data.tbs.length} transaksi • Harga: {formatRupiah(data.harga)}/kg</div>
            </div>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Total Pembelian</span>
                <div className="card-icon card-icon-gold">💰</div>
              </div>
              <div className="card-value">{formatRupiah(data.totalTBSRp)}</div>
              <div className="card-label">Tunai: {formatRupiah(data.totalBayarTunai)} • Potong Hutang: {formatRupiah(data.totalPotongHutang)}</div>
            </div>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Total Biaya</span>
                <div className="card-icon card-icon-red">🔧</div>
              </div>
              <div className="card-value">{formatRupiah(data.totalBiaya)}</div>
              <div className="card-label">{data.biaya.length} item pengeluaran</div>
            </div>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Total Uang Keluar</span>
                <div className="card-icon card-icon-red">📤</div>
              </div>
              <div className="card-value" style={{ color: 'var(--color-danger)' }}>{formatRupiah(data.totalKeluar)}</div>
              <div className="card-label">Bayar TBS tunai + Biaya Operasional</div>
            </div>
          </div>

          {/* Detail TBS */}
          <div className="card" style={{ marginBottom: 'var(--space-lg)' }}>
            <div className="card-header">
              <span className="card-title">Detail Pembelian TBS</span>
            </div>
            {data.tbs.length === 0 ? (
              <div className="text-tertiary text-center" style={{ padding: 'var(--space-lg)' }}>Tidak ada transaksi</div>
            ) : (
              <div className="table-container" style={{ border: 'none' }}>
                <table className="table">
                  <thead>
                    <tr><th>No Struk</th><th>Petani</th><th style={{ textAlign: 'right' }}>Berat</th><th style={{ textAlign: 'right' }}>Total</th><th style={{ textAlign: 'right' }}>Pot. Hutang</th><th style={{ textAlign: 'right' }}>Tunai</th></tr>
                  </thead>
                  <tbody>
                    {data.tbs.map(t => (
                      <tr key={t.id}>
                        <td className="table-mono" style={{ fontSize: 'var(--text-xs)' }}>{t.no_struk}</td>
                        <td>{t.petani?.nama}</td>
                        <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(t.berat_bersih)} kg</td>
                        <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(t.total_harga)}</td>
                        <td className="table-mono" style={{ textAlign: 'right', color: t.potongan_hutang > 0 ? 'var(--color-warning)' : '' }}>
                          {t.potongan_hutang > 0 ? formatRupiah(t.potongan_hutang) : '-'}
                        </td>
                        <td className="table-mono" style={{ textAlign: 'right', fontWeight: 600 }}>{formatRupiah(t.total_bayar_tunai)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* Detail Biaya */}
          <div className="card" style={{ marginBottom: 'var(--space-lg)' }}>
            <div className="card-header">
              <span className="card-title">Detail Biaya Operasional</span>
            </div>
            {data.biaya.length === 0 ? (
              <div className="text-tertiary text-center" style={{ padding: 'var(--space-lg)' }}>Tidak ada biaya</div>
            ) : (
              <div className="table-container" style={{ border: 'none' }}>
                <table className="table">
                  <thead>
                    <tr><th>Kategori</th><th>Keterangan</th><th style={{ textAlign: 'right' }}>Jumlah</th></tr>
                  </thead>
                  <tbody>
                    {data.biaya.map(b => (
                      <tr key={b.id}>
                        <td>{kategoriLabel[b.kategori] || b.kategori}</td>
                        <td>{b.keterangan || '-'}</td>
                        <td className="table-mono text-danger" style={{ textAlign: 'right', fontWeight: 600 }}>{formatRupiah(b.jumlah)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* Pengiriman */}
          {data.pengiriman.length > 0 && (
            <div className="card">
              <div className="card-header">
                <span className="card-title">Pengiriman Hari Ini</span>
              </div>
              <div className="table-container" style={{ border: 'none' }}>
                <table className="table">
                  <thead>
                    <tr><th>Pabrik</th><th>Sopir</th><th style={{ textAlign: 'right' }}>Tonase</th><th>Status</th></tr>
                  </thead>
                  <tbody>
                    {data.pengiriman.map(p => (
                      <tr key={p.id}>
                        <td>{p.pabrik?.nama}</td>
                        <td>{p.sopir?.nama}</td>
                        <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(p.tonase_kirim)} kg</td>
                        <td>
                          <span className={`badge ${p.status === 'dibayar' ? 'badge-success' : p.status === 'diterima' ? 'badge-warning' : 'badge-info'}`}>
                            {p.status}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </>
      )}
    </AppShell>
  );
}
