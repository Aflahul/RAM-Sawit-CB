'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';

export default function ArmadaPage() {
  const [activeTab, setActiveTab] = useState('kendaraan');
  const [kendaraanList, setKendaraanList] = useState([]);
  const [sopirList, setSopirList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [saving, setSaving] = useState(false);

  const [kendaraanForm, setKendaraanForm] = useState({
    plat_nomor: '', jenis: '', kapasitas_ton: '', kepemilikan: 'sendiri',
  });
  const [sopirForm, setSopirForm] = useState({
    nama: '', no_hp: '', kendaraan_id: '',
  });

  useEffect(() => { loadData(); }, []);

  async function loadData() {
    setLoading(true);
    const [{ data: kData }, { data: sData }] = await Promise.all([
      supabase.from('kendaraan').select('*').eq('aktif', true).order('plat_nomor'),
      supabase.from('sopir').select('*, kendaraan:kendaraan_id(plat_nomor)').eq('aktif', true).order('nama'),
    ]);
    setKendaraanList(kData || []);
    setSopirList(sData || []);
    setLoading(false);
  }

  function openNewKendaraan() {
    setEditingId(null);
    setKendaraanForm({ plat_nomor: '', jenis: '', kapasitas_ton: '', kepemilikan: 'sendiri' });
    setShowModal('kendaraan');
  }

  function openNewSopir() {
    setEditingId(null);
    setSopirForm({ nama: '', no_hp: '', kendaraan_id: '' });
    setShowModal('sopir');
  }

  function editKendaraan(k) {
    setEditingId(k.id);
    setKendaraanForm({
      plat_nomor: k.plat_nomor, jenis: k.jenis || '',
      kapasitas_ton: k.kapasitas_ton || '', kepemilikan: k.kepemilikan || 'sendiri',
    });
    setShowModal('kendaraan');
  }

  function editSopir(s) {
    setEditingId(s.id);
    setSopirForm({ nama: s.nama, no_hp: s.no_hp || '', kendaraan_id: s.kendaraan_id || '' });
    setShowModal('sopir');
  }

  async function saveKendaraan(e) {
    e.preventDefault();
    setSaving(true);
    const payload = {
      plat_nomor: kendaraanForm.plat_nomor,
      jenis: kendaraanForm.jenis || null,
      kapasitas_ton: parseFloat(kendaraanForm.kapasitas_ton) || null,
      kepemilikan: kendaraanForm.kepemilikan,
    };
    if (editingId) {
      await supabase.from('kendaraan').update(payload).eq('id', editingId);
    } else {
      await supabase.from('kendaraan').insert(payload);
    }
    setSaving(false);
    setShowModal(false);
    loadData();
  }

  async function saveSopir(e) {
    e.preventDefault();
    setSaving(true);
    const payload = {
      nama: sopirForm.nama,
      no_hp: sopirForm.no_hp || null,
      kendaraan_id: sopirForm.kendaraan_id || null,
    };
    if (editingId) {
      await supabase.from('sopir').update(payload).eq('id', editingId);
    } else {
      await supabase.from('sopir').insert(payload);
    }
    setSaving(false);
    setShowModal(false);
    loadData();
  }

  async function deleteKendaraan(id) {
    if (!confirm('Nonaktifkan kendaraan ini?')) return;
    await supabase.from('kendaraan').update({ aktif: false }).eq('id', id);
    loadData();
  }

  async function deleteSopir(id) {
    if (!confirm('Nonaktifkan sopir ini?')) return;
    await supabase.from('sopir').update({ aktif: false }).eq('id', id);
    loadData();
  }

  return (
    <AppShell title="Armada & Sopir" subtitle="Kelola data kendaraan dan sopir">
      <div className="page-header" style={{ justifyContent: 'flex-end' }}>
        <div className="flex gap-sm">
          <button className="btn btn-outline" onClick={openNewKendaraan}>+ Kendaraan</button>
          <button className="btn btn-primary" onClick={openNewSopir}>+ Sopir</button>
        </div>
      </div>

      {/* Tabs */}
      <div className="tabs">
        <button className={`tab ${activeTab === 'kendaraan' ? 'active' : ''}`} onClick={() => setActiveTab('kendaraan')}>
          🚛 Kendaraan ({kendaraanList.length})
        </button>
        <button className={`tab ${activeTab === 'sopir' ? 'active' : ''}`} onClick={() => setActiveTab('sopir')}>
          👤 Sopir ({sopirList.length})
        </button>
      </div>

      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {[1, 2, 3].map((i) => <div key={i} className="skeleton" style={{ height: 52 }}></div>)}
        </div>
      ) : activeTab === 'kendaraan' ? (
        kendaraanList.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-icon">🚛</div>
            <div className="empty-state-title">Belum ada kendaraan</div>
            <div className="empty-state-text">Klik tombol Kendaraan untuk menambahkan</div>
          </div>
        ) : (
          <div className="table-container">
            <table className="table">
              <thead>
                <tr>
                  <th>Plat Nomor</th>
                  <th>Jenis</th>
                  <th>Kapasitas</th>
                  <th>Kepemilikan</th>
                  <th style={{ textAlign: 'center' }}>Aksi</th>
                </tr>
              </thead>
              <tbody>
                {kendaraanList.map((k) => (
                  <tr key={k.id}>
                    <td className="table-mono" style={{ fontWeight: 600 }}>{k.plat_nomor}</td>
                    <td>{k.jenis || '-'}</td>
                    <td>{k.kapasitas_ton ? `${k.kapasitas_ton} ton` : '-'}</td>
                    <td>
                      <span className={`badge ${k.kepemilikan === 'sendiri' ? 'badge-success' : 'badge-warning'}`}>
                        {k.kepemilikan === 'sendiri' ? 'Milik Sendiri' : 'Sewa'}
                      </span>
                    </td>
                    <td style={{ textAlign: 'center' }}>
                      <button className="btn btn-ghost btn-sm" onClick={() => editKendaraan(k)}>✏️</button>
                      <button className="btn btn-ghost btn-sm" onClick={() => deleteKendaraan(k.id)}>🗑️</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )
      ) : (
        sopirList.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-icon">👤</div>
            <div className="empty-state-title">Belum ada sopir</div>
            <div className="empty-state-text">Klik tombol Sopir untuk menambahkan</div>
          </div>
        ) : (
          <div className="table-container">
            <table className="table">
              <thead>
                <tr>
                  <th>Nama Sopir</th>
                  <th>No. HP</th>
                  <th>Kendaraan</th>
                  <th style={{ textAlign: 'center' }}>Aksi</th>
                </tr>
              </thead>
              <tbody>
                {sopirList.map((s) => (
                  <tr key={s.id}>
                    <td style={{ fontWeight: 600 }}>{s.nama}</td>
                    <td className="table-mono">{s.no_hp || '-'}</td>
                    <td className="table-mono">{s.kendaraan?.plat_nomor || '-'}</td>
                    <td style={{ textAlign: 'center' }}>
                      <button className="btn btn-ghost btn-sm" onClick={() => editSopir(s)}>✏️</button>
                      <button className="btn btn-ghost btn-sm" onClick={() => deleteSopir(s.id)}>🗑️</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )
      )}

      {/* Modal Kendaraan */}
      {showModal === 'kendaraan' && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">{editingId ? 'Edit' : 'Tambah'} Kendaraan</h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <form onSubmit={saveKendaraan}>
              <div className="modal-body">
                <div className="form-group">
                  <label className="form-label form-label-required">Plat Nomor</label>
                  <input className="form-input form-input-mono" value={kendaraanForm.plat_nomor}
                    onChange={(e) => setKendaraanForm({ ...kendaraanForm, plat_nomor: e.target.value.toUpperCase() })}
                    placeholder="KT 1234 AB" required />
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label">Jenis Kendaraan</label>
                    <input className="form-input" value={kendaraanForm.jenis}
                      onChange={(e) => setKendaraanForm({ ...kendaraanForm, jenis: e.target.value })}
                      placeholder="Truk, Pickup, dll" />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Kapasitas (ton)</label>
                    <input type="number" className="form-input form-input-mono" value={kendaraanForm.kapasitas_ton}
                      onChange={(e) => setKendaraanForm({ ...kendaraanForm, kapasitas_ton: e.target.value })}
                      placeholder="0" min={0} step={0.1} />
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label">Kepemilikan</label>
                  <select className="form-input form-select" value={kendaraanForm.kepemilikan}
                    onChange={(e) => setKendaraanForm({ ...kendaraanForm, kepemilikan: e.target.value })}>
                    <option value="sendiri">Milik Sendiri</option>
                    <option value="sewa">Sewa / Pihak Ketiga</option>
                  </select>
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

      {/* Modal Sopir */}
      {showModal === 'sopir' && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">{editingId ? 'Edit' : 'Tambah'} Sopir</h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <form onSubmit={saveSopir}>
              <div className="modal-body">
                <div className="form-group">
                  <label className="form-label form-label-required">Nama Sopir</label>
                  <input className="form-input" value={sopirForm.nama}
                    onChange={(e) => setSopirForm({ ...sopirForm, nama: e.target.value })}
                    placeholder="Nama lengkap" required />
                </div>
                <div className="form-group">
                  <label className="form-label">No. HP</label>
                  <input className="form-input" value={sopirForm.no_hp}
                    onChange={(e) => setSopirForm({ ...sopirForm, no_hp: e.target.value })}
                    placeholder="08xxxxxxxxxx" />
                </div>
                <div className="form-group">
                  <label className="form-label">Kendaraan</label>
                  <select className="form-input form-select" value={sopirForm.kendaraan_id}
                    onChange={(e) => setSopirForm({ ...sopirForm, kendaraan_id: e.target.value })}>
                    <option value="">-- Tidak ada --</option>
                    {kendaraanList.map((k) => (
                      <option key={k.id} value={k.id}>{k.plat_nomor} ({k.jenis || '-'})</option>
                    ))}
                  </select>
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
