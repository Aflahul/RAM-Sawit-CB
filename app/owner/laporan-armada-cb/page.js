'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import AppShell from '@/components/layout/AppShell';
import ConfirmDialog from '@/components/ui/ConfirmDialog';
import PromptDialog from '@/components/ui/PromptDialog';
import { exportToExcel } from '@/lib/export';
import { canApproveCorrections, canManageFinance, canViewProfit, normalizeRole } from '@/lib/roles';
import { supabase } from '@/lib/supabase';
import {
  isDanaOperasionalDibayarMitra,
  resolveBiayaSewaArmada,
  resolveBiayaSewaArmadaKotor,
  resolveDanaOperasionalTrip,
} from '@/lib/transaksi-mitra-calculations';
import { formatDateDisplay, formatRupiah } from '@/lib/utils';
import { Eye, EyeOff, FileSpreadsheet, RefreshCw, RotateCcw, Truck, Weight, WalletCards } from 'lucide-react';

const BULAN = [
  '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

function getPeriodRange(year, month) {
  const monthText = String(month).padStart(2, '0');
  const lastDay = new Date(year, month, 0).getDate();
  return {
    from: `${year}-${monthText}-01`,
    to: `${year}-${monthText}-${String(lastDay).padStart(2, '0')}`,
  };
}

function toNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

export default function LaporanArmadaCBPage() {
  const now = new Date();
  const [bulan, setBulan] = useState(now.getMonth() + 1);
  const [tahun, setTahun] = useState(now.getFullYear());
  const [selectedArmada, setSelectedArmada] = useState('semua');
  const [showTripDetails, setShowTripDetails] = useState(false);
  const [armadas, setArmadas] = useState([]);
  const [transactions, setTransactions] = useState([]);
  const [expenses, setExpenses] = useState([]);
  const [loading, setLoading] = useState(true);
  const [cancelPayTarget, setCancelPayTarget] = useState(null);
  const [cancelingPay, setCancelingPay] = useState(false);
  const [syncConfirm, setSyncConfirm] = useState(false);
  const [syncingRates, setSyncingRates] = useState(false);
  const [toast, setToast] = useState(null);
  const [userRole, setUserRole] = useState(null);

  const period = useMemo(() => getPeriodRange(tahun, bulan), [bulan, tahun]);

  const loadRole = useCallback(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return;
    const { data } = await supabase.from('users').select('role').eq('id', session.user.id).single();
    setUserRole(normalizeRole(data?.role));
  }, []);

  const loadData = useCallback(async () => {
    setLoading(true);

    const canLoadStrategicValues = canViewProfit(userRole);
    const transactionFields = [
      'id', 'tanggal', 'created_at', 'sopir_id', 'mitra_id', 'plat_nomor',
      'sopir_default_nama', 'sopir_aktual_nama',
      'berat_netto_pabrik_kg', 'tonase',
      ...(canLoadStrategicValues ? ['biaya_sewa_armada_total', 'biaya_sewa_armada_kotor'] : []),
      'menggunakan_armada_cb_snapshot', 'kenakan_sewa_armada_cb',
      'catat_dana_operasional_trip', 'armada_cb_perlu_review',
      'dana_operasional_dibayar_mitra',
      'dana_operasional_trip_snapshot', 'total_biaya_sopir_cb_snapshot',
      'biaya_sopir_dibayar_at', 'status',
      'master_mitra ( id, kode, nama, alamat )',
    ].join(', ');

    let transactionQuery = supabase
      .from('transaksi_mitra')
      .select(transactionFields)
      .eq('menggunakan_armada_cb_snapshot', true)
      .eq('status', 'aktif')
      .gte('tanggal', period.from)
      .lte('tanggal', period.to)
      .order('tanggal', { ascending: false })
      .order('created_at', { ascending: false });

    let expenseQuery = null;
    if (canLoadStrategicValues) {
      expenseQuery = supabase
        .from('biaya_operasional')
        .select('id, tanggal, kategori, jumlah, keterangan, armada_sopir_id, transaksi_mitra_id, status')
        .neq('status', 'dibatalkan')
        .not('armada_sopir_id', 'is', null)
        .gte('tanggal', period.from)
        .lte('tanggal', period.to);
    }

    if (selectedArmada !== 'semua') {
      transactionQuery = transactionQuery.eq('sopir_id', selectedArmada);
      if (expenseQuery) expenseQuery = expenseQuery.eq('armada_sopir_id', selectedArmada);
    }

    const [
      { data: armadaData, error: armadaError },
      { data: transactionData, error: transactionError },
      { data: expenseData, error: expenseError },
    ] = await Promise.all([
      supabase
        .from('sopir')
        .select('id, nama, plat_nomor')
        .eq('aktif', true)
        .eq('is_armada_cb', true)
        .order('plat_nomor'),
      transactionQuery,
      expenseQuery || Promise.resolve({ data: [], error: null }),
    ]);

    const error = armadaError || transactionError || expenseError;
    if (error) {
      setToast({ type: 'error', message: `Gagal memuat laporan armada: ${error.message}` });
    }

    setArmadas(armadaData || []);
    setTransactions(transactionData || []);
    setExpenses(expenseData || []);
    setLoading(false);
  }, [period.from, period.to, selectedArmada, userRole]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadRole();
  }, [loadRole]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (userRole && (canManageFinance(userRole) || canViewProfit(userRole))) loadData();
  }, [loadData, userRole]);

  const summary = useMemo(() => {
    const totalTrip = transactions.length;
    const totalMuatan = transactions.reduce((sum, row) => sum + toNumber(row.berat_netto_pabrik_kg ?? row.tonase), 0);
    const totalSewaKotor = transactions.reduce((sum, row) => sum + resolveBiayaSewaArmadaKotor(row), 0);
    const totalSewaBersih = transactions.reduce((sum, row) => sum + resolveBiayaSewaArmada(row), 0);
    const totalDanaTrip = transactions.reduce((sum, row) => sum + resolveDanaOperasionalTrip(row), 0);
    const totalOperasionalLain = expenses
      .filter(row => !['gaji_sopir', 'dana_operasional_trip'].includes(row.kategori))
      .reduce((sum, row) => sum + toNumber(row.jumlah), 0);
    const tripDenganSewa = transactions.filter(row => row.kenakan_sewa_armada_cb).length;
    const tripDenganDana = transactions.filter(row => row.catat_dana_operasional_trip).length;
    const perluReview = transactions.filter(row => row.armada_cb_perlu_review).length;

    return {
      totalTrip,
      totalMuatan,
      totalSewaKotor,
      totalSewaBersih,
      totalDanaTrip,
      totalOperasionalLain,
      tripDenganSewa,
      tripTanpaSewa: totalTrip - tripDenganSewa,
      tripDenganDana,
      tripTanpaDana: totalTrip - tripDenganDana,
      perluReview,
      margin: totalSewaBersih - totalOperasionalLain,
    };
  }, [expenses, transactions]);

  const canCancelPay = canApproveCorrections(userRole);
  const canSeeMargin = canViewProfit(userRole);

  const armadaSummaries = useMemo(() => {
    const rowsByArmada = new Map();
    const visibleArmadas = selectedArmada === 'semua'
      ? armadas
      : armadas.filter(armada => armada.id === selectedArmada);

    visibleArmadas.forEach(armada => {
      rowsByArmada.set(armada.id, {
        id: armada.id,
        platNomor: armada.plat_nomor || '-',
        sopir: armada.nama || '-',
        trip: 0,
        muatan: 0,
        sewaKotor: 0,
        sewaBersih: 0,
        danaTrip: 0,
        biayaLain: 0,
        tripDenganSewa: 0,
        tripDenganDana: 0,
        perluReview: 0,
      });
    });

    transactions.forEach(transaction => {
      const key = transaction.sopir_id;
      if (!key) return;
      const current = rowsByArmada.get(key) || {
        id: key,
        platNomor: transaction.plat_nomor || '-',
        sopir: transaction.sopir_default_nama || transaction.sopir_aktual_nama || '-',
        trip: 0,
        muatan: 0,
        sewaKotor: 0,
        sewaBersih: 0,
        danaTrip: 0,
        biayaLain: 0,
        tripDenganSewa: 0,
        tripDenganDana: 0,
        perluReview: 0,
      };
      const danaTrip = resolveDanaOperasionalTrip(transaction);
      current.trip += 1;
      if (transaction.kenakan_sewa_armada_cb) current.tripDenganSewa += 1;
      if (transaction.catat_dana_operasional_trip) current.tripDenganDana += 1;
      if (transaction.armada_cb_perlu_review) current.perluReview += 1;
      current.muatan += toNumber(transaction.berat_netto_pabrik_kg ?? transaction.tonase);
      current.sewaKotor += resolveBiayaSewaArmadaKotor(transaction);
      current.sewaBersih += resolveBiayaSewaArmada(transaction);
      current.danaTrip += danaTrip;
      rowsByArmada.set(key, current);
    });

    expenses.forEach(expense => {
      if (['gaji_sopir', 'dana_operasional_trip'].includes(expense.kategori)) return;
      const current = rowsByArmada.get(expense.armada_sopir_id);
      if (current) current.biayaLain += toNumber(expense.jumlah);
    });

    return [...rowsByArmada.values()]
      .map(row => ({
        ...row,
        margin: row.sewaBersih - row.biayaLain,
      }))
      .sort((a, b) => b.muatan - a.muatan || b.trip - a.trip || a.platNomor.localeCompare(b.platNomor, 'id'));
  }, [armadas, expenses, selectedArmada, transactions]);

  function showToast(message, type = 'success') {
    setToast({ message, type });
    setTimeout(() => setToast(null), type === 'error' ? 5000 : 3000);
  }

  function showArmadaTripDetails(armadaId) {
    setSelectedArmada(armadaId);
    setShowTripDetails(true);
  }

  async function confirmCancelPay(reason) {
    if (!cancelPayTarget || cancelingPay) return;
    setCancelingPay(true);
    const { error } = await supabase.rpc('cancel_pembayaran_dana_trip', {
      p_transaksi_id: cancelPayTarget.id,
      p_alasan: reason,
    });
    setCancelingPay(false);

    if (error) {
      showToast(`Gagal membatalkan Dana Trip: ${error.message}`, 'error');
      return;
    }

    setCancelPayTarget(null);
    showToast('Pembayaran Dana Trip dibalik dan kas sudah dikembalikan.');
    await loadData();
  }

  async function confirmSyncRates() {
    if (syncingRates) return;
    setSyncingRates(true);
    const { data, error } = await supabase.rpc('sync_tarif_sopir_cb_period', {
      p_date_from: period.from,
      p_date_to: period.to,
      p_armada_sopir_id: selectedArmada === 'semua' ? null : selectedArmada,
    });
    setSyncingRates(false);

    if (error) {
      showToast(`Gagal menerapkan tarif mitra: ${error.message}`, 'error');
      return;
    }

    setSyncConfirm(false);
    showToast(`Dana operasional diterapkan ke ${Number(data?.updated_count || 0)} trip yang belum dibayar.`);
    await loadData();
  }

  function exportReport() {
    const rows = transactions.map(row => ({
      tanggal: row.tanggal,
      plat_nomor: row.plat_nomor,
      sopir: row.sopir_aktual_nama || row.sopir_default_nama,
      mitra: row.master_mitra?.kode || row.master_mitra?.nama || '-',
      berat_netto: toNumber(row.berat_netto_pabrik_kg ?? row.tonase),
      ...(canSeeMargin ? {
        sewa_armada_kotor: resolveBiayaSewaArmadaKotor(row),
        sewa_armada_bersih: resolveBiayaSewaArmada(row),
      } : {}),
      dana_operasional_trip: resolveDanaOperasionalTrip(row),
      sumber_dana_operasional: isDanaOperasionalDibayarMitra(row)
        ? 'Sudah dibayar Mitra sebelum berangkat'
        : row.biaya_sopir_dibayar_at
          ? 'Legacy - pernah dibayar Kas CB'
          : 'Tidak ada Dana Operasional',
      perlu_review: row.armada_cb_perlu_review ? 'Ya' : 'Tidak',
    }));
    const columns = [
      { key: 'tanggal', label: 'Tanggal' },
      { key: 'plat_nomor', label: 'Plat' },
      { key: 'sopir', label: 'Sopir' },
      { key: 'mitra', label: 'Mitra Transaksi' },
      { key: 'berat_netto', label: 'Berat Netto (kg)' },
      ...(canSeeMargin ? [
        { key: 'sewa_armada_kotor', label: 'Sewa Armada Kotor (Rp)' },
        { key: 'sewa_armada_bersih', label: 'Sewa Bersih CB (Rp)' },
      ] : []),
      { key: 'dana_operasional_trip', label: 'Dana Operasional Trip (Rp)' },
      { key: 'sumber_dana_operasional', label: 'Sumber Dana Operasional' },
      { key: 'perlu_review', label: 'Perlu Dicek' },
    ];
    exportToExcel(rows, columns, `Laporan_Armada_CB_${tahun}_${String(bulan).padStart(2, '0')}`, 'Armada CB');
  }

  if (userRole !== null && !canManageFinance(userRole) && !canViewProfit(userRole)) {
    return (
      <AppShell title="Laporan Armada CB" subtitle="Akses terbatas">
        <div className="empty-state"><div className="empty-state-title">Akses Ditolak</div></div>
      </AppShell>
    );
  }

  if (userRole === null) {
    return (
      <AppShell title="Laporan Armada CB">
        <div className="spinner spinner-lg" style={{ margin: '48px auto' }} />
      </AppShell>
    );
  }

  return (
    <AppShell
      title={canSeeMargin ? 'Laporan Armada CB' : 'Rekap Operasional Armada CB'}
      subtitle={canSeeMargin ? 'Sewa kotor, Dana Operasional dari Mitra, dan sewa bersih per armada' : 'Muatan, trip, dan sumber Dana Operasional per armada'}
    >
      {toast && (
        <div className="toast-container"><div className={`toast toast-${toast.type}`}><span>{toast.message}</span></div></div>
      )}

      <div className="page-header">
        <div className="flex gap-sm" style={{ flexWrap: 'wrap' }}>
          <select className="form-input form-select" value={bulan} onChange={e => setBulan(Number(e.target.value))} style={{ width: 150 }}>
            {BULAN.slice(1).map((name, index) => <option key={name} value={index + 1}>{name}</option>)}
          </select>
          <select className="form-input form-select" value={tahun} onChange={e => setTahun(Number(e.target.value))} style={{ width: 110 }}>
            {[tahun - 1, tahun, tahun + 1].filter((value, index, rows) => rows.indexOf(value) === index).map(value => <option key={value}>{value}</option>)}
          </select>
          <select className="form-input form-select" value={selectedArmada} onChange={e => setSelectedArmada(e.target.value)} style={{ minWidth: 220 }}>
            <option value="semua">Semua Armada CB</option>
            {armadas.map(armada => <option key={armada.id} value={armada.id}>{armada.plat_nomor || '-'} - {armada.nama}</option>)}
          </select>
        </div>
        <div className="flex gap-sm" style={{ flexWrap: 'wrap' }}>
          {canSeeMargin && (
            <button className="btn btn-secondary" onClick={() => setSyncConfirm(true)} disabled={transactions.length === 0 || syncingRates}>
              <RefreshCw size={16} /> Terapkan Tarif Mitra
            </button>
          )}
          <button className="btn btn-outline" onClick={exportReport} disabled={transactions.length === 0}>
            <FileSpreadsheet size={16} /> Export Excel
          </button>
        </div>
      </div>

      <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))' }}>
        <div className="card"><div className="card-header"><span className="card-title">Trip</span><Truck size={20} /></div><div className="card-value">{summary.totalTrip}</div><div className="card-label">pengiriman Armada CB</div></div>
        <div className="card"><div className="card-header"><span className="card-title">Muatan</span><Weight size={20} /></div><div className="card-value">{summary.totalMuatan.toLocaleString('id-ID')} kg</div><div className="card-label">berat netto pabrik</div></div>
        {canSeeMargin && <div className="card"><div className="card-header"><span className="card-title">Sewa Kotor</span><WalletCards size={20} /></div><div className="card-value">{formatRupiah(summary.totalSewaKotor)}</div><div className="card-label">netto x tarif sewa Mitra</div></div>}
        <div className="card"><div className="card-header"><span className="card-title">Dana Dibayar Mitra</span></div><div className="card-value text-warning">{formatRupiah(summary.totalDanaTrip)}</div><div className="card-label">diserahkan langsung ke sopir</div></div>
        {canSeeMargin && <div className="card"><div className="card-header"><span className="card-title">Sewa Bersih CB</span></div><div className="card-value text-success">{formatRupiah(summary.totalSewaBersih)}</div><div className="card-label">sewa kotor - Dana Operasional</div></div>}
        {canSeeMargin && (
          <div className="card"><div className="card-header"><span className="card-title">Margin Armada</span></div><div className={`card-value ${summary.margin >= 0 ? 'text-success' : 'text-danger'}`}>{formatRupiah(summary.margin)}</div><div className="card-label">sewa bersih CB - biaya CB lain</div></div>
        )}
      </div>

      {summary.totalTrip > 0 && summary.totalDanaTrip === 0 && (
        <div className="alert alert-warning" style={{ marginTop: 'var(--space-lg)' }}>
          {summary.tripDenganDana > 0
            ? 'Dana Operasional Trip yang dipilih belum memiliki nominal. Atur tarif mitra, lalu terapkan ke trip yang belum dibayar.'
            : 'Semua trip pada periode ini sengaja dicatat tanpa Dana Operasional Trip.'}
        </div>
      )}

      {summary.perluReview > 0 && (
        <div className="alert alert-warning" style={{ marginTop: 'var(--space-lg)' }}>
          <div>
            <strong>{summary.perluReview} trip lama perlu dicek.</strong>
            <div style={{ marginTop: 4 }}>Pastikan apakah sewa perlu dipotong dan Dana Operasional Trip perlu dicatat.</div>
            <Link className="btn btn-outline btn-sm" href="/admin/input-timbangan?status=review_armada_cb" style={{ marginTop: 10 }}>
              Periksa di Pengiriman Mitra
            </Link>
          </div>
        </div>
      )}

      <div style={{ marginTop: 'var(--space-xl)' }}>
        <div className="page-header" style={{ marginBottom: 'var(--space-md)' }}>
          <div>
            <h2 style={{ margin: 0, fontSize: 20 }}>Rekap per Armada</h2>
            <div className="text-tertiary text-sm" style={{ marginTop: 4 }}>Perbandingan semua Armada CB pada periode yang dipilih.</div>
          </div>
        </div>
        <div className="table-container">
          <table className="table">
            <thead>
              <tr>
                <th>Armada / Sopir</th>
                <th style={{ textAlign: 'right' }}>Trip</th>
                <th style={{ textAlign: 'right' }}>Muatan</th>
                {canSeeMargin && <th style={{ textAlign: 'right' }}>Sewa Kotor</th>}
                <th style={{ textAlign: 'right' }}>Dana Dibayar Mitra</th>
                {canSeeMargin && <th style={{ textAlign: 'right' }}>Sewa Bersih CB</th>}
                {canSeeMargin && <th style={{ textAlign: 'right' }}>Biaya Lain</th>}
                {canSeeMargin && <th style={{ textAlign: 'right' }}>Margin</th>}
                {selectedArmada === 'semua' && <th style={{ textAlign: 'center' }}>Aksi</th>}
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={5 + (canSeeMargin ? 3 : 0) + (selectedArmada === 'semua' ? 1 : 0)}>Memuat rekap armada...</td></tr>
              ) : armadaSummaries.length === 0 ? (
                <tr><td colSpan={5 + (canSeeMargin ? 3 : 0) + (selectedArmada === 'semua' ? 1 : 0)}>Belum ada Armada CB aktif.</td></tr>
              ) : armadaSummaries.map(row => (
                <tr key={row.id}>
                  <td><strong className="table-mono">{row.platNomor}</strong><div className="text-tertiary text-xs">{row.sopir}</div></td>
                  <td className="table-mono" style={{ textAlign: 'right' }}>
                    {row.trip.toLocaleString('id-ID')}
                    {(row.tripDenganSewa < row.trip || row.tripDenganDana < row.trip || row.perluReview > 0) && (
                      <div className="text-tertiary text-xs" style={{ marginTop: 3 }}>
                        {row.trip - row.tripDenganSewa} tanpa sewa, {row.trip - row.tripDenganDana} tanpa Dana
                        {row.perluReview > 0 ? `, ${row.perluReview} perlu cek` : ''}
                      </div>
                    )}
                  </td>
                  <td className="table-mono" style={{ textAlign: 'right' }}>{row.muatan.toLocaleString('id-ID')} kg</td>
                  {canSeeMargin && <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(row.sewaKotor)}</td>}
                  <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(row.danaTrip)}</td>
                  {canSeeMargin && <td className="table-mono text-success" style={{ textAlign: 'right' }}>{formatRupiah(row.sewaBersih)}</td>}
                  {canSeeMargin && <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(row.biayaLain)}</td>}
                  {canSeeMargin && <td className={`table-mono ${row.margin >= 0 ? 'text-success' : 'text-danger'}`} style={{ textAlign: 'right', fontWeight: 700 }}>{formatRupiah(row.margin)}</td>}
                  {selectedArmada === 'semua' && <td style={{ textAlign: 'center' }}><button className="btn btn-outline btn-sm" onClick={() => showArmadaTripDetails(row.id)}><Eye size={15} /> Lihat Detail</button></td>}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div style={{ marginTop: 'var(--space-xl)' }}>
        <button className="btn btn-outline" onClick={() => setShowTripDetails(current => !current)} disabled={transactions.length === 0}>
          {showTripDetails ? <EyeOff size={16} /> : <Eye size={16} />}
          {showTripDetails ? 'Sembunyikan Rincian Trip' : 'Tampilkan Rincian Trip'}
        </button>
      </div>

      {showTripDetails && (
        <>
          <div style={{ marginTop: 'var(--space-lg)', marginBottom: 'var(--space-md)' }}>
            <h2 style={{ margin: 0, fontSize: 20 }}>Rincian Trip</h2>
            <div className="text-tertiary text-sm" style={{ marginTop: 4 }}>Dana Operasional pada skema baru sudah dibayar langsung oleh Mitra kepada sopir dan tidak menunggu pembayaran kas CB.</div>
          </div>
          <div className="table-container">
        <table className="table">
          <thead>
            <tr>
              <th>Tanggal</th><th>Armada / Sopir</th><th>Mitra</th>
              <th style={{ textAlign: 'right' }}>Muatan</th>{canSeeMargin && <th style={{ textAlign: 'right' }}>Sewa Kotor</th>}
              <th style={{ textAlign: 'right' }}>Dana Operasional</th>{canSeeMargin && <th style={{ textAlign: 'right' }}>Sewa Bersih CB</th>}<th>Sumber Dana</th><th>Aksi</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={canSeeMargin ? 9 : 7}>Memuat laporan...</td></tr>
            ) : transactions.length === 0 ? (
              <tr><td colSpan={canSeeMargin ? 9 : 7}>Belum ada trip Armada CB pada periode ini.</td></tr>
            ) : transactions.map(row => {
              const driverCost = resolveDanaOperasionalTrip(row);
              const directPaidByMitra = isDanaOperasionalDibayarMitra(row);
              const legacyPaidByCb = Boolean(row.biaya_sopir_dibayar_at) && !directPaidByMitra;
              return (
                <tr key={row.id}>
                  <td>{formatDateDisplay(row.tanggal)}</td>
                  <td><strong className="table-mono">{row.plat_nomor || '-'}</strong><div className="text-tertiary text-xs">{row.sopir_aktual_nama || row.sopir_default_nama || '-'}</div></td>
                  <td>{row.master_mitra?.kode || row.master_mitra?.nama || '-'}</td>
                  <td className="table-mono" style={{ textAlign: 'right' }}>{toNumber(row.berat_netto_pabrik_kg ?? row.tonase).toLocaleString('id-ID')} kg</td>
                  {canSeeMargin && <td className="table-mono" style={{ textAlign: 'right' }}>
                    {formatRupiah(resolveBiayaSewaArmadaKotor(row))}
                    {!row.kenakan_sewa_armada_cb && <div className="text-tertiary text-xs">tanpa potongan sewa</div>}
                  </td>}
                  <td className="table-mono" style={{ textAlign: 'right' }}>
                    {formatRupiah(driverCost)}
                    <div className="text-tertiary text-xs">{row.catat_dana_operasional_trip ? 'dibayar sebelum berangkat' : 'tidak dicatat'}</div>
                  </td>
                  {canSeeMargin && <td className="table-mono text-success" style={{ textAlign: 'right' }}>{formatRupiah(resolveBiayaSewaArmada(row))}</td>}
                  <td>
                    <span className={`badge ${legacyPaidByCb ? 'badge-warning' : row.armada_cb_perlu_review ? 'badge-warning' : driverCost > 0 ? 'badge-success' : 'badge-neutral'}`}>
                      {legacyPaidByCb ? 'Legacy: Kas CB' : row.armada_cb_perlu_review ? 'Perlu Cek' : !row.catat_dana_operasional_trip ? 'Tanpa Dana' : driverCost > 0 ? 'Sudah Dibayar Mitra' : 'Tarif Kosong'}
                    </span>
                  </td>
                  <td>
                    {canCancelPay && legacyPaidByCb && (
                      <button className="btn btn-ghost btn-sm" onClick={() => setCancelPayTarget(row)} title="Batalkan pembayaran Dana Trip">
                        <RotateCcw size={14} /> Batal Bayar
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
          </div>
        </>
      )}

      <PromptDialog
        open={Boolean(cancelPayTarget)}
        title="Batalkan Pembayaran Dana Trip"
        message={cancelPayTarget ? `Kas keluar Dana Trip ${cancelPayTarget.plat_nomor || '-'} tanggal ${formatDateDisplay(cancelPayTarget.tanggal)} akan dibuatkan transaksi balik.` : ''}
        label="Alasan pembatalan"
        placeholder="Contoh: pembayaran dicatat dua kali"
        confirmText="Batalkan Pembayaran"
        loading={cancelingPay}
        onConfirm={confirmCancelPay}
        onCancel={() => !cancelingPay && setCancelPayTarget(null)}
      />
      <ConfirmDialog
        open={syncConfirm}
        title="Terapkan Tarif Mitra"
        message={`Dana Operasional Trip dari tarif mitra akan diterapkan ke trip ${BULAN[bulan]} ${tahun} yang belum dibayar. Trip yang sudah dibayar tidak berubah.`}
        confirmText={syncingRates ? 'Menyinkronkan...' : 'Terapkan Dana Trip'}
        cancelText="Batal"
        variant="info"
        onConfirm={confirmSyncRates}
        onCancel={() => !syncingRates && setSyncConfirm(false)}
      />
    </AppShell>
  );
}
