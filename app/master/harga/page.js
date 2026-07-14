'use client';

import { useCallback, useEffect, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatDateTimeDisplay, formatRupiah } from '@/lib/utils';

function formatDateTime(value) {
  return formatDateTimeDisplay(value, { seconds: false });
}

export default function HargaTBSPage() {
  const [hargaList, setHargaList] = useState([]);
  const [hargaAktif, setHargaAktif] = useState(null);
  const [hargaBaru, setHargaBaru] = useState('');
  const [alasan, setAlasan] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState(null);

  const loadHarga = useCallback(async () => {
    setLoading(true);

    const { data, error } = await supabase
      .from('harga_tbs_lokal')
      .select('*')
      .order('berlaku_mulai', { ascending: false })
      .limit(30);

    if (error) {
      setToast({ type: 'error', message: error.message });
      setHargaList([]);
      setHargaAktif(null);
      setLoading(false);
      return;
    }

    const list = data || [];
    setHargaList(list);
    setHargaAktif(list.find((item) => item.aktif) || null);
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadHarga();
  }, [loadHarga]);

  async function setHarga(e) {
    e.preventDefault();
    const nilai = Number(hargaBaru);
    if (!nilai || nilai <= 0) return;

    setSaving(true);
    const { error } = await supabase.rpc('set_harga_tbs_lokal', {
      p_harga_per_kg: nilai,
      p_alasan_override: alasan || null,
    });

    if (error) {
      setToast({ type: 'error', message: `Gagal menyimpan harga: ${error.message}` });
      setSaving(false);
      return;
    }

    setToast({ type: 'success', message: 'Harga TBS lokal berhasil diperbarui.' });
    setHargaBaru('');
    setAlasan('');
    await loadHarga();
    setSaving(false);
  }

  return (
    <AppShell title="Harga TBS" subtitle="Harga beli TBS petani lokal">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <div>
          <p className="page-description">
            Harga memakai waktu berlaku, jadi perubahan hari yang sama tetap tercatat sebagai riwayat.
          </p>
        </div>
      </div>

      {!loading && !hargaAktif && (
        <div className="alert alert-warning" style={{ marginBottom: 'var(--space-lg)' }}>
          <span>
            Harga TBS lokal aktif belum diset. Input pembelian petani akan terkunci sampai harga aktif tersedia.
          </span>
        </div>
      )}

      <div className="card" style={{ marginBottom: 'var(--space-xl)' }}>
        <div className="card-header" style={{ marginBottom: 'var(--space-md)' }}>
          <span className="card-title">Set Harga Baru</span>
          {hargaAktif && (
            <div className="text-mono" style={{ fontSize: 'var(--text-xl)', fontWeight: 700, color: 'var(--color-primary-400)' }}>
              {formatRupiah(hargaAktif.harga_per_kg)}/kg
            </div>
          )}
        </div>

        {hargaAktif && (
          <div className="alert alert-success" style={{ marginBottom: 16 }}>
            <span>
              Harga aktif sekarang: <strong className="text-mono">{formatRupiah(hargaAktif.harga_per_kg)}/kg</strong>
              {' '}berlaku sejak {formatDateTime(hargaAktif.berlaku_mulai)}.
            </span>
          </div>
        )}

        <form onSubmit={setHarga}>
          <div className="form-grid">
            <div className="form-group">
              <label className="form-label form-label-required">Harga TBS per kg (Rp)</label>
              <input
                type="number"
                className="form-input form-input-mono"
                value={hargaBaru}
                onChange={(e) => setHargaBaru(e.target.value)}
                placeholder="contoh: 2500"
                min={1}
                step={10}
                required
              />
            </div>
            <div className="form-group">
              <label className="form-label">Alasan perubahan</label>
              <input
                className="form-input"
                value={alasan}
                onChange={(e) => setAlasan(e.target.value)}
                placeholder="Opsional"
              />
            </div>
          </div>
          <div className="form-actions">
            <button type="submit" className="btn btn-primary btn-lg" disabled={saving}>
              {saving ? 'Menyimpan...' : 'Simpan Harga Baru'}
            </button>
          </div>
        </form>
      </div>

      <div className="card">
        <div className="card-header">
          <span className="card-title">Riwayat Harga</span>
        </div>

        {loading ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {[1, 2, 3].map((item) => (
              <div key={item} className="skeleton" style={{ height: 40 }} />
            ))}
          </div>
        ) : hargaList.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-title">Belum ada riwayat harga</div>
          </div>
        ) : (
          <div className="table-container" style={{ border: 'none' }}>
            <table className="table">
              <thead>
                <tr>
                  <th>Berlaku mulai</th>
                  <th>Berlaku sampai</th>
                  <th style={{ textAlign: 'right' }}>Harga /kg</th>
                  <th>Status</th>
                  <th>Alasan</th>
                </tr>
              </thead>
              <tbody>
                {hargaList.map((harga) => (
                  <tr key={harga.id}>
                    <td>{formatDateTime(harga.berlaku_mulai)}</td>
                    <td>{formatDateTime(harga.berlaku_sampai)}</td>
                    <td className="table-mono" style={{ textAlign: 'right', fontWeight: 600 }}>
                      {formatRupiah(harga.harga_per_kg)}
                    </td>
                    <td>
                      <span className={`badge ${harga.aktif ? 'badge-success' : 'badge-neutral'}`}>
                        {harga.aktif ? 'Aktif' : 'Riwayat'}
                      </span>
                    </td>
                    <td>{harga.alasan_override || '-'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </AppShell>
  );
}
