'use client';

import { useCallback, useEffect, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import PromptDialog from '@/components/ui/PromptDialog';
import TablePagination from '@/components/ui/TablePagination';
import { canApproveCorrections, normalizeRole } from '@/lib/roles';
import { paginateRows } from '@/lib/pagination-utils';
import { supabase } from '@/lib/supabase';
import { formatDateDisplay, formatRupiah, getTodayISO } from '@/lib/utils';
import { RotateCcw } from 'lucide-react';

const KAS_SOURCES = [
  { value: 'modal_awal', label: 'Modal Awal' },
  { value: 'koreksi', label: 'Koreksi' },
  { value: 'lainnya', label: 'Lainnya' },
];

const PAGE_SIZE = 20;
const QUERY_LIMIT = 500;

function getSignedAmount(row) {
  const jumlah = Number(row.jumlah || 0);
  if (['masuk', 'transfer_masuk'].includes(row.tipe)) return jumlah;
  if (['keluar', 'transfer_keluar'].includes(row.tipe)) return -jumlah;
  if (row.tipe === 'reversal') return jumlah;
  return row.sumber === 'reversal' ? jumlah : 0;
}

function getSourceLabel(source) {
  const labels = {
    modal_awal: 'Modal Awal',
    pembayaran_pabrik: 'Pembayaran Pabrik',
    pembayaran_mitra: 'Pembayaran Mitra',
    pembayaran_petani: 'Pembayaran Petani',
    pembelian_tbs: 'Pembelian TBS',
    hutang_pencairan: 'Pencairan Hutang',
    hutang_pelunasan: 'Pelunasan Hutang',
    panjar_mitra: 'Panjar Mitra',
    biaya_operasional: 'Biaya Operasional',
    transfer_kas: 'Transfer Kas',
    koreksi: 'Koreksi',
    reversal: 'Reversal',
    lainnya: 'Lainnya',
  };
  return labels[source] || source || '-';
}

export default function KasLedgerPage() {
  const [accounts, setAccounts] = useState([]);
  const [ledger, setLedger] = useState([]);
  const [loading, setLoading] = useState(true);
  const [userRole, setUserRole] = useState(null);
  const [cashSummary, setCashSummary] = useState({ saldo_pembuka: 0, kas_masuk: 0, kas_keluar: 0, saldo_akhir: 0 });
  const [showModal, setShowModal] = useState(false);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState(null);
  const [reverseTarget, setReverseTarget] = useState(null);
  const [reversing, setReversing] = useState(false);
  const [page, setPage] = useState(1);
  const [filter, setFilter] = useState({ accountId: 'semua', dateFrom: '', dateTo: getTodayISO() });
  const [form, setForm] = useState({
    tanggal: getTodayISO(),
    tipe: 'masuk',
    sumber: 'modal_awal',
    jumlah: '',
    keterangan: '',
    rekening_kas_id: '',
  });

  const loadData = useCallback(async () => {
    setLoading(true);

    let ledgerQuery = supabase
      .from('kas_ledger')
      .select('*, rekening_kas:rekening_kas_id(nama, tipe)')
      .neq('status', 'dibatalkan')
      .order('tanggal', { ascending: false })
      .order('created_at', { ascending: false })
      .limit(QUERY_LIMIT);

    if (filter.accountId !== 'semua') ledgerQuery = ledgerQuery.eq('rekening_kas_id', filter.accountId);
    if (filter.dateFrom) ledgerQuery = ledgerQuery.gte('tanggal', filter.dateFrom);
    if (filter.dateTo) ledgerQuery = ledgerQuery.lte('tanggal', filter.dateTo);

    const [{ data: accountData, error: accountError }, { data: ledgerData, error: ledgerError }, { data: summaryData, error: summaryError }] = await Promise.all([
      supabase.from('rekening_kas').select('*').eq('aktif', true).order('is_default', { ascending: false }).order('nama'),
      ledgerQuery,
      supabase.rpc('get_kas_summary', {
        p_rekening_kas_id: filter.accountId === 'semua' ? null : filter.accountId,
        p_date_from: filter.dateFrom || null,
        p_date_to: filter.dateTo || null,
      }),
    ]);

    const firstError = accountError || ledgerError || summaryError;
    if (firstError) {
      setToast({ type: 'error', message: firstError.message });
      setTimeout(() => setToast(null), 5000);
    }

    setAccounts(accountData || []);
    setLedger(ledgerData || []);
    setCashSummary(summaryData || { saldo_pembuka: 0, kas_masuk: 0, kas_keluar: 0, saldo_akhir: 0 });
    setLoading(false);
  }, [filter.accountId, filter.dateFrom, filter.dateTo]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  useEffect(() => {
    async function loadRole() {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return;
      const { data } = await supabase.from('users').select('role').eq('id', session.user.id).maybeSingle();
      setUserRole(normalizeRole(data?.role));
    }
    loadRole();
  }, []);

  const canReverse = canApproveCorrections(userRole);
  const paginatedLedger = paginateRows(ledger, page, PAGE_SIZE);

  function openModal(tipe = 'masuk') {
    setForm({
      tanggal: getTodayISO(),
      tipe,
      sumber: tipe === 'masuk' ? 'modal_awal' : 'lainnya',
      jumlah: '',
      keterangan: '',
      rekening_kas_id: accounts.find((item) => item.is_default)?.id || accounts[0]?.id || '',
    });
    setShowModal(true);
  }

  async function handleSave(e) {
    e.preventDefault();
    const jumlah = Number(form.jumlah);
    if (!jumlah || jumlah <= 0 || !form.keterangan.trim()) return;

    setSaving(true);
    const { error } = await supabase.rpc('create_kas_mutasi', {
      p_tanggal: form.tanggal,
      p_tipe: form.tipe,
      p_sumber: form.sumber,
      p_jumlah: jumlah,
      p_rekening_kas_id: form.rekening_kas_id || null,
      p_keterangan: form.keterangan || null,
      p_source_table: null,
      p_source_id: null,
      p_idempotency_key: null,
    });
    setSaving(false);

    if (error) {
      setToast({ type: 'error', message: `Gagal mencatat kas: ${error.message}` });
      setTimeout(() => setToast(null), 5000);
      return;
    }

    setShowModal(false);
    setToast({ type: 'success', message: 'Mutasi kas berhasil dicatat.' });
    setTimeout(() => setToast(null), 3000);
    await loadData();
  }

  async function handleReverse(reason) {
    if (!reverseTarget || reversing) return;
    setReversing(true);
    const { error } = await supabase.rpc('cancel_kas_mutasi_manual', {
      p_kas_id: reverseTarget.id,
      p_alasan: reason,
    });
    setReversing(false);

    if (error) {
      setToast({ type: 'error', message: `Gagal membalik mutasi: ${error.message}` });
      setTimeout(() => setToast(null), 5000);
      return;
    }

    setReverseTarget(null);
    setToast({ type: 'success', message: 'Mutasi manual dibalik dan riwayat tetap tersimpan.' });
    setTimeout(() => setToast(null), 3000);
    await loadData();
  }

  return (
    <AppShell title="Buku Kas" subtitle="Catatan uang masuk dan keluar berbasis transaksi">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <div>
          <p className="page-description">Catatan kas ini menjadi dasar audit uang masuk dan keluar.</p>
        </div>
        <div className="flex gap-sm" style={{ flexWrap: 'wrap' }}>
          <button className="btn btn-outline btn-sm" onClick={() => openModal('keluar')}>Kas Keluar Manual</button>
          <button className="btn btn-primary btn-sm" onClick={() => openModal('masuk')}>Kas Masuk Manual</button>
        </div>
      </div>

      <div className="toolbar">
        <select
          className="form-input form-select"
          value={filter.accountId}
          onChange={(e) => { setFilter((current) => ({ ...current, accountId: e.target.value })); setPage(1); }}
          style={{ maxWidth: 220 }}
        >
          <option value="semua">Semua Rekening</option>
          {accounts.map((account) => <option key={account.id} value={account.id}>{account.nama}</option>)}
        </select>
        <input
          type="date"
          className="form-input"
          value={filter.dateFrom}
          onChange={(e) => { setFilter((current) => ({ ...current, dateFrom: e.target.value })); setPage(1); }}
          style={{ maxWidth: 170 }}
        />
        <input
          type="date"
          className="form-input"
          value={filter.dateTo}
          onChange={(e) => { setFilter((current) => ({ ...current, dateTo: e.target.value })); setPage(1); }}
          style={{ maxWidth: 170 }}
        />
      </div>

      <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', marginBottom: 'var(--space-lg)' }}>
        <div className="card">
          <div className="card-header"><span className="card-title">Saldo Pembuka</span></div>
          <div className="card-value">{formatRupiah(cashSummary.saldo_pembuka)}</div>
          <div className="card-label">Sebelum periode</div>
        </div>
        <div className="card">
          <div className="card-header"><span className="card-title">Kas Masuk</span></div>
          <div className="card-value text-success">{formatRupiah(cashSummary.kas_masuk)}</div>
          <div className="card-label">Sesuai filter</div>
        </div>
        <div className="card">
          <div className="card-header"><span className="card-title">Kas Keluar</span></div>
          <div className="card-value text-danger">{formatRupiah(cashSummary.kas_keluar)}</div>
          <div className="card-label">Sesuai filter</div>
        </div>
        <div className="card">
          <div className="card-header"><span className="card-title">Saldo Akhir</span></div>
          <div className={`card-value ${Number(cashSummary.saldo_akhir) >= 0 ? 'text-success' : 'text-danger'}`}>{formatRupiah(cashSummary.saldo_akhir)}</div>
          <div className="card-label">{ledger.length} mutasi</div>
        </div>
      </div>

      <div className="table-container">
        <table className="table">
          <thead>
            <tr>
              <th>Tanggal</th>
              <th>Rekening</th>
              <th>Sumber</th>
              <th>Keterangan</th>
              <th style={{ textAlign: 'right' }}>Masuk</th>
              <th style={{ textAlign: 'right' }}>Keluar</th>
              <th style={{ textAlign: 'center' }}>Aksi</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={7} style={{ textAlign: 'center', padding: 24 }}>Memuat ledger kas...</td></tr>
            ) : ledger.length === 0 ? (
              <tr><td colSpan={7} style={{ textAlign: 'center', padding: 24 }}>Belum ada mutasi kas</td></tr>
            ) : (
              paginatedLedger.rows.map((row) => {
                const signed = getSignedAmount(row);
                return (
                  <tr key={row.id}>
                    <td>{formatDateDisplay(row.tanggal)}</td>
                    <td>{row.rekening_kas?.nama || '-'}</td>
                    <td><span className="badge badge-neutral">{getSourceLabel(row.sumber)}</span></td>
                    <td>{row.keterangan || '-'}</td>
                    <td className="table-mono text-success" style={{ textAlign: 'right' }}>{signed > 0 ? formatRupiah(signed) : ''}</td>
                    <td className="table-mono text-danger" style={{ textAlign: 'right' }}>{signed < 0 ? formatRupiah(Math.abs(signed)) : ''}</td>
                    <td style={{ textAlign: 'center' }}>
                      {canReverse && !row.source_table && !row.reversed_at && row.sumber !== 'reversal' && (
                        <button className="btn btn-ghost btn-sm" title="Balikkan mutasi manual" onClick={() => setReverseTarget(row)}>
                          <RotateCcw size={15} />
                        </button>
                      )}
                      {row.reversed_at && <span className="badge badge-warning">Sudah dibalik</span>}
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
        <TablePagination
          page={paginatedLedger.page}
          totalPages={paginatedLedger.totalPages}
          totalItems={ledger.length}
          startIndex={paginatedLedger.startIndex}
          endIndex={paginatedLedger.endIndex}
          onPageChange={setPage}
        />
        {ledger.length >= QUERY_LIMIT && (
          <div className="alert alert-warning" style={{ margin: 'var(--space-md)' }}>
            Menampilkan maksimal {QUERY_LIMIT} mutasi terbaru. Persempit periode untuk melihat data lain.
          </div>
        )}
      </div>

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">{form.tipe === 'masuk' ? 'Kas Masuk Manual' : 'Kas Keluar Manual'}</h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>x</button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Tanggal</label>
                    <input type="date" className="form-input" value={form.tanggal} onChange={(e) => setForm({ ...form, tanggal: e.target.value })} required />
                  </div>
                  <div className="form-group">
                    <label className="form-label form-label-required">Rekening Kas</label>
                    <select className="form-input form-select" value={form.rekening_kas_id} onChange={(e) => setForm({ ...form, rekening_kas_id: e.target.value })}>
                      {accounts.map((account) => <option key={account.id} value={account.id}>{account.nama}</option>)}
                    </select>
                  </div>
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Tipe</label>
                    <select className="form-input form-select" value={form.tipe} onChange={(e) => setForm({ ...form, tipe: e.target.value })}>
                      <option value="masuk">Masuk</option>
                      <option value="keluar">Keluar</option>
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label form-label-required">Sumber</label>
                    <select className="form-input form-select" value={form.sumber} onChange={(e) => setForm({ ...form, sumber: e.target.value })}>
                      {KAS_SOURCES.map((source) => <option key={source.value} value={source.value}>{source.label}</option>)}
                    </select>
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Jumlah (Rp)</label>
                  <input type="number" className="form-input form-input-mono" min={1} value={form.jumlah} onChange={(e) => setForm({ ...form, jumlah: e.target.value })} required />
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Nomor Bukti / Keterangan</label>
                  <input className="form-input" required value={form.keterangan} onChange={(e) => setForm({ ...form, keterangan: e.target.value })} placeholder="Contoh: bukti transfer 123 atau koreksi saldo" />
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" onClick={() => setShowModal(false)}>Batal</button>
                <button className="btn btn-primary" disabled={saving}>{saving ? 'Menyimpan...' : 'Simpan'}</button>
              </div>
            </form>
          </div>
        </div>
      )}

      <PromptDialog
        open={Boolean(reverseTarget)}
        title="Balikkan Mutasi Kas Manual"
        message="Sistem akan membuat transaksi dengan arah berlawanan. Catatan awal tidak dihapus."
        label="Alasan pembalikan"
        placeholder="Contoh: salah jumlah"
        confirmText="Balikkan Mutasi"
        loading={reversing}
        onConfirm={handleReverse}
        onCancel={() => !reversing && setReverseTarget(null)}
      />
    </AppShell>
  );
}
