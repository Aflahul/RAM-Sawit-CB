export function getTotalPages(totalItems, pageSize) {
  return Math.max(1, Math.ceil(totalItems / pageSize));
}

export function clampPage(page, totalPages) {
  return Math.min(Math.max(Number(page) || 1, 1), totalPages);
}

export function paginateRows(rows, page, pageSize) {
  const totalPages = getTotalPages(rows.length, pageSize);
  const currentPage = clampPage(page, totalPages);
  const start = (currentPage - 1) * pageSize;

  return {
    rows: rows.slice(start, start + pageSize),
    page: currentPage,
    totalPages,
    startIndex: rows.length === 0 ? 0 : start + 1,
    endIndex: Math.min(start + pageSize, rows.length),
  };
}
