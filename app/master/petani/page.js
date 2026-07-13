'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah } from '@/lib/utils';

export default function PetaniPage() {
  const [petaniList, setPetaniList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [search, setSearch] = useState('');
  const [form, setForm] = useState({
    nama: '',
    no_ktp: '',
    no_hp: '',
    alamat: '',
    batas_hutang: 0,
  });
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    loadPetani();
  }, []);

  async function loadPetani() {
    setLoading(true);
    const { data, error } = await supabase
      .from('petani')
      .select('*')
      .eq('aktif', true)
      .order('nama');

    if (!error) setPetaniList(data || []);
    setLoading(false);
  }

  function openNew() {
    setEditingId(null);
    setForm({ nama: '', no_ktp: '', no_hp: '', alamat: '', batas_hutang: 0 });
    setShowModal(true);
  }

  function openEdit(petani) {
    setEditingId(petani.id);
    setForm({
      nama: petani.nama || '',
      no_ktp: petani.no_ktp || '',
      no_hp: petani.no_hp || '',
      alamat: petani.alamat || '',
      batas_hutang: petani.batas_hutang || 0,
    });
    setShowModal(true);
  }

  async function handleSave(e) {
    e.preventDefault();
    setSaving(true);

    const payload = {
      nama: form.nama,
      no_ktp: form.no_ktp || null,
      no_hp: form.no_hp || null,
      alamat: form.alamat || null,
      batas_hutang: parseFloat(form.batas_hutang) || 0,
    };

    if (editingId) {
      await supabase.from('petani').update(payload).eq('id', editingId);
    } else {
      await supabase.from('petani').insert(payload);
    }

    setSaving(false);
    setShowModal(false);
    loadPetani();
  }

  async function handleDelete(id) {
    if (!confirm('Yakin ingin menonaktifkan petani ini?')) return;
    await supabase.from('petani').update({ aktif: false }).eq('id', id);
    loadPetani();
  }

  const filtered = petaniList.filter(
    (p) =>
      p.nama?.toLowerCase().includes(search.toLowerCase()) ||
      p.no_hp?.includes(search)
  );

  return (
    <AppShell title="Petani / Mitra" subtitle="Kelola data petani dan mitra TBS">
      <div className="page-header">
        <div>
          <p className="page-description">Total: {petaniList.length} petani aktif</p>
        </div>
        <button className="btn btn-primary" onClick={openNew}>
          + Tambah Petani
        </button>
      </div>

      {/* Search */}
      <div className="toolbar">
        <div className="search-box" style={{ flex: 1, maxWidth: 400 }}>
          <span className="search-box-icon">🔍</span>
          <input
            type="text"
            className="form-input"
            placeholder="Cari nama atau nomor HP..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ paddingLeft: 40 }}
          />
        </div>
      </div>

      {/* Table */}
      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {[1, 2, 3, 4, 5].map((i) => (
            <div key={i} className="skeleton" style={{ height: 52 }}></div>
          ))}
        </div>
      ) : filtered.length === 0 ? (
        <div className="empty-state">
          <div className="empty-state-icon">👥</div>
          <div className="empty-state-title">
            {search ? 'Tidak ditemukan' : 'Belum ada data petani'}
          </div>
          <div className="empty-state-text">
            {search
              ? 'Coba ubah kata pencarian'
              : 'Klik "Tambah Petani" untuk menambahkan data petani baru'}
          </div>
        </div>
      ) : (
        <div className="table-container">
          <table className="table">
            <thead>
              <tr>
                <th>Nama</th>
                <th>No. HP</th>
                <th>Alamat</th>
                <th style={{ textAlign: 'right' }}>Batas Hutang</th>
                <th style={{ textAlign: 'center' }}>Aksi</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((p) => (
                <tr key={p.id}>
                  <td style={{ fontWeight: 600 }}>{p.nama}</td>
                  <td className="table-mono">{p.no_hp || '-'}</td>
                  <td>{p.alamat || '-'}</td>
                  <td className="table-mono" style={{ textAlign: 'right' }}>
                    {p.batas_hutang > 0 ? formatRupiah(p.batas_hutang) : <span className="text-tertiary">Tidak ada</span>}
                  </td>
                  <td style={{ textAlign: 'center' }}>
                    <div className="flex justify-center gap-xs">
                      <button className="btn btn-ghost btn-sm" onClick={() => openEdit(p)}>
                        ✏️
                      </button>
                      <button className="btn btn-ghost btn-sm" onClick={() => handleDelete(p.id)}>
                        🗑️
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Modal */}
      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">
                {editingId ? 'Edit Petani' : 'Tambah Petani Baru'}
              </h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>
                ✕
              </button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                <div className="form-group">
                  <label className="form-label form-label-required">Nama Petani</label>
                  <input
                    className="form-input"
                    value={form.nama}
                    onChange={(e) => setForm({ ...form, nama: e.target.value })}
                    placeholder="Masukkan nama lengkap"
                    required
                  />
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label">No. KTP</label>
                    <input
                      className="form-input"
                      value={form.no_ktp}
                      onChange={(e) => setForm({ ...form, no_ktp: e.target.value })}
                      placeholder="16 digit"
                      maxLength={16}
                    />
                  </div>
                  <div className="form-group">
                    <label className="form-label">No. HP</label>
                    <input
                      className="form-input"
                      value={form.no_hp}
                      onChange={(e) => setForm({ ...form, no_hp: e.target.value })}
                      placeholder="08xxxxxxxxxx"
                    />
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label">Alamat</label>
                  <input
                    className="form-input"
                    value={form.alamat}
                    onChange={(e) => setForm({ ...form, alamat: e.target.value })}
                    placeholder="Alamat petani"
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Batas Hutang Maksimal (Rp)</label>
                  <input
                    type="number"
                    className="form-input form-input-mono"
                    value={form.batas_hutang}
                    onChange={(e) => setForm({ ...form, batas_hutang: e.target.value })}
                    placeholder="0 = tidak ada batas"
                    min={0}
                    step={1000}
                  />
                  <div className="form-hint">Isi 0 jika tidak ingin membatasi hutang petani ini</div>
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" onClick={() => setShowModal(false)}>
                  Batal
                </button>
                <button type="submit" className="btn btn-primary" disabled={saving}>
                  {saving ? 'Menyimpan...' : editingId ? 'Simpan Perubahan' : 'Tambah Petani'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AppShell>
  );
}
