'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import AppShell from '@/components/layout/AppShell';
import PromptDialog from '@/components/ui/PromptDialog';
import { canManageFinance, normalizeRole } from '@/lib/roles';
import { supabase } from '@/lib/supabase';
import { resolveBeratDibayar, resolveHargaPabrikPerKg, toNumber } from '@/lib/transaksi-mitra-calculations';
import { formatDateDisplay, formatNumber, formatRupiah, formatWaktu, getTodayISO } from '@/lib/utils';
import { AlertTriangle, BadgeDollarSign, CalendarDays, CheckCircle2, RotateCcw, Scale, Search } from 'lucide-react';

function getMitraLabel(mitra) {
  if (!mitra) return 'Tanpa mitra';
  return [mitra.kode, mitra.alamat || mitra.nama].filter(Boolean).join(' - ') || mitra.nama || 'Tanpa mitra';
}

function getTransactionSearchText(row) {
  return [
    row.tanggal,
    getMitraLabel(row.master_mitra),
    row.sopir_aktual_nama,
    row.sopir_default_nama,
    row.plat_nomor,
  ].filter(Boolean).join(' ').toLowerCase();
}

function getOffsetDateISO(offsetDays) {
  const date = new Date(`${getTodayISO()}T00:00:00`);
  date.setDate(date.getDate() + offsetDays);
  return date.toISOString().split('T')[0];
}

const emptyForm = {
  pabrik_id: '',
  tanggal_bayar: getTodayISO(),
  metode_bayar: 'transfer',
  rekening_kas_id: '',
  nomor_bukti: '',
  tonase_pabrik: '',
  harga_pabrik_per_kg: '',
  nominal_diterima: '',
  catatan: '',
};

export default function PembayaranPabrikPage() {
  const [userRole, setUserRole] = useState(null);
  const [accounts, setAccounts] = useState([]);
  const [pabriks, setPabriks] = useState([]);
  const [hargaTwb, setHargaTwb] = useState(0);
  const [transactions, setTransactions] = useState([]);
  const [payments, setPayments] = useState([]);
  const [selectedIds, setSelectedIds] = useState([]);
  const [form, setForm] = useState(emptyForm);
  const [filters, setFilters] = useState({ dateFrom: getTodayISO(), dateTo: getTodayISO(), search: '' });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [canceling, setCanceling] = useState(false);
  const [cancelTarget, setCancelTarget] = useState(null);
  const [toast, setToast] = useState(null);

  const loadRole = useCallback(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
      setUserRole('admin_operasional');
      return;
    }

    const { data: user } = await supabase
      .from('users')
      .select('role')
      .eq('id', session.user.id)
      .maybeSingle();

    setUserRole(normalizeRole(user?.role));
  }, []);

  const loadData = useCallback(async () => {
    setLoading(true);

    let trxQuery = supabase
      .from('transaksi_mitra')
      .select(`
        id, mitra_id, tanggal, tonase, berat_netto_pabrik_kg, potongan_pabrik_kg, berat_dibayar_kg,
        harga_harian, total_kotor, created_at,
        harga_pabrik_per_kg, total_nilai_bersih, total_fee_owner,
        sopir_aktual_nama, sopir_default_nama, plat_nomor, status, pembayaran_pabrik_status,
        master_mitra ( id, kode, nama, alamat, tipe_mitra, fee_per_kg )
      `)
      .neq('status', 'dibatalkan')
      .eq('pembayaran_pabrik_status', 'belum_dibayar')
      .order('tanggal', { ascending: false })
      .order('created_at', { ascending: false })
      .limit(500);

    if (filters.dateFrom) trxQuery = trxQuery.gte('tanggal', filters.dateFrom);
    if (filters.dateTo) trxQuery = trxQuery.lte('tanggal', filters.dateTo);

    const [
      { data: accountData, error: accountError },
      { data: pabrikData, error: pabrikError },
      { data: hargaData, error: hargaError },
      { data: trxData, error: trxError },
      { data: paymentData, error: paymentError },
    ] = await Promise.all([
      supabase.from('rekening_kas').select('id, nama, tipe, is_default').eq('aktif', true).order('is_default', { ascending: false }).order('nama'),
      supabase.from('pabrik').select('id, nama').eq('aktif', true).order('nama'),
      supabase.from('harga_tbs').select('harga_per_kg').order('tanggal', { ascending: false }).limit(1).maybeSingle(),
      trxQuery,
      supabase
        .from('pembayaran_pabrik_batch')
        .select(`
          id, pabrik_id, tanggal_bayar, metode_bayar, nomor_bukti, status,
          total_tonase, total_tonase_sistem, selisih_tonase,
          harga_pabrik_per_kg, total_nilai_pabrik,
          total_diterima, total_selisih, jumlah_transaksi,
          catatan, alasan_batal, created_at,
          pabrik:pabrik_id ( id, nama ),
          rekening_kas:rekening_kas_id ( id, nama ),
          items:pembayaran_pabrik_item (
            id, transaksi_mitra_id, tanggal, mitra_label_snapshot,
            tonase_snapshot, total_nilai_pabrik_snapshot, jumlah_dialokasikan, status
          )
        `)
        .order('tanggal_bayar', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(30),
    ]);

    const firstError = accountError || pabrikError || hargaError || trxError || paymentError;
    if (firstError) {
      setToast({ type: 'error', message: `Gagal memuat pembayaran pabrik: ${firstError.message}` });
      setTimeout(() => setToast(null), 5000);
    }

    setAccounts(accountData || []);
    setPabriks(pabrikData || []);
    setHargaTwb(Number(hargaData?.harga_per_kg || 0));
    setTransactions(trxData || []);
    setPayments(paymentData || []);
    setForm((current) => ({
      ...current,
      rekening_kas_id: current.rekening_kas_id || accountData?.find((item) => item.is_default)?.id || accountData?.[0]?.id || '',
      pabrik_id: current.pabrik_id || pabrikData?.[0]?.id || '',
      harga_pabrik_per_kg: hargaData?.harga_per_kg ? String(hargaData.harga_per_kg) : '',
    }));
    setSelectedIds((current) => current.filter((id) => (trxData || []).some((row) => row.id === id)));
    setLoading(false);
  }, [filters.dateFrom, filters.dateTo]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadRole();
  }, [loadRole]);

  useEffect(() => {
    if (userRole && canManageFinance(userRole)) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      loadData();
    }
  }, [loadData, userRole]);

  const visibleTransactions = useMemo(() => {
    const search = filters.search.trim().toLowerCase();
    if (!search) return transactions;
    return transactions.filter((row) => getTransactionSearchText(row).includes(search));
  }, [filters.search, transactions]);

  const selectedRows = useMemo(() => (
    transactions.filter((row) => selectedIds.includes(row.id))
  ), [selectedIds, transactions]);

  const resolvePaymentHargaPerKg = useCallback((row) => resolveHargaPabrikPerKg(row), []);

  const resolvePaymentTotal = useCallback((row) => (
    Math.round(resolveBeratDibayar(row) * resolvePaymentHargaPerKg(row))
  ), [resolvePaymentHargaPerKg]);

  const visibleSummary = useMemo(() => (
    visibleTransactions.reduce((summary, row) => ({
      count: summary.count + 1,
      tonase: summary.tonase + resolveBeratDibayar(row),
      nilai: summary.nilai + resolvePaymentTotal(row),
    }), { count: 0, tonase: 0, nilai: 0 })
  ), [resolvePaymentTotal, visibleTransactions]);

  const reconciliationSummary = useMemo(() => {
    const totalTonaseSistem = selectedRows.reduce((sum, row) => sum + resolveBeratDibayar(row), 0);
    const totalNilaiSistem = selectedRows.reduce((sum, row) => sum + resolvePaymentTotal(row), 0);
    const tonasePabrik = Number(form.tonase_pabrik || 0);
    const hargaPabrik = Number(form.harga_pabrik_per_kg || 0);
    const nominalDiterima = Number(form.nominal_diterima || 0);
    const nilaiPabrik = tonasePabrik * hargaPabrik;

    return {
      totalTonaseSistem,
      totalNilaiSistem,
      tonasePabrik,
      hargaPabrik,
      nilaiPabrik,
      nominalDiterima,
      selisihTonase: tonasePabrik - totalTonaseSistem,
      selisihKas: nilaiPabrik - nominalDiterima,
    };
  }, [form.harga_pabrik_per_kg, form.nominal_diterima, form.tonase_pabrik, resolvePaymentTotal, selectedRows]);

  function setCalculatedNominal() {
    const calculated = Math.max(reconciliationSummary.nilaiPabrik, 0);
    setForm((current) => ({ ...current, nominal_diterima: String(Math.round(calculated)) }));
  }

  function toggleSelected(id) {
    setSelectedIds((current) => (
      current.includes(id) ? current.filter((item) => item !== id) : [...current, id]
    ));
  }

  function selectAllVisible() {
    const visibleIds = visibleTransactions.map((row) => row.id);
    setSelectedIds((current) => Array.from(new Set([...current, ...visibleIds])));
  }

  function clearSelected() {
    setSelectedIds([]);
  }

  function applyPeriod(dateFrom, dateTo = dateFrom) {
    setFilters((current) => ({ ...current, dateFrom, dateTo }));
    setSelectedIds([]);
  }

  async function handleSubmit(event) {
    event.preventDefault();
    if (saving) return;

    const tonasePabrik = Number(form.tonase_pabrik || 0);
    const hargaPabrik = Number(form.harga_pabrik_per_kg || 0);

    if (!tonasePabrik || tonasePabrik <= 0) {
      setToast({ type: 'error', message: 'Tonase dari pabrik wajib lebih dari 0.' });
      setTimeout(() => setToast(null), 4000);
      return;
    }

    if (!hargaPabrik || hargaPabrik <= 0) {
      setToast({ type: 'error', message: 'Harga per kg dari nota pabrik wajib diisi.' });
      setTimeout(() => setToast(null), 4000);
      return;
    }

    const nominal = Number(form.nominal_diterima || 0);
    if (!nominal || nominal <= 0) {
      setToast({ type: 'error', message: 'Uang diterima dari pabrik wajib lebih dari 0.' });
      setTimeout(() => setToast(null), 4000);
      return;
    }

    if (form.metode_bayar === 'transfer' && !form.nomor_bukti.trim()) {
      setToast({ type: 'error', message: 'Nomor bukti transfer wajib diisi.' });
      setTimeout(() => setToast(null), 4000);
      return;
    }

    setSaving(true);
    const { error } = await supabase.rpc('create_pembayaran_pabrik_batch', {
      p_pabrik_id: form.pabrik_id || null,
      p_tanggal_bayar: form.tanggal_bayar || getTodayISO(),
      p_metode_bayar: form.metode_bayar,
      p_tonase_pabrik: tonasePabrik,
      p_harga_pabrik_per_kg: hargaPabrik,
      p_nominal_diterima: nominal,
      p_rekening_kas_id: form.rekening_kas_id || null,
      p_nomor_bukti: form.nomor_bukti || null,
      p_catatan: form.catatan || null,
      p_transaksi_ids: selectedIds,
    });
    setSaving(false);

    if (error) {
      setToast({ type: 'error', message: `Gagal mencatat pembayaran pabrik: ${error.message}` });
      setTimeout(() => setToast(null), 6000);
      return;
    }

    setToast({ type: 'success', message: selectedIds.length > 0 ? 'Pembayaran pabrik berhasil dicatat dan data timbang sudah dicocokkan.' : 'Pembayaran pabrik berhasil dicatat ke Buku Kas.' });
    setSelectedIds([]);
    setForm((current) => ({
      ...emptyForm,
      pabrik_id: current.pabrik_id,
      rekening_kas_id: current.rekening_kas_id,
      harga_pabrik_per_kg: hargaTwb ? String(hargaTwb) : '',
      tanggal_bayar: getTodayISO(),
    }));
    setTimeout(() => setToast(null), 4000);
    await loadData();
  }

  async function handleConfirmCancel(reason) {
    if (!cancelTarget || canceling) return;

    setCanceling(true);
    const { error } = await supabase.rpc('cancel_pembayaran_pabrik_batch', {
      p_pembayaran_id: cancelTarget.id,
      p_alasan: reason,
    });
    setCanceling(false);

    if (error) {
      setToast({ type: 'error', message: `Gagal membatalkan pembayaran pabrik: ${error.message}` });
      setTimeout(() => setToast(null), 6000);
      return;
    }

    setToast({ type: 'success', message: 'Pembayaran pabrik dibatalkan dan catatan balik kas sudah dibuat.' });
    setCancelTarget(null);
    setTimeout(() => setToast(null), 4000);
    await loadData();
  }

  if (userRole !== null && !canManageFinance(userRole)) {
    return (
      <AppShell title="Pembayaran Pabrik" subtitle="Akses terbatas">
        <div className="empty-state" style={{ marginTop: 'var(--space-3xl)' }}>
          <div className="empty-state-title">Akses Ditolak</div>
          <div className="empty-state-text">Halaman ini hanya untuk Admin, Owner, dan Super Admin.</div>
        </div>
      </AppShell>
    );
  }

  if (userRole === null) {
    return (
      <AppShell title="Pembayaran Pabrik">
        <div style={{ textAlign: 'center', padding: 'var(--space-3xl)' }}>
          <div className="spinner spinner-lg" style={{ margin: '0 auto' }} />
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title="Pembayaran Pabrik" subtitle="Catat uang masuk dari pabrik dan cocokkan dengan data timbang kita">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <div>
          <p className="page-description">Isi sesuai nota pabrik. Pilih periode data timbang sesuai tanggal TBS masuk pabrik.</p>
        </div>
        <Link className="btn btn-outline btn-sm" href="/laporan/laba-rugi">Lihat Laba/Rugi</Link>
      </div>

      <div className="period-panel">
        <div className="period-panel-heading">
          <div>
            <h2><CalendarDays size={18} /> Periode Data Timbang</h2>
            <p>Ini tanggal catatan timbang kita, boleh berbeda dari tanggal uang masuk.</p>
          </div>
          <div className="period-quick-actions">
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => applyPeriod(getTodayISO())}>Hari Ini</button>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => applyPeriod(getOffsetDateISO(-1))}>Kemarin</button>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => applyPeriod(getOffsetDateISO(-6), getTodayISO())}>7 Hari</button>
          </div>
        </div>
        <div className="period-filter-grid">
          <div className="form-group">
            <label className="form-label">Dari Tanggal Timbang</label>
            <input
              type="date"
              className="form-input"
              value={filters.dateFrom}
              onChange={(event) => {
                setFilters({ ...filters, dateFrom: event.target.value });
                setSelectedIds([]);
              }}
            />
          </div>
          <div className="form-group">
            <label className="form-label">Sampai Tanggal Timbang</label>
            <input
              type="date"
              className="form-input"
              value={filters.dateTo}
              onChange={(event) => {
                setFilters({ ...filters, dateTo: event.target.value });
                setSelectedIds([]);
              }}
            />
          </div>
          <div className="form-group">
            <label className="form-label">Cari Data Timbang</label>
            <div className="search-box">
              <span className="search-box-icon"><Search size={16} /></span>
              <input
                className="form-input"
                value={filters.search}
                onChange={(event) => setFilters({ ...filters, search: event.target.value })}
                placeholder="Cari mitra, sopir, plat..."
                style={{ paddingLeft: 40 }}
              />
            </div>
          </div>
        </div>
      </div>

      <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(210px, 1fr))', marginBottom: 'var(--space-lg)' }}>
        <div className="card">
          <div className="card-header"><span className="card-title">Data Dipilih</span><CheckCircle2 size={18} /></div>
          <div className="card-value">{selectedRows.length}</div>
          <div className="card-label">{formatNumber(reconciliationSummary.totalTonaseSistem)} kg catatan kita</div>
        </div>
        <div className="card">
          <div className="card-header"><span className="card-title">Tonase dari Pabrik</span><Scale size={18} /></div>
          <div className="card-value">{formatNumber(reconciliationSummary.tonasePabrik)} kg</div>
          <div className="card-label">Sesuai nota pabrik</div>
        </div>
        <div className="card">
          <div className="card-header"><span className="card-title">Uang Masuk</span><BadgeDollarSign size={18} /></div>
          <div className="card-value text-success">{formatRupiah(reconciliationSummary.nominalDiterima)}</div>
          <div className="card-label">Tercatat di Buku Kas</div>
        </div>
        <div className="card">
          <div className="card-header"><span className="card-title">Beda Tonase</span><AlertTriangle size={18} /></div>
          <div className={`card-value ${Math.abs(reconciliationSummary.selisihTonase) > 0 ? 'text-warning' : 'text-success'}`}>{formatNumber(reconciliationSummary.selisihTonase)} kg</div>
          <div className="card-label">Pabrik - catatan kita</div>
        </div>
      </div>

      <div className="dashboard-two-col" style={{ marginBottom: 'var(--space-xl)' }}>
        <div className="card">
          <div className="section-heading compact">
            <div>
              <h2>Catat Pembayaran</h2>
              <p>Isi angka yang tertulis di nota pabrik.</p>
            </div>
          </div>
          <form onSubmit={handleSubmit}>
            <div className="form-grid">
              <div className="form-group">
                <label className="form-label form-label-required">Pabrik</label>
                <select className="form-input form-select" value={form.pabrik_id} onChange={(event) => setForm({ ...form, pabrik_id: event.target.value })} required>
                  <option value="">Pilih pabrik</option>
                  {pabriks.map((pabrik) => <option key={pabrik.id} value={pabrik.id}>{pabrik.nama}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label form-label-required">Tanggal Uang Masuk</label>
                <input type="date" className="form-input" value={form.tanggal_bayar} onChange={(event) => setForm({ ...form, tanggal_bayar: event.target.value })} required />
              </div>
            </div>
            <div className="form-grid">
              <div className="form-group">
                <label className="form-label form-label-required">Rekening Kas</label>
                <select className="form-input form-select" value={form.rekening_kas_id} onChange={(event) => setForm({ ...form, rekening_kas_id: event.target.value })} required>
                  {accounts.map((account) => <option key={account.id} value={account.id}>{account.nama}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label form-label-required">Metode</label>
                <select className="form-input form-select" value={form.metode_bayar} onChange={(event) => setForm({ ...form, metode_bayar: event.target.value })}>
                  <option value="transfer">Transfer</option>
                  <option value="tunai">Tunai</option>
                  <option value="lainnya">Lainnya</option>
                </select>
              </div>
            </div>
            <div className="form-grid">
              <div className="form-group">
                <label className="form-label form-label-required">Tonase dari Pabrik (kg)</label>
                <input type="number" min={1} step="0.01" className="form-input form-input-mono" value={form.tonase_pabrik} onChange={(event) => setForm({ ...form, tonase_pabrik: event.target.value })} required />
                <div className="form-hint">Isi tonase bersih yang tertulis di nota/timbangan pabrik.</div>
                {selectedRows.length > 0 && (
                  <button type="button" className="btn btn-ghost btn-sm" style={{ marginTop: 8 }} onClick={() => setForm({ ...form, tonase_pabrik: String(reconciliationSummary.totalTonaseSistem) })}>
                    Pakai tonase catatan kita
                  </button>
                )}
              </div>
              <div className="form-group">
                <label className="form-label form-label-required">Harga per Kg dari Nota Pabrik</label>
                <input type="number" min={1} step="1" className="form-input form-input-mono" value={form.harga_pabrik_per_kg} onChange={(event) => setForm({ ...form, harga_pabrik_per_kg: event.target.value })} required />
                <div className="form-hint">Otomatis memakai harga Dashboard terbaru ({hargaTwb ? `${formatRupiah(hargaTwb)} / kg` : 'belum diset'}). Ubah hanya jika nota pembayaran memakai harga lain.</div>
              </div>
            </div>
            <div className="form-grid">
              <div className="form-group">
                <label className="form-label form-label-required">Uang Diterima</label>
                <input type="number" min={1} className="form-input form-input-mono" value={form.nominal_diterima} onChange={(event) => setForm({ ...form, nominal_diterima: event.target.value })} required />
                <button type="button" className="btn btn-ghost btn-sm" style={{ marginTop: 8 }} onClick={setCalculatedNominal}>
                  Hitung otomatis
                </button>
              </div>
              <div className="form-group">
                <label className={`form-label ${form.metode_bayar === 'transfer' ? 'form-label-required' : ''}`}>Nomor Bukti</label>
                <input className="form-input" required={form.metode_bayar === 'transfer'} value={form.nomor_bukti} onChange={(event) => setForm({ ...form, nomor_bukti: event.target.value })} placeholder="Nomor transfer atau bukti dari pabrik" />
              </div>
            </div>
            <div className="form-group">
              <label className="form-label">Catatan</label>
              <input className="form-input" value={form.catatan} onChange={(event) => setForm({ ...form, catatan: event.target.value })} placeholder="Opsional" />
            </div>
            <div className="alert alert-info" style={{ marginBottom: 'var(--space-md)' }}>
              Pilih data timbang di bawah hanya untuk mencocokkan. Jika belum siap, uang masuk tetap bisa dicatat dulu dari nota pabrik.
            </div>
            {!form.harga_pabrik_per_kg && (
              <div className="alert alert-warning" style={{ marginBottom: 'var(--space-md)' }}>
                Harga Dashboard belum tersedia. Isi harga sesuai angka pada nota pembayaran pabrik.
              </div>
            )}
            <button className="btn btn-primary" disabled={saving}>
              {saving ? 'Mencatat...' : 'Catat Pembayaran Pabrik'}
            </button>
          </form>
        </div>

        <div className="card">
          <div className="section-heading compact">
            <div>
              <h2>Riwayat Terakhir</h2>
              <p>Pembayaran pabrik yang sudah tercatat.</p>
            </div>
          </div>
          <div className="payment-history-list">
            {payments.length === 0 ? (
              <div className="empty-compact">Belum ada pembayaran pabrik.</div>
            ) : payments.map((payment) => (
              <div className="payment-history-item" key={payment.id}>
                <div>
                  <strong>{payment.pabrik?.nama || 'Pabrik'}</strong>
                  <small>{formatDateDisplay(payment.tanggal_bayar)} - tonase pabrik {formatNumber(payment.total_tonase)} kg - {payment.jumlah_transaksi > 0 ? `${payment.jumlah_transaksi} data dicocokkan` : 'belum dicocokkan'} - {payment.nomor_bukti || 'Tanpa bukti'}</small>
                  {payment.status === 'dibatalkan' && <small className="text-danger">Dibatalkan: {payment.alasan_batal || '-'}</small>}
                </div>
                <div className="payment-history-side">
                  <b className={payment.status === 'dibatalkan' ? 'text-danger' : 'text-success'}>{formatRupiah(payment.total_diterima)}</b>
                  {payment.status !== 'dibatalkan' && (
                    <button className="btn btn-ghost btn-sm" onClick={() => setCancelTarget(payment)} title="Batalkan dan buat catatan balik di kas">
                      <RotateCcw size={14} /> Batal
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <section className="dashboard-section">
        <div className="section-heading">
          <div>
            <h2>Cocokkan Dengan Catatan Kita</h2>
            <p>Yang tampil mengikuti periode data timbang. Berat dan harga memakai angka yang tersimpan saat pengiriman dicatat.</p>
          </div>
          <div className="flex gap-sm" style={{ flexWrap: 'wrap', justifyContent: 'flex-end' }}>
            <button className="btn btn-outline btn-sm" onClick={selectAllVisible} disabled={visibleTransactions.length === 0}>Pilih Semua</button>
            <button className="btn btn-ghost btn-sm" onClick={clearSelected}>Kosongkan</button>
          </div>
        </div>

        <div className="reconciliation-strip">
          <span>{visibleSummary.count.toLocaleString('id-ID')} data tampil</span>
          <span>{formatNumber(visibleSummary.tonase)} kg catatan kita</span>
          <span>{formatRupiah(visibleSummary.nilai)} nilai catatan kita</span>
          <span>{selectedRows.length.toLocaleString('id-ID')} data dipilih</span>
          <span>{formatRupiah(reconciliationSummary.totalNilaiSistem)} nilai dipilih</span>
        </div>

        <div className="table-container">
          <table className="table">
            <thead>
              <tr>
                <th style={{ width: 44 }}></th>
                <th>Tanggal</th>
                <th>Waktu</th>
                <th>Mitra</th>
                <th>Sopir / Plat</th>
                <th style={{ textAlign: 'right' }}>Tonase</th>
                <th style={{ textAlign: 'right' }}>Harga Saat Dicatat</th>
                <th style={{ textAlign: 'right' }}>Nilai Catatan Kita</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={8} style={{ textAlign: 'center', padding: 24 }}>Memuat data timbang...</td></tr>
              ) : visibleTransactions.length === 0 ? (
                <tr><td colSpan={8} style={{ textAlign: 'center', padding: 24 }}>Tidak ada data timbang yang belum dicocokkan pada tanggal ini.</td></tr>
              ) : visibleTransactions.map((row) => {
                const hargaTampilan = resolvePaymentHargaPerKg(row);
                const hargaSaatInput = resolveHargaPabrikPerKg(row);
                const hargaNota = Number(form.harga_pabrik_per_kg || 0);
                const hargaBerbeda = hargaNota > 0 && hargaSaatInput > 0 && Math.round(hargaSaatInput) !== Math.round(hargaNota);

                return (
                  <tr key={row.id} className={selectedIds.includes(row.id) ? 'row-selected' : ''}>
                    <td>
                      <input type="checkbox" checked={selectedIds.includes(row.id)} onChange={() => toggleSelected(row.id)} aria-label={`Pilih data timbang ${row.id}`} />
                    </td>
                    <td>{formatDateDisplay(row.tanggal)}</td>
                    <td className="table-mono">{formatWaktu(row.created_at)}</td>
                    <td>{getMitraLabel(row.master_mitra)}</td>
                    <td>
                      <div>{row.sopir_aktual_nama || row.sopir_default_nama || '-'}</div>
                      <small className="text-tertiary table-mono">{row.plat_nomor || '-'}</small>
                    </td>
                    <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(resolveBeratDibayar(row))} kg</td>
                    <td className="table-mono" style={{ textAlign: 'right' }}>
                      <div>{formatRupiah(hargaTampilan)}</div>
                      {hargaBerbeda && <small className="text-warning">Nota sekarang: {formatRupiah(hargaNota)}</small>}
                    </td>
                    <td className="table-mono" style={{ textAlign: 'right', fontWeight: 800 }}>{formatRupiah(resolvePaymentTotal(row))}</td>
                  </tr>
                );
              })}
            </tbody>
            {visibleTransactions.length > 0 && (
              <tfoot>
                <tr>
                  <td colSpan={5} style={{ textAlign: 'right', fontWeight: 800 }}>TOTAL TAMPIL:</td>
                  <td className="table-mono" style={{ textAlign: 'right', fontWeight: 800 }}>{formatNumber(visibleSummary.tonase)} kg</td>
                  <td></td>
                  <td className="table-mono" style={{ textAlign: 'right', fontWeight: 800 }}>{formatRupiah(visibleSummary.nilai)}</td>
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      </section>

      <PromptDialog
        open={!!cancelTarget}
        title="Batalkan Pembayaran Pabrik"
        message={cancelTarget ? `Pembayaran ${cancelTarget.nomor_bukti || cancelTarget.id} akan dibatalkan dan dibuat catatan balik di Buku Kas.` : ''}
        label="Alasan pembatalan"
        placeholder="Contoh: salah nominal / salah tanggal / duplikat"
        confirmText="Batalkan Pembayaran"
        cancelText="Kembali"
        variant="danger"
        loading={canceling}
        onConfirm={handleConfirmCancel}
        onCancel={() => !canceling && setCancelTarget(null)}
      />

      <style jsx global>{`
        .dashboard-two-col {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(320px, 0.8fr);
          gap: var(--space-lg);
        }

        .section-heading {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: var(--space-md);
          margin-bottom: var(--space-md);
        }

        .section-heading.compact {
          margin-bottom: var(--space-lg);
        }

        .section-heading h2 {
          margin: 0;
          color: var(--text-primary);
          font-size: var(--text-lg);
          font-weight: 800;
        }

        .section-heading p {
          margin: 4px 0 0;
          color: var(--text-tertiary);
          font-size: var(--text-sm);
        }

        .payment-history-list {
          display: flex;
          flex-direction: column;
          gap: var(--space-sm);
        }

        .payment-history-item {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: var(--space-md);
          padding: 12px;
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          background: rgba(15, 23, 42, 0.36);
        }

        .payment-history-item strong,
        .payment-history-item small {
          display: block;
        }

        .payment-history-item small {
          margin-top: 4px;
          color: var(--text-tertiary);
          font-size: var(--text-xs);
          line-height: 1.35;
        }

        .payment-history-side {
          display: flex;
          align-items: flex-end;
          flex-direction: column;
          gap: 8px;
          text-align: right;
        }

        .payment-history-side b {
          font-family: var(--font-mono);
          white-space: nowrap;
        }

        .empty-compact {
          padding: 16px 0;
          color: var(--text-tertiary);
          font-size: var(--text-sm);
        }

        .row-selected {
          background: rgba(46, 204, 113, 0.08);
        }

        .period-panel {
          margin-bottom: var(--space-lg);
          padding: var(--space-lg);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-lg);
          background: rgba(15, 23, 42, 0.36);
        }

        .period-panel-heading {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: var(--space-md);
          margin-bottom: var(--space-md);
        }

        .period-panel-heading h2 {
          margin: 0;
          display: flex;
          align-items: center;
          gap: 8px;
          font-size: var(--text-md);
          font-weight: 800;
        }

        .period-panel-heading p {
          margin: 4px 0 0;
          color: var(--text-tertiary);
          font-size: var(--text-sm);
        }

        .period-quick-actions {
          display: flex;
          gap: 8px;
          flex-wrap: wrap;
          justify-content: flex-end;
        }

        .period-filter-grid {
          display: grid;
          grid-template-columns: minmax(160px, 0.7fr) minmax(160px, 0.7fr) minmax(260px, 1.4fr);
          gap: var(--space-md);
          align-items: end;
        }

        .reconciliation-strip {
          margin: calc(var(--space-md) * -0.25) 0 var(--space-md);
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }

        .reconciliation-strip span {
          padding: 6px 10px;
          border: 1px solid var(--border-default);
          border-radius: 8px;
          background: rgba(15, 23, 42, 0.36);
          color: var(--text-secondary);
          font-size: 12px;
          font-weight: 700;
        }

        @media (max-width: 980px) {
          .dashboard-two-col {
            grid-template-columns: 1fr;
          }

          .period-filter-grid {
            grid-template-columns: 1fr;
          }
        }

        @media (max-width: 640px) {
          .section-heading,
          .payment-history-item,
          .period-panel-heading {
            flex-direction: column;
          }

          .payment-history-side {
            align-items: flex-start;
            text-align: left;
          }

          .period-quick-actions {
            justify-content: flex-start;
          }
        }
      `}</style>
    </AppShell>
  );
}
