'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import AppShell from '@/components/layout/AppShell';
import BrandMark from '@/components/branding/BrandMark';
import PromptDialog from '@/components/ui/PromptDialog';
import { useBrandingSettings } from '@/lib/use-branding-settings';
import { canApproveCorrections, normalizeRole } from '@/lib/roles';
import { supabase } from '@/lib/supabase';
import { exportToExcel } from '@/lib/export';
import { formatDateDisplay, formatRupiah, getTodayISO } from '@/lib/utils';
import {
  BanknoteArrowDown, Check, FileText, HandCoins, Printer, RotateCcw,
  ShieldCheck, WalletCards, X,
} from 'lucide-react';

const PARTY_TYPES = [
  { value: 'mitra', label: 'Mitra' },
  { value: 'karyawan', label: 'Karyawan' },
  { value: 'sopir', label: 'Sopir' },
  { value: 'petani', label: 'Petani' },
  { value: 'lainnya', label: 'Pihak Lain' },
];

const STATUS_META = {
  menunggu_persetujuan: { label: 'Menunggu Persetujuan', badge: 'badge-warning' },
  disetujui: { label: 'Siap Diserahkan', badge: 'badge-info' },
  ditolak: { label: 'Ditolak', badge: 'badge-danger' },
  diserahkan: { label: 'Belum Lunas', badge: 'badge-warning' },
  lunas: { label: 'Lunas', badge: 'badge-success' },
  dibatalkan: { label: 'Dibatalkan', badge: 'badge-neutral' },
};

const METHOD_LABELS = {
  potong_kwitansi_tbs: 'Potong dari Kwitansi TBS',
  potong_gaji: 'Potong dari Gaji',
  potong_upah: 'Potong dari Upah Sopir',
  tunai_transfer: 'Dikembalikan Tunai/Transfer',
  tunai: 'Tunai',
  transfer: 'Transfer',
};

function getPartyLabel(type) {
  return PARTY_TYPES.find((item) => item.value === type)?.label || type || '-';
}

function getDocumentTitle(document) {
  if (document?.jenis_dokumen === 'panjar_mitra') return 'Bukti Pemberian Panjar Mitra';
  if (document?.jenis_dokumen === 'panjar_petani') return 'Bukti Pemberian Panjar Petani';
  if (document?.jenis_dokumen === 'kasbon_sopir') return 'Bukti Pemberian Pinjaman Sopir';
  if (document?.jenis_dokumen === 'kasbon_karyawan') return 'Bukti Pemberian Pinjaman Karyawan';
  return 'Surat Pengakuan Pinjaman';
}

function getDefaultRepaymentMethod(type) {
  if (type === 'mitra') return 'potong_kwitansi_tbs';
  if (type === 'sopir') return 'potong_upah';
  if (type === 'karyawan') return 'potong_gaji';
  return 'tunai_transfer';
}

function getRepaymentOptions(type) {
  if (type === 'mitra') return [{ value: 'potong_kwitansi_tbs', label: METHOD_LABELS.potong_kwitansi_tbs }];
  if (type === 'sopir') return [
    { value: 'potong_upah', label: METHOD_LABELS.potong_upah },
    { value: 'tunai_transfer', label: METHOD_LABELS.tunai_transfer },
  ];
  if (type === 'karyawan') return [
    { value: 'potong_gaji', label: METHOD_LABELS.potong_gaji },
    { value: 'tunai_transfer', label: METHOD_LABELS.tunai_transfer },
  ];
  return [{ value: 'tunai_transfer', label: METHOD_LABELS.tunai_transfer }];
}

function calculateRemaining(document) {
  if (!document || ['lunas', 'dibatalkan', 'ditolak'].includes(document.status)) return 0;
  const paid = (document.piutang_pelunasan || [])
    .filter((item) => item.status === 'aktif')
    .reduce((total, item) => total + Number(item.jumlah || 0), 0);
  return Math.max(Number(document.jumlah || 0) - paid, 0);
}

function createEmptyRequest(type = 'mitra') {
  return {
    pihak_type: type,
    petani_id: '',
    master_mitra_id: '',
    sopir_id: '',
    pihak_nama_manual: '',
    tanggal: getTodayISO(),
    tanggal_jatuh_tempo: '',
    jumlah: '',
    tujuan: '',
    metode_pelunasan: getDefaultRepaymentMethod(type),
    catatan: '',
  };
}

export default function PinjamanPage() {
  const { branding } = useBrandingSettings();
  const [userRole, setUserRole] = useState(null);
  const [petaniList, setPetaniList] = useState([]);
  const [mitraList, setMitraList] = useState([]);
  const [sopirList, setSopirList] = useState([]);
  const [rekeningList, setRekeningList] = useState([]);
  const [documents, setDocuments] = useState([]);
  const [ledgerRows, setLedgerRows] = useState([]);
  const [legacyPanjarIssues, setLegacyPanjarIssues] = useState([]);
  const [selectedDocument, setSelectedDocument] = useState(null);
  const [statusFilter, setStatusFilter] = useState('aktif');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState(null);
  const [requestOpen, setRequestOpen] = useState(false);
  const [disburseTarget, setDisburseTarget] = useState(null);
  const [repaymentTarget, setRepaymentTarget] = useState(null);
  const [rejectTarget, setRejectTarget] = useState(null);
  const [cancelTarget, setCancelTarget] = useState(null);
  const [cancelRepaymentTarget, setCancelRepaymentTarget] = useState(null);
  const [reconcileTarget, setReconcileTarget] = useState(null);
  const [printRepayment, setPrintRepayment] = useState(null);
  const [requestForm, setRequestForm] = useState(createEmptyRequest());
  const [disburseForm, setDisburseForm] = useState({ metode: 'tunai', penerima: '', identitas: '', rekening_id: '' });
  const [repaymentForm, setRepaymentForm] = useState({ jumlah: '', metode: 'tunai', tanggal: getTodayISO(), rekening_id: '', keterangan: '' });

  const canApprove = canApproveCorrections(userRole);

  const showToast = useCallback((message, type = 'error', timeout = 4500) => {
    setToast({ message, type });
    window.setTimeout(() => setToast(null), timeout);
  }, []);

  const loadData = useCallback(async () => {
    setLoading(true);
    const { data: { session } } = await supabase.auth.getSession();
    const userId = session?.user?.id;

    const [userResult, petaniResult, mitraResult, sopirResult, rekeningResult, documentResult, ledgerResult, legacyPanjarResult] = await Promise.all([
      userId ? supabase.from('users').select('role').eq('id', userId).maybeSingle() : Promise.resolve({ data: null }),
      supabase.from('petani').select('id, nama, no_hp').eq('aktif', true).order('nama'),
      supabase.from('master_mitra').select('id, kode, nama, no_hp').eq('aktif', true).order('kode'),
      supabase.from('sopir').select('id, nama, no_hp, plat_nomor').eq('aktif', true).order('nama'),
      supabase.from('rekening_kas').select('id, nama, tipe').eq('aktif', true).order('is_default', { ascending: false }),
      supabase.from('piutang_dokumen').select('*, piutang_pelunasan(*), panjar_mitra:panjar_mitra_id(status, pembayaran_mitra_kwitansi_id, pembayaran_mitra_kwitansi:pembayaran_mitra_kwitansi_id(periode_dari, periode_sampai))').order('created_at', { ascending: false }),
      supabase.from('hutang_ledger').select('id, pihak_type, petani_id, mitra_id, master_mitra_id, sopir_id, pihak_nama_manual, tipe, jumlah, status, legacy_source_table').neq('status', 'dibatalkan'),
      supabase.from('panjar_mitra').select('id, tanggal, mitra_id, jumlah, keterangan, status, pembayaran_mitra_kwitansi_id, settlement_hutang_ledger_id').eq('status', 'lunas').not('settlement_hutang_ledger_id', 'is', null).is('hutang_ledger_id', null).order('tanggal'),
    ]);

    const firstError = [petaniResult, mitraResult, sopirResult, rekeningResult, documentResult, ledgerResult, legacyPanjarResult].find((item) => item.error)?.error;
    if (firstError) showToast(`Gagal memuat Pinjaman & Panjar: ${firstError.message}`);

    setUserRole(normalizeRole(userResult.data?.role));
    setPetaniList(petaniResult.data || []);
    setMitraList(mitraResult.data || []);
    setSopirList(sopirResult.data || []);
    setRekeningList(rekeningResult.data || []);
    setDocuments(documentResult.data || []);
    setLedgerRows((ledgerResult.data || []).filter((row) => !['tagihan_sopir_cb', 'pembayaran_tagihan_sopir_cb'].includes(row.legacy_source_table)));
    setLegacyPanjarIssues(legacyPanjarResult.data || []);
    setSelectedDocument((current) => {
      if (!current) return documentResult.data?.[0] || null;
      return documentResult.data?.find((item) => item.id === current.id) || null;
    });
    setLoading(false);
  }, [showToast]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  const filteredDocuments = useMemo(() => documents.filter((document) => {
    if (statusFilter === 'semua') return true;
    if (statusFilter === 'aktif') return !['lunas', 'ditolak', 'dibatalkan'].includes(document.status);
    return document.status === statusFilter;
  }), [documents, statusFilter]);

  const summary = useMemo(() => {
    const balances = new Map();
    ledgerRows.forEach((row) => {
      const partyId = row.petani_id || row.master_mitra_id || row.mitra_id || row.sopir_id || row.pihak_nama_manual || 'tanpa-pihak';
      const key = `${row.pihak_type}:${partyId}`;
      const mutation = row.tipe === 'debit' ? Number(row.jumlah || 0) : -Number(row.jumlah || 0);
      balances.set(key, (balances.get(key) || 0) + mutation);
    });
    const partyBalances = [...balances.values()];
    const totalOutstanding = partyBalances.filter((balance) => balance > 0).reduce((total, balance) => total + balance, 0);
    const unmatchedReduction = Math.abs(partyBalances.filter((balance) => balance < 0).reduce((total, balance) => total + balance, 0));
    return {
      totalOutstanding,
      unmatchedReduction,
      waiting: documents.filter((item) => item.status === 'menunggu_persetujuan').length,
      ready: documents.filter((item) => item.status === 'disetujui').length,
      open: documents.filter((item) => item.status === 'diserahkan').length,
      anomaly: unmatchedReduction > 0,
    };
  }, [documents, ledgerRows]);

  function openRequest(type = 'mitra') {
    setRequestForm(createEmptyRequest(type));
    setRequestOpen(true);
  }

  async function handleCreateRequest(event) {
    event.preventDefault();
    setSaving(true);
    const { error } = await supabase.rpc('create_piutang_request', {
      p_pihak_type: requestForm.pihak_type,
      p_jumlah: Number(requestForm.jumlah),
      p_tujuan: requestForm.tujuan,
      p_metode_pelunasan: requestForm.metode_pelunasan,
      p_tanggal: requestForm.tanggal,
      p_tanggal_jatuh_tempo: requestForm.tanggal_jatuh_tempo || null,
      p_petani_id: requestForm.pihak_type === 'petani' ? requestForm.petani_id || null : null,
      p_master_mitra_id: requestForm.pihak_type === 'mitra' ? requestForm.master_mitra_id || null : null,
      p_sopir_id: requestForm.pihak_type === 'sopir' ? requestForm.sopir_id || null : null,
      p_pihak_nama_manual: ['karyawan', 'lainnya'].includes(requestForm.pihak_type) ? requestForm.pihak_nama_manual || null : null,
      p_catatan: requestForm.catatan || null,
    });
    setSaving(false);
    if (error) return showToast(`Gagal membuat pengajuan: ${error.message}`);
    setRequestOpen(false);
    showToast(canApprove ? 'Pengajuan tersimpan dan otomatis disetujui.' : 'Pengajuan tersimpan. Menunggu persetujuan Owner.', 'success');
    await loadData();
  }

  const [approveTarget, setApproveTarget] = useState(null);
  const [alasanDarurat, setAlasanDarurat] = useState('');

  async function reviewDocument(document, action, note = null, darurat = null) {
    setSaving(true);
    const { error } = await supabase.rpc('review_piutang_request', {
      p_document_id: document.id,
      p_action: action,
      p_catatan: note,
      p_alasan_darurat: darurat || null,
    });
    setSaving(false);
    if (error) return showToast(`Gagal memproses persetujuan: ${error.message}`);
    setRejectTarget(null);
    setApproveTarget(null);
    setAlasanDarurat('');
    showToast(action === 'setujui' ? 'Pengajuan disetujui dan siap diserahkan.' : 'Pengajuan ditolak.', 'success');
    await loadData();
  }

  function openDisbursement(document) {
    setDisburseTarget(document);
    setDisburseForm({
      metode: 'tunai',
      penerima: document.pihak_nama_snapshot,
      identitas: '',
      rekening_id: rekeningList[0]?.id || '',
    });
  }

  async function handleDisbursement(event) {
    event.preventDefault();
    setSaving(true);
    const { error } = await supabase.rpc('disburse_piutang_document', {
      p_document_id: disburseTarget.id,
      p_metode_penyerahan: disburseForm.metode,
      p_nama_penerima: disburseForm.penerima,
      p_rekening_kas_id: disburseForm.rekening_id || null,
      p_nomor_identitas: disburseForm.identitas || null,
    });
    setSaving(false);
    if (error) return showToast(`Gagal mencatat penyerahan uang: ${error.message}`);
    setDisburseTarget(null);
    showToast('Uang diserahkan, kas keluar dan pinjaman sudah tercatat.', 'success');
    await loadData();
  }

  function openRepayment(document) {
    setRepaymentTarget(document);
    setRepaymentForm({
      jumlah: calculateRemaining(document),
      metode: document.metode_pelunasan === 'potong_gaji' ? 'potong_gaji' : document.metode_pelunasan === 'potong_upah' ? 'potong_upah' : 'tunai',
      tanggal: getTodayISO(),
      rekening_id: rekeningList[0]?.id || '',
      keterangan: '',
    });
  }

  async function handleRepayment(event) {
    event.preventDefault();
    setSaving(true);
    const { error } = await supabase.rpc('record_piutang_repayment', {
      p_document_id: repaymentTarget.id,
      p_jumlah: Number(repaymentForm.jumlah),
      p_metode: repaymentForm.metode,
      p_tanggal: repaymentForm.tanggal,
      p_keterangan: repaymentForm.keterangan || null,
      p_rekening_kas_id: ['tunai', 'transfer'].includes(repaymentForm.metode) ? repaymentForm.rekening_id || null : null,
    });
    setSaving(false);
    if (error) return showToast(`Gagal mencatat pengembalian: ${error.message}`);
    setRepaymentTarget(null);
    showToast('Pengembalian tercatat dan sisa pinjaman diperbarui.', 'success');
    await loadData();
  }

  async function handleCancel(reason) {
    setSaving(true);
    const { error } = await supabase.rpc('cancel_piutang_document', {
      p_document_id: cancelTarget.id,
      p_alasan: reason,
    });
    setSaving(false);
    if (error) return showToast(`Gagal membatalkan dokumen: ${error.message}`);
    setCancelTarget(null);
    showToast('Dokumen dibatalkan dan transaksi balik sudah dibuat bila diperlukan.', 'success');
    await loadData();
  }

  async function handleCancelRepayment(reason) {
    setSaving(true);
    const { error } = await supabase.rpc('cancel_piutang_repayment', {
      p_payment_id: cancelRepaymentTarget.id,
      p_alasan: reason,
    });
    setSaving(false);
    if (error) return showToast(`Gagal membatalkan pengembalian: ${error.message}`);
    setCancelRepaymentTarget(null);
    showToast('Pengembalian dibatalkan dan transaksi balik sudah dibuat.', 'success');
    await loadData();
  }

  async function handleReconcileLegacyPanjar(reason) {
    setSaving(true);
    const { error } = await supabase.rpc('reconcile_legacy_panjar_opening', {
      p_panjar_id: reconcileTarget.id,
      p_alasan: reason,
    });
    setSaving(false);
    if (error) return showToast(`Gagal mencocokkan data lama: ${error.message}`);
    setReconcileTarget(null);
    showToast('Catatan awal pinjaman lama berhasil dilengkapi tanpa mengubah Buku Kas.', 'success', 5000);
    await loadData();
  }

  function exportDocuments() {
    exportToExcel(filteredDocuments.map((document) => ({
      nomor: document.nomor_bukti,
      tanggal: document.tanggal_pengajuan,
      pihak: getPartyLabel(document.pihak_type),
      nama: document.pihak_nama_snapshot,
      jumlah: Number(document.jumlah),
      sisa: calculateRemaining(document),
      status: STATUS_META[document.status]?.label || document.status,
      pelunasan: METHOD_LABELS[document.metode_pelunasan],
    })), [
      { key: 'nomor', label: 'Nomor Bukti' }, { key: 'tanggal', label: 'Tanggal' },
      { key: 'pihak', label: 'Jenis Pihak' }, { key: 'nama', label: 'Nama' },
      { key: 'jumlah', label: 'Jumlah' }, { key: 'sisa', label: 'Sisa' },
      { key: 'status', label: 'Status' }, { key: 'pelunasan', label: 'Cara Pengembalian' },
    ], 'Pinjaman_dan_Panjar', 'Dokumen Pinjaman');
  }

  const printDocument = selectedDocument;
  const printRemaining = calculateRemaining(printDocument);

  return (
    <AppShell title="Pinjaman & Panjar" subtitle="Uang CB yang diberikan kepada pihak lain dan masih harus dikembalikan atau dipotong">
      {toast && <div className="toast-container"><div className={`toast toast-${toast.type}`}><span>{toast.message}</span></div></div>}

      <div className="page-header no-print">
        <div>
          <p className="page-description">Panjar Mitra dipotong dari Kwitansi TBS. Pinjaman karyawan dan sopir dicatat terpisah dari Dana Trip.</p>
        </div>
        <div className="flex gap-sm" style={{ flexWrap: 'wrap' }}>
          <button className="btn btn-outline btn-sm" onClick={exportDocuments}>Export Excel</button>
          <button className="btn btn-primary btn-sm" onClick={() => openRequest()}><HandCoins size={17} /> Ajukan Pemberian Uang</button>
        </div>
      </div>

      {summary.anomaly && (
        <div className="alert alert-warning no-print" style={{ marginBottom: 'var(--space-lg)' }}>
          <div style={{ flex: 1 }}>
            <strong>Data lama perlu dicocokkan:</strong> ada pengurangan pinjaman/panjar sebesar {formatRupiah(summary.unmatchedReduction)} yang belum mempunyai catatan pemberian uang awal. Cocokkan dengan panjar dan kwitansi lama sebelum membuat koreksi.
          </div>
          {canApprove && legacyPanjarIssues.length > 0 && (
            <button className="btn btn-outline btn-sm" onClick={() => setReconcileTarget(legacyPanjarIssues[0])}>Cocokkan Data Lama</button>
          )}
        </div>
      )}

      <div className="stats-grid no-print" style={{ gridTemplateColumns: 'repeat(4, minmax(0, 1fr))', marginBottom: 'var(--space-xl)' }}>
        <div className="stat-card"><WalletCards size={20} /><div className="stat-label">Pinjaman Belum Kembali</div><div className="stat-value" style={{ fontSize: 24 }}>{formatRupiah(summary.totalOutstanding)}</div></div>
        <div className="stat-card"><ShieldCheck size={20} /><div className="stat-label">Menunggu Owner</div><div className="stat-value">{summary.waiting}</div></div>
        <div className="stat-card"><BanknoteArrowDown size={20} /><div className="stat-label">Siap Diserahkan</div><div className="stat-value">{summary.ready}</div></div>
        <div className="stat-card"><RotateCcw size={20} /><div className="stat-label">Belum Lunas</div><div className="stat-value">{summary.open}</div></div>
      </div>

      <section className="card no-print">
        <div className="card-header" style={{ gap: 12, flexWrap: 'wrap' }}>
          <div>
            <div className="card-title">Dokumen & Riwayat Pinjaman</div>
            <div className="text-tertiary text-sm">Kwitansi Pembayaran TBS tetap dikelola di menu Kwitansi & Pembayaran Mitra.</div>
          </div>
          <select className="form-input form-select" value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)} style={{ maxWidth: 220 }}>
            <option value="aktif">Pinjaman Aktif</option>
            <option value="menunggu_persetujuan">Menunggu Persetujuan</option>
            <option value="disetujui">Siap Diserahkan</option>
            <option value="diserahkan">Belum Lunas</option>
            <option value="lunas">Riwayat Lunas</option>
            <option value="semua">Semua Riwayat</option>
          </select>
        </div>

        {loading ? <div className="skeleton" style={{ height: 220 }} /> : filteredDocuments.length === 0 ? (
          <div className="empty-state"><FileText className="empty-state-icon" /><div className="empty-state-title">Belum ada dokumen pada status ini</div><div className="empty-state-text">Buat pengajuan pemberian uang untuk memulai alur persetujuan.</div></div>
        ) : (
          <div className="table-container" style={{ border: 'none' }}>
            <table className="table piutang-table">
              <thead><tr><th>Dokumen</th><th>Penerima</th><th>Status</th><th style={{ textAlign: 'right' }}>Jumlah / Sisa</th><th>Aksi</th></tr></thead>
              <tbody>{filteredDocuments.map((document) => {
                const status = STATUS_META[document.status] || STATUS_META.dibatalkan;
                const remaining = calculateRemaining(document);
                return (
                  <tr key={document.id} className={selectedDocument?.id === document.id ? 'row-highlight' : ''} onClick={() => setSelectedDocument(document)}>
                    <td><strong>{document.nomor_bukti}</strong><div className="text-tertiary text-xs">{formatDateDisplay(document.tanggal_pengajuan)} / {getDocumentTitle(document)}</div></td>
                    <td><strong>{document.pihak_nama_snapshot}</strong><div className="text-tertiary text-xs">{getPartyLabel(document.pihak_type)} / {METHOD_LABELS[document.metode_pelunasan]}</div></td>
                    <td><span className={`badge ${status.badge}`}>{status.label}</span>{document.tanggal_jatuh_tempo && <div className="text-tertiary text-xs">Target {formatDateDisplay(document.tanggal_jatuh_tempo)}</div>}</td>
                    <td className="table-mono" style={{ textAlign: 'right' }}><strong>{formatRupiah(document.jumlah)}</strong><div className={remaining > 0 ? 'text-warning text-xs' : 'text-success text-xs'}>Sisa {formatRupiah(remaining)}</div></td>
                    <td onClick={(event) => event.stopPropagation()}><div className="flex gap-xs" style={{ flexWrap: 'wrap' }}>
                      {canApprove && document.status === 'menunggu_persetujuan' && <button className="btn btn-primary btn-sm" disabled={saving} onClick={() => {
                        if (userRole === 'super_admin') {
                          setApproveTarget(document);
                          setAlasanDarurat('');
                        } else {
                          reviewDocument(document, 'setujui');
                        }
                      }}><Check size={15} /> Setujui</button>}
                      {canApprove && document.status === 'menunggu_persetujuan' && <button className="btn btn-outline btn-sm" onClick={() => setRejectTarget(document)}>Tolak</button>}
                      {document.status === 'disetujui' && <button className="btn btn-primary btn-sm" onClick={() => openDisbursement(document)}><BanknoteArrowDown size={15} /> Serahkan</button>}
                      {document.status === 'diserahkan' && document.jenis_dokumen !== 'panjar_mitra' && <button className="btn btn-outline btn-sm" onClick={() => openRepayment(document)}><RotateCcw size={15} /> Pengembalian</button>}
                      {['diserahkan', 'lunas'].includes(document.status) && <button className="btn btn-ghost btn-sm" title="Cetak bukti" onClick={() => { setSelectedDocument(document); setPrintRepayment(null); window.setTimeout(() => window.print(), 50); }}><Printer size={16} /></button>}
                      {canApprove && !['lunas', 'ditolak', 'dibatalkan'].includes(document.status) && <button className="btn btn-ghost btn-sm" onClick={() => setCancelTarget(document)}>Batalkan</button>}
                    </div></td>
                  </tr>
                );
              })}</tbody>
            </table>
          </div>
        )}
      </section>

      {selectedDocument && (
        <section className="card no-print" style={{ marginTop: 'var(--space-xl)' }}>
          <div className="card-header">
            <div><div className="card-title">Riwayat {selectedDocument.nomor_bukti}</div><div className="text-tertiary text-sm">{selectedDocument.pihak_nama_snapshot} / {selectedDocument.tujuan}</div></div>
            {['diserahkan', 'lunas'].includes(selectedDocument.status) && <button className="btn btn-outline btn-sm" onClick={() => { setPrintRepayment(null); window.setTimeout(() => window.print(), 50); }}><Printer size={16} /> Bukti Pemberian</button>}
          </div>
          {selectedDocument.panjar_mitra?.pembayaran_mitra_kwitansi ? (
            <div className="alert alert-info" style={{ alignItems: 'center' }}>
              <div style={{ flex: 1 }}><strong>Lunas melalui Kwitansi Pembayaran TBS.</strong><div className="text-sm">Periode {formatDateDisplay(selectedDocument.panjar_mitra.pembayaran_mitra_kwitansi.periode_dari)} sampai {formatDateDisplay(selectedDocument.panjar_mitra.pembayaran_mitra_kwitansi.periode_sampai)}.</div></div>
              <Link className="btn btn-outline btn-sm" href={`/owner/kwitansi-mitra?mitra=${selectedDocument.master_mitra_id}&dari=${selectedDocument.panjar_mitra.pembayaran_mitra_kwitansi.periode_dari}&sampai=${selectedDocument.panjar_mitra.pembayaran_mitra_kwitansi.periode_sampai}`}>Lihat Kwitansi TBS</Link>
            </div>
          ) : (selectedDocument.piutang_pelunasan || []).filter((item) => item.status === 'aktif').length === 0 ? (
            <p className="text-tertiary text-sm">Belum ada pengembalian yang dicatat.</p>
          ) : (
            <div className="table-container" style={{ border: 0 }}><table className="table"><thead><tr><th>Tanggal</th><th>Nomor Bukti</th><th>Metode</th><th style={{ textAlign: 'right' }}>Jumlah</th><th>Aksi</th></tr></thead><tbody>
              {selectedDocument.piutang_pelunasan.filter((item) => item.status === 'aktif').map((item) => <tr key={item.id}><td>{formatDateDisplay(item.tanggal)}</td><td><strong>{item.nomor_bukti}</strong></td><td>{METHOD_LABELS[item.metode] || item.metode}</td><td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(item.jumlah)}</td><td><div className="flex gap-xs"><button className="btn btn-ghost btn-sm" title="Cetak bukti pengembalian" onClick={() => { setPrintRepayment(item); window.setTimeout(() => window.print(), 50); }}><Printer size={16} /></button>{canApprove && <button className="btn btn-ghost btn-sm" onClick={() => setCancelRepaymentTarget(item)}>Batalkan</button>}</div></td></tr>)}
            </tbody></table></div>
          )}
        </section>
      )}

      {requestOpen && (
        <div className="modal-overlay" onClick={() => !saving && setRequestOpen(false)}><div className="modal" onClick={(event) => event.stopPropagation()}>
          <div className="modal-header"><div><h3 className="modal-title">Ajukan Pemberian Uang</h3><p className="text-tertiary text-sm">Pencatatan ini belum mengurangi kas sampai uang benar-benar diserahkan.</p></div><button className="modal-close" onClick={() => setRequestOpen(false)}><X size={18} /></button></div>
          <form onSubmit={handleCreateRequest}><div className="modal-body">
            <div className="form-grid"><div className="form-group"><label className="form-label form-label-required">Penerima</label><select className="form-input form-select" value={requestForm.pihak_type} onChange={(event) => { const type = event.target.value; setRequestForm(createEmptyRequest(type)); }}>{PARTY_TYPES.map((type) => <option key={type.value} value={type.value}>{type.label}</option>)}</select></div><div className="form-group"><label className="form-label form-label-required">Tanggal Pengajuan</label><input type="date" className="form-input" value={requestForm.tanggal} onChange={(event) => setRequestForm({ ...requestForm, tanggal: event.target.value })} required /></div></div>
            {requestForm.pihak_type === 'mitra' && <div className="form-group"><label className="form-label form-label-required">Mitra</label><select className="form-input form-select" value={requestForm.master_mitra_id} onChange={(event) => setRequestForm({ ...requestForm, master_mitra_id: event.target.value })} required><option value="">Pilih mitra</option>{mitraList.map((item) => <option key={item.id} value={item.id}>{item.kode} - {item.nama}</option>)}</select></div>}
            {requestForm.pihak_type === 'petani' && <div className="form-group"><label className="form-label form-label-required">Petani</label><select className="form-input form-select" value={requestForm.petani_id} onChange={(event) => setRequestForm({ ...requestForm, petani_id: event.target.value })} required><option value="">Pilih petani</option>{petaniList.map((item) => <option key={item.id} value={item.id}>{item.nama}</option>)}</select></div>}
            {requestForm.pihak_type === 'sopir' && <div className="form-group"><label className="form-label form-label-required">Sopir</label><select className="form-input form-select" value={requestForm.sopir_id} onChange={(event) => setRequestForm({ ...requestForm, sopir_id: event.target.value })} required><option value="">Pilih sopir</option>{sopirList.map((item) => <option key={item.id} value={item.id}>{item.nama}{item.plat_nomor ? ` - ${item.plat_nomor}` : ''}</option>)}</select><div className="form-hint">Dana Trip bukan pinjaman. Gunakan halaman operasional armada untuk Dana Trip.</div></div>}
            {['karyawan', 'lainnya'].includes(requestForm.pihak_type) && <div className="form-group"><label className="form-label form-label-required">Nama Lengkap Penerima</label><input className="form-input" value={requestForm.pihak_nama_manual} onChange={(event) => setRequestForm({ ...requestForm, pihak_nama_manual: event.target.value })} required /></div>}
            <div className="form-grid"><div className="form-group"><label className="form-label form-label-required">Jumlah (Rp)</label><input type="number" min="1" className="form-input form-input-mono" value={requestForm.jumlah} onChange={(event) => setRequestForm({ ...requestForm, jumlah: event.target.value })} required /></div><div className="form-group"><label className="form-label">Target Pengembalian</label><input type="date" min={requestForm.tanggal} className="form-input" value={requestForm.tanggal_jatuh_tempo} onChange={(event) => setRequestForm({ ...requestForm, tanggal_jatuh_tempo: event.target.value })} /></div></div>
            <div className="form-group"><label className="form-label form-label-required">Cara Pengembalian</label><select className="form-input form-select" value={requestForm.metode_pelunasan} onChange={(event) => setRequestForm({ ...requestForm, metode_pelunasan: event.target.value })}>{getRepaymentOptions(requestForm.pihak_type).map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}</select></div>
            <div className="form-group"><label className="form-label form-label-required">Keperluan Uang</label><textarea className="form-input" rows="3" value={requestForm.tujuan} onChange={(event) => setRequestForm({ ...requestForm, tujuan: event.target.value })} placeholder="Contoh: kebutuhan operasional kebun / keperluan keluarga" required /></div>
            <div className="form-group"><label className="form-label">Catatan</label><input className="form-input" value={requestForm.catatan} onChange={(event) => setRequestForm({ ...requestForm, catatan: event.target.value })} placeholder="Opsional" /></div>
          </div><div className="modal-footer"><button type="button" className="btn btn-outline" onClick={() => setRequestOpen(false)}>Batal</button><button className="btn btn-primary" disabled={saving}>{saving ? 'Menyimpan...' : canApprove ? 'Simpan & Setujui' : 'Kirim ke Owner'}</button></div></form>
        </div></div>
      )}

      {disburseTarget && (
        <div className="modal-overlay" onClick={() => !saving && setDisburseTarget(null)}><div className="modal" onClick={(event) => event.stopPropagation()}>
          <div className="modal-header"><div><h3 className="modal-title">Serahkan Uang</h3><p className="text-tertiary text-sm">{disburseTarget.nomor_bukti} / {formatRupiah(disburseTarget.jumlah)}</p></div><button className="modal-close" onClick={() => setDisburseTarget(null)}><X size={18} /></button></div>
          <form onSubmit={handleDisbursement}><div className="modal-body"><div className="form-grid"><div className="form-group"><label className="form-label form-label-required">Metode</label><select className="form-input form-select" value={disburseForm.metode} onChange={(event) => setDisburseForm({ ...disburseForm, metode: event.target.value })}><option value="tunai">Tunai</option><option value="transfer">Transfer</option></select></div><div className="form-group"><label className="form-label form-label-required">Rekening Kas</label><select className="form-input form-select" value={disburseForm.rekening_id} onChange={(event) => setDisburseForm({ ...disburseForm, rekening_id: event.target.value })} required><option value="">Pilih kas</option>{rekeningList.map((item) => <option key={item.id} value={item.id}>{item.nama}</option>)}</select></div></div><div className="form-group"><label className="form-label form-label-required">Nama yang Menerima Uang</label><input className="form-input" value={disburseForm.penerima} onChange={(event) => setDisburseForm({ ...disburseForm, penerima: event.target.value })} required /></div><div className="form-group"><label className="form-label">Nomor Identitas / Catatan Penerima</label><input className="form-input" value={disburseForm.identitas} onChange={(event) => setDisburseForm({ ...disburseForm, identitas: event.target.value })} placeholder="Opsional" /></div><div className="alert alert-info"><strong>Setelah dikonfirmasi:</strong> kas CB berkurang dan pinjaman penerima bertambah. Cetak bukti lalu minta tanda tangan penerima.</div></div><div className="modal-footer"><button type="button" className="btn btn-outline" onClick={() => setDisburseTarget(null)}>Batal</button><button className="btn btn-primary" disabled={saving}>{saving ? 'Mencatat...' : 'Konfirmasi Penyerahan'}</button></div></form>
        </div></div>
      )}

      {repaymentTarget && (
        <div className="modal-overlay" onClick={() => !saving && setRepaymentTarget(null)}><div className="modal" onClick={(event) => event.stopPropagation()}>
          <div className="modal-header"><div><h3 className="modal-title">Catat Pengembalian</h3><p className="text-tertiary text-sm">Sisa {formatRupiah(calculateRemaining(repaymentTarget))}</p></div><button className="modal-close" onClick={() => setRepaymentTarget(null)}><X size={18} /></button></div>
          <form onSubmit={handleRepayment}><div className="modal-body"><div className="form-grid"><div className="form-group"><label className="form-label form-label-required">Jumlah</label><input type="number" min="1" max={calculateRemaining(repaymentTarget)} className="form-input form-input-mono" value={repaymentForm.jumlah} onChange={(event) => setRepaymentForm({ ...repaymentForm, jumlah: event.target.value })} required /></div><div className="form-group"><label className="form-label form-label-required">Tanggal</label><input type="date" className="form-input" value={repaymentForm.tanggal} onChange={(event) => setRepaymentForm({ ...repaymentForm, tanggal: event.target.value })} required /></div></div><div className="form-group"><label className="form-label form-label-required">Cara Pengembalian</label><select className="form-input form-select" value={repaymentForm.metode} onChange={(event) => setRepaymentForm({ ...repaymentForm, metode: event.target.value })}><option value="tunai">Tunai</option><option value="transfer">Transfer</option>{repaymentTarget.metode_pelunasan === 'potong_gaji' && <option value="potong_gaji">Potong Gaji</option>}{repaymentTarget.metode_pelunasan === 'potong_upah' && <option value="potong_upah">Potong Upah</option>}</select></div>{['tunai', 'transfer'].includes(repaymentForm.metode) && <div className="form-group"><label className="form-label form-label-required">Rekening Kas Penerima</label><select className="form-input form-select" value={repaymentForm.rekening_id} onChange={(event) => setRepaymentForm({ ...repaymentForm, rekening_id: event.target.value })} required><option value="">Pilih kas</option>{rekeningList.map((item) => <option key={item.id} value={item.id}>{item.nama}</option>)}</select></div>}<div className="form-group"><label className="form-label">Keterangan</label><input className="form-input" value={repaymentForm.keterangan} onChange={(event) => setRepaymentForm({ ...repaymentForm, keterangan: event.target.value })} /></div></div><div className="modal-footer"><button type="button" className="btn btn-outline" onClick={() => setRepaymentTarget(null)}>Batal</button><button className="btn btn-primary" disabled={saving}>{saving ? 'Menyimpan...' : 'Simpan Pengembalian'}</button></div></form>
        </div></div>
      )}

      <PromptDialog open={!!rejectTarget} title="Tolak Pengajuan" message={rejectTarget ? `${rejectTarget.nomor_bukti} atas nama ${rejectTarget.pihak_nama_snapshot} akan ditolak.` : ''} label="Alasan penolakan" placeholder="Jelaskan alasan agar admin dapat menindaklanjuti" confirmText="Tolak Pengajuan" cancelText="Kembali" variant="danger" loading={saving} onConfirm={(reason) => reviewDocument(rejectTarget, 'tolak', reason)} onCancel={() => !saving && setRejectTarget(null)} />
      <PromptDialog open={!!cancelTarget} title="Batalkan Dokumen" message={cancelTarget ? `${cancelTarget.nomor_bukti} akan dibatalkan. Jika uang sudah diserahkan, sistem membuat transaksi balik kas dan pinjaman.` : ''} label="Alasan pembatalan" placeholder="Contoh: salah nominal atau pengajuan dibatalkan penerima" confirmText="Batalkan Dokumen" cancelText="Kembali" variant="danger" loading={saving} onConfirm={handleCancel} onCancel={() => !saving && setCancelTarget(null)} />
      <PromptDialog open={!!cancelRepaymentTarget} title="Batalkan Pengembalian" message={cancelRepaymentTarget ? `${cancelRepaymentTarget.nomor_bukti} sebesar ${formatRupiah(cancelRepaymentTarget.jumlah)} akan dibuatkan transaksi balik.` : ''} label="Alasan pembatalan" placeholder="Contoh: salah nominal atau pembayaran ganda" confirmText="Batalkan Pengembalian" cancelText="Kembali" variant="danger" loading={saving} onConfirm={handleCancelRepayment} onCancel={() => !saving && setCancelRepaymentTarget(null)} />
      <PromptDialog
        open={!!reconcileTarget}
        title="Cocokkan Data Lama"
        message={reconcileTarget ? `Lengkapi catatan awal ${formatRupiah(reconcileTarget.jumlah)} untuk ${mitraList.find((item) => item.id === reconcileTarget.mitra_id)?.kode || 'Mitra'} tanggal ${formatDateDisplay(reconcileTarget.tanggal)}. Tindakan ini tidak mengubah Buku Kas dan hanya boleh dilakukan setelah bukti/konfirmasi Owner diperiksa.` : ''}
        label="Dasar pencocokan"
        placeholder="Contoh: sesuai buku panjar Owner tanggal 13-07-2026"
        confirmText="Lengkapi Catatan Awal"
        cancelText="Kembali"
        variant="warning"
        loading={saving}
        onConfirm={handleReconcileLegacyPanjar}
        onCancel={() => !saving && setReconcileTarget(null)}
      />

      {printDocument && !printRepayment && (
        <article className="piutang-print-area">
          <header className="piutang-print-header"><BrandMark branding={branding} mode="print" size={78} /><div><h1>{getDocumentTitle(printDocument)}</h1><p>{branding.appName}</p><p className="piutang-print-number">Nomor: {printDocument.nomor_bukti}</p></div></header>
          <p className="piutang-print-intro">Pada tanggal <strong>{formatDateDisplay(printDocument.tanggal_pengajuan)}</strong>, CB telah menyerahkan uang kepada pihak berikut:</p>
          <dl className="piutang-print-grid"><dt>Nama penerima</dt><dd>{printDocument.nama_penerima || printDocument.pihak_nama_snapshot}</dd><dt>Jenis pihak</dt><dd>{getPartyLabel(printDocument.pihak_type)}</dd><dt>Jumlah</dt><dd><strong>{formatRupiah(printDocument.jumlah)}</strong></dd><dt>Keperluan</dt><dd>{printDocument.tujuan}</dd><dt>Cara pengembalian</dt><dd>{METHOD_LABELS[printDocument.metode_pelunasan]}</dd><dt>Target pengembalian</dt><dd>{printDocument.tanggal_jatuh_tempo ? formatDateDisplay(printDocument.tanggal_jatuh_tempo) : 'Mengikuti pembayaran/transaksi berikutnya'}</dd><dt>Sisa saat dicetak</dt><dd>{formatRupiah(printRemaining)}</dd></dl>
          <div className="piutang-print-note">Penerima menyatakan telah menerima uang tersebut dan menyetujui cara pengembalian yang tercantum. Dokumen ini berbeda dari Kwitansi Pembayaran TBS Mitra.</div>
          <div className="piutang-signatures"><div><span>Disetujui Owner</span><div className="signature-line" /></div><div><span>Yang Menyerahkan</span><div className="signature-line" /></div><div><span>Yang Menerima</span><div className="signature-line" /><strong>{printDocument.nama_penerima || printDocument.pihak_nama_snapshot}</strong></div></div>
          <footer>Dokumen dibuat oleh sistem {branding.appName}. Simpan dokumen bertanda tangan sebagai bukti penyerahan uang.</footer>
        </article>
      )}

      {printDocument && printRepayment && (
        <article className="piutang-print-area">
          <header className="piutang-print-header"><BrandMark branding={branding} mode="print" size={78} /><div><h1>Bukti Pengembalian Uang</h1><p>{branding.appName}</p><p className="piutang-print-number">Nomor: {printRepayment.nomor_bukti}</p></div></header>
          <p className="piutang-print-intro">Pada tanggal <strong>{formatDateDisplay(printRepayment.tanggal)}</strong>, CB telah menerima pengembalian uang dengan rincian berikut:</p>
          <dl className="piutang-print-grid"><dt>Diterima dari</dt><dd>{printDocument.pihak_nama_snapshot}</dd><dt>Dokumen awal</dt><dd>{printDocument.nomor_bukti}</dd><dt>Jumlah diterima</dt><dd><strong>{formatRupiah(printRepayment.jumlah)}</strong></dd><dt>Metode</dt><dd>{METHOD_LABELS[printRepayment.metode] || printRepayment.metode}</dd><dt>Keterangan</dt><dd>{printRepayment.keterangan || 'Pengembalian pinjaman'}</dd><dt>Sisa setelah pembayaran</dt><dd>{formatRupiah(printRemaining)}</dd></dl>
          <div className="piutang-signatures"><div><span>Yang Membayar</span><div className="signature-line" /><strong>{printDocument.pihak_nama_snapshot}</strong></div><div><span>Yang Menerima untuk CB</span><div className="signature-line" /></div></div>
          <footer>Dokumen ini adalah bukti pengembalian uang, bukan Kwitansi Pembayaran TBS Mitra.</footer>
        </article>
      )}

      <style jsx global>{`
        .row-highlight { background: rgba(52, 211, 153, 0.06); }
        .piutang-print-area { display: none; }
        @media (max-width: 900px) {
          .stats-grid { grid-template-columns: repeat(2, minmax(0, 1fr)) !important; }
          .piutang-table { min-width: 850px; }
        }
        @media print {
          @page { size: A4 portrait; margin: 14mm; }
          body * { visibility: hidden !important; }
          .piutang-print-area, .piutang-print-area * { visibility: visible !important; }
          .piutang-print-area { display: block !important; position: absolute; inset: 0; width: 100%; color: #111; background: #fff; font-family: Arial, sans-serif; font-size: 12px; }
          .piutang-print-header { display: flex; align-items: center; gap: 18px; padding-bottom: 16px; border-bottom: 2px solid #111; }
          .piutang-print-header h1 { margin: 0 0 4px; font-size: 22px; text-transform: uppercase; letter-spacing: 0; }
          .piutang-print-header p { margin: 2px 0; }
          .piutang-print-number { font-family: monospace; }
          .piutang-print-intro { margin: 28px 0 18px; line-height: 1.7; }
          .piutang-print-grid { display: grid; grid-template-columns: 170px 1fr; margin: 0; border: 1px solid #444; }
          .piutang-print-grid dt, .piutang-print-grid dd { margin: 0; padding: 10px 12px; border-bottom: 1px solid #bbb; }
          .piutang-print-grid dt { font-weight: 700; background: #f2f2f2 !important; }
          .piutang-print-note { margin-top: 18px; border: 1px solid #777; padding: 12px; line-height: 1.6; }
          .piutang-signatures { display: grid; grid-template-columns: repeat(3, 1fr); gap: 32px; margin-top: 44px; text-align: center; }
          .signature-line { height: 78px; border-bottom: 1px solid #111; margin-bottom: 8px; }
          .piutang-print-area footer { margin-top: 36px; border-top: 1px solid #aaa; padding-top: 10px; font-size: 10px; color: #444; }
        }
      `}</style>
    </AppShell>
  );
}
