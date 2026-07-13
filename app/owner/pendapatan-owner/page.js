'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, BadgeDollarSign, Printer, ReceiptText, Scale } from 'lucide-react';
import AppShell from '@/components/layout/AppShell';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import {
  MITRA_TYPES,
  formatMitraLabel,
  getMitraSearchText,
  getMitraTypeBadgeClass,
  getMitraTypeLabel,
} from '@/lib/display-labels';
import { paginateRows } from '@/lib/pagination-utils';
import { canViewProfit, normalizeRole } from '@/lib/roles';
import { getNextSort, sortRows } from '@/lib/sort-utils';
import { supabase } from '@/lib/supabase';
import { formatNumber, formatRupiah, getTodayISO } from '@/lib/utils';

const TABLE_PAGE_SIZE = 20;

function toNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function hasFeeSnapshot(row) {
  return row.fee_owner_per_kg != null || row.total_fee_owner != null;
}

function resolveFeePerKg(row) {
  const tonase = toNumber(row.tonase);

  if (row.fee_owner_per_kg != null) return toNumber(row.fee_owner_per_kg);
  if (row.total_fee_owner != null && tonase > 0) return toNumber(row.total_fee_owner) / tonase;
  if (row.harga_pabrik_per_kg != null && row.harga_bersih_per_kg != null) {
    return Math.max(0, toNumber(row.harga_pabrik_per_kg) - toNumber(row.harga_bersih_per_kg));
  }

  return 0;
}

function resolveTotalFeeOwner(row) {
  if (row.total_fee_owner != null) return toNumber(row.total_fee_owner);
  return Math.round(toNumber(row.tonase) * resolveFeePerKg(row));
}

function resolveHargaPabrik(row) {
  if (row.harga_pabrik_per_kg != null) return toNumber(row.harga_pabrik_per_kg);

  const feePerKg = resolveFeePerKg(row);
  const hargaBersih = row.harga_bersih_per_kg ?? row.harga_harian;

  if (hargaBersih != null && feePerKg > 0) return toNumber(hargaBersih) + feePerKg;
  return null;
}

function resolveNilaiPabrik(row) {
  const hargaPabrik = resolveHargaPabrik(row);
  if (hargaPabrik == null) return null;
  return Math.round(toNumber(row.tonase) * hargaPabrik);
}

function resolveNilaiBersihMitra(row) {
  return toNumber(row.total_nilai_bersih ?? row.total_kotor);
}

export default function PendapatanOwnerPage() {
  const [dateFrom, setDateFrom] = useState(getTodayISO);
  const [dateTo, setDateTo] = useState(getTodayISO);
  const [selectedMitra, setSelectedMitra] = useState('');
  const [selectedTipeMitra, setSelectedTipeMitra] = useState('semua');
  const [mitras, setMitras] = useState([]);
  const [transaksi, setTransaksi] = useState([]);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [userRole, setUserRole] = useState(null);
  const [summarySort, setSummarySort] = useState({ key: 'pendapatan', direction: 'desc' });
  const [detailSort, setDetailSort] = useState({ key: 'tanggal', direction: 'desc' });
  const [summaryPage, setSummaryPage] = useState(1);
  const [detailPage, setDetailPage] = useState(1);

  const checkRole = useCallback(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return;

    const { data: user } = await supabase
      .from('users')
      .select('role')
      .eq('id', session.user.id)
      .single();

    setUserRole(normalizeRole(user?.role));
  }, []);

  const loadMitras = useCallback(async () => {
    const { data } = await supabase
      .from('master_mitra')
      .select('id, kode, alamat, nama, penanggung_jawab, no_hp, tipe_mitra')
      .eq('aktif', true)
      .order('kode');

    setMitras(data || []);
  }, []);

  const loadLaporan = useCallback(async () => {
    setLoading(true);
    setErrorMsg('');

    let query = supabase
      .from('transaksi_mitra')
      .select(`
        id, mitra_id, tanggal, tonase, harga_harian, total_kotor,
        harga_pabrik_per_kg, fee_owner_per_kg, harga_bersih_per_kg,
        total_fee_owner, total_nilai_bersih, plat_nomor,
        sopir_aktual_nama, sopir_default_nama,
        master_mitra ( kode, alamat, nama, tipe_mitra )
      `)
      .gte('tanggal', dateFrom)
      .lte('tanggal', dateTo)
      .neq('status', 'dibatalkan');

    if (selectedMitra) {
      query = query.eq('mitra_id', selectedMitra);
    }

    const { data, error } = await query.order('tanggal', { ascending: false });

    if (error) {
      console.error('Gagal memuat pendapatan owner:', error);
      setTransaksi([]);
      setErrorMsg(error.message);
      setLoading(false);
      return;
    }

    setTransaksi(data || []);
    setLoading(false);
  }, [dateFrom, dateTo, selectedMitra]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    checkRole();
  }, [checkRole]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadMitras();
  }, [loadMitras]);

  useEffect(() => {
    if (userRole && canViewProfit(userRole) && dateFrom && dateTo) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      loadLaporan();
    }
  }, [dateFrom, dateTo, loadLaporan, userRole]);

  const filteredTransaksi = useMemo(() => {
    if (selectedTipeMitra === 'semua') return transaksi;
    return transaksi.filter((row) => (row.master_mitra?.tipe_mitra || MITRA_TYPES.EKSTERNAL) === selectedTipeMitra);
  }, [selectedTipeMitra, transaksi]);

  const summary = useMemo(() => {
    const totalTonase = filteredTransaksi.reduce((sum, row) => sum + toNumber(row.tonase), 0);
    const totalPendapatanOwner = filteredTransaksi.reduce((sum, row) => sum + resolveTotalFeeOwner(row), 0);
    const totalNilaiBersihMitra = filteredTransaksi.reduce((sum, row) => sum + resolveNilaiBersihMitra(row), 0);
    const totalNilaiPabrik = filteredTransaksi.reduce((sum, row) => sum + (resolveNilaiPabrik(row) ?? 0), 0);
    const missingSnapshots = filteredTransaksi.filter((row) => !hasFeeSnapshot(row)).length;

    return {
      totalTonase,
      totalPendapatanOwner,
      totalNilaiBersihMitra,
      totalNilaiPabrik,
      rataFeeOwner: totalTonase > 0 ? totalPendapatanOwner / totalTonase : 0,
      jumlahTransaksi: filteredTransaksi.length,
      missingSnapshots,
    };
  }, [filteredTransaksi]);

  const feeBreakdown = useMemo(() => {
    const grouped = new Map();

    filteredTransaksi.forEach((row) => {
      const feePerKg = resolveFeePerKg(row);
      const key = String(feePerKg);
      const current = grouped.get(key) || {
        feePerKg,
        tonase: 0,
        jumlahTransaksi: 0,
        pendapatanOwner: 0,
      };

      current.tonase += toNumber(row.tonase);
      current.jumlahTransaksi += 1;
      current.pendapatanOwner += resolveTotalFeeOwner(row);
      grouped.set(key, current);
    });

    return Array.from(grouped.values())
      .sort((a, b) => b.feePerKg - a.feePerKg);
  }, [filteredTransaksi]);

  const positiveFeeBreakdown = feeBreakdown.filter(item => item.feePerKg > 0);
  const zeroFeeBreakdown = feeBreakdown.find(item => item.feePerKg === 0);

  const ringkasanMitra = useMemo(() => {
    const grouped = new Map();

    filteredTransaksi.forEach((row) => {
      const key = row.mitra_id || 'tanpa-mitra';
      const current = grouped.get(key) || {
        key,
        label: formatMitraLabel(row.master_mitra) || 'Tanpa mitra',
        tipeMitra: row.master_mitra?.tipe_mitra || MITRA_TYPES.EKSTERNAL,
        jumlahTransaksi: 0,
        tonase: 0,
        nilaiPabrik: 0,
        nilaiBersihMitra: 0,
        pendapatanOwner: 0,
        missingSnapshots: 0,
      };

      current.jumlahTransaksi += 1;
      current.tonase += toNumber(row.tonase);
      current.nilaiPabrik += resolveNilaiPabrik(row) ?? 0;
      current.nilaiBersihMitra += resolveNilaiBersihMitra(row);
      current.pendapatanOwner += resolveTotalFeeOwner(row);
      current.missingSnapshots += hasFeeSnapshot(row) ? 0 : 1;

      grouped.set(key, current);
    });

    return Array.from(grouped.values());
  }, [filteredTransaksi]);

  const sortedRingkasanMitra = useMemo(() => {
    return sortRows(ringkasanMitra, summarySort, {
      mitra: row => row.label,
      tipe: row => getMitraTypeLabel(row.tipeMitra),
      transaksi: row => row.jumlahTransaksi,
      tonase: row => row.tonase,
      nilai_pabrik: row => row.nilaiPabrik,
      nilai_bersih: row => row.nilaiBersihMitra,
      pendapatan: row => row.pendapatanOwner,
    });
  }, [ringkasanMitra, summarySort]);

  const paginatedRingkasanMitra = useMemo(() => {
    return paginateRows(sortedRingkasanMitra, summaryPage, TABLE_PAGE_SIZE);
  }, [sortedRingkasanMitra, summaryPage]);

  const sortedDetailTransaksi = useMemo(() => {
    return sortRows(filteredTransaksi, detailSort, {
      tanggal: row => row.tanggal,
      mitra: row => formatMitraLabel(row.master_mitra),
      tipe: row => getMitraTypeLabel(row.master_mitra?.tipe_mitra),
      sopir: row => `${row.sopir_aktual_nama || row.sopir_default_nama || ''} ${row.plat_nomor || ''}`,
      tonase: row => toNumber(row.tonase),
      harga_pabrik: row => resolveHargaPabrik(row) ?? 0,
      fee: row => resolveFeePerKg(row),
      pendapatan: row => resolveTotalFeeOwner(row),
    });
  }, [detailSort, filteredTransaksi]);

  const paginatedDetailTransaksi = useMemo(() => {
    return paginateRows(sortedDetailTransaksi, detailPage, TABLE_PAGE_SIZE);
  }, [detailPage, sortedDetailTransaksi]);

  const selectedMitraData = mitras.find((mitra) => mitra.id === selectedMitra);

  const handlePrint = () => {
    window.print();
  };

  const handleSummarySort = (key) => {
    setSummaryPage(1);
    setSummarySort(current => getNextSort(current, key, ['transaksi', 'tonase', 'nilai_pabrik', 'nilai_bersih', 'pendapatan'].includes(key) ? 'desc' : 'asc'));
  };

  const handleDetailSort = (key) => {
    setDetailPage(1);
    setDetailSort(current => getNextSort(current, key, ['tanggal', 'tonase', 'harga_pabrik', 'fee', 'pendapatan'].includes(key) ? 'desc' : 'asc'));
  };

  if (userRole !== null && !canViewProfit(userRole)) {
    return (
      <AppShell title="Pendapatan Owner Bruto" subtitle="Akses terbatas">
        <div className="empty-state" style={{ marginTop: 'var(--space-3xl)' }}>
          <div className="empty-state-title">Akses Ditolak</div>
          <div className="empty-state-text">
            Laporan Pendapatan Owner Bruto hanya dapat diakses oleh Owner dan Super Admin.
          </div>
        </div>
      </AppShell>
    );
  }

  if (userRole === null) {
    return (
      <AppShell title="Pendapatan Owner Bruto">
        <div style={{ textAlign: 'center', padding: 'var(--space-3xl)' }}>
          <div className="spinner spinner-lg" style={{ margin: '0 auto' }} />
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title="Pendapatan Owner Bruto" subtitle="Fee Owner bruto dari pengiriman mitra">
      <div className="page-header no-print">
        <div>
          <h2 className="page-title">Laporan Pendapatan Owner Bruto</h2>
          <p className="page-description">
            Fee Owner bruto dari transaksi mitra periode {dateFrom} s/d {dateTo}
          </p>
        </div>
        <button className="btn btn-primary" onClick={handlePrint} disabled={filteredTransaksi.length === 0}>
          <Printer size={18} /> Cetak Laporan
        </button>
      </div>

      <div className="no-print card owner-income-filter">
        <div className="owner-income-filter-mitra">
          <label className="form-label">Mitra</label>
          <SearchableCombobox
            value={selectedMitra}
            options={mitras}
            onChange={(mitraId) => {
              setSelectedMitra(mitraId);
              setSummaryPage(1);
              setDetailPage(1);
            }}
            getOptionLabel={formatMitraLabel}
            getSearchText={getMitraSearchText}
            placeholder="Semua mitra"
            emptyLabel="Mitra tidak ditemukan"
          />
        </div>
        <div>
          <label className="form-label">Tipe</label>
          <select className="form-input form-select" value={selectedTipeMitra} onChange={event => {
            setSelectedTipeMitra(event.target.value);
            setSummaryPage(1);
            setDetailPage(1);
          }}>
            <option value="semua">Semua</option>
            <option value={MITRA_TYPES.INTERNAL_OWNER}>Internal Owner</option>
            <option value={MITRA_TYPES.EKSTERNAL}>Mitra Eksternal</option>
          </select>
        </div>
        <div>
          <label className="form-label">Dari Tanggal</label>
          <input type="date" className="form-input" value={dateFrom} onChange={event => {
            setDateFrom(event.target.value);
            setSummaryPage(1);
            setDetailPage(1);
          }} />
        </div>
        <div>
          <label className="form-label">Sampai Tanggal</label>
          <input type="date" className="form-input" value={dateTo} onChange={event => {
            setDateTo(event.target.value);
            setSummaryPage(1);
            setDetailPage(1);
          }} />
        </div>
      </div>

      {summary.missingSnapshots > 0 && (
        <div className="alert alert-warning no-print">
          <AlertTriangle size={18} />
          <div>
            <strong>{summary.missingSnapshots} transaksi belum punya snapshot Fee Owner.</strong>
            <div style={{ marginTop: 4 }}>
              Baris tersebut tidak dipaksa memakai fee master saat ini. Koreksi dari Riwayat Pengiriman jika transaksi lama perlu masuk pendapatan owner.
            </div>
          </div>
        </div>
      )}

      <div className="alert alert-info no-print">
        <div>
          <strong>Angka ini masih bruto.</strong>
          <div style={{ marginTop: 4 }}>
            Pendapatan Owner Bruto belum dikurangi biaya operasional seperti solar, gaji sopir, uang jalan, perawatan armada, kuli, retribusi, atau biaya timbang.
          </div>
        </div>
      </div>

      <div className="print-area">
        <div className="only-print" style={{ textAlign: 'center', marginBottom: 24, borderBottom: '2px solid #000', paddingBottom: 16 }}>
          <h2 style={{ margin: 0, fontSize: 22 }}>LAPORAN PENDAPATAN OWNER BRUTO</h2>
          <p style={{ margin: '4px 0 0' }}>
            Periode: {dateFrom} s/d {dateTo}
            {selectedTipeMitra !== 'semua' ? ` | Tipe: ${getMitraTypeLabel(selectedTipeMitra)}` : ''}
            {selectedMitraData ? ` | Mitra: ${formatMitraLabel(selectedMitraData)}` : ''}
          </p>
          <p style={{ margin: '6px 0 0', fontSize: 12 }}>
            Belum dikurangi biaya operasional owner.
          </p>
        </div>

        <div className="stats-grid owner-income-stats">
          <div className="card">
            <div className="card-header">
              <span className="card-title">Pendapatan Owner Bruto</span>
              <div className="card-icon card-icon-green"><BadgeDollarSign size={20} /></div>
            </div>
            <div className="card-value" style={{ color: 'var(--color-success)' }}>
              {formatRupiah(summary.totalPendapatanOwner)}
            </div>
            <div className="card-label">Total Fee Owner sebelum biaya operasional</div>
            {(positiveFeeBreakdown.length > 0 || zeroFeeBreakdown) && (
              <div className="owner-income-fee-breakdown">
                {positiveFeeBreakdown.map(item => (
                  <div key={item.feePerKg} className="owner-income-fee-breakdown-row">
                    <span>Fee {formatRupiah(item.feePerKg)}/kg</span>
                    <strong>{formatRupiah(item.pendapatanOwner)}</strong>
                  </div>
                ))}
                {zeroFeeBreakdown && (
                  <div className="owner-income-fee-breakdown-note">
                    {zeroFeeBreakdown.jumlahTransaksi} transaksi fee belum terset.
                  </div>
                )}
              </div>
            )}
          </div>

          <div className="card">
            <div className="card-header">
              <span className="card-title">Total Tonase Mitra</span>
              <div className="card-icon card-icon-blue"><Scale size={20} /></div>
            </div>
            <div className="card-value">{formatNumber(summary.totalTonase)} <span style={{ fontSize: 'var(--text-base)', fontWeight: 400 }}>Kg</span></div>
            <div className="card-label">{summary.jumlahTransaksi} transaksi aktif</div>
          </div>

          <div className="card">
            <div className="card-header">
              <span className="card-title">Rata-rata Fee</span>
              <div className="card-icon card-icon-gold"><ReceiptText size={20} /></div>
            </div>
            <div className="card-value">{formatRupiah(summary.rataFeeOwner)}<span style={{ fontSize: 'var(--text-base)', fontWeight: 400 }}>/Kg</span></div>
            <div className="card-label">Berbobot dari tonase</div>
          </div>

          <div className="card">
            <div className="card-header">
              <span className="card-title">Nilai Bersih Mitra</span>
            </div>
            <div className="card-value">{formatRupiah(summary.totalNilaiBersihMitra)}</div>
            <div className="card-label">Total yang menjadi dasar pembayaran mitra</div>
          </div>
        </div>

        {loading ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {[1, 2, 3].map((item) => <div key={item} className="skeleton" style={{ height: 88 }} />)}
          </div>
        ) : errorMsg ? (
          <div className="card" style={{ padding: 24, color: 'var(--color-danger)', textAlign: 'center' }}>
            Gagal memuat laporan: {errorMsg}
          </div>
        ) : (
          <>
            <div className="card" style={{ marginBottom: 'var(--space-lg)' }}>
              <div className="card-header">
                <span className="card-title">Ringkasan Per Mitra</span>
              </div>
              <div className="table-container">
                <table className="table">
                  <thead>
                    <tr>
                      <SortableHeader label="Mitra" sortKey="mitra" sort={summarySort} onSort={handleSummarySort} />
                      <SortableHeader label="Tipe" sortKey="tipe" sort={summarySort} onSort={handleSummarySort} />
                      <SortableHeader label="Transaksi" sortKey="transaksi" sort={summarySort} onSort={handleSummarySort} align="right" />
                      <SortableHeader label="Tonase" sortKey="tonase" sort={summarySort} onSort={handleSummarySort} align="right" />
                      <SortableHeader label="Nilai Pabrik/TWB" sortKey="nilai_pabrik" sort={summarySort} onSort={handleSummarySort} align="right" />
                      <SortableHeader label="Nilai Bersih Mitra" sortKey="nilai_bersih" sort={summarySort} onSort={handleSummarySort} align="right" />
                      <SortableHeader label="Pendapatan Owner Bruto" sortKey="pendapatan" sort={summarySort} onSort={handleSummarySort} align="right" />
                    </tr>
                  </thead>
                  <tbody>
                    {sortedRingkasanMitra.length === 0 ? (
                      <tr>
                        <td colSpan={7} style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)' }}>
                          Tidak ada transaksi pada periode ini
                        </td>
                      </tr>
                    ) : paginatedRingkasanMitra.rows.map((row) => (
                      <tr key={row.key}>
                        <td style={{ fontWeight: 700 }}>
                          {row.label}
                          {row.missingSnapshots > 0 && (
                            <div style={{ marginTop: 4 }}>
                              <span className="badge badge-warning">{row.missingSnapshots} perlu koreksi fee</span>
                            </div>
                          )}
                        </td>
                        <td>
                          <span className={`badge ${getMitraTypeBadgeClass(row.tipeMitra)}`}>
                            {getMitraTypeLabel(row.tipeMitra)}
                          </span>
                        </td>
                        <td className="table-mono" style={{ textAlign: 'right' }}>{row.jumlahTransaksi}</td>
                        <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(row.tonase)} Kg</td>
                        <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(row.nilaiPabrik)}</td>
                        <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(row.nilaiBersihMitra)}</td>
                        <td className="table-mono" style={{ textAlign: 'right', fontWeight: 800, color: 'var(--color-success)' }}>
                          {formatRupiah(row.pendapatanOwner)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <TablePagination
                  page={paginatedRingkasanMitra.page}
                  totalPages={paginatedRingkasanMitra.totalPages}
                  totalItems={sortedRingkasanMitra.length}
                  startIndex={paginatedRingkasanMitra.startIndex}
                  endIndex={paginatedRingkasanMitra.endIndex}
                  onPageChange={setSummaryPage}
                />
              </div>
            </div>

            <div className="card">
              <div className="card-header">
                <span className="card-title">Rincian Transaksi</span>
              </div>
              <div className="table-container">
                <table className="table">
                  <thead>
                    <tr>
                      <SortableHeader label="Tanggal" sortKey="tanggal" sort={detailSort} onSort={handleDetailSort} />
                      <SortableHeader label="Mitra" sortKey="mitra" sort={detailSort} onSort={handleDetailSort} />
                      <SortableHeader label="Tipe" sortKey="tipe" sort={detailSort} onSort={handleDetailSort} />
                      <SortableHeader label="Sopir / Plat" sortKey="sopir" sort={detailSort} onSort={handleDetailSort} />
                      <SortableHeader label="Tonase" sortKey="tonase" sort={detailSort} onSort={handleDetailSort} align="right" />
                      <SortableHeader label="Harga Pabrik" sortKey="harga_pabrik" sort={detailSort} onSort={handleDetailSort} align="right" />
                      <SortableHeader label="Fee/Kg" sortKey="fee" sort={detailSort} onSort={handleDetailSort} align="right" />
                      <SortableHeader label="Pendapatan Owner Bruto" sortKey="pendapatan" sort={detailSort} onSort={handleDetailSort} align="right" />
                    </tr>
                  </thead>
                  <tbody>
                    {sortedDetailTransaksi.length === 0 ? (
                      <tr>
                        <td colSpan={8} style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)' }}>
                          Tidak ada transaksi pada periode ini
                        </td>
                      </tr>
                    ) : paginatedDetailTransaksi.rows.map((row) => {
                      const hargaPabrik = resolveHargaPabrik(row);
                      const feePerKg = resolveFeePerKg(row);
                      const totalFeeOwner = resolveTotalFeeOwner(row);
                      const tipeMitra = row.master_mitra?.tipe_mitra || MITRA_TYPES.EKSTERNAL;

                      return (
                        <tr key={row.id}>
                          <td>{row.tanggal}</td>
                          <td style={{ fontWeight: 600 }}>{formatMitraLabel(row.master_mitra) || '-'}</td>
                          <td>
                            <span className={`badge ${getMitraTypeBadgeClass(tipeMitra)}`}>
                              {getMitraTypeLabel(tipeMitra)}
                            </span>
                          </td>
                          <td>
                            <div>{row.sopir_aktual_nama || row.sopir_default_nama || '-'}</div>
                            <div className="table-mono" style={{ marginTop: 4, color: 'var(--text-tertiary)', fontSize: 12 }}>
                              {row.plat_nomor || '-'}
                            </div>
                          </td>
                          <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(toNumber(row.tonase))} Kg</td>
                          <td className="table-mono" style={{ textAlign: 'right' }}>
                            {hargaPabrik == null ? '-' : formatRupiah(hargaPabrik)}
                          </td>
                          <td className="table-mono" style={{ textAlign: 'right' }}>
                            {hasFeeSnapshot(row) ? formatRupiah(feePerKg) : <span className="badge badge-warning">Perlu koreksi</span>}
                          </td>
                          <td className="table-mono" style={{ textAlign: 'right', fontWeight: 800, color: hasFeeSnapshot(row) ? 'var(--color-success)' : 'var(--text-tertiary)' }}>
                            {formatRupiah(totalFeeOwner)}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                  {filteredTransaksi.length > 0 && (
                    <tfoot>
                      <tr>
                        <td colSpan={4} style={{ textAlign: 'right', fontWeight: 800 }}>TOTAL</td>
                        <td className="table-mono" style={{ textAlign: 'right', fontWeight: 800 }}>{formatNumber(summary.totalTonase)} Kg</td>
                        <td className="table-mono" style={{ textAlign: 'right', fontWeight: 800 }}>{formatRupiah(summary.totalNilaiPabrik)}</td>
                        <td></td>
                        <td className="table-mono" style={{ textAlign: 'right', fontWeight: 900, color: 'var(--color-success)' }}>
                          {formatRupiah(summary.totalPendapatanOwner)}
                        </td>
                      </tr>
                    </tfoot>
                  )}
                </table>
                <TablePagination
                  page={paginatedDetailTransaksi.page}
                  totalPages={paginatedDetailTransaksi.totalPages}
                  totalItems={sortedDetailTransaksi.length}
                  startIndex={paginatedDetailTransaksi.startIndex}
                  endIndex={paginatedDetailTransaksi.endIndex}
                  onPageChange={setDetailPage}
                />
              </div>
            </div>
          </>
        )}
      </div>

      <style jsx global>{`
        .owner-income-filter {
          margin-bottom: var(--space-lg);
          display: grid;
          grid-template-columns: minmax(260px, 1fr) repeat(3, minmax(150px, 210px));
          gap: var(--space-md);
          align-items: end;
        }

        .owner-income-stats {
          grid-template-columns: repeat(4, minmax(0, 1fr));
        }

        .owner-income-fee-breakdown {
          margin-top: 12px;
          padding-top: 10px;
          border-top: 1px dashed var(--border-default);
          display: grid;
          gap: 6px;
        }

        .owner-income-fee-breakdown-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
          font-size: 12px;
          color: var(--text-secondary);
        }

        .owner-income-fee-breakdown-row strong {
          color: var(--text-primary);
          font-family: var(--font-mono);
          font-size: 12px;
          white-space: nowrap;
        }

        .owner-income-fee-breakdown-note {
          margin-top: 2px;
          color: var(--color-warning);
          font-size: 12px;
        }

        @media (max-width: 900px) {
          .owner-income-filter,
          .owner-income-stats {
            grid-template-columns: 1fr;
          }
        }

        @media print {
          body * { visibility: hidden; }
          .print-area, .print-area * { visibility: visible; color: #000 !important; background: #fff !important; }
          .print-area { position: absolute; left: 0; top: 0; width: 100%; box-shadow: none !important; padding: 0 !important; }
          .print-area .card { box-shadow: none !important; border: 1px solid #111 !important; break-inside: avoid; }
          .no-print { display: none !important; }
        }
      `}</style>
    </AppShell>
  );
}
