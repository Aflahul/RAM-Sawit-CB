'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import { FileSpreadsheet } from 'lucide-react';
import {
  MITRA_TYPES,
  formatMitraLabel,
  getMitraTypeBadgeClass,
  getMitraTypeLabel,
  getMitraSearchText,
  getSopirArmadaSearchText,
} from '@/lib/display-labels';
import { paginateRows } from '@/lib/pagination-utils';
import { getNextSort, sortRows } from '@/lib/sort-utils';
import { exportStyledWorkbook } from '@/lib/spreadsheet-export';
import { supabase } from '@/lib/supabase';
import { formatRupiah, getTodayISO } from '@/lib/utils';

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

const sopirSortAccessors = {
  nama: row => row.nama,
  plat: row => row.plat_nomor,
  no_hp: row => row.no_hp,
  mitra: row => formatMitraLabel(row.master_mitra),
};

export default function MasterDataMVPPage() {
  const [activeTab, setActiveTab] = useState('mitra'); // 'mitra' | 'sopir'
  
  // Data State
  const [mitras, setMitras] = useState([]);
  const [sopirs, setSopirs] = useState([]);
  const [loading, setLoading] = useState(true);
  
  // UI State
  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [saving, setSaving] = useState(false);
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState({ key: 'kode', direction: 'asc' });
  const [page, setPage] = useState(1);

  // Forms
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
  const [formSopir, setFormSopir] = useState({ nama: '', no_hp: '', mitra_id: '', plat_nomor: '' });

  const loadData = useCallback(async () => {
    setLoading(true);
    if (activeTab === 'mitra') {
      const { data } = await supabase.from('master_mitra').select('*').eq('aktif', true).order('nama');
      setMitras(data || []);
    } else {
      const { data } = await supabase.from('sopir').select(`
        *,
        master_mitra ( kode, nama, alamat, tipe_mitra )
      `).eq('aktif', true).order('nama');
      
      // We also need mitra for the dropdown when adding a sopir
      const resMitra = await supabase
        .from('master_mitra')
        .select('id, kode, nama, alamat, tipe_mitra')
        .eq('aktif', true)
        .order('kode');
      setMitras(resMitra.data || []);
      
      setSopirs(data || []);
    }
    setLoading(false);
  }, [activeTab]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  function openNew() {
    setEditingId(null);
    if (activeTab === 'mitra') {
      setFormMitra({ kode: '', nama: '', penanggung_jawab: '', no_hp: '', alamat: '', tipe_mitra: MITRA_TYPES.EKSTERNAL, fee_per_kg: 0, fee_berlaku_mulai: getTodayISO(), fee_alasan: '' });
    } else {
      setFormSopir({ nama: '', no_hp: '', mitra_id: '', plat_nomor: '' });
    }
    setShowModal(true);
  }

  function handleTabChange(tab) {
    setActiveTab(tab);
    setSearch('');
    setPage(1);
    setSort(tab === 'mitra'
      ? { key: 'kode', direction: 'asc' }
      : { key: 'nama', direction: 'asc' });
  }

  function handleSort(key) {
    setPage(1);
    setSort(current => getNextSort(current, key));
  }

  function openEdit(item) {
    setEditingId(item.id);
    if (activeTab === 'mitra') {
      setFormMitra({
        kode: item.kode || '',
        nama: item.nama || '',
        penanggung_jawab: item.penanggung_jawab || '',
        no_hp: item.no_hp || '',
        alamat: item.alamat || '',
        tipe_mitra: item.tipe_mitra || MITRA_TYPES.EKSTERNAL,
        fee_per_kg: item.fee_per_kg || 0,
        fee_berlaku_mulai: getTodayISO(),
        fee_alasan: ''
      });
    } else {
      setFormSopir({
        nama: item.nama || '',
        no_hp: item.no_hp || '',
        mitra_id: item.mitra_id || '',
        plat_nomor: item.plat_nomor || ''
      });
    }
    setShowModal(true);
  }
  async function handleSave(e) {
    e.preventDefault();
    setSaving(true);

    if (activeTab === 'mitra') {
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

      if (editingId) {
        const { error } = await supabase.from('master_mitra').update(payload).eq('id', editingId);
        if (error) {
          alert('Gagal menyimpan mitra: ' + error.message);
          setSaving(false);
          return;
        }
      } else {
        const { data, error } = await supabase.from('master_mitra').insert(payload).select('id').single();
        if (error) {
          alert('Gagal menyimpan mitra: ' + error.message);
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
            alasan_perubahan: formMitra.fee_alasan || 'Update Fee Owner dari Master Mitra',
            aktif: true,
          }, { onConflict: 'master_mitra_id,berlaku_mulai' });

        if (historyError) {
          alert('Mitra tersimpan, tetapi riwayat Fee Owner gagal dicatat: ' + historyError.message);
        }
      }
    } else {
      const payload = {
         nama: formSopir.nama, 
         no_hp: formSopir.no_hp || null, 
         mitra_id: formSopir.mitra_id || null, 
         plat_nomor: formSopir.plat_nomor || null
      };
      
      if (editingId) await supabase.from('sopir').update(payload).eq('id', editingId);
      else await supabase.from('sopir').insert(payload);
    }

    setSaving(false);
    setShowModal(false);
    loadData();
  }

  async function handleDelete(id) {
    if (!confirm('Yakin ingin menonaktifkan data ini?')) return;
    if (activeTab === 'mitra') await supabase.from('master_mitra').update({ aktif: false }).eq('id', id);
    else await supabase.from('sopir').update({ aktif: false }).eq('id', id);
    loadData();
  }

  const filteredMitras = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return mitras;
    return mitras.filter(m => getMitraSearchText(m).toLowerCase().includes(keyword));
  }, [mitras, search]);
  const filteredSopirs = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return sopirs;
    return sopirs.filter(s => getSopirArmadaSearchText(s).toLowerCase().includes(keyword));
  }, [search, sopirs]);
  const sortedMitras = useMemo(() => sortRows(filteredMitras, sort, mitraSortAccessors), [filteredMitras, sort]);
  const sortedSopirs = useMemo(() => sortRows(filteredSopirs, sort, sopirSortAccessors), [filteredSopirs, sort]);
  const paginatedMitras = useMemo(() => paginateRows(sortedMitras, page, TABLE_PAGE_SIZE), [page, sortedMitras]);
  const paginatedSopirs = useMemo(() => paginateRows(sortedSopirs, page, TABLE_PAGE_SIZE), [page, sortedSopirs]);

  async function handleExportExcel() {
    const generatedAt = new Date().toLocaleString('id-ID');

    if (activeTab === 'mitra') {
      await exportStyledWorkbook({
        filename: `master-mitra-${getTodayISO()}.xlsx`,
        sheets: [{
          name: 'Master Mitra',
          title: 'MASTER MITRA SAWIT CB',
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
      return;
    }

    await exportStyledWorkbook({
      filename: `master-armada-sopir-${getTodayISO()}.xlsx`,
      sheets: [{
        name: 'Armada Sopir',
        title: 'MASTER ARMADA DAN SOPIR SAWIT CB',
        subtitle: `Total ${sortedSopirs.length.toLocaleString('id-ID')} data | Filter: ${search || 'Semua'} | Dibuat: ${generatedAt}`,
        columns: [
          { header: 'No', value: (_, index) => index + 1, type: 'number', width: 6 },
          { header: 'Sopir Default', key: 'nama', width: 24 },
          { header: 'Plat Default', key: 'plat_nomor', width: 18 },
          { header: 'No. HP / WA', key: 'no_hp', width: 18 },
          { header: 'Kode Mitra Default', value: row => row.master_mitra?.kode || '', width: 18 },
          { header: 'Alamat Mitra Default', value: row => row.master_mitra?.alamat || '', width: 24 },
          { header: 'Nama Mitra Default', value: row => row.master_mitra?.nama || '', width: 24 },
          { header: 'Afiliasi Default', value: row => formatMitraLabel(row.master_mitra) || 'Tanpa default / armada bersama', width: 38 },
        ],
        rows: sortedSopirs,
      }],
    });
  }

  return (
    <AppShell title="Master Data MVP" subtitle="Kelola Mitra dan Armada/Sopir">
      <div className="page-header">
        <div>
          <div style={{ display: 'flex', gap: 16, marginTop: 0 }}>
            <button 
              className={`btn ${activeTab === 'mitra' ? 'btn-primary' : 'btn-outline'}`}
              onClick={() => handleTabChange('mitra')}
            >
              👥 Mitra
            </button>
            <button 
              className={`btn ${activeTab === 'sopir' ? 'btn-primary' : 'btn-outline'}`}
              onClick={() => handleTabChange('sopir')}
            >
              🚚 Armada & Sopir
            </button>
          </div>
        </div>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
          <button
            className="btn btn-outline"
            onClick={handleExportExcel}
            disabled={activeTab === 'mitra' ? sortedMitras.length === 0 : sortedSopirs.length === 0}
          >
            <FileSpreadsheet size={16} />
            Export Excel
          </button>
          <button className="btn btn-primary" onClick={openNew}>
            + Tambah {activeTab === 'mitra' ? 'Mitra' : 'Sopir Default'}
          </button>
        </div>
      </div>

      <div className="toolbar">
        <div className="search-box" style={{ flex: 1, maxWidth: 400 }}>
          <span className="search-box-icon">🔍</span>
          <input
            type="text"
            className="form-input"
            placeholder={`Cari nama ${activeTab === 'mitra' ? 'mitra' : 'sopir'}...`}
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setPage(1);
            }}
            style={{ paddingLeft: 40 }}
          />
        </div>
      </div>

      <div className="table-container">
        <table className="table">
          {activeTab === 'mitra' ? (
            <>
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
                {paginatedMitras.rows.map(m => (
                  <tr key={m.id}>
                    <td className="table-mono" style={{ fontWeight: 600 }}>{m.kode || '-'}</td>
                    <td style={{ fontWeight: 600 }}>{m.nama}</td>
                    <td>
                      <span className={`badge ${getMitraTypeBadgeClass(m.tipe_mitra)}`}>
                        {getMitraTypeLabel(m.tipe_mitra)}
                      </span>
                    </td>
                    <td>{m.penanggung_jawab || '-'}</td>
                    <td className="table-mono">{m.no_hp || '-'}</td>
                    <td>{m.alamat || '-'}</td>
                    <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(m.fee_per_kg)}</td>
                    <td style={{ textAlign: 'center' }}>
                      <button className="btn btn-ghost btn-sm" onClick={() => openEdit(m)}>✏️</button>
                      <button className="btn btn-ghost btn-sm" onClick={() => handleDelete(m.id)}>🗑️</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </>
          ) : (
            <>
               <thead>
                <tr>
                  <SortableHeader label="Sopir Default" sortKey="nama" sort={sort} onSort={handleSort} />
                  <SortableHeader label="Plat Default" sortKey="plat" sort={sort} onSort={handleSort} />
                  <SortableHeader label="No. HP" sortKey="no_hp" sort={sort} onSort={handleSort} />
                  <SortableHeader label="Afiliasi Mitra" sortKey="mitra" sort={sort} onSort={handleSort} />
                  <th style={{ textAlign: 'center' }}>Aksi</th>
                </tr>
              </thead>
              <tbody>
                {paginatedSopirs.rows.map(s => (
                  <tr key={s.id}>
                    <td style={{ fontWeight: 600 }}>{s.nama}</td>
                    <td className="table-mono">{s.plat_nomor || '-'}</td>
                    <td className="table-mono">{s.no_hp || '-'}</td>
                    <td><span className="badge badge-blue">{s.master_mitra ? formatMitraLabel(s.master_mitra) : '-'}</span></td>
                    <td style={{ textAlign: 'center' }}>
                      <button className="btn btn-ghost btn-sm" onClick={() => openEdit(s)}>✏️</button>
                      <button className="btn btn-ghost btn-sm" onClick={() => handleDelete(s.id)}>🗑️</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </>
          )}
        </table>
        {activeTab === 'mitra' ? (
          <TablePagination
            page={paginatedMitras.page}
            totalPages={paginatedMitras.totalPages}
            totalItems={sortedMitras.length}
            startIndex={paginatedMitras.startIndex}
            endIndex={paginatedMitras.endIndex}
            onPageChange={setPage}
          />
        ) : (
          <TablePagination
            page={paginatedSopirs.page}
            totalPages={paginatedSopirs.totalPages}
            totalItems={sortedSopirs.length}
            startIndex={paginatedSopirs.startIndex}
            endIndex={paginatedSopirs.endIndex}
            onPageChange={setPage}
          />
        )}
      </div>

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">
                {editingId ? 'Edit' : 'Tambah'} {activeTab === 'mitra' ? 'Mitra' : 'Sopir'}
              </h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                {activeTab === 'mitra' ? (
                  <>
                    <div className="form-grid">
                      <div className="form-group">
                        <label className="form-label form-label-required">Kode Mitra</label>
                        <input className="form-input" required value={formMitra.kode} onChange={e => setFormMitra({...formMitra, kode: e.target.value})} placeholder="Contoh: SL/HB" />
                      </div>
                      <div className="form-group">
                        <label className="form-label form-label-required">Nama Usaha / Mitra</label>
                        <input className="form-input" required value={formMitra.nama} onChange={e => setFormMitra({...formMitra, nama: e.target.value})} />
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
                      <div className="form-hint">Internal Owner dipakai untuk grup/timbangan milik owner seperti BL/SL. Laporan pendapatan tetap bruto sampai biaya operasional dibuat.</div>
                    </div>
                    <div className="form-grid">
                      <div className="form-group">
                        <label className="form-label">Penanggung Jawab</label>
                        <input className="form-input" value={formMitra.penanggung_jawab} onChange={e => setFormMitra({...formMitra, penanggung_jawab: e.target.value})} />
                      </div>
                      <div className="form-group">
                        <label className="form-label">No. HP / WA</label>
                        <input className="form-input" value={formMitra.no_hp} onChange={e => setFormMitra({...formMitra, no_hp: e.target.value})} />
                      </div>
                    </div>
                    <div className="form-group">
                      <label className="form-label">Alamat / Lokasi</label>
                      <input className="form-input" value={formMitra.alamat} onChange={e => setFormMitra({...formMitra, alamat: e.target.value})} />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Fee Owner (Rp/Kg)</label>
                      <input type="number" className="form-input" value={formMitra.fee_per_kg} onChange={e => setFormMitra({...formMitra, fee_per_kg: e.target.value})} />
                      <div className="form-hint">Potongan owner dari Harga Pabrik/TWB. Harga bersih ke mitra = Harga Pabrik - Fee Owner.</div>
                    </div>
                    <div className="form-grid">
                      <div className="form-group">
                        <label className="form-label form-label-required">Fee Berlaku Mulai</label>
                        <input type="date" className="form-input" required value={formMitra.fee_berlaku_mulai} onChange={e => setFormMitra({...formMitra, fee_berlaku_mulai: e.target.value})} />
                      </div>
                      <div className="form-group">
                        <label className="form-label">Alasan Perubahan Fee</label>
                        <input className="form-input" value={formMitra.fee_alasan} onChange={e => setFormMitra({...formMitra, fee_alasan: e.target.value})} placeholder="Contoh: kesepakatan baru" />
                      </div>
                    </div>
                  </>
                ) : (
                  <>
                    <div className="form-group">
                      <label className="form-label form-label-required">Nama Sopir Default</label>
                      <input className="form-input" required value={formSopir.nama} onChange={e => setFormSopir({...formSopir, nama: e.target.value})} />
                    </div>
                    <div className="form-grid">
                      <div className="form-group">
                        <label className="form-label form-label-required">Plat Default</label>
                        <input className="form-input" required value={formSopir.plat_nomor} onChange={e => setFormSopir({...formSopir, plat_nomor: e.target.value})} placeholder="Contoh: BM 1234 XY" />
                      </div>
                      <div className="form-group">
                        <label className="form-label">No. HP / WA</label>
                        <input className="form-input" value={formSopir.no_hp} onChange={e => setFormSopir({...formSopir, no_hp: e.target.value})} />
                      </div>
                    </div>
                    <div className="form-group">
                      <label className="form-label">Afiliasi Mitra Default</label>
                      <SearchableCombobox
                        value={formSopir.mitra_id}
                        options={mitras}
                        onChange={mitraId => setFormSopir({ ...formSopir, mitra_id: mitraId })}
                        getOptionLabel={formatMitraLabel}
                        getSearchText={getMitraSearchText}
                        placeholder="Tanpa default / cari mitra..."
                        emptyLabel="Mitra tidak ditemukan"
                      />
                      <div className="form-hint">Ini hanya default untuk auto-fill. Mitra transaksi dan sopir aktual tetap bisa diganti saat input timbangan.</div>
                    </div>
                  </>
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
    </AppShell>
  );
}
