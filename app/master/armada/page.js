'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import { FileSpreadsheet, Pencil, Search, Trash2, X } from 'lucide-react';
import {
  formatMitraLabel,
  getMitraSearchText,
  getSopirArmadaSearchText,
} from '@/lib/display-labels';
import { paginateRows } from '@/lib/pagination-utils';
import { getNextSort, sortRows } from '@/lib/sort-utils';
import { exportStyledWorkbook } from '@/lib/spreadsheet-export';
import { supabase } from '@/lib/supabase';
import { formatDateTimeDisplay, getTodayISO } from '@/lib/utils';

const TABLE_PAGE_SIZE = 20;

const armadaSortAccessors = {
  nama: row => row.nama,
  plat: row => row.plat_nomor,
  no_hp: row => row.no_hp,
  mitra: row => formatMitraLabel(row.master_mitra),
};

export default function ArmadaPage() {
  const [armadas, setArmadas] = useState([]);
  const [mitras, setMitras] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [saving, setSaving] = useState(false);
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState({ key: 'nama', direction: 'asc' });
  const [page, setPage] = useState(1);
  const [formArmada, setFormArmada] = useState({
    nama: '',
    no_hp: '',
    mitra_id: '',
    plat_nomor: '',
  });

  const loadData = useCallback(async () => {
    setLoading(true);
    const [{ data: armadaData }, { data: mitraData }] = await Promise.all([
      supabase
        .from('sopir')
        .select(`
          *,
          master_mitra ( kode, nama, alamat, tipe_mitra )
        `)
        .eq('aktif', true)
        .order('nama'),
      supabase
        .from('master_mitra')
        .select('id, kode, nama, alamat, tipe_mitra')
        .eq('aktif', true)
        .order('kode'),
    ]);

    setArmadas(armadaData || []);
    setMitras(mitraData || []);
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  function resetForm() {
    setFormArmada({ nama: '', no_hp: '', mitra_id: '', plat_nomor: '' });
  }

  function openNew() {
    setEditingId(null);
    resetForm();
    setShowModal(true);
  }

  function openEdit(item) {
    setEditingId(item.id);
    setFormArmada({
      nama: item.nama || '',
      no_hp: item.no_hp || '',
      mitra_id: item.mitra_id || '',
      plat_nomor: item.plat_nomor || '',
    });
    setShowModal(true);
  }

  function handleSort(key) {
    setPage(1);
    setSort(current => getNextSort(current, key));
  }

  async function handleSave(e) {
    e.preventDefault();
    setSaving(true);

    const payload = {
      nama: formArmada.nama,
      no_hp: formArmada.no_hp || null,
      mitra_id: formArmada.mitra_id || null,
      plat_nomor: formArmada.plat_nomor || null,
    };

    if (editingId) {
      const { error } = await supabase.from('sopir').update(payload).eq('id', editingId);
      if (error) {
        alert('Gagal menyimpan armada: ' + error.message);
        setSaving(false);
        return;
      }
    } else {
      const { error } = await supabase.from('sopir').insert(payload);
      if (error) {
        alert('Gagal menyimpan armada: ' + error.message);
        setSaving(false);
        return;
      }
    }

    setSaving(false);
    setShowModal(false);
    await loadData();
  }

  async function handleDelete(id) {
    if (!confirm('Yakin ingin menonaktifkan armada ini?')) return;
    await supabase.from('sopir').update({ aktif: false }).eq('id', id);
    await loadData();
  }

  const filteredArmadas = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return armadas;
    return armadas.filter(armada => getSopirArmadaSearchText(armada).toLowerCase().includes(keyword));
  }, [armadas, search]);

  const sortedArmadas = useMemo(() => sortRows(filteredArmadas, sort, armadaSortAccessors), [filteredArmadas, sort]);
  const paginatedArmadas = useMemo(() => paginateRows(sortedArmadas, page, TABLE_PAGE_SIZE), [page, sortedArmadas]);

  async function handleExportExcel() {
    const generatedAt = formatDateTimeDisplay(new Date());

    await exportStyledWorkbook({
      filename: `armada-${getTodayISO()}.xlsx`,
      sheets: [{
        name: 'Armada',
        title: 'ARMADA SAWIT CB',
        subtitle: `Total ${sortedArmadas.length.toLocaleString('id-ID')} armada | Filter: ${search || 'Semua'} | Dibuat: ${generatedAt}`,
        columns: [
          { header: 'No', value: (_, index) => index + 1, type: 'number', width: 6 },
          { header: 'Nama Sopir / Unit', key: 'nama', width: 24 },
          { header: 'Plat Default', key: 'plat_nomor', width: 18 },
          { header: 'No. HP / WA', key: 'no_hp', width: 18 },
          { header: 'Kode Mitra Default', value: row => row.master_mitra?.kode || '', width: 18 },
          { header: 'Nama Mitra Default', value: row => row.master_mitra?.nama || '', width: 24 },
          { header: 'Afiliasi Default', value: row => formatMitraLabel(row.master_mitra) || 'Tanpa default / armada bersama', width: 38 },
        ],
        rows: sortedArmadas,
      }],
    });
  }

  return (
    <AppShell title="Armada" subtitle="Kelola sopir, plat default, dan afiliasi mitra">
      <div className="page-header">
        <div className="toolbar" style={{ flex: 1, marginBottom: 0 }}>
          <div className="search-box" style={{ flex: 1, maxWidth: 420 }}>
            <span className="search-box-icon"><Search size={16} /></span>
            <input
              type="text"
              className="form-input"
              placeholder="Cari nama sopir, plat, atau mitra default..."
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
          <button className="btn btn-outline" onClick={handleExportExcel} disabled={sortedArmadas.length === 0}>
            <FileSpreadsheet size={16} />
            Export Excel
          </button>
          <button className="btn btn-primary" onClick={openNew}>+ Tambah Armada</button>
        </div>
      </div>

      <div className="table-container">
        <table className="table">
          <thead>
            <tr>
              <SortableHeader label="Nama Sopir / Unit" sortKey="nama" sort={sort} onSort={handleSort} />
              <SortableHeader label="Plat Default" sortKey="plat" sort={sort} onSort={handleSort} />
              <SortableHeader label="No. HP" sortKey="no_hp" sort={sort} onSort={handleSort} />
              <SortableHeader label="Mitra Default" sortKey="mitra" sort={sort} onSort={handleSort} />
              <th style={{ textAlign: 'center' }}>Aksi</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td colSpan={5}>Memuat data...</td>
              </tr>
            ) : paginatedArmadas.rows.length === 0 ? (
              <tr>
                <td colSpan={5}>Data armada tidak ditemukan.</td>
              </tr>
            ) : (
              paginatedArmadas.rows.map(armada => (
                <tr key={armada.id}>
                  <td style={{ fontWeight: 600 }}>{armada.nama}</td>
                  <td className="table-mono">{armada.plat_nomor || '-'}</td>
                  <td className="table-mono">{armada.no_hp || '-'}</td>
                  <td><span className="badge badge-blue">{armada.master_mitra ? formatMitraLabel(armada.master_mitra) : '-'}</span></td>
                  <td style={{ textAlign: 'center' }}>
                    <button className="btn btn-ghost btn-sm" onClick={() => openEdit(armada)} aria-label={`Edit ${armada.nama}`}>
                      <Pencil size={16} />
                    </button>
                    <button className="btn btn-ghost btn-sm" onClick={() => handleDelete(armada.id)} aria-label={`Nonaktifkan ${armada.nama}`}>
                      <Trash2 size={16} />
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        <TablePagination
          page={paginatedArmadas.page}
          totalPages={paginatedArmadas.totalPages}
          totalItems={sortedArmadas.length}
          startIndex={paginatedArmadas.startIndex}
          endIndex={paginatedArmadas.endIndex}
          onPageChange={setPage}
        />
      </div>

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">{editingId ? 'Edit' : 'Tambah'} Armada</h3>
              <button className="modal-close" onClick={() => setShowModal(false)} aria-label="Tutup">
                <X size={18} />
              </button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                <div className="form-group">
                  <label className="form-label form-label-required">Nama Sopir / Unit</label>
                  <input
                    className="form-input"
                    required
                    value={formArmada.nama}
                    onChange={e => setFormArmada({ ...formArmada, nama: e.target.value })}
                  />
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Plat Default</label>
                    <input
                      className="form-input form-input-mono"
                      required
                      value={formArmada.plat_nomor}
                      onChange={e => setFormArmada({ ...formArmada, plat_nomor: e.target.value.toUpperCase() })}
                      placeholder="Contoh: BM 1234 XY"
                    />
                  </div>
                  <div className="form-group">
                    <label className="form-label">No. HP / WA</label>
                    <input
                      className="form-input"
                      value={formArmada.no_hp}
                      onChange={e => setFormArmada({ ...formArmada, no_hp: e.target.value })}
                    />
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label">Mitra Default</label>
                  <SearchableCombobox
                    value={formArmada.mitra_id}
                    options={mitras}
                    onChange={mitraId => setFormArmada({ ...formArmada, mitra_id: mitraId })}
                    getOptionLabel={formatMitraLabel}
                    getSearchText={getMitraSearchText}
                    placeholder="Tanpa default / cari mitra..."
                    emptyLabel="Mitra tidak ditemukan"
                  />
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
    </AppShell>
  );
}
