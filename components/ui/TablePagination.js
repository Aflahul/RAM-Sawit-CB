import { ChevronsLeft, ChevronsRight, ChevronLeft, ChevronRight } from 'lucide-react';

export default function TablePagination({
  page,
  totalPages,
  totalItems,
  startIndex,
  endIndex,
  onPageChange,
}) {
  if (totalItems <= 0 || totalPages <= 1) return null;

  return (
    <div className="table-pagination">
      <div className="table-pagination-info">
        Menampilkan {startIndex}-{endIndex} dari {totalItems} data
      </div>
      <div className="table-pagination-actions">
        <button
          type="button"
          className="btn btn-ghost btn-sm btn-icon"
          onClick={() => onPageChange(1)}
          disabled={page <= 1}
          title="Halaman pertama"
        >
          <ChevronsLeft size={16} />
        </button>
        <button
          type="button"
          className="btn btn-ghost btn-sm btn-icon"
          onClick={() => onPageChange(page - 1)}
          disabled={page <= 1}
          title="Halaman sebelumnya"
        >
          <ChevronLeft size={16} />
        </button>
        <span className="table-pagination-page">
          {page} / {totalPages}
        </span>
        <button
          type="button"
          className="btn btn-ghost btn-sm btn-icon"
          onClick={() => onPageChange(page + 1)}
          disabled={page >= totalPages}
          title="Halaman berikutnya"
        >
          <ChevronRight size={16} />
        </button>
        <button
          type="button"
          className="btn btn-ghost btn-sm btn-icon"
          onClick={() => onPageChange(totalPages)}
          disabled={page >= totalPages}
          title="Halaman terakhir"
        >
          <ChevronsRight size={16} />
        </button>
      </div>
    </div>
  );
}
