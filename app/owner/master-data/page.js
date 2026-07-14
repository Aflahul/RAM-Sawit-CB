'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import ConfirmDialog from '@/components/ui/ConfirmDialog';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import { FileSpreadsheet, Pencil, Search, Trash2, X } from 'lucide-react';
import {
  MITRA_TYPES,
  getMitraSearchText,
  getMitraTypeBadgeClass,
  getMitraTypeLabel,
} from '@/lib/display-labels';
import { paginateRows } from '@/lib/pagination-utils';
import { getNextSort, sortRows } from '@/lib/sort-utils';
import { exportStyledWorkbook } from '@/lib/spreadsheet-export';
import { supabase } from '@/lib/supabase';
import { formatDateTimeDisplay, formatRupiah, getTodayISO } from '@/lib/utils';

const TABLE_PAGE_SIZE = 20;

const mitraSortAccessors = {
  kode: row => row.kode,
  nama: row => row.nama,
  tipe: row => getMitraTypeLabel(row.tipe_mitra),
  penanggung_jawab: row => row.penanggung_jawab,
  no_hp: row => row.no_hp,
  alamat: row => row.alamat,
  fee: row => Number(row.fee_per_kg),
};

export default function MitraPage() {
  const [mitras, setMitras] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [saving, setSaving] = useState(false);
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState({ key: 'kode', direction: 'asc' });
  const [page, setPage] = useState(1);
  const [toast, setToast] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [formMitra, setFormMitra] = useState({
    kode: '',
    nama: '',
    penanggung_jawab: '',
    no_hp: '',
    alamat: '',
    tipe_mitra: MITRA_TYPES.EKSTERNAL,
    fee_per_kg: 0,
    fee_berlaku_mulai: getTodayISO(),
    fee_alasan: '',
  });

  const loadData = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase
      .from('master_mitra')
      .select('*')
      .eq('aktif', true)
      .order('nama');

    setMitras(data || []);
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  function resetForm() {
    setFormMitra({
      kode: '',
      nama: '',
      penanggung_jawab: '',
      no_hp: '',
      alamat: '',
      tipe_mitra: MITRA_TYPES.EKSTERNAL,
      fee_per_kg: 0,
      fee_berlaku_mulai: getTodayISO(),
      fee_alasan: '',
    });
  }

  function openNew() {
    setEditingId(null);
    resetForm();
    setShowModal(true);
  }

  function openEdit(item) {
    setEditingId(item.id);
    setFormMitra({
      kode: item.kode || '',
      nama: item.nama || '',
      penanggung_jawab: item.penanggung_jawab || '',
      no_hp: item.no_hp || '',
      alamat: item.alamat || '',
      tipe_mitra: item.tipe_mitra || MITRA_TYPES.EKSTERNAL,
      fee_per_kg: item.fee_per_kg || 0,
      fee_berlaku_mulai: getTodayISO(),
      fee_alasan: '',
    });
    setShowModal(true);
  }

  function handleSort(key) {
    setPage(1);
    setSort(current => getNextSort(current, key));
  }

  function showToast(message, type = 'error', timeout = 4000) {
    setToast({ message, type });
    setTimeout(() => setToast(null), timeout);
  }

  async function handleSave(e) {
    e.preventDefault();
    setSaving(true);

    const feePerKg = parseFloat(formMitra.fee_per_kg) || 0;
    const payload = {
      kode: formMitra.kode,
      nama: formMitra.nama,
      penanggung_jawab: formMitra.penanggung_jawab || null,
      no_hp: formMitra.no_hp || null,
      alamat: formMitra.alamat || null,
      tipe_mitra: formMitra.tipe_mitra || MITRA_TYPES.EKSTERNAL,
      fee_per_kg: feePerKg,
    };
    let savedMitraId = editingId;
    let historyFailed = false;

    if (editingId) {
      const { error } = await supabase.from('master_mitra').update(payload).eq('id', editingId);
      if (error) {
        showToast(`Gagal menyimpan mitra: ${error.message}`, 'error', 5000);
        setSaving(false);
        return;
      }
    } else {
      const { data, error } = await supabase.from('master_mitra').insert(payload).select('id').single();
      if (error) {
        showToast(`Gagal menyimpan mitra: ${error.message}`, 'error', 5000);
        setSaving(false);
        return;
      }
      savedMitraId = data?.id;
    }

    if (savedMitraId) {
      const { error: historyError } = await supabase
        .from('fee_owner_mitra_history')
        .upsert({
          master_mitra_id: savedMitraId,
          fee_per_kg: feePerKg,
          berlaku_mulai: formMitra.fee_berlaku_mulai || getTodayISO(),
          alasan_perubahan: formMitra.fee_alasan || 'Update Fee Owner dari Mitra',
          aktif: true,
        }, { onConflict: 'master_mitra_id,berlaku_mulai' });

      if (historyError) {
        historyFailed = true;
        showToast(`Mitra tersimpan, tetapi riwayat Fee Owner gagal dicatat: ${historyError.message}`, 'error', 6000);
      }
    }

    setSaving(false);
    setShowModal(false);
    if (!historyFailed) {
      showToast('Mitra berhasil disimpan.', 'success', 3000);
    }
    await loadData();
  }

  async function handleDelete() {
    if (!deleteTarget) return;

    const { error } = await supabase.from('master_mitra').update({ aktif: false }).eq('id', deleteTarget.id);
    if (error) {
      showToast(`Gagal menonaktifkan mitra: ${error.message}`, 'error', 5000);
      return;
    }

    setDeleteTarget(null);
    showToast('Mitra berhasil dinonaktifkan.', 'success', 3000);
    await loadData();
  }

  const filteredMitras = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return mitras;
    return mitras.filter(mitra => getMitraSearchText(mitra).toLowerCase().includes(keyword));
  }, [mitras, search]);

  const sortedMitras = useMemo(() => sortRows(filteredMitras, sort, mitraSortAccessors), [filteredMitras, sort]);
  const paginatedMitras = useMemo(() => paginateRows(sortedMitras, page, TABLE_PAGE_SIZE), [page, sortedMitras]);

  async function handleExportExcel() {
    const generatedAt = formatDateTimeDisplay(new Date());

    await exportStyledWorkbook({
      filename: `mitra-${getTodayISO()}.xlsx`,
      sheets: [{
        name: 'Mitra',
        title: 'MITRA SAWIT CB',
        subtitle: `Total ${sortedMitras.length.toLocaleString('id-ID')} mitra | Filter: ${search || 'Semua'} | Dibuat: ${generatedAt}`,
        columns: [
          { header: 'No', value: (_, index) => index + 1, type: 'number', width: 6 },
          { header: 'Kode', key: 'kode', width: 14 },
          { header: 'Nama Mitra', key: 'nama', width: 24 },
          { header: 'Tipe', value: row => getMitraTypeLabel(row.tipe_mitra), width: 18 },
          { header: 'Penanggung Jawab', key: 'penanggung_jawab', width: 24 },
          { header: 'No. HP / WA', key: 'no_hp', width: 18 },
          { header: 'Alamat / Lokasi', key: 'alamat', width: 28 },
          { header: 'Fee Owner/Kg', key: 'fee_per_kg', type: 'currency', width: 16 },
        ],
        rows: sortedMitras,
      }],
    });
  }

  return (
    <AppShell title="Mitra" subtitle="Kelola mitra eksternal, mitra internal, dan fee owner">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <div className="toolbar" style={{ flex: 1, marginBottom: 0 }}>
          <div className="search-box" style={{ flex: 1, maxWidth: 420 }}>
            <span className="search-box-icon"><Search size={16} /></span>
            <input
              type="text"
              className="form-input"
              placeholder="Cari nama, kode, atau lokasi mitra..."
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setPage(1);
              }}
              style={{ paddingLeft: 40 }}
            />
          </div>
        </div>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
          <button className="btn btn-outline" onClick={handleExportExcel} disabled={sortedMitras.length === 0}>
            <FileSpreadsheet size={16} />
            Export Excel
          </button>
          <button className="btn btn-primary" onClick={openNew}>+ Tambah Mitra</button>
        </div>
      </div>

      <div className="table-container">
        <table className="table">
          <thead>
            <tr>
              <SortableHeader label="Kode" sortKey="kode" sort={sort} onSort={handleSort} />
              <SortableHeader label="Nama Mitra" sortKey="nama" sort={sort} onSort={handleSort} />
              <SortableHeader label="Tipe" sortKey="tipe" sort={sort} onSort={handleSort} />
              <SortableHeader label="Penanggung Jawab" sortKey="penanggung_jawab" sort={sort} onSort={handleSort} />
              <SortableHeader label="No. HP" sortKey="no_hp" sort={sort} onSort={handleSort} />
              <SortableHeader label="Alamat" sortKey="alamat" sort={sort} onSort={handleSort} />
              <SortableHeader label="Fee Owner/Kg" sortKey="fee" sort={sort} onSort={handleSort} align="right" />
              <th style={{ textAlign: 'center' }}>Aksi</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td colSpan={8}>Memuat data...</td>
              </tr>
            ) : paginatedMitras.rows.length === 0 ? (
              <tr>
                <td colSpan={8}>Data mitra tidak ditemukan.</td>
              </tr>
            ) : (
              paginatedMitras.rows.map(mitra => (
                <tr key={mitra.id}>
                  <td className="table-mono" style={{ fontWeight: 600 }}>{mitra.kode || '-'}</td>
                  <td style={{ fontWeight: 600 }}>{mitra.nama}</td>
                  <td>
                    <span className={`badge ${getMitraTypeBadgeClass(mitra.tipe_mitra)}`}>
                      {getMitraTypeLabel(mitra.tipe_mitra)}
                    </span>
                  </td>
                  <td>{mitra.penanggung_jawab || '-'}</td>
                  <td className="table-mono">{mitra.no_hp || '-'}</td>
                  <td>{mitra.alamat || '-'}</td>
                  <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(mitra.fee_per_kg)}</td>
                  <td style={{ textAlign: 'center' }}>
                    <button className="btn btn-ghost btn-sm" onClick={() => openEdit(mitra)} aria-label={`Edit ${mitra.nama}`}>
                      <Pencil size={16} />
                    </button>
                    <button className="btn btn-ghost btn-sm" onClick={() => setDeleteTarget(mitra)} aria-label={`Nonaktifkan ${mitra.nama}`}>
                      <Trash2 size={16} />
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        <TablePagination
          page={paginatedMitras.page}
          totalPages={paginatedMitras.totalPages}
          totalItems={sortedMitras.length}
          startIndex={paginatedMitras.startIndex}
          endIndex={paginatedMitras.endIndex}
          onPageChange={setPage}
        />
      </div>

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">{editingId ? 'Edit' : 'Tambah'} Mitra</h3>
              <button className="modal-close" onClick={() => setShowModal(false)} aria-label="Tutup">
                <X size={18} />
              </button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Kode Mitra</label>
                    <input
                      className="form-input"
                      required
                      value={formMitra.kode}
                      onChange={e => setFormMitra({ ...formMitra, kode: e.target.value })}
                      placeholder="Contoh: SL/HB"
                    />
                  </div>
                  <div className="form-group">
                    <label className="form-label form-label-required">Nama Usaha / Mitra</label>
                    <input
                      className="form-input"
                      required
                      value={formMitra.nama}
                      onChange={e => setFormMitra({ ...formMitra, nama: e.target.value })}
                    />
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Tipe Mitra / Grup</label>
                  <select
                    className="form-input form-select"
                    required
                    value={formMitra.tipe_mitra}
                    onChange={e => setFormMitra({ ...formMitra, tipe_mitra: e.target.value })}
                  >
                    <option value={MITRA_TYPES.EKSTERNAL}>Mitra Eksternal</option>
                    <option value={MITRA_TYPES.INTERNAL_OWNER}>Internal Owner</option>
                  </select>
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label">Penanggung Jawab</label>
                    <input className="form-input" value={formMitra.penanggung_jawab} onChange={e => setFormMitra({ ...formMitra, penanggung_jawab: e.target.value })} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">No. HP / WA</label>
                    <input className="form-input" value={formMitra.no_hp} onChange={e => setFormMitra({ ...formMitra, no_hp: e.target.value })} />
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label">Alamat / Lokasi</label>
                  <input className="form-input" value={formMitra.alamat} onChange={e => setFormMitra({ ...formMitra, alamat: e.target.value })} />
                </div>
                <div className="form-group">
                  <label className="form-label">Fee Owner (Rp/Kg)</label>
                  <input type="number" className="form-input" value={formMitra.fee_per_kg} onChange={e => setFormMitra({ ...formMitra, fee_per_kg: e.target.value })} />
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Fee Berlaku Mulai</label>
                    <input type="date" className="form-input" required value={formMitra.fee_berlaku_mulai} onChange={e => setFormMitra({ ...formMitra, fee_berlaku_mulai: e.target.value })} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Alasan Perubahan Fee</label>
                    <input className="form-input" value={formMitra.fee_alasan} onChange={e => setFormMitra({ ...formMitra, fee_alasan: e.target.value })} placeholder="Contoh: kesepakatan baru" />
                  </div>
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" onClick={() => setShowModal(false)}>Batal</button>
                <button type="submit" className="btn btn-primary" disabled={saving}>
                  {saving ? 'Menyimpan...' : 'Simpan'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      <ConfirmDialog
        open={!!deleteTarget}
        title="Nonaktifkan Mitra"
        message={deleteTarget ? `${deleteTarget.nama} tidak akan tampil lagi sebagai mitra aktif.` : ''}
        confirmText="Nonaktifkan"
        cancelText="Batal"
        variant="danger"
        onConfirm={handleDelete}
        onCancel={() => setDeleteTarget(null)}
      />
    </AppShell>
  );
}
