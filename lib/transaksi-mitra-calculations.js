export function toNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

export function hasFeeSnapshot(row) {
  return row?.fee_owner_per_kg != null || row?.total_fee_owner != null;
}

export function resolveFeePerKg(row) {
  const tonase = toNumber(row?.tonase);

  if (row?.fee_owner_per_kg != null) return toNumber(row.fee_owner_per_kg);
  if (row?.total_fee_owner != null && tonase > 0) return toNumber(row.total_fee_owner) / tonase;
  if (row?.harga_pabrik_per_kg != null && row?.harga_bersih_per_kg != null) {
    return Math.max(0, toNumber(row.harga_pabrik_per_kg) - toNumber(row.harga_bersih_per_kg));
  }

  return 0;
}

export function resolveHargaBersihPerKg(row) {
  if (row?.harga_bersih_per_kg != null) return toNumber(row.harga_bersih_per_kg);

  const feePerKg = resolveFeePerKg(row);
  if (row?.harga_pabrik_per_kg != null) return Math.max(0, toNumber(row.harga_pabrik_per_kg) - feePerKg);

  return toNumber(row?.harga_harian);
}

export function resolveHargaPabrikPerKg(row) {
  if (row?.harga_pabrik_per_kg != null) return toNumber(row.harga_pabrik_per_kg);

  const feePerKg = resolveFeePerKg(row);
  const hargaBersih = resolveHargaBersihPerKg(row);
  if (hargaBersih > 0 && feePerKg > 0) return hargaBersih + feePerKg;

  return toNumber(row?.harga_harian);
}

export function resolveTotalFeeOwner(row) {
  if (row?.total_fee_owner != null) return toNumber(row.total_fee_owner);
  return Math.round(toNumber(row?.tonase) * resolveFeePerKg(row));
}

export function resolveTotalKotorPabrik(row) {
  const hargaPabrik = resolveHargaPabrikPerKg(row);
  if (hargaPabrik > 0) return Math.round(toNumber(row?.tonase) * hargaPabrik);
  return toNumber(row?.total_kotor);
}

export function resolveTotalNilaiBersihMitra(row) {
  if (row?.total_nilai_bersih != null) return toNumber(row.total_nilai_bersih);

  const hargaBersih = resolveHargaBersihPerKg(row);
  if (hargaBersih > 0) return Math.round(toNumber(row?.tonase) * hargaBersih);

  return toNumber(row?.total_kotor);
}
