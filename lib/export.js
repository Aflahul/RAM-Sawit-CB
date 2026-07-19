function sanitizeFilename(filename) {
  const safeName = String(filename || 'laporan.xlsx')
    .replace(/[\\/:*?"<>|]+/g, '-')
    .replace(/\s+/g, '-');
  return safeName.toLowerCase().endsWith('.xlsx') ? safeName : `${safeName}.xlsx`;
}

function sanitizeSheetName(name) {
  return String(name || 'Sheet')
    .replace(/[\\/?*[\]:]+/g, ' ')
    .trim()
    .slice(0, 31) || 'Sheet';
}

function cell(value, style = {}) {
  return { value: value ?? '', ...style };
}

function tableSheet(name, rows, widths) {
  const headers = rows.length > 0 ? Object.keys(rows[0]) : [];
  const headerStyle = {
    fontWeight: 'bold',
    textColor: '#FFFFFF',
    backgroundColor: '#047857',
    align: 'center',
    alignVertical: 'center',
  };

  return {
    sheet: sanitizeSheetName(name),
    data: [
      headers.map((header) => cell(header, headerStyle)),
      ...rows.map((row) => headers.map((header) => cell(row[header]))),
    ],
    columns: headers.map((header, index) => ({
      width: widths?.[index] || Math.min(
        Math.max(header.length + 2, ...rows.map((row) => String(row[header] ?? '').length + 2)),
        40,
      ),
    })),
    stickyRowsCount: 1,
  };
}

async function writeSheets(filename, sheets) {
  const { default: writeExcelFile } = await import('write-excel-file/browser');
  await writeExcelFile(sheets).toFile(sanitizeFilename(filename));
}

/**
 * Export data ke Excel (.xlsx).
 * @param {Array<Object>} data - Array of objects
 * @param {Array<{key: string, label: string, format?: function}>} columns - Column definitions
 * @param {string} filename - Nama file (tanpa .xlsx)
 * @param {string} sheetName - Nama sheet
 */
export async function exportToExcel(data, columns, filename = 'laporan', sheetName = 'Data') {
  const rows = data.map((row) => Object.fromEntries(columns.map((column) => [
    column.label,
    column.format ? column.format(row[column.key], row) : (row[column.key] ?? ''),
  ])));

  await writeSheets(filename, [tableSheet(sheetName, rows)]);
}

/** Export laporan harian ke Excel dengan multiple sections. */
export async function exportLaporanHarian(tanggal, data) {
  const sheets = [];

  if (data.tbs?.length > 0) {
    const rows = data.tbs.map((transaction) => ({
      'No Struk': transaction.no_struk,
      Petani: transaction.petani?.nama || '-',
      'Berat Kotor (kg)': transaction.berat_kotor_kg ?? transaction.berat_kotor,
      'Potongan (%)': transaction.potongan_value ?? transaction.persen_potongan,
      'Berat Bersih (kg)': transaction.berat_bersih_kg ?? transaction.berat_bersih,
      'Harga /kg': transaction.harga_per_kg,
      'Total Harga': transaction.total_harga,
      'Potong Pinjaman': transaction.potongan_hutang,
      'Bayar Tunai': transaction.total_bayar_tunai,
    }));
    sheets.push(tableSheet('Pembelian TBS', rows, [18, 20, 14, 12, 14, 12, 14, 14, 14]));
  }

  if (data.biaya?.length > 0) {
    const rows = data.biaya.map((cost) => ({
      Kategori: cost.kategori,
      Keterangan: cost.keterangan || '-',
      Jumlah: cost.jumlah,
    }));
    sheets.push(tableSheet('Biaya Operasional', rows, [20, 30, 15]));
  }

  sheets.push(tableSheet('Ringkasan', [
    { Keterangan: 'Total TBS Masuk (kg)', Nilai: data.totalTBSKg || 0 },
    { Keterangan: 'Total Pembelian TBS', Nilai: data.totalTBSRp || 0 },
    { Keterangan: 'Bayar Tunai', Nilai: data.totalBayarTunai || 0 },
    { Keterangan: 'Potong Pinjaman', Nilai: data.totalPotongHutang || 0 },
    { Keterangan: 'Total Biaya Operasional', Nilai: data.totalBiaya || 0 },
    { Keterangan: 'TOTAL UANG KELUAR', Nilai: data.totalKeluar || 0 },
  ], [28, 18]));

  await writeSheets(`Laporan_Harian_${tanggal}`, sheets);
}

/** Export laporan laba rugi ke Excel. */
export async function exportLabaRugi(periode, data) {
  const rows = [
    { Keterangan: '=== PENDAPATAN ===', Jumlah: '' },
    { Keterangan: 'Penjualan ke Pabrik', Jumlah: data.totalPendapatan },
    { Keterangan: '', Jumlah: '' },
    { Keterangan: '=== PENGELUARAN ===', Jumlah: '' },
    { Keterangan: 'Pembelian TBS', Jumlah: data.totalPembelian },
  ];

  if (data.biayaPerKategori) {
    const categoryLabels = {
      solar: 'Solar / BBM',
      gaji_sopir: 'Gaji Sopir',
      dana_operasional_trip: 'Dana Operasional Trip Armada CB',
      kuli: 'Kuli Bongkar',
      retribusi: 'Retribusi',
      perawatan: 'Perawatan',
      lainnya: 'Lainnya',
    };
    Object.entries(data.biayaPerKategori).forEach(([category, amount]) => {
      rows.push({ Keterangan: categoryLabels[category] || category, Jumlah: amount });
    });
  }

  rows.push(
    { Keterangan: 'Total Pengeluaran', Jumlah: data.totalPengeluaran },
    { Keterangan: '', Jumlah: '' },
    {
      Keterangan: data.labaBersih >= 0 ? '*** LABA BERSIH ***' : '*** RUGI BERSIH ***',
      Jumlah: data.labaBersih,
    },
  );

  await writeSheets(`Laba_Rugi_${periode}`, [tableSheet('Laba Rugi', rows, [28, 18])]);
}
