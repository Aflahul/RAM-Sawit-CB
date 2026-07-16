'use client';

import { useCallback, useEffect, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { canViewProfit, normalizeRole } from '@/lib/roles';
import { formatRupiah } from '@/lib/utils';
import { exportLabaRugi } from '@/lib/export';

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

    const { data: kasLedger, error: kasLedgerError } = await supabase
        .from('kas_ledger')
        .select('tipe, sumber, jumlah, status')
        .neq('status', 'dibatalkan')
        .gte('tanggal', startDate)
        .lte('tanggal', endDate);

    const firstError = kasLedgerError;
    if (firstError) {
      setToast({ type: 'error', message: firstError.message });
    }

    const kasRows = kasLedger || [];
    const kasMasukRows = kasRows.filter((row) => ['masuk', 'transfer_masuk'].includes(row.tipe));
    const kasKeluarRows = kasRows.filter((row) => ['keluar', 'transfer_keluar'].includes(row.tipe));
    const totalPendapatanKas = kasMasukRows
      .reduce((sum, row) => sum + Number(row.jumlah || 0), 0);
    const totalPembelianKas = kasKeluarRows
      .filter((row) => row.sumber === 'pembelian_tbs')
      .reduce((sum, row) => sum + Number(row.jumlah || 0), 0);
    const totalPembayaranMitraKas = kasKeluarRows
      .filter((row) => row.sumber === 'pembayaran_mitra')
      .reduce((sum, row) => sum + Number(row.jumlah || 0), 0);

    const pengeluaranPerSumber = {};
    kasKeluarRows.forEach((row) => {
      pengeluaranPerSumber[row.sumber] = (pengeluaranPerSumber[row.sumber] || 0) + Number(row.jumlah || 0);
    });
    const totalPengeluaranKas = kasKeluarRows.reduce((sum, row) => sum + Number(row.jumlah || 0), 0);
    const labaKas = totalPendapatanKas - totalPengeluaranKas;

    setData({
      totalPendapatan: totalPendapatanKas,
      totalPembelian: totalPembelianKas,
      biayaPerKategori: pengeluaranPerSumber,
      totalBiaya: totalPengeluaranKas,
      totalPengeluaran: totalPengeluaranKas,
      labaBersih: labaKas,
      totalPendapatanKas,
      totalPembelianKas,
      totalPembayaranMitraKas,
      totalPengeluaranKas,
      labaKas,
      jumlahTxPendapatanKas: kasMasukRows.length,
      jumlahTxPembelian: kasKeluarRows.length,
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
    dana_operasional_trip: 'Dana Operasional Trip Armada CB',
    kuli: 'Kuli Bongkar',
    retribusi: 'Retribusi',
    perawatan: 'Perawatan',
    lainnya: 'Lainnya',
    pembayaran_pabrik: 'Pembayaran dari Pabrik',
    pembayaran_mitra: 'Pembayaran Mitra',
    pembelian_tbs: 'Pembelian TBS',
    biaya_operasional: 'Biaya Operasional',
    panjar_mitra: 'Panjar Mitra',
    hutang_pencairan: 'Pemberian Pinjaman',
    hutang_pelunasan: 'Pengembalian Pinjaman',
    reversal: 'Pembalikan Transaksi',
  };

  const bulanNama = [
    '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  if (userRole !== null && !canViewProfit(userRole)) {
    return (
      <AppShell title="Ringkasan Arus Kas" subtitle="Akses terbatas">
        <div className="empty-state" style={{ marginTop: 'var(--space-3xl)' }}>
          <div className="empty-state-title">Akses Ditolak</div>
          <div className="empty-state-text">
            Ringkasan Arus Kas hanya dapat diakses oleh Owner dan Super Admin.
          </div>
        </div>
      </AppShell>
    );
  }

  if (userRole === null) {
    return (
      <AppShell title="Ringkasan Arus Kas">
        <div style={{ textAlign: 'center', padding: 'var(--space-3xl)' }}>
          <div className="spinner spinner-lg" style={{ margin: '0 auto' }} />
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title="Ringkasan Arus Kas" subtitle="Uang masuk dan keluar yang sudah tercatat">
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
            {Array.from({ length: 5 }, (_, index) => new Date().getFullYear() - 2 + index).map((item) => <option key={item} value={item}>{item}</option>)}
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
            Ringkasan ini memakai uang aktual di Buku Kas. Angka surplus belum sama dengan laba akuntansi karena belum menghitung persediaan, kewajiban yang belum dibayar, dan penyusutan aset.
          </div>

          {data.jumlahTxPendapatanKas === 0 && (
            <div className="alert alert-warning" style={{ marginBottom: 'var(--space-lg)' }}>
              Belum ada kas masuk pada periode ini. Catat pembayaran pabrik agar ringkasan arus kas dapat dipantau.
            </div>
          )}

          <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(3, 1fr)' }}>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Kas Masuk</span>
              </div>
              <div className="card-value" style={{ color: 'var(--color-success)' }}>{formatRupiah(data.totalPendapatanKas)}</div>
              <div className="card-label">{data.jumlahTxPendapatanKas} mutasi masuk</div>
            </div>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Kas Keluar</span>
              </div>
              <div className="card-value" style={{ color: 'var(--color-danger)' }}>{formatRupiah(data.totalPengeluaranKas)}</div>
              <div className="card-label">Semua mutasi keluar</div>
            </div>
            <div className="card" style={{ border: data.labaKas >= 0 ? '1px solid rgba(46,204,113,0.3)' : '1px solid rgba(231,76,60,0.3)' }}>
              <div className="card-header">
                <span className="card-title">Surplus / Defisit Kas</span>
              </div>
              <div className="card-value" style={{ color: data.labaKas >= 0 ? 'var(--color-success)' : 'var(--color-danger)' }}>
                {formatRupiah(data.labaKas)}
              </div>
              <div className="card-label">Kas masuk dikurangi kas keluar</div>
            </div>
          </div>

          <div className="card" style={{ marginTop: 'var(--space-lg)' }}>
            <div className="card-header">
              <span className="card-title">Rincian Basis Kas</span>
            </div>
            <div className="calc-result" style={{ marginBottom: 'var(--space-lg)' }}>
              <div className="calc-result-row">
                <span className="calc-result-label">Total kas masuk</span>
                <span className="calc-result-value text-success">{formatRupiah(data.totalPendapatanKas)}</span>
              </div>
              <div className="calc-result-row">
                <span className="calc-result-label">Pembayaran tunai TBS petani</span>
                <span className="calc-result-value text-danger">{formatRupiah(data.totalPembelianKas)}</span>
              </div>
              <div className="calc-result-row">
                <span className="calc-result-label">Pembayaran mitra</span>
                <span className="calc-result-value text-danger">{formatRupiah(data.totalPembayaranMitraKas)}</span>
              </div>
              {Object.entries(data.biayaPerKategori).filter(([kategori]) => !['pembelian_tbs', 'pembayaran_mitra'].includes(kategori)).map(([kategori, jumlah]) => (
                <div key={kategori} className="calc-result-row">
                  <span className="calc-result-label">{kategoriLabel[kategori] || kategori}</span>
                  <span className="calc-result-value text-danger">{formatRupiah(jumlah)}</span>
                </div>
              ))}
              <div className="calc-result-row" style={{ fontWeight: 700, borderTop: '2px solid rgba(255,255,255,0.08)', paddingTop: 12 }}>
                <span className="calc-result-label" style={{ fontWeight: 700 }}>Surplus / Defisit Kas</span>
                <span className={data.labaKas >= 0 ? 'calc-result-value text-success' : 'calc-result-value text-danger'}>
                  {formatRupiah(data.labaKas)}
                </span>
              </div>
            </div>
          </div>
        </>
      )}
    </AppShell>
  );
}
