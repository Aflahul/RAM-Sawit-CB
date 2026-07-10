'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, getTodayISO } from '@/lib/utils';

export default function HargaTBSPage() {
  const [hargaList, setHargaList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [hargaBaru, setHargaBaru] = useState('');
  const [saving, setSaving] = useState(false);
  const [todayHarga, setTodayHarga] = useState(null);

  useEffect(() => { loadHarga(); }, []);

  async function loadHarga() {
    setLoading(true);
    const { data } = await supabase
      .from('harga_tbs')
      .select('*')
      .order('tanggal', { ascending: false })
      .limit(30);
    setHargaList(data || []);

    const today = getTodayISO(); // WITA (UTC+8)
    const todayEntry = data?.find(h => h.tanggal === today);
    setTodayHarga(todayEntry || null);
    if (todayEntry) setHargaBaru(todayEntry.harga_per_kg.toString());
    setLoading(false);
  }

  async function setHarga(e) {
    e.preventDefault();
    const nilai = parseFloat(hargaBaru);
    if (!nilai || nilai <= 0) return;
    setSaving(true);
    const today = getTodayISO(); // WITA
    try {
      if (todayHarga) {
        await supabase.from('harga_tbs').update({ harga_per_kg: nilai }).eq('id', todayHarga.id);
      } else {
        await supabase.from('harga_tbs').insert({ tanggal: today, harga_per_kg: nilai });
      }
      await loadHarga();
    } finally {
      setSaving(false);
    }
  }

  const todayLabel = new Date().toLocaleDateString('id-ID', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
    timeZone: 'Asia/Makassar',
  });

  return (
    <AppShell title="Harga TBS" subtitle="Set harga TBS harian">
      <div className="page-header">
        <div>
          <h2 className="page-title">💲 Harga TBS Hari Ini</h2>
          <p className="page-description">{todayLabel} (WITA)</p>
        </div>
      </div>

      {/* Banner jika harga belum diset */}
      {!loading && !todayHarga && (
        <div className="alert alert-warning" style={{ marginBottom: 'var(--space-lg)' }}>
          <span className="alert-icon">⚠️</span>
          <span>
            <strong>Harga TBS hari ini belum diset!</strong> Mohon set harga terlebih dahulu
            sebelum mencatat transaksi pembelian TBS.
          </span>
        </div>
      )}

      {/* Set / Edit Harga Form */}
      <div className="card" style={{ marginBottom: 'var(--space-xl)' }}>
        <div className="card-header" style={{ marginBottom: 'var(--space-md)' }}>
          <span className="card-title">
            {todayHarga ? '✏️ Update Harga Hari Ini' : '💲 Set Harga Hari Ini'}
          </span>
          {todayHarga && (
            <div style={{
              fontFamily: 'var(--font-mono)', fontSize: 'var(--text-xl)',
              fontWeight: 700, color: 'var(--color-primary-400)',
            }}>
              {formatRupiah(todayHarga.harga_per_kg)}/kg
            </div>
          )}
        </div>

        <form onSubmit={setHarga} className="flex items-center gap-md" style={{ flexWrap: 'wrap' }}>
          <div style={{ flex: 1, minWidth: 200 }}>
            <label className="form-label">Harga TBS per kg (Rp)</label>
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
          <button
            type="submit"
            className="btn btn-primary btn-lg"
            disabled={saving}
            style={{ marginTop: 24 }}
          >
            {saving ? (
              <><span className="spinner" style={{ width: 16, height: 16, borderWidth: 2 }} /> Menyimpan...</>
            ) : todayHarga ? '✏️ Update Harga' : '💲 Set Harga Hari Ini'}
          </button>
        </form>

        {todayHarga && (
          <div className="alert alert-success" style={{ marginTop: 16 }}>
            <span className="alert-icon">✅</span>
            <span>
              Harga hari ini sudah diset:{' '}
              <strong className="text-mono">{formatRupiah(todayHarga.harga_per_kg)}/kg</strong>
            </span>
          </div>
        )}
      </div>

      {/* Riwayat Harga */}
      <div className="card">
        <div className="card-header">
          <span className="card-title">Riwayat Harga (30 hari terakhir)</span>
        </div>
        {loading ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {[1, 2, 3].map(i => <div key={i} className="skeleton" style={{ height: 40 }} />)}
          </div>
        ) : hargaList.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-icon">💲</div>
            <div className="empty-state-title">Belum ada riwayat harga</div>
          </div>
        ) : (
          <div className="table-container" style={{ border: 'none' }}>
            <table className="table">
              <thead>
                <tr>
                  <th>Tanggal</th>
                  <th style={{ textAlign: 'right' }}>Harga /kg</th>
                  <th style={{ textAlign: 'right' }}>Perubahan</th>
                </tr>
              </thead>
              <tbody>
                {hargaList.map((h, idx) => {
                  const prev = hargaList[idx + 1];
                  const delta = prev ? h.harga_per_kg - prev.harga_per_kg : null;
                  // Parse tanggal tanpa shift timezone
                  const [y, m, d] = h.tanggal.split('-').map(Number);
                  const tglLabel = new Date(y, m - 1, d).toLocaleDateString('id-ID', {
                    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
                  });
                  return (
                    <tr key={h.id}>
                      <td>
                        {tglLabel}
                        {h.tanggal === getTodayISO() && (
                          <span className="badge badge-success" style={{ marginLeft: 8 }}>Hari ini</span>
                        )}
                      </td>
                      <td className="table-mono" style={{ textAlign: 'right', fontWeight: 600 }}>
                        {formatRupiah(h.harga_per_kg)}
                      </td>
                      <td style={{ textAlign: 'right' }}>
                        {delta !== null ? (
                          <span style={{
                            color: delta > 0
                              ? 'var(--color-success)'
                              : delta < 0
                                ? 'var(--color-danger)'
                                : 'var(--text-tertiary)',
                            fontFamily: 'var(--font-mono)',
                            fontSize: 'var(--text-sm)',
                          }}>
                            {delta > 0 ? '▲' : delta < 0 ? '▼' : '—'}{' '}
                            {delta !== 0 ? formatRupiah(Math.abs(delta)) : 'Sama'}
                          </span>
                        ) : (
                          <span style={{ color: 'var(--text-tertiary)' }}>—</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </AppShell>
  );
}
