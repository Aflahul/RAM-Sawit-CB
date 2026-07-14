'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import ConfirmDialog from '@/components/ui/ConfirmDialog';
import PromptDialog from '@/components/ui/PromptDialog';
import { formatMitraLabel } from '@/lib/display-labels';
import { supabase } from '@/lib/supabase';
import { formatDateDisplay, formatRupiah, getTodayISO } from '@/lib/utils';
import { exportToExcel } from '@/lib/export';
import { X } from 'lucide-react';

const PARTY_TYPES = [
  { value: 'petani', label: 'Petani' },
  { value: 'mitra', label: 'Mitra' },
  { value: 'sopir', label: 'Sopir' },
  { value: 'karyawan', label: 'Karyawan' },
  { value: 'lainnya', label: 'Lainnya' },
];

const DEBIT_SOURCES = [
  { value: 'kasbon', label: 'Kasbon' },
  { value: 'panjar', label: 'Panjar' },
  { value: 'peminjaman', label: 'Peminjaman' },
  { value: 'uang_jalan', label: 'Uang Jalan' },
  { value: 'pupuk', label: 'Bon Pupuk' },
  { value: 'gaji', label: 'Gaji / Talangan' },
  { value: 'operasional', label: 'Operasional' },
  { value: 'lainnya', label: 'Lainnya' },
];

const CREDIT_SOURCES = [
  { value: 'bayar_tunai', label: 'Bayar Tunai' },
  { value: 'pelunasan_kas', label: 'Pelunasan Kas' },
  { value: 'potong_tbs', label: 'Potong TBS' },
  { value: 'potong_settlement', label: 'Potong Settlement' },
  { value: 'koreksi', label: 'Koreksi' },
  { value: 'lainnya', label: 'Lainnya' },
];

function hitungSaldoLedger(rows = []) {
  return rows.reduce((total, row) => {
    const jumlah = Number(row.jumlah || 0);
    return total + (row.tipe === 'debit' ? jumlah : -jumlah);
  }, 0);
}

function getLedgerLabel(row) {
  const labels = {
    kasbon: 'Kasbon',
    panjar: 'Panjar',
    peminjaman: 'Peminjaman',
    uang_jalan: 'Uang Jalan',
    pupuk: 'Bon Pupuk',
    gaji: 'Gaji / Talangan',
    operasional: 'Operasional',
    lainnya: 'Lainnya',
    bayar_tunai: 'Bayar Tunai',
    pelunasan_kas: 'Pelunasan Kas',
    potong_tbs: 'Potong TBS',
    potong_settlement: 'Potong Settlement',
    koreksi: 'Koreksi',
    reversal: 'Reversal',
  };

  return labels[row.sumber] || row.sumber || '-';
}

function getPartyTypeLabel(type) {
  return PARTY_TYPES.find((item) => item.value === type)?.label || type || '-';
}

function getPartyKey(type, id, manualName = '') {
  return `${type}:${id || manualName.trim().toLowerCase()}`;
}

function getPartyFromLedger(row) {
  if (row.pihak_type === 'petani') {
    return {
      key: getPartyKey('petani', row.petani_id),
      type: 'petani',
      id: row.petani_id,
      name: row.petani?.nama || 'Petani',
      contact: row.petani?.no_hp || '',
      batas: Number(row.petani?.batas_hutang || 0),
    };
  }

  if (row.pihak_type === 'mitra') {
    return {
      key: getPartyKey('mitra', row.master_mitra_id || row.mitra_id),
      type: 'mitra',
      id: row.master_mitra_id || row.mitra_id,
      name: row.master_mitra ? formatMitraLabel(row.master_mitra) : row.mitra?.nama || 'Mitra',
      contact: row.master_mitra?.no_hp || '',
      batas: 0,
    };
  }

  if (row.pihak_type === 'sopir') {
    const plat = row.sopir?.plat_nomor ? ` - ${row.sopir.plat_nomor}` : '';
    return {
      key: getPartyKey('sopir', row.sopir_id),
      type: 'sopir',
      id: row.sopir_id,
      name: `${row.sopir?.nama || 'Sopir'}${plat}`,
      contact: row.sopir?.no_hp || '',
      batas: 0,
    };
  }

  return {
    key: getPartyKey(row.pihak_type, null, row.pihak_nama_manual || ''),
    type: row.pihak_type,
    id: null,
    name: row.pihak_nama_manual || getPartyTypeLabel(row.pihak_type),
    contact: '',
    batas: 0,
  };
}

function getDefaultSource(type, tipe) {
  if (tipe === 'kredit') return 'bayar_tunai';
  if (type === 'mitra') return 'panjar';
  if (type === 'sopir') return 'uang_jalan';
  if (type === 'karyawan') return 'kasbon';
  return 'peminjaman';
}

export default function HutangPage() {
  const [petaniList, setPetaniList] = useState([]);
  const [mitraList, setMitraList] = useState([]);
  const [sopirList, setSopirList] = useState([]);
  const [ledgerAll, setLedgerAll] = useState([]);
  const [selectedParty, setSelectedParty] = useState(null);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState(null);
  const [limitConfirm, setLimitConfirm] = useState(null);
  const [cancelTarget, setCancelTarget] = useState(null);
  const [canceling, setCanceling] = useState(false);
  const [selector, setSelector] = useState({ type: 'petani', id: '', manualName: '' });
  const [form, setForm] = useState({
    pihak_type: 'petani',
    petani_id: '',
    master_mitra_id: '',
    sopir_id: '',
    pihak_nama_manual: '',
    tipe: 'debit',
    sumber: 'kasbon',
    jumlah: '',
    keterangan: '',
  });

  const loadData = useCallback(async () => {
    setLoading(true);

    const [
      { data: petani },
      { data: mitra },
      { data: sopir },
      { data: ledger, error: ledgerError },
    ] = await Promise.all([
      supabase.from('petani').select('*').eq('aktif', true).order('nama'),
      supabase.from('master_mitra').select('id, kode, nama, alamat, no_hp').eq('aktif', true).order('kode'),
      supabase.from('sopir').select('id, nama, no_hp, plat_nomor').eq('aktif', true).order('nama'),
      supabase
        .from('hutang_ledger')
        .select(`
          *,
          petani:petani_id(nama, no_hp, batas_hutang),
          master_mitra:master_mitra_id(kode, nama, alamat, no_hp),
          mitra:mitra_id(nama),
          sopir:sopir_id(nama, no_hp, plat_nomor)
        `)
        .neq('status', 'dibatalkan')
        .order('tanggal', { ascending: false })
        .order('created_at', { ascending: false }),
    ]);

    if (ledgerError) {
      setToast({ message: `Gagal membaca ledger hutang: ${ledgerError.message}`, type: 'error' });
    }

    setPetaniList(petani || []);
    setMitraList(mitra || []);
    setSopirList(sopir || []);
    setLedgerAll(ledger || []);
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  function showToast(message, type = 'error', timeout = 4000) {
    setToast({ message, type });
    setTimeout(() => setToast(null), timeout);
  }

  const summaryRows = useMemo(() => {
    const groups = {};

    ledgerAll.forEach((row) => {
      const party = getPartyFromLedger(row);
      if (!groups[party.key]) {
        groups[party.key] = { ...party, rows: [] };
      }
      groups[party.key].rows.push(row);
    });

    return Object.values(groups)
      .map((party) => ({
        ...party,
        saldo: Math.max(hitungSaldoLedger(party.rows), 0),
      }))
      .filter((party) => party.saldo > 0)
      .sort((a, b) => b.saldo - a.saldo);
  }, [ledgerAll]);

  const ledgerList = useMemo(() => {
    if (!selectedParty) return [];
    return ledgerAll.filter((row) => getPartyFromLedger(row).key === selectedParty.key);
  }, [ledgerAll, selectedParty]);

  const saldo = useMemo(() => Math.max(hitungSaldoLedger(ledgerList), 0), [ledgerList]);

  const selectorOptions = useMemo(() => {
    if (selector.type === 'petani') {
      return petaniList.map((item) => ({ value: item.id, label: item.nama }));
    }
    if (selector.type === 'mitra') {
      return mitraList.map((item) => ({ value: item.id, label: formatMitraLabel(item) }));
    }
    if (selector.type === 'sopir') {
      return sopirList.map((item) => ({
        value: item.id,
        label: `${item.nama}${item.plat_nomor ? ` - ${item.plat_nomor}` : ''}`,
      }));
    }
    return [];
  }, [mitraList, petaniList, selector.type, sopirList]);

  function applySelectedParty(party) {
    setSelectedParty(party);
  }

  function selectFromControl(nextSelector = selector) {
    const { type, id, manualName } = nextSelector;
    if (['petani', 'mitra', 'sopir'].includes(type) && !id) {
      setSelectedParty(null);
      return;
    }

    let party = null;
    if (type === 'petani') {
      const item = petaniList.find((row) => row.id === id);
      party = item ? {
        key: getPartyKey('petani', item.id),
        type: 'petani',
        id: item.id,
        name: item.nama,
        contact: item.no_hp || '',
        batas: Number(item.batas_hutang || 0),
      } : null;
    } else if (type === 'mitra') {
      const item = mitraList.find((row) => row.id === id);
      party = item ? {
        key: getPartyKey('mitra', item.id),
        type: 'mitra',
        id: item.id,
        name: formatMitraLabel(item),
        contact: item.no_hp || '',
        batas: 0,
      } : null;
    } else if (type === 'sopir') {
      const item = sopirList.find((row) => row.id === id);
      party = item ? {
        key: getPartyKey('sopir', item.id),
        type: 'sopir',
        id: item.id,
        name: `${item.nama}${item.plat_nomor ? ` - ${item.plat_nomor}` : ''}`,
        contact: item.no_hp || '',
        batas: 0,
      } : null;
    } else if (manualName.trim()) {
      party = {
        key: getPartyKey(type, null, manualName),
        type,
        id: null,
        name: manualName.trim(),
        contact: '',
        batas: 0,
      };
    }

    if (!party) return;
    applySelectedParty(party);
  }

  function openModal(tipe = 'debit') {
    const party = selectedParty;
    const pihakType = party?.type || selector.type;
    setForm({
      pihak_type: pihakType,
      petani_id: pihakType === 'petani' ? party?.id || selector.id : '',
      master_mitra_id: pihakType === 'mitra' ? party?.id || selector.id : '',
      sopir_id: pihakType === 'sopir' ? party?.id || selector.id : '',
      pihak_nama_manual: ['karyawan', 'lainnya'].includes(pihakType) ? party?.name || selector.manualName : '',
      tipe,
      sumber: getDefaultSource(pihakType, tipe),
      jumlah: '',
      keterangan: '',
    });
    setShowModal(true);
  }

  async function saveLedger({ bypassLimit = false } = {}) {
    const jumlah = Number(form.jumlah);
    if (!jumlah || jumlah <= 0) return;

    if (!bypassLimit && form.tipe === 'debit' && selectedParty?.batas > 0 && (saldo + jumlah) > selectedParty.batas) {
      setLimitConfirm({
        jumlah,
        saldo,
        batas: selectedParty.batas,
        total: saldo + jumlah,
      });
      return;
    }

    setSaving(true);
    const isMitraPanjar = form.pihak_type === 'mitra' && form.tipe === 'debit' && form.sumber === 'panjar';
    const { error } = isMitraPanjar
      ? await supabase.rpc('create_panjar_mitra_kas', {
        p_mitra_id: form.master_mitra_id || null,
        p_tanggal: getTodayISO(),
        p_jumlah: jumlah,
        p_keterangan: form.keterangan || null,
        p_rekening_kas_id: null,
      })
      : await supabase.rpc('create_hutang_pihak', {
        p_pihak_type: form.pihak_type,
        p_tipe: form.tipe,
        p_sumber: form.sumber,
        p_jumlah: jumlah,
        p_tanggal: getTodayISO(),
        p_petani_id: form.pihak_type === 'petani' ? form.petani_id || null : null,
        p_master_mitra_id: form.pihak_type === 'mitra' ? form.master_mitra_id || null : null,
        p_sopir_id: form.pihak_type === 'sopir' ? form.sopir_id || null : null,
        p_pihak_nama_manual: ['karyawan', 'lainnya'].includes(form.pihak_type) ? form.pihak_nama_manual || null : null,
        p_keterangan: form.keterangan || null,
        p_rekening_kas_id: null,
        p_catat_kas: true,
        p_legacy_source_table: null,
        p_legacy_source_id: null,
      });
    setSaving(false);

    if (error) {
      showToast(`Gagal menyimpan hutang/panjar: ${error.message}`, 'error', 5000);
      return;
    }

    setShowModal(false);
    showToast(isMitraPanjar ? 'Panjar mitra berhasil dicatat dan siap dipotong di kwitansi.' : 'Hutang/panjar berhasil dicatat.', 'success', 3000);
    await loadData();
  }

  async function handleSave(e) {
    e.preventDefault();
    await saveLedger();
  }

  async function handleConfirmLimit() {
    setLimitConfirm(null);
    await saveLedger({ bypassLimit: true });
  }

  async function handleCancelLedger(reason) {
    if (!cancelTarget || canceling) return;

    setCanceling(true);
    const { error } = await supabase.rpc('cancel_hutang_ledger', {
      p_hutang_ledger_id: cancelTarget.id,
      p_alasan: reason.trim(),
    });
    setCanceling(false);

    if (error) {
      showToast(`Gagal membatalkan hutang: ${error.message}`, 'error', 5000);
      return;
    }

    setCancelTarget(null);
    showToast('Hutang/panjar berhasil dibatalkan dengan reversal.', 'success', 3000);
    await loadData();
  }

  function exportHutang() {
    const data = summaryRows.map((party) => ({
      tipe: getPartyTypeLabel(party.type),
      nama: party.name,
      kontak: party.contact || '-',
      saldo: party.saldo,
      batas: party.batas || 0,
    }));

    exportToExcel(data, [
      { key: 'tipe', label: 'Tipe Pihak' },
      { key: 'nama', label: 'Nama Pihak' },
      { key: 'kontak', label: 'Kontak' },
      { key: 'saldo', label: 'Sisa Hutang/Panjar' },
      { key: 'batas', label: 'Batas Panjar' },
    ], 'Daftar_Hutang_Panjar', 'Sisa Hutang Panjar');
  }

  return (
    <AppShell title="Hutang & Panjar Semua Pihak" subtitle="Kelola sisa hutang, kasbon, dan panjar lintas petani, mitra, sopir, karyawan, dan pihak lain">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <div>
          <p className="page-description">Panjar adalah kasbon/uang muka yang akan dipotong saat pembayaran berikutnya. Untuk panjar mitra, pilih pihak Mitra dan jenis Panjar.</p>
        </div>
        <div className="flex gap-sm" style={{ flexWrap: 'wrap' }}>
          <button className="btn btn-outline btn-sm" onClick={exportHutang}>Export Excel</button>
          <button className="btn btn-primary btn-sm" onClick={() => openModal('debit')}>Catat Hutang & Panjar</button>
        </div>
      </div>

      <div className="toolbar">
        <select
          className="form-input form-select"
          value={selector.type}
          onChange={(e) => {
            const next = { type: e.target.value, id: '', manualName: '' };
            setSelector(next);
            setSelectedParty(null);
          }}
          style={{ maxWidth: 180 }}
        >
          {PARTY_TYPES.map((type) => <option key={type.value} value={type.value}>{type.label}</option>)}
        </select>

        {['petani', 'mitra', 'sopir'].includes(selector.type) ? (
          <select
            className="form-input form-select"
            value={selector.id}
            onChange={(e) => {
              const next = { ...selector, id: e.target.value };
              setSelector(next);
              if (e.target.value) selectFromControl(next);
            }}
          >
            <option value="">-- Pilih {getPartyTypeLabel(selector.type)} --</option>
            {selectorOptions.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}
          </select>
        ) : (
          <input
            className="form-input"
            value={selector.manualName}
            onChange={(e) => setSelector({ ...selector, manualName: e.target.value })}
            onBlur={() => selectFromControl({ ...selector })}
            placeholder={`Nama ${getPartyTypeLabel(selector.type).toLowerCase()}...`}
          />
        )}
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: selectedParty ? 'minmax(260px, 0.9fr) minmax(0, 1.5fr)' : '1fr', gap: 'var(--space-xl)' }}>
        <div className="card">
          <div className="card-header">
            <span className="card-title">Pihak dengan Sisa Hutang/Panjar</span>
            <span className="badge badge-warning">{summaryRows.length}</span>
          </div>
          {loading ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[1, 2, 3].map((item) => <div key={item} className="skeleton" style={{ height: 44 }} />)}
            </div>
          ) : summaryRows.length === 0 ? (
            <div className="empty-state" style={{ padding: 'var(--space-lg)' }}>
              <div className="empty-state-title">Tidak ada hutang aktif</div>
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              {summaryRows.map((party) => (
                <button
                  key={party.key}
                  onClick={() => applySelectedParty(party)}
                  className="btn btn-ghost"
                  style={{
                    justifyContent: 'space-between',
                    background: selectedParty?.key === party.key ? 'var(--color-primary-700)' : 'transparent',
                  }}
                >
                  <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 2 }}>
                    <span style={{ fontWeight: 700 }}>{party.name}</span>
                    <span className="text-tertiary text-xs">{getPartyTypeLabel(party.type)}</span>
                  </span>
                  <span className="text-mono text-warning" style={{ fontWeight: 700 }}>{formatRupiah(party.saldo)}</span>
                </button>
              ))}
            </div>
          )}
        </div>

        {selectedParty && (
          <div>
            <div className="card" style={{ marginBottom: 'var(--space-lg)' }}>
              <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-md)', gap: 12, flexWrap: 'wrap' }}>
                <div>
                  <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>{selectedParty.name}</h3>
                  <p className="text-tertiary text-sm">{getPartyTypeLabel(selectedParty.type)}{selectedParty.contact ? ` / ${selectedParty.contact}` : ''}</p>
                </div>
                <div className="flex gap-sm" style={{ flexWrap: 'wrap' }}>
                  <button className="btn btn-primary btn-sm" onClick={() => openModal('debit')}>Tambah</button>
                  <button className="btn btn-outline btn-sm" onClick={() => openModal('kredit')}>Bayar</button>
                </div>
              </div>

              <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))' }}>
                <div style={{ textAlign: 'center', padding: 'var(--space-md)', background: 'var(--bg-surface)', borderRadius: 'var(--radius-md)' }}>
                  <div className="text-mono" style={{ fontSize: 'var(--text-2xl)', fontWeight: 700, color: saldo > 0 ? 'var(--color-warning)' : 'var(--color-success)' }}>
                    {formatRupiah(saldo)}
                  </div>
                  <div className="text-tertiary text-sm">Sisa Hutang/Panjar</div>
                </div>
                {selectedParty.batas > 0 && (
                  <div style={{ textAlign: 'center', padding: 'var(--space-md)', background: 'var(--bg-surface)', borderRadius: 'var(--radius-md)' }}>
                    <div className="text-mono" style={{ fontSize: 'var(--text-2xl)', fontWeight: 700 }}>
                      {formatRupiah(selectedParty.batas)}
                    </div>
                    <div className="text-tertiary text-sm">Batas Maksimal</div>
                  </div>
                )}
              </div>
            </div>

            <div className="card">
              <div className="card-header">
                <span className="card-title">Riwayat Hutang dan Pembayaran</span>
              </div>
              {ledgerList.length === 0 ? (
                <div className="empty-state" style={{ padding: 'var(--space-lg)' }}>
                  <div className="empty-state-title">Belum ada riwayat</div>
                </div>
              ) : (
                <div className="table-container" style={{ border: 'none' }}>
                  <table className="table">
                    <thead>
                      <tr>
                        <th>Tanggal</th>
                        <th>Keterangan</th>
                        <th style={{ textAlign: 'right' }}>Debit</th>
                        <th style={{ textAlign: 'right' }}>Kredit</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      {ledgerList.map((item) => (
                        <tr key={item.id}>
                          <td>{formatDateDisplay(item.tanggal)}</td>
                          <td>
                            <span className={`badge ${item.tipe === 'debit' ? 'badge-danger' : 'badge-success'}`}>
                              {getLedgerLabel(item)}
                            </span>
                            {' '}{item.keterangan || ''}
                            {item.status === 'reversal' && <span className="text-tertiary"> / reversal</span>}
                          </td>
                          <td className="table-mono text-danger" style={{ textAlign: 'right' }}>
                            {item.tipe === 'debit' ? formatRupiah(item.jumlah) : ''}
                          </td>
                          <td className="table-mono text-success" style={{ textAlign: 'right' }}>
                            {item.tipe === 'kredit' ? formatRupiah(item.jumlah) : ''}
                          </td>
                          <td style={{ textAlign: 'right' }}>
                            {item.status === 'aktif' && (
                              <button className="btn btn-ghost btn-sm" onClick={() => setCancelTarget(item)}>Batalkan</button>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">{form.tipe === 'debit' ? 'Tambah Hutang & Panjar' : 'Catat Pembayaran'}</h3>
              <button className="modal-close" onClick={() => setShowModal(false)} aria-label="Tutup">
                <X size={18} />
              </button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Tipe Pihak</label>
                    <select
                      className="form-input form-select"
                      value={form.pihak_type}
                      onChange={(e) => {
                        const pihakType = e.target.value;
                        setForm({
                          ...form,
                          pihak_type: pihakType,
                          petani_id: '',
                          master_mitra_id: '',
                          sopir_id: '',
                          pihak_nama_manual: '',
                          sumber: getDefaultSource(pihakType, form.tipe),
                        });
                      }}
                    >
                      {PARTY_TYPES.map((type) => <option key={type.value} value={type.value}>{type.label}</option>)}
                    </select>
                  </div>

                  <div className="form-group">
                    <label className="form-label form-label-required">Tanggal</label>
                    <input className="form-input" type="date" value={getTodayISO()} readOnly />
                  </div>
                </div>

                {form.pihak_type === 'petani' && (
                  <div className="form-group">
                    <label className="form-label form-label-required">Petani</label>
                    <select className="form-input form-select" value={form.petani_id} onChange={(e) => setForm({ ...form, petani_id: e.target.value })} required>
                      <option value="">-- Pilih Petani --</option>
                      {petaniList.map((item) => <option key={item.id} value={item.id}>{item.nama}</option>)}
                    </select>
                  </div>
                )}

                {form.pihak_type === 'mitra' && (
                  <div className="form-group">
                    <label className="form-label form-label-required">Mitra</label>
                    <select className="form-input form-select" value={form.master_mitra_id} onChange={(e) => setForm({ ...form, master_mitra_id: e.target.value })} required>
                      <option value="">-- Pilih Mitra --</option>
                      {mitraList.map((item) => <option key={item.id} value={item.id}>{formatMitraLabel(item)}</option>)}
                    </select>
                  </div>
                )}

                {form.pihak_type === 'sopir' && (
                  <div className="form-group">
                    <label className="form-label form-label-required">Sopir</label>
                    <select className="form-input form-select" value={form.sopir_id} onChange={(e) => setForm({ ...form, sopir_id: e.target.value })} required>
                      <option value="">-- Pilih Sopir --</option>
                      {sopirList.map((item) => (
                        <option key={item.id} value={item.id}>{item.nama}{item.plat_nomor ? ` - ${item.plat_nomor}` : ''}</option>
                      ))}
                    </select>
                  </div>
                )}

                {['karyawan', 'lainnya'].includes(form.pihak_type) && (
                  <div className="form-group">
                    <label className="form-label form-label-required">Nama Pihak</label>
                    <input
                      className="form-input"
                      value={form.pihak_nama_manual}
                      onChange={(e) => setForm({ ...form, pihak_nama_manual: e.target.value })}
                      placeholder="Contoh: Irfandi / Karyawan panen / Bengkel"
                      required
                    />
                  </div>
                )}

                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Aksi</label>
                    <select
                      className="form-input form-select"
                      value={form.tipe}
                      onChange={(e) => {
                        const tipe = e.target.value;
                        setForm({ ...form, tipe, sumber: getDefaultSource(form.pihak_type, tipe) });
                      }}
                    >
                      <option value="debit">Tambah hutang / uang keluar</option>
                      <option value="kredit">Pembayaran / uang masuk</option>
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label form-label-required">Jenis</label>
                    <select className="form-input form-select" value={form.sumber} onChange={(e) => setForm({ ...form, sumber: e.target.value })}>
                      {(form.tipe === 'debit' ? DEBIT_SOURCES : CREDIT_SOURCES).map((item) => (
                        <option key={item.value} value={item.value}>{item.label}</option>
                      ))}
                    </select>
                    {form.pihak_type === 'mitra' && form.tipe === 'debit' && form.sumber === 'panjar' && (
                      <div className="form-hint">Panjar mitra ini akan muncul sebagai potongan saat membuat Kwitansi Mitra.</div>
                    )}
                  </div>
                </div>

                <div className="form-group">
                  <label className="form-label form-label-required">Jumlah (Rp)</label>
                  <input
                    type="number"
                    className="form-input form-input-mono"
                    value={form.jumlah}
                    onChange={(e) => setForm({ ...form, jumlah: e.target.value })}
                    min={1}
                    required
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Keterangan</label>
                  <input
                    className="form-input"
                    value={form.keterangan}
                    onChange={(e) => setForm({ ...form, keterangan: e.target.value })}
                    placeholder="Opsional"
                  />
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

      <ConfirmDialog
        open={!!limitConfirm}
        title="Batas Hutang Terlewati"
        message={limitConfirm ? `Sisa sekarang ${formatRupiah(limitConfirm.saldo)}, tambahan ${formatRupiah(limitConfirm.jumlah)}, total menjadi ${formatRupiah(limitConfirm.total)}. Batas pihak ini ${formatRupiah(limitConfirm.batas)}.` : ''}
        confirmText="Tetap Simpan"
        cancelText="Cek Lagi"
        variant="warning"
        onConfirm={handleConfirmLimit}
        onCancel={() => setLimitConfirm(null)}
      />

      <PromptDialog
        open={!!cancelTarget}
        title="Batalkan Catatan"
        message={cancelTarget ? `${getLedgerLabel(cancelTarget)} ${formatRupiah(cancelTarget.jumlah)} akan dibatalkan dan dibuat catatan balik.` : ''}
        label="Alasan pembatalan"
        placeholder="Contoh: salah input / duplikat / sudah diganti catatan baru"
        confirmText="Batalkan Catatan"
        cancelText="Kembali"
        variant="danger"
        loading={canceling}
        onConfirm={handleCancelLedger}
        onCancel={() => !canceling && setCancelTarget(null)}
      />
    </AppShell>
  );
}
