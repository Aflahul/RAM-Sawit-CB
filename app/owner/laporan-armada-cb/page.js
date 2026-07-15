'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import ConfirmDialog from '@/components/ui/ConfirmDialog';
import { exportToExcel } from '@/lib/export';
import { canManageFinance, canViewProfit, normalizeRole } from '@/lib/roles';
import { supabase } from '@/lib/supabase';
import { formatDateDisplay, formatRupiah, getTodayISO } from '@/lib/utils';
import { Banknote, FileSpreadsheet, RefreshCw, Truck, Weight, WalletCards } from 'lucide-react';

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
  const [armadas, setArmadas] = useState([]);
  const [transactions, setTransactions] = useState([]);
  const [expenses, setExpenses] = useState([]);
  const [loading, setLoading] = useState(true);
  const [paying, setPaying] = useState(false);
  const [payTarget, setPayTarget] = useState(null);
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

    let transactionQuery = supabase
      .from('transaksi_mitra')
      .select(`
        id, tanggal, created_at, sopir_id, mitra_id, plat_nomor,
        sopir_default_nama, sopir_aktual_nama,
        berat_netto_pabrik_kg, tonase,
        biaya_sewa_armada_total, biaya_sewa_armada_kotor,
        upah_sopir_cb_snapshot, uang_jalan_sopir_cb_snapshot,
        total_biaya_sopir_cb_snapshot, tagihan_sopir_ledger_id,
        biaya_sopir_operasional_id, biaya_sopir_dibayar_at,
        status, master_mitra ( id, kode, nama, alamat )
      `)
      .eq('pakai_sewa_armada_bl', true)
      .eq('status', 'aktif')
      .gte('tanggal', period.from)
      .lte('tanggal', period.to)
      .order('tanggal', { ascending: false })
      .order('created_at', { ascending: false });

    let expenseQuery = supabase
      .from('biaya_operasional')
      .select('id, tanggal, kategori, jumlah, keterangan, armada_sopir_id, transaksi_mitra_id, status')
      .neq('status', 'dibatalkan')
      .not('armada_sopir_id', 'is', null)
      .gte('tanggal', period.from)
      .lte('tanggal', period.to);

    if (selectedArmada !== 'semua') {
      transactionQuery = transactionQuery.eq('sopir_id', selectedArmada);
      expenseQuery = expenseQuery.eq('armada_sopir_id', selectedArmada);
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
      expenseQuery,
    ]);

    const error = armadaError || transactionError || expenseError;
    if (error) {
      setToast({ type: 'error', message: `Gagal memuat laporan armada: ${error.message}` });
    }

    setArmadas(armadaData || []);
    setTransactions(transactionData || []);
    setExpenses(expenseData || []);
    setLoading(false);
  }, [period.from, period.to, selectedArmada]);

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
    const totalSewa = transactions.reduce((sum, row) => sum + toNumber(row.biaya_sewa_armada_kotor ?? row.biaya_sewa_armada_total), 0);
    const totalUpah = transactions.reduce((sum, row) => sum + toNumber(row.upah_sopir_cb_snapshot), 0);
    const totalUangJalan = transactions.reduce((sum, row) => sum + toNumber(row.uang_jalan_sopir_cb_snapshot), 0);
    const totalBiayaSopir = totalUpah + totalUangJalan;
    const totalSudahDibayar = transactions
      .filter(row => row.biaya_sopir_dibayar_at)
      .reduce((sum, row) => sum + toNumber(row.total_biaya_sopir_cb_snapshot), 0);
    const totalOperasionalLain = expenses
      .filter(row => row.kategori !== 'gaji_sopir')
      .reduce((sum, row) => sum + toNumber(row.jumlah), 0);

    return {
      totalTrip,
      totalMuatan,
      totalSewa,
      totalUpah,
      totalUangJalan,
      totalBiayaSopir,
      totalSudahDibayar,
      totalBelumDibayar: Math.max(totalBiayaSopir - totalSudahDibayar, 0),
      totalOperasionalLain,
      margin: totalSewa - totalBiayaSopir - totalOperasionalLain,
    };
  }, [expenses, transactions]);

  const canPay = canManageFinance(userRole);
  const canSeeMargin = canViewProfit(userRole);

  function showToast(message, type = 'success') {
    setToast({ message, type });
    setTimeout(() => setToast(null), type === 'error' ? 5000 : 3000);
  }

  async function confirmPay() {
    if (!payTarget || paying) return;
    setPaying(true);
    const { error } = await supabase.rpc('bayar_tagihan_sopir_cb', {
      p_transaksi_mitra_id: payTarget.id,
      p_tanggal_bayar: getTodayISO(),
      p_rekening_kas_id: null,
    });
    setPaying(false);

    if (error) {
      showToast(`Gagal membayar sopir: ${error.message}`, 'error');
      return;
    }

    setPayTarget(null);
    showToast('Pembayaran sopir tercatat di Buku Kas dan Biaya Operasional.');
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
      showToast(`Gagal menerapkan tarif sopir: ${error.message}`, 'error');
      return;
    }

    setSyncConfirm(false);
    showToast(`Tarif diterapkan ke ${Number(data?.updated_count || 0)} trip yang belum dibayar.`);
    await loadData();
  }

  function exportReport() {
    exportToExcel(transactions.map(row => ({
      tanggal: row.tanggal,
      plat_nomor: row.plat_nomor,
      sopir: row.sopir_aktual_nama || row.sopir_default_nama,
      mitra: row.master_mitra?.kode || row.master_mitra?.nama || '-',
      berat_netto: toNumber(row.berat_netto_pabrik_kg ?? row.tonase),
      sewa_armada: toNumber(row.biaya_sewa_armada_kotor ?? row.biaya_sewa_armada_total),
      upah_sopir: toNumber(row.upah_sopir_cb_snapshot),
      uang_jalan: toNumber(row.uang_jalan_sopir_cb_snapshot),
      total_biaya_sopir: toNumber(row.total_biaya_sopir_cb_snapshot),
      status_bayar: row.biaya_sopir_dibayar_at ? 'Sudah Dibayar' : 'Belum Dibayar',
    })), [
      { key: 'tanggal', label: 'Tanggal' },
      { key: 'plat_nomor', label: 'Plat' },
      { key: 'sopir', label: 'Sopir' },
      { key: 'mitra', label: 'Mitra Transaksi' },
      { key: 'berat_netto', label: 'Berat Netto (kg)' },
      { key: 'sewa_armada', label: 'Sewa Armada (Rp)' },
      { key: 'upah_sopir', label: 'Upah Sopir (Rp)' },
      { key: 'uang_jalan', label: 'Uang Jalan (Rp)' },
      { key: 'total_biaya_sopir', label: 'Total Biaya Sopir (Rp)' },
      { key: 'status_bayar', label: 'Status Bayar Sopir' },
    ], `Laporan_Armada_CB_${tahun}_${String(bulan).padStart(2, '0')}`, 'Armada CB');
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
    <AppShell title="Laporan Armada CB" subtitle="Trip, sewa masuk, dan biaya sopir per armada">
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
              <RefreshCw size={16} /> Terapkan Tarif Saat Ini
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
        <div className="card"><div className="card-header"><span className="card-title">Sewa Masuk</span><WalletCards size={20} /></div><div className="card-value text-success">{formatRupiah(summary.totalSewa)}</div><div className="card-label">dibebankan ke mitra</div></div>
        <div className="card"><div className="card-header"><span className="card-title">Belum Bayar Sopir</span><Banknote size={20} /></div><div className="card-value text-warning">{formatRupiah(summary.totalBelumDibayar)}</div><div className="card-label">upah + uang jalan</div></div>
        {canSeeMargin && (
          <div className="card"><div className="card-header"><span className="card-title">Margin Armada</span></div><div className={`card-value ${summary.margin >= 0 ? 'text-success' : 'text-danger'}`}>{formatRupiah(summary.margin)}</div><div className="card-label">sewa - biaya sopir - operasional</div></div>
        )}
      </div>

      {summary.totalTrip > 0 && summary.totalBiayaSopir === 0 && (
        <div className="alert alert-warning" style={{ marginTop: 'var(--space-lg)' }}>
          Tarif sopir belum terisi pada trip periode ini. Atur tarif global atau tarif khusus di menu Armada sebelum mencatat trip berikutnya.
        </div>
      )}

      <div className="table-container" style={{ marginTop: 'var(--space-lg)' }}>
        <table className="table">
          <thead>
            <tr>
              <th>Tanggal</th><th>Armada / Sopir</th><th>Mitra</th>
              <th style={{ textAlign: 'right' }}>Muatan</th><th style={{ textAlign: 'right' }}>Sewa</th>
              <th style={{ textAlign: 'right' }}>Upah + Jalan</th><th>Status Sopir</th><th>Aksi</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={8}>Memuat laporan...</td></tr>
            ) : transactions.length === 0 ? (
              <tr><td colSpan={8}>Belum ada trip Armada CB pada periode ini.</td></tr>
            ) : transactions.map(row => {
              const driverCost = toNumber(row.total_biaya_sopir_cb_snapshot);
              const paid = Boolean(row.biaya_sopir_dibayar_at);
              return (
                <tr key={row.id}>
                  <td>{formatDateDisplay(row.tanggal)}</td>
                  <td><strong className="table-mono">{row.plat_nomor || '-'}</strong><div className="text-tertiary text-xs">{row.sopir_aktual_nama || row.sopir_default_nama || '-'}</div></td>
                  <td>{row.master_mitra?.kode || row.master_mitra?.nama || '-'}</td>
                  <td className="table-mono" style={{ textAlign: 'right' }}>{toNumber(row.berat_netto_pabrik_kg ?? row.tonase).toLocaleString('id-ID')} kg</td>
                  <td className="table-mono text-success" style={{ textAlign: 'right' }}>{formatRupiah(row.biaya_sewa_armada_kotor ?? row.biaya_sewa_armada_total)}</td>
                  <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(driverCost)}<div className="text-tertiary text-xs">{formatRupiah(row.upah_sopir_cb_snapshot)} + {formatRupiah(row.uang_jalan_sopir_cb_snapshot)}</div></td>
                  <td><span className={`badge ${paid ? 'badge-success' : driverCost > 0 ? 'badge-warning' : 'badge-neutral'}`}>{paid ? 'Sudah Dibayar' : driverCost > 0 ? 'Belum Dibayar' : 'Tarif Kosong'}</span></td>
                  <td>{canPay && !paid && driverCost > 0 && <button className="btn btn-primary btn-sm" onClick={() => setPayTarget(row)}>Bayar Tunai</button>}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <ConfirmDialog
        open={!!payTarget}
        title="Bayar Tunai Sopir"
        message={payTarget ? `${payTarget.sopir_aktual_nama || payTarget.sopir_default_nama || 'Sopir'} menerima ${formatRupiah(payTarget.total_biaya_sopir_cb_snapshot)} untuk trip ${payTarget.plat_nomor || '-'} tanggal ${formatDateDisplay(payTarget.tanggal)}. Uang akan dicatat keluar dari Kas Utama.` : ''}
        confirmText={paying ? 'Menyimpan...' : 'Bayar dan Catat Kas'}
        cancelText="Batal"
        variant="warning"
        onConfirm={confirmPay}
        onCancel={() => !paying && setPayTarget(null)}
      />
      <ConfirmDialog
        open={syncConfirm}
        title="Terapkan Tarif Sopir"
        message={`Upah dan uang jalan saat ini akan diterapkan ke trip ${BULAN[bulan]} ${tahun} yang belum dibayar. Trip yang sudah dibayar tidak berubah.`}
        confirmText={syncingRates ? 'Menyinkronkan...' : 'Terapkan Tarif'}
        cancelText="Batal"
        variant="info"
        onConfirm={confirmSyncRates}
        onCancel={() => !syncingRates && setSyncConfirm(false)}
      />
    </AppShell>
  );
}
