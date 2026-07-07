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

    const today = getTodayISO();
    const todayEntry = data?.find(h => h.tanggal === today);
    setTodayHarga(todayEntry);
    if (todayEntry) setHargaBaru(todayEntry.harga_per_kg.toString());
    setLoading(false);
  }

  async function setHarga(e) {
    e.preventDefault();
    if (!hargaBaru || parseFloat(hargaBaru) <= 0) return;
    setSaving(true);
    const today = getTodayISO();

    if (todayHarga) {
      await supabase.from('harga_tbs').update({ harga_per_kg: parseFloat(hargaBaru) }).eq('id', todayHarga.id);
    } else {
      await supabase.from('harga_tbs').insert({ tanggal: today, harga_per_kg: parseFloat(hargaBaru) });
    }
    setSaving(false);
    loadHarga();
  }

  return (
    <AppShell title="Harga TBS" subtitle="Set harga TBS harian">
      <div className="page-header">
        <h2 className="page-title">💲 Harga TBS Hari Ini</h2>
      </div>

      {/* Set Harga Form */}
      <div className="card" style={{ marginBottom: 'var(--space-xl)' }}>
        <form onSubmit={setHarga} className="flex items-center gap-md" style={{ flexWrap: 'wrap' }}>
          <div style={{ flex: 1, minWidth: 200 }}>
            <label className="form-label">Harga TBS per kg (Rp)</label>
            <input
              type="number"
              className="form-input form-input-mono"
              value={hargaBaru}
              onChange={(e) => setHargaBaru(e.target.value)}
              placeholder="contoh: 2500"
              min={0}
              step={10}
              required
            />
          </div>
          <button type="submit" className="btn btn-primary btn-lg" disabled={saving} style={{ marginTop: 24 }}>
            {saving ? 'Menyimpan...' : todayHarga ? '✏️ Update Harga' : '💲 Set Harga Hari Ini'}
          </button>
        </form>
        {todayHarga && (
          <div className="alert alert-success" style={{ marginTop: 16 }}>
            <span className="alert-icon">✅</span>
            <span>Harga hari ini sudah diset: <strong className="text-mono">{formatRupiah(todayHarga.harga_per_kg)}/kg</strong></span>
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
            {[1, 2, 3].map(i => <div key={i} className="skeleton" style={{ height: 40 }}></div>)}
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
                <tr><th>Tanggal</th><th style={{ textAlign: 'right' }}>Harga /kg</th></tr>
              </thead>
              <tbody>
                {hargaList.map(h => (
                  <tr key={h.id}>
                    <td>{new Date(h.tanggal).toLocaleDateString('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</td>
                    <td className="table-mono" style={{ textAlign: 'right', fontWeight: 600 }}>{formatRupiah(h.harga_per_kg)}</td>
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
