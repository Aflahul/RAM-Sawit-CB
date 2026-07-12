'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, formatNumber, getTodayISO } from '@/lib/utils';

function getSignedBerat(row) {
  const berat = Number(row.berat_kg || 0);

  if (row.tipe === 'masuk') return Math.abs(berat);
  if (row.tipe === 'keluar') return -Math.abs(berat);
  return berat;
}

function getStatusLabel(status) {
  const labels = {
    draft: 'Draft',
    stok_siap_kirim: 'Stok siap kirim',
    dikirim: 'Dikirim',
    diterima: 'Diterima pabrik',
    diterima_pabrik: 'Diterima pabrik',
    dibayar: 'Dibayar pabrik',
    dibayar_pabrik: 'Dibayar pabrik',
    selesai: 'Selesai',
    dibatalkan: 'Dibatalkan',
  };

  return labels[status] || status || '-';
}

function getStatusBadgeClass(status) {
  if (['dibayar', 'dibayar_pabrik', 'selesai'].includes(status)) return 'badge-success';
  if (['diterima', 'diterima_pabrik'].includes(status)) return 'badge-warning';
  if (status === 'dibatalkan') return 'badge-danger';
  return 'badge-info';
}

function hitungNilaiPabrik(form) {
  const tonasePabrik = Number(form.tonase_pabrik || 0);
  const harga = Number(form.harga_pabrik_per_kg || 0);
  const sortasiType = form.potongan_sortasi_type || 'none';
  const sortasiValue = Number(form.potongan_sortasi_value || 0);
  const biayaTimbang = Number(form.biaya_timbang || 0);
  const potonganLain = Number(form.potongan_pabrik_lain || 0);

  const tonaseDasar = sortasiType === 'kg'
    ? Math.max(tonasePabrik - sortasiValue, 0)
    : tonasePabrik;
  const bruto = tonaseDasar * harga;
  const sortasiRupiah = sortasiType === 'percent'
    ? bruto * (sortasiValue / 100)
    : sortasiType === 'nominal'
      ? sortasiValue
      : 0;
  const totalPembayaran = Math.max(bruto - sortasiRupiah - biayaTimbang - potonganLain, 0);

  return {
    tonaseDasar,
    bruto,
    sortasiRupiah,
    totalPembayaran,
  };
}

export default function PengirimanPage() {
  const [list, setList] = useState([]);
  const [sopirList, setSopirList] = useState([]);
  const [kendaraanList, setKendaraanList] = useState([]);
  const [pabrikList, setPabrikList] = useState([]);
  const [allocationsByPengiriman, setAllocationsByPengiriman] = useState({});
  const [stokSaldo, setStokSaldo] = useState(0);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [showUpdateModal, setShowUpdateModal] = useState(null);
  const [detailTarget, setDetailTarget] = useState(null);
  const [saving, setSaving] = useState(false);
  const [filter, setFilter] = useState('semua');
  const [toast, setToast] = useState(null);

  const [form, setForm] = useState({
    tanggal: getTodayISO(),
    sopir_id: '',
    kendaraan_id: '',
    pabrik_id: '',
    tonase_kirim: '',
    nomor_do: '',
  });
  const [updateForm, setUpdateForm] = useState({
    status: 'diterima_pabrik',
    tonase_pabrik: '',
    harga_pabrik_per_kg: '',
    potongan_sortasi_type: 'none',
    potongan_sortasi_value: '',
    biaya_timbang: '',
    potongan_pabrik_lain: '',
    tanggal_bayar: getTodayISO(),
  });

  const estimasiPabrik = useMemo(() => hitungNilaiPabrik(updateForm), [updateForm]);

  const loadAll = useCallback(async () => {
    setLoading(true);

    const [{ data: peng, error: pengError }, { data: sop }, { data: ken }, { data: pab }, { data: stokRows }] = await Promise.all([
      supabase
        .from('pengiriman')
        .select('*, sopir:sopir_id(nama), kendaraan:kendaraan_id(plat_nomor), pabrik:pabrik_id(nama)')
        .eq('sumber', 'lokal')
        .order('tanggal', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(50),
      supabase.from('sopir').select('*').eq('aktif', true).order('nama'),
      supabase.from('kendaraan').select('*').eq('aktif', true).order('plat_nomor'),
      supabase.from('pabrik').select('*').eq('aktif', true).order('nama'),
      supabase.from('stok_tbs_lokal_ledger').select('tipe, berat_kg'),
    ]);

    if (pengError) {
      setToast({ type: 'error', message: pengError.message });
    }

    const pengiriman = peng || [];
    const ids = pengiriman.map((item) => item.id);
    const allocations = {};

    if (ids.length > 0) {
      const { data: details, error: detailError } = await supabase
        .from('pengiriman_lokal_detail')
        .select('*, petani:petani_id(nama), transaksi_beli:transaksi_beli_id(no_struk)')
        .in('pengiriman_id', ids)
        .order('created_at', { ascending: true });

      if (detailError) {
        setToast({ type: 'error', message: detailError.message });
      }

      (details || []).forEach((detail) => {
        if (!allocations[detail.pengiriman_id]) allocations[detail.pengiriman_id] = [];
        allocations[detail.pengiriman_id].push(detail);
      });
    }

    setList(pengiriman);
    setSopirList(sop || []);
    setKendaraanList(ken || []);
    setPabrikList(pab || []);
    setAllocationsByPengiriman(allocations);
    setStokSaldo((stokRows || []).reduce((total, row) => total + getSignedBerat(row), 0));
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadAll();
  }, [loadAll]);

  function showToast(message, type = 'success') {
    setToast({ message, type });
    setTimeout(() => setToast(null), 3000);
  }

  async function handleSave(e) {
    e.preventDefault();
    const tonase = Number(form.tonase_kirim);
    if (!form.pabrik_id || !tonase || tonase <= 0) return;

    setSaving(true);
    const { error } = await supabase.rpc('create_pengiriman_lokal', {
      p_tanggal: form.tanggal,
      p_pabrik_id: form.pabrik_id,
      p_tonase_kirim_kg: tonase,
      p_nomor_do: form.nomor_do || null,
      p_sopir_id: form.sopir_id || null,
      p_kendaraan_id: form.kendaraan_id || null,
    });

    setSaving(false);

    if (error) {
      showToast(`Gagal menyimpan pengiriman: ${error.message}`, 'error');
      return;
    }

    setShowModal(false);
    setForm({ tanggal: getTodayISO(), sopir_id: '', kendaraan_id: '', pabrik_id: '', tonase_kirim: '', nomor_do: '' });
    showToast('Pengiriman lokal berhasil dibuat dan stok sudah dialokasikan FIFO.');
    await loadAll();
  }

  function openUpdateModal(pengiriman) {
    setShowUpdateModal(pengiriman);
    setUpdateForm({
      status: ['dikirim', 'stok_siap_kirim'].includes(pengiriman.status) ? 'diterima_pabrik' : 'dibayar_pabrik',
      tonase_pabrik: String(pengiriman.tonase_pabrik || pengiriman.tonase_timbang_sumber || pengiriman.tonase_kirim || ''),
      harga_pabrik_per_kg: String(pengiriman.harga_pabrik_per_kg || ''),
      potongan_sortasi_type: pengiriman.potongan_sortasi_type || 'none',
      potongan_sortasi_value: String(pengiriman.potongan_sortasi_value || ''),
      biaya_timbang: String(pengiriman.biaya_timbang || ''),
      potongan_pabrik_lain: String(pengiriman.potongan_pabrik_lain || ''),
      tanggal_bayar: pengiriman.tanggal_bayar || getTodayISO(),
    });
  }

  async function handleUpdate(e) {
    e.preventDefault();
    if (!showUpdateModal) return;

    const nilai = hitungNilaiPabrik(updateForm);
    const tonasePabrik = Number(updateForm.tonase_pabrik || 0);
    const hargaPabrik = Number(updateForm.harga_pabrik_per_kg || 0);
    const payload = {
      status: updateForm.status,
      tonase_pabrik: tonasePabrik || null,
      tonase_dasar_settlement: nilai.tonaseDasar || null,
      updated_at: new Date().toISOString(),
    };

    if (updateForm.status === 'dibayar_pabrik') {
      if (tonasePabrik <= 0 || hargaPabrik <= 0) {
        showToast('Tonase pabrik dan harga pabrik wajib diisi sebelum status dibayar.', 'error');
        return;
      }

      payload.harga_pabrik_per_kg = hargaPabrik;
      payload.potongan_sortasi_type = updateForm.potongan_sortasi_type;
      payload.potongan_sortasi_value = Number(updateForm.potongan_sortasi_value || 0);
      payload.potongan_sortasi_rupiah = nilai.sortasiRupiah;
      payload.biaya_timbang = Number(updateForm.biaya_timbang || 0);
      payload.potongan_pabrik_lain = Number(updateForm.potongan_pabrik_lain || 0);
      payload.total_pembayaran_pabrik = nilai.totalPembayaran;
      payload.total_harga_pabrik = nilai.totalPembayaran;
      payload.tanggal_bayar = updateForm.tanggal_bayar || getTodayISO();
    }

    setSaving(true);
    const { error } = await supabase
      .from('pengiriman')
      .update(payload)
      .eq('id', showUpdateModal.id);
    setSaving(false);

    if (error) {
      showToast(`Gagal update pengiriman: ${error.message}`, 'error');
      return;
    }

    setShowUpdateModal(null);
    showToast('Status pengiriman berhasil diperbarui.');
    await loadAll();
  }

  const filtered = filter === 'semua' ? list : list.filter((item) => item.status === filter);

  return (
    <AppShell title="Pengiriman Lokal" subtitle="Kelola pengiriman TBS lokal ke pabrik per DO">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <div>
          <h2 className="page-title">Pengiriman Lokal ke Pabrik</h2>
          <p className="text-tertiary text-sm">Sisa stok lokal: <strong className="text-mono">{formatNumber(stokSaldo)} kg</strong></p>
        </div>
        <button className="btn btn-primary" onClick={() => setShowModal(true)}>Pengiriman Baru</button>
      </div>

      <div className="tabs">
        {[
          { key: 'semua', label: 'Semua' },
          { key: 'dikirim', label: 'Dikirim' },
          { key: 'diterima_pabrik', label: 'Diterima' },
          { key: 'dibayar_pabrik', label: 'Dibayar' },
          { key: 'selesai', label: 'Selesai' },
        ].map((item) => (
          <button key={item.key} className={`tab ${filter === item.key ? 'active' : ''}`} onClick={() => setFilter(item.key)}>
            {item.label} ({item.key === 'semua' ? list.length : list.filter((row) => row.status === item.key).length})
          </button>
        ))}
      </div>

      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {[1, 2, 3].map((item) => <div key={item} className="skeleton" style={{ height: 52 }} />)}
        </div>
      ) : filtered.length === 0 ? (
        <div className="empty-state">
          <div className="empty-state-title">Belum ada pengiriman</div>
        </div>
      ) : (
        <div className="table-container">
          <table className="table">
            <thead>
              <tr>
                <th>Tanggal</th>
                <th>Sopir</th>
                <th>Kendaraan</th>
                <th>Pabrik</th>
                <th style={{ textAlign: 'right' }}>Tonase kirim</th>
                <th>No DO</th>
                <th>Status</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((pengiriman) => {
                const allocations = allocationsByPengiriman[pengiriman.id] || [];
                return (
                  <tr key={pengiriman.id}>
                    <td>{new Date(pengiriman.tanggal).toLocaleDateString('id-ID')}</td>
                    <td>{pengiriman.sopir?.nama || '-'}</td>
                    <td className="table-mono">{pengiriman.kendaraan?.plat_nomor || '-'}</td>
                    <td>{pengiriman.pabrik?.nama || '-'}</td>
                    <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(pengiriman.tonase_timbang_sumber || pengiriman.tonase_kirim)} kg</td>
                    <td className="table-mono">{pengiriman.nomor_do || pengiriman.no_do || '-'}</td>
                    <td><span className={`badge ${getStatusBadgeClass(pengiriman.status)}`}>{getStatusLabel(pengiriman.status)}</span></td>
                    <td>
                      <div className="flex gap-xs">
                        {allocations.length > 0 && (
                          <button className="btn btn-ghost btn-sm" onClick={() => setDetailTarget(pengiriman)}>Alokasi</button>
                        )}
                        {!['dibayar_pabrik', 'dibayar', 'selesai', 'dibatalkan'].includes(pengiriman.status) && (
                          <button className="btn btn-ghost btn-sm" onClick={() => openUpdateModal(pengiriman)}>Update</button>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Pengiriman Lokal Baru</h3>
              <button className="modal-close" onClick={() => setShowModal(false)}>x</button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                <div className="alert alert-info" style={{ marginBottom: 'var(--space-md)' }}>
                  Stok tersedia saat ini: <strong className="text-mono">{formatNumber(stokSaldo)} kg</strong>
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Tanggal</label>
                  <input
                    type="date"
                    className="form-input"
                    value={form.tanggal}
                    onChange={(e) => setForm({ ...form, tanggal: e.target.value })}
                    required
                  />
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label">Sopir</label>
                    <select
                      className="form-input form-select"
                      value={form.sopir_id}
                      onChange={(e) => setForm({ ...form, sopir_id: e.target.value })}
                    >
                      <option value="">-- Pilih --</option>
                      {sopirList.map((sopir) => <option key={sopir.id} value={sopir.id}>{sopir.nama}</option>)}
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Kendaraan</label>
                    <select
                      className="form-input form-select"
                      value={form.kendaraan_id}
                      onChange={(e) => setForm({ ...form, kendaraan_id: e.target.value })}
                    >
                      <option value="">-- Pilih --</option>
                      {kendaraanList.map((kendaraan) => <option key={kendaraan.id} value={kendaraan.id}>{kendaraan.plat_nomor}</option>)}
                    </select>
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Pabrik Tujuan</label>
                  <select
                    className="form-input form-select"
                    value={form.pabrik_id}
                    onChange={(e) => setForm({ ...form, pabrik_id: e.target.value })}
                    required
                  >
                    <option value="">-- Pilih --</option>
                    {pabrikList.map((pabrik) => <option key={pabrik.id} value={pabrik.id}>{pabrik.nama}</option>)}
                  </select>
                </div>
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Tonase kirim (kg)</label>
                    <input
                      type="number"
                      className="form-input form-input-mono"
                      value={form.tonase_kirim}
                      onChange={(e) => setForm({ ...form, tonase_kirim: e.target.value })}
                      min={0.01}
                      step={0.01}
                      required
                    />
                    {Number(form.tonase_kirim || 0) > stokSaldo && (
                      <div className="form-hint text-danger">Tonase melebihi stok tersedia.</div>
                    )}
                  </div>
                  <div className="form-group">
                    <label className="form-label">No. DO / Surat Jalan</label>
                    <input
                      className="form-input"
                      value={form.nomor_do}
                      onChange={(e) => setForm({ ...form, nomor_do: e.target.value })}
                    />
                  </div>
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" onClick={() => setShowModal(false)}>Batal</button>
                <button
                  type="submit"
                  className="btn btn-primary"
                  disabled={saving || Number(form.tonase_kirim || 0) <= 0 || Number(form.tonase_kirim || 0) > stokSaldo}
                >
                  {saving ? 'Menyimpan...' : 'Simpan'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {showUpdateModal && (
        <div className="modal-overlay" onClick={() => setShowUpdateModal(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Update Status Pengiriman</h3>
              <button className="modal-close" onClick={() => setShowUpdateModal(null)}>x</button>
            </div>
            <form onSubmit={handleUpdate}>
              <div className="modal-body">
                <div className="alert alert-info" style={{ marginBottom: 16 }}>
                  <span>DO: <strong>{showUpdateModal.nomor_do || showUpdateModal.no_do || '-'}</strong> / {showUpdateModal.pabrik?.nama || '-'}</span>
                </div>
                <div className="form-group">
                  <label className="form-label">Status baru</label>
                  <select
                    className="form-input form-select"
                    value={updateForm.status}
                    onChange={(e) => setUpdateForm({ ...updateForm, status: e.target.value })}
                  >
                    <option value="diterima_pabrik">Diterima pabrik</option>
                    <option value="dibayar_pabrik">Dibayar pabrik</option>
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Tonase final pabrik (kg)</label>
                  <input
                    type="number"
                    className="form-input form-input-mono"
                    value={updateForm.tonase_pabrik}
                    onChange={(e) => setUpdateForm({ ...updateForm, tonase_pabrik: e.target.value })}
                    min={0}
                    step={0.01}
                  />
                </div>

                {updateForm.status === 'dibayar_pabrik' && (
                  <>
                    <div className="form-group">
                      <label className="form-label form-label-required">Harga pabrik /kg (Rp)</label>
                      <input
                        type="number"
                        className="form-input form-input-mono"
                        value={updateForm.harga_pabrik_per_kg}
                        onChange={(e) => setUpdateForm({ ...updateForm, harga_pabrik_per_kg: e.target.value })}
                        required
                        min={0}
                      />
                    </div>
                    <div className="form-grid">
                      <div className="form-group">
                        <label className="form-label">Tipe sortasi/grading</label>
                        <select
                          className="form-input form-select"
                          value={updateForm.potongan_sortasi_type}
                          onChange={(e) => setUpdateForm({ ...updateForm, potongan_sortasi_type: e.target.value, potongan_sortasi_value: '' })}
                        >
                          <option value="none">Tidak ada</option>
                          <option value="kg">Kg</option>
                          <option value="percent">Persentase</option>
                          <option value="nominal">Nominal rupiah</option>
                        </select>
                      </div>
                      <div className="form-group">
                        <label className="form-label">Nilai sortasi</label>
                        <input
                          type="number"
                          className="form-input form-input-mono"
                          value={updateForm.potongan_sortasi_value}
                          onChange={(e) => setUpdateForm({ ...updateForm, potongan_sortasi_value: e.target.value })}
                          min={0}
                          step={0.01}
                          disabled={updateForm.potongan_sortasi_type === 'none'}
                        />
                      </div>
                    </div>
                    <div className="form-grid">
                      <div className="form-group">
                        <label className="form-label">Biaya timbang</label>
                        <input
                          type="number"
                          className="form-input form-input-mono"
                          value={updateForm.biaya_timbang}
                          onChange={(e) => setUpdateForm({ ...updateForm, biaya_timbang: e.target.value })}
                          min={0}
                        />
                      </div>
                      <div className="form-group">
                        <label className="form-label">Potongan pabrik lain</label>
                        <input
                          type="number"
                          className="form-input form-input-mono"
                          value={updateForm.potongan_pabrik_lain}
                          onChange={(e) => setUpdateForm({ ...updateForm, potongan_pabrik_lain: e.target.value })}
                          min={0}
                        />
                      </div>
                    </div>
                    <div className="form-group">
                      <label className="form-label">Tanggal bayar pabrik</label>
                      <input
                        type="date"
                        className="form-input"
                        value={updateForm.tanggal_bayar}
                        onChange={(e) => setUpdateForm({ ...updateForm, tanggal_bayar: e.target.value })}
                      />
                    </div>
                    <div className="calc-result">
                      <div className="calc-result-row">
                        <span className="calc-result-label">Tonase dasar</span>
                        <span className="calc-result-value">{formatNumber(estimasiPabrik.tonaseDasar)} kg</span>
                      </div>
                      <div className="calc-result-row">
                        <span className="calc-result-label">Bruto pabrik</span>
                        <span className="calc-result-value">{formatRupiah(estimasiPabrik.bruto)}</span>
                      </div>
                      <div className="calc-result-row">
                        <span className="calc-result-label">Sortasi rupiah</span>
                        <span className="calc-result-value text-danger">{formatRupiah(estimasiPabrik.sortasiRupiah)}</span>
                      </div>
                      <div className="calc-result-row">
                        <span className="calc-result-label" style={{ fontWeight: 600 }}>Nilai final DO</span>
                        <span className="calc-result-value calc-result-total">{formatRupiah(estimasiPabrik.totalPembayaran)}</span>
                      </div>
                    </div>
                  </>
                )}
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" onClick={() => setShowUpdateModal(null)}>Batal</button>
                <button type="submit" className="btn btn-primary" disabled={saving}>{saving ? 'Menyimpan...' : 'Update'}</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {detailTarget && (
        <div className="modal-overlay" onClick={() => setDetailTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Alokasi Stok DO {detailTarget.nomor_do || detailTarget.no_do || '-'}</h3>
              <button className="modal-close" onClick={() => setDetailTarget(null)}>x</button>
            </div>
            <div className="modal-body">
              <div className="table-container" style={{ border: 'none' }}>
                <table className="table">
                  <thead>
                    <tr>
                      <th>Struk</th>
                      <th>Petani</th>
                      <th style={{ textAlign: 'right' }}>Berat alokasi</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(allocationsByPengiriman[detailTarget.id] || []).map((detail) => (
                      <tr key={detail.id}>
                        <td className="table-mono">{detail.transaksi_beli?.no_struk || '-'}</td>
                        <td>{detail.petani?.nama || '-'}</td>
                        <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(detail.berat_alokasi_kg)} kg</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-outline" onClick={() => setDetailTarget(null)}>Tutup</button>
            </div>
          </div>
        </div>
      )}
    </AppShell>
  );
}
