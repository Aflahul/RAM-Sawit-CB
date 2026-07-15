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

    const [
      { data: kasLedger, error: kasLedgerError },
      { data: pembelian, error: pembelianError },
      { data: biaya, error: biayaError },
    ] = await Promise.all([
      supabase
        .from('kas_ledger')
        .select('tipe, sumber, jumlah, status')
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
        .neq('status', 'dibatalkan')
        .gte('tanggal', startDate)
        .lte('tanggal', endDate),
    ]);

    const firstError = kasLedgerError || pembelianError || biayaError;
    if (firstError) {
      setToast({ type: 'error', message: firstError.message });
    }

    const kasRows = kasLedger || [];
    const totalPendapatanKas = kasRows
      .filter((row) => row.sumber === 'pembayaran_pabrik' && ['masuk', 'transfer_masuk'].includes(row.tipe))
      .reduce((sum, row) => sum + Number(row.jumlah || 0), 0);
    const totalPembelianKas = kasRows
      .filter((row) => row.sumber === 'pembelian_tbs' && ['keluar', 'transfer_keluar'].includes(row.tipe))
      .reduce((sum, row) => sum + Number(row.jumlah || 0), 0);
    const totalPembayaranMitraKas = kasRows
      .filter((row) => row.sumber === 'pembayaran_mitra' && ['keluar', 'transfer_keluar'].includes(row.tipe))
      .reduce((sum, row) => sum + Number(row.jumlah || 0), 0);

    const biayaPerKategori = {};
    (biaya || []).forEach((row) => {
      biayaPerKategori[row.kategori] = (biayaPerKategori[row.kategori] || 0) + Number(row.jumlah || 0);
    });
    const totalBiaya = (biaya || []).reduce((sum, row) => sum + Number(row.jumlah || 0), 0);

    const totalPengeluaranKas = totalPembelianKas + totalPembayaranMitraKas + totalBiaya;
    const labaKas = totalPendapatanKas - totalPengeluaranKas;

    setData({
      totalPendapatan: totalPendapatanKas,
      totalPembelian: totalPembelianKas,
      biayaPerKategori,
      totalBiaya,
      totalPengeluaran: totalPengeluaranKas,
      labaBersih: labaKas,
      totalPendapatanKas,
      totalPembelianKas,
      totalPembayaranMitraKas,
      totalPengeluaranKas,
      labaKas,
      jumlahTxPendapatanKas: kasRows.filter((row) => row.sumber === 'pembayaran_pabrik').length,
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
    dana_operasional_trip: 'Dana Operasional Trip Armada CB',
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
            Laba Bersih Kas dihitung dari uang aktual di Buku Kas: pembayaran pabrik yang sudah diterima dikurangi pembayaran mitra, pembelian lokal, dan biaya operasional. Angka ini tidak diinput manual agar tidak bercampur dengan estimasi transaksi.
          </div>

          {data.jumlahTxPendapatanKas === 0 && (
            <div className="alert alert-warning" style={{ marginBottom: 'var(--space-lg)' }}>
              Belum ada mutasi pembayaran pabrik pada periode ini. Laba/Rugi belum bisa menunjukkan laba final sampai uang masuk pabrik dicatat ke Buku Kas atau flow Pembayaran Pabrik.
            </div>
          )}

          <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(3, 1fr)' }}>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Pendapatan Kas</span>
              </div>
              <div className="card-value" style={{ color: 'var(--color-success)' }}>{formatRupiah(data.totalPendapatanKas)}</div>
              <div className="card-label">{data.jumlahTxPendapatanKas} mutasi pembayaran pabrik</div>
            </div>
            <div className="card">
              <div className="card-header">
                <span className="card-title">Pengeluaran Kas</span>
              </div>
              <div className="card-value" style={{ color: 'var(--color-danger)' }}>{formatRupiah(data.totalPengeluaranKas)}</div>
              <div className="card-label">Bayar petani + mitra + biaya</div>
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
              <div className="calc-result-row">
                <span className="calc-result-label">Pembayaran mitra</span>
                <span className="calc-result-value text-danger">{formatRupiah(data.totalPembayaranMitraKas)}</span>
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
          </div>
        </>
      )}
    </AppShell>
  );
}
