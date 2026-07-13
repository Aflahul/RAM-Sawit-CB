'use client';

import { useCallback, useEffect, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import {
  formatMitraLabel,
  formatSopirArmadaDescription,
  formatSopirArmadaLabel,
  getMitraSearchText,
  getSopirArmadaSearchText,
} from '@/lib/display-labels';
import { supabase } from '@/lib/supabase';
import { formatRupiah, getTodayISO } from '@/lib/utils';

const SOPIR_AKTUAL_DEFAULT = 'default';
const SOPIR_AKTUAL_MASTER = 'master';
const SOPIR_AKTUAL_MANUAL = 'manual';

export default function InputTimbanganPage() {
  const [sopirs, setSopirs] = useState([]);
  const [mitras, setMitras] = useState([]);
  const [feeHistories, setFeeHistories] = useState([]);
  const [latestHarga, setLatestHarga] = useState(0);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');

  const [form, setForm] = useState({
    tanggal: getTodayISO(),
    sopir_id: '',
    plat_nomor: '',
    mitra_id: '',
    mitra_nama: '',
    mitra_fee: 0,
    fee_owner_history_id: '',
    sopir_default_nama: '',
    sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
    sopir_aktual_id: '',
    sopir_aktual_nama: '',
    sopir_aktual_no_hp: '',
    catatan_sopir: '',
    tonase: '',
  });

  const loadData = useCallback(async () => {
    setLoading(true);
    
    // Load Sopir + Relasi Mitra
    const [{ data: sopirData }, { data: mitraData }, { data: hargaData }, { data: feeHistoryData, error: feeHistoryError }] = await Promise.all([
      supabase
        .from('sopir')
        .select(`
          id, nama, no_hp, plat_nomor, mitra_id,
          master_mitra ( id, kode, nama, alamat, fee_per_kg )
        `)
        .eq('aktif', true)
        .order('nama'),
      supabase
        .from('master_mitra')
        .select('id, kode, nama, alamat, fee_per_kg')
        .eq('aktif', true)
        .order('kode'),
      supabase
        .from('harga_tbs')
        .select('harga_per_kg')
        .order('tanggal', { ascending: false })
        .limit(1),
      supabase
        .from('fee_owner_mitra_history')
        .select('id, master_mitra_id, fee_per_kg, berlaku_mulai, berlaku_sampai, aktif')
        .eq('aktif', true)
        .order('berlaku_mulai', { ascending: false }),
    ]);

    setSopirs(sopirData || []);
    setMitras(mitraData || []);
    setFeeHistories(feeHistoryError ? [] : feeHistoryData || []);

    // Load Harga Terbaru
    if (hargaData && hargaData.length > 0) {
      setLatestHarga(hargaData[0].harga_per_kg);
    }
    
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  function getEffectiveFeeSnapshot(mitraId, tanggal) {
    const fallbackMitra = mitras.find(m => m.id === mitraId);
    const tanggalValue = tanggal || getTodayISO();
    const history = feeHistories.find(item => {
      if (item.master_mitra_id !== mitraId) return false;
      if (item.berlaku_mulai && tanggalValue < item.berlaku_mulai) return false;
      if (item.berlaku_sampai && tanggalValue > item.berlaku_sampai) return false;
      return true;
    });

    return {
      fee: Number(history?.fee_per_kg ?? fallbackMitra?.fee_per_kg ?? 0),
      historyId: history?.id || '',
    };
  }

  function applyMitraSnapshot(nextForm, mitraId = nextForm.mitra_id, tanggal = nextForm.tanggal) {
    const mitra = mitras.find(m => m.id === mitraId);
    const feeSnapshot = getEffectiveFeeSnapshot(mitraId, tanggal);

    return {
      ...nextForm,
      mitra_id: mitraId,
      mitra_nama: formatMitraLabel(mitra),
      mitra_fee: feeSnapshot.fee,
      fee_owner_history_id: feeSnapshot.historyId,
    };
  }

  function handleTanggalChange(tanggal) {
    const nextForm = { ...form, tanggal };
    setForm(form.mitra_id ? applyMitraSnapshot(nextForm, form.mitra_id, tanggal) : nextForm);
  }

  function handleSopirChange(selectedId) {
    if (!selectedId) {
      setForm({
        ...form,
        sopir_id: '',
        plat_nomor: '',
        mitra_id: '',
        mitra_nama: '',
        mitra_fee: 0,
        fee_owner_history_id: '',
        sopir_default_nama: '',
        sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
        sopir_aktual_id: '',
        sopir_aktual_nama: '',
        sopir_aktual_no_hp: '',
        catatan_sopir: '',
      });
      return;
    }

    const sopir = sopirs.find(s => s.id === selectedId);
    if (sopir) {
      setForm(applyMitraSnapshot({
        ...form,
        sopir_id: sopir.id,
        plat_nomor: sopir.plat_nomor || '-',
        mitra_id: sopir.mitra_id || '',
        sopir_default_nama: sopir.nama,
        sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
        sopir_aktual_id: sopir.id,
        sopir_aktual_nama: sopir.nama,
        sopir_aktual_no_hp: sopir.no_hp || '',
        catatan_sopir: '',
      }, sopir.mitra_id || '', form.tanggal));
    }
  }

  function handleMitraChange(selectedId) {
    setForm(applyMitraSnapshot({ ...form }, selectedId, form.tanggal));
  }

  function handleSopirAktualModeChange(mode) {
    const defaultSopir = sopirs.find(s => s.id === form.sopir_id);
    const nextForm = {
      ...form,
      sopir_aktual_mode: mode,
      catatan_sopir: mode === SOPIR_AKTUAL_DEFAULT ? '' : form.catatan_sopir,
    };

    if (mode === SOPIR_AKTUAL_DEFAULT && defaultSopir) {
      nextForm.sopir_aktual_id = defaultSopir.id;
      nextForm.sopir_aktual_nama = defaultSopir.nama;
      nextForm.sopir_aktual_no_hp = defaultSopir.no_hp || '';
    }

    if (mode === SOPIR_AKTUAL_MASTER) {
      nextForm.sopir_aktual_id = '';
      nextForm.sopir_aktual_nama = '';
      nextForm.sopir_aktual_no_hp = '';
    }

    if (mode === SOPIR_AKTUAL_MANUAL) {
      nextForm.sopir_aktual_id = '';
      nextForm.sopir_aktual_nama = '';
      nextForm.sopir_aktual_no_hp = '';
    }

    setForm(nextForm);
  }

  function handleSopirAktualMasterChange(selectedId) {
    const selectedSopir = sopirs.find(s => s.id === selectedId);

    setForm({
      ...form,
      sopir_aktual_id: selectedId,
      sopir_aktual_nama: selectedSopir?.nama || '',
      sopir_aktual_no_hp: selectedSopir?.no_hp || '',
    });
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
      alert("Pilih mitra transaksi terlebih dahulu.");
      setSaving(false);
      return;
    }

    const sopirAktualNama = form.sopir_aktual_nama.trim();
    if (!sopirAktualNama) {
      alert("Sopir aktual wajib diisi.");
      setSaving(false);
      return;
    }

    const hargaPabrik = latestHarga;
    const hargaBeliMitra = hargaPabrik - form.mitra_fee;
    const totalKotorPabrik = tonase * hargaPabrik;
    const totalNilaiBersih = tonase * hargaBeliMitra;
    const totalFeeOwner = tonase * form.mitra_fee;
    const sopirDiganti = form.sopir_aktual_mode === SOPIR_AKTUAL_MANUAL
      || (form.sopir_aktual_mode === SOPIR_AKTUAL_MASTER && form.sopir_aktual_id !== form.sopir_id);
    const sopirAktualId = form.sopir_aktual_mode === SOPIR_AKTUAL_DEFAULT
      ? form.sopir_id
      : form.sopir_aktual_mode === SOPIR_AKTUAL_MASTER
        ? form.sopir_aktual_id
        : null;

    const { error } = await supabase.from('transaksi_mitra').insert({
      tanggal: form.tanggal,
      sopir_id: form.sopir_id,
      mitra_id: form.mitra_id,
      plat_nomor: form.plat_nomor,
      sopir_default_id: form.sopir_id,
      sopir_default_nama: form.sopir_default_nama,
      sopir_aktual_id: sopirAktualId,
      sopir_aktual_nama: sopirAktualNama,
      sopir_aktual_no_hp: form.sopir_aktual_no_hp || null,
      sopir_aktual_source: form.sopir_aktual_mode === SOPIR_AKTUAL_MANUAL ? 'manual' : 'master',
      sopir_diganti_dari_default: sopirDiganti,
      catatan_sopir: form.catatan_sopir || null,
      tonase: tonase,
      harga_harian: hargaPabrik,
      total_kotor: totalKotorPabrik,
      harga_pabrik_per_kg: hargaPabrik,
      fee_owner_per_kg: form.mitra_fee,
      harga_bersih_per_kg: hargaBeliMitra,
      total_fee_owner: totalFeeOwner,
      total_nilai_bersih: totalNilaiBersih,
      fee_owner_history_id: form.fee_owner_history_id || null
    });

    if (error) {
      alert("Gagal menyimpan data: " + error.message);
    } else {
      const infoSopir = sopirDiganti ? `, sopir aktual: ${sopirAktualNama}` : '';
      setSuccessMsg(`Berhasil menyimpan ${tonase} Kg untuk armada ${form.plat_nomor}${infoSopir} (Mitra: ${form.mitra_nama}).`);
      // Reset form but keep date
      setForm({
        ...form,
        sopir_id: '',
        plat_nomor: '',
        mitra_id: '',
        mitra_nama: '',
        mitra_fee: 0,
        fee_owner_history_id: '',
        sopir_default_nama: '',
        sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
        sopir_aktual_id: '',
        sopir_aktual_nama: '',
        sopir_aktual_no_hp: '',
        catatan_sopir: '',
        tonase: '',
      });
    }

    setSaving(false);
  }

  return (
    <AppShell title="Pengiriman Mitra" subtitle="Catat armada mitra masuk">
      <div className="page-header">
        <div>
          <p className="page-description">Harga Pabrik / TWB Hari Ini: <strong>{formatRupiah(latestHarga)} / Kg</strong></p>
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
              onChange={e => handleTanggalChange(e.target.value)}
            />
          </div>

          <div className="form-group">
            <label className="form-label form-label-required">Armada / Sopir Default</label>
            <SearchableCombobox
              value={form.sopir_id}
              options={sopirs}
              onChange={handleSopirChange}
              getOptionLabel={formatSopirArmadaLabel}
              getOptionDescription={formatSopirArmadaDescription}
              getSearchText={getSopirArmadaSearchText}
              placeholder="Cari sopir, plat, atau mitra..."
              emptyLabel="Armada / sopir tidak ditemukan"
              loading={loading}
            />
            <div className="form-hint">Data ini dipakai untuk auto-fill plat dan afiliasi mitra.</div>
          </div>

          {form.sopir_id && (
            <div style={{ background: 'var(--bg-surface)', padding: 16, borderRadius: 8, marginBottom: 16, border: '1px solid var(--border-default)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Sopir Default:</span>
                <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{form.sopir_default_nama}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Plat Armada:</span>
                <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{form.plat_nomor}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Default Mitra:</span>
                <span style={{ fontWeight: 600, color: 'var(--color-info)' }}>{form.mitra_nama || 'Belum ada'}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Fee Owner:</span>
                <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{formatRupiah(form.mitra_fee)} / Kg</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Harga Bersih ke Mitra:</span>
                <span style={{ fontWeight: 600, color: 'var(--color-success)' }}>
                  {form.mitra_id ? `${formatRupiah(latestHarga - form.mitra_fee)} / Kg` : 'Pilih mitra'}
                </span>
              </div>
            </div>
          )}

          {form.sopir_id && (
            <div className="form-group">
              <label className="form-label form-label-required">Mitra Transaksi</label>
              <SearchableCombobox
                value={form.mitra_id}
                options={mitras}
                onChange={handleMitraChange}
                getOptionLabel={formatMitraLabel}
                getSearchText={getMitraSearchText}
                placeholder="Cari kode, alamat, atau nama mitra..."
                emptyLabel="Mitra tidak ditemukan"
              />
              <div className="form-hint">Bisa diubah jika armada yang sama dipakai oleh mitra SL/BL yang berbeda.</div>
            </div>
          )}

          {form.sopir_id && (
            <div className="form-group">
              <label className="form-label form-label-required">Sopir Aktual Hari Ini</label>
              <select
                className="form-input"
                value={form.sopir_aktual_mode}
                onChange={(e) => handleSopirAktualModeChange(e.target.value)}
              >
                <option value={SOPIR_AKTUAL_DEFAULT}>Sama dengan sopir default</option>
                <option value={SOPIR_AKTUAL_MASTER}>Pilih sopir lain dari master</option>
                <option value={SOPIR_AKTUAL_MANUAL}>Input sopir pengganti manual</option>
              </select>
            </div>
          )}

          {form.sopir_id && form.sopir_aktual_mode === SOPIR_AKTUAL_MASTER && (
            <div className="form-group">
              <label className="form-label form-label-required">Pilih Sopir Pengganti</label>
              <SearchableCombobox
                value={form.sopir_aktual_id}
                options={sopirs}
                onChange={handleSopirAktualMasterChange}
                getOptionLabel={formatSopirArmadaLabel}
                getOptionDescription={formatSopirArmadaDescription}
                getSearchText={getSopirArmadaSearchText}
                placeholder="Cari sopir pengganti..."
                emptyLabel="Sopir tidak ditemukan"
              />
            </div>
          )}

          {form.sopir_id && form.sopir_aktual_mode === SOPIR_AKTUAL_MANUAL && (
            <div className="form-grid">
              <div className="form-group">
                <label className="form-label form-label-required">Nama Sopir Pengganti</label>
                <input
                  className="form-input"
                  required
                  value={form.sopir_aktual_nama}
                  onChange={e => setForm({ ...form, sopir_aktual_nama: e.target.value })}
                  placeholder="Nama sopir aktual"
                />
              </div>
              <div className="form-group">
                <label className="form-label">No. HP</label>
                <input
                  className="form-input"
                  value={form.sopir_aktual_no_hp}
                  onChange={e => setForm({ ...form, sopir_aktual_no_hp: e.target.value })}
                  placeholder="Opsional"
                />
              </div>
            </div>
          )}

          {form.sopir_id && form.sopir_aktual_mode !== SOPIR_AKTUAL_DEFAULT && (
            <div className="form-group">
              <label className="form-label">Catatan Pergantian Sopir</label>
              <input
                className="form-input"
                value={form.catatan_sopir}
                onChange={e => setForm({ ...form, catatan_sopir: e.target.value })}
                placeholder="Contoh: sopir default berhalangan"
              />
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
