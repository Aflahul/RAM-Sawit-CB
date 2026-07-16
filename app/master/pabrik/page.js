'use client';

import { useCallback, useEffect, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import ConfirmDialog from '@/components/ui/ConfirmDialog';
import { canApproveCorrections, normalizeRole } from '@/lib/roles';
import { supabase } from '@/lib/supabase';
import { CheckCircle2, Factory, Pencil, Trash2, X } from 'lucide-react';

export default function PabrikPage() {
  const [list, setList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [userRole, setUserRole] = useState('admin_operasional');
  const [form, setForm] = useState({ nama: '', alamat: '', no_hp: '' });

  const showToast = useCallback((message, type = 'error', timeout = 4000) => {
    setToast({ message, type });
    setTimeout(() => setToast(null), timeout);
  }, []);

  const loadData = useCallback(async () => {
    setLoading(true);
    const [{ data, error }, { data: sessionData }] = await Promise.all([
      supabase
        .from('pabrik')
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

    if (error) {
      showToast(`Gagal memuat pabrik: ${error.message}`, 'error', 5000);
    }

    setList(data || []);
    setLoading(false);
  }, [showToast]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  function openNew() {
    setEditingId(null);
    setForm({ nama: '', alamat: '', no_hp: '' });
    setShowModal(true);
  }

  function openEdit(pabrik) {
    setEditingId(pabrik.id);
    setForm({ nama: pabrik.nama, alamat: pabrik.alamat || '', no_hp: pabrik.no_hp || '' });
    setShowModal(true);
  }

  async function handleSave(event) {
    event.preventDefault();
    setSaving(true);

    const result = await supabase.rpc('save_pabrik_master', {
      p_id: editingId || null,
      p_nama: form.nama,
      p_alamat: form.alamat || null,
      p_no_hp: form.no_hp || null,
    });

    setSaving(false);

    if (result.error) {
      showToast(`Gagal menyimpan pabrik: ${result.error.message}`, 'error', 5000);
      return;
    }

    setShowModal(false);
    showToast(
      canApproveCorrections(userRole)
        ? 'Pabrik berhasil disimpan.'
        : 'Pabrik tersimpan dan masuk daftar Perlu Verifikasi.',
      'success',
      4000,
    );
    await loadData();
  }

  async function handleDelete() {
    if (!deleteTarget) return;

    const { error } = await supabase.rpc('set_pabrik_master_active', {
      p_id: deleteTarget.id,
      p_active: false,
    });

    if (error) {
      showToast(`Gagal menonaktifkan pabrik: ${error.message}`, 'error', 5000);
      return;
    }

    setDeleteTarget(null);
    showToast('Pabrik berhasil dinonaktifkan.', 'success', 3000);
    await loadData();
  }

  async function handleVerify(pabrik) {
    const { error } = await supabase.rpc('verify_pabrik_master', {
      p_id: pabrik.id,
      p_catatan: 'Diperiksa dari Master Pabrik',
    });

    if (error) {
      showToast(`Gagal memverifikasi pabrik: ${error.message}`, 'error', 5000);
      return;
    }

    showToast('Pabrik sudah diverifikasi.', 'success', 3000);
    await loadData();
  }

  return (
    <AppShell title="Pabrik Tujuan" subtitle="Kelola data pabrik pengolahan">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header" style={{ justifyContent: 'flex-end' }}>
        <button className="btn btn-primary" onClick={openNew}>+ Tambah Pabrik</button>
      </div>

      {!canApproveCorrections(userRole) && (
        <div className="alert alert-info" style={{ marginBottom: 'var(--space-lg)' }}>
          Pabrik yang ditambah atau diubah Admin tetap dapat dipakai, tetapi akan ditandai Perlu Verifikasi sampai diperiksa Owner.
        </div>
      )}

      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {[1, 2, 3].map((item) => <div key={item} className="skeleton" style={{ height: 52 }} />)}
        </div>
      ) : list.length === 0 ? (
        <div className="empty-state">
          <div className="empty-state-icon"><Factory size={28} /></div>
          <div className="empty-state-title">Belum ada pabrik</div>
          <div className="empty-state-text">Tambahkan pabrik tujuan pengiriman TBS</div>
        </div>
      ) : (
        <div className="table-container">
          <table className="table">
            <thead>
              <tr>
                <th>Nama Pabrik</th>
                <th>Alamat</th>
                <th>No. HP</th>
                <th style={{ textAlign: 'center' }}>Aksi</th>
              </tr>
            </thead>
            <tbody>
              {list.map((pabrik) => (
                <tr key={pabrik.id}>
                  <td style={{ fontWeight: 600 }}>
                    <div>{pabrik.nama}</div>
                    {pabrik.status_verifikasi === 'perlu_verifikasi' && (
                      <span className="badge badge-warning" style={{ marginTop: 5 }}>Perlu Verifikasi</span>
                    )}
                  </td>
                  <td>{pabrik.alamat || '-'}</td>
                  <td className="table-mono">{pabrik.no_hp || '-'}</td>
                  <td style={{ textAlign: 'center' }}>
                    {canApproveCorrections(userRole) && pabrik.status_verifikasi === 'perlu_verifikasi' && (
                      <button className="btn btn-ghost btn-sm" onClick={() => handleVerify(pabrik)} aria-label={`Verifikasi ${pabrik.nama}`} title="Tandai sudah diperiksa">
                        <CheckCircle2 size={16} />
                      </button>
                    )}
                    <button className="btn btn-ghost btn-sm" onClick={() => openEdit(pabrik)} aria-label={`Edit ${pabrik.nama}`}>
                      <Pencil size={16} />
                    </button>
                    {canApproveCorrections(userRole) && (
                      <button className="btn btn-ghost btn-sm" onClick={() => setDeleteTarget(pabrik)} aria-label={`Nonaktifkan ${pabrik.nama}`}>
                        <Trash2 size={16} />
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(event) => event.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">{editingId ? 'Edit' : 'Tambah'} Pabrik</h3>
              <button className="modal-close" onClick={() => setShowModal(false)} aria-label="Tutup">
                <X size={18} />
              </button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                <div className="form-group">
                  <label className="form-label form-label-required">Nama Pabrik</label>
                  <input
                    className="form-input"
                    value={form.nama}
                    onChange={(event) => setForm({ ...form, nama: event.target.value })}
                    required
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Alamat</label>
                  <input
                    className="form-input"
                    value={form.alamat}
                    onChange={(event) => setForm({ ...form, alamat: event.target.value })}
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">No. HP / Kontak</label>
                  <input
                    className="form-input"
                    value={form.no_hp}
                    onChange={(event) => setForm({ ...form, no_hp: event.target.value })}
                  />
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
        title="Nonaktifkan Pabrik"
        message={deleteTarget ? `${deleteTarget.nama} tidak akan tampil lagi sebagai pabrik aktif.` : ''}
        confirmText="Nonaktifkan"
        cancelText="Batal"
        variant="danger"
        onConfirm={handleDelete}
        onCancel={() => setDeleteTarget(null)}
      />
    </AppShell>
  );
}
