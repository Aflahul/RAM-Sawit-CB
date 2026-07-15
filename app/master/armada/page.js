'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import AppShell from '@/components/layout/AppShell';
import ConfirmDialog from '@/components/ui/ConfirmDialog';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import { FileSpreadsheet, Pencil, Save, Search, Trash2, X } from 'lucide-react';
import {
  formatMitraLabel,
  getMitraSearchText,
  getSopirArmadaSearchText,
} from '@/lib/display-labels';
import { paginateRows } from '@/lib/pagination-utils';
import { getNextSort, sortRows } from '@/lib/sort-utils';
import { exportStyledWorkbook } from '@/lib/spreadsheet-export';
import { supabase } from '@/lib/supabase';
import { formatDateTimeDisplay, formatRupiah, getTodayISO } from '@/lib/utils';

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
  const [toast, setToast] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [savingSettings, setSavingSettings] = useState(false);
  const [driverSettings, setDriverSettings] = useState({
    id: '',
    upah_sopir_per_trip: 0,
    uang_jalan_per_trip: 0,
  });
  const [formArmada, setFormArmada] = useState({
    nama: '',
    no_hp: '',
    mitra_id: '',
    plat_nomor: '',
    is_armada_cb: false,
    upah_sopir_per_trip_override: '',
    uang_jalan_per_trip_override: '',
  });

  const loadData = useCallback(async () => {
    setLoading(true);
    const [{ data: armadaData }, { data: mitraData }, { data: settingsData }] = await Promise.all([
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
      supabase
        .from('pengaturan_bisnis')
        .select('id, value_json')
        .eq('key', 'armada_cb_biaya_sopir')
        .eq('scope', 'global')
        .eq('aktif', true)
        .maybeSingle(),
    ]);

    setArmadas(armadaData || []);
    setMitras(mitraData || []);
    setDriverSettings({
      id: settingsData?.id || '',
      upah_sopir_per_trip: Number(settingsData?.value_json?.upah_sopir_per_trip || 0),
      uang_jalan_per_trip: Number(settingsData?.value_json?.uang_jalan_per_trip || 0),
    });
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  function resetForm() {
    setFormArmada({
      nama: '',
      no_hp: '',
      mitra_id: '',
      plat_nomor: '',
      is_armada_cb: false,
      upah_sopir_per_trip_override: '',
      uang_jalan_per_trip_override: '',
    });
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
      is_armada_cb: Boolean(item.is_armada_cb),
      upah_sopir_per_trip_override: item.upah_sopir_per_trip_override ?? '',
      uang_jalan_per_trip_override: item.uang_jalan_per_trip_override ?? '',
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

    const payload = {
      nama: formArmada.nama,
      no_hp: formArmada.no_hp || null,
      mitra_id: formArmada.mitra_id || null,
      plat_nomor: formArmada.plat_nomor || null,
      is_armada_cb: Boolean(formArmada.is_armada_cb),
      upah_sopir_per_trip_override: formArmada.is_armada_cb && formArmada.upah_sopir_per_trip_override !== ''
        ? Number(formArmada.upah_sopir_per_trip_override)
        : null,
      uang_jalan_per_trip_override: formArmada.is_armada_cb && formArmada.uang_jalan_per_trip_override !== ''
        ? Number(formArmada.uang_jalan_per_trip_override)
        : null,
    };

    if (editingId) {
      const { error } = await supabase.from('sopir').update(payload).eq('id', editingId);
      if (error) {
        showToast(`Gagal menyimpan armada: ${error.message}`, 'error', 5000);
        setSaving(false);
        return;
      }
    } else {
      const { error } = await supabase.from('sopir').insert(payload);
      if (error) {
        showToast(`Gagal menyimpan armada: ${error.message}`, 'error', 5000);
        setSaving(false);
        return;
      }
    }

    setSaving(false);
    setShowModal(false);
    showToast('Armada berhasil disimpan.', 'success', 3000);
    await loadData();
  }

  async function handleDelete() {
    if (!deleteTarget) return;

    const { error } = await supabase.from('sopir').update({ aktif: false }).eq('id', deleteTarget.id);
    if (error) {
      showToast(`Gagal menonaktifkan armada: ${error.message}`, 'error', 5000);
      return;
    }

    setDeleteTarget(null);
    showToast('Armada berhasil dinonaktifkan.', 'success', 3000);
    await loadData();
  }

  async function handleSaveSettings(e) {
    e.preventDefault();
    setSavingSettings(true);

    const valueJson = {
      upah_sopir_per_trip: Math.max(0, Number(driverSettings.upah_sopir_per_trip) || 0),
      uang_jalan_per_trip: Math.max(0, Number(driverSettings.uang_jalan_per_trip) || 0),
    };
    const request = driverSettings.id
      ? supabase.from('pengaturan_bisnis').update({ value_json: valueJson }).eq('id', driverSettings.id)
      : supabase.from('pengaturan_bisnis').insert({
        key: 'armada_cb_biaya_sopir',
        value_json: valueJson,
        scope: 'global',
        aktif: true,
      }).select('id').single();
    const { data, error } = await request;

    setSavingSettings(false);
    if (error) {
      showToast(`Gagal menyimpan tarif sopir: ${error.message}`, 'error', 5000);
      return;
    }

    setDriverSettings(current => ({ ...current, id: current.id || data?.id || '', ...valueJson }));
    showToast('Tarif sopir Armada CB berhasil disimpan.', 'success', 3000);
  }

  function getEffectiveDriverCost(armada, field) {
    const overrideField = `${field}_override`;
    return Number(armada?.[overrideField] ?? driverSettings[field] ?? 0);
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
          { header: 'Tipe Armada', value: row => row.is_armada_cb ? 'Armada CB' : 'Armada Mitra', width: 16 },
          { header: 'Upah Sopir / Trip', value: row => row.is_armada_cb ? getEffectiveDriverCost(row, 'upah_sopir_per_trip') : 0, type: 'currency', width: 18 },
          { header: 'Uang Jalan / Trip', value: row => row.is_armada_cb ? getEffectiveDriverCost(row, 'uang_jalan_per_trip') : 0, type: 'currency', width: 18 },
        ],
        rows: sortedArmadas,
      }],
    });
  }

  return (
    <AppShell title="Armada" subtitle="Kelola plat, sopir tetap, dan tarif Armada CB">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <form className="card" onSubmit={handleSaveSettings} style={{ marginBottom: 'var(--space-lg)' }}>
        <div className="card-header" style={{ alignItems: 'flex-start', gap: 16, flexWrap: 'wrap' }}>
          <div>
            <div className="card-title">Tarif Sopir Armada CB</div>
            <div className="text-tertiary text-sm" style={{ marginTop: 4 }}>Berlaku untuk semua Armada CB yang tidak memiliki tarif khusus.</div>
          </div>
          <Link href="/owner/laporan-armada-cb" className="btn btn-outline btn-sm">Lihat Laporan Armada</Link>
        </div>
        <div className="form-grid" style={{ alignItems: 'end' }}>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Upah Sopir per Trip</label>
            <input
              type="number"
              min={0}
              className="form-input form-input-mono"
              value={driverSettings.upah_sopir_per_trip}
              onChange={e => setDriverSettings({ ...driverSettings, upah_sopir_per_trip: e.target.value })}
            />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Uang Jalan per Trip</label>
            <input
              type="number"
              min={0}
              className="form-input form-input-mono"
              value={driverSettings.uang_jalan_per_trip}
              onChange={e => setDriverSettings({ ...driverSettings, uang_jalan_per_trip: e.target.value })}
            />
          </div>
          <button className="btn btn-primary" type="submit" disabled={savingSettings}>
            <Save size={16} /> {savingSettings ? 'Menyimpan...' : 'Simpan Tarif'}
          </button>
        </div>
      </form>

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
              <th>Biaya Sopir / Trip</th>
              <th style={{ textAlign: 'center' }}>Aksi</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td colSpan={6}>Memuat data...</td>
              </tr>
            ) : paginatedArmadas.rows.length === 0 ? (
              <tr>
                <td colSpan={6}>Data armada tidak ditemukan.</td>
              </tr>
            ) : (
              paginatedArmadas.rows.map(armada => (
                <tr key={armada.id}>
                  <td style={{ fontWeight: 600 }}>{armada.nama}</td>
                  <td className="table-mono">{armada.plat_nomor || '-'}</td>
                  <td className="table-mono">{armada.no_hp || '-'}</td>
                  <td>
                    {armada.is_armada_cb && (
                      <span className="badge badge-success" style={{ marginRight: 8 }}>Armada CB</span>
                    )}
                    <span className="badge badge-blue">{armada.master_mitra ? formatMitraLabel(armada.master_mitra) : '-'}</span>
                  </td>
                  <td>
                    {armada.is_armada_cb ? (
                      <div style={{ fontSize: 12, lineHeight: 1.6 }}>
                        <div>Upah: <strong>{formatRupiah(getEffectiveDriverCost(armada, 'upah_sopir_per_trip'))}</strong></div>
                        <div>Jalan: <strong>{formatRupiah(getEffectiveDriverCost(armada, 'uang_jalan_per_trip'))}</strong></div>
                      </div>
                    ) : '-'}
                  </td>
                  <td style={{ textAlign: 'center' }}>
                    <button className="btn btn-ghost btn-sm" onClick={() => openEdit(armada)} aria-label={`Edit ${armada.nama}`}>
                      <Pencil size={16} />
                    </button>
                    <button className="btn btn-ghost btn-sm" onClick={() => setDeleteTarget(armada)} aria-label={`Nonaktifkan ${armada.nama}`}>
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
                  <div style={{ marginTop: 16 }}>
                    <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', fontSize: 14 }}>
                      <input
                        type="checkbox"
                      checked={formArmada.is_armada_cb}
                      onChange={e => setFormArmada({
                        ...formArmada,
                        is_armada_cb: e.target.checked,
                        upah_sopir_per_trip_override: e.target.checked ? formArmada.upah_sopir_per_trip_override : '',
                        uang_jalan_per_trip_override: e.target.checked ? formArmada.uang_jalan_per_trip_override : '',
                      })}
                      />
                      Ini adalah Armada CB
                    </label>
                    <div style={{ fontSize: 12, color: 'var(--text-tertiary)', marginTop: 4, marginLeft: 21 }}>
                      Armada CB otomatis dikenakan sewa pada Mitra Transaksi.
                    </div>
                  </div>
                </div>
                {formArmada.is_armada_cb && (
                  <div className="form-grid">
                    <div className="form-group">
                      <label className="form-label">Upah Khusus per Trip</label>
                      <input
                        type="number"
                        min={0}
                        className="form-input form-input-mono"
                        value={formArmada.upah_sopir_per_trip_override}
                        onChange={e => setFormArmada({ ...formArmada, upah_sopir_per_trip_override: e.target.value })}
                        placeholder={`Global: ${formatRupiah(driverSettings.upah_sopir_per_trip)}`}
                      />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Uang Jalan Khusus per Trip</label>
                      <input
                        type="number"
                        min={0}
                        className="form-input form-input-mono"
                        value={formArmada.uang_jalan_per_trip_override}
                        onChange={e => setFormArmada({ ...formArmada, uang_jalan_per_trip_override: e.target.value })}
                        placeholder={`Global: ${formatRupiah(driverSettings.uang_jalan_per_trip)}`}
                      />
                    </div>
                  </div>
                )}
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
        title="Nonaktifkan Armada"
        message={deleteTarget ? `${deleteTarget.nama} tidak akan tampil lagi di pilihan armada aktif.` : ''}
        confirmText="Nonaktifkan"
        cancelText="Batal"
        variant="danger"
        onConfirm={handleDelete}
        onCancel={() => setDeleteTarget(null)}
      />
    </AppShell>
  );
}
