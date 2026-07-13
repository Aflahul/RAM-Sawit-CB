'use client';

import { useMemo, useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import { formatMitraLabel, getMitraSearchText } from '@/lib/display-labels';
import { paginateRows } from '@/lib/pagination-utils';
import { getNextSort, sortRows } from '@/lib/sort-utils';
import { supabase } from '@/lib/supabase';
import { formatRupiah, getTodayISO } from '@/lib/utils';

const TABLE_PAGE_SIZE = 20;

const panjarSortAccessors = {
  tanggal: row => row.tanggal,
  mitra: row => formatMitraLabel(row.master_mitra),
  keterangan: row => row.keterangan,
  jumlah: row => Number(row.jumlah),
  status: row => row.status,
};

export default function PanjarMitraPage() {
  const [panjars, setPanjars] = useState([]);
  const [mitras, setMitras] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [saving, setSaving] = useState(false);
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState({ key: 'tanggal', direction: 'desc' });
  const [page, setPage] = useState(1);

  const [form, setForm] = useState({
    tanggal: '',
    mitra_id: '',
    jumlah: '',
    keterangan: ''
  });

  useEffect(() => {
    loadData();
  }, []);

  async function loadData() {
    setLoading(true);
    
    // Load Panjar
    const { data: pData } = await supabase
      .from('panjar_mitra')
      .select(`
        *,
        master_mitra ( kode, alamat, nama )
      `)
      .order('tanggal', { ascending: false });
      
    setPanjars(pData || []);

    // Load Mitra
    const { data: mData } = await supabase
      .from('master_mitra')
      .select('id, kode, alamat, nama')
      .eq('aktif', true)
      .order('kode');
      
    setMitras(mData || []);
    
    setLoading(false);
  }

  function openNew() {
    setForm({ tanggal: getTodayISO(), mitra_id: '', jumlah: '', keterangan: '' });
    setShowModal(true);
  }

  async function handleSave(e) {
    e.preventDefault();
    setSaving(true);

    if (!form.mitra_id) {
      alert("Pilih mitra terlebih dahulu.");
      setSaving(false);
      return;
    }

    const payload = {
      tanggal: form.tanggal,
      mitra_id: form.mitra_id,
      jumlah: parseFloat(form.jumlah) || 0,
      keterangan: form.keterangan || null,
      status: 'belum_lunas'
    };

    const { error } = await supabase.from('panjar_mitra').insert(payload);
    
    if (error) {
      alert("Gagal menyimpan panjar: " + error.message);
    } else {
      setShowModal(false);
      loadData();
    }
    
    setSaving(false);
  }

  async function handleLunasi(id) {
    if (!confirm('Tandai panjar ini sebagai LUNAS? (Biasanya dilakukan saat atau setelah cetak kwitansi)')) return;
    
    await supabase.from('panjar_mitra').update({ status: 'lunas' }).eq('id', id);
    loadData();
  }

  async function handleDelete(id) {
    if (!confirm('Hapus data panjar ini?')) return;
    await supabase.from('panjar_mitra').delete().eq('id', id);
    loadData();
  }

  function handleSort(key) {
    setPage(1);
    setSort(current => getNextSort(current, key, key === 'tanggal' ? 'desc' : 'asc'));
  }

  const filteredPanjars = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return panjars;
    return panjars.filter(p => getMitraSearchText(p.master_mitra || {}).toLowerCase().includes(keyword));
  }, [panjars, search]);
  const sortedPanjars = useMemo(() => {
    return sortRows(filteredPanjars, sort, panjarSortAccessors);
  }, [filteredPanjars, sort]);
  const paginatedPanjars = useMemo(() => {
    return paginateRows(sortedPanjars, page, TABLE_PAGE_SIZE);
  }, [page, sortedPanjars]);

  return (
    <AppShell title="Panjar Mitra" subtitle="Kelola kasbon/panjar mitra">
      <div className="page-header">
        <div>
          <p className="page-description">Kasbon yang akan memotong otomatis tagihan kwitansi</p>
        </div>
        <button className="btn btn-primary" onClick={openNew}>
          + Tambah Panjar
        </button>
      </div>

      <div className="toolbar">
        <div className="search-box" style={{ flex: 1, maxWidth: 400 }}>
          <span className="search-box-icon">🔍</span>
          <input
            type="text"
            className="form-input"
            placeholder="Cari nama mitra..."
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
          <thead>
            <tr>
              <SortableHeader label="Tanggal" sortKey="tanggal" sort={sort} onSort={handleSort} />
              <SortableHeader label="Nama Mitra" sortKey="mitra" sort={sort} onSort={handleSort} />
              <SortableHeader label="Keterangan" sortKey="keterangan" sort={sort} onSort={handleSort} />
              <SortableHeader label="Jumlah (Rp)" sortKey="jumlah" sort={sort} onSort={handleSort} align="right" />
              <SortableHeader label="Status" sortKey="status" sort={sort} onSort={handleSort} align="center" />
              <th style={{ textAlign: 'center' }}>Aksi</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={6} style={{ textAlign: 'center', padding: 24 }}>Memuat data...</td></tr>
            ) : sortedPanjars.length === 0 ? (
              <tr><td colSpan={6} style={{ textAlign: 'center', padding: 24 }}>Belum ada data panjar</td></tr>
            ) : (
              paginatedPanjars.rows.map(p => (
                <tr key={p.id}>
                  <td>{p.tanggal}</td>
                  <td style={{ fontWeight: 600 }}>
                    {p.master_mitra ? formatMitraLabel(p.master_mitra) : '-'}
                  </td>
                  <td>{p.keterangan || '-'}</td>
                  <td className="table-mono" style={{ textAlign: 'right', fontWeight: 'bold' }}>
                    {formatRupiah(p.jumlah)}
                  </td>
                  <td style={{ textAlign: 'center' }}>
                    {p.status === 'belum_lunas' ? (
                      <span className="badge badge-red">Belum Lunas</span>
                    ) : (
                      <span className="badge badge-green">Lunas</span>
                    )}
                  </td>
                  <td style={{ textAlign: 'center', display: 'flex', gap: 8, justifyContent: 'center' }}>
                    {p.status === 'belum_lunas' && (
                      <button className="btn btn-ghost btn-sm" onClick={() => handleLunasi(p.id)} title="Tandai Lunas">✅</button>
                    )}
                    <button className="btn btn-ghost btn-sm" onClick={() => handleDelete(p.id)} title="Hapus">🗑️</button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        <TablePagination
          page={paginatedPanjars.page}
          totalPages={paginatedPanjars.totalPages}
          totalItems={sortedPanjars.length}
          startIndex={paginatedPanjars.startIndex}
          endIndex={paginatedPanjars.endIndex}
          onPageChange={setPage}
        />
      </div>

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Tambah Panjar Mitra</h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                <div className="form-group">
                  <label className="form-label form-label-required">Tanggal Pencairan</label>
                  <input type="date" className="form-input" required value={form.tanggal} onChange={e => setForm({...form, tanggal: e.target.value})} />
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Pilih Mitra</label>
                  <SearchableCombobox
                    value={form.mitra_id}
                    options={mitras}
                    onChange={mitraId => setForm({ ...form, mitra_id: mitraId })}
                    getOptionLabel={formatMitraLabel}
                    getSearchText={getMitraSearchText}
                    placeholder="Cari kode, alamat, atau nama mitra..."
                    emptyLabel="Mitra tidak ditemukan"
                  />
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Jumlah Panjar (Rp)</label>
                  <input type="number" className="form-input" required min={1} value={form.jumlah} onChange={e => setForm({...form, jumlah: e.target.value})} />
                  <div style={{ display: 'flex', gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
                    {[1, 5, 10, 50, 100].map(val => (
                      <button 
                        key={val} 
                        type="button" 
                        className="btn btn-outline btn-sm" 
                        onClick={() => setForm(prev => ({ ...prev, jumlah: (Number(prev.jumlah) || 0) + (val * 1000000) }))}
                        style={{ padding: '4px 8px', fontSize: 12 }}
                      >
                        + {val} Jt
                      </button>
                    ))}
                    <button 
                      type="button" 
                      className="btn btn-ghost btn-sm" 
                      onClick={() => setForm(prev => ({ ...prev, jumlah: '' }))}
                      style={{ padding: '4px 8px', fontSize: 12, color: 'var(--text-tertiary)' }}
                    >
                      Reset
                    </button>
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label">Keterangan (Opsional)</label>
                  <input type="text" className="form-input" value={form.keterangan} onChange={e => setForm({...form, keterangan: e.target.value})} placeholder="Contoh: Pinjaman operasional truk" />
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" onClick={() => setShowModal(false)}>Batal</button>
                <button type="submit" className="btn btn-primary" disabled={saving}>
                  {saving ? 'Menyimpan...' : 'Simpan Kasbon'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AppShell>
  );
}
