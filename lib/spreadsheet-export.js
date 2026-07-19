function sanitizeFilename(filename) {
  const safeName = String(filename || 'export.xlsx')
    .replace(/[\\/:*?"<>|]+/g, '-')
    .replace(/\s+/g, '-')
    .toLowerCase();
  return safeName.endsWith('.xlsx') ? safeName : `${safeName}.xlsx`;
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
  if (['number', 'currency', 'decimal'].includes(column.type)) {
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

const borderStyle = {
  borderColor: '#CBD5E1',
  borderStyle: 'thin',
};

function styledCell(value, style = {}) {
  return {
    value,
    alignVertical: 'center',
    wrap: true,
    ...borderStyle,
    ...style,
  };
}

function buildSheet(sheetConfig) {
  const columns = sheetConfig.columns || [];
  const rows = sheetConfig.rows || [];
  const footerRows = sheetConfig.footerRows || [];
  const data = [];

  if (sheetConfig.title) {
    data.push([
      styledCell(sheetConfig.title, {
        columnSpan: Math.max(columns.length, 1),
        fontWeight: 'bold',
        fontSize: 16,
        textColor: '#0F172A',
        backgroundColor: '#D1FAE5',
        align: 'center',
      }),
      ...Array(Math.max(columns.length - 1, 0)).fill(null),
    ]);
  }

  if (sheetConfig.subtitle) {
    data.push([
      styledCell(sheetConfig.subtitle, {
        columnSpan: Math.max(columns.length, 1),
        fontStyle: 'italic',
        textColor: '#475569',
        backgroundColor: '#ECFDF5',
        align: 'center',
      }),
      ...Array(Math.max(columns.length - 1, 0)).fill(null),
    ]);
  }

  if (data.length > 0) data.push(columns.map(() => styledCell('')));

  data.push(columns.map((column) => styledCell(column.header, {
    fontWeight: 'bold',
    textColor: '#FFFFFF',
    backgroundColor: '#047857',
    align: 'center',
  })));
  const headerRowCount = data.length;

  rows.forEach((row, rowIndex) => {
    data.push(columns.map((column) => {
      const numeric = ['number', 'currency', 'decimal'].includes(column.type);
      return styledCell(resolveCellValue(row, column, rowIndex), {
        align: column.align || (numeric ? 'right' : 'left'),
        backgroundColor: rowIndex % 2 === 0 ? '#FFFFFF' : '#F8FAFC',
        format: getColumnFormat(column),
      });
    }));
  });

  footerRows.forEach((row, rowIndex) => {
    data.push(columns.map((column) => {
      const numeric = ['number', 'currency', 'decimal'].includes(column.type);
      return styledCell(resolveCellValue(row, column, rowIndex), {
        align: column.align || (numeric ? 'right' : 'left'),
        fontWeight: 'bold',
        textColor: '#0F172A',
        backgroundColor: '#DCFCE7',
        format: getColumnFormat(column),
      });
    }));
  });

  return {
    data,
    sheet: sanitizeSheetName(sheetConfig.name),
    columns: columns.map((column) => ({
      width: column.width || Math.max(String(column.header || '').length + 4, 12),
    })),
    stickyRowsCount: headerRowCount,
  };
}

export async function exportStyledWorkbook({ filename, sheets }) {
  const { default: writeExcelFile } = await import('write-excel-file/browser');
  await writeExcelFile(sheets.map(buildSheet)).toFile(sanitizeFilename(filename));
}
