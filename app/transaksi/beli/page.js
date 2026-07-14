'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import PromptDialog from '@/components/ui/PromptDialog';
import { supabase } from '@/lib/supabase';
import {
  formatRupiah,
  formatNumber,
  formatTanggal,
  formatTanggalPendek,
  formatWaktu,
  hitungBeratBersih,
  hitungTotalHarga,
  getTodayISO,
} from '@/lib/utils';

function toPrintableTransaction(transaction, selectedPetani) {
  if (!transaction) return null;

  return {
    ...transaction,
    petani: {
      nama: transaction.petani?.nama || transaction.petani_nama || selectedPetani?.nama || '-',
    },
  };
}

export default function InputTBSPage() {
  const [petaniList, setPetaniList] = useState([]);
  const [hargaAktif, setHargaAktif] = useState(null);
  const [transaksiHariIni, setTransaksiHariIni] = useState([]);
  const [selectedPetani, setSelectedPetani] = useState(null);
  const [saldoHutang, setSaldoHutang] = useState(0);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState(null);
  const [showStruk, setShowStruk] = useState(null);
  const [cancelTarget, setCancelTarget] = useState(null);
  const [canceling, setCanceling] = useState(false);
  const strukRef = useRef(null);

  const [form, setForm] = useState({
    petani_id: '',
    berat_kotor: '',
    persen_potongan: '2',
    potong_hutang: false,
    jumlah_potong: '',
  });

  const loadInitialData = useCallback(async () => {
    setLoading(true);
    const today = getTodayISO();

    const [{ data: petani }, { data: harga }, { data: transaksi, error: transaksiError }] = await Promise.all([
      supabase.from('petani').select('*').eq('aktif', true).order('nama'),
      supabase
        .from('harga_tbs_lokal')
        .select('*')
        .eq('aktif', true)
        .order('berlaku_mulai', { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from('transaksi_beli_tbs')
        .select('*, petani:petani_id(nama)')
        .eq('tanggal', today)
        .neq('status', 'dibatalkan')
        .order('created_at', { ascending: false }),
    ]);

    if (transaksiError) {
      setToast({ type: 'error', message: transaksiError.message });
    }

    setPetaniList(petani || []);
    setHargaAktif(harga || null);
    setTransaksiHariIni(transaksi || []);
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadInitialData();
  }, [loadInitialData]);

  async function loadSaldoHutang(petaniId) {
    const { data, error } = await supabase
      .from('hutang_ledger')
      .select('tipe, jumlah')
      .eq('pihak_type', 'petani')
      .eq('petani_id', petaniId)
      .neq('status', 'dibatalkan');

    if (error) {
      setSaldoHutang(0);
      setToast({ type: 'error', message: `Gagal membaca saldo hutang: ${error.message}` });
      return;
    }

    const saldo = (data || []).reduce((total, row) => {
      return total + (row.tipe === 'debit' ? Number(row.jumlah || 0) : -Number(row.jumlah || 0));
    }, 0);

    setSaldoHutang(Math.max(saldo, 0));
  }

  function showToast(message, type = 'success') {
    setToast({ message, type });
    setTimeout(() => setToast(null), 3000);
  }

  function handlePetaniChange(petaniId) {
    setForm({ ...form, petani_id: petaniId, potong_hutang: false, jumlah_potong: '' });
    const petani = petaniList.find((item) => item.id === petaniId);
    setSelectedPetani(petani || null);
    if (petaniId) loadSaldoHutang(petaniId);
    else setSaldoHutang(0);
  }

  const hargaPerKg = Number(hargaAktif?.harga_per_kg || 0);
  const beratKotor = Number(form.berat_kotor) || 0;
  const persenPot = Number(form.persen_potongan) || 0;
  const beratBersih = hitungBeratBersih(beratKotor, persenPot);
  const totalHarga = hitungTotalHarga(beratBersih, hargaPerKg);
  const potonganHutang = form.potong_hutang
    ? Math.min(Number(form.jumlah_potong) || saldoHutang, saldoHutang, totalHarga)
    : 0;
  const bayarTunai = totalHarga - potonganHutang;

  async function handleSubmit(e, cetak = false) {
    e.preventDefault();
    if (!form.petani_id || beratKotor <= 0 || hargaPerKg <= 0) return;

    setSaving(true);
    const { data, error } = await supabase.rpc('create_transaksi_beli_tbs', {
      p_petani_id: form.petani_id,
      p_berat_kotor_kg: beratKotor,
      p_potongan_percent: persenPot,
      p_potongan_hutang: potonganHutang,
      p_keterangan: null,
      p_tanggal: getTodayISO(),
    });

    if (error) {
      showToast(`Gagal menyimpan transaksi: ${error.message}`, 'error');
      setSaving(false);
      return;
    }

    const saved = Array.isArray(data) ? data[0] : data;
    const printable = toPrintableTransaction(saved, selectedPetani);

    showToast('Transaksi berhasil disimpan.');
    setForm({ petani_id: '', berat_kotor: '', persen_potongan: '2', potong_hutang: false, jumlah_potong: '' });
    setSelectedPetani(null);
    setSaldoHutang(0);
    await loadInitialData();
    setSaving(false);

    if (cetak && printable) {
      setShowStruk(printable);
      setTimeout(() => window.print(), 500);
    }
  }

  async function handleCancelTransaction(reason) {
    if (!cancelTarget || canceling) return;

    setCanceling(true);
    const { error } = await supabase.rpc('cancel_transaksi_beli_tbs', {
      p_transaksi_id: cancelTarget.id,
      p_alasan: reason,
    });
    setCanceling(false);

    if (error) {
      showToast(`Gagal membatalkan transaksi: ${error.message}`, 'error');
      setCancelTarget(null);
      return;
    }

    showToast('Transaksi berhasil dibatalkan dengan reversal ledger.');
    setCancelTarget(null);
    await loadInitialData();
  }

  return (
    <AppShell title="Input TBS Lokal" subtitle="Catat pembelian TBS dari petani lokal">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      {hargaPerKg > 0 ? (
        <div className="alert alert-success" style={{ marginBottom: 'var(--space-lg)' }}>
          <span>
            Harga TBS aktif: <strong className="text-mono">{formatRupiah(hargaPerKg)}/kg</strong>
          </span>
        </div>
      ) : (
        <div className="alert alert-warning" style={{ marginBottom: 'var(--space-lg)' }}>
          <span>
            Harga TBS lokal aktif belum diset. Buka <a href="/master/harga" style={{ textDecoration: 'underline' }}>Harga TBS</a>.
          </span>
        </div>
      )}

      <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: 'var(--space-xl)' }}>
        <div className="card">
          <div className="card-header">
            <span className="card-title">Form Timbangan Petani Lokal</span>
            <span className="text-tertiary text-sm">{formatTanggal(new Date())}</span>
          </div>

          <form onSubmit={(e) => handleSubmit(e, false)}>
            <div className="form-group">
              <label className="form-label form-label-required">Petani lokal</label>
              <select
                className="form-input form-select"
                value={form.petani_id}
                onChange={(e) => handlePetaniChange(e.target.value)}
                required
              >
                <option value="">-- Pilih Petani --</option>
                {petaniList.map((petani) => (
                  <option key={petani.id} value={petani.id}>{petani.nama}</option>
                ))}
              </select>
            </div>

            {selectedPetani && saldoHutang > 0 && (
              <div className="alert alert-warning">
                <div>
                  <strong>{selectedPetani.nama}</strong> memiliki saldo hutang{' '}
                  <strong className="text-mono">{formatRupiah(saldoHutang)}</strong>
                  {selectedPetani.batas_hutang > 0 && (
                    <span className="text-tertiary"> / Batas: {formatRupiah(selectedPetani.batas_hutang)}</span>
                  )}
                </div>
              </div>
            )}

            <div className="form-grid">
              <div className="form-group">
                <label className="form-label form-label-required">Berat kotor (kg)</label>
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

            {beratKotor > 0 && hargaPerKg > 0 && (
              <div className="calc-result">
                <div className="calc-result-row">
                  <span className="calc-result-label">Berat kotor</span>
                  <span className="calc-result-value">{formatNumber(beratKotor)} kg</span>
                </div>
                <div className="calc-result-row">
                  <span className="calc-result-label">Potongan {persenPot}%</span>
                  <span className="calc-result-value text-danger">-{formatNumber(beratKotor * persenPot / 100)} kg</span>
                </div>
                <div className="calc-result-row">
                  <span className="calc-result-label">Berat bersih</span>
                  <span className="calc-result-value">{formatNumber(beratBersih)} kg</span>
                </div>
                <div className="calc-result-row">
                  <span className="calc-result-label">Harga /kg</span>
                  <span className="calc-result-value">{formatRupiah(hargaPerKg)}</span>
                </div>
                <div className="calc-result-row">
                  <span className="calc-result-label" style={{ fontWeight: 600 }}>Total harga</span>
                  <span className="calc-result-value calc-result-total">{formatRupiah(totalHarga)}</span>
                </div>
              </div>
            )}

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
                  <span className="toggle-label">Potong hutang dari pembayaran</span>
                </label>
                {form.potong_hutang && (
                  <div style={{ marginTop: 'var(--space-sm)' }}>
                    <label className="form-label">Jumlah potong (Rp)</label>
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
                        Bayar tunai: <span className="text-mono">{formatRupiah(bayarTunai)}</span>
                      </div>
                    )}
                  </div>
                )}
              </div>
            )}

            <div className="form-actions">
              <button
                type="submit"
                className="btn btn-primary btn-lg"
                disabled={saving || beratKotor <= 0 || !form.petani_id || hargaPerKg <= 0}
              >
                {saving ? 'Menyimpan...' : 'Simpan'}
              </button>
              <button
                type="button"
                className="btn btn-gold btn-lg"
                disabled={saving || beratKotor <= 0 || !form.petani_id || hargaPerKg <= 0}
                onClick={(e) => handleSubmit(e, true)}
              >
                Simpan & Cetak
              </button>
            </div>
          </form>
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">Transaksi Hari Ini ({transaksiHariIni.length})</span>
            <span className="text-mono text-secondary">
              {formatNumber(transaksiHariIni.reduce((sum, item) => sum + Number(item.berat_bersih_kg || 0), 0))} kg
            </span>
          </div>
          {loading ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[1, 2, 3].map((item) => (
                <div key={item} className="skeleton" style={{ height: 44 }} />
              ))}
            </div>
          ) : transaksiHariIni.length === 0 ? (
            <div className="empty-state" style={{ padding: 'var(--space-xl)' }}>
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
                  {transaksiHariIni.map((transaksi) => (
                    <tr key={transaksi.id}>
                      <td className="table-mono" style={{ fontSize: 'var(--text-xs)' }}>{transaksi.no_struk}</td>
                      <td>{transaksi.petani?.nama || '-'}</td>
                      <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(transaksi.berat_bersih_kg)}</td>
                      <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(transaksi.total_harga)}</td>
                      <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(transaksi.total_bayar_tunai)}</td>
                      <td>
                        <div className="flex gap-xs">
                          <button
                            className="btn btn-ghost btn-sm"
                            onClick={() => { setShowStruk(toPrintableTransaction(transaksi)); setTimeout(() => window.print(), 300); }}
                            title="Cetak"
                          >
                            Cetak
                          </button>
                          <button
                            className="btn btn-ghost btn-sm"
                            onClick={() => setCancelTarget(transaksi)}
                            title="Batalkan"
                          >
                            Batalkan
                          </button>
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

      {showStruk && (
        <div ref={strukRef} className="struk-thermal">
          <div className="struk-center struk-bold struk-lg">SAWIT CB</div>
          <div className="struk-center">RAM Kelapa Sawit</div>
          <hr className="struk-separator" />
          <div>No: {showStruk.no_struk}</div>
          <div>Tgl: {formatTanggalPendek(showStruk.tanggal)} {formatWaktu(showStruk.created_at)}</div>
          <br />
          <div>Petani: {showStruk.petani?.nama || '-'}</div>
          <hr className="struk-separator" />
          <div className="struk-row">
            <span>Berat Kotor</span>
            <span>{formatNumber(showStruk.berat_kotor_kg)} kg</span>
          </div>
          <div className="struk-row">
            <span>Potongan {showStruk.potongan_value}%</span>
            <span>{formatNumber(showStruk.berat_kotor_kg * showStruk.potongan_value / 100)} kg</span>
          </div>
          <div className="struk-row">
            <span>Berat Bersih</span>
            <span>{formatNumber(showStruk.berat_bersih_kg)} kg</span>
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

      <PromptDialog
        open={!!cancelTarget}
        title="Batalkan Transaksi"
        message={cancelTarget ? `Transaksi ${cancelTarget.no_struk} akan dibatalkan dengan reversal stok dan hutang.` : ''}
        label="Alasan pembatalan"
        placeholder="Contoh: salah timbang / salah petani / input ganda"
        confirmText="Batalkan Transaksi"
        cancelText="Kembali"
        variant="danger"
        loading={canceling}
        onConfirm={handleCancelTransaction}
        onCancel={() => !canceling && setCancelTarget(null)}
      />
    </AppShell>
  );
}
