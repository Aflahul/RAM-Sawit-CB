export function getNextSort(currentSort, key, defaultDirection = 'asc') {
  if (currentSort?.key !== key) {
    return { key, direction: defaultDirection };
  }

  return {
    key,
    direction: currentSort.direction === 'asc' ? 'desc' : 'asc',
  };
}

function normalizeSortValue(value) {
  if (value == null) return '';
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  if (typeof value === 'boolean') return value ? 1 : 0;
  return String(value).trim().toLowerCase();
}

function compareSortValues(a, b) {
  const normalizedA = normalizeSortValue(a);
  const normalizedB = normalizeSortValue(b);

  if (typeof normalizedA === 'number' && typeof normalizedB === 'number') {
    return normalizedA - normalizedB;
  }

  return String(normalizedA).localeCompare(String(normalizedB), 'id-ID', {
    numeric: true,
    sensitivity: 'base',
  });
}

export function sortRows(rows, sort, accessors) {
  const accessor = accessors?.[sort?.key];
  if (!sort?.key || !accessor) return rows;

  const directionMultiplier = sort.direction === 'desc' ? -1 : 1;

  return [...rows]
    .map((row, index) => ({ row, index }))
    .sort((a, b) => {
      const result = compareSortValues(accessor(a.row), accessor(b.row));
      if (result !== 0) return result * directionMultiplier;
      return a.index - b.index;
    })
    .map(item => item.row);
}
