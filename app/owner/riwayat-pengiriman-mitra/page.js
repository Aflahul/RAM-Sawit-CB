'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import {
  formatMitraLabel,
  formatSopirArmadaDescription,
  formatSopirArmadaLabel,
  getMitraSearchText,
  getSopirArmadaSearchText,
} from '@/lib/display-labels';
import { paginateRows } from '@/lib/pagination-utils';
import { getNextSort, sortRows } from '@/lib/sort-utils';
import { supabase } from '@/lib/supabase';
import { formatRupiah, getTodayISO } from '@/lib/utils';
import { Ban, Pencil, RefreshCw } from 'lucide-react';

const SOPIR_AKTUAL_DEFAULT = 'default';
const SOPIR_AKTUAL_MASTER = 'master';
const SOPIR_AKTUAL_MANUAL = 'manual';
const TABLE_PAGE_SIZE = 20;

const emptyEditForm = {
  tanggal: '',
  sopir_default_id: '',
  sopir_default_nama: '',
  mitra_id: '',
  plat_nomor: '',
  sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
  sopir_aktual_id: '',
  sopir_aktual_nama: '',
  sopir_aktual_no_hp: '',
  catatan_sopir: '',
  tonase: '',
  harga_dasar: 0,
  fee_owner_history_id: '',
  fee_owner_per_kg: 0,
  harga_harian: 0,
  total_kotor: 0,
  total_fee_owner: 0,
  alasan_edit: '',
};

function toNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function getRowSearchText(row) {
  return [
    row.tanggal,
    formatMitraLabel(row.master_mitra),
    row.sopir_default_nama,
    row.sopir_aktual_nama,
    row.plat_nomor,
    row.status,
    row.alasan_batal,
    row.alasan_edit,
  ].filter(Boolean).join(' ').toLowerCase();
}

const riwayatSortAccessors = {
  tanggal: row => row.tanggal,
  mitra: row => formatMitraLabel(row.master_mitra),
  sopir: row => row.sopir_aktual_nama || row.sopir_default_nama,
  plat: row => row.plat_nomor,
  status: row => row.status,
  tonase: row => toNumber(row.tonase),
  harga_bersih: row => toNumber(row.harga_bersih_per_kg ?? row.harga_harian),
  nilai_bersih: row => toNumber(row.total_nilai_bersih ?? row.total_kotor),
};

export default function RiwayatPengirimanMitraPage() {
  const [dateFrom, setDateFrom] = useState(getTodayISO);
  const [dateTo, setDateTo] = useState(getTodayISO);
  const [statusFilter, setStatusFilter] = useState('aktif');
  const [search, setSearch] = useState('');
  const [transaksi, setTransaksi] = useState([]);
  const [mitras, setMitras] = useState([]);
  const [sopirs, setSopirs] = useState([]);
  const [feeHistories, setFeeHistories] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [editTarget, setEditTarget] = useState(null);
  const [editForm, setEditForm] = useState(emptyEditForm);
  const [cancelTarget, setCancelTarget] = useState(null);
  const [cancelReason, setCancelReason] = useState('');
  const [sort, setSort] = useState({ key: 'tanggal', direction: 'desc' });
  const [page, setPage] = useState(1);

  const loadData = useCallback(async () => {
    setLoading(true);
    setErrorMsg('');

    let transaksiQuery = supabase
      .from('transaksi_mitra')
      .select(`
        id, tanggal, sopir_id, mitra_id, plat_nomor, tonase, harga_harian, total_kotor,
        harga_pabrik_per_kg, fee_owner_per_kg, harga_bersih_per_kg, total_fee_owner,
        total_nilai_bersih, fee_owner_history_id,
        status, created_at, updated_at, updated_by, alasan_edit, dibatalkan_at, dibatalkan_by, alasan_batal,
        sopir_default_id, sopir_default_nama, sopir_aktual_id, sopir_aktual_nama,
        sopir_aktual_no_hp, sopir_aktual_source, sopir_diganti_dari_default, catatan_sopir,
        master_mitra ( id, kode, alamat, nama, fee_per_kg )
      `)
      .gte('tanggal', dateFrom)
      .lte('tanggal', dateTo)
      .order('created_at', { ascending: false });

    if (statusFilter !== 'semua') {
      transaksiQuery = transaksiQuery.eq('status', statusFilter);
    }

    const [
      { data: trxData, error: trxError },
      { data: mitraData, error: mitraError },
      { data: sopirData, error: sopirError },
      { data: feeHistoryData, error: feeHistoryError },
    ] = await Promise.all([
      transaksiQuery,
      supabase
        .from('master_mitra')
        .select('id, kode, alamat, nama, fee_per_kg')
        .eq('aktif', true)
        .order('kode'),
      supabase
        .from('sopir')
        .select(`
          id, nama, no_hp, plat_nomor, mitra_id,
          master_mitra ( id, kode, alamat, nama, fee_per_kg )
        `)
        .eq('aktif', true)
        .order('nama'),
      supabase
        .from('fee_owner_mitra_history')
        .select('id, master_mitra_id, fee_per_kg, berlaku_mulai, berlaku_sampai, aktif')
        .eq('aktif', true)
        .order('berlaku_mulai', { ascending: false }),
    ]);

    const error = trxError || mitraError || sopirError;
    if (error) {
      console.error('Gagal memuat riwayat pengiriman mitra:', error);
      setErrorMsg(error.message);
      setTransaksi([]);
    } else {
      setTransaksi(trxData || []);
      setMitras(mitraData || []);
      setSopirs(sopirData || []);
      setFeeHistories(feeHistoryError ? [] : feeHistoryData || []);
    }

    setLoading(false);
  }, [dateFrom, dateTo, statusFilter]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  const filteredTransaksi = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return transaksi;
    return transaksi.filter(row => getRowSearchText(row).includes(keyword));
  }, [search, transaksi]);
  const sortedTransaksi = useMemo(() => {
    return sortRows(filteredTransaksi, sort, riwayatSortAccessors);
  }, [filteredTransaksi, sort]);
  const paginatedTransaksi = useMemo(() => {
    return paginateRows(sortedTransaksi, page, TABLE_PAGE_SIZE);
  }, [page, sortedTransaksi]);

  const totals = useMemo(() => {
    return filteredTransaksi
      .filter(row => row.status !== 'dibatalkan')
      .reduce((acc, row) => ({
        tonase: acc.tonase + toNumber(row.tonase),
        total: acc.total + toNumber(row.total_nilai_bersih ?? row.total_kotor),
      }), { tonase: 0, total: 0 });
  }, [filteredTransaksi]);
  const editFeeOwner = toNumber(editForm.fee_owner_per_kg);

  function handleSort(key) {
    setPage(1);
    setSort(current => getNextSort(current, key, key === 'tanggal' ? 'desc' : 'asc'));
  }

  function getEffectiveFeeSnapshot(mitraId, tanggal) {
    const fallbackMitra = mitras.find(item => item.id === mitraId);
    const tanggalValue = tanggal || getTodayISO();
    const history = feeHistories.find(item => {
      if (item.master_mitra_id !== mitraId) return false;
      if (item.berlaku_mulai && tanggalValue < item.berlaku_mulai) return false;
      if (item.berlaku_sampai && tanggalValue > item.berlaku_sampai) return false;
      return true;
    });

    return {
      fee: toNumber(history?.fee_per_kg ?? fallbackMitra?.fee_per_kg),
      historyId: history?.id || '',
    };
  }

  function applyFeeSnapshot(nextForm, mitraId = nextForm.mitra_id, tanggal = nextForm.tanggal) {
    const snapshot = getEffectiveFeeSnapshot(mitraId, tanggal);

    return {
      ...nextForm,
      mitra_id: mitraId,
      fee_owner_per_kg: snapshot.fee,
      fee_owner_history_id: snapshot.historyId,
    };
  }

  function recalculateTotals(nextForm) {
    const feeOwner = toNumber(nextForm.fee_owner_per_kg);
    const hargaHarian = Math.max(toNumber(nextForm.harga_dasar) - feeOwner, 0);
    const tonase = toNumber(nextForm.tonase);

    return {
      ...nextForm,
      harga_harian: hargaHarian,
      total_kotor: Math.round(tonase * hargaHarian),
      total_fee_owner: Math.round(tonase * feeOwner),
    };
  }

  function openEdit(row) {
    const isManual = row.sopir_aktual_source === 'manual';
    const isDefault = !isManual && String(row.sopir_aktual_id || '') === String(row.sopir_default_id || row.sopir_id || '');
    const effectiveFee = getEffectiveFeeSnapshot(row.mitra_id, row.tanggal);
    const fallbackFee = toNumber(row.fee_owner_per_kg ?? effectiveFee.fee ?? row.master_mitra?.fee_per_kg);
    const hargaDasar = toNumber(row.harga_pabrik_per_kg ?? (toNumber(row.harga_harian) + fallbackFee));

    setEditTarget(row);
    setEditForm({
      tanggal: row.tanggal || '',
      sopir_default_id: row.sopir_default_id || row.sopir_id || '',
      sopir_default_nama: row.sopir_default_nama || '',
      mitra_id: row.mitra_id || '',
      plat_nomor: row.plat_nomor || '',
      sopir_aktual_mode: isManual ? SOPIR_AKTUAL_MANUAL : isDefault ? SOPIR_AKTUAL_DEFAULT : SOPIR_AKTUAL_MASTER,
      sopir_aktual_id: row.sopir_aktual_id || '',
      sopir_aktual_nama: row.sopir_aktual_nama || '',
      sopir_aktual_no_hp: row.sopir_aktual_no_hp || '',
      catatan_sopir: row.catatan_sopir || '',
      tonase: String(row.tonase || ''),
      harga_dasar: hargaDasar,
      fee_owner_history_id: row.fee_owner_history_id || effectiveFee.historyId,
      fee_owner_per_kg: fallbackFee,
      harga_harian: toNumber(row.harga_bersih_per_kg ?? row.harga_harian),
      total_kotor: toNumber(row.total_nilai_bersih ?? row.total_kotor),
      total_fee_owner: toNumber(row.total_fee_owner),
      alasan_edit: '',
    });
  }

  function handleEditSopirDefaultChange(sopirId) {
    const sopir = sopirs.find(item => item.id === sopirId);
    if (!sopir) {
      setEditForm({
        ...editForm,
        sopir_default_id: '',
        sopir_default_nama: '',
        plat_nomor: '',
        sopir_aktual_id: '',
        sopir_aktual_nama: '',
        sopir_aktual_no_hp: '',
      });
      return;
    }

    const nextForm = {
      ...editForm,
      sopir_default_id: sopir.id,
      sopir_default_nama: sopir.nama,
      plat_nomor: sopir.plat_nomor || '',
      mitra_id: sopir.mitra_id || '',
      sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
      sopir_aktual_id: sopir.id,
      sopir_aktual_nama: sopir.nama,
      sopir_aktual_no_hp: sopir.no_hp || '',
    };

    setEditForm(recalculateTotals(applyFeeSnapshot(nextForm, sopir.mitra_id || '', editForm.tanggal)));
  }

  function handleEditMitraChange(mitraId) {
    setEditForm(recalculateTotals(applyFeeSnapshot({ ...editForm }, mitraId, editForm.tanggal)));
  }

  function handleEditTanggalChange(tanggal) {
    setEditForm(recalculateTotals(applyFeeSnapshot({ ...editForm, tanggal }, editForm.mitra_id, tanggal)));
  }

  function handleEditTonaseChange(value) {
    setEditForm(recalculateTotals({ ...editForm, tonase: value }));
  }

  function handleEditHargaDasarChange(value) {
    setEditForm(recalculateTotals({ ...editForm, harga_dasar: value }));
  }

  function handleUseStoredNetAsFactoryPrice() {
    if (!editTarget) return;

    setEditForm(recalculateTotals({
      ...editForm,
      harga_dasar: toNumber(editTarget.harga_harian),
      alasan_edit: editForm.alasan_edit || 'Koreksi harga bersih: Fee Owner belum terpotong pada input awal.',
    }));
  }

  function handleEditSopirAktualModeChange(mode) {
    const defaultSopir = sopirs.find(item => item.id === editForm.sopir_default_id);
    const nextForm = {
      ...editForm,
      sopir_aktual_mode: mode,
      catatan_sopir: mode === SOPIR_AKTUAL_DEFAULT ? '' : editForm.catatan_sopir,
    };

    if (mode === SOPIR_AKTUAL_DEFAULT && defaultSopir) {
      nextForm.sopir_aktual_id = defaultSopir.id;
      nextForm.sopir_aktual_nama = defaultSopir.nama;
      nextForm.sopir_aktual_no_hp = defaultSopir.no_hp || '';
    }

    if (mode === SOPIR_AKTUAL_MASTER || mode === SOPIR_AKTUAL_MANUAL) {
      nextForm.sopir_aktual_id = '';
      nextForm.sopir_aktual_nama = '';
      nextForm.sopir_aktual_no_hp = '';
    }

    setEditForm(nextForm);
  }

  function handleEditSopirAktualMasterChange(sopirId) {
    const sopir = sopirs.find(item => item.id === sopirId);
    setEditForm({
      ...editForm,
      sopir_aktual_id: sopirId,
      sopir_aktual_nama: sopir?.nama || '',
      sopir_aktual_no_hp: sopir?.no_hp || '',
    });
  }

  async function getCurrentUserId() {
    const { data } = await supabase.auth.getUser();
    return data?.user?.id || null;
  }

  async function writeAuditLog(action, beforeJson, afterJson, alasan) {
    const { error } = await supabase.rpc('write_audit_log', {
      p_entity_type: 'transaksi_mitra',
      p_entity_id: beforeJson?.id || afterJson?.id,
      p_action: action,
      p_before_json: beforeJson || null,
      p_after_json: afterJson || null,
      p_alasan: alasan || null,
    });

    if (error) {
      console.warn('Audit log riwayat pengiriman mitra gagal:', error.message);
    }
  }

  async function handleSaveEdit(event) {
    event.preventDefault();
    if (!editTarget || saving) return;

    const tonase = toNumber(editForm.tonase);
    if (!editForm.sopir_default_id) return alert('Pilih armada / sopir default.');
    if (!editForm.mitra_id) return alert('Pilih mitra transaksi.');
    if (!editForm.sopir_aktual_nama.trim()) return alert('Sopir aktual wajib diisi.');
    if (tonase <= 0) return alert('Tonase harus lebih dari 0.');
    if (!editForm.alasan_edit.trim()) return alert('Alasan edit wajib diisi.');

    setSaving(true);
    const userId = await getCurrentUserId();
    const sopirDiganti = editForm.sopir_aktual_mode === SOPIR_AKTUAL_MANUAL
      || (editForm.sopir_aktual_mode === SOPIR_AKTUAL_MASTER && editForm.sopir_aktual_id !== editForm.sopir_default_id);
    const sopirAktualId = editForm.sopir_aktual_mode === SOPIR_AKTUAL_DEFAULT
      ? editForm.sopir_default_id
      : editForm.sopir_aktual_mode === SOPIR_AKTUAL_MASTER
        ? editForm.sopir_aktual_id
        : null;

    const payload = {
      tanggal: editForm.tanggal,
      sopir_id: editForm.sopir_default_id,
      sopir_default_id: editForm.sopir_default_id,
      sopir_default_nama: editForm.sopir_default_nama,
      mitra_id: editForm.mitra_id,
      plat_nomor: editForm.plat_nomor || null,
      sopir_aktual_id: sopirAktualId,
      sopir_aktual_nama: editForm.sopir_aktual_nama.trim(),
      sopir_aktual_no_hp: editForm.sopir_aktual_no_hp || null,
      sopir_aktual_source: editForm.sopir_aktual_mode === SOPIR_AKTUAL_MANUAL ? 'manual' : 'master',
      sopir_diganti_dari_default: sopirDiganti,
      catatan_sopir: editForm.catatan_sopir || null,
      tonase,
      harga_harian: editForm.harga_harian,
      total_kotor: editForm.total_kotor,
      harga_pabrik_per_kg: toNumber(editForm.harga_dasar),
      fee_owner_per_kg: toNumber(editForm.fee_owner_per_kg),
      harga_bersih_per_kg: editForm.harga_harian,
      total_fee_owner: editForm.total_fee_owner,
      total_nilai_bersih: editForm.total_kotor,
      fee_owner_history_id: editForm.fee_owner_history_id || null,
      updated_by: userId,
      alasan_edit: editForm.alasan_edit.trim(),
    };

    const { error } = await supabase
      .from('transaksi_mitra')
      .update(payload)
      .eq('id', editTarget.id)
      .neq('status', 'dibatalkan');

    if (error) {
      alert(`Gagal menyimpan edit: ${error.message}`);
      setSaving(false);
      return;
    }

    await writeAuditLog('update', editTarget, { ...editTarget, ...payload }, payload.alasan_edit);
    setEditTarget(null);
    setEditForm(emptyEditForm);
    await loadData();
    setSaving(false);
  }

  async function handleCancelTransaction(event) {
    event.preventDefault();
    if (!cancelTarget || saving) return;
    if (!cancelReason.trim()) return alert('Alasan batal wajib diisi.');

    setSaving(true);
    const userId = await getCurrentUserId();
    const payload = {
      status: 'dibatalkan',
      dibatalkan_at: new Date().toISOString(),
      dibatalkan_by: userId,
      alasan_batal: cancelReason.trim(),
      updated_by: userId,
      alasan_edit: `Dibatalkan: ${cancelReason.trim()}`,
    };

    const { error } = await supabase
      .from('transaksi_mitra')
      .update(payload)
      .eq('id', cancelTarget.id)
      .neq('status', 'dibatalkan');

    if (error) {
      alert(`Gagal membatalkan transaksi: ${error.message}`);
      setSaving(false);
      return;
    }

    await writeAuditLog('cancel', cancelTarget, { ...cancelTarget, ...payload }, cancelReason.trim());
    setCancelTarget(null);
    setCancelReason('');
    await loadData();
    setSaving(false);
  }

  return (
    <AppShell title="Riwayat Pengiriman Mitra" subtitle="Edit dan koreksi transaksi mitra">
      <div className="page-header">
        <div>
          <h2 className="page-title">Riwayat Pengiriman Mitra</h2>
          <p className="page-description">Daftar transaksi detail untuk koreksi input dan pembatalan tanpa hapus data</p>
        </div>
        <button className="btn btn-outline" onClick={loadData} disabled={loading}>
          <RefreshCw size={18} /> Muat Ulang
        </button>
      </div>

      <div className="card" style={{ padding: 'var(--space-md)', marginBottom: 'var(--space-lg)' }}>
        <div className="form-grid" style={{ alignItems: 'end' }}>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Dari Tanggal</label>
            <input type="date" className="form-input" value={dateFrom} onChange={event => setDateFrom(event.target.value)} />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Sampai Tanggal</label>
            <input type="date" className="form-input" value={dateTo} onChange={event => setDateTo(event.target.value)} />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Status</label>
            <select className="form-input" value={statusFilter} onChange={event => setStatusFilter(event.target.value)}>
              <option value="aktif">Aktif</option>
              <option value="dibatalkan">Dibatalkan</option>
              <option value="semua">Semua</option>
            </select>
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Cari</label>
            <input
              className="form-input"
              value={search}
              onChange={event => {
                setSearch(event.target.value);
                setPage(1);
              }}
              placeholder="Cari mitra, sopir, plat..."
            />
          </div>
        </div>
      </div>

      <div className="card" style={{ padding: 'var(--space-md)', marginBottom: 'var(--space-lg)' }}>
        <div style={{ display: 'flex', gap: 20, flexWrap: 'wrap' }}>
          <div>
            <div className="text-tertiary" style={{ fontSize: 12 }}>Transaksi Tampil</div>
            <div style={{ fontWeight: 800, fontSize: 20 }}>{filteredTransaksi.length}</div>
          </div>
          <div>
            <div className="text-tertiary" style={{ fontSize: 12 }}>Total Tonase Aktif</div>
            <div style={{ fontWeight: 800, fontSize: 20 }}>{totals.tonase.toLocaleString('id-ID')} Kg</div>
          </div>
          <div>
            <div className="text-tertiary" style={{ fontSize: 12 }}>Total Nilai Aktif</div>
            <div style={{ fontWeight: 800, fontSize: 20 }}>{formatRupiah(totals.total)}</div>
          </div>
        </div>
      </div>

      <div className="table-container">
        <table className="table">
          <thead>
            <tr>
              <SortableHeader label="Tanggal" sortKey="tanggal" sort={sort} onSort={handleSort} />
              <SortableHeader label="Mitra" sortKey="mitra" sort={sort} onSort={handleSort} />
              <SortableHeader label="Sopir Aktual" sortKey="sopir" sort={sort} onSort={handleSort} />
              <SortableHeader label="Plat" sortKey="plat" sort={sort} onSort={handleSort} />
              <SortableHeader label="Status" sortKey="status" sort={sort} onSort={handleSort} />
              <SortableHeader label="Tonase" sortKey="tonase" sort={sort} onSort={handleSort} align="right" />
              <SortableHeader label="Harga Bersih/Kg" sortKey="harga_bersih" sort={sort} onSort={handleSort} align="right" />
              <SortableHeader label="Nilai Bersih" sortKey="nilai_bersih" sort={sort} onSort={handleSort} align="right" />
              <th style={{ textAlign: 'center' }}>Aksi</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={9} style={{ padding: 24, textAlign: 'center' }}>Memuat riwayat...</td></tr>
            ) : errorMsg ? (
              <tr><td colSpan={9} style={{ padding: 24, textAlign: 'center', color: 'var(--color-danger)' }}>Gagal memuat riwayat: {errorMsg}</td></tr>
            ) : sortedTransaksi.length === 0 ? (
              <tr><td colSpan={9} style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)' }}>Tidak ada transaksi pada filter ini</td></tr>
            ) : (
              paginatedTransaksi.rows.map(row => (
                <tr key={row.id} style={row.status === 'dibatalkan' ? { opacity: 0.62 } : undefined}>
                  <td>{row.tanggal}</td>
                  <td style={{ fontWeight: 700 }}>{formatMitraLabel(row.master_mitra) || '-'}</td>
                  <td>
                    <div style={{ fontWeight: 700 }}>{row.sopir_aktual_nama || row.sopir_default_nama || '-'}</div>
                    {row.sopir_diganti_dari_default && (
                      <div style={{ color: 'var(--text-tertiary)', fontSize: 12 }}>Default: {row.sopir_default_nama || '-'}</div>
                    )}
                  </td>
                  <td className="table-mono">{row.plat_nomor || '-'}</td>
                  <td>
                    <span className={`badge ${row.status === 'dibatalkan' ? 'badge-danger' : 'badge-success'}`}>
                      {row.status === 'dibatalkan' ? 'Dibatalkan' : 'Aktif'}
                    </span>
                    {row.alasan_batal && (
                      <div style={{ color: 'var(--text-tertiary)', fontSize: 12, marginTop: 4 }}>{row.alasan_batal}</div>
                    )}
                  </td>
                  <td style={{ textAlign: 'right', fontWeight: 700 }}>{toNumber(row.tonase).toLocaleString('id-ID')}</td>
                  <td style={{ textAlign: 'right' }} className="table-mono">{formatRupiah(row.harga_bersih_per_kg ?? row.harga_harian)}</td>
                  <td style={{ textAlign: 'right' }} className="table-mono">{formatRupiah(row.total_nilai_bersih ?? row.total_kotor)}</td>
                  <td>
                    <div style={{ display: 'flex', gap: 8, justifyContent: 'center' }}>
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        title="Edit transaksi"
                        disabled={row.status === 'dibatalkan'}
                        onClick={() => openEdit(row)}
                      >
                        <Pencil size={16} />
                      </button>
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        title="Batalkan transaksi"
                        disabled={row.status === 'dibatalkan'}
                        onClick={() => {
                          setCancelTarget(row);
                          setCancelReason('');
                        }}
                      >
                        <Ban size={16} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        <TablePagination
          page={paginatedTransaksi.page}
          totalPages={paginatedTransaksi.totalPages}
          totalItems={sortedTransaksi.length}
          startIndex={paginatedTransaksi.startIndex}
          endIndex={paginatedTransaksi.endIndex}
          onPageChange={setPage}
        />
      </div>

      {editTarget && (
        <div className="modal-overlay" onClick={() => !saving && setEditTarget(null)}>
          <div className="modal" onClick={event => event.stopPropagation()} style={{ maxWidth: 760 }}>
            <div className="modal-header">
              <h3 className="modal-title">Edit Pengiriman Mitra</h3>
              <button className="modal-close" disabled={saving} onClick={() => setEditTarget(null)}>x</button>
            </div>
            <form onSubmit={handleSaveEdit}>
              <div className="modal-body">
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Tanggal</label>
                    <input className="form-input" type="date" required value={editForm.tanggal} onChange={event => handleEditTanggalChange(event.target.value)} />
                  </div>
                  <div className="form-group">
                    <label className="form-label form-label-required">Tonase (Kg)</label>
                    <input className="form-input form-input-mono" type="number" required min={1} value={editForm.tonase} onChange={event => handleEditTonaseChange(event.target.value)} />
                  </div>
                </div>

                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Harga Pabrik / TWB (Rp/Kg)</label>
                    <input
                      className="form-input form-input-mono"
                      type="number"
                      required
                      min={0}
                      value={editForm.harga_dasar}
                      onChange={event => handleEditHargaDasarChange(event.target.value)}
                    />
                    <div className="form-hint">Harga ini akan dikurangi Fee Owner aktif untuk menghitung Harga Bersih/Kg ke mitra.</div>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Fee Owner Aktif (Rp/Kg)</label>
                    <input className="form-input form-input-mono" value={formatRupiah(editFeeOwner)} readOnly />
                    <div className="form-hint">Diambil dari master mitra saat koreksi dilakukan.</div>
                  </div>
                </div>

                <div className="alert alert-info">
                  <div>
                    <strong>Koreksi data lama sebelum fee dipakai</strong>
                    <div style={{ marginTop: 4 }}>
                      Jika transaksi lama tersimpan memakai harga pabrik penuh, klik tombol ini agar harga tersimpan lama diperlakukan sebagai Harga Pabrik/TWB lalu dikurangi Fee Owner aktif.
                    </div>
                    <button
                      type="button"
                      className="btn btn-outline btn-sm"
                      style={{ marginTop: 12 }}
                      onClick={handleUseStoredNetAsFactoryPrice}
                    >
                      Gunakan Harga Lama sebagai Harga Pabrik
                    </button>
                  </div>
                </div>

                <div className="form-group">
                  <label className="form-label form-label-required">Armada / Sopir Default</label>
                  <SearchableCombobox
                    value={editForm.sopir_default_id}
                    options={sopirs}
                    onChange={handleEditSopirDefaultChange}
                    getOptionLabel={formatSopirArmadaLabel}
                    getOptionDescription={formatSopirArmadaDescription}
                    getSearchText={getSopirArmadaSearchText}
                    placeholder="Cari sopir, plat, atau mitra..."
                    emptyLabel="Armada / sopir tidak ditemukan"
                  />
                </div>

                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Plat Armada</label>
                    <input className="form-input form-input-mono" required value={editForm.plat_nomor} onChange={event => setEditForm({ ...editForm, plat_nomor: event.target.value })} />
                  </div>
                  <div className="form-group">
                    <label className="form-label form-label-required">Mitra Transaksi</label>
                    <SearchableCombobox
                      value={editForm.mitra_id}
                      options={mitras}
                      onChange={handleEditMitraChange}
                      getOptionLabel={formatMitraLabel}
                      getSearchText={getMitraSearchText}
                      placeholder="Cari kode, alamat, atau nama mitra..."
                      emptyLabel="Mitra tidak ditemukan"
                    />
                  </div>
                </div>

                <div className="form-group">
                  <label className="form-label form-label-required">Sopir Aktual</label>
                  <select className="form-input" value={editForm.sopir_aktual_mode} onChange={event => handleEditSopirAktualModeChange(event.target.value)}>
                    <option value={SOPIR_AKTUAL_DEFAULT}>Sama dengan sopir default</option>
                    <option value={SOPIR_AKTUAL_MASTER}>Pilih sopir lain dari master</option>
                    <option value={SOPIR_AKTUAL_MANUAL}>Input sopir pengganti manual</option>
                  </select>
                </div>

                {editForm.sopir_aktual_mode === SOPIR_AKTUAL_MASTER && (
                  <div className="form-group">
                    <label className="form-label form-label-required">Pilih Sopir Pengganti</label>
                    <SearchableCombobox
                      value={editForm.sopir_aktual_id}
                      options={sopirs}
                      onChange={handleEditSopirAktualMasterChange}
                      getOptionLabel={formatSopirArmadaLabel}
                      getOptionDescription={formatSopirArmadaDescription}
                      getSearchText={getSopirArmadaSearchText}
                      placeholder="Cari sopir pengganti..."
                      emptyLabel="Sopir tidak ditemukan"
                    />
                  </div>
                )}

                {editForm.sopir_aktual_mode === SOPIR_AKTUAL_MANUAL && (
                  <div className="form-grid">
                    <div className="form-group">
                      <label className="form-label form-label-required">Nama Sopir Pengganti</label>
                      <input className="form-input" required value={editForm.sopir_aktual_nama} onChange={event => setEditForm({ ...editForm, sopir_aktual_nama: event.target.value })} />
                    </div>
                    <div className="form-group">
                      <label className="form-label">No. HP</label>
                      <input className="form-input" value={editForm.sopir_aktual_no_hp} onChange={event => setEditForm({ ...editForm, sopir_aktual_no_hp: event.target.value })} />
                    </div>
                  </div>
                )}

                {editForm.sopir_aktual_mode !== SOPIR_AKTUAL_DEFAULT && (
                  <div className="form-group">
                    <label className="form-label">Catatan Pergantian Sopir</label>
                    <input className="form-input" value={editForm.catatan_sopir} onChange={event => setEditForm({ ...editForm, catatan_sopir: event.target.value })} />
                  </div>
                )}

                <div className="card" style={{ padding: 'var(--space-md)', marginBottom: 'var(--space-lg)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' }}>
                    <span>Harga Pabrik/TWB: <strong>{formatRupiah(editForm.harga_dasar)}</strong></span>
                    <span>Fee Owner: <strong>{formatRupiah(editFeeOwner)}</strong></span>
                    <span>Harga Bersih/Kg: <strong>{formatRupiah(editForm.harga_harian)}</strong></span>
                    <span>Nilai Bersih: <strong>{formatRupiah(editForm.total_kotor)}</strong></span>
                  </div>
                </div>

                <div className="form-group">
                  <label className="form-label form-label-required">Alasan Edit</label>
                  <textarea
                    className="form-input"
                    required
                    rows={3}
                    value={editForm.alasan_edit}
                    onChange={event => setEditForm({ ...editForm, alasan_edit: event.target.value })}
                    placeholder="Contoh: salah pilih plat / tonase typo"
                  />
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" disabled={saving} onClick={() => setEditTarget(null)}>Batal</button>
                <button type="submit" className="btn btn-primary" disabled={saving}>
                  {saving ? 'Menyimpan...' : 'Simpan Perubahan'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {cancelTarget && (
        <div className="modal-overlay" onClick={() => !saving && setCancelTarget(null)}>
          <div className="modal" onClick={event => event.stopPropagation()} style={{ maxWidth: 520 }}>
            <div className="modal-header">
              <h3 className="modal-title">Batalkan Pengiriman</h3>
              <button className="modal-close" disabled={saving} onClick={() => setCancelTarget(null)}>x</button>
            </div>
            <form onSubmit={handleCancelTransaction}>
              <div className="modal-body">
                <p className="text-secondary" style={{ marginBottom: 16 }}>
                  Transaksi {cancelTarget.tanggal} - {formatMitraLabel(cancelTarget.master_mitra)} akan ditandai dibatalkan. Data tidak dihapus.
                </p>
                <div className="form-group">
                  <label className="form-label form-label-required">Alasan Batal</label>
                  <textarea
                    className="form-input"
                    required
                    rows={3}
                    value={cancelReason}
                    onChange={event => setCancelReason(event.target.value)}
                    placeholder="Contoh: double input / salah transaksi"
                  />
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" disabled={saving} onClick={() => setCancelTarget(null)}>Kembali</button>
                <button type="submit" className="btn btn-danger" disabled={saving}>
                  {saving ? 'Membatalkan...' : 'Batalkan Transaksi'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AppShell>
  );
}
