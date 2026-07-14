'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import AppShell from '@/components/layout/AppShell';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import { Search } from 'lucide-react';
import { formatMitraLabel, getMitraSearchText } from '@/lib/display-labels';
import { paginateRows } from '@/lib/pagination-utils';
import { getNextSort, sortRows } from '@/lib/sort-utils';
import { supabase } from '@/lib/supabase';
import { formatDateDisplay, formatRupiah } from '@/lib/utils';

const TABLE_PAGE_SIZE = 20;

const panjarSortAccessors = {
  tanggal: row => row.tanggal,
  mitra: row => formatMitraLabel(row.master_mitra),
  keterangan: row => row.keterangan,
  jumlah: row => Number(row.jumlah),
  status: row => row.status,
};

export default function PanjarMitraPage() {
  const [panjars, setPanjars] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState({ key: 'tanggal', direction: 'desc' });
  const [page, setPage] = useState(1);

  useEffect(() => {
    loadData();
  }, []);

  async function loadData() {
    setLoading(true);

    const { data } = await supabase
      .from('panjar_mitra')
      .select(`
        *,
        master_mitra ( kode, alamat, nama )
      `)
      .neq('status', 'dibatalkan')
      .order('tanggal', { ascending: false });

    setPanjars(data || []);
    setLoading(false);
  }

  async function handleLunasi(id) {
    const alasan = prompt('Alasan pelunasan manual panjar:');
    if (!alasan || !alasan.trim()) return;

    const { error } = await supabase.rpc('settle_panjar_mitra_manual', {
      p_panjar_id: id,
      p_alasan: alasan.trim(),
    });

    if (error) {
      alert('Gagal melunasi panjar: ' + error.message);
      return;
    }

    loadData();
  }

  async function handleCancel(id) {
    const alasan = prompt('Alasan pembatalan panjar:');
    if (!alasan || !alasan.trim()) return;

    const { error } = await supabase.rpc('cancel_panjar_mitra_kas', {
      p_panjar_id: id,
      p_alasan: alasan.trim(),
    });

    if (error) {
      alert('Gagal membatalkan panjar: ' + error.message);
      return;
    }

    loadData();
  }

  function handleSort(key) {
    setPage(1);
    setSort(current => getNextSort(current, key, key === 'tanggal' ? 'desc' : 'asc'));
  }

  const filteredPanjars = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return panjars;
    return panjars.filter(p => getMitraSearchText(p.master_mitra || {}).toLowerCase().includes(keyword));
  }, [panjars, search]);

  const sortedPanjars = useMemo(() => {
    return sortRows(filteredPanjars, sort, panjarSortAccessors);
  }, [filteredPanjars, sort]);

  const paginatedPanjars = useMemo(() => {
    return paginateRows(sortedPanjars, page, TABLE_PAGE_SIZE);
  }, [page, sortedPanjars]);

  return (
    <AppShell title="Arsip Panjar Mitra" subtitle="Pantau panjar mitra dari Hutang & Panjar">
      <div className="page-header">
        <div>
          <p className="page-description">Input panjar sekarang satu pintu melalui Hutang & Panjar Semua Pihak.</p>
        </div>
        <Link className="btn btn-primary" href="/keuangan/hutang">Input di Hutang & Panjar</Link>
      </div>

      <div className="alert alert-info" style={{ marginBottom: 'var(--space-lg)' }}>
        Halaman ini hanya untuk memantau panjar mitra yang akan dipotong saat kwitansi. Untuk mencatat panjar baru, pilih pihak Mitra dan jenis Panjar di Hutang & Panjar Semua Pihak.
      </div>

      <div className="toolbar">
        <div className="search-box" style={{ flex: 1, maxWidth: 400 }}>
          <span className="search-box-icon"><Search size={16} /></span>
          <input
            type="text"
            className="form-input"
            placeholder="Cari nama mitra..."
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setPage(1);
            }}
            style={{ paddingLeft: 40 }}
          />
        </div>
      </div>

      <div className="table-container">
        <table className="table">
          <thead>
            <tr>
              <SortableHeader label="Tanggal" sortKey="tanggal" sort={sort} onSort={handleSort} />
              <SortableHeader label="Nama Mitra" sortKey="mitra" sort={sort} onSort={handleSort} />
              <SortableHeader label="Keterangan" sortKey="keterangan" sort={sort} onSort={handleSort} />
              <SortableHeader label="Jumlah (Rp)" sortKey="jumlah" sort={sort} onSort={handleSort} align="right" />
              <SortableHeader label="Status" sortKey="status" sort={sort} onSort={handleSort} align="center" />
              <th style={{ textAlign: 'center' }}>Aksi</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={6} style={{ textAlign: 'center', padding: 24 }}>Memuat data...</td></tr>
            ) : sortedPanjars.length === 0 ? (
              <tr><td colSpan={6} style={{ textAlign: 'center', padding: 24 }}>Belum ada data panjar</td></tr>
            ) : (
              paginatedPanjars.rows.map(p => (
                <tr key={p.id}>
                  <td>{formatDateDisplay(p.tanggal)}</td>
                  <td style={{ fontWeight: 600 }}>
                    {p.master_mitra ? formatMitraLabel(p.master_mitra) : '-'}
                  </td>
                  <td>{p.keterangan || '-'}</td>
                  <td className="table-mono" style={{ textAlign: 'right', fontWeight: 'bold' }}>
                    {formatRupiah(p.jumlah)}
                  </td>
                  <td style={{ textAlign: 'center' }}>
                    {p.status === 'belum_lunas' ? (
                      <span className="badge badge-red">Belum Lunas</span>
                    ) : (
                      <span className="badge badge-green">Lunas</span>
                    )}
                  </td>
                  <td style={{ textAlign: 'center' }}>
                    {p.status === 'belum_lunas' ? (
                      <div className="flex gap-xs" style={{ justifyContent: 'center' }}>
                        <button className="btn btn-ghost btn-sm" onClick={() => handleLunasi(p.id)}>Lunasi Manual</button>
                        <button className="btn btn-ghost btn-sm" onClick={() => handleCancel(p.id)}>Batalkan</button>
                      </div>
                    ) : (
                      <span className="text-tertiary">-</span>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
        <TablePagination
          page={paginatedPanjars.page}
          totalPages={paginatedPanjars.totalPages}
          totalItems={sortedPanjars.length}
          startIndex={paginatedPanjars.startIndex}
          endIndex={paginatedPanjars.endIndex}
          onPageChange={setPage}
        />
      </div>
    </AppShell>
  );
}
