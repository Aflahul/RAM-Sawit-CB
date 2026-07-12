'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, getTodayDate } from '@/lib/utils';

export default function InputTimbanganPage() {
  const [sopirs, setSopirs] = useState([]);
  const [latestHarga, setLatestHarga] = useState(0);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');

  const [form, setForm] = useState({
    tanggal: '',
    sopir_id: '',
    plat_nomor: '',
    mitra_id: '',
    mitra_nama: '',
    mitra_fee: 0,
    tonase: '',
  });

  useEffect(() => {
    // We don't have getTodayDate defined possibly, let's just use JS Date
    const today = new Date().toISOString().split('T')[0];
    setForm(f => ({ ...f, tanggal: today }));
    loadData();
  }, []);

  async function loadData() {
    setLoading(true);
    
    // Load Sopir + Relasi Mitra
    const { data: sopirData } = await supabase
      .from('sopir')
      .select(`
        id, nama, plat_nomor, mitra_id,
        master_mitra ( id, nama, fee_per_kg )
      `)
      .eq('aktif', true)
      .order('nama');
      
    setSopirs(sopirData || []);

    // Load Harga Terbaru
    const { data: hargaData } = await supabase
      .from('harga_tbs')
      .select('harga_per_kg')
      .order('tanggal', { ascending: false })
      .limit(1);
      
    if (hargaData && hargaData.length > 0) {
      setLatestHarga(hargaData[0].harga_per_kg);
    }
    
    setLoading(false);
  }

  function handleSopirChange(e) {
    const selectedId = e.target.value;
    if (!selectedId) {
      setForm({ ...form, sopir_id: '', plat_nomor: '', mitra_id: '', mitra_nama: '' });
      return;
    }

    const sopir = sopirs.find(s => s.id === selectedId);
    if (sopir) {
      setForm({
        ...form,
        sopir_id: sopir.id,
        plat_nomor: sopir.plat_nomor || '-',
        mitra_id: sopir.mitra_id || '',
        mitra_nama: sopir.master_mitra?.nama || 'Tanpa Afiliasi',
        mitra_fee: Number(sopir.master_mitra?.fee_per_kg || 0),
      });
    }
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setSaving(true);
    setSuccessMsg('');

    const tonase = parseFloat(form.tonase);
    if (isNaN(tonase) || tonase <= 0) {
      alert("Tonase tidak valid");
      setSaving(false);
      return;
    }

    if (!form.mitra_id) {
      alert("Sopir ini tidak terafiliasi dengan Mitra manapun di Master Data.");
      setSaving(false);
      return;
    }

    const hargaBeliMitra = latestHarga - form.mitra_fee;
    const totalKotor = tonase * hargaBeliMitra;

    const { error } = await supabase.from('transaksi_mitra').insert({
      tanggal: form.tanggal,
      sopir_id: form.sopir_id,
      mitra_id: form.mitra_id,
      plat_nomor: form.plat_nomor,
      tonase: tonase,
      harga_harian: hargaBeliMitra,
      total_kotor: totalKotor
    });

    if (error) {
      alert("Gagal menyimpan data: " + error.message);
    } else {
      setSuccessMsg(`Berhasil menyimpan ${tonase} Kg untuk armada ${form.plat_nomor} (Mitra: ${form.mitra_nama}).`);
      // Reset form but keep date
      setForm({ ...form, sopir_id: '', plat_nomor: '', mitra_id: '', mitra_nama: '', mitra_fee: 0, tonase: '' });
    }

    setSaving(false);
  }

  return (
    <AppShell title="Pengiriman Mitra" subtitle="Catat armada mitra masuk">
      <div className="page-header">
        <div>
          <h2 className="page-title">Pengiriman Mitra (MVP)</h2>
          <p className="page-description">Harga Dasar Hari Ini: <strong>{formatRupiah(latestHarga)} / Kg</strong></p>
        </div>
      </div>

      <div className="card" style={{ maxWidth: 480, margin: '0 auto', padding: 'var(--space-xl)' }}>
        {successMsg && (
          <div style={{ background: 'var(--color-success-bg)', color: 'var(--color-success)', padding: 'var(--space-md)', borderRadius: 'var(--radius-md)', marginBottom: 'var(--space-lg)', fontWeight: 500 }}>
            ✅ {successMsg}
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label className="form-label form-label-required">Tanggal</label>
            <input 
              type="date" 
              className="form-input" 
              required 
              value={form.tanggal} 
              onChange={e => setForm({...form, tanggal: e.target.value})} 
            />
          </div>

          <div className="form-group">
            <label className="form-label form-label-required">Pilih Nama Sopir</label>
            <select className="form-input" required value={form.sopir_id} onChange={handleSopirChange} disabled={loading}>
              <option value="">-- Ketuk untuk memilih Sopir --</option>
              {sopirs.map(s => (
                <option key={s.id} value={s.id}>{s.nama}</option>
              ))}
            </select>
          </div>

          {form.sopir_id && (
            <div style={{ background: 'var(--bg-surface)', padding: 16, borderRadius: 8, marginBottom: 16, border: '1px solid var(--border-default)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Plat Armada:</span>
                <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{form.plat_nomor}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Afiliasi Mitra:</span>
                <span style={{ fontWeight: 600, color: 'var(--color-info)' }}>{form.mitra_nama}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Harga Bersih Pembelian:</span>
                <span style={{ fontWeight: 600, color: 'var(--color-success)' }}>
                  {formatRupiah(latestHarga - form.mitra_fee)} / Kg
                </span>
              </div>
            </div>
          )}

          <div className="form-group">
            <label className="form-label form-label-required">Tonase Masuk Pabrik (Kg)</label>
            <input 
              type="number" 
              className="form-input" 
              style={{ fontSize: 24, fontWeight: 'bold', padding: 16, height: 'auto' }}
              required 
              min={1}
              placeholder="0"
              value={form.tonase} 
              onChange={e => setForm({...form, tonase: e.target.value})} 
            />
          </div>

          <button 
            type="submit" 
            className="btn btn-primary" 
            style={{ width: '100%', padding: 16, fontSize: 18 }}
            disabled={saving || loading || !form.sopir_id}
          >
            {saving ? 'MENYIMPAN...' : 'SIMPAN TRANSAKSI'}
          </button>
        </form>
      </div>
    </AppShell>
  );
}
