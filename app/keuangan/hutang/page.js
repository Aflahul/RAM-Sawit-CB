'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, getTodayISO } from '@/lib/utils';
import { exportToExcel } from '@/lib/export';

export default function HutangPage() {
  const [petaniList, setPetaniList] = useState([]);
  const [selectedPetani, setSelectedPetani] = useState(null);
  const [hutangList, setHutangList] = useState([]);
  const [logList, setLogList] = useState([]);
  const [saldo, setSaldo] = useState(0);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState(null);

  const [form, setForm] = useState({
    jenis: 'kasbon', jumlah: '', keterangan: '',
  });

  // Summary per petani
  const [petaniSummary, setPetaniSummary] = useState([]);

  useEffect(() => { loadData(); }, []);

  async function loadData() {
    setLoading(true);
    const { data: petani } = await supabase.from('petani').select('*').eq('aktif', true).order('nama');
    setPetaniList(petani || []);

    // Load all hutang and logs to calculate summary
    const { data: allHutang } = await supabase.from('hutang').select('petani_id, jumlah');
    const { data: allLogs } = await supabase.from('hutang_log').select('petani_id, jumlah_bayar');

    const summary = {};
    (allHutang || []).forEach(h => {
      if (!summary[h.petani_id]) summary[h.petani_id] = { hutang: 0, bayar: 0 };
      summary[h.petani_id].hutang += h.jumlah || 0;
    });
    (allLogs || []).forEach(l => {
      if (!summary[l.petani_id]) summary[l.petani_id] = { hutang: 0, bayar: 0 };
      summary[l.petani_id].bayar += l.jumlah_bayar || 0;
    });

    const summaryArr = (petani || [])
      .map(p => ({
        ...p,
        saldo: (summary[p.id]?.hutang || 0) - (summary[p.id]?.bayar || 0),
      }))
      .filter(p => p.saldo > 0)
      .sort((a, b) => b.saldo - a.saldo);

    setPetaniSummary(summaryArr);
    setLoading(false);
  }

  async function selectPetani(petaniId) {
    const petani = petaniList.find(p => p.id === petaniId);
    setSelectedPetani(petani);

    // Load hutang entries
    const { data: hutang } = await supabase
      .from('hutang')
      .select('*')
      .eq('petani_id', petaniId)
      .order('tanggal', { ascending: false });

    const { data: logs } = await supabase
      .from('hutang_log')
      .select('*')
      .eq('petani_id', petaniId)
      .order('tanggal', { ascending: false });

    setHutangList(hutang || []);
    setLogList(logs || []);

    const totalH = (hutang || []).reduce((s, h) => s + (h.jumlah || 0), 0);
    const totalL = (logs || []).reduce((s, l) => s + (l.jumlah_bayar || 0), 0);
    setSaldo(totalH - totalL);
  }

  async function handleTambahHutang(e) {
    e.preventDefault();
    if (!selectedPetani) return;
    setSaving(true);

    const jumlah = parseFloat(form.jumlah);
    const { data: { session } } = await supabase.auth.getSession();

    // Cek batas hutang
    if (selectedPetani.batas_hutang > 0 && (saldo + jumlah) > selectedPetani.batas_hutang) {
      if (!confirm(`⚠️ PERINGATAN: Hutang akan melebihi batas (${formatRupiah(selectedPetani.batas_hutang)}).\n\nSaldo saat ini: ${formatRupiah(saldo)}\nTambahan: ${formatRupiah(jumlah)}\nTotal: ${formatRupiah(saldo + jumlah)}\n\nLanjutkan?`)) {
        setSaving(false);
        return;
      }
    }

    await supabase.from('hutang').insert({
      petani_id: selectedPetani.id,
      tanggal: getTodayISO(),
      jenis: form.jenis,
      jumlah,
      keterangan: form.keterangan || null,
      created_by: session?.user?.id || null,
    });

    setSaving(false);
    setShowModal(false);
    setForm({ jenis: 'kasbon', jumlah: '', keterangan: '' });
    setToast({ message: 'Hutang berhasil ditambahkan!', type: 'success' });
    setTimeout(() => setToast(null), 3000);

    selectPetani(selectedPetani.id);
    loadData();
  }

  async function handleBayarTunai() {
    const jumlah = prompt('Masukkan jumlah pembayaran tunai (Rp):');
    if (!jumlah || parseFloat(jumlah) <= 0) return;

    await supabase.from('hutang_log').insert({
      petani_id: selectedPetani.id,
      tanggal: getTodayISO(),
      jumlah_bayar: parseFloat(jumlah),
      sumber: 'bayar_tunai',
      keterangan: 'Pembayaran tunai',
    });

    setToast({ message: 'Pembayaran berhasil dicatat!', type: 'success' });
    setTimeout(() => setToast(null), 3000);
    selectPetani(selectedPetani.id);
    loadData();
  }

  const jenisLabel = { kasbon: 'Kasbon', panjar: 'Panjar', pupuk: 'Bon Pupuk', lainnya: 'Lainnya' };

  function exportHutang() {
    const data = petaniList.filter(p => p.saldo > 0).map(p => ({
      nama: p.nama, no_hp: p.no_hp || '-', saldo: p.saldo,
      batas: p.batas_hutang || 0,
    }));
    exportToExcel(data, [
      { key: 'nama', label: 'Nama Petani' },
      { key: 'no_hp', label: 'No HP' },
      { key: 'saldo', label: 'Saldo Hutang' },
      { key: 'batas', label: 'Batas Hutang' },
    ], 'Daftar_Hutang_Petani', 'Hutang');
  }

  return (
    <AppShell title="Hutang Petani" subtitle="Kelola kasbon, panjar, dan hutang petani">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.type === 'success' ? '✅' : '❌'}</span>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <h2 className="page-title">💳 Hutang Petani</h2>
        <button className="btn btn-outline btn-sm" onClick={exportHutang}>📥 Export Excel</button>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: selectedPetani ? '1fr 1.5fr' : '1fr', gap: 'var(--space-xl)' }}>
        {/* Daftar Petani dengan Hutang */}
        <div>
          {/* Pilih Petani */}
          <div className="form-group">
            <select className="form-input form-select" onChange={e => e.target.value && selectPetani(e.target.value)} defaultValue="">
              <option value="">-- Pilih Petani --</option>
              {petaniList.map(p => <option key={p.id} value={p.id}>{p.nama}</option>)}
            </select>
          </div>

          {/* Summary */}
          <div className="card">
            <div className="card-header">
              <span className="card-title">Petani dengan Hutang Aktif</span>
              <span className="badge badge-warning">{petaniSummary.length}</span>
            </div>
            {loading ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {[1, 2, 3].map(i => <div key={i} className="skeleton" style={{ height: 44 }}></div>)}
              </div>
            ) : petaniSummary.length === 0 ? (
              <div className="empty-state" style={{ padding: 'var(--space-lg)' }}>
                <div className="empty-state-icon">✅</div>
                <div className="empty-state-title">Tidak ada hutang aktif</div>
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                {petaniSummary.map(p => (
                  <div
                    key={p.id}
                    onClick={() => selectPetani(p.id)}
                    className="flex items-center justify-between"
                    style={{
                      padding: '10px 12px', borderRadius: 'var(--radius-md)', cursor: 'pointer',
                      background: selectedPetani?.id === p.id ? 'var(--color-primary-700)' : 'transparent',
                      transition: 'background var(--transition-fast)',
                    }}
                  >
                    <span style={{ fontWeight: 500 }}>{p.nama}</span>
                    <span className="text-mono text-warning" style={{ fontWeight: 600 }}>{formatRupiah(p.saldo)}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Detail Petani */}
        {selectedPetani && (
          <div>
            {/* Info */}
            <div className="card" style={{ marginBottom: 'var(--space-lg)' }}>
              <div className="flex items-center justify-between" style={{ marginBottom: 'var(--space-md)' }}>
                <div>
                  <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>{selectedPetani.nama}</h3>
                  <p className="text-tertiary text-sm">{selectedPetani.no_hp || 'No HP tidak tersedia'}</p>
                </div>
                <div className="flex gap-sm">
                  <button className="btn btn-primary btn-sm" onClick={() => setShowModal(true)}>+ Kasbon</button>
                  <button className="btn btn-outline btn-sm" onClick={handleBayarTunai}>💵 Bayar Tunai</button>
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

            {/* Riwayat */}
            <div className="card">
              <div className="card-header">
                <span className="card-title">Riwayat Hutang & Pembayaran</span>
              </div>
              {hutangList.length === 0 && logList.length === 0 ? (
                <div className="empty-state" style={{ padding: 'var(--space-lg)' }}>
                  <div className="empty-state-title">Belum ada riwayat</div>
                </div>
              ) : (
                <div className="table-container" style={{ border: 'none' }}>
                  <table className="table">
                    <thead>
                      <tr><th>Tanggal</th><th>Keterangan</th><th style={{ textAlign: 'right' }}>Debit</th><th style={{ textAlign: 'right' }}>Kredit</th></tr>
                    </thead>
                    <tbody>
                      {/* Combine and sort by date */}
                      {[
                        ...hutangList.map(h => ({ ...h, _type: 'hutang', _date: h.tanggal, _sort: new Date(h.created_at) })),
                        ...logList.map(l => ({ ...l, _type: 'bayar', _date: l.tanggal, _sort: new Date(l.created_at) })),
                      ].sort((a, b) => b._sort - a._sort).map((item, i) => (
                        <tr key={i}>
                          <td>{new Date(item._date).toLocaleDateString('id-ID')}</td>
                          <td>
                            {item._type === 'hutang'
                              ? <span className="badge badge-danger">{jenisLabel[item.jenis] || item.jenis}</span>
                              : <span className="badge badge-success">{item.sumber === 'potong_tbs' ? 'Potong TBS' : 'Bayar Tunai'}</span>
                            }
                            {' '}{item.keterangan || ''}
                          </td>
                          <td className="table-mono text-danger" style={{ textAlign: 'right' }}>
                            {item._type === 'hutang' ? formatRupiah(item.jumlah) : ''}
                          </td>
                          <td className="table-mono text-success" style={{ textAlign: 'right' }}>
                            {item._type === 'bayar' ? formatRupiah(item.jumlah_bayar) : ''}
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

      {/* Modal Tambah Hutang */}
      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Tambah Hutang — {selectedPetani?.nama}</h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <form onSubmit={handleTambahHutang}>
              <div className="modal-body">
                <div className="form-group">
                  <label className="form-label form-label-required">Jenis</label>
                  <select className="form-input form-select" value={form.jenis}
                    onChange={e => setForm({ ...form, jenis: e.target.value })}>
                    <option value="kasbon">Kasbon</option>
                    <option value="panjar">Panjar / Uang Muka</option>
                    <option value="pupuk">Bon Pupuk</option>
                    <option value="lainnya">Lainnya</option>
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Jumlah (Rp)</label>
                  <input type="number" className="form-input form-input-mono" value={form.jumlah}
                    onChange={e => setForm({ ...form, jumlah: e.target.value })} min={1} required />
                </div>
                <div className="form-group">
                  <label className="form-label">Keterangan</label>
                  <input className="form-input" value={form.keterangan}
                    onChange={e => setForm({ ...form, keterangan: e.target.value })} placeholder="Opsional" />
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
