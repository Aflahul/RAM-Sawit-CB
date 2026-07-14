'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import { formatMitraLabel, getMitraSearchText } from '@/lib/display-labels';
import { paginateRows } from '@/lib/pagination-utils';
import { getNextSort, sortRows } from '@/lib/sort-utils';
import { exportStyledWorkbook } from '@/lib/spreadsheet-export';
import { supabase } from '@/lib/supabase';
import {
  resolveHargaPabrikPerKg,
  resolveTotalKotorPabrik,
  resolveTotalNilaiBersihMitra,
} from '@/lib/transaksi-mitra-calculations';
import { formatDateDisplay, formatDateRangeDisplay, formatDateTimeDisplay, formatRupiah, formatWaktu, getTimestampMs, getTodayISO } from '@/lib/utils';
import { FileSpreadsheet, Printer, X } from 'lucide-react';

const TABLE_PAGE_SIZE = 20;

const laporanSortAccessors = {
  tanggal: row => row.tanggal,
  waktu: row => getTimestampMs(row.created_at || row.tanggal),
  mitra: row => formatMitraLabel(row.master_mitra),
  pembayaran: row => row.payment_status,
  sopir: row => row.sopir_aktual_nama || row.sopir_default_nama,
  plat: row => row.plat_nomor,
  tonase: row => Number(row.tonase),
  hasil_kotor_pabrik: row => resolveTotalKotorPabrik(row),
  nilai_bersih: row => resolveTotalNilaiBersihMitra(row),
};

export default function LaporanMitraPage() {
  const [dateFrom, setDateFrom] = useState(getTodayISO);
  const [dateTo, setDateTo] = useState(getTodayISO);
  const [mitras, setMitras] = useState([]);
  const [selectedMitraIds, setSelectedMitraIds] = useState([]);
  const [mitraPickerValue, setMitraPickerValue] = useState('');
  const [viewMode, setViewMode] = useState('gabung');
  const [paymentFilter, setPaymentFilter] = useState('semua');
  const [transaksi, setTransaksi] = useState([]);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [sort, setSort] = useState({ key: 'waktu', direction: 'desc' });
  const [page, setPage] = useState(1);

  const loadMitras = useCallback(async () => {
    const { data, error } = await supabase
      .from('master_mitra')
      .select('id, kode, alamat, nama, penanggung_jawab, no_hp, tipe_mitra, fee_per_kg')
      .eq('aktif', true)
      .order('kode');

    if (error) {
      console.error('Gagal memuat daftar mitra:', error);
      setMitras([]);
      return;
    }

    setMitras(data || []);
  }, []);

  const loadLaporan = useCallback(async () => {
    setLoading(true);
    setErrorMsg('');

    let query = supabase
      .from('transaksi_mitra')
      .select(`
        id, mitra_id, tanggal, tonase, harga_harian, total_kotor,
        created_at,
        harga_pabrik_per_kg, fee_owner_per_kg, harga_bersih_per_kg,
        total_fee_owner, total_nilai_bersih, plat_nomor,
        sopir_default_nama, sopir_aktual_nama, sopir_diganti_dari_default, catatan_sopir,
        master_mitra ( id, kode, alamat, nama, fee_per_kg )
      `)
      .gte('tanggal', dateFrom)
      .lte('tanggal', dateTo)
      .neq('status', 'dibatalkan');

    if (selectedMitraIds.length > 0) {
      query = query.in('mitra_id', selectedMitraIds);
    }

    const { data, error } = await query
      .order('tanggal', { ascending: false })
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Gagal memuat laporan mitra:', error);
      setTransaksi([]);
      setErrorMsg(error.message);
      setLoading(false);
      return;
    }

    let rows = data || [];

    if (rows.length > 0) {
      const trxIds = rows.map(row => row.id);
      const { data: paymentItems, error: paymentError } = await supabase
        .from('pembayaran_mitra_kwitansi_item')
        .select(`
          transaksi_mitra_id,
          tonase_snapshot,
          total_nilai_bersih_snapshot,
          pembayaran:pembayaran_mitra_kwitansi ( id, status, tanggal_bayar, dibayar_at, metode_bayar )
        `)
        .in('transaksi_mitra_id', trxIds);

      if (paymentError) {
        console.error('Gagal memuat status bayar laporan mitra:', paymentError);
      }

      const paymentMap = new Map((paymentItems || []).map((item) => {
        const payment = Array.isArray(item.pembayaran) ? item.pembayaran[0] : item.pembayaran;
        return [item.transaksi_mitra_id, { ...item, pembayaran: payment }];
      }));
      rows = rows.map(row => {
        const paymentItem = paymentMap.get(row.id);
        const payment = paymentItem?.pembayaran;
        const hasChangedAfterPayment = payment
          && (
            Math.round(Number(row.tonase || 0) * 100) !== Math.round(Number(paymentItem.tonase_snapshot || 0) * 100)
            || Math.round(resolveTotalNilaiBersihMitra(row)) !== Math.round(Number(paymentItem.total_nilai_bersih_snapshot || 0))
          );
        return {
          ...row,
          payment,
          payment_status: payment?.status === 'perlu_review' || hasChangedAfterPayment
            ? 'perlu_review'
            : payment?.status === 'dibayar'
              ? 'sudah_dibayar'
              : 'belum_dibayar',
        };
      });
    }

    setTransaksi(rows);
    setLoading(false);
  }, [dateFrom, dateTo, selectedMitraIds]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadMitras();
  }, [loadMitras]);

  useEffect(() => {
    if (dateFrom && dateTo) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      loadLaporan();
    }
  }, [dateFrom, dateTo, loadLaporan]);

  const handlePrint = () => {
    window.print();
  };

  const handleSort = (key) => {
    setPage(1);
    setSort(current => getNextSort(current, key, ['tanggal', 'waktu'].includes(key) ? 'desc' : 'asc'));
  };

  const handleDateFromChange = (value) => {
    setDateFrom(value);
    setPage(1);
  };

  const handleDateToChange = (value) => {
    setDateTo(value);
    setPage(1);
  };

  const handleAddMitra = (mitraId) => {
    if (!mitraId) return;
    setSelectedMitraIds(current => (current.includes(mitraId) ? current : [...current, mitraId]));
    setMitraPickerValue('');
    setPage(1);
  };

  const handleRemoveMitra = (mitraId) => {
    setSelectedMitraIds(current => current.filter(id => id !== mitraId));
    setPage(1);
  };

  const handleClearMitras = () => {
    setSelectedMitraIds([]);
    setMitraPickerValue('');
    setPage(1);
  };

  const handlePaymentFilterChange = (value) => {
    setPaymentFilter(value);
    setPage(1);
  };

  const selectedMitras = useMemo(() => {
    return selectedMitraIds
      .map(id => mitras.find(mitra => mitra.id === id))
      .filter(Boolean);
  }, [mitras, selectedMitraIds]);

  const availableMitras = useMemo(() => {
    return mitras.filter(mitra => !selectedMitraIds.includes(mitra.id));
  }, [mitras, selectedMitraIds]);

  const filteredTransaksi = useMemo(() => {
    if (paymentFilter === 'semua') return transaksi;
    return transaksi.filter(row => row.payment_status === paymentFilter);
  }, [paymentFilter, transaksi]);
  const sortedTransaksi = useMemo(() => {
    return sortRows(filteredTransaksi, sort, laporanSortAccessors);
  }, [filteredTransaksi, sort]);
  const paginatedTransaksi = useMemo(() => {
    return paginateRows(sortedTransaksi, page, TABLE_PAGE_SIZE);
  }, [page, sortedTransaksi]);
  const groupedTransaksi = useMemo(() => {
    const groups = new Map();

    sortedTransaksi.forEach((row) => {
      const key = row.mitra_id || 'tanpa-mitra';
      const current = groups.get(key) || {
        key,
        label: formatMitraLabel(row.master_mitra) || 'Tanpa mitra',
        rows: [],
        tonase: 0,
        totalKotorPabrik: 0,
        totalNilaiBersih: 0,
      };

      current.rows.push(row);
      current.tonase += Number(row.tonase || 0);
      current.totalKotorPabrik += resolveTotalKotorPabrik(row);
      current.totalNilaiBersih += resolveTotalNilaiBersihMitra(row);
      groups.set(key, current);
    });

    return Array.from(groups.values()).sort((a, b) => (
      a.label.localeCompare(b.label, 'id-ID', { numeric: true, sensitivity: 'base' })
    ));
  }, [sortedTransaksi]);

  const totalTonase = filteredTransaksi.reduce((sum, t) => sum + Number(t.tonase), 0);
  const totalKotorPabrik = filteredTransaksi.reduce((sum, t) => sum + resolveTotalKotorPabrik(t), 0);
  const totalNilaiBersih = filteredTransaksi.reduce((sum, t) => sum + resolveTotalNilaiBersihMitra(t), 0);
  const displayPeriode = formatDateRangeDisplay(dateFrom, dateTo);
  const shouldGroupByMitra = viewMode === 'kelompok';
  const paymentFilterLabel = {
    semua: 'Semua status bayar',
    belum_dibayar: 'Belum dibayar',
    sudah_dibayar: 'Sudah dibayar',
    perlu_review: 'Perlu review',
  }[paymentFilter] || 'Semua status bayar';

  function getPaymentBadge(row) {
    if (row.payment_status === 'sudah_dibayar') {
      return <span className="badge badge-success">Sudah Dibayar</span>;
    }
    if (row.payment_status === 'perlu_review') {
      return <span className="badge badge-warning">Perlu Review</span>;
    }
    return <span className="badge badge-neutral">Belum Dibayar</span>;
  }

  const renderRows = (rows) => {
    if (rows.length === 0) {
      return (
        <tr>
          <td colSpan={6} style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)' }}>
            Tidak ada transaksi pada periode ini
          </td>
        </tr>
      );
    }

    return rows.map(t => (
      <tr key={t.id}>
        <td>
          <div style={{ fontWeight: 700 }}>{formatDateDisplay(t.tanggal)}</div>
          <div className="table-mono" style={{ marginTop: 4, fontSize: 12, color: 'var(--text-tertiary)' }}>{formatWaktu(t.created_at)}</div>
        </td>
        <td>
          <div style={{ fontWeight: 700 }}>{t.sopir_aktual_nama || t.sopir_default_nama || '-'}</div>
          <div style={{ marginTop: 4, fontSize: 12, color: 'var(--text-tertiary)', lineHeight: 1.45 }}>
            <span>{t.master_mitra?.kode || '-'}</span>
            <span> - </span>
            <span className="table-mono">{t.plat_nomor || 'Tanpa plat'}</span>
          </div>
          {t.sopir_diganti_dari_default && (
            <div style={{ marginTop: 4 }}>
              <span className="badge badge-warning">Pengganti</span>
              <div style={{ fontSize: 12, color: 'var(--text-tertiary)', marginTop: 4 }}>
                Default: {t.sopir_default_nama || '-'}
                {t.catatan_sopir ? ` - ${t.catatan_sopir}` : ''}
              </div>
            </div>
          )}
        </td>
        <td>{getPaymentBadge(t)}</td>
        <td style={{ textAlign: 'right', fontWeight: 'bold', color: 'var(--text-primary)' }}>{Number(t.tonase).toLocaleString('id-ID')}</td>
        <td style={{ textAlign: 'right' }} className="table-mono">{formatRupiah(resolveTotalKotorPabrik(t))}</td>
        <td style={{ textAlign: 'right' }} className="table-mono">{formatRupiah(resolveTotalNilaiBersihMitra(t))}</td>
      </tr>
    ));
  };

  const renderTableHead = () => (
    <thead>
      <tr>
        <SortableHeader label="Tanggal" sortKey="waktu" sort={sort} onSort={handleSort} />
        <SortableHeader label="Mitra" sortKey="sopir" sort={sort} onSort={handleSort} />
        <SortableHeader label="Status Bayar" sortKey="pembayaran" sort={sort} onSort={handleSort} />
        <SortableHeader label="Tonase" sortKey="tonase" sort={sort} onSort={handleSort} align="right" />
        <SortableHeader label="Hasil Pabrik" sortKey="hasil_kotor_pabrik" sort={sort} onSort={handleSort} align="right" />
        <SortableHeader label="Nilai Bersih" sortKey="nilai_bersih" sort={sort} onSort={handleSort} align="right" />
      </tr>
    </thead>
  );

  async function handleExportExcel() {
    const generatedAt = formatDateTimeDisplay(new Date());
    const filterLabel = selectedMitras.length > 0
      ? selectedMitras.map(formatMitraLabel).join(', ')
      : 'Semua mitra';

    await exportStyledWorkbook({
      filename: `laporan-mitra-${dateFrom}-sd-${dateTo}.xlsx`,
      sheets: [
        {
          name: 'Detail Pengiriman',
          title: 'LAPORAN PENGIRIMAN MITRA SAWIT CB',
          subtitle: `Periode ${displayPeriode} | Filter: ${filterLabel} | Status Bayar: ${paymentFilterLabel} | Dibuat: ${generatedAt}`,
          columns: [
            { header: 'No', value: (row, index) => row.__footer ? '' : index + 1, type: 'number', width: 6 },
            { header: 'Tanggal', value: row => row.__footer ? '' : formatDateDisplay(row.tanggal), width: 14 },
            { header: 'Waktu', value: row => row.__footer ? '' : formatWaktu(row.created_at), width: 12 },
            { header: 'Kode Mitra', value: row => row.__footer ? '' : row.master_mitra?.kode || '', width: 16 },
            { header: 'Alamat Mitra', value: row => row.__footer ? '' : row.master_mitra?.alamat || '', width: 24 },
            { header: 'Nama Mitra', value: row => row.__footer ? '' : row.master_mitra?.nama || '', width: 24 },
            { header: 'Mitra / Afiliasi', value: row => row.mitra_label ?? formatMitraLabel(row.master_mitra), width: 38 },
            { header: 'Status Bayar', value: row => row.__footer ? '' : row.payment_status === 'sudah_dibayar' ? 'Sudah Dibayar' : row.payment_status === 'perlu_review' ? 'Perlu Review' : 'Belum Dibayar', width: 18 },
            { header: 'Sopir Aktual', value: row => row.__footer ? '' : row.sopir_aktual_nama || row.sopir_default_nama || '', width: 24 },
            { header: 'Sopir Default', key: 'sopir_default_nama', width: 24 },
            { header: 'Status Sopir', value: row => row.__footer ? '' : row.sopir_diganti_dari_default ? 'Pengganti' : 'Sesuai default/manual', width: 20 },
            { header: 'Plat Nomor', key: 'plat_nomor', width: 18 },
            { header: 'Tonase (Kg)', key: 'tonase', type: 'decimal', width: 16 },
            { header: 'Harga Pabrik/Kg', value: row => row.__footer ? '' : resolveHargaPabrikPerKg(row), type: 'currency', width: 18 },
            { header: 'Hasil Kotor Pabrik (Rp)', value: row => row.__footer ? row.total_kotor : resolveTotalKotorPabrik(row), type: 'currency', width: 22 },
            { header: 'Nilai Bersih Mitra (Rp)', value: row => row.__footer ? row.total_nilai_bersih : resolveTotalNilaiBersihMitra(row), type: 'currency', width: 22 },
            { header: 'Catatan Sopir', key: 'catatan_sopir', width: 28 },
          ],
          rows: sortedTransaksi,
          footerRows: [{
            __footer: true,
            mitra_label: 'TOTAL',
            tonase: totalTonase,
            total_kotor: totalKotorPabrik,
            total_nilai_bersih: totalNilaiBersih,
          }],
        },
        {
          name: 'Ringkasan Mitra',
          title: 'RINGKASAN PENGIRIMAN PER MITRA',
          subtitle: `Periode ${displayPeriode} | Filter: ${filterLabel} | Status Bayar: ${paymentFilterLabel} | Dibuat: ${generatedAt}`,
          columns: [
            { header: 'No', value: (row, index) => row.__footer ? '' : index + 1, type: 'number', width: 6 },
            { header: 'Mitra / Afiliasi', key: 'label', width: 38 },
            { header: 'Jumlah Transaksi', value: row => row.jumlahTransaksi ?? row.rows?.length ?? '', type: 'number', width: 18 },
            { header: 'Total Tonase (Kg)', key: 'tonase', type: 'decimal', width: 18 },
            { header: 'Total Hasil Kotor Pabrik (Rp)', value: row => row.totalKotorPabrik ?? row.total_kotor, type: 'currency', width: 28 },
            { header: 'Total Nilai Bersih Mitra (Rp)', value: row => row.totalNilaiBersih ?? row.total_nilai_bersih, type: 'currency', width: 28 },
          ],
          rows: groupedTransaksi,
          footerRows: [{
            __footer: true,
            label: 'TOTAL',
            jumlahTransaksi: filteredTransaksi.length,
            tonase: totalTonase,
            totalKotorPabrik,
            totalNilaiBersih,
          }],
        },
      ],
    });
  }

  return (
    <AppShell title="Laporan Mitra" subtitle="Laporan harian seluruh pengiriman mitra">
      <div className="page-header no-print">
        <div>
          <p className="page-description">Rekap seluruh transaksi penerimaan TWB dari armada mitra</p>
        </div>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
          <button className="btn btn-outline" onClick={handleExportExcel} disabled={transaksi.length === 0}>
            <FileSpreadsheet size={18} /> Export Excel
          </button>
          <button className="btn btn-primary" onClick={handlePrint} disabled={transaksi.length === 0}>
            <Printer size={18} /> Cetak Laporan
          </button>
        </div>
      </div>

      <div className="no-print card laporan-filter-card">
        <div className="laporan-filter-grid">
          <div className="date-filter-item">
            <label className="date-filter-label">Dari Tanggal</label>
            <input type="date" className="form-input date-filter-input" value={dateFrom} onChange={e => handleDateFromChange(e.target.value)} />
          </div>
          <div className="date-filter-item">
            <label className="date-filter-label">Sampai Tanggal</label>
            <input type="date" className="form-input date-filter-input" value={dateTo} onChange={e => handleDateToChange(e.target.value)} />
          </div>
          <div className="mitra-filter-item">
            <label className="date-filter-label">Filter Mitra</label>
            <SearchableCombobox
              value={mitraPickerValue}
              options={availableMitras}
              onChange={handleAddMitra}
              getOptionLabel={formatMitraLabel}
              getSearchText={getMitraSearchText}
              placeholder={selectedMitraIds.length > 0 ? 'Tambah mitra' : 'Semua mitra'}
              emptyLabel="Mitra tidak ditemukan"
              clearable={false}
            />
          </div>
          <div className="date-filter-item">
            <label className="date-filter-label">Status Bayar</label>
            <select
              className="form-input date-filter-input"
              value={paymentFilter}
              onChange={(e) => handlePaymentFilterChange(e.target.value)}
            >
              <option value="semua">Semua status</option>
              <option value="belum_dibayar">Belum dibayar</option>
              <option value="sudah_dibayar">Sudah dibayar</option>
              <option value="perlu_review">Perlu review</option>
            </select>
          </div>
          <div className="date-filter-item">
            <label className="date-filter-label">Tampilan</label>
            <select
              className="form-input date-filter-input"
              value={viewMode}
              onChange={(e) => {
                setViewMode(e.target.value);
                setPage(1);
              }}
            >
              <option value="gabung">Gabung pilihan</option>
              <option value="kelompok">Kelompok per mitra</option>
            </select>
          </div>
        </div>

        {selectedMitras.length > 0 && (
          <div className="selected-mitra-bar">
            <div className="selected-mitra-chips">
              {selectedMitras.map(mitra => (
                <span key={mitra.id} className="selected-mitra-chip">
                  {formatMitraLabel(mitra)}
                  <button
                    type="button"
                    className="selected-mitra-chip-remove"
                    title="Hapus filter mitra"
                    aria-label={`Hapus ${formatMitraLabel(mitra)}`}
                    onClick={() => handleRemoveMitra(mitra.id)}
                  >
                    <X size={14} />
                  </button>
                </span>
              ))}
            </div>
            <button type="button" className="btn btn-secondary selected-mitra-clear" onClick={handleClearMitras}>
              Bersihkan
            </button>
          </div>
        )}
      </div>

      <div className="no-print laporan-summary-strip">
        <span>{selectedMitras.length > 0 ? `${selectedMitras.length} mitra dipilih` : 'Semua mitra'}</span>
        <span>{filteredTransaksi.length.toLocaleString('id-ID')} transaksi tampil</span>
        {paymentFilter !== 'semua' && <span>Status: {paymentFilterLabel}</span>}
        <span>{totalTonase.toLocaleString('id-ID')} Kg</span>
        <span>{formatRupiah(totalKotorPabrik)} kotor pabrik</span>
      </div>

      <div className="print-area card" style={{ padding: 0, overflow: 'hidden' }}>
        <div className="only-print" style={{ textAlign: 'center', marginBottom: 24, borderBottom: '2px solid var(--border-default)', paddingBottom: 16 }}>
          <h2 style={{ margin: 0, fontSize: 22 }}>LAPORAN HARIAN PENGIRIMAN MITRA</h2>
          <p style={{ margin: '4px 0 0', color: 'var(--text-secondary)' }}>Periode: {displayPeriode}</p>
          <p style={{ margin: '4px 0 0', color: 'var(--text-secondary)' }}>
            Filter Mitra: {selectedMitras.length > 0 ? selectedMitras.map(formatMitraLabel).join(', ') : 'Semua mitra'}
          </p>
        </div>

        {loading ? (
          <div style={{ textAlign: 'center', padding: 40 }}>Memuat laporan...</div>
        ) : errorMsg ? (
          <div style={{ padding: 24, color: 'var(--color-danger)', textAlign: 'center' }}>
            Gagal memuat laporan: {errorMsg}
          </div>
        ) : shouldGroupByMitra ? (
          <div className="grouped-laporan-container">
            {groupedTransaksi.length === 0 ? (
              <div style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)' }}>
                Tidak ada transaksi pada periode ini
              </div>
            ) : (
              groupedTransaksi.map(group => (
                <section key={group.key} className="grouped-mitra-section">
                  <div className="grouped-mitra-header">
                    <div>
                      <h3>{group.label}</h3>
                      <p>{group.rows.length.toLocaleString('id-ID')} transaksi</p>
                    </div>
                    <div className="grouped-mitra-totals">
                      <span>{group.tonase.toLocaleString('id-ID')} Kg</span>
                      <span>{formatRupiah(group.totalKotorPabrik)}</span>
                      <span>{formatRupiah(group.totalNilaiBersih)}</span>
                    </div>
                  </div>
                  <div className="table-container grouped-table-container">
                    <table className="table">
                      {renderTableHead()}
                      <tbody>{renderRows(group.rows)}</tbody>
                    </table>
                  </div>
                </section>
              ))
            )}
            {groupedTransaksi.length > 0 && (
              <div className="grouped-overall-total">
                <span>Total</span>
                <strong>{totalTonase.toLocaleString('id-ID')} Kg</strong>
                <strong>{formatRupiah(totalKotorPabrik)}</strong>
                <strong>{formatRupiah(totalNilaiBersih)}</strong>
              </div>
            )}
          </div>
        ) : (
          <div className="table-container">
            <table className="table">
              {renderTableHead()}
              <tbody>
                {renderRows(paginatedTransaksi.rows)}
              </tbody>
              {filteredTransaksi.length > 0 && (
                <tfoot>
                  <tr>
                    <td colSpan={3} style={{ textAlign: 'right', fontWeight: 'bold' }}>TOTAL:</td>
                    <td style={{ textAlign: 'right', fontWeight: 'bold', color: 'var(--color-success)' }}>{totalTonase.toLocaleString('id-ID')} Kg</td>
                    <td style={{ textAlign: 'right', fontWeight: 'bold' }}>{formatRupiah(totalKotorPabrik)}</td>
                    <td style={{ textAlign: 'right', fontWeight: 'bold' }}>{formatRupiah(totalNilaiBersih)}</td>
                  </tr>
                </tfoot>
              )}
            </table>
            <TablePagination
              page={paginatedTransaksi.page}
              totalPages={paginatedTransaksi.totalPages}
              totalItems={sortedTransaksi.length}
              startIndex={paginatedTransaksi.startIndex}
              endIndex={paginatedTransaksi.endIndex}
              onPageChange={setPage}
            />
          </div>
        )}
      </div>

      <style jsx global>{`
        .laporan-filter-card {
          margin: 0 auto var(--space-lg) auto;
          padding: var(--space-sm);
        }
        .laporan-filter-grid {
          display: grid;
          grid-template-columns: 1fr;
          gap: 10px;
        }
        .date-filter-item {
          min-width: 0;
          display: flex;
          flex-direction: column;
        }
        .mitra-filter-item {
          min-width: 0;
          display: flex;
          flex-direction: column;
        }
        .date-filter-label {
          display: block;
          font-size: 11px;
          font-weight: 500;
          margin-bottom: 4px;
          white-space: nowrap;
          flex-shrink: 0;
        }
        .date-filter-input {
          padding: 6px 4px;
          font-size: 11px;
          width: 100%;
          min-width: 0;
        }
        .selected-mitra-bar {
          margin-top: var(--space-sm);
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: 10px;
        }
        .selected-mitra-chips {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
          min-width: 0;
        }
        .selected-mitra-chip {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          max-width: 100%;
          padding: 6px 8px;
          border: 1px solid rgba(52, 211, 153, 0.35);
          border-radius: 8px;
          background: rgba(16, 185, 129, 0.12);
          color: var(--text-primary);
          font-size: 12px;
          font-weight: 600;
          line-height: 1.2;
        }
        .selected-mitra-chip-remove {
          width: 22px;
          height: 22px;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          flex: 0 0 auto;
          border: 0;
          border-radius: 999px;
          color: var(--text-secondary);
          background: rgba(15, 23, 42, 0.45);
          cursor: pointer;
        }
        .selected-mitra-chip-remove:hover {
          color: var(--text-primary);
          background: rgba(239, 68, 68, 0.22);
        }
        .selected-mitra-clear {
          flex: 0 0 auto;
          padding: 8px 12px;
        }
        .laporan-summary-strip {
          margin: calc(var(--space-lg) * -0.35) auto var(--space-lg) auto;
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }
        .laporan-summary-strip span {
          padding: 6px 10px;
          border: 1px solid var(--border-default);
          border-radius: 8px;
          background: rgba(15, 23, 42, 0.36);
          color: var(--text-secondary);
          font-size: 12px;
          font-weight: 700;
        }
        .grouped-laporan-container {
          display: flex;
          flex-direction: column;
          gap: var(--space-md);
          padding: var(--space-md);
        }
        .grouped-mitra-section {
          overflow: hidden;
          border: 1px solid var(--border-default);
          border-radius: var(--radius-lg);
          background: rgba(15, 23, 42, 0.28);
        }
        .grouped-mitra-header {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: var(--space-md);
          padding: var(--space-md);
          border-bottom: 1px solid var(--border-default);
          background: rgba(15, 23, 42, 0.48);
        }
        .grouped-mitra-header h3 {
          margin: 0;
          font-size: 16px;
          line-height: 1.35;
        }
        .grouped-mitra-header p {
          margin: 4px 0 0;
          color: var(--text-tertiary);
          font-size: 12px;
        }
        .grouped-mitra-totals {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 4px;
          color: var(--text-primary);
          font-weight: 800;
          white-space: nowrap;
        }
        .grouped-mitra-totals span:first-child {
          color: var(--color-success);
        }
        .grouped-table-container {
          border-radius: 0;
          border: 0;
        }
        .grouped-overall-total {
          display: flex;
          align-items: center;
          justify-content: flex-end;
          gap: var(--space-lg);
          padding: var(--space-md);
          border-top: 1px solid var(--border-default);
          color: var(--text-primary);
          font-weight: 800;
        }
        .grouped-overall-total span {
          color: var(--text-secondary);
        }
        .grouped-overall-total strong:first-of-type {
          color: var(--color-success);
        }

        /* Mode Tablet dan Laptop (768px ke atas) */
        @media (min-width: 768px) {
          .laporan-filter-card {
            padding: var(--space-md);
          }
          .laporan-filter-grid {
            grid-template-columns: minmax(145px, 0.7fr) minmax(145px, 0.7fr) minmax(260px, 1.4fr) minmax(150px, 0.7fr) minmax(150px, 0.7fr);
            gap: 24px;
          }
          .date-filter-item {
            justify-content: flex-start;
            gap: 12px;
          }
          .date-filter-label {
            font-size: 13px;
          }
          .date-filter-input {
            padding: 8px 12px;
            font-size: 14px;
          }
        }

        @media (max-width: 767px) {
          .selected-mitra-bar {
            flex-direction: column;
          }
          .selected-mitra-clear {
            width: 100%;
          }
          .grouped-mitra-header {
            flex-direction: column;
          }
          .grouped-mitra-totals {
            align-items: flex-start;
          }
          .grouped-overall-total {
            align-items: flex-start;
            flex-direction: column;
            gap: 6px;
          }
        }

        @media print {
          body * { visibility: hidden; }
          .print-area, .print-area * { visibility: visible; color: #000 !important; background: #fff !important; }
          .print-area { position: absolute; left: 0; top: 0; width: 100%; box-shadow: none !important; padding: 0 !important; }
          .no-print { display: none !important; }
        }
      `}</style>
    </AppShell>
  );
}
