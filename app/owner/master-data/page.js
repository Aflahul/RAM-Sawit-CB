'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import ConfirmDialog from '@/components/ui/ConfirmDialog';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import { CheckCircle2, FileSpreadsheet, Pencil, Search, Trash2, X } from 'lucide-react';
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
import { canApproveCorrections, normalizeRole } from '@/lib/roles';
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
  sewa_angkut: row => Number(row.tarif_sewa_angkut_per_kg),
  dana_trip: row => Number(row.dana_operasional_trip),
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
  const [userRole, setUserRole] = useState('admin_operasional');
  const [formMitra, setFormMitra] = useState({
    kode: '',
    nama: '',
    penanggung_jawab: '',
    no_hp: '',
    alamat: '',
    tipe_mitra: MITRA_TYPES.EKSTERNAL,
    fee_per_kg: 0,
    tarif_sewa_angkut_per_kg: 0,
    dana_operasional_trip: 0,
    fee_berlaku_mulai: getTodayISO(),
    fee_alasan: '',
  });

  const loadData = useCallback(async () => {
    setLoading(true);
    const [{ data }, { data: sessionData }] = await Promise.all([
      supabase
        .from('master_mitra')
        .select('*')
        .eq('aktif', true)
        .order('nama'),
      supabase.auth.getSession(),
    ]);

    const userId = sessionData?.session?.user?.id;
    if (userId) {
      const { data: userData } = await supabase.from('users').select('role').eq('id', userId).maybeSingle();
      setUserRole(normalizeRole(userData?.role));
    }

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
      tarif_sewa_angkut_per_kg: 0,
      dana_operasional_trip: 0,
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
      tarif_sewa_angkut_per_kg: item.tarif_sewa_angkut_per_kg || 0,
      dana_operasional_trip: item.dana_operasional_trip || 0,
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
    const tarifSewaAngkut = parseFloat(formMitra.tarif_sewa_angkut_per_kg) || 0;
    const danaOperasionalTrip = parseFloat(formMitra.dana_operasional_trip) || 0;
    
    const { error } = await supabase.rpc('save_master_mitra', {
      p_id: editingId || null,
      p_kode: formMitra.kode,
      p_nama: formMitra.nama,
      p_penanggung_jawab: formMitra.penanggung_jawab || null,
      p_no_hp: formMitra.no_hp || null,
      p_alamat: formMitra.alamat || null,
      p_tipe_mitra: formMitra.tipe_mitra || MITRA_TYPES.EKSTERNAL,
      p_fee_per_kg: feePerKg,
      p_tarif_sewa_angkut_per_kg: tarifSewaAngkut,
      p_dana_operasional_trip: danaOperasionalTrip,
      p_berlaku_mulai: formMitra.fee_berlaku_mulai || getTodayISO(),
      p_alasan_perubahan: formMitra.fee_alasan || null,
    });

    if (error) {
      showToast(`Gagal menyimpan mitra: ${error.message}`, 'error', 6000);
      setSaving(false);
      return;
    }

    setSaving(false);
    setShowModal(false);
    showToast(canApproveCorrections(userRole) ? 'Mitra dan riwayat tarif berhasil disimpan.' : 'Mitra tersimpan dan masuk daftar Perlu Verifikasi.', 'success', 4000);
    await loadData();
  }

  async function handleDelete() {
    if (!deleteTarget) return;

    const { error } = await supabase.rpc('set_master_mitra_active', {
      p_id: deleteTarget.id,
      p_active: false,
    });
    if (error) {
      showToast(`Gagal menonaktifkan mitra: ${error.message}`, 'error', 5000);
      return;
    }

    setDeleteTarget(null);
    showToast('Mitra berhasil dinonaktifkan.', 'success', 3000);
    await loadData();
  }

  async function handleVerify(item) {
    const { error } = await supabase.rpc('verify_master_mitra', {
      p_id: item.id,
      p_catatan: 'Diperiksa dari Master Mitra',
    });
    if (error) {
      showToast(`Gagal memverifikasi mitra: ${error.message}`, 'error', 5000);
      return;
    }
    showToast('Mitra sudah terverifikasi.', 'success', 3000);
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
          { header: 'Sewa Angkut', key: 'tarif_sewa_angkut_per_kg', type: 'currency', width: 16 },
          { header: 'Dana Operasional / Trip', key: 'dana_operasional_trip', type: 'currency', width: 22 },
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
              <SortableHeader label="Mitra" sortKey="kode" sort={sort} onSort={handleSort} />
              <SortableHeader label="Penanggung Jawab" sortKey="penanggung_jawab" sort={sort} onSort={handleSort} />
              <SortableHeader label="Fee Owner/Kg" sortKey="fee" sort={sort} onSort={handleSort} align="right" />
              <SortableHeader label="Sewa Angkut" sortKey="sewa_angkut" sort={sort} onSort={handleSort} align="right" />
              <SortableHeader label="Dana Operasional / Trip" sortKey="dana_trip" sort={sort} onSort={handleSort} align="right" />
              <th style={{ textAlign: 'center' }}>Aksi</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td colSpan={6}>Memuat data...</td>
              </tr>
            ) : paginatedMitras.rows.length === 0 ? (
              <tr>
                <td colSpan={6}>Data mitra tidak ditemukan.</td>
              </tr>
            ) : (
              paginatedMitras.rows.map(mitra => (
                <tr key={mitra.id}>
                  <td>
                    <div style={{ fontWeight: 600, fontSize: 14 }}>{mitra.kode || '-'}</div>
                    {mitra.status_verifikasi === 'perlu_verifikasi' && <span className="badge badge-warning" style={{ marginTop: 5 }}>Perlu Verifikasi</span>}
                    <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{mitra.nama} • {mitra.alamat || '-'}</div>
                  </td>
                  <td>
                    <div style={{ fontWeight: 500 }}>{mitra.penanggung_jawab || '-'}</div>
                    <div className="table-mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{mitra.no_hp || '-'}</div>
                  </td>
                  <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(mitra.fee_per_kg)}</td>
                  <td className="table-mono" style={{ textAlign: 'right', color: 'var(--text-secondary)' }}>{mitra.tarif_sewa_angkut_per_kg > 0 ? formatRupiah(mitra.tarif_sewa_angkut_per_kg) : '-'}</td>
                  <td className="table-mono" style={{ textAlign: 'right', color: 'var(--text-secondary)' }}>{mitra.dana_operasional_trip > 0 ? formatRupiah(mitra.dana_operasional_trip) : '-'}</td>
                  <td style={{ textAlign: 'center' }}>
                    {canApproveCorrections(userRole) && mitra.status_verifikasi === 'perlu_verifikasi' && (
                      <button className="btn btn-ghost btn-sm" onClick={() => handleVerify(mitra)} aria-label={`Verifikasi ${mitra.nama}`} title="Tandai sudah diperiksa">
                        <CheckCircle2 size={16} />
                      </button>
                    )}
                    <button className="btn btn-ghost btn-sm" onClick={() => openEdit(mitra)} aria-label={`Edit ${mitra.nama}`}>
                      <Pencil size={16} />
                    </button>
                    {canApproveCorrections(userRole) && (
                      <button className="btn btn-ghost btn-sm" onClick={() => setDeleteTarget(mitra)} aria-label={`Nonaktifkan ${mitra.nama}`}>
                        <Trash2 size={16} />
                      </button>
                    )}
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
                  <input type="number" className="form-input" value={formMitra.fee_per_kg} onChange={e => setFormMitra({ ...formMitra, fee_per_kg: e.target.value })} disabled={!canApproveCorrections(userRole)} />
                  {!canApproveCorrections(userRole) && <div className="form-hint">Tarif diperiksa dan diisi oleh Owner.</div>}
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label">Tarif Sewa Armada CB (Rp/Kg Netto)</label>
                    <input type="number" min={0} className="form-input" value={formMitra.tarif_sewa_angkut_per_kg} onChange={e => setFormMitra({ ...formMitra, tarif_sewa_angkut_per_kg: e.target.value })} disabled={!canApproveCorrections(userRole)} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Dana Operasional Armada CB / Trip</label>
                    <input type="number" min={0} className="form-input" value={formMitra.dana_operasional_trip} onChange={e => setFormMitra({ ...formMitra, dana_operasional_trip: e.target.value })} disabled={!canApproveCorrections(userRole)} />
                    <div className="form-hint">Satu jumlah untuk solar, makan, uang jalan, dan bagian sopir.</div>
                  </div>
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Tarif Berlaku Mulai</label>
                    <input type="date" className="form-input" required value={formMitra.fee_berlaku_mulai} onChange={e => setFormMitra({ ...formMitra, fee_berlaku_mulai: e.target.value })} disabled={!canApproveCorrections(userRole)} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Alasan Perubahan Tarif</label>
                    <input className="form-input" value={formMitra.fee_alasan} onChange={e => setFormMitra({ ...formMitra, fee_alasan: e.target.value })} placeholder="Contoh: kesepakatan baru" disabled={!canApproveCorrections(userRole)} />
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
