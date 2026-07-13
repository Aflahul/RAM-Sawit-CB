import { ArrowDown, ArrowUp, ArrowUpDown } from 'lucide-react';

export default function SortableHeader({ label, sortKey, sort, onSort, align = 'left' }) {
  const isActive = sort?.key === sortKey;
  const Icon = !isActive ? ArrowUpDown : sort.direction === 'asc' ? ArrowUp : ArrowDown;
  const ariaSort = !isActive ? 'none' : sort.direction === 'asc' ? 'ascending' : 'descending';

  return (
    <th style={{ textAlign: align }} aria-sort={ariaSort}>
      <button
        type="button"
        className={`table-sort-button ${isActive ? 'is-active' : ''} ${align === 'right' ? 'align-right' : ''} ${align === 'center' ? 'align-center' : ''}`}
        onClick={() => onSort(sortKey)}
        title={`Urutkan berdasarkan ${label}`}
      >
        <span>{label}</span>
        <Icon size={14} aria-hidden="true" />
      </button>
    </th>
  );
}
