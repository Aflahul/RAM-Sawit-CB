'use client';

import { useCallback, useEffect, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import ConfirmDialog from '@/components/ui/ConfirmDialog';
import { supabase } from '@/lib/supabase';
import { formatDateDisplay, formatRupiah, getTodayISO } from '@/lib/utils';
import { exportToExcel } from '@/lib/export';

const KATEGORI = [
  { value: 'solar', label: '⛽ Solar / BBM' },
  { value: 'gaji_sopir', label: '👤 Gaji Sopir' },
  { value: 'kuli', label: '💪 Kuli Bongkar' },
  { value: 'retribusi', label: '📋 Retribusi' },
  { value: 'perawatan', label: '🔧 Perawatan Kendaraan' },
  { value: 'lainnya', label: '📦 Lainnya' },
];

export default function BiayaPage() {
  const [list, setList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [saving, setSaving] = useState(false);
  const [filterKategori, setFilterKategori] = useState('semua');
  const [filterTanggal, setFilterTanggal] = useState(getTodayISO());
  const [toast, setToast] = useState(null);

  const [form, setForm] = useState({
    tanggal: getTodayISO(), kategori: 'solar', jumlah: '', keterangan: '',
  });

  const loadData = useCallback(async () => {
    setLoading(true);
    let query = supabase
      .from('biaya_operasional')
      .select('*')
      .neq('status', 'dibatalkan')
      .order('created_at', { ascending: false });

    if (filterTanggal) {
      query = query.eq('tanggal', filterTanggal);
    }

    const { data } = await query.limit(100);
    setList(data || []);
    setLoading(false);
  }, [filterTanggal]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  async function handleSave(e) {
    e.preventDefault();
    setSaving(true);
    const { data: { session } } = await supabase.auth.getSession();

    await supabase.from('biaya_operasional').insert({
      tanggal: form.tanggal,
      kategori: form.kategori,
      jumlah: parseFloat(form.jumlah),
      keterangan: form.keterangan || null,
      status: 'aktif',
      created_by: session?.user?.id || null,
    });

    setSaving(false);
    setShowModal(false);
    setForm({ tanggal: getTodayISO(), kategori: 'solar', jumlah: '', keterangan: '' });
    setToast({ message: 'Biaya berhasil dicatat!', type: 'success' });
    setTimeout(() => setToast(null), 3000);
    loadData();
  }

  async function handleCancel(id) {
    const alasan = prompt('Alasan pembatalan biaya:');
    if (!alasan || !alasan.trim()) return;

    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase
      .from('biaya_operasional')
      .update({
        status: 'dibatalkan',
        alasan_batal: alasan.trim(),
        dibatalkan_at: new Date().toISOString(),
        dibatalkan_by: user?.id || null,
      })
      .eq('id', id);

    if (error) {
      setToast({ message: 'Gagal membatalkan biaya: ' + error.message, type: 'error' });
      setTimeout(() => setToast(null), 4000);
      return;
    }

    setToast({ message: 'Biaya berhasil dibatalkan.', type: 'success' });
    setTimeout(() => setToast(null), 3000);
    loadData();
  }

  const filtered = filterKategori === 'semua' ? list : list.filter(b => b.kategori === filterKategori);
  const totalFiltered = filtered.reduce((s, b) => s + (b.jumlah || 0), 0);

  const kategoriLabel = (k) => KATEGORI.find(c => c.value === k)?.label || k;

  return (
    <AppShell title="Biaya Operasional" subtitle="Catat pengeluaran harian">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>✅</span><span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header" style={{ justifyContent: 'flex-end' }}>
        <div className="flex gap-sm">
          <button className="btn btn-outline btn-sm" onClick={() => {
            exportToExcel(filtered, [
              { key: 'tanggal', label: 'Tanggal', format: formatDateDisplay },
              { key: 'kategori', label: 'Kategori', format: v => kategoriLabel(v) },
              { key: 'jumlah', label: 'Jumlah (Rp)' },
              { key: 'keterangan', label: 'Keterangan' },
            ], `Biaya_Operasional_${filterTanggal}`, 'Biaya');
          }}>📥 Export Excel</button>
          <button className="btn btn-primary" onClick={() => setShowModal(true)}>+ Tambah Biaya</button>
        </div>
      </div>

      {/* Toolbar */}
      <div className="toolbar">
        <div className="form-group" style={{ marginBottom: 0 }}>
          <input type="date" className="form-input" value={filterTanggal}
            onChange={e => setFilterTanggal(e.target.value)} />
        </div>
        <select className="form-input form-select" value={filterKategori}
          onChange={e => setFilterKategori(e.target.value)} style={{ maxWidth: 220 }}>
          <option value="semua">Semua Kategori</option>
          {KATEGORI.map(k => <option key={k.value} value={k.value}>{k.label}</option>)}
        </select>
        <div className="toolbar-spacer"></div>
        <div className="text-mono" style={{ fontWeight: 700, fontSize: 'var(--text-lg)', color: 'var(--color-danger)' }}>
          Total: {formatRupiah(totalFiltered)}
        </div>
      </div>

      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {[1, 2, 3].map(i => <div key={i} className="skeleton" style={{ height: 48 }}></div>)}
        </div>
      ) : filtered.length === 0 ? (
        <div className="empty-state">
          <div className="empty-state-icon">🔧</div>
          <div className="empty-state-title">Belum ada biaya dicatat</div>
          <div className="empty-state-text">Klik tombol Tambah Biaya untuk mencatat pengeluaran</div>
        </div>
      ) : (
        <div className="table-container">
          <table className="table">
            <thead>
              <tr><th>Kategori</th><th>Keterangan</th><th style={{ textAlign: 'right' }}>Jumlah</th><th></th></tr>
            </thead>
            <tbody>
              {filtered.map(b => (
                <tr key={b.id}>
                  <td><span className="badge badge-neutral">{kategoriLabel(b.kategori)}</span></td>
                  <td>{b.keterangan || '-'}</td>
                  <td className="table-mono text-danger" style={{ textAlign: 'right', fontWeight: 600 }}>{formatRupiah(b.jumlah)}</td>
                  <td><button className="btn btn-ghost btn-sm" onClick={() => handleCancel(b.id)}>Batalkan</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Tambah Biaya</h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                <div className="form-group">
                  <label className="form-label">Tanggal</label>
                  <input type="date" className="form-input" value={form.tanggal}
                    onChange={e => setForm({ ...form, tanggal: e.target.value })} required />
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Kategori</label>
                  <select className="form-input form-select" value={form.kategori}
                    onChange={e => setForm({ ...form, kategori: e.target.value })}>
                    {KATEGORI.map(k => <option key={k.value} value={k.value}>{k.label}</option>)}
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Jumlah (Rp)</label>
                  <input type="number" className="form-input form-input-mono" value={form.jumlah}
                    onChange={e => setForm({ ...form, jumlah: e.target.value })} min={1} required />
                </div>
                <div className="form-group">
                  <label className="form-label">Keterangan</label>
                  <input className="form-input" value={form.keterangan}
                    onChange={e => setForm({ ...form, keterangan: e.target.value })} placeholder="Opsional" />
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
    </AppShell>
  );
}
