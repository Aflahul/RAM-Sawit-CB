'use client';

import { useState, useEffect, useRef } from 'react';
import AppShell from '@/components/layout/AppShell';
import ConfirmDialog from '@/components/ui/ConfirmDialog';
import { supabase } from '@/lib/supabase';
import {
  formatRupiah, formatNumber, formatTanggal, formatTanggalPendek,
  formatWaktu, hitungBeratBersih, hitungTotalHarga, getTodayISO, generateNoStruk,
} from '@/lib/utils';

export default function InputTBSPage() {
  const [petaniList, setPetaniList] = useState([]);
  const [hargaHariIni, setHargaHariIni] = useState(0);
  const [transaksiHariIni, setTransaksiHariIni] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showStruk, setShowStruk] = useState(null);
  const [toast, setToast] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [editTarget, setEditTarget] = useState(null);
  const [editForm, setEditForm] = useState({ berat_kotor: '', persen_potongan: '' });
  const strukRef = useRef(null);

  const [form, setForm] = useState({
    petani_id: '',
    berat_kotor: '',
    persen_potongan: '2',
    potong_hutang: false,
    jumlah_potong: '',
  });

  const [selectedPetani, setSelectedPetani] = useState(null);
  const [saldoHutang, setSaldoHutang] = useState(0);

  useEffect(() => { loadInitialData(); }, []);

  async function loadInitialData() {
    setLoading(true);
    const today = getTodayISO();

    const [{ data: petani }, { data: harga }, { data: transaksi }] = await Promise.all([
      supabase.from('petani').select('*').eq('aktif', true).order('nama'),
      supabase.from('harga_tbs').select('*').eq('tanggal', today).single(),
      supabase.from('transaksi_beli').select('*, petani:petani_id(nama)').eq('tanggal', today).order('created_at', { ascending: false }),
    ]);

    setPetaniList(petani || []);
    setHargaHariIni(harga?.harga_per_kg || 0);
    setTransaksiHariIni(transaksi || []);
    setLoading(false);
  }

  async function loadSaldoHutang(petaniId) {
    const [{ data: hutangData }, { data: logData }] = await Promise.all([
      supabase.from('hutang').select('jumlah').eq('petani_id', petaniId),
      supabase.from('hutang_log').select('jumlah_bayar').eq('petani_id', petaniId),
    ]);
    const totalHutang = hutangData?.reduce((s, h) => s + (h.jumlah || 0), 0) || 0;
    const totalBayar = logData?.reduce((s, h) => s + (h.jumlah_bayar || 0), 0) || 0;
    setSaldoHutang(totalHutang - totalBayar);
  }

  function handlePetaniChange(petaniId) {
    setForm({ ...form, petani_id: petaniId, potong_hutang: false, jumlah_potong: '' });
    const petani = petaniList.find(p => p.id === petaniId);
    setSelectedPetani(petani || null);
    if (petaniId) loadSaldoHutang(petaniId);
    else setSaldoHutang(0);
  }

  // Calculations
  const beratKotor = parseFloat(form.berat_kotor) || 0;
  const persenPot = parseFloat(form.persen_potongan) || 0;
  const beratBersih = hitungBeratBersih(beratKotor, persenPot);
  const totalHarga = hitungTotalHarga(beratBersih, hargaHariIni);
  const potonganHutang = form.potong_hutang ? Math.min(parseFloat(form.jumlah_potong) || saldoHutang, saldoHutang, totalHarga) : 0;
  const bayarTunai = totalHarga - potonganHutang;

  async function handleSubmit(e, cetak = false) {
    e.preventDefault();
    if (!form.petani_id || beratKotor <= 0 || hargaHariIni <= 0) return;

    setSaving(true);
    const today = getTodayISO();

    // Get sequence for struk number
    const { count } = await supabase
      .from('transaksi_beli')
      .select('*', { count: 'exact', head: true })
      .eq('tanggal', today);

    const noStruk = generateNoStruk('TBS', (count || 0) + 1);

    // Get user
    const { data: { session } } = await supabase.auth.getSession();

    const transaksiPayload = {
      tanggal: today,
      petani_id: form.petani_id,
      berat_kotor: beratKotor,
      persen_potongan: persenPot,
      berat_bersih: beratBersih,
      harga_per_kg: hargaHariIni,
      total_harga: totalHarga,
      potongan_hutang: potonganHutang,
      total_bayar_tunai: bayarTunai,
      no_struk: noStruk,
      created_by: session?.user?.id || null,
    };

    const { data: savedTrx, error: trxError } = await supabase
      .from('transaksi_beli')
      .insert(transaksiPayload)
      .select('*, petani:petani_id(nama)')
      .single();

    if (trxError) {
      showToast('Gagal menyimpan transaksi: ' + trxError.message, 'error');
      setSaving(false);
      return;
    }

    // Jika ada potongan hutang, catat di hutang_log
    if (potonganHutang > 0) {
      await supabase.from('hutang_log').insert({
        petani_id: form.petani_id,
        tanggal: today,
        jumlah_bayar: potonganHutang,
        sumber: 'potong_tbs',
        transaksi_beli_id: savedTrx.id,
        keterangan: `Potong dari ${noStruk}`,
      });
    }

    showToast('Transaksi berhasil disimpan!', 'success');
    setSaving(false);

    // Reset form
    setForm({ petani_id: '', berat_kotor: '', persen_potongan: '2', potong_hutang: false, jumlah_potong: '' });
    setSelectedPetani(null);
    setSaldoHutang(0);

    // Reload transaksi hari ini
    loadInitialData();

    // Cetak struk
    if (cetak && savedTrx) {
      setShowStruk(savedTrx);
      setTimeout(() => window.print(), 500);
    }
  }

  function showToast(message, type = 'success') {
    setToast({ message, type });
    setTimeout(() => setToast(null), 3000);
  }

  function openEdit(t) {
    setEditTarget(t);
    setEditForm({ berat_kotor: t.berat_kotor.toString(), persen_potongan: t.persen_potongan.toString() });
  }

  async function handleEditSave() {
    if (!editTarget) return;
    const bk = parseFloat(editForm.berat_kotor) || 0;
    const pp = parseFloat(editForm.persen_potongan) || 0;
    const bb = hitungBeratBersih(bk, pp);
    const th = hitungTotalHarga(bb, editTarget.harga_per_kg);
    const tunai = th - (editTarget.potongan_hutang || 0);

    await supabase.from('transaksi_beli').update({
      berat_kotor: bk, persen_potongan: pp, berat_bersih: bb,
      total_harga: th, total_bayar_tunai: Math.max(tunai, 0),
    }).eq('id', editTarget.id);

    setEditTarget(null);
    showToast('Transaksi berhasil diperbarui!');
    loadInitialData();
  }

  async function handleDelete() {
    if (!deleteTarget) return;
    // Jika ada potongan hutang, kembalikan ke hutang_log
    if (deleteTarget.potongan_hutang > 0) {
      await supabase.from('hutang_log').delete().eq('transaksi_beli_id', deleteTarget.id);
    }
    await supabase.from('transaksi_beli').delete().eq('id', deleteTarget.id);
    setDeleteTarget(null);
    showToast('Transaksi berhasil dihapus!');
    loadInitialData();
  }

  return (
    <AppShell title="Input TBS" subtitle="Catat pembelian TBS dari petani">
      {/* Toast */}
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.type === 'success' ? '✅' : '❌'}</span>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      {/* Harga Hari Ini Banner */}
      {hargaHariIni > 0 ? (
        <div className="alert alert-success" style={{ marginBottom: 'var(--space-lg)' }}>
          <span className="alert-icon">💲</span>
          <span>Harga TBS hari ini: <strong className="text-mono">{formatRupiah(hargaHariIni)}/kg</strong></span>
        </div>
      ) : (
        <div className="alert alert-warning" style={{ marginBottom: 'var(--space-lg)' }}>
          <span className="alert-icon">⚠️</span>
          <span>Harga TBS hari ini belum diset! <a href="/master/harga" style={{ textDecoration: 'underline' }}>Set harga →</a></span>
        </div>
      )}

      <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: 'var(--space-xl)' }}>
        {/* Form Input */}
        <div className="card">
          <div className="card-header">
            <span className="card-title">📦 Form Input Timbangan</span>
            <span className="text-tertiary text-sm">{formatTanggal(new Date())}</span>
          </div>

          <form onSubmit={(e) => handleSubmit(e, false)}>
            {/* Pilih Petani */}
            <div className="form-group">
              <label className="form-label form-label-required">Petani / Mitra</label>
              <select
                className="form-input form-select"
                value={form.petani_id}
                onChange={(e) => handlePetaniChange(e.target.value)}
                required
              >
                <option value="">-- Pilih Petani --</option>
                {petaniList.map(p => (
                  <option key={p.id} value={p.id}>{p.nama}</option>
                ))}
              </select>
            </div>

            {/* Info Hutang */}
            {selectedPetani && saldoHutang > 0 && (
              <div className="alert alert-warning">
                <span className="alert-icon">💳</span>
                <div>
                  <strong>{selectedPetani.nama}</strong> memiliki saldo hutang:{' '}
                  <strong className="text-mono">{formatRupiah(saldoHutang)}</strong>
                  {selectedPetani.batas_hutang > 0 && (
                    <span className="text-tertiary"> / Batas: {formatRupiah(selectedPetani.batas_hutang)}</span>
                  )}
                </div>
              </div>
            )}

            {/* Input Berat */}
            <div className="form-grid">
              <div className="form-group">
                <label className="form-label form-label-required">Berat Kotor (kg)</label>
                <input
                  type="number"
                  className="form-input form-input-mono"
                  value={form.berat_kotor}
                  onChange={(e) => setForm({ ...form, berat_kotor: e.target.value })}
                  placeholder="0"
                  min={0}
                  step={0.1}
                  required
                />
              </div>
              <div className="form-group">
                <label className="form-label">Potongan (%)</label>
                <input
                  type="number"
                  className="form-input form-input-mono"
                  value={form.persen_potongan}
                  onChange={(e) => setForm({ ...form, persen_potongan: e.target.value })}
                  min={0}
                  max={100}
                  step={0.5}
                />
              </div>
            </div>

            {/* Kalkulasi */}
            {beratKotor > 0 && hargaHariIni > 0 && (
              <div className="calc-result">
                <div className="calc-result-row">
                  <span className="calc-result-label">Berat Kotor</span>
                  <span className="calc-result-value">{formatNumber(beratKotor)} kg</span>
                </div>
                <div className="calc-result-row">
                  <span className="calc-result-label">Potongan {persenPot}%</span>
                  <span className="calc-result-value text-danger">-{formatNumber(beratKotor * persenPot / 100)} kg</span>
                </div>
                <div className="calc-result-row">
                  <span className="calc-result-label">Berat Bersih</span>
                  <span className="calc-result-value">{formatNumber(beratBersih)} kg</span>
                </div>
                <div className="calc-result-row">
                  <span className="calc-result-label">Harga /kg</span>
                  <span className="calc-result-value">{formatRupiah(hargaHariIni)}</span>
                </div>
                <div className="calc-result-row">
                  <span className="calc-result-label" style={{ fontWeight: 600 }}>Total Harga</span>
                  <span className="calc-result-value calc-result-total">{formatRupiah(totalHarga)}</span>
                </div>
              </div>
            )}

            {/* Potong Hutang */}
            {selectedPetani && saldoHutang > 0 && totalHarga > 0 && (
              <div className="form-group" style={{ background: 'var(--bg-surface)', padding: 'var(--space-md)', borderRadius: 'var(--radius-md)' }}>
                <label className="toggle" style={{ marginBottom: 'var(--space-sm)' }}>
                  <input
                    type="checkbox"
                    className="toggle-input"
                    checked={form.potong_hutang}
                    onChange={(e) => setForm({ ...form, potong_hutang: e.target.checked, jumlah_potong: saldoHutang.toString() })}
                  />
                  <span className="toggle-track">
                    <span className="toggle-thumb"></span>
                  </span>
                  <span className="toggle-label">Potong Hutang Otomatis</span>
                </label>
                {form.potong_hutang && (
                  <div style={{ marginTop: 'var(--space-sm)' }}>
                    <label className="form-label">Jumlah Potong (Rp)</label>
                    <input
                      type="number"
                      className="form-input form-input-mono"
                      value={form.jumlah_potong}
                      onChange={(e) => setForm({ ...form, jumlah_potong: e.target.value })}
                      max={Math.min(saldoHutang, totalHarga)}
                      min={0}
                    />
                    <div className="form-hint">Maks: {formatRupiah(Math.min(saldoHutang, totalHarga))}</div>
                    {potonganHutang > 0 && (
                      <div style={{ marginTop: 8, fontWeight: 600, color: 'var(--color-primary-400)' }}>
                        💰 Bayar Tunai: <span className="text-mono">{formatRupiah(bayarTunai)}</span>
                      </div>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* Actions */}
            <div className="form-actions">
              <button
                type="submit"
                className="btn btn-primary btn-lg"
                disabled={saving || beratKotor <= 0 || !form.petani_id || hargaHariIni <= 0}
              >
                {saving ? 'Menyimpan...' : '💾 Simpan'}
              </button>
              <button
                type="button"
                className="btn btn-gold btn-lg"
                disabled={saving || beratKotor <= 0 || !form.petani_id || hargaHariIni <= 0}
                onClick={(e) => handleSubmit(e, true)}
              >
                🖨️ Simpan & Cetak
              </button>
            </div>
          </form>
        </div>

        {/* Transaksi Hari Ini */}
        <div className="card">
          <div className="card-header">
            <span className="card-title">Transaksi Hari Ini ({transaksiHariIni.length})</span>
            <span className="text-mono text-secondary">
              {formatNumber(transaksiHariIni.reduce((s, t) => s + (t.berat_bersih || 0), 0))} kg
            </span>
          </div>
          {transaksiHariIni.length === 0 ? (
            <div className="empty-state" style={{ padding: 'var(--space-xl)' }}>
              <div className="empty-state-icon">📦</div>
              <div className="empty-state-title">Belum ada transaksi hari ini</div>
            </div>
          ) : (
            <div className="table-container" style={{ border: 'none' }}>
              <table className="table">
                <thead>
                  <tr>
                    <th>Struk</th>
                    <th>Petani</th>
                    <th style={{ textAlign: 'right' }}>Berat</th>
                    <th style={{ textAlign: 'right' }}>Total</th>
                    <th style={{ textAlign: 'right' }}>Bayar</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {transaksiHariIni.map(t => (
                    <tr key={t.id}>
                      <td className="table-mono" style={{ fontSize: 'var(--text-xs)' }}>{t.no_struk}</td>
                      <td>{t.petani?.nama || '-'}</td>
                      <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(t.berat_bersih)}</td>
                      <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(t.total_harga)}</td>
                      <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(t.total_bayar_tunai)}</td>
                      <td>
                        <div className="flex gap-xs">
                          <button className="btn btn-ghost btn-sm" onClick={() => openEdit(t)} title="Edit">✏️</button>
                          <button className="btn btn-ghost btn-sm" onClick={() => { setShowStruk(t); setTimeout(() => window.print(), 300); }} title="Cetak">🖨️</button>
                          <button className="btn btn-ghost btn-sm" onClick={() => setDeleteTarget(t)} title="Hapus">🗑️</button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {/* Struk Thermal (hidden, only visible on print) */}
      {showStruk && (
        <div ref={strukRef} className="struk-thermal">
          <div className="struk-center struk-bold struk-lg">SAWIT CB</div>
          <div className="struk-center">RAM Kelapa Sawit</div>
          <hr className="struk-separator" />
          <div>No: {showStruk.no_struk}</div>
          <div>Tgl: {formatTanggalPendek(showStruk.tanggal)}  {formatWaktu(showStruk.created_at)}</div>
          <br />
          <div>Petani: {showStruk.petani?.nama || '-'}</div>
          <hr className="struk-separator" />
          <div className="struk-row">
            <span>Berat Kotor</span>
            <span>{formatNumber(showStruk.berat_kotor)} kg</span>
          </div>
          <div className="struk-row">
            <span>Potongan {showStruk.persen_potongan}%</span>
            <span>{formatNumber(showStruk.berat_kotor * showStruk.persen_potongan / 100)} kg</span>
          </div>
          <div className="struk-row">
            <span>Berat Bersih</span>
            <span>{formatNumber(showStruk.berat_bersih)} kg</span>
          </div>
          <div className="struk-row">
            <span>Harga /kg</span>
            <span>{formatRupiah(showStruk.harga_per_kg)}</span>
          </div>
          <hr className="struk-separator" />
          <div className="struk-row struk-bold">
            <span>TOTAL HARGA</span>
            <span>{formatRupiah(showStruk.total_harga)}</span>
          </div>
          {showStruk.potongan_hutang > 0 && (
            <div className="struk-row">
              <span>Potong Hutang</span>
              <span>{formatRupiah(showStruk.potongan_hutang)}</span>
            </div>
          )}
          <div className="struk-row struk-bold struk-lg">
            <span>DIBAYAR</span>
            <span>{formatRupiah(showStruk.total_bayar_tunai)}</span>
          </div>
          <hr className="struk-separator" />
          <div className="struk-center" style={{ marginTop: 8 }}>Terima Kasih</div>
          <div className="struk-center" style={{ fontSize: 10, marginTop: 4 }}>Sawit CB - Sistem Pencatatan RAM</div>
        </div>
      )}

      {/* Edit Modal */}
      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: 450 }}>
            <div className="modal-header">
              <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>✏️ Edit Transaksi</h3>
              <button className="btn btn-ghost btn-sm" onClick={() => setEditTarget(null)}>✕</button>
            </div>
            <div className="modal-body" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-md)' }}>
              <div className="text-tertiary text-sm" style={{ marginBottom: 'var(--space-sm)' }}>
                Struk: <strong>{editTarget.no_struk}</strong> • Petani: <strong>{editTarget.petani?.nama}</strong>
              </div>
              <div>
                <label className="form-label">Berat Kotor (kg)</label>
                <input type="number" className="form-input form-input-mono"
                  value={editForm.berat_kotor}
                  onChange={e => setEditForm({ ...editForm, berat_kotor: e.target.value })} />
              </div>
              <div>
                <label className="form-label">Potongan (%)</label>
                <input type="number" step="0.1" className="form-input form-input-mono"
                  value={editForm.persen_potongan}
                  onChange={e => setEditForm({ ...editForm, persen_potongan: e.target.value })} />
              </div>
              <div style={{ padding: 'var(--space-sm)', background: 'var(--bg-surface)', borderRadius: 'var(--radius-md)', fontSize: 'var(--text-sm)' }}>
                <div>Berat Bersih: <strong className="text-mono">{formatNumber(hitungBeratBersih(parseFloat(editForm.berat_kotor) || 0, parseFloat(editForm.persen_potongan) || 0))} kg</strong></div>
                <div>Total: <strong className="text-mono">{formatRupiah(hitungTotalHarga(hitungBeratBersih(parseFloat(editForm.berat_kotor) || 0, parseFloat(editForm.persen_potongan) || 0), editTarget.harga_per_kg))}</strong></div>
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-outline" onClick={() => setEditTarget(null)}>Batal</button>
              <button className="btn btn-primary" onClick={handleEditSave}>💾 Simpan Perubahan</button>
            </div>
          </div>
        </div>
      )}

      {/* Delete Confirm */}
      <ConfirmDialog
        open={!!deleteTarget}
        title="Hapus Transaksi?"
        message={deleteTarget ? `Yakin hapus transaksi ${deleteTarget.no_struk} (${deleteTarget.petani?.nama})? ${deleteTarget.potongan_hutang > 0 ? 'Potongan hutang juga akan dikembalikan.' : ''} Tindakan ini tidak bisa dibatalkan.` : ''}
        confirmText="🗑️ Ya, Hapus"
        cancelText="Batal"
        variant="danger"
        onConfirm={handleDelete}
        onCancel={() => setDeleteTarget(null)}
      />
    </AppShell>
  );
}
