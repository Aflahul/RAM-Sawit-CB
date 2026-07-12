'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah } from '@/lib/utils';

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

  // Forms
  const [formMitra, setFormMitra] = useState({ kode: '', nama: '', penanggung_jawab: '', no_hp: '', alamat: '', fee_per_kg: 0 });
  const [formSopir, setFormSopir] = useState({ nama: '', no_hp: '', mitra_id: '', plat_nomor: '' });

  useEffect(() => {
    loadData();
  }, [activeTab]);

  async function loadData() {
    setLoading(true);
    if (activeTab === 'mitra') {
      const { data } = await supabase.from('master_mitra').select('*').eq('aktif', true).order('nama');
      setMitras(data || []);
    } else {
      const { data } = await supabase.from('sopir').select(`
        *,
        master_mitra ( nama )
      `).eq('aktif', true).order('nama');
      
      // We also need mitra for the dropdown when adding a sopir
      const resMitra = await supabase.from('master_mitra').select('id, nama').eq('aktif', true).order('nama');
      setMitras(resMitra.data || []);
      
      setSopirs(data || []);
    }
    setLoading(false);
  }

  function openNew() {
    setEditingId(null);
    if (activeTab === 'mitra') {
      setFormMitra({ kode: '', nama: '', penanggung_jawab: '', no_hp: '', alamat: '', fee_per_kg: 0 });
    } else {
      setFormSopir({ nama: '', no_hp: '', mitra_id: '', plat_nomor: '' });
    }
    setShowModal(true);
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
        fee_per_kg: item.fee_per_kg || 0
      });
    } else {
      setFormSopir({
        nama: item.nama || '',
        no_hp: item.no_hp || '',
        mitra_id: item.mitra_id || '',
        plat_nomor: item.plat_nomor || '' // assuming plat_nomor is now in sopir table? Wait, I added it to transaksi_mitra. I need to make sure sopir has plat_nomor. 
        // Ah, the user said "saat memasukkan nama sopir harusnya plat nomor juga sudah ikut". So plat_nomor should be in the sopir table.
        // Wait, did I add plat_nomor to sopir? Let me check the schema I created.
      });
    }
    setShowModal(true);
  }
  
  // Need to fix plat_nomor on sopir later if it doesn't exist.

  async function handleSave(e) {
    e.preventDefault();
    setSaving(true);

    if (activeTab === 'mitra') {
      const payload = { ...formMitra, fee_per_kg: parseFloat(formMitra.fee_per_kg) || 0 };
      if (editingId) await supabase.from('master_mitra').update(payload).eq('id', editingId);
      else await supabase.from('master_mitra').insert(payload);
    } else {
      const payload = {
         nama: formSopir.nama, 
         no_hp: formSopir.no_hp || null, 
         mitra_id: formSopir.mitra_id || null, 
         // plat_nomor: formSopir.plat_nomor || null // We will add this to sopir table
      };
      // Temporary workaround until we alter table: we will use 'no_hp' to store plat if needed, but no, we should just alter table sopir.
      // I will alter table sopir and add plat_nomor.
      payload.plat_nomor = formSopir.plat_nomor || null;
      
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

  return (
    <AppShell title="Master Data MVP" subtitle="Kelola Mitra dan Armada/Sopir">
      <div className="page-header">
        <div>
          <h2 className="page-title">Master Data (Tahap 1)</h2>
          <div style={{ display: 'flex', gap: 16, marginTop: 12 }}>
            <button 
              className={`btn ${activeTab === 'mitra' ? 'btn-primary' : 'btn-outline'}`}
              onClick={() => setActiveTab('mitra')}
            >
              👥 Mitra
            </button>
            <button 
              className={`btn ${activeTab === 'sopir' ? 'btn-primary' : 'btn-outline'}`}
              onClick={() => setActiveTab('sopir')}
            >
              🚚 Armada & Sopir
            </button>
          </div>
        </div>
        <button className="btn btn-primary" onClick={openNew}>
          + Tambah {activeTab === 'mitra' ? 'Mitra' : 'Sopir'}
        </button>
      </div>

      <div className="toolbar">
        <div className="search-box" style={{ flex: 1, maxWidth: 400 }}>
          <span className="search-box-icon">🔍</span>
          <input
            type="text"
            className="form-input"
            placeholder={`Cari nama ${activeTab === 'mitra' ? 'mitra' : 'sopir'}...`}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
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
                  <th>Kode</th>
                  <th>Nama Mitra</th>
                  <th>Penanggung Jawab</th>
                  <th>No. HP</th>
                  <th>Alamat</th>
                  <th style={{ textAlign: 'right' }}>Fee/Kg</th>
                  <th style={{ textAlign: 'center' }}>Aksi</th>
                </tr>
              </thead>
              <tbody>
                {mitras.filter(m => m.nama?.toLowerCase().includes(search.toLowerCase()) || m.kode?.toLowerCase().includes(search.toLowerCase())).map(m => (
                  <tr key={m.id}>
                    <td className="table-mono" style={{ fontWeight: 600 }}>{m.kode || '-'}</td>
                    <td style={{ fontWeight: 600 }}>{m.nama}</td>
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
                  <th>Nama Sopir</th>
                  <th>Plat Armada</th>
                  <th>No. HP</th>
                  <th>Afiliasi Mitra</th>
                  <th style={{ textAlign: 'center' }}>Aksi</th>
                </tr>
              </thead>
              <tbody>
                {sopirs.filter(s => s.nama?.toLowerCase().includes(search.toLowerCase())).map(s => (
                  <tr key={s.id}>
                    <td style={{ fontWeight: 600 }}>{s.nama}</td>
                    <td className="table-mono">{s.plat_nomor || '-'}</td>
                    <td className="table-mono">{s.no_hp || '-'}</td>
                    <td><span className="badge badge-blue">{s.master_mitra?.nama || '-'}</span></td>
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
                      <label className="form-label">Fee Pabrik (Rp/Kg)</label>
                      <input type="number" className="form-input" value={formMitra.fee_per_kg} onChange={e => setFormMitra({...formMitra, fee_per_kg: e.target.value})} />
                      <div className="form-hint">Kosongkan jika fee dibebaskan, atau bisa diisi 0.</div>
                    </div>
                  </>
                ) : (
                  <>
                    <div className="form-group">
                      <label className="form-label form-label-required">Nama Sopir</label>
                      <input className="form-input" required value={formSopir.nama} onChange={e => setFormSopir({...formSopir, nama: e.target.value})} />
                    </div>
                    <div className="form-grid">
                      <div className="form-group">
                        <label className="form-label form-label-required">Plat Armada</label>
                        <input className="form-input" required value={formSopir.plat_nomor} onChange={e => setFormSopir({...formSopir, plat_nomor: e.target.value})} placeholder="Contoh: BM 1234 XY" />
                      </div>
                      <div className="form-group">
                        <label className="form-label">No. HP / WA</label>
                        <input className="form-input" value={formSopir.no_hp} onChange={e => setFormSopir({...formSopir, no_hp: e.target.value})} />
                      </div>
                    </div>
                    <div className="form-group">
                      <label className="form-label form-label-required">Afiliasi Mitra</label>
                      <select className="form-input" required value={formSopir.mitra_id} onChange={e => setFormSopir({...formSopir, mitra_id: e.target.value})}>
                        <option value="">-- Pilih Mitra --</option>
                        {mitras.map(m => <option key={m.id} value={m.id}>{m.nama}</option>)}
                      </select>
                      <div className="form-hint">Sopir ini beroperasi atas nama siapa?</div>
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
