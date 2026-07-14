'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
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
import {
  hitungSewaArmadaBL,
  kalkulasiTransaksiMitra,
  resolveEffectiveMitraFeeSnapshot,
} from '@/lib/transaksi-mitra-calculations';
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
  const [toast, setToast] = useState(null);

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
    berat_netto: '',
    potongan_pabrik: '0',
    pakai_sewa_armada_cb: false,
  });

  const loadData = useCallback(async () => {
    setLoading(true);

    const [
      { data: sopirData },
      { data: mitraData },
      { data: hargaData },
      { data: feeHistoryData, error: feeHistoryError },
    ] = await Promise.all([
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
        .select('id, master_mitra_id, fee_per_kg, berlaku_mulai, berlaku_sampai, aktif, alasan_perubahan')
        .eq('aktif', true)
        .order('berlaku_mulai', { ascending: false }),
    ]);

    setSopirs(sopirData || []);
    setMitras(mitraData || []);
    setFeeHistories(feeHistoryError ? [] : feeHistoryData || []);

    if (hargaData && hargaData.length > 0) {
      setLatestHarga(hargaData[0].harga_per_kg);
    }

    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  // ---------------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------------

  const selectedDefaultSopir = useMemo(() => (
    sopirs.find(s => s.id === form.sopir_id) || null
  ), [form.sopir_id, sopirs]);

  const mitraTransaksi = useMemo(() => (
    mitras.find(m => m.id === form.mitra_id) || null
  ), [form.mitra_id, mitras]);

  const mitraAfiliasiSopir = useMemo(() => {
    if (!selectedDefaultSopir?.mitra_id) return null;
    return mitras.find(m => m.id === selectedDefaultSopir.mitra_id) || null;
  }, [selectedDefaultSopir, mitras]);

  const prioritizedSopirs = useMemo(() => {
    if (!form.mitra_id) return sopirs;
    return [...sopirs].sort((a, b) => {
      const getRank = (sopir) => {
        if (sopir.mitra_id === form.mitra_id) return 0;
        if (!sopir.mitra_id) return 1;
        return 2;
      };
      const rankDiff = getRank(a) - getRank(b);
      if (rankDiff !== 0) return rankDiff;
      return String(a.nama || '').localeCompare(String(b.nama || ''), 'id');
    });
  }, [form.mitra_id, sopirs]);

  const defaultMitraLabel = formatMitraLabel(selectedDefaultSopir?.master_mitra) || 'Tanpa default / armada bersama';
  const sopirMitraBerbeda = Boolean(
    selectedDefaultSopir?.mitra_id
    && form.mitra_id
    && selectedDefaultSopir.mitra_id !== form.mitra_id
  );

  /** Kalkulasi real-time berdasarkan input form saat ini */
  const kalkulasi = useMemo(() => {
    const beratNetto = parseFloat(form.berat_netto) || 0;
    const potongan   = parseFloat(form.potongan_pabrik) || 0;
    const beratDibayar = Math.max(0, beratNetto - potongan);

    const hargaPabrik = latestHarga;
    const feeOwner    = form.mitra_fee;
    const hargaBersih = Math.max(0, hargaPabrik - feeOwner);

    const totalKotor        = Math.round(beratDibayar * hargaPabrik);
    const totalFeeOwner     = Math.round(beratDibayar * feeOwner);
    const totalNilaiBersih  = Math.round(beratDibayar * hargaBersih);

    const pakaiSewaArmada = form.pakai_sewa_armada_cb;
    const sewaArmada = {
      pakaiSewaArmada,
      biayaSewaArmadaPerKg: pakaiSewaArmada ? 150 : 0,
      biayaSewaArmadaTotal: pakaiSewaArmada ? Math.round(beratNetto * 150) : 0,
    };

    const totalBersihMitra = totalNilaiBersih - sewaArmada.biayaSewaArmadaTotal;

    return {
      beratNetto,
      potongan,
      beratDibayar,
      hargaPabrik,
      feeOwner,
      hargaBersih,
      totalKotor,
      totalFeeOwner,
      totalNilaiBersih,
      totalBersihMitra,
      ...sewaArmada,
    };
  }, [form.berat_netto, form.potongan_pabrik, form.mitra_fee, form.pakai_sewa_armada_cb, latestHarga]);

  // ---------------------------------------------------------------------------
  // Helpers mitra/sopir
  // ---------------------------------------------------------------------------

  function getEffectiveFeeSnapshot(mitraId, tanggal) {
    return resolveEffectiveMitraFeeSnapshot({
      mitraId,
      tanggal: tanggal || getTodayISO(),
      mitras,
      feeHistories,
    });
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
        sopir_default_nama: '',
        sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
        sopir_aktual_id: '',
        sopir_aktual_nama: '',
        sopir_aktual_no_hp: '',
        catatan_sopir: '',
        pakai_sewa_armada_cb: false,
      });
      return;
    }

    const sopir = sopirs.find(s => s.id === selectedId);
    if (sopir) {
      const nextMitraId = form.mitra_id || sopir.mitra_id || '';
      
      const mitraTx = mitras.find(m => m.id === nextMitraId);
      const mitraAfiliasi = mitras.find(m => m.id === sopir.mitra_id);
      const autoSewa = hitungSewaArmadaBL({ mitraTransaksi: mitraTx, mitraAfiliasiSopir: mitraAfiliasi, beratNettoPabrikKg: 0 }).pakaiSewaArmada;

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
        pakai_sewa_armada_cb: autoSewa,
      }, nextMitraId, form.tanggal));
    }
  }

  function handleMitraChange(selectedId) {
    if (!selectedId) {
      setForm(applyMitraSnapshot({
        ...form,
        sopir_id: '',
        plat_nomor: '',
        sopir_default_nama: '',
        sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
        sopir_aktual_id: '',
        sopir_aktual_nama: '',
        sopir_aktual_no_hp: '',
        catatan_sopir: '',
        berat_netto: '',
        potongan_pabrik: '0',
      }, '', form.tanggal));
      return;
    }
    const mitraTx = mitras.find(m => m.id === selectedId);
    const sopir = sopirs.find(s => s.id === form.sopir_id);
    const mitraAfiliasi = mitras.find(m => m.id === sopir?.mitra_id);
    const autoSewa = hitungSewaArmadaBL({ mitraTransaksi: mitraTx, mitraAfiliasiSopir: mitraAfiliasi, beratNettoPabrikKg: 0 }).pakaiSewaArmada;

    setForm(applyMitraSnapshot({ ...form, pakai_sewa_armada_cb: autoSewa }, selectedId, form.tanggal));
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

  function showToast(message, type = 'error') {
    setToast({ message, type });
    setTimeout(() => setToast(null), 4000);
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  async function handleSubmit(e) {
    e.preventDefault();
    setSaving(true);
    setSuccessMsg('');

    const beratNetto = parseFloat(form.berat_netto);
    if (isNaN(beratNetto) || beratNetto <= 0) {
      showToast('Berat Netto dari Pabrik harus lebih dari 0.');
      setSaving(false);
      return;
    }

    const potongan = parseFloat(form.potongan_pabrik) || 0;
    if (potongan < 0) {
      showToast('Potongan Pabrik tidak boleh negatif.');
      setSaving(false);
      return;
    }

    if (potongan > beratNetto) {
      showToast('Potongan Pabrik tidak boleh lebih besar dari Berat Netto.');
      setSaving(false);
      return;
    }

    if (!form.mitra_id) {
      showToast('Pilih mitra transaksi terlebih dahulu.');
      setSaving(false);
      return;
    }

    const sopirAktualNama = form.sopir_aktual_nama.trim();
    if (!sopirAktualNama) {
      showToast('Sopir aktual wajib diisi.');
      setSaving(false);
      return;
    }

    const k = kalkulasi; // pakai kalkulasi yang sudah dihitung di useMemo
    const sopirDiganti = form.sopir_aktual_mode === SOPIR_AKTUAL_MANUAL
      || (form.sopir_aktual_mode === SOPIR_AKTUAL_MASTER && form.sopir_aktual_id !== form.sopir_id);
    const sopirAktualId = form.sopir_aktual_mode === SOPIR_AKTUAL_DEFAULT
      ? form.sopir_id
      : form.sopir_aktual_mode === SOPIR_AKTUAL_MASTER
        ? form.sopir_aktual_id
        : null;

    const { error } = await supabase.from('transaksi_mitra').insert({
      tanggal:            form.tanggal,
      sopir_id:           form.sopir_id,
      mitra_id:           form.mitra_id,
      plat_nomor:         form.plat_nomor,
      sopir_default_id:   form.sopir_id,
      sopir_default_nama: form.sopir_default_nama,
      sopir_aktual_id:    sopirAktualId,
      sopir_aktual_nama:  sopirAktualNama,
      sopir_aktual_no_hp: form.sopir_aktual_no_hp || null,
      sopir_aktual_source: form.sopir_aktual_mode === SOPIR_AKTUAL_MANUAL ? 'manual' : 'master',
      sopir_diganti_dari_default: sopirDiganti,
      catatan_sopir:      form.catatan_sopir || null,

      // Field berat (P0)
      tonase:                 k.beratNetto,          // backward-compat: tonase = berat netto
      berat_netto_pabrik_kg:  k.beratNetto,
      potongan_pabrik_kg:     k.potongan,
      berat_dibayar_kg:       k.beratDibayar,

      // Snapshot harga
      harga_harian:       k.hargaPabrik,
      harga_pabrik_per_kg: k.hargaPabrik,
      fee_owner_per_kg:    k.feeOwner,
      harga_bersih_per_kg: k.hargaBersih,
      fee_owner_history_id: form.fee_owner_history_id || null,

      // Total nilai (semua basis berat_dibayar)
      total_kotor:        k.totalKotor,
      total_fee_owner:    k.totalFeeOwner,
      total_nilai_bersih: k.totalNilaiBersih,

      // Sewa armada CB
      pakai_sewa_armada_bl:      form.pakai_sewa_armada_cb,
      biaya_sewa_armada_per_kg:  form.pakai_sewa_armada_cb ? k.biayaSewaArmadaPerKg : null,
      biaya_sewa_armada_total:   form.pakai_sewa_armada_cb ? k.biayaSewaArmadaTotal : 0,
    });

    if (error) {
      showToast(`Gagal menyimpan data: ${error.message}`);
    } else {
      const infoSopir   = sopirDiganti ? `, sopir aktual: ${sopirAktualNama}` : '';
      const infoPotongan = k.potongan > 0 ? `, potongan ${k.potongan.toLocaleString('id-ID')} kg` : '';
      const infoSewa     = k.pakaiSewaArmada ? `, sewa armada ${formatRupiah(k.biayaSewaArmadaTotal)}` : '';
      setSuccessMsg(
        `Berhasil menyimpan ${k.beratNetto.toLocaleString('id-ID')} kg (berat dibayar ${k.beratDibayar.toLocaleString('id-ID')} kg)${infoPotongan} untuk armada ${form.plat_nomor}${infoSopir}${infoSewa} (Mitra: ${form.mitra_nama}).`
      );
      // Reset form, pertahankan tanggal
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
        berat_netto: '',
        potongan_pabrik: '0',
        pakai_sewa_armada_cb: false,
      });
    }

    setSaving(false);
  }

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  const siapInput = Boolean(form.mitra_id && form.sopir_id);
  const beratNettoNum = parseFloat(form.berat_netto) || 0;
  const potonganNum   = parseFloat(form.potongan_pabrik) || 0;
  const beratDibayarNum = Math.max(0, beratNettoNum - potonganNum);
  const reviewReady = siapInput && beratNettoNum > 0;

  return (
    <AppShell title="Pengiriman Mitra" subtitle="Catat pengiriman mitra masuk">
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
            Harga Pabrik / TWB Hari Ini: <strong>{formatRupiah(latestHarga)} / Kg</strong>
          </p>
        </div>
      </div>

      <div className="card" style={{ maxWidth: 580, margin: '0 auto', padding: 'var(--space-xl)' }}>
        {successMsg && (
          <div style={{ background: 'var(--color-success-bg)', color: 'var(--color-success)', padding: 'var(--space-md)', borderRadius: 'var(--radius-md)', marginBottom: 'var(--space-lg)', fontWeight: 500 }}>
            ✅ {successMsg}
          </div>
        )}

        <form onSubmit={handleSubmit}>
          {/* Tanggal */}
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

          {/* Mitra Transaksi */}
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
              loading={loading}
            />
            <div className="form-hint">Fee Owner dan harga bersih mengikuti mitra dan tanggal transaksi ini.</div>
          </div>

          {/* Panel info mitra */}
          {form.mitra_id && (
            <div style={{ background: 'var(--bg-surface)', padding: 16, borderRadius: 8, marginBottom: 16, border: '1px solid var(--border-default)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 8 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Mitra Transaksi:</span>
                <span style={{ fontWeight: 600, color: 'var(--color-info)', textAlign: 'right' }}>{form.mitra_nama || '-'}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 8 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Fee Owner:</span>
                <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{formatRupiah(form.mitra_fee)} / Kg</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: form.sopir_id ? 12 : 0 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Harga Bersih ke Mitra:</span>
                <span style={{ fontWeight: 600, color: 'var(--color-success)' }}>{formatRupiah(Math.max(latestHarga - form.mitra_fee, 0))} / Kg</span>
              </div>

              {form.sopir_id && (
                <div style={{ borderTop: '1px solid var(--border-default)', paddingTop: 12 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 8 }}>
                    <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Sopir Default:</span>
                    <span style={{ fontWeight: 600, color: 'var(--text-primary)', textAlign: 'right' }}>{form.sopir_default_nama}</span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 8 }}>
                    <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Plat Armada:</span>
                    <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{form.plat_nomor}</span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                    <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Afiliasi Default:</span>
                    <span style={{ fontWeight: 600, color: sopirMitraBerbeda ? 'var(--color-warning)' : 'var(--text-primary)', textAlign: 'right' }}>
                      {defaultMitraLabel}
                    </span>
                  </div>
                  {sopirMitraBerbeda && (
                    <div className="form-hint" style={{ marginTop: 8 }}>
                      Afiliasi sopir berbeda dari mitra transaksi. Ini tetap boleh untuk kasus sopir/armada dipakai lintas mitra.
                    </div>
                  )}
                </div>
              )}
            </div>
          )}

          {/* Sopir / Armada */}
          <div className="form-group">
            <label className="form-label form-label-required">Sopir / Armada</label>
            <SearchableCombobox
              value={form.sopir_id}
              options={prioritizedSopirs}
              onChange={handleSopirChange}
              getOptionLabel={formatSopirArmadaLabel}
              getOptionDescription={formatSopirArmadaDescription}
              getSearchText={getSopirArmadaSearchText}
              placeholder={form.mitra_id ? 'Cari sopir, plat, atau mitra...' : 'Pilih mitra dulu'}
              emptyLabel="Armada / sopir tidak ditemukan"
              loading={loading}
              disabled={!form.mitra_id}
            />
            <div className="form-hint">Sopir/armada dari mitra ini ditampilkan lebih dulu; sopir lain tetap bisa dicari jika ada penggantian lapangan.</div>
          </div>

          {/* Sopir Aktual */}
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

          {/* Berat Netto dari Pabrik */}
          <div className="form-group">
            <label className="form-label form-label-required">Berat Netto dari Pabrik (kg)</label>
            <input
              type="number"
              className="form-input"
              style={{ fontSize: 24, fontWeight: 'bold', padding: 16, height: 'auto' }}
              required
              min={1}
              placeholder={siapInput ? '0' : 'Pilih mitra dan sopir dulu'}
              value={form.berat_netto}
              onChange={e => setForm({ ...form, berat_netto: e.target.value })}
              disabled={!siapInput}
            />
            <div className="form-hint">Angka berat yang tertulis di nota / timbangan pabrik.</div>
          </div>

          {/* Potongan Pabrik */}
          <div className="form-group">
            <label className="form-label">Potongan Pabrik (kg)</label>
            <input
              type="number"
              className="form-input"
              min={0}
              placeholder="0"
              value={form.potongan_pabrik}
              onChange={e => setForm({ ...form, potongan_pabrik: e.target.value })}
              disabled={!siapInput}
            />
            <div className="form-hint">Isi 0 jika tidak ada potongan dari pabrik.</div>
          </div>

          {/* Sewa Armada CB */}
          <div className="form-group" style={{ marginTop: 8 }}>
            <label className="form-label" style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', marginBottom: 0 }}>
              <input
                type="checkbox"
                checked={form.pakai_sewa_armada_cb}
                onChange={e => setForm({ ...form, pakai_sewa_armada_cb: e.target.checked })}
                disabled={!siapInput}
                style={{ width: 18, height: 18 }}
              />
              <span style={{ fontSize: 15, fontWeight: 500 }}>Pakai Armada CB (Dipotong Sewa Rp150/kg)</span>
            </label>
            <div className="form-hint" style={{ marginTop: 4 }}>
              Centang jika mitra luar menggunakan fasilitas armada/angkutan milik pabrik (Armada CB).
            </div>
          </div>

          {/* Panel review kalkulasi */}
          {reviewReady && (
            <div style={{
              background: 'var(--bg-surface)',
              border: '1px solid var(--border-default)',
              borderRadius: 8,
              padding: 16,
              marginBottom: 16,
            }}>
              <div style={{ fontWeight: 700, fontSize: 13, color: 'var(--text-tertiary)', marginBottom: 12, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                Ringkasan Transaksi
              </div>

              {/* Berat */}
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Berat Netto dari Pabrik:</span>
                <span style={{ fontWeight: 600 }}>{beratNettoNum.toLocaleString('id-ID')} kg</span>
              </div>
              {potonganNum > 0 && (
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                  <span style={{ color: 'var(--color-warning)', fontSize: 14 }}>Potongan Pabrik:</span>
                  <span style={{ fontWeight: 600, color: 'var(--color-warning)' }}>−{potonganNum.toLocaleString('id-ID')} kg</span>
                </div>
              )}
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 12, paddingBottom: 12, borderBottom: '1px solid var(--border-default)' }}>
                <span style={{ color: 'var(--text-primary)', fontSize: 14, fontWeight: 600 }}>Berat Dibayar:</span>
                <span style={{ fontWeight: 800, fontSize: 16 }}>{beratDibayarNum.toLocaleString('id-ID')} kg</span>
              </div>

              {/* Harga */}
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Harga Pabrik / TWB:</span>
                <span style={{ fontWeight: 600 }}>{formatRupiah(kalkulasi.hargaPabrik)} / kg</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Fee Owner:</span>
                <span style={{ fontWeight: 600 }}>{formatRupiah(kalkulasi.feeOwner)} / kg</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 12, paddingBottom: 12, borderBottom: '1px solid var(--border-default)' }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Harga Bersih Mitra / kg:</span>
                <span style={{ fontWeight: 600, color: 'var(--color-success)' }}>{formatRupiah(kalkulasi.hargaBersih)}</span>
              </div>

              {/* Nilai */}
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Total Kotor Pabrik:</span>
                <span style={{ fontWeight: 600 }}>{formatRupiah(kalkulasi.totalKotor)}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Fee Owner Dasar:</span>
                <span style={{ fontWeight: 600 }}>{formatRupiah(kalkulasi.totalFeeOwner)}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: kalkulasi.pakaiSewaArmada ? 6 : 0 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Nilai Bersih Mitra:</span>
                <span style={{ fontWeight: 700, color: 'var(--color-success)' }}>{formatRupiah(kalkulasi.totalNilaiBersih)}</span>
              </div>

              {/* Sewa armada CB */}
              {kalkulasi.pakaiSewaArmada && (
                <>
                  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                    <span style={{ color: 'var(--color-warning)', fontSize: 14 }}>
                      Sewa Armada CB (Rp{kalkulasi.biayaSewaArmadaPerKg}/kg × {beratNettoNum.toLocaleString('id-ID')} kg netto):
                    </span>
                    <span style={{ fontWeight: 600, color: 'var(--color-warning)' }}>−{formatRupiah(kalkulasi.biayaSewaArmadaTotal)}</span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, paddingTop: 8, borderTop: '1px solid var(--border-default)', marginTop: 4 }}>
                    <span style={{ color: 'var(--text-primary)', fontSize: 14, fontWeight: 600 }}>Estimasi Diterima Mitra:</span>
                    <span style={{ fontWeight: 800, color: 'var(--color-success)', fontSize: 16 }}>{formatRupiah(kalkulasi.totalBersihMitra)}</span>
                  </div>
                  <div className="form-hint" style={{ marginTop: 8 }}>
                    ⚠️ Sewa armada dipotong saat kwitansi dibayar dan menjadi pendapatan owner.
                  </div>
                </>
              )}
            </div>
          )}

          <button
            type="submit"
            className="btn btn-primary"
            style={{ width: '100%', padding: 16, fontSize: 18 }}
            disabled={saving || loading || !siapInput}
          >
            {saving ? 'MENYIMPAN...' : 'SIMPAN TRANSAKSI'}
          </button>
        </form>
      </div>
    </AppShell>
  );
}
