'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatDateDisplay, formatNumber } from '@/lib/utils';

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

export default function PengirimanPage() {
  const [list, setList] = useState([]);
  const [allocationsByPengiriman, setAllocationsByPengiriman] = useState({});
  const [stokSaldo, setStokSaldo] = useState(0);
  const [loading, setLoading] = useState(true);
  const [detailTarget, setDetailTarget] = useState(null);
  const [filter, setFilter] = useState('semua');
  const [toast, setToast] = useState(null);

  const loadAll = useCallback(async () => {
    setLoading(true);

    const [{ data: peng, error: pengError }, { data: stokRows }] = await Promise.all([
      supabase
        .from('pengiriman')
        .select('*, sopir:sopir_id(nama), kendaraan:kendaraan_id(plat_nomor), pabrik:pabrik_id(nama)')
        .eq('sumber', 'lokal')
        .order('tanggal', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(50),
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
    setAllocationsByPengiriman(allocations);
    setStokSaldo((stokRows || []).reduce((total, row) => total + getSignedBerat(row), 0));
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadAll();
  }, [loadAll]);

  const filtered = filter === 'semua' ? list : list.filter((item) => item.status === filter);

  return (
    <AppShell title="Pengiriman Lokal Legacy" subtitle="Arsip pengiriman lokal lama. Input baru gunakan Pengiriman Mitra dengan mitra internal.">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <div>
          <p className="text-tertiary text-sm">Sisa stok lokal: <strong className="text-mono">{formatNumber(stokSaldo)} kg</strong></p>
        </div>
        <Link className="btn btn-primary" href="/admin/input-timbangan">Input via Mitra Internal</Link>
      </div>

      <div className="alert alert-info" style={{ marginBottom: 'var(--space-lg)' }}>
        Halaman ini sudah dibekukan sebagai arsip baca-saja untuk data pengiriman lokal lama. Pengiriman hasil pembelian lokal ke pabrik wajib dicatat sebagai mitra internal agar laporan harian, kwitansi, dan dashboard memakai sumber data yang sama.
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
                    <td>{formatDateDisplay(pengiriman.tanggal)}</td>
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
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
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
