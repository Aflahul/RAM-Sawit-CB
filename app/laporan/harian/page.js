'use client';

import { useCallback, useEffect, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, formatNumber, getTodayISO } from '@/lib/utils';
import { exportLaporanHarian } from '@/lib/export';

const kategoriLabel = {
  solar: 'Solar',
  gaji_sopir: 'Gaji Sopir',
  kuli: 'Kuli',
  retribusi: 'Retribusi',
  perawatan: 'Perawatan',
  lainnya: 'Lainnya',
};

function getPengirimanTonase(pengiriman) {
  return pengiriman.tonase_timbang_sumber || pengiriman.tonase_kirim || pengiriman.tonase_pabrik || 0;
}

export default function LaporanHarianPage() {
  const [tanggal, setTanggal] = useState(getTodayISO());
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState(null);

  const loadLaporan = useCallback(async () => {
    setLoading(true);
    const endOfDay = `${tanggal}T23:59:59+08:00`;

    const [
      tbsRes,
      biayaRes,
      pengirimanRes,
      hargaRes,
      stokRes,
    ] = await Promise.all([
      supabase
        .from('transaksi_beli_tbs')
        .select('*, petani:petani_id(nama)')
        .eq('tanggal', tanggal)
        .neq('status', 'dibatalkan')
        .order('created_at'),
      supabase
        .from('biaya_operasional')
        .select('*')
        .eq('tanggal', tanggal)
        .neq('status', 'dibatalkan')
        .order('created_at'),
      supabase
        .from('pengiriman')
        .select('*, pabrik:pabrik_id(nama), sopir:sopir_id(nama)')
        .eq('tanggal', tanggal)
        .order('created_at'),
      supabase
        .from('harga_tbs_lokal')
        .select('*')
        .lte('berlaku_mulai', endOfDay)
        .order('berlaku_mulai', { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from('stok_tbs_lokal_ledger')
        .select('tipe, berat_kg')
        .eq('tanggal', tanggal),
    ]);

    if (tbsRes.error || biayaRes.error || pengirimanRes.error || hargaRes.error || stokRes.error) {
      setToast({ type: 'error', message: 'Sebagian data laporan gagal dimuat.' });
    }

    const tbs = tbsRes.data || [];
    const biaya = biayaRes.data || [];
    const pengiriman = pengirimanRes.data || [];
    const stokRows = stokRes.data || [];

    const totalTBSKg = tbs.reduce((sum, item) => sum + Number(item.berat_bersih_kg || 0), 0);
    const totalTBSRp = tbs.reduce((sum, item) => sum + Number(item.total_harga || 0), 0);
    const totalBayarTunai = tbs.reduce((sum, item) => sum + Number(item.total_bayar_tunai || 0), 0);
    const totalPotongHutang = tbs.reduce((sum, item) => sum + Number(item.potongan_hutang || 0), 0);
    const totalBiaya = biaya.reduce((sum, item) => sum + Number(item.jumlah || 0), 0);
    const stokMasukKg = stokRows
      .filter((item) => item.tipe === 'masuk')
      .reduce((sum, item) => sum + Number(item.berat_kg || 0), 0);
    const stokKeluarKg = stokRows
      .filter((item) => item.tipe === 'keluar')
      .reduce((sum, item) => sum + Math.abs(Number(item.berat_kg || 0)), 0);
    const stokKoreksiKg = stokRows
      .filter((item) => !['masuk', 'keluar'].includes(item.tipe))
      .reduce((sum, item) => sum + Number(item.berat_kg || 0), 0);

    setData({
      tbs,
      biaya,
      pengiriman,
      harga: hargaRes.data?.harga_per_kg || tbs[0]?.harga_per_kg || 0,
      totalTBSKg,
      totalTBSRp,
      totalBayarTunai,
      totalPotongHutang,
      totalBiaya,
      totalKeluar: totalBayarTunai + totalBiaya,
      stokMasukKg,
      stokKeluarKg,
      stokKoreksiKg,
    });
    setLoading(false);
  }, [tanggal]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadLaporan();
  }, [loadLaporan]);

  return (
    <AppShell title="Laporan Harian" subtitle="Rekap operasional per hari">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <h2 className="page-title">Laporan Harian</h2>
        <div className="flex gap-sm items-center">
          <input
            type="date"
            className="form-input"
            style={{ maxWidth: 200 }}
            value={tanggal}
            onChange={(event) => setTanggal(event.target.value)}
          />
          {data && (
            <button className="btn btn-outline btn-sm" onClick={() => exportLaporanHarian(tanggal, data)}>
              Export Excel
            </button>
          )}
        </div>
      </div>

      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          {[1, 2, 3, 4].map((item) => <div key={item} className="skeleton" style={{ height: 80 }} />)}
        </div>
      ) : !data ? null : (
        <>
          <div className="stats-grid">
            <div className="card">
              <div className="card-header">
                <span className="card-title">TBS Lokal Masuk</span>
                <div className="card-icon card-icon-green">TB</div>
              </div>
              <div className="card-value">{formatNumber(data.totalTBSKg)} <span style={{ fontSize: 'var(--text-sm)', fontWeight: 400 }}>kg</span></div>
              <div className="card-label">{data.tbs.length} transaksi / Harga acuan {formatRupiah(data.harga)}/kg</div>
            </div>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Total Pembelian</span>
                <div className="card-icon card-icon-gold">RP</div>
              </div>
              <div className="card-value">{formatRupiah(data.totalTBSRp)}</div>
              <div className="card-label">Tunai {formatRupiah(data.totalBayarTunai)} / Potong hutang {formatRupiah(data.totalPotongHutang)}</div>
            </div>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Stok Lokal Hari Ini</span>
                <div className="card-icon card-icon-blue">ST</div>
              </div>
              <div className="card-value">{formatNumber(data.stokMasukKg - data.stokKeluarKg + data.stokKoreksiKg)} <span style={{ fontSize: 'var(--text-sm)', fontWeight: 400 }}>kg</span></div>
              <div className="card-label">Masuk {formatNumber(data.stokMasukKg)} / Keluar {formatNumber(data.stokKeluarKg)}</div>
            </div>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Total Uang Keluar</span>
                <div className="card-icon card-icon-red">OUT</div>
              </div>
              <div className="card-value" style={{ color: 'var(--color-danger)' }}>{formatRupiah(data.totalKeluar)}</div>
              <div className="card-label">Bayar TBS tunai + biaya operasional</div>
            </div>
          </div>

          <div className="card" style={{ marginBottom: 'var(--space-lg)' }}>
            <div className="card-header">
              <span className="card-title">Detail Pembelian TBS Lokal</span>
            </div>
            {data.tbs.length === 0 ? (
              <div className="text-tertiary text-center" style={{ padding: 'var(--space-lg)' }}>Tidak ada transaksi</div>
            ) : (
              <div className="table-container" style={{ border: 'none' }}>
                <table className="table">
                  <thead>
                    <tr>
                      <th>No Struk</th>
                      <th>Petani</th>
                      <th style={{ textAlign: 'right' }}>Berat</th>
                      <th style={{ textAlign: 'right' }}>Total</th>
                      <th style={{ textAlign: 'right' }}>Pot. Hutang</th>
                      <th style={{ textAlign: 'right' }}>Tunai</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.tbs.map((transaction) => (
                      <tr key={transaction.id}>
                        <td className="table-mono" style={{ fontSize: 'var(--text-xs)' }}>{transaction.no_struk}</td>
                        <td>{transaction.petani?.nama}</td>
                        <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(transaction.berat_bersih_kg)} kg</td>
                        <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(transaction.total_harga)}</td>
                        <td className="table-mono" style={{ textAlign: 'right', color: transaction.potongan_hutang > 0 ? 'var(--color-warning)' : '' }}>
                          {transaction.potongan_hutang > 0 ? formatRupiah(transaction.potongan_hutang) : '-'}
                        </td>
                        <td className="table-mono" style={{ textAlign: 'right', fontWeight: 600 }}>{formatRupiah(transaction.total_bayar_tunai)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

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
                    <tr>
                      <th>Kategori</th>
                      <th>Keterangan</th>
                      <th style={{ textAlign: 'right' }}>Jumlah</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.biaya.map((biaya) => (
                      <tr key={biaya.id}>
                        <td>{kategoriLabel[biaya.kategori] || biaya.kategori}</td>
                        <td>{biaya.keterangan || '-'}</td>
                        <td className="table-mono text-danger" style={{ textAlign: 'right', fontWeight: 600 }}>{formatRupiah(biaya.jumlah)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {data.pengiriman.length > 0 && (
            <div className="card">
              <div className="card-header">
                <span className="card-title">Pengiriman Hari Ini</span>
              </div>
              <div className="table-container" style={{ border: 'none' }}>
                <table className="table">
                  <thead>
                    <tr>
                      <th>Pabrik</th>
                      <th>Sopir</th>
                      <th>Sumber</th>
                      <th style={{ textAlign: 'right' }}>Tonase</th>
                      <th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.pengiriman.map((pengiriman) => (
                      <tr key={pengiriman.id}>
                        <td>{pengiriman.pabrik?.nama}</td>
                        <td>{pengiriman.sopir?.nama || pengiriman.sopir_mitra_text || '-'}</td>
                        <td>{pengiriman.sumber || 'lokal'}</td>
                        <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(getPengirimanTonase(pengiriman))} kg</td>
                        <td>
                          <span className="badge badge-info">{pengiriman.status}</span>
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
