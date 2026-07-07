'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, formatNumber, getTodayISO } from '@/lib/utils';

export default function PengirimanPage() {
  const [list, setList] = useState([]);
  const [sopirList, setSopirList] = useState([]);
  const [kendaraanList, setKendaraanList] = useState([]);
  const [pabrikList, setPabrikList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [showUpdateModal, setShowUpdateModal] = useState(null);
  const [saving, setSaving] = useState(false);
  const [filter, setFilter] = useState('semua');

  const [form, setForm] = useState({
    tanggal: getTodayISO(), sopir_id: '', kendaraan_id: '',
    pabrik_id: '', tonase_kirim: '', no_do: '',
  });
  const [updateForm, setUpdateForm] = useState({
    status: '', harga_pabrik_per_kg: '', tanggal_bayar: '',
  });

  useEffect(() => { loadAll(); }, []);

  async function loadAll() {
    setLoading(true);
    const [{ data: peng }, { data: sop }, { data: ken }, { data: pab }] = await Promise.all([
      supabase.from('pengiriman').select('*, sopir:sopir_id(nama), kendaraan:kendaraan_id(plat_nomor), pabrik:pabrik_id(nama)').order('tanggal', { ascending: false }).limit(50),
      supabase.from('sopir').select('*').eq('aktif', true).order('nama'),
      supabase.from('kendaraan').select('*').eq('aktif', true).order('plat_nomor'),
      supabase.from('pabrik').select('*').eq('aktif', true).order('nama'),
    ]);
    setList(peng || []);
    setSopirList(sop || []);
    setKendaraanList(ken || []);
    setPabrikList(pab || []);
    setLoading(false);
  }

  async function handleSave(e) {
    e.preventDefault();
    setSaving(true);
    const { data: { session } } = await supabase.auth.getSession();
    await supabase.from('pengiriman').insert({
      tanggal: form.tanggal,
      sopir_id: form.sopir_id || null,
      kendaraan_id: form.kendaraan_id || null,
      pabrik_id: form.pabrik_id,
      tonase_kirim: parseFloat(form.tonase_kirim),
      no_do: form.no_do || null,
      status: 'dikirim',
      created_by: session?.user?.id || null,
    });
    setSaving(false);
    setShowModal(false);
    setForm({ tanggal: getTodayISO(), sopir_id: '', kendaraan_id: '', pabrik_id: '', tonase_kirim: '', no_do: '' });
    loadAll();
  }

  async function handleUpdate(e) {
    e.preventDefault();
    setSaving(true);
    const payload = { status: updateForm.status };
    if (updateForm.status === 'dibayar') {
      payload.harga_pabrik_per_kg = parseFloat(updateForm.harga_pabrik_per_kg) || 0;
      payload.total_harga_pabrik = (parseFloat(updateForm.harga_pabrik_per_kg) || 0) * (showUpdateModal.tonase_kirim || 0);
      payload.tanggal_bayar = updateForm.tanggal_bayar || getTodayISO();
    }
    await supabase.from('pengiriman').update(payload).eq('id', showUpdateModal.id);
    setSaving(false);
    setShowUpdateModal(null);
    loadAll();
  }

  const statusBadge = (s) => {
    const map = { dikirim: 'badge-info', diterima: 'badge-warning', dibayar: 'badge-success' };
    const labels = { dikirim: '🚚 Dikirim', diterima: '✅ Diterima', dibayar: '💰 Dibayar' };
    return <span className={`badge ${map[s] || 'badge-neutral'}`}>{labels[s] || s}</span>;
  };

  const filtered = filter === 'semua' ? list : list.filter(p => p.status === filter);

  return (
    <AppShell title="Pengiriman" subtitle="Kelola pengiriman TBS ke pabrik">
      <div className="page-header">
        <h2 className="page-title">🚚 Pengiriman ke Pabrik</h2>
        <button className="btn btn-primary" onClick={() => setShowModal(true)}>+ Pengiriman Baru</button>
      </div>

      {/* Filter */}
      <div className="tabs">
        {['semua', 'dikirim', 'diterima', 'dibayar'].map(f => (
          <button key={f} className={`tab ${filter === f ? 'active' : ''}`} onClick={() => setFilter(f)}>
            {f === 'semua' ? 'Semua' : f.charAt(0).toUpperCase() + f.slice(1)} ({f === 'semua' ? list.length : list.filter(p => p.status === f).length})
          </button>
        ))}
      </div>

      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {[1, 2, 3].map(i => <div key={i} className="skeleton" style={{ height: 52 }}></div>)}
        </div>
      ) : filtered.length === 0 ? (
        <div className="empty-state">
          <div className="empty-state-icon">🚚</div>
          <div className="empty-state-title">Belum ada pengiriman</div>
        </div>
      ) : (
        <div className="table-container">
          <table className="table">
            <thead>
              <tr>
                <th>Tanggal</th><th>Sopir</th><th>Kendaraan</th><th>Pabrik</th>
                <th style={{ textAlign: 'right' }}>Tonase</th><th>No DO</th><th>Status</th><th></th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(p => (
                <tr key={p.id}>
                  <td>{new Date(p.tanggal).toLocaleDateString('id-ID')}</td>
                  <td>{p.sopir?.nama || '-'}</td>
                  <td className="table-mono">{p.kendaraan?.plat_nomor || '-'}</td>
                  <td>{p.pabrik?.nama || '-'}</td>
                  <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(p.tonase_kirim)} kg</td>
                  <td className="table-mono">{p.no_do || '-'}</td>
                  <td>{statusBadge(p.status)}</td>
                  <td>
                    {p.status !== 'dibayar' && (
                      <button className="btn btn-ghost btn-sm" onClick={() => {
                        setShowUpdateModal(p);
                        setUpdateForm({
                          status: p.status === 'dikirim' ? 'diterima' : 'dibayar',
                          harga_pabrik_per_kg: '', tanggal_bayar: getTodayISO(),
                        });
                      }}>📝</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Modal Tambah */}
      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Pengiriman Baru</h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                <div className="form-group">
                  <label className="form-label">Tanggal</label>
                  <input type="date" className="form-input" value={form.tanggal}
                    onChange={e => setForm({ ...form, tanggal: e.target.value })} required />
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label">Sopir</label>
                    <select className="form-input form-select" value={form.sopir_id}
                      onChange={e => setForm({ ...form, sopir_id: e.target.value })}>
                      <option value="">-- Pilih --</option>
                      {sopirList.map(s => <option key={s.id} value={s.id}>{s.nama}</option>)}
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Kendaraan</label>
                    <select className="form-input form-select" value={form.kendaraan_id}
                      onChange={e => setForm({ ...form, kendaraan_id: e.target.value })}>
                      <option value="">-- Pilih --</option>
                      {kendaraanList.map(k => <option key={k.id} value={k.id}>{k.plat_nomor}</option>)}
                    </select>
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Pabrik Tujuan</label>
                  <select className="form-input form-select" value={form.pabrik_id}
                    onChange={e => setForm({ ...form, pabrik_id: e.target.value })} required>
                    <option value="">-- Pilih --</option>
                    {pabrikList.map(p => <option key={p.id} value={p.id}>{p.nama}</option>)}
                  </select>
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Tonase (kg)</label>
                    <input type="number" className="form-input form-input-mono" value={form.tonase_kirim}
                      onChange={e => setForm({ ...form, tonase_kirim: e.target.value })} min={0} required />
                  </div>
                  <div className="form-group">
                    <label className="form-label">No. DO / Surat</label>
                    <input className="form-input" value={form.no_do}
                      onChange={e => setForm({ ...form, no_do: e.target.value })} />
                  </div>
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" onClick={() => setShowModal(false)}>Batal</button>
                <button type="submit" className="btn btn-primary" disabled={saving}>{saving ? 'Menyimpan...' : 'Simpan'}</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal Update Status */}
      {showUpdateModal && (
        <div className="modal-overlay" onClick={() => setShowUpdateModal(null)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Update Status Pengiriman</h3>
              <button className="modal-close" onClick={() => setShowUpdateModal(null)}>✕</button>
            </div>
            <form onSubmit={handleUpdate}>
              <div className="modal-body">
                <div className="alert alert-info" style={{ marginBottom: 16 }}>
                  <span>Tonase: <strong>{formatNumber(showUpdateModal.tonase_kirim)} kg</strong> ke {showUpdateModal.pabrik?.nama}</span>
                </div>
                <div className="form-group">
                  <label className="form-label">Status Baru</label>
                  <select className="form-input form-select" value={updateForm.status}
                    onChange={e => setUpdateForm({ ...updateForm, status: e.target.value })}>
                    <option value="diterima">✅ Diterima Pabrik</option>
                    <option value="dibayar">💰 Sudah Dibayar</option>
                  </select>
                </div>
                {updateForm.status === 'dibayar' && (
                  <>
                    <div className="form-group">
                      <label className="form-label form-label-required">Harga Pabrik /kg (Rp)</label>
                      <input type="number" className="form-input form-input-mono" value={updateForm.harga_pabrik_per_kg}
                        onChange={e => setUpdateForm({ ...updateForm, harga_pabrik_per_kg: e.target.value })} required min={0} />
                      {updateForm.harga_pabrik_per_kg > 0 && (
                        <div className="form-hint text-mono">Total: {formatRupiah(parseFloat(updateForm.harga_pabrik_per_kg) * showUpdateModal.tonase_kirim)}</div>
                      )}
                    </div>
                    <div className="form-group">
                      <label className="form-label">Tanggal Bayar</label>
                      <input type="date" className="form-input" value={updateForm.tanggal_bayar}
                        onChange={e => setUpdateForm({ ...updateForm, tanggal_bayar: e.target.value })} />
                    </div>
                  </>
                )}
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" onClick={() => setShowUpdateModal(null)}>Batal</button>
                <button type="submit" className="btn btn-primary" disabled={saving}>{saving ? 'Menyimpan...' : 'Update'}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AppShell>
  );
}
