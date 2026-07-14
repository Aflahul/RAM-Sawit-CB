'use client';

import { useCallback, useEffect, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatDateDisplay, formatRupiah, getTodayISO } from '@/lib/utils';
import { exportToExcel } from '@/lib/export';

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
    pupuk: 'Bon Pupuk',
    lainnya: 'Lainnya',
    bayar_tunai: 'Bayar Tunai',
    potong_tbs: 'Potong TBS',
    koreksi: 'Koreksi',
    reversal: 'Reversal',
  };

  return labels[row.sumber] || row.sumber || '-';
}

export default function HutangPage() {
  const [petaniList, setPetaniList] = useState([]);
  const [selectedPetani, setSelectedPetani] = useState(null);
  const [ledgerList, setLedgerList] = useState([]);
  const [saldo, setSaldo] = useState(0);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState(null);
  const [petaniSummary, setPetaniSummary] = useState([]);

  const [form, setForm] = useState({
    jenis: 'kasbon',
    jumlah: '',
    keterangan: '',
  });

  const loadData = useCallback(async () => {
    setLoading(true);

    const [{ data: petani }, { data: ledger, error: ledgerError }] = await Promise.all([
      supabase.from('petani').select('*').eq('aktif', true).order('nama'),
      supabase
        .from('hutang_ledger')
        .select('petani_id, tipe, jumlah')
        .eq('pihak_type', 'petani'),
    ]);

    if (ledgerError) {
      setToast({ message: `Gagal membaca ledger hutang: ${ledgerError.message}`, type: 'error' });
    }

    const summary = {};
    (ledger || []).forEach((row) => {
      if (!summary[row.petani_id]) summary[row.petani_id] = [];
      summary[row.petani_id].push(row);
    });

    const summaryArr = (petani || [])
      .map((item) => ({
        ...item,
        saldo: Math.max(hitungSaldoLedger(summary[item.id] || []), 0),
      }))
      .filter((item) => item.saldo > 0)
      .sort((a, b) => b.saldo - a.saldo);

    setPetaniList(petani || []);
    setPetaniSummary(summaryArr);
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  async function selectPetani(petaniId) {
    const petani = petaniList.find((item) => item.id === petaniId);
    setSelectedPetani(petani || null);

    const { data, error } = await supabase
      .from('hutang_ledger')
      .select('*')
      .eq('pihak_type', 'petani')
      .eq('petani_id', petaniId)
      .order('created_at', { ascending: false });

    if (error) {
      setToast({ message: `Gagal membaca riwayat hutang: ${error.message}`, type: 'error' });
      setLedgerList([]);
      setSaldo(0);
      return;
    }

    const rows = data || [];
    setLedgerList(rows);
    setSaldo(Math.max(hitungSaldoLedger(rows), 0));
  }

  async function handleTambahHutang(e) {
    e.preventDefault();
    if (!selectedPetani) return;

    const jumlah = Number(form.jumlah);
    if (!jumlah || jumlah <= 0) return;

    setSaving(true);
    const { data: { session } } = await supabase.auth.getSession();

    if (selectedPetani.batas_hutang > 0 && (saldo + jumlah) > selectedPetani.batas_hutang) {
      const lanjut = window.confirm(
        `Hutang akan melebihi batas ${formatRupiah(selectedPetani.batas_hutang)}.\n\n` +
        `Saldo saat ini: ${formatRupiah(saldo)}\n` +
        `Tambahan: ${formatRupiah(jumlah)}\n` +
        `Total: ${formatRupiah(saldo + jumlah)}\n\n` +
        'Lanjutkan?'
      );

      if (!lanjut) {
        setSaving(false);
        return;
      }
    }

    const { error } = await supabase.from('hutang_ledger').insert({
      pihak_type: 'petani',
      petani_id: selectedPetani.id,
      tanggal: getTodayISO(),
      tipe: 'debit',
      sumber: form.jenis,
      jumlah,
      keterangan: form.keterangan || null,
      created_by: session?.user?.id || null,
    });

    setSaving(false);

    if (error) {
      setToast({ message: `Gagal menambah hutang: ${error.message}`, type: 'error' });
      return;
    }

    setShowModal(false);
    setForm({ jenis: 'kasbon', jumlah: '', keterangan: '' });
    setToast({ message: 'Hutang berhasil ditambahkan.', type: 'success' });
    setTimeout(() => setToast(null), 3000);

    await selectPetani(selectedPetani.id);
    await loadData();
  }

  async function handleBayarTunai() {
    if (!selectedPetani) return;

    const jumlah = window.prompt('Masukkan jumlah pembayaran tunai (Rp):');
    const jumlahNumber = Number(jumlah);
    if (!jumlahNumber || jumlahNumber <= 0) return;

    const { data: { session } } = await supabase.auth.getSession();
    const { error } = await supabase.from('hutang_ledger').insert({
      pihak_type: 'petani',
      petani_id: selectedPetani.id,
      tanggal: getTodayISO(),
      tipe: 'kredit',
      sumber: 'bayar_tunai',
      jumlah: jumlahNumber,
      keterangan: 'Pembayaran tunai',
      created_by: session?.user?.id || null,
    });

    if (error) {
      setToast({ message: `Gagal mencatat pembayaran: ${error.message}`, type: 'error' });
      return;
    }

    setToast({ message: 'Pembayaran berhasil dicatat.', type: 'success' });
    setTimeout(() => setToast(null), 3000);
    await selectPetani(selectedPetani.id);
    await loadData();
  }

  function exportHutang() {
    const data = petaniSummary.map((petani) => ({
      nama: petani.nama,
      no_hp: petani.no_hp || '-',
      saldo: petani.saldo,
      batas: petani.batas_hutang || 0,
    }));

    exportToExcel(data, [
      { key: 'nama', label: 'Nama Petani' },
      { key: 'no_hp', label: 'No HP' },
      { key: 'saldo', label: 'Saldo Hutang' },
      { key: 'batas', label: 'Batas Hutang' },
    ], 'Daftar_Hutang_Petani', 'Hutang');
  }

  return (
    <AppShell title="Hutang Petani" subtitle="Kelola kasbon, panjar, dan hutang petani lokal">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header" style={{ justifyContent: 'flex-end' }}>
        <button className="btn btn-outline btn-sm" onClick={exportHutang}>Export Excel</button>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: selectedPetani ? '1fr 1.5fr' : '1fr', gap: 'var(--space-xl)' }}>
        <div>
          <div className="form-group">
            <select className="form-input form-select" onChange={(e) => e.target.value && selectPetani(e.target.value)} defaultValue="">
              <option value="">-- Pilih Petani --</option>
              {petaniList.map((petani) => <option key={petani.id} value={petani.id}>{petani.nama}</option>)}
            </select>
          </div>

          <div className="card">
            <div className="card-header">
              <span className="card-title">Petani dengan Hutang Aktif</span>
              <span className="badge badge-warning">{petaniSummary.length}</span>
            </div>
            {loading ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {[1, 2, 3].map((item) => <div key={item} className="skeleton" style={{ height: 44 }} />)}
              </div>
            ) : petaniSummary.length === 0 ? (
              <div className="empty-state" style={{ padding: 'var(--space-lg)' }}>
                <div className="empty-state-title">Tidak ada hutang aktif</div>
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                {petaniSummary.map((petani) => (
                  <div
                    key={petani.id}
                    onClick={() => selectPetani(petani.id)}
                    className="flex items-center justify-between"
                    style={{
                      padding: '10px 12px',
                      borderRadius: 'var(--radius-md)',
                      cursor: 'pointer',
                      background: selectedPetani?.id === petani.id ? 'var(--color-primary-700)' : 'transparent',
                      transition: 'background var(--transition-fast)',
                    }}
                  >
                    <span style={{ fontWeight: 500 }}>{petani.nama}</span>
                    <span className="text-mono text-warning" style={{ fontWeight: 600 }}>{formatRupiah(petani.saldo)}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {selectedPetani && (
          <div>
            <div className="card" style={{ marginBottom: 'var(--space-lg)' }}>
              <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-md)' }}>
                <div>
                  <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>{selectedPetani.nama}</h3>
                  <p className="text-tertiary text-sm">{selectedPetani.no_hp || 'No HP tidak tersedia'}</p>
                </div>
                <div className="flex gap-sm">
                  <button className="btn btn-primary btn-sm" onClick={() => setShowModal(true)}>Tambah Kasbon</button>
                  <button className="btn btn-outline btn-sm" onClick={handleBayarTunai}>Bayar Tunai</button>
                </div>
              </div>
              <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))' }}>
                <div style={{ textAlign: 'center', padding: 'var(--space-md)', background: 'var(--bg-surface)', borderRadius: 'var(--radius-md)' }}>
                  <div className="text-mono" style={{ fontSize: 'var(--text-2xl)', fontWeight: 700, color: saldo > 0 ? 'var(--color-warning)' : 'var(--color-success)' }}>
                    {formatRupiah(saldo)}
                  </div>
                  <div className="text-tertiary text-sm">Saldo Hutang</div>
                </div>
                {selectedPetani.batas_hutang > 0 && (
                  <div style={{ textAlign: 'center', padding: 'var(--space-md)', background: 'var(--bg-surface)', borderRadius: 'var(--radius-md)' }}>
                    <div className="text-mono" style={{ fontSize: 'var(--text-2xl)', fontWeight: 700 }}>
                      {formatRupiah(selectedPetani.batas_hutang)}
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
                          </td>
                          <td className="table-mono text-danger" style={{ textAlign: 'right' }}>
                            {item.tipe === 'debit' ? formatRupiah(item.jumlah) : ''}
                          </td>
                          <td className="table-mono text-success" style={{ textAlign: 'right' }}>
                            {item.tipe === 'kredit' ? formatRupiah(item.jumlah) : ''}
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
              <h3 className="modal-title">Tambah Hutang - {selectedPetani?.nama}</h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>x</button>
            </div>
            <form onSubmit={handleTambahHutang}>
              <div className="modal-body">
                <div className="form-group">
                  <label className="form-label form-label-required">Jenis</label>
                  <select
                    className="form-input form-select"
                    value={form.jenis}
                    onChange={(e) => setForm({ ...form, jenis: e.target.value })}
                  >
                    <option value="kasbon">Kasbon</option>
                    <option value="panjar">Panjar / Uang Muka</option>
                    <option value="pupuk">Bon Pupuk</option>
                    <option value="lainnya">Lainnya</option>
                  </select>
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
                <button type="submit" className="btn btn-primary" disabled={saving}>{saving ? 'Menyimpan...' : 'Tambah Hutang'}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AppShell>
  );
}
