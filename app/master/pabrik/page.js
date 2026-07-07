'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';

export default function PabrikPage() {
  const [list, setList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({ nama: '', alamat: '', no_hp: '' });

  useEffect(() => { loadData(); }, []);

  async function loadData() {
    setLoading(true);
    const { data } = await supabase.from('pabrik').select('*').eq('aktif', true).order('nama');
    setList(data || []);
    setLoading(false);
  }

  function openNew() {
    setEditingId(null);
    setForm({ nama: '', alamat: '', no_hp: '' });
    setShowModal(true);
  }

  function openEdit(p) {
    setEditingId(p.id);
    setForm({ nama: p.nama, alamat: p.alamat || '', no_hp: p.no_hp || '' });
    setShowModal(true);
  }

  async function handleSave(e) {
    e.preventDefault();
    setSaving(true);
    const payload = { nama: form.nama, alamat: form.alamat || null, no_hp: form.no_hp || null };
    if (editingId) {
      await supabase.from('pabrik').update(payload).eq('id', editingId);
    } else {
      await supabase.from('pabrik').insert(payload);
    }
    setSaving(false);
    setShowModal(false);
    loadData();
  }

  async function handleDelete(id) {
    if (!confirm('Nonaktifkan pabrik ini?')) return;
    await supabase.from('pabrik').update({ aktif: false }).eq('id', id);
    loadData();
  }

  return (
    <AppShell title="Pabrik Tujuan" subtitle="Kelola data pabrik pengolahan">
      <div className="page-header">
        <h2 className="page-title">Pabrik Tujuan</h2>
        <button className="btn btn-primary" onClick={openNew}>+ Tambah Pabrik</button>
      </div>

      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {[1, 2, 3].map((i) => <div key={i} className="skeleton" style={{ height: 52 }}></div>)}
        </div>
      ) : list.length === 0 ? (
        <div className="empty-state">
          <div className="empty-state-icon">🏭</div>
          <div className="empty-state-title">Belum ada pabrik</div>
          <div className="empty-state-text">Tambahkan pabrik tujuan pengiriman TBS</div>
        </div>
      ) : (
        <div className="table-container">
          <table className="table">
            <thead>
              <tr><th>Nama Pabrik</th><th>Alamat</th><th>No. HP</th><th style={{ textAlign: 'center' }}>Aksi</th></tr>
            </thead>
            <tbody>
              {list.map((p) => (
                <tr key={p.id}>
                  <td style={{ fontWeight: 600 }}>{p.nama}</td>
                  <td>{p.alamat || '-'}</td>
                  <td className="table-mono">{p.no_hp || '-'}</td>
                  <td style={{ textAlign: 'center' }}>
                    <button className="btn btn-ghost btn-sm" onClick={() => openEdit(p)}>✏️</button>
                    <button className="btn btn-ghost btn-sm" onClick={() => handleDelete(p.id)}>🗑️</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">{editingId ? 'Edit' : 'Tambah'} Pabrik</h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                <div className="form-group">
                  <label className="form-label form-label-required">Nama Pabrik</label>
                  <input className="form-input" value={form.nama}
                    onChange={(e) => setForm({ ...form, nama: e.target.value })} required />
                </div>
                <div className="form-group">
                  <label className="form-label">Alamat</label>
                  <input className="form-input" value={form.alamat}
                    onChange={(e) => setForm({ ...form, alamat: e.target.value })} />
                </div>
                <div className="form-group">
                  <label className="form-label">No. HP / Kontak</label>
                  <input className="form-input" value={form.no_hp}
                    onChange={(e) => setForm({ ...form, no_hp: e.target.value })} />
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
