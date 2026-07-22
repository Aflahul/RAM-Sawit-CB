'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Modal from '@/components/ui/Modal';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import { ChevronDown, ChevronRight } from 'lucide-react';
import {
  formatMitraLabel,
  formatSopirArmadaDescription,
  formatSopirArmadaLabel,
  getMitraSearchText,
  getSopirArmadaSearchText,
} from '@/lib/display-labels';
import { supabase } from '@/lib/supabase';
import {
  hitungSewaArmadaCB,
  kalkulasiTransaksiMitra,
  resolveEffectiveMitraFeeSnapshot,
} from '@/lib/transaksi-mitra-calculations';
import { formatRupiah, getTodayISO } from '@/lib/utils';

const SOPIR_AKTUAL_DEFAULT = 'default';
const SOPIR_AKTUAL_MASTER = 'master';
const SOPIR_AKTUAL_MANUAL = 'manual';

export default function FormPengirimanModal({ open, onClose, onSuccess, initialDate }) {
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [sopirs, setSopirs] = useState([]);
  const [mitras, setMitras] = useState([]);
  const [feeHistories, setFeeHistories] = useState([]);
  const [latestHarga, setLatestHarga] = useState(0);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');
  const [toast, setToast] = useState(null);

  const [showQuickAddArmada, setShowQuickAddArmada] = useState(false);
  const [savingArmada, setSavingArmada] = useState(false);
  const [formArmadaCepat, setFormArmadaCepat] = useState({
    nama: '',
    plat_nomor: '',
    no_hp: '',
    mitra_id: '',
    is_armada_cb: false,
  });

  const [form, setForm] = useState({
    tanggal: initialDate || getTodayISO(),
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
    kenakan_sewa_armada_cb: false,
    catat_dana_operasional_trip: false,
    alasan_tanpa_sewa_armada_cb: '',
    alasan_tanpa_dana_operasional_trip: '',
    tarif_sewa_angkut: 0,
    dana_operasional_trip: 0,
  });

  useEffect(() => {
    if (open) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setForm(f => ({ ...f, tanggal: initialDate || getTodayISO() }));
      setSuccessMsg('');
      setShowAdvanced(false);
    }
  }, [open, initialDate]);

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
          id, nama, no_hp, plat_nomor, mitra_id, is_armada_cb,
          master_mitra ( id, kode, nama, alamat, fee_per_kg )
        `)
        .eq('aktif', true)
        .order('nama'),
      supabase
        .from('master_mitra')
        .select('id, kode, nama, alamat, fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip')
        .eq('aktif', true)
        .order('kode'),
      supabase
        .from('harga_tbs')
        .select('harga_per_kg')
        .order('tanggal', { ascending: false })
        .limit(1),
      supabase
        .from('fee_owner_mitra_history')
        .select('id, master_mitra_id, fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip, berlaku_mulai, berlaku_sampai, aktif, alasan_perubahan')
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
    if (open) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      loadData();
    }
  }, [loadData, open]);

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
  const isSelectedArmadaCB = Boolean(selectedDefaultSopir?.is_armada_cb);
  const danaOperasionalTrip = isSelectedArmadaCB && form.catat_dana_operasional_trip
    ? Number(form.dana_operasional_trip || 0)
    : 0;

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

    const pakaiSewaArmada = isSelectedArmadaCB && form.kenakan_sewa_armada_cb;
    const isSewa = hitungSewaArmadaCB({ 
      isArmadaCB: pakaiSewaArmada, 
      beratNettoPabrikKg: beratNetto,
      tarifSewaAngkut: form.tarif_sewa_angkut,
    });
    const sewaArmada = {
      pakaiSewaArmada: isSewa.pakaiSewaArmada,
      biayaSewaArmadaKotor: isSewa.biayaSewaArmadaKotor,
      biayaSewaArmadaTotal: isSewa.pakaiSewaArmada
        ? Math.max(0, isSewa.biayaSewaArmadaKotor - danaOperasionalTrip)
        : 0,
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
  }, [form.berat_netto, form.potongan_pabrik, form.mitra_fee, form.kenakan_sewa_armada_cb, form.tarif_sewa_angkut, isSelectedArmadaCB, danaOperasionalTrip, latestHarga]);

  const beratNettoNum = kalkulasi.beratNetto;
  const potonganNum = kalkulasi.potongan;
  const beratDibayarNum = kalkulasi.beratDibayar;
  const reviewReady = beratNettoNum > 0 && form.mitra_id;

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
      tarif_sewa_angkut: feeSnapshot.tarifSewaAngkut || 0,
      dana_operasional_trip: feeSnapshot.danaOperasionalTrip || 0,
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
        kenakan_sewa_armada_cb: false,
        catat_dana_operasional_trip: false,
        alasan_tanpa_sewa_armada_cb: '',
        alasan_tanpa_dana_operasional_trip: '',
      });
      return;
    }

    const sopir = sopirs.find(s => s.id === selectedId);
    if (sopir) {
      const nextMitraId = form.mitra_id || sopir.mitra_id || '';
      
      const isCb = Boolean(sopir.is_armada_cb);
      setForm(applyMitraSnapshot({
        ...form,
        sopir_id: sopir.id,
        plat_nomor: sopir.plat_nomor || '-',
        mitra_id: nextMitraId,
        sopir_default_nama: sopir.nama,
        sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
        sopir_aktual_id: sopir.id,
        sopir_aktual_nama: sopir.nama,
        sopir_aktual_no_hp: sopir.no_hp || '',
        catatan_sopir: '',
        kenakan_sewa_armada_cb: isCb,
        catat_dana_operasional_trip: isCb,
        alasan_tanpa_sewa_armada_cb: '',
        alasan_tanpa_dana_operasional_trip: '',
      }, nextMitraId, form.tanggal));
    }
  }

  function handleMitraChange(selectedId) {
    if (!selectedId) {
      setForm(applyMitraSnapshot({
        ...form,
        berat_netto: '',
        potongan_pabrik: '0',
      }, '', form.tanggal));
      return;
    }
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

  function showToast(message, type = 'error') {
    setToast({ message, type });
    setTimeout(() => setToast(null), 4000);
  }

  // ---------------------------------------------------------------------------
  // Quick Add Armada
  // ---------------------------------------------------------------------------

  async function handleSimpanArmadaCepat(e) {
    e.preventDefault();
    if (!formArmadaCepat.nama.trim() || !formArmadaCepat.plat_nomor.trim()) {
      showToast('Nama Sopir dan Plat Nomor wajib diisi.');
      return;
    }
    setSavingArmada(true);

    const normalizedName = formArmadaCepat.nama.trim().toLowerCase();
    const normalizedPlat = formArmadaCepat.plat_nomor.replace(/[^a-z0-9]/gi, '').toUpperCase();
    const duplicate = sopirs.find(item => String(item.nama || '').trim().toLowerCase() === normalizedName
      && String(item.plat_nomor || '').replace(/[^a-z0-9]/gi, '').toUpperCase() === normalizedPlat);

    if (duplicate) {
      showToast('Sopir dan plat tersebut sudah ada. Pilih dari daftar pencarian.');
      setSavingArmada(false);
      return;
    }

    const { data, error } = await supabase.rpc('save_sopir_armada', {
      p_id: null,
      p_nama: formArmadaCepat.nama.trim(),
      p_no_hp: formArmadaCepat.no_hp || null,
      p_mitra_id: formArmadaCepat.mitra_id || null,
      p_plat_nomor: formArmadaCepat.plat_nomor,
      p_is_armada_cb: formArmadaCepat.is_armada_cb,
    });

    if (error) {
      showToast(`Gagal menyimpan armada: ${error.message}`);
      setSavingArmada(false);
      return;
    }

    const savedArmada = Array.isArray(data) ? data[0] : data;
    const savedMitra = mitras.find(item => item.id === savedArmada?.mitra_id) || null;
    const selectableArmada = { ...savedArmada, master_mitra: savedMitra };
    setSopirs(prev => [...prev, selectableArmada]);
    
    const nextMitraId = savedArmada.mitra_id || '';
    setForm(applyMitraSnapshot({
      ...form,
      sopir_id: savedArmada.id,
      plat_nomor: savedArmada.plat_nomor || '-',
      mitra_id: nextMitraId,
      sopir_default_nama: savedArmada.nama,
      sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
      sopir_aktual_id: savedArmada.id,
      sopir_aktual_nama: savedArmada.nama,
      sopir_aktual_no_hp: savedArmada.no_hp || '',
      catatan_sopir: '',
      kenakan_sewa_armada_cb: Boolean(savedArmada.is_armada_cb),
      catat_dana_operasional_trip: Boolean(savedArmada.is_armada_cb),
      alasan_tanpa_sewa_armada_cb: '',
      alasan_tanpa_dana_operasional_trip: '',
    }, nextMitraId, form.tanggal));

    setFormArmadaCepat({ nama: '', plat_nomor: '', no_hp: '', mitra_id: '', is_armada_cb: false });
    setShowQuickAddArmada(false);
    setSavingArmada(false);
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

    if (isSelectedArmadaCB && form.kenakan_sewa_armada_cb && Number(form.tarif_sewa_angkut || 0) <= 0) {
      showToast('Tarif sewa Armada CB untuk mitra ini belum diatur. Lengkapi tarif di menu Mitra.');
      setSaving(false);
      return;
    }

    if (isSelectedArmadaCB && form.catat_dana_operasional_trip && danaOperasionalTrip <= 0) {
      showToast('Dana Operasional Trip untuk mitra ini belum diatur. Lengkapi tarif di menu Mitra.');
      setSaving(false);
      return;
    }

    if (isSelectedArmadaCB && !form.kenakan_sewa_armada_cb && !form.alasan_tanpa_sewa_armada_cb.trim()) {
      showToast('Isi alasan mengapa sewa Armada CB tidak dipotong dari mitra.');
      setSaving(false);
      return;
    }

    if (isSelectedArmadaCB && !form.catat_dana_operasional_trip && !form.alasan_tanpa_dana_operasional_trip.trim()) {
      showToast('Isi alasan mengapa Dana Operasional Trip tidak dibuat.');
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

    const { error } = await supabase.rpc('save_transaksi_mitra_v2', {
      payload: {
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
        berat_netto_pabrik_kg:  k.beratNetto,
        potongan_pabrik_kg:     k.potongan,
        menggunakan_armada_cb_snapshot: isSelectedArmadaCB,
        kenakan_sewa_armada_cb: form.kenakan_sewa_armada_cb,
        catat_dana_operasional_trip: form.catat_dana_operasional_trip,
        alasan_tanpa_sewa_armada_cb: form.kenakan_sewa_armada_cb ? null : form.alasan_tanpa_sewa_armada_cb.trim(),
        alasan_tanpa_dana_operasional_trip: form.catat_dana_operasional_trip
          ? null
          : form.alasan_tanpa_dana_operasional_trip.trim()
      }
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
      if (onSuccess) onSuccess();
      setShowAdvanced(false);
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
        kenakan_sewa_armada_cb: false,
        catat_dana_operasional_trip: false,
        alasan_tanpa_sewa_armada_cb: '',
        alasan_tanpa_dana_operasional_trip: '',
        tarif_sewa_angkut: 0,
        dana_operasional_trip: 0,
      });
    }

    setSaving(false);
  }

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  const siapInput = Boolean(form.mitra_id && form.sopir_id);
  return (
    <Modal open={open} onClose={onClose} title="Tambah Pengiriman Mitra" maxWidth={640}>
      {toast && (
        <div className="toast-container" style={{ position: 'absolute', top: 16, right: 16 }}>
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      {successMsg && (
        <div style={{ background: 'var(--color-success-bg)', color: 'var(--color-success)', padding: 'var(--space-md)', borderRadius: 'var(--radius-md)', marginBottom: 'var(--space-lg)', fontWeight: 500 }}>
          ✅ {successMsg}
        </div>
      )}

      {showQuickAddArmada ? (
        <form onSubmit={handleSimpanArmadaCepat} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div style={{ background: 'var(--bg-surface)', padding: 16, borderRadius: 8, border: '1px solid var(--border-default)' }}>
            <h4 style={{ margin: '0 0 6px 0', fontSize: 16 }}>Tambah Sopir/Armada</h4>
            <p className="form-hint" style={{ marginBottom: 16 }}>Data langsung dapat dipakai dan akan masuk daftar Perlu Verifikasi Owner.</p>
            <div className="form-group">
              <label className="form-label form-label-required">Nama Sopir / Unit</label>
              <input
                className="form-input"
                required
                value={formArmadaCepat.nama}
                onChange={e => setFormArmadaCepat({ ...formArmadaCepat, nama: e.target.value })}
                placeholder="Contoh: Budi"
              />
            </div>
            <div className="form-grid">
              <div className="form-group">
                <label className="form-label">No. HP / WA</label>
                <input
                  className="form-input"
                  value={formArmadaCepat.no_hp}
                  onChange={e => setFormArmadaCepat({ ...formArmadaCepat, no_hp: e.target.value })}
                  placeholder="Opsional"
                />
              </div>
              <div className="form-group">
                <label className="form-label">Mitra Default</label>
                <SearchableCombobox
                  value={formArmadaCepat.mitra_id}
                  options={mitras}
                  onChange={mitraId => setFormArmadaCepat({ ...formArmadaCepat, mitra_id: mitraId })}
                  getOptionLabel={formatMitraLabel}
                  getSearchText={getMitraSearchText}
                  placeholder="Tanpa default"
                  emptyLabel="Mitra tidak ditemukan"
                />
              </div>
            </div>
            <div className="form-group">
              <label className="form-label form-label-required">Plat Nomor</label>
              <input
                className="form-input form-input-mono"
                required
                value={formArmadaCepat.plat_nomor}
                onChange={e => setFormArmadaCepat({ ...formArmadaCepat, plat_nomor: e.target.value.toUpperCase() })}
                placeholder="Contoh: BM 1234 XY"
              />
            </div>
            <div className="form-group">
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', fontSize: 14 }}>
                <input
                  type="checkbox"
                  checked={formArmadaCepat.is_armada_cb}
                  onChange={e => setFormArmadaCepat({ ...formArmadaCepat, is_armada_cb: e.target.checked })}
                />
                Ini adalah Armada Internal (CB)
              </label>
            </div>
            <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end', marginTop: 16 }}>
              <button type="button" className="btn btn-outline" onClick={() => setShowQuickAddArmada(false)}>Batal</button>
              <button type="submit" className="btn btn-primary" disabled={savingArmada}>
                {savingArmada ? 'Menyimpan...' : 'Simpan & Gunakan'}
              </button>
            </div>
          </div>
        </form>
      ) : (
        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          {/* Row 1: Tanggal & Sopir/Armada */}
          <div className="form-grid pengiriman-primary-grid">
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
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
                <label className="form-label form-label-required" style={{ marginBottom: 0 }}>Sopir / Armada</label>
                <button type="button" className="btn btn-ghost btn-sm" onClick={() => setShowQuickAddArmada(true)} style={{ padding: '0 8px', height: 24, fontSize: 12 }}>
                  + Sopir/Armada Baru
                </button>
              </div>
              <SearchableCombobox
                value={form.sopir_id}
                options={prioritizedSopirs}
                onChange={handleSopirChange}
                getOptionLabel={formatSopirArmadaLabel}
                getOptionDescription={formatSopirArmadaDescription}
                getSearchText={getSopirArmadaSearchText}
                placeholder="Cari plat nomor atau sopir..."
                emptyLabel="Tidak ditemukan. Klik '+ Sopir/Armada Baru' di atas."
                loading={loading}
                disabled={false}
              />
              {selectedDefaultSopir && (
                <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginTop: 8, flexWrap: 'wrap' }}>
                  <span className={`badge ${isSelectedArmadaCB ? 'badge-success' : 'badge-neutral'}`}>
                    {isSelectedArmadaCB ? 'Armada CB' : 'Armada Mitra'}
                  </span>
                  {!selectedDefaultSopir.mitra_id && (
                    <span className="text-tertiary text-xs">Tanpa mitra default</span>
                  )}
                </div>
              )}
            </div>
          </div>

        {/* Row 2: Mitra Transaksi */}
        <div className="form-group">
          <label className="form-label form-label-required">Mitra Transaksi</label>
          <SearchableCombobox
            value={form.mitra_id}
            options={mitras}
            onChange={handleMitraChange}
            getOptionLabel={formatMitraLabel}
            getSearchText={getMitraSearchText}
            placeholder="Otomatis terisi jika armada dipilih..."
            emptyLabel="Mitra tidak ditemukan"
            loading={loading}
          />
        </div>

        {/* Berat & Potongan */}
        <div className="form-grid">
          <div className="form-group">
            <label className="form-label form-label-required">Berat Netto Pabrik (kg)</label>
            <input
              type="number"
              className="form-input"
              style={{ fontSize: 24, fontWeight: 'bold', padding: 16, height: 'auto' }}
              required
              min={1}
              placeholder={siapInput ? '0' : selectedDefaultSopir ? 'Pilih mitra dulu' : 'Pilih armada dulu'}
              value={form.berat_netto}
              onChange={e => setForm({ ...form, berat_netto: e.target.value })}
              disabled={!siapInput}
            />
          </div>
          <div className="form-group">
            <label className="form-label">Potongan Pabrik (kg)</label>
            <input
              type="number"
              className="form-input"
              style={{ fontSize: 24, fontWeight: 'bold', padding: 16, height: 'auto' }}
              min={0}
              placeholder="0"
              value={form.potongan_pabrik}
              onChange={e => setForm({ ...form, potongan_pabrik: e.target.value })}
              disabled={!siapInput}
            />
          </div>
        </div>

        {isSelectedArmadaCB && (
          <div style={{ border: '1px solid var(--color-info)', borderRadius: 8, padding: 16 }}>
            <div style={{ fontWeight: 700, marginBottom: 4 }}>Perlakuan Armada CB</div>
            <div className="text-sm text-tertiary" style={{ marginBottom: 14 }}>
              Perjalanan tetap dihitung sebagai trip Armada CB. Pilih perlakuan uangnya untuk pengiriman ini.
            </div>

            <label style={{ display: 'flex', alignItems: 'flex-start', gap: 10, cursor: 'pointer', marginBottom: 12 }}>
              <input
                type="checkbox"
                checked={form.kenakan_sewa_armada_cb}
                onChange={event => setForm({
                  ...form,
                  kenakan_sewa_armada_cb: event.target.checked,
                  alasan_tanpa_sewa_armada_cb: event.target.checked ? '' : form.alasan_tanpa_sewa_armada_cb,
                })}
                style={{ marginTop: 3 }}
              />
              <span>
                <strong>Potong sewa dari pembayaran mitra</strong>
                <span className="text-sm text-tertiary" style={{ display: 'block' }}>
                  {formatRupiah(form.tarif_sewa_angkut)}/kg dari Berat Netto Pabrik
                </span>
              </span>
            </label>

            {!form.kenakan_sewa_armada_cb && (
              <div className="form-group" style={{ marginLeft: 26 }}>
                <label className="form-label form-label-required">Alasan tanpa potongan sewa</label>
                <input
                  className="form-input"
                  list="alasan-tanpa-sewa-armada"
                  required
                  value={form.alasan_tanpa_sewa_armada_cb}
                  onChange={event => setForm({ ...form, alasan_tanpa_sewa_armada_cb: event.target.value })}
                  placeholder="Pilih atau tulis alasan"
                />
                <datalist id="alasan-tanpa-sewa-armada">
                  <option value="Bantuan armada tanpa biaya sewa" />
                  <option value="Mitra internal, sewa tidak dipotong" />
                  <option value="Keputusan Owner" />
                </datalist>
              </div>
            )}

            <label style={{ display: 'flex', alignItems: 'flex-start', gap: 10, cursor: 'pointer' }}>
              <input
                type="checkbox"
                checked={form.catat_dana_operasional_trip}
                onChange={event => setForm({
                  ...form,
                  catat_dana_operasional_trip: event.target.checked,
                  alasan_tanpa_dana_operasional_trip: event.target.checked ? '' : form.alasan_tanpa_dana_operasional_trip,
                })}
                style={{ marginTop: 3 }}
              />
              <span>
                <strong>Dana Operasional Dibayar Mitra ke Sopir</strong>
                <span className="text-sm text-tertiary" style={{ display: 'block' }}>
                  {formatRupiah(form.dana_operasional_trip)} diserahkan sebelum armada berangkat
                </span>
              </span>
            </label>

            {!form.catat_dana_operasional_trip && (
              <div className="form-group" style={{ marginLeft: 26, marginTop: 12, marginBottom: 0 }}>
                <label className="form-label form-label-required">Alasan tanpa Dana Operasional Trip</label>
                <input
                  className="form-input"
                  list="alasan-tanpa-dana-trip"
                  required
                  value={form.alasan_tanpa_dana_operasional_trip}
                  onChange={event => setForm({ ...form, alasan_tanpa_dana_operasional_trip: event.target.value })}
                  placeholder="Pilih atau tulis alasan"
                />
                <datalist id="alasan-tanpa-dana-trip">
                  <option value="Dana dibayar di luar transaksi ini" />
                  <option value="Tidak ada Dana Operasional Trip" />
                  <option value="Keputusan Owner" />
                </datalist>
              </div>
            )}
          </div>
        )}

        {/* Advanced Options Accordion */}
        <div style={{ border: '1px solid var(--border-default)', borderRadius: 8, overflow: 'hidden' }}>
          <button
            type="button"
            onClick={() => setShowAdvanced(!showAdvanced)}
            style={{
              width: '100%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '12px 16px',
              background: 'var(--bg-surface)',
              border: 'none',
              cursor: 'pointer',
              fontWeight: 500,
              color: 'var(--text-secondary)'
            }}
          >
            <span>Opsi Lanjutan (Pergantian Sopir Aktual, Catatan)</span>
            {showAdvanced ? <ChevronDown size={18} /> : <ChevronRight size={18} />}
          </button>
          
          {showAdvanced && (
            <div style={{ padding: 16, borderTop: '1px solid var(--border-default)' }}>
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

              <div className="form-group">
                <label className="form-label">Catatan Pergantian Sopir</label>
                <input
                  className="form-input"
                  value={form.catatan_sopir}
                  onChange={e => setForm({ ...form, catatan_sopir: e.target.value })}
                  placeholder="Contoh: sopir default berhalangan"
                />
              </div>
            </div>
          )}
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
                <span style={{ color: 'var(--color-danger)', fontSize: 14 }}>Potongan Pabrik:</span>
                <span style={{ fontWeight: 600, color: 'var(--color-danger)' }}>- {potonganNum.toLocaleString('id-ID')} kg</span>
              </div>
            )}
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 12, borderBottom: '1px dashed var(--border-default)', paddingBottom: 8 }}>
              <span style={{ color: 'var(--text-primary)', fontSize: 14, fontWeight: 500 }}>Berat Bersih Dibayar:</span>
              <span style={{ fontWeight: 700 }}>{beratDibayarNum.toLocaleString('id-ID')} kg</span>
            </div>

            {/* Uang */}
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
              <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Hasil Kotor (Pabrik):</span>
              <span style={{ fontWeight: 600, textAlign: 'right' }}>
                {formatRupiah(kalkulasi.totalKotor)}
                <div style={{ fontSize: 12, color: 'var(--text-tertiary)', fontWeight: 400 }}>({formatRupiah(latestHarga)}/kg)</div>
              </span>
            </div>

            {kalkulasi.totalFeeOwner > 0 && (
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Potongan Fee Owner:</span>
                <span style={{ fontWeight: 600, color: 'var(--color-warning)', textAlign: 'right' }}>
                  - {formatRupiah(kalkulasi.totalFeeOwner)}
                  <div style={{ fontSize: 12, color: 'var(--text-tertiary)', fontWeight: 400 }}>({formatRupiah(form.mitra_fee)}/kg)</div>
                </span>
              </div>
            )}

            {kalkulasi.pakaiSewaArmada && (
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Sewa Armada Kotor:</span>
                <span style={{ fontWeight: 600, textAlign: 'right' }}>
                  {formatRupiah(kalkulasi.biayaSewaArmadaKotor)}
                  <div style={{ fontSize: 12, color: 'var(--text-tertiary)', fontWeight: 400 }}>
                    ({formatRupiah(form.tarif_sewa_angkut)}/kg netto)
                  </div>
                </span>
              </div>
            )}

            {isSelectedArmadaCB && form.catat_dana_operasional_trip && (
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Dana Dibayar Mitra ke Sopir:</span>
                <span style={{ fontWeight: 600, color: 'var(--color-info)', textAlign: 'right' }}>
                  - {formatRupiah(danaOperasionalTrip)}
                  <div style={{ fontSize: 12, color: 'var(--text-tertiary)', fontWeight: 400 }}>
                    Tidak keluar dari kas CB
                  </div>
                </span>
              </div>
            )}

            {kalkulasi.pakaiSewaArmada && (
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14, fontWeight: 700 }}>Potongan Akhir Sewa:</span>
                <span style={{ fontWeight: 700, color: 'var(--color-danger)', textAlign: 'right' }}>
                  - {formatRupiah(kalkulasi.biayaSewaArmadaTotal)}
                </span>
              </div>
            )}

            {isSelectedArmadaCB && !form.kenakan_sewa_armada_cb && (
              <div className="alert alert-warning" style={{ marginTop: 10, marginBottom: 0 }}>
                Trip Armada CB tercatat tanpa potongan sewa: {form.alasan_tanpa_sewa_armada_cb || 'alasan belum diisi'}.
              </div>
            )}

            {isSelectedArmadaCB && !form.catat_dana_operasional_trip && (
              <div className="alert alert-warning" style={{ marginTop: 10, marginBottom: 0 }}>
                Dana Operasional Trip tidak dibuat: {form.alasan_tanpa_dana_operasional_trip || 'alasan belum diisi'}.
              </div>
            )}

            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginTop: 12, borderTop: '1px solid var(--border-default)', paddingTop: 12 }}>
              <span style={{ color: 'var(--color-success)', fontSize: 16, fontWeight: 700 }}>Nilai Bersih Mitra:</span>
              <span style={{ fontWeight: 800, color: 'var(--color-success)', fontSize: 18, textAlign: 'right' }}>
                {formatRupiah(kalkulasi.totalBersihMitra)}
                <div style={{ fontSize: 13, fontWeight: 500 }}>
                  ({formatRupiah(kalkulasi.hargaBersih)}/kg bersih
                  {kalkulasi.pakaiSewaArmada ? ' dikurangi potongan akhir sewa' : ''})
                </div>
              </span>
            </div>
          </div>
        )}

        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 12, marginTop: 16 }}>
          <button type="button" className="btn btn-outline" onClick={onClose} disabled={saving}>
            Batal
          </button>
          <button
            type="submit"
            className="btn btn-primary"
            disabled={!siapInput || saving}
            style={{ minWidth: 160 }}
          >
            {saving ? 'Menyimpan...' : 'Simpan Transaksi'}
          </button>
        </div>
      </form>
      )}
    </Modal>
  );
}
