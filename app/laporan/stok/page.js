'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { canManageBusinessSettings, normalizeRole } from '@/lib/roles';
import { exportToExcel } from '@/lib/export';
import { formatNumber, getTodayISO } from '@/lib/utils';

function getMonthStartISO(dateValue) {
  const date = new Date(dateValue);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}-01`;
}

function getSignedBerat(row) {
  const berat = Number(row.berat_kg || 0);

  if (row.tipe === 'masuk') return Math.abs(berat);
  if (row.tipe === 'keluar') return -Math.abs(berat);
  return berat;
}

function getTipeLabel(row) {
  const labels = {
    masuk: 'Masuk',
    keluar: 'Keluar',
    koreksi: 'Koreksi',
    reversal: 'Reversal',
  };

  return labels[row.tipe] || row.tipe || '-';
}

function getSumberLabel(row) {
  const labels = {
    pembelian_petani: 'Pembelian Petani',
    pengiriman_pabrik: 'Pengiriman Pabrik',
    koreksi_manual: 'Koreksi Manual',
    reversal: 'Reversal',
  };

  return labels[row.sumber] || row.sumber || '-';
}

export default function LaporanStokPage() {
  const today = getTodayISO();
  const [tanggalAwal, setTanggalAwal] = useState(getMonthStartISO(today));
  const [tanggalAkhir, setTanggalAkhir] = useState(today);
  const [ledger, setLedger] = useState([]);
  const [saldoRows, setSaldoRows] = useState([]);
  const [userRole, setUserRole] = useState('admin_operasional');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showKoreksi, setShowKoreksi] = useState(false);
  const [toast, setToast] = useState(null);
  const [form, setForm] = useState({
    arah: 'tambah',
    berat_kg: '',
    keterangan: '',
  });

  const canAdjustStock = canManageBusinessSettings(userRole);

  const saldoAkhir = useMemo(() => {
    return saldoRows.reduce((total, row) => total + getSignedBerat(row), 0);
  }, [saldoRows]);

  const summary = useMemo(() => {
    return ledger.reduce((acc, row) => {
      const signed = getSignedBerat(row);

      if (row.tipe === 'masuk') acc.masuk += Math.abs(signed);
      if (row.tipe === 'keluar') acc.keluar += Math.abs(signed);
      if (row.tipe === 'koreksi' || row.tipe === 'reversal') acc.koreksi += signed;

      return acc;
    }, { masuk: 0, keluar: 0, koreksi: 0 });
  }, [ledger]);

  const loadData = useCallback(async () => {
    setLoading(true);

    const { data: { session } } = await supabase.auth.getSession();
    if (session?.user?.id) {
      const { data: userData } = await supabase
        .from('users')
        .select('role')
        .eq('id', session.user.id)
        .maybeSingle();
      setUserRole(normalizeRole(userData?.role));
    }

    const [{ data: periodRows, error: periodError }, { data: allRowsToEnd, error: saldoError }] = await Promise.all([
      supabase
        .from('stok_tbs_lokal_ledger')
        .select('*, transaksi_beli:transaksi_beli_id(no_struk, petani:petani_id(nama))')
        .gte('tanggal', tanggalAwal)
        .lte('tanggal', tanggalAkhir)
        .order('tanggal', { ascending: false })
        .order('created_at', { ascending: false }),
      supabase
        .from('stok_tbs_lokal_ledger')
        .select('tipe, berat_kg')
        .lte('tanggal', tanggalAkhir),
    ]);

    if (periodError || saldoError) {
      setToast({ type: 'error', message: periodError?.message || saldoError?.message });
    }

    setLedger(periodRows || []);
    setSaldoRows(allRowsToEnd || []);
    setLoading(false);
  }, [tanggalAwal, tanggalAkhir]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  async function handleKoreksi(e) {
    e.preventDefault();
    if (!canAdjustStock) return;

    const berat = Number(form.berat_kg);
    if (!berat || berat <= 0) return;

    const signedBerat = form.arah === 'tambah' ? berat : -berat;
    const saldoSetelah = saldoAkhir + signedBerat;

    if (saldoSetelah < 0) {
      const lanjut = window.confirm(
        `Koreksi ini membuat stok menjadi minus ${formatNumber(saldoSetelah)} kg.\n\nLanjutkan sebagai koreksi khusus?`
      );
      if (!lanjut) return;
    }

    setSaving(true);
    const { data: { session } } = await supabase.auth.getSession();
    const { error } = await supabase.from('stok_tbs_lokal_ledger').insert({
      tanggal: getTodayISO(),
      tipe: 'koreksi',
      sumber: 'koreksi_manual',
      berat_kg: signedBerat,
      keterangan: form.keterangan || null,
      created_by: session?.user?.id || null,
    });

    setSaving(false);

    if (error) {
      setToast({ type: 'error', message: `Gagal menyimpan koreksi: ${error.message}` });
      return;
    }

    setShowKoreksi(false);
    setForm({ arah: 'tambah', berat_kg: '', keterangan: '' });
    setToast({ type: 'success', message: 'Koreksi stok berhasil disimpan.' });
    setTimeout(() => setToast(null), 3000);
    await loadData();
  }

  function exportStok() {
    exportToExcel(
      ledger.map((row) => ({
        ...row,
        tipe_label: getTipeLabel(row),
        sumber_label: getSumberLabel(row),
        signed_berat: getSignedBerat(row),
        no_struk: row.transaksi_beli?.no_struk || '-',
        petani: row.transaksi_beli?.petani?.nama || '-',
      })),
      [
        { key: 'tanggal', label: 'Tanggal', format: (value) => new Date(value).toLocaleDateString('id-ID') },
        { key: 'tipe_label', label: 'Tipe' },
        { key: 'sumber_label', label: 'Sumber' },
        { key: 'signed_berat', label: 'Berat Signed (kg)' },
        { key: 'no_struk', label: 'No Struk' },
        { key: 'petani', label: 'Petani' },
        { key: 'keterangan', label: 'Keterangan' },
      ],
      `Laporan_Stok_${tanggalAwal}_${tanggalAkhir}`,
      'Stok Lokal'
    );
  }

  return (
    <AppShell title="Laporan Stok Lokal" subtitle="Rekonsiliasi TBS lokal masuk, keluar, koreksi, dan sisa stok">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header" style={{ justifyContent: 'flex-end' }}>
        <div className="flex gap-sm">
          <button className="btn btn-outline btn-sm" onClick={exportStok}>Export Excel</button>
          {canAdjustStock && (
            <button className="btn btn-primary btn-sm" onClick={() => setShowKoreksi(true)}>Koreksi Stok</button>
          )}
        </div>
      </div>

      <div className="card" style={{ marginBottom: 'var(--space-lg)' }}>
        <div className="form-grid">
          <div className="form-group">
            <label className="form-label">Tanggal awal</label>
            <input
              type="date"
              className="form-input"
              value={tanggalAwal}
              onChange={(e) => setTanggalAwal(e.target.value)}
            />
          </div>
          <div className="form-group">
            <label className="form-label">Tanggal akhir</label>
            <input
              type="date"
              className="form-input"
              value={tanggalAkhir}
              onChange={(e) => setTanggalAkhir(e.target.value)}
            />
          </div>
        </div>
      </div>

      <div className="stats-grid" style={{ marginBottom: 'var(--space-lg)' }}>
        <div className="stat-card">
          <div className="stat-label">Masuk periode</div>
          <div className="stat-value text-success">{formatNumber(summary.masuk)} kg</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Keluar periode</div>
          <div className="stat-value text-danger">{formatNumber(summary.keluar)} kg</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Koreksi periode</div>
          <div className={`stat-value ${summary.koreksi < 0 ? 'text-danger' : 'text-warning'}`}>{formatNumber(summary.koreksi)} kg</div>
        </div>
        <div className="stat-card">
          <div className="stat-label">Sisa stok sampai {new Date(tanggalAkhir).toLocaleDateString('id-ID')}</div>
          <div className={`stat-value ${saldoAkhir < 0 ? 'text-danger' : 'text-primary'}`}>{formatNumber(saldoAkhir)} kg</div>
        </div>
      </div>

      <div className="card">
        <div className="card-header">
          <span className="card-title">Riwayat Ledger Stok</span>
          <span className="badge badge-neutral">{ledger.length}</span>
        </div>
        {loading ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {[1, 2, 3, 4].map((item) => <div key={item} className="skeleton" style={{ height: 44 }} />)}
          </div>
        ) : ledger.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-xl)' }}>
            <div className="empty-state-title">Belum ada pergerakan stok pada periode ini</div>
          </div>
        ) : (
          <div className="table-container" style={{ border: 'none' }}>
            <table className="table">
              <thead>
                <tr>
                  <th>Tanggal</th>
                  <th>Tipe</th>
                  <th>Sumber</th>
                  <th>Referensi</th>
                  <th style={{ textAlign: 'right' }}>Berat</th>
                  <th>Keterangan</th>
                </tr>
              </thead>
              <tbody>
                {ledger.map((row) => {
                  const signed = getSignedBerat(row);
                  return (
                    <tr key={row.id}>
                      <td>{new Date(row.tanggal).toLocaleDateString('id-ID')}</td>
                      <td>
                        <span className={`badge ${signed < 0 ? 'badge-danger' : row.tipe === 'koreksi' ? 'badge-warning' : 'badge-success'}`}>
                          {getTipeLabel(row)}
                        </span>
                      </td>
                      <td>{getSumberLabel(row)}</td>
                      <td>
                        {row.transaksi_beli?.no_struk || '-'}
                        {row.transaksi_beli?.petani?.nama ? ` / ${row.transaksi_beli.petani.nama}` : ''}
                      </td>
                      <td className={`table-mono ${signed < 0 ? 'text-danger' : 'text-success'}`} style={{ textAlign: 'right' }}>
                        {signed > 0 ? '+' : ''}{formatNumber(signed)} kg
                      </td>
                      <td>{row.keterangan || '-'}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {showKoreksi && (
        <div className="modal-overlay" onClick={() => setShowKoreksi(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Koreksi Stok Lokal</h3>
              <button className="modal-close" onClick={() => setShowKoreksi(false)}>x</button>
            </div>
            <form onSubmit={handleKoreksi}>
              <div className="modal-body">
                <div className="alert alert-warning" style={{ marginBottom: 'var(--space-md)' }}>
                  Saldo saat ini sampai tanggal akhir filter: <strong className="text-mono">{formatNumber(saldoAkhir)} kg</strong>
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Arah koreksi</label>
                  <select
                    className="form-input form-select"
                    value={form.arah}
                    onChange={(e) => setForm({ ...form, arah: e.target.value })}
                  >
                    <option value="tambah">Tambah stok</option>
                    <option value="kurang">Kurangi stok</option>
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Berat koreksi (kg)</label>
                  <input
                    type="number"
                    className="form-input form-input-mono"
                    min={0.01}
                    step={0.01}
                    value={form.berat_kg}
                    onChange={(e) => setForm({ ...form, berat_kg: e.target.value })}
                    required
                  />
                </div>
                <div className="form-group">
                  <label className="form-label form-label-required">Keterangan</label>
                  <input
                    className="form-input"
                    value={form.keterangan}
                    onChange={(e) => setForm({ ...form, keterangan: e.target.value })}
                    placeholder="Contoh: koreksi selisih timbang"
                    required
                  />
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" onClick={() => setShowKoreksi(false)}>Batal</button>
                <button type="submit" className="btn btn-primary" disabled={saving}>{saving ? 'Menyimpan...' : 'Simpan Koreksi'}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AppShell>
  );
}
