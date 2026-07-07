'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, formatNumber } from '@/lib/utils';
import { exportToExcel } from '@/lib/export';

export default function LaporanPetaniPage() {
  const [petaniList, setPetaniList] = useState([]);
  const [selectedPetani, setSelectedPetani] = useState(null);
  const [detail, setDetail] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadingDetail, setLoadingDetail] = useState(false);

  useEffect(() => { loadPetani(); }, []);

  async function loadPetani() {
    setLoading(true);
    const { data: petani } = await supabase.from('petani').select('*').eq('aktif', true).order('nama');

    // Load summary for all petani
    const { data: allTbs } = await supabase.from('transaksi_beli').select('petani_id, berat_bersih, total_harga');
    const { data: allHutang } = await supabase.from('hutang').select('petani_id, jumlah');
    const { data: allLogs } = await supabase.from('hutang_log').select('petani_id, jumlah_bayar');

    const enriched = (petani || []).map(p => {
      const tbs = (allTbs || []).filter(t => t.petani_id === p.id);
      const hutang = (allHutang || []).filter(h => h.petani_id === p.id);
      const logs = (allLogs || []).filter(l => l.petani_id === p.id);

      const totalKg = tbs.reduce((s, t) => s + (t.berat_bersih || 0), 0);
      const totalRp = tbs.reduce((s, t) => s + (t.total_harga || 0), 0);
      const totalHutang = hutang.reduce((s, h) => s + (h.jumlah || 0), 0);
      const totalBayar = logs.reduce((s, l) => s + (l.jumlah_bayar || 0), 0);

      return {
        ...p,
        totalKg, totalRp, jumlahTransaksi: tbs.length,
        saldoHutang: totalHutang - totalBayar,
      };
    });

    setPetaniList(enriched);
    setLoading(false);
  }

  async function loadDetail(petaniId) {
    setLoadingDetail(true);
    const petani = petaniList.find(p => p.id === petaniId);
    setSelectedPetani(petani);

    const [{ data: tbs }, { data: hutang }, { data: logs }] = await Promise.all([
      supabase.from('transaksi_beli').select('*').eq('petani_id', petaniId).order('tanggal', { ascending: false }).limit(50),
      supabase.from('hutang').select('*').eq('petani_id', petaniId).order('tanggal', { ascending: false }),
      supabase.from('hutang_log').select('*').eq('petani_id', petaniId).order('tanggal', { ascending: false }),
    ]);

    setDetail({ tbs: tbs || [], hutang: hutang || [], logs: logs || [] });
    setLoadingDetail(false);
  }

  function exportPetaniData() {
    if (!selectedPetani || !detail) return;
    exportToExcel(
      detail.tbs,
      [
        { key: 'tanggal', label: 'Tanggal', format: v => new Date(v).toLocaleDateString('id-ID') },
        { key: 'no_struk', label: 'No Struk' },
        { key: 'berat_kotor', label: 'Berat Kotor (kg)' },
        { key: 'persen_potongan', label: 'Potongan (%)' },
        { key: 'berat_bersih', label: 'Berat Bersih (kg)' },
        { key: 'harga_per_kg', label: 'Harga /kg' },
        { key: 'total_harga', label: 'Total Harga' },
        { key: 'potongan_hutang', label: 'Potong Hutang' },
        { key: 'total_bayar_tunai', label: 'Bayar Tunai' },
      ],
      `Laporan_${selectedPetani.nama.replace(/\s+/g, '_')}`,
      'Transaksi TBS'
    );
  }

  const jenisLabel = { kasbon: 'Kasbon', panjar: 'Panjar', pupuk: 'Bon Pupuk', lainnya: 'Lainnya' };

  return (
    <AppShell title="Laporan per Petani" subtitle="Rekap data per mitra">
      <div className="page-header">
        <h2 className="page-title">👤 Laporan per Petani</h2>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: selectedPetani ? '300px 1fr' : '1fr', gap: 'var(--space-lg)' }}>
        {/* Daftar Petani */}
        <div className="card" style={{ maxHeight: selectedPetani ? '80vh' : 'auto', overflow: 'auto' }}>
          <div className="card-header">
            <span className="card-title">Pilih Petani</span>
            <span className="badge badge-neutral">{petaniList.length}</span>
          </div>
          {loading ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[1, 2, 3, 4, 5].map(i => <div key={i} className="skeleton" style={{ height: 56 }}></div>)}
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              {petaniList.map(p => (
                <div
                  key={p.id}
                  onClick={() => loadDetail(p.id)}
                  style={{
                    padding: '10px 12px', borderRadius: 'var(--radius-md)', cursor: 'pointer',
                    background: selectedPetani?.id === p.id ? 'var(--color-primary-700)' : 'transparent',
                    transition: 'background var(--transition-fast)',
                  }}
                >
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{p.nama}</div>
                  <div className="flex gap-md" style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)', marginTop: 2 }}>
                    <span>{formatNumber(p.totalKg)} kg</span>
                    <span>•</span>
                    <span>{p.jumlahTransaksi} trx</span>
                    {p.saldoHutang > 0 && (
                      <>
                        <span>•</span>
                        <span style={{ color: 'var(--color-warning)' }}>Hutang: {formatRupiah(p.saldoHutang)}</span>
                      </>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Detail Petani */}
        {selectedPetani && (
          <div>
            {/* Header Info */}
            <div className="card" style={{ marginBottom: 'var(--space-lg)' }}>
              <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-md)' }}>
                <div>
                  <h3 style={{ fontSize: 'var(--text-xl)', fontWeight: 700 }}>{selectedPetani.nama}</h3>
                  <p className="text-tertiary text-sm">{selectedPetani.no_hp || '-'} • {selectedPetani.alamat || '-'}</p>
                </div>
                <button className="btn btn-outline btn-sm" onClick={exportPetaniData}>📥 Export Excel</button>
              </div>

              <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))' }}>
                <div style={{ textAlign: 'center', padding: 'var(--space-md)', background: 'var(--bg-surface)', borderRadius: 'var(--radius-md)' }}>
                  <div className="text-mono" style={{ fontSize: 'var(--text-xl)', fontWeight: 700, color: 'var(--color-primary-400)' }}>
                    {formatNumber(selectedPetani.totalKg)}
                  </div>
                  <div className="text-tertiary text-xs">Total kg</div>
                </div>
                <div style={{ textAlign: 'center', padding: 'var(--space-md)', background: 'var(--bg-surface)', borderRadius: 'var(--radius-md)' }}>
                  <div className="text-mono" style={{ fontSize: 'var(--text-xl)', fontWeight: 700, color: 'var(--color-success)' }}>
                    {formatRupiah(selectedPetani.totalRp)}
                  </div>
                  <div className="text-tertiary text-xs">Total Pembelian</div>
                </div>
                <div style={{ textAlign: 'center', padding: 'var(--space-md)', background: 'var(--bg-surface)', borderRadius: 'var(--radius-md)' }}>
                  <div className="text-mono" style={{ fontSize: 'var(--text-xl)', fontWeight: 700 }}>
                    {selectedPetani.jumlahTransaksi}
                  </div>
                  <div className="text-tertiary text-xs">Transaksi</div>
                </div>
                <div style={{ textAlign: 'center', padding: 'var(--space-md)', background: 'var(--bg-surface)', borderRadius: 'var(--radius-md)' }}>
                  <div className="text-mono" style={{ fontSize: 'var(--text-xl)', fontWeight: 700, color: selectedPetani.saldoHutang > 0 ? 'var(--color-warning)' : 'var(--color-success)' }}>
                    {formatRupiah(selectedPetani.saldoHutang)}
                  </div>
                  <div className="text-tertiary text-xs">Saldo Hutang</div>
                </div>
              </div>
            </div>

            {loadingDetail ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                {[1, 2, 3].map(i => <div key={i} className="skeleton" style={{ height: 60 }}></div>)}
              </div>
            ) : (
              <>
                {/* Riwayat Transaksi TBS */}
                <div className="card" style={{ marginBottom: 'var(--space-lg)' }}>
                  <div className="card-header">
                    <span className="card-title">Riwayat Pembelian TBS ({detail?.tbs.length || 0})</span>
                  </div>
                  {detail?.tbs.length === 0 ? (
                    <div className="text-tertiary text-center" style={{ padding: 'var(--space-lg)' }}>Belum ada transaksi</div>
                  ) : (
                    <div className="table-container" style={{ border: 'none' }}>
                      <table className="table">
                        <thead>
                          <tr>
                            <th>Tanggal</th><th>Struk</th>
                            <th style={{ textAlign: 'right' }}>Berat</th>
                            <th style={{ textAlign: 'right' }}>Total</th>
                            <th style={{ textAlign: 'right' }}>Pot. Hutang</th>
                            <th style={{ textAlign: 'right' }}>Tunai</th>
                          </tr>
                        </thead>
                        <tbody>
                          {detail.tbs.map(t => (
                            <tr key={t.id}>
                              <td>{new Date(t.tanggal).toLocaleDateString('id-ID')}</td>
                              <td className="table-mono" style={{ fontSize: 'var(--text-xs)' }}>{t.no_struk}</td>
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

                {/* Riwayat Hutang */}
                {(detail?.hutang.length > 0 || detail?.logs.length > 0) && (
                  <div className="card">
                    <div className="card-header">
                      <span className="card-title">Riwayat Hutang & Pembayaran</span>
                    </div>
                    <div className="table-container" style={{ border: 'none' }}>
                      <table className="table">
                        <thead>
                          <tr><th>Tanggal</th><th>Keterangan</th><th style={{ textAlign: 'right' }}>Debit</th><th style={{ textAlign: 'right' }}>Kredit</th></tr>
                        </thead>
                        <tbody>
                          {[
                            ...(detail?.hutang || []).map(h => ({ ...h, _type: 'hutang', _date: h.tanggal, _sort: new Date(h.created_at) })),
                            ...(detail?.logs || []).map(l => ({ ...l, _type: 'bayar', _date: l.tanggal, _sort: new Date(l.created_at) })),
                          ].sort((a, b) => b._sort - a._sort).map((item, i) => (
                            <tr key={i}>
                              <td>{new Date(item._date).toLocaleDateString('id-ID')}</td>
                              <td>
                                {item._type === 'hutang'
                                  ? <span className="badge badge-danger">{jenisLabel[item.jenis] || item.jenis}</span>
                                  : <span className="badge badge-success">{item.sumber === 'potong_tbs' ? 'Potong TBS' : 'Bayar Tunai'}</span>
                                }
                                {' '}{item.keterangan || ''}
                              </td>
                              <td className="table-mono text-danger" style={{ textAlign: 'right' }}>
                                {item._type === 'hutang' ? formatRupiah(item.jumlah) : ''}
                              </td>
                              <td className="table-mono text-success" style={{ textAlign: 'right' }}>
                                {item._type === 'bayar' ? formatRupiah(item.jumlah_bayar) : ''}
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
          </div>
        )}
      </div>
    </AppShell>
  );
}
