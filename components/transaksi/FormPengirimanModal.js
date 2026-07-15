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
    pakai_sewa_armada_cb: false,
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
  const danaOperasionalTrip = isSelectedArmadaCB
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

    const pakaiSewaArmada = form.pakai_sewa_armada_cb;
    const isSewa = hitungSewaArmadaCB({ 
      isArmadaCB: pakaiSewaArmada, 
      beratNettoPabrikKg: beratNetto,
      tarifSewaAngkut: form.tarif_sewa_angkut,
    });
    const sewaArmada = {
      pakaiSewaArmada: isSewa.pakaiSewaArmada,
      biayaSewaArmadaKotor: isSewa.biayaSewaArmadaKotor,
      biayaSewaArmadaTotal: isSewa.biayaSewaArmadaTotal,
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
  }, [form.berat_netto, form.potongan_pabrik, form.mitra_fee, form.pakai_sewa_armada_cb, form.tarif_sewa_angkut, latestHarga]);

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
        pakai_sewa_armada_cb: false,
      });
      return;
    }

    const sopir = sopirs.find(s => s.id === selectedId);
    if (sopir) {
      const nextMitraId = form.mitra_id || sopir.mitra_id || '';
      
      const isCb = Boolean(sopir.is_armada_cb);
      const autoSewa = hitungSewaArmadaCB({ isArmadaCB: isCb, beratNettoPabrikKg: 0 }).pakaiSewaArmada;

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
        pakai_sewa_armada_cb: autoSewa,
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
    const sopir = sopirs.find(s => s.id === form.sopir_id);
    const isCb = Boolean(sopir?.is_armada_cb);
    const autoSewa = hitungSewaArmadaCB({ isArmadaCB: isCb, beratNettoPabrikKg: 0 }).pakaiSewaArmada;

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
  // Quick Add Armada
  // ---------------------------------------------------------------------------

  async function handleSimpanArmadaCepat(e) {
    e.preventDefault();
    if (!formArmadaCepat.nama.trim() || !formArmadaCepat.plat_nomor.trim()) {
      showToast('Nama Sopir dan Plat Nomor wajib diisi.');
      return;
    }
    setSavingArmada(true);

    const payload = {
      nama: formArmadaCepat.nama.trim(),
      plat_nomor: formArmadaCepat.plat_nomor.toUpperCase().trim(),
      is_armada_cb: formArmadaCepat.is_armada_cb,
    };

    const { data, error } = await supabase.from('sopir').insert(payload).select().single();

    if (error) {
      showToast(`Gagal menyimpan armada: ${error.message}`);
      setSavingArmada(false);
      return;
    }

    setSopirs(prev => [...prev, data]);
    
    setForm({
      ...form,
      sopir_id: data.id,
      plat_nomor: data.plat_nomor || '-',
      mitra_id: '',
      sopir_default_nama: data.nama,
      sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
      sopir_aktual_id: data.id,
      sopir_aktual_nama: data.nama,
      sopir_aktual_no_hp: '',
      catatan_sopir: '',
      pakai_sewa_armada_cb: Boolean(data.is_armada_cb),
    });

    setFormArmadaCepat({ nama: '', plat_nomor: '', is_armada_cb: false });
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

    if (isSelectedArmadaCB && Number(form.tarif_sewa_angkut || 0) <= 0) {
      showToast('Tarif sewa Armada CB untuk mitra ini belum diatur. Lengkapi tarif di menu Mitra.');
      setSaving(false);
      return;
    }

    if (isSelectedArmadaCB && danaOperasionalTrip <= 0) {
      showToast('Dana Operasional Trip untuk mitra ini belum diatur. Lengkapi tarif di menu Mitra.');
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
      tarif_sewa_angkut_per_kg_snapshot: form.pakai_sewa_armada_cb ? form.tarif_sewa_angkut : 0,
      nominal_perongkosan_snapshot:      0,
      biaya_sewa_armada_kotor:           form.pakai_sewa_armada_cb ? k.biayaSewaArmadaKotor : 0,
      biaya_sewa_armada_total:           form.pakai_sewa_armada_cb ? k.biayaSewaArmadaTotal : 0,

      // Satu dana per trip; rinciannya dikelola sopir di luar sistem.
      dana_operasional_trip_snapshot:      danaOperasionalTrip,
      upah_sopir_cb_snapshot:              0,
      uang_jalan_sopir_cb_snapshot:        0,
      total_biaya_sopir_cb_snapshot:       danaOperasionalTrip,
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
        pakai_sewa_armada_cb: false,
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
            <h4 style={{ margin: '0 0 16px 0', fontSize: 16 }}>Tambah Armada Baru</h4>
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
                {savingArmada ? 'Menyimpan...' : 'Simpan Armada'}
              </button>
            </div>
          </div>
        </form>
      ) : (
        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          {/* Row 1: Tanggal & Sopir/Armada */}
          <div className="form-grid" style={{ gridTemplateColumns: '1fr 2fr' }}>
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
                  + Armada Baru
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
                emptyLabel="Tidak ditemukan. Klik '+ Armada Baru' di atas."
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
              placeholder={siapInput ? '0' : 'Pilih armada/mitra dulu'}
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
          <div className="alert alert-info" style={{ marginBottom: 0 }}>
            <strong>Armada CB</strong>
            <div className="text-sm" style={{ marginTop: 4 }}>
              Sewa {formatRupiah(form.tarif_sewa_angkut)}/kg netto
              {' | '}Dana operasional trip {formatRupiah(danaOperasionalTrip)}
            </div>
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
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Sewa Armada CB:</span>
                <span style={{ fontWeight: 600, color: 'var(--color-danger)', textAlign: 'right' }}>
                  - {formatRupiah(kalkulasi.biayaSewaArmadaTotal)}
                  <div style={{ fontSize: 12, color: 'var(--text-tertiary)', fontWeight: 400 }}>
                    ({formatRupiah(form.tarif_sewa_angkut)}/kg netto)
                  </div>
                </span>
              </div>
            )}

            {isSelectedArmadaCB && (
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginBottom: 6 }}>
                <span style={{ color: 'var(--text-tertiary)', fontSize: 14 }}>Dana Operasional Trip:</span>
                <span style={{ fontWeight: 600, textAlign: 'right' }}>
                  {formatRupiah(danaOperasionalTrip)}
                  <div style={{ fontSize: 12, color: 'var(--text-tertiary)', fontWeight: 400 }}>
                    Dibayar satu kali jalan; sudah termasuk solar, makan, dan bagian sopir
                  </div>
                </span>
              </div>
            )}

            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, marginTop: 12, borderTop: '1px solid var(--border-default)', paddingTop: 12 }}>
              <span style={{ color: 'var(--color-success)', fontSize: 16, fontWeight: 700 }}>Nilai Bersih Mitra:</span>
              <span style={{ fontWeight: 800, color: 'var(--color-success)', fontSize: 18, textAlign: 'right' }}>
                {formatRupiah(kalkulasi.totalBersihMitra)}
                <div style={{ fontSize: 13, fontWeight: 500 }}>
                  ({formatRupiah(kalkulasi.hargaBersih)}/kg bersih
                  {kalkulasi.pakaiSewaArmada ? ' dipotong armada' : ''})
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
