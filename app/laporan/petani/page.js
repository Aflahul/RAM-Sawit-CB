'use client';

import { useCallback, useEffect, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, formatNumber } from '@/lib/utils';
import { exportToExcel } from '@/lib/export';

function hitungSaldoLedger(rows = []) {
  return rows.reduce((total, row) => {
    const jumlah = Number(row.jumlah || 0);
    return total + (row.tipe === 'debit' ? jumlah : -jumlah);
  }, 0);
}

function getLedgerLabel(row) {
  const labels = {
    kasbon: 'Kasbon',
    panjar: 'Panjar',
    pupuk: 'Bon Pupuk',
    lainnya: 'Lainnya',
    bayar_tunai: 'Bayar Tunai',
    potong_tbs: 'Potong TBS',
    koreksi: 'Koreksi',
    reversal: 'Reversal',
  };

  return labels[row.sumber] || row.sumber || '-';
}

export default function LaporanPetaniPage() {
  const [petaniList, setPetaniList] = useState([]);
  const [selectedPetani, setSelectedPetani] = useState(null);
  const [detail, setDetail] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [toast, setToast] = useState(null);

  const loadPetani = useCallback(async () => {
    setLoading(true);

    const [{ data: petani }, { data: allTbs, error: tbsError }, { data: allLedger, error: ledgerError }] = await Promise.all([
      supabase.from('petani').select('*').eq('aktif', true).order('nama'),
      supabase
        .from('transaksi_beli_tbs')
        .select('petani_id, berat_bersih_kg, total_harga, status')
        .eq('status', 'aktif'),
      supabase
        .from('hutang_ledger')
        .select('petani_id, tipe, jumlah')
        .eq('pihak_type', 'petani'),
    ]);

    if (tbsError || ledgerError) {
      setToast({ type: 'error', message: tbsError?.message || ledgerError?.message });
    }

    const tbsByPetani = {};
    (allTbs || []).forEach((row) => {
      if (!tbsByPetani[row.petani_id]) tbsByPetani[row.petani_id] = [];
      tbsByPetani[row.petani_id].push(row);
    });

    const ledgerByPetani = {};
    (allLedger || []).forEach((row) => {
      if (!ledgerByPetani[row.petani_id]) ledgerByPetani[row.petani_id] = [];
      ledgerByPetani[row.petani_id].push(row);
    });

    const enriched = (petani || []).map((item) => {
      const tbs = tbsByPetani[item.id] || [];
      const ledger = ledgerByPetani[item.id] || [];

      return {
        ...item,
        totalKg: tbs.reduce((sum, row) => sum + Number(row.berat_bersih_kg || 0), 0),
        totalRp: tbs.reduce((sum, row) => sum + Number(row.total_harga || 0), 0),
        jumlahTransaksi: tbs.length,
        saldoHutang: Math.max(hitungSaldoLedger(ledger), 0),
      };
    });

    setPetaniList(enriched);
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadPetani();
  }, [loadPetani]);

  async function loadDetail(petaniId) {
    setLoadingDetail(true);
    const petani = petaniList.find((item) => item.id === petaniId);
    setSelectedPetani(petani || null);

    const [{ data: tbs, error: tbsError }, { data: ledger, error: ledgerError }] = await Promise.all([
      supabase
        .from('transaksi_beli_tbs')
        .select('*')
        .eq('petani_id', petaniId)
        .eq('status', 'aktif')
        .order('tanggal', { ascending: false })
        .limit(50),
      supabase
        .from('hutang_ledger')
        .select('*')
        .eq('pihak_type', 'petani')
        .eq('petani_id', petaniId)
        .order('created_at', { ascending: false }),
    ]);

    if (tbsError || ledgerError) {
      setToast({ type: 'error', message: tbsError?.message || ledgerError?.message });
    }

    setDetail({ tbs: tbs || [], ledger: ledger || [] });
    setLoadingDetail(false);
  }

  function exportPetaniData() {
    if (!selectedPetani || !detail) return;

    exportToExcel(
      detail.tbs,
      [
        { key: 'tanggal', label: 'Tanggal', format: (value) => new Date(value).toLocaleDateString('id-ID') },
        { key: 'no_struk', label: 'No Struk' },
        { key: 'berat_kotor_kg', label: 'Berat Kotor (kg)' },
        { key: 'potongan_value', label: 'Potongan (%)' },
        { key: 'berat_bersih_kg', label: 'Berat Bersih (kg)' },
        { key: 'harga_per_kg', label: 'Harga /kg' },
        { key: 'total_harga', label: 'Total Harga' },
        { key: 'potongan_hutang', label: 'Potong Hutang' },
        { key: 'total_bayar_tunai', label: 'Bayar Tunai' },
      ],
      `Laporan_${selectedPetani.nama.replace(/\s+/g, '_')}`,
      'Transaksi TBS'
    );
  }

  return (
    <AppShell title="Laporan per Petani" subtitle="Rekap transaksi, pembayaran, dan hutang petani lokal">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <h2 className="page-title">Laporan per Petani</h2>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: selectedPetani ? '300px 1fr' : '1fr', gap: 'var(--space-lg)' }}>
        <div className="card" style={{ maxHeight: selectedPetani ? '80vh' : 'auto', overflow: 'auto' }}>
          <div className="card-header">
            <span className="card-title">Pilih Petani</span>
            <span className="badge badge-neutral">{petaniList.length}</span>
          </div>
          {loading ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[1, 2, 3, 4, 5].map((item) => <div key={item} className="skeleton" style={{ height: 56 }} />)}
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              {petaniList.map((petani) => (
                <div
                  key={petani.id}
                  onClick={() => loadDetail(petani.id)}
                  style={{
                    padding: '10px 12px',
                    borderRadius: 'var(--radius-md)',
                    cursor: 'pointer',
                    background: selectedPetani?.id === petani.id ? 'var(--color-primary-700)' : 'transparent',
                    transition: 'background var(--transition-fast)',
                  }}
                >
                  <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{petani.nama}</div>
                  <div className="flex gap-md" style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)', marginTop: 2 }}>
                    <span>{formatNumber(petani.totalKg)} kg</span>
                    <span>|</span>
                    <span>{petani.jumlahTransaksi} trx</span>
                    {petani.saldoHutang > 0 && (
                      <>
                        <span>|</span>
                        <span style={{ color: 'var(--color-warning)' }}>Hutang: {formatRupiah(petani.saldoHutang)}</span>
                      </>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {selectedPetani && (
          <div>
            <div className="card" style={{ marginBottom: 'var(--space-lg)' }}>
              <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-md)' }}>
                <div>
                  <h3 style={{ fontSize: 'var(--text-xl)', fontWeight: 700 }}>{selectedPetani.nama}</h3>
                  <p className="text-tertiary text-sm">{selectedPetani.no_hp || '-'} | {selectedPetani.alamat || '-'}</p>
                </div>
                <button className="btn btn-outline btn-sm" onClick={exportPetaniData}>Export Excel</button>
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
                {[1, 2, 3].map((item) => <div key={item} className="skeleton" style={{ height: 60 }} />)}
              </div>
            ) : (
              <>
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
                            <th>Tanggal</th>
                            <th>Struk</th>
                            <th style={{ textAlign: 'right' }}>Berat</th>
                            <th style={{ textAlign: 'right' }}>Total</th>
                            <th style={{ textAlign: 'right' }}>Pot. Hutang</th>
                            <th style={{ textAlign: 'right' }}>Tunai</th>
                          </tr>
                        </thead>
                        <tbody>
                          {detail.tbs.map((transaksi) => (
                            <tr key={transaksi.id}>
                              <td>{new Date(transaksi.tanggal).toLocaleDateString('id-ID')}</td>
                              <td className="table-mono" style={{ fontSize: 'var(--text-xs)' }}>{transaksi.no_struk}</td>
                              <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(transaksi.berat_bersih_kg)} kg</td>
                              <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(transaksi.total_harga)}</td>
                              <td className="table-mono" style={{ textAlign: 'right', color: transaksi.potongan_hutang > 0 ? 'var(--color-warning)' : '' }}>
                                {transaksi.potongan_hutang > 0 ? formatRupiah(transaksi.potongan_hutang) : '-'}
                              </td>
                              <td className="table-mono" style={{ textAlign: 'right', fontWeight: 600 }}>{formatRupiah(transaksi.total_bayar_tunai)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )}
                </div>

                {detail?.ledger.length > 0 && (
                  <div className="card">
                    <div className="card-header">
                      <span className="card-title">Riwayat Hutang dan Pembayaran</span>
                    </div>
                    <div className="table-container" style={{ border: 'none' }}>
                      <table className="table">
                        <thead>
                          <tr>
                            <th>Tanggal</th>
                            <th>Keterangan</th>
                            <th style={{ textAlign: 'right' }}>Debit</th>
                            <th style={{ textAlign: 'right' }}>Kredit</th>
                          </tr>
                        </thead>
                        <tbody>
                          {detail.ledger.map((item) => (
                            <tr key={item.id}>
                              <td>{new Date(item.tanggal).toLocaleDateString('id-ID')}</td>
                              <td>
                                <span className={`badge ${item.tipe === 'debit' ? 'badge-danger' : 'badge-success'}`}>
                                  {getLedgerLabel(item)}
                                </span>
                                {' '}{item.keterangan || ''}
                              </td>
                              <td className="table-mono text-danger" style={{ textAlign: 'right' }}>
                                {item.tipe === 'debit' ? formatRupiah(item.jumlah) : ''}
                              </td>
                              <td className="table-mono text-success" style={{ textAlign: 'right' }}>
                                {item.tipe === 'kredit' ? formatRupiah(item.jumlah) : ''}
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
