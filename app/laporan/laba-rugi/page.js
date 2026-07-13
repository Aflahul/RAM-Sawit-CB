'use client';

import { useCallback, useEffect, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { canViewProfit, normalizeRole } from '@/lib/roles';
import { formatRupiah } from '@/lib/utils';
import { exportLabaRugi } from '@/lib/export';

function getNilaiPabrik(row) {
  return Number(row.total_pembayaran_pabrik ?? row.total_harga_pabrik ?? 0);
}

export default function LabaRugiPage() {
  const [periode, setPeriode] = useState('bulanan');
  const [bulan, setBulan] = useState(new Date().getMonth() + 1);
  const [tahun, setTahun] = useState(new Date().getFullYear());
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [userRole, setUserRole] = useState(null);
  const [toast, setToast] = useState(null);

  const checkRole = useCallback(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (session) {
      const { data: user } = await supabase.from('users').select('role').eq('id', session.user.id).single();
      setUserRole(normalizeRole(user?.role));
    }
  }, []);

  const loadData = useCallback(async () => {
    setLoading(true);

    let startDate;
    let endDate;
    if (periode === 'bulanan') {
      startDate = `${tahun}-${bulan.toString().padStart(2, '0')}-01`;
      const lastDay = new Date(tahun, bulan, 0).getDate();
      endDate = `${tahun}-${bulan.toString().padStart(2, '0')}-${lastDay}`;
    } else {
      startDate = `${tahun}-01-01`;
      endDate = `${tahun}-12-31`;
    }

    const [
      { data: pendapatanKas, error: pendapatanKasError },
      { data: pendapatanTransaksi, error: pendapatanTransaksiError },
      { data: pembelian, error: pembelianError },
      { data: biaya, error: biayaError },
    ] = await Promise.all([
      supabase
        .from('pengiriman')
        .select('sumber, total_pembayaran_pabrik, total_harga_pabrik, tanggal_bayar, status')
        .in('status', ['dibayar', 'dibayar_pabrik', 'selesai'])
        .gte('tanggal_bayar', startDate)
        .lte('tanggal_bayar', endDate),
      supabase
        .from('pengiriman')
        .select('sumber, total_pembayaran_pabrik, total_harga_pabrik, tanggal, status')
        .neq('status', 'dibatalkan')
        .gte('tanggal', startDate)
        .lte('tanggal', endDate),
      supabase
        .from('transaksi_beli_tbs')
        .select('total_harga, total_bayar_tunai')
        .eq('status', 'aktif')
        .gte('tanggal', startDate)
        .lte('tanggal', endDate),
      supabase
        .from('biaya_operasional')
        .select('kategori, jumlah')
        .gte('tanggal', startDate)
        .lte('tanggal', endDate),
    ]);

    const firstError = pendapatanKasError || pendapatanTransaksiError || pembelianError || biayaError;
    if (firstError) {
      setToast({ type: 'error', message: firstError.message });
    }

    const totalPendapatanKas = (pendapatanKas || []).reduce((sum, row) => sum + getNilaiPabrik(row), 0);
    const totalPendapatanTransaksi = (pendapatanTransaksi || []).reduce((sum, row) => sum + getNilaiPabrik(row), 0);

    const totalPembelianKas = (pembelian || []).reduce((sum, row) => sum + Number(row.total_bayar_tunai || 0), 0);
    const totalPembelianTransaksi = (pembelian || []).reduce((sum, row) => sum + Number(row.total_harga || 0), 0);

    const biayaPerKategori = {};
    (biaya || []).forEach((row) => {
      biayaPerKategori[row.kategori] = (biayaPerKategori[row.kategori] || 0) + Number(row.jumlah || 0);
    });
    const totalBiaya = (biaya || []).reduce((sum, row) => sum + Number(row.jumlah || 0), 0);

    const totalPengeluaranKas = totalPembelianKas + totalBiaya;
    const totalPengeluaranTransaksi = totalPembelianTransaksi + totalBiaya;
    const labaKas = totalPendapatanKas - totalPengeluaranKas;
    const labaTransaksi = totalPendapatanTransaksi - totalPengeluaranTransaksi;

    setData({
      totalPendapatan: totalPendapatanKas,
      totalPembelian: totalPembelianKas,
      biayaPerKategori,
      totalBiaya,
      totalPengeluaran: totalPengeluaranKas,
      labaBersih: labaKas,
      totalPendapatanKas,
      totalPendapatanTransaksi,
      totalPembelianKas,
      totalPembelianTransaksi,
      totalPengeluaranKas,
      totalPengeluaranTransaksi,
      labaKas,
      labaTransaksi,
      jumlahTxPendapatanKas: pendapatanKas?.length || 0,
      jumlahTxPendapatanTransaksi: pendapatanTransaksi?.filter((row) => getNilaiPabrik(row) > 0).length || 0,
      jumlahTxPembelian: pembelian?.length || 0,
    });

    setLoading(false);
  }, [bulan, tahun, periode]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    checkRole();
  }, [checkRole]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (canViewProfit(userRole)) loadData();
  }, [loadData, userRole]);

  const kategoriLabel = {
    solar: 'Solar / BBM',
    gaji_sopir: 'Gaji Sopir',
    kuli: 'Kuli Bongkar',
    retribusi: 'Retribusi',
    perawatan: 'Perawatan',
    lainnya: 'Lainnya',
  };

  const bulanNama = [
    '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  if (userRole !== null && !canViewProfit(userRole)) {
    return (
      <AppShell title="Laba / Rugi" subtitle="Akses terbatas">
        <div className="empty-state" style={{ marginTop: 'var(--space-3xl)' }}>
          <div className="empty-state-title">Akses Ditolak</div>
          <div className="empty-state-text">
            Halaman Laba/Rugi hanya dapat diakses oleh Owner dan Super Admin.
          </div>
        </div>
      </AppShell>
    );
  }

  if (userRole === null) {
    return (
      <AppShell title="Laba / Rugi">
        <div style={{ textAlign: 'center', padding: 'var(--space-3xl)' }}>
          <div className="spinner spinner-lg" style={{ margin: '0 auto' }} />
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title="Laba / Rugi" subtitle="Laporan keuangan owner dan super admin">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <div>
          <p className="page-description">
            {periode === 'bulanan' ? `${bulanNama[bulan]} ${tahun}` : `Tahun ${tahun}`}
          </p>
        </div>
        <div className="flex gap-sm items-center" style={{ flexWrap: 'wrap' }}>
          <select className="form-input form-select" value={periode} onChange={(e) => setPeriode(e.target.value)} style={{ width: 140 }}>
            <option value="bulanan">Bulanan</option>
            <option value="tahunan">Tahunan</option>
          </select>
          {periode === 'bulanan' && (
            <select className="form-input form-select" value={bulan} onChange={(e) => setBulan(Number(e.target.value))} style={{ width: 150 }}>
              {bulanNama.slice(1).map((nama, index) => <option key={index + 1} value={index + 1}>{nama}</option>)}
            </select>
          )}
          <select className="form-input form-select" value={tahun} onChange={(e) => setTahun(Number(e.target.value))} style={{ width: 100 }}>
            {[2024, 2025, 2026, 2027].map((item) => <option key={item} value={item}>{item}</option>)}
          </select>
          {data && (
            <button className="btn btn-outline btn-sm" onClick={() => {
              const periodeStr = periode === 'bulanan' ? `${bulanNama[bulan]}_${tahun}` : `Tahun_${tahun}`;
              exportLabaRugi(periodeStr, data);
            }}>
              Export Excel
            </button>
          )}
        </div>
      </div>

      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          {[1, 2, 3].map((item) => <div key={item} className="skeleton" style={{ height: 100 }} />)}
        </div>
      ) : !data ? null : (
        <>
          <div className="alert alert-info" style={{ marginBottom: 'var(--space-lg)' }}>
            Laba Bersih Kas adalah angka utama karena memakai uang yang sudah diterima/dikeluarkan. Laba Estimasi Transaksi memakai transaksi final yang sudah tercatat.
          </div>

          <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(4, 1fr)' }}>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Pendapatan Kas</span>
              </div>
              <div className="card-value" style={{ color: 'var(--color-success)' }}>{formatRupiah(data.totalPendapatanKas)}</div>
              <div className="card-label">{data.jumlahTxPendapatanKas} DO dibayar</div>
            </div>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Pengeluaran Kas</span>
              </div>
              <div className="card-value" style={{ color: 'var(--color-danger)' }}>{formatRupiah(data.totalPengeluaranKas)}</div>
              <div className="card-label">Bayar petani + biaya</div>
            </div>
            <div className="card" style={{ border: data.labaKas >= 0 ? '1px solid rgba(46,204,113,0.3)' : '1px solid rgba(231,76,60,0.3)' }}>
              <div className="card-header">
                <span className="card-title">Laba Bersih Kas</span>
              </div>
              <div className="card-value" style={{ color: data.labaKas >= 0 ? 'var(--color-success)' : 'var(--color-danger)' }}>
                {formatRupiah(data.labaKas)}
              </div>
              <div className="card-label">Angka utama owner</div>
            </div>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Estimasi Transaksi</span>
              </div>
              <div className="card-value" style={{ color: data.labaTransaksi >= 0 ? 'var(--color-success)' : 'var(--color-danger)' }}>
                {formatRupiah(data.labaTransaksi)}
              </div>
              <div className="card-label">{data.jumlahTxPendapatanTransaksi} DO bernilai final</div>
            </div>
          </div>

          <div className="card" style={{ marginTop: 'var(--space-lg)' }}>
            <div className="card-header">
              <span className="card-title">Rincian Basis Kas</span>
            </div>
            <div className="calc-result" style={{ marginBottom: 'var(--space-lg)' }}>
              <div className="calc-result-row">
                <span className="calc-result-label">Pendapatan pabrik diterima</span>
                <span className="calc-result-value text-success">{formatRupiah(data.totalPendapatanKas)}</span>
              </div>
              <div className="calc-result-row">
                <span className="calc-result-label">Pembayaran tunai TBS petani</span>
                <span className="calc-result-value text-danger">{formatRupiah(data.totalPembelianKas)}</span>
              </div>
              {Object.entries(data.biayaPerKategori).map(([kategori, jumlah]) => (
                <div key={kategori} className="calc-result-row">
                  <span className="calc-result-label">{kategoriLabel[kategori] || kategori}</span>
                  <span className="calc-result-value text-danger">{formatRupiah(jumlah)}</span>
                </div>
              ))}
              <div className="calc-result-row" style={{ fontWeight: 700, borderTop: '2px solid rgba(255,255,255,0.08)', paddingTop: 12 }}>
                <span className="calc-result-label" style={{ fontWeight: 700 }}>Laba Bersih Kas</span>
                <span className={data.labaKas >= 0 ? 'calc-result-value text-success' : 'calc-result-value text-danger'}>
                  {formatRupiah(data.labaKas)}
                </span>
              </div>
            </div>

            <div className="card-header" style={{ paddingLeft: 0, paddingRight: 0 }}>
              <span className="card-title">Rincian Basis Transaksi</span>
            </div>
            <div className="calc-result">
              <div className="calc-result-row">
                <span className="calc-result-label">Nilai DO/pengiriman final</span>
                <span className="calc-result-value text-success">{formatRupiah(data.totalPendapatanTransaksi)}</span>
              </div>
              <div className="calc-result-row">
                <span className="calc-result-label">Nilai pembelian TBS lokal</span>
                <span className="calc-result-value text-danger">{formatRupiah(data.totalPembelianTransaksi)}</span>
              </div>
              <div className="calc-result-row">
                <span className="calc-result-label">Biaya operasional tercatat</span>
                <span className="calc-result-value text-danger">{formatRupiah(data.totalBiaya)}</span>
              </div>
              <div className="calc-result-row" style={{ fontWeight: 700, borderTop: '2px solid rgba(255,255,255,0.08)', paddingTop: 12 }}>
                <span className="calc-result-label" style={{ fontWeight: 700 }}>Laba Estimasi Transaksi</span>
                <span className={data.labaTransaksi >= 0 ? 'calc-result-value text-success' : 'calc-result-value text-danger'}>
                  {formatRupiah(data.labaTransaksi)}
                </span>
              </div>
            </div>
          </div>
        </>
      )}
    </AppShell>
  );
}
