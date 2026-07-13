function sanitizeFilename(filename) {
  return String(filename || 'export.xlsx')
    .replace(/[\\/:*?"<>|]+/g, '-')
    .replace(/\s+/g, '-')
    .toLowerCase();
}

function sanitizeSheetName(name) {
  return String(name || 'Sheet')
    .replace(/[\\/?*[\]:]+/g, ' ')
    .trim()
    .slice(0, 31) || 'Sheet';
}

function resolveCellValue(row, column, rowIndex) {
  const value = typeof column.value === 'function'
    ? column.value(row, rowIndex)
    : row?.[column.key];

  if (value == null || value === '') return '';
  if (column.type === 'number' || column.type === 'currency' || column.type === 'decimal') {
    const number = Number(value);
    return Number.isFinite(number) ? number : '';
  }
  return value;
}

function getColumnFormat(column) {
  if (column.numFmt) return column.numFmt;
  if (column.type === 'currency') return '#,##0';
  if (column.type === 'decimal') return '#,##0.000';
  if (column.type === 'number') return '#,##0';
  return undefined;
}

function applyCellStyle(cell, style) {
  if (!cell) return;
  cell.s = {
    ...(cell.s || {}),
    ...style,
    border: {
      top: { style: 'thin', color: { rgb: 'CBD5E1' } },
      right: { style: 'thin', color: { rgb: 'CBD5E1' } },
      bottom: { style: 'thin', color: { rgb: 'CBD5E1' } },
      left: { style: 'thin', color: { rgb: 'CBD5E1' } },
    },
  };
}

function buildWorksheet(XLSX, sheetConfig) {
  const columns = sheetConfig.columns || [];
  const rows = sheetConfig.rows || [];
  const footerRows = sheetConfig.footerRows || [];
  const aoa = [];
  const merges = [];

  if (sheetConfig.title) {
    aoa.push([sheetConfig.title]);
    if (columns.length > 1) {
      merges.push({ s: { r: 0, c: 0 }, e: { r: 0, c: columns.length - 1 } });
    }
  }

  if (sheetConfig.subtitle) {
    aoa.push([sheetConfig.subtitle]);
    if (columns.length > 1) {
      merges.push({ s: { r: aoa.length - 1, c: 0 }, e: { r: aoa.length - 1, c: columns.length - 1 } });
    }
  }

  if (aoa.length > 0) aoa.push([]);

  const headerRowIndex = aoa.length;
  aoa.push(columns.map(column => column.header));
  const dataStartIndex = aoa.length;

  rows.forEach((row, rowIndex) => {
    aoa.push(columns.map(column => resolveCellValue(row, column, rowIndex)));
  });

  const footerStartIndex = aoa.length;
  footerRows.forEach((row, rowIndex) => {
    aoa.push(columns.map(column => resolveCellValue(row, column, rowIndex)));
  });

  const worksheet = XLSX.utils.aoa_to_sheet(aoa);
  worksheet['!cols'] = columns.map(column => ({ wch: column.width || Math.max(String(column.header || '').length + 4, 12) }));
  worksheet['!merges'] = merges;

  if (rows.length > 0) {
    worksheet['!autofilter'] = {
      ref: XLSX.utils.encode_range({
        s: { r: headerRowIndex, c: 0 },
        e: { r: headerRowIndex + rows.length, c: Math.max(columns.length - 1, 0) },
      }),
    };
  }

  const titleStyle = {
    font: { bold: true, sz: 16, color: { rgb: '0F172A' } },
    fill: { fgColor: { rgb: 'D1FAE5' } },
    alignment: { horizontal: 'center', vertical: 'center' },
  };
  const subtitleStyle = {
    font: { italic: true, color: { rgb: '475569' } },
    fill: { fgColor: { rgb: 'ECFDF5' } },
    alignment: { horizontal: 'center', vertical: 'center' },
  };
  const headerStyle = {
    font: { bold: true, color: { rgb: 'FFFFFF' } },
    fill: { fgColor: { rgb: '047857' } },
    alignment: { horizontal: 'center', vertical: 'center', wrapText: true },
  };
  const evenRowStyle = { fill: { fgColor: { rgb: 'F8FAFC' } } };
  const oddRowStyle = { fill: { fgColor: { rgb: 'FFFFFF' } } };
  const footerStyle = {
    font: { bold: true, color: { rgb: '0F172A' } },
    fill: { fgColor: { rgb: 'DCFCE7' } },
  };

  for (let rowIndex = 0; rowIndex < aoa.length; rowIndex += 1) {
    for (let colIndex = 0; colIndex < columns.length; colIndex += 1) {
      const address = XLSX.utils.encode_cell({ r: rowIndex, c: colIndex });
      const cell = worksheet[address];
      if (!cell) continue;

      const column = columns[colIndex];
      const isNumeric = ['number', 'currency', 'decimal'].includes(column.type);
      const baseAlignment = {
        horizontal: column.align || (isNumeric ? 'right' : 'left'),
        vertical: 'center',
        wrapText: true,
      };
      const numFmt = getColumnFormat(column);

      if (rowIndex === 0 && sheetConfig.title) {
        applyCellStyle(cell, titleStyle);
      } else if (rowIndex === 1 && sheetConfig.subtitle) {
        applyCellStyle(cell, subtitleStyle);
      } else if (rowIndex === headerRowIndex) {
        applyCellStyle(cell, headerStyle);
      } else if (rowIndex >= footerStartIndex && footerRows.length > 0) {
        applyCellStyle(cell, { ...footerStyle, alignment: baseAlignment, numFmt });
      } else if (rowIndex >= dataStartIndex && rowIndex < footerStartIndex) {
        const zebraStyle = (rowIndex - dataStartIndex) % 2 === 0 ? oddRowStyle : evenRowStyle;
        applyCellStyle(cell, { ...zebraStyle, alignment: baseAlignment, numFmt });
      }
    }
  }

  return worksheet;
}

export async function exportStyledWorkbook({ filename, sheets }) {
  const xlsxModule = await import('xlsx-js-style');
  const XLSX = xlsxModule.default || xlsxModule;
  const workbook = XLSX.utils.book_new();

  sheets.forEach((sheetConfig) => {
    const worksheet = buildWorksheet(XLSX, sheetConfig);
    XLSX.utils.book_append_sheet(workbook, worksheet, sanitizeSheetName(sheetConfig.name));
  });

  XLSX.writeFile(workbook, sanitizeFilename(filename));
}
