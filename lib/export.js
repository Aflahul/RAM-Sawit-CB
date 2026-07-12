import * as XLSX from 'xlsx';

/**
 * Export data ke Excel (.xlsx)
 * @param {Array<Object>} data - Array of objects
 * @param {Array<{key: string, label: string, format?: function}>} columns - Column definitions
 * @param {string} filename - Nama file (tanpa .xlsx)
 * @param {string} sheetName - Nama sheet
 */
export function exportToExcel(data, columns, filename = 'laporan', sheetName = 'Data') {
  // Transform data sesuai kolom
  const rows = data.map(row => {
    const obj = {};
    columns.forEach(col => {
      obj[col.label] = col.format ? col.format(row[col.key], row) : (row[col.key] ?? '');
    });
    return obj;
  });

  const ws = XLSX.utils.json_to_sheet(rows);

  // Auto-width columns
  const colWidths = columns.map(col => {
    const maxLen = Math.max(
      col.label.length,
      ...rows.map(r => String(r[col.label] || '').length)
    );
    return { wch: Math.min(maxLen + 2, 40) };
  });
  ws['!cols'] = colWidths;

  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, sheetName);

  XLSX.writeFile(wb, `${filename}.xlsx`);
}

/**
 * Export laporan harian ke Excel dengan multiple sections
 */
export function exportLaporanHarian(tanggal, data) {
  const wb = XLSX.utils.book_new();

  // Sheet 1: Pembelian TBS
  if (data.tbs && data.tbs.length > 0) {
    const tbsRows = data.tbs.map(t => ({
      'No Struk': t.no_struk,
      'Petani': t.petani?.nama || '-',
      'Berat Kotor (kg)': t.berat_kotor_kg ?? t.berat_kotor,
      'Potongan (%)': t.potongan_value ?? t.persen_potongan,
      'Berat Bersih (kg)': t.berat_bersih_kg ?? t.berat_bersih,
      'Harga /kg': t.harga_per_kg,
      'Total Harga': t.total_harga,
      'Potong Hutang': t.potongan_hutang,
      'Bayar Tunai': t.total_bayar_tunai,
    }));
    const ws1 = XLSX.utils.json_to_sheet(tbsRows);
    ws1['!cols'] = [
      { wch: 18 }, { wch: 20 }, { wch: 14 }, { wch: 12 },
      { wch: 14 }, { wch: 12 }, { wch: 14 }, { wch: 14 }, { wch: 14 },
    ];
    XLSX.utils.book_append_sheet(wb, ws1, 'Pembelian TBS');
  }

  // Sheet 2: Biaya
  if (data.biaya && data.biaya.length > 0) {
    const biayaRows = data.biaya.map(b => ({
      'Kategori': b.kategori,
      'Keterangan': b.keterangan || '-',
      'Jumlah': b.jumlah,
    }));
    const ws2 = XLSX.utils.json_to_sheet(biayaRows);
    ws2['!cols'] = [{ wch: 20 }, { wch: 30 }, { wch: 15 }];
    XLSX.utils.book_append_sheet(wb, ws2, 'Biaya Operasional');
  }

  // Sheet 3: Ringkasan
  const ringkasan = [
    { 'Keterangan': 'Total TBS Masuk (kg)', 'Nilai': data.totalTBSKg || 0 },
    { 'Keterangan': 'Total Pembelian TBS', 'Nilai': data.totalTBSRp || 0 },
    { 'Keterangan': 'Bayar Tunai', 'Nilai': data.totalBayarTunai || 0 },
    { 'Keterangan': 'Potong Hutang', 'Nilai': data.totalPotongHutang || 0 },
    { 'Keterangan': 'Total Biaya Operasional', 'Nilai': data.totalBiaya || 0 },
    { 'Keterangan': 'TOTAL UANG KELUAR', 'Nilai': data.totalKeluar || 0 },
  ];
  const ws3 = XLSX.utils.json_to_sheet(ringkasan);
  ws3['!cols'] = [{ wch: 28 }, { wch: 18 }];
  XLSX.utils.book_append_sheet(wb, ws3, 'Ringkasan');

  XLSX.writeFile(wb, `Laporan_Harian_${tanggal}.xlsx`);
}

/**
 * Export laporan laba rugi ke Excel
 */
export function exportLabaRugi(periode, data) {
  const wb = XLSX.utils.book_new();

  const rows = [
    { 'Keterangan': '=== PENDAPATAN ===', 'Jumlah': '' },
    { 'Keterangan': 'Penjualan ke Pabrik', 'Jumlah': data.totalPendapatan },
    { 'Keterangan': '', 'Jumlah': '' },
    { 'Keterangan': '=== PENGELUARAN ===', 'Jumlah': '' },
    { 'Keterangan': 'Pembelian TBS', 'Jumlah': data.totalPembelian },
  ];

  if (data.biayaPerKategori) {
    const kategoriLabel = {
      solar: 'Solar / BBM', gaji_sopir: 'Gaji Sopir', kuli: 'Kuli Bongkar',
      retribusi: 'Retribusi', perawatan: 'Perawatan', lainnya: 'Lainnya',
    };
    Object.entries(data.biayaPerKategori).forEach(([kat, jml]) => {
      rows.push({ 'Keterangan': kategoriLabel[kat] || kat, 'Jumlah': jml });
    });
  }

  rows.push(
    { 'Keterangan': 'Total Pengeluaran', 'Jumlah': data.totalPengeluaran },
    { 'Keterangan': '', 'Jumlah': '' },
    { 'Keterangan': data.labaBersih >= 0 ? '*** LABA BERSIH ***' : '*** RUGI BERSIH ***', 'Jumlah': data.labaBersih },
  );

  const ws = XLSX.utils.json_to_sheet(rows);
  ws['!cols'] = [{ wch: 28 }, { wch: 18 }];
  XLSX.utils.book_append_sheet(wb, ws, 'Laba Rugi');

  XLSX.writeFile(wb, `Laba_Rugi_${periode}.xlsx`);
}
