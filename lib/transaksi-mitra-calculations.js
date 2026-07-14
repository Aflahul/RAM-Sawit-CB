export function toNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

export function resolveMasterFeePerKg(row) {
  return toNumber(row?.master_mitra?.fee_per_kg ?? row?.mitra_fee_per_kg);
}

export function hasStaleZeroFeeSnapshot(row) {
  const masterFee = resolveMasterFeePerKg(row);
  if (masterFee <= 0) return false;

  const snapshotFee = row?.fee_owner_per_kg == null ? null : toNumber(row.fee_owner_per_kg);
  const totalFee = row?.total_fee_owner == null ? null : toNumber(row.total_fee_owner);

  return (snapshotFee == null || snapshotFee === 0) && (totalFee == null || totalFee === 0);
}

export function hasFeeSnapshot(row) {
  if (hasStaleZeroFeeSnapshot(row)) return false;
  return row?.fee_owner_per_kg != null || row?.total_fee_owner != null;
}

export function resolveFeePerKg(row) {
  const tonase = toNumber(row?.tonase);
  const masterFee = resolveMasterFeePerKg(row);

  if (hasStaleZeroFeeSnapshot(row)) return masterFee;

  if (row?.fee_owner_per_kg != null) return toNumber(row.fee_owner_per_kg);
  if (row?.total_fee_owner != null && tonase > 0) return toNumber(row.total_fee_owner) / tonase;
  if (row?.harga_pabrik_per_kg != null && row?.harga_bersih_per_kg != null) {
    return Math.max(0, toNumber(row.harga_pabrik_per_kg) - toNumber(row.harga_bersih_per_kg));
  }

  return masterFee;
}

export function resolveHargaBersihPerKg(row) {
  if (row?.harga_bersih_per_kg != null && !hasStaleZeroFeeSnapshot(row)) return toNumber(row.harga_bersih_per_kg);

  const feePerKg = resolveFeePerKg(row);
  if (row?.harga_pabrik_per_kg != null) return Math.max(0, toNumber(row.harga_pabrik_per_kg) - feePerKg);
  if (feePerKg > 0 && row?.harga_harian != null) return Math.max(0, toNumber(row.harga_harian) - feePerKg);

  return toNumber(row?.harga_harian);
}

export function resolveHargaPabrikPerKg(row) {
  if (row?.harga_pabrik_per_kg != null) return toNumber(row.harga_pabrik_per_kg);
  if (hasStaleZeroFeeSnapshot(row) && row?.harga_harian != null) return toNumber(row.harga_harian);

  const feePerKg = resolveFeePerKg(row);
  const hargaBersih = resolveHargaBersihPerKg(row);
  if (hargaBersih > 0 && feePerKg > 0) return hargaBersih + feePerKg;

  return toNumber(row?.harga_harian);
}

export function resolveTotalFeeOwner(row) {
  if (row?.total_fee_owner != null && !hasStaleZeroFeeSnapshot(row)) return toNumber(row.total_fee_owner);
  return Math.round(toNumber(row?.tonase) * resolveFeePerKg(row));
}

export function resolveTotalKotorPabrik(row) {
  const hargaPabrik = resolveHargaPabrikPerKg(row);
  if (hargaPabrik > 0) return Math.round(toNumber(row?.tonase) * hargaPabrik);
  return toNumber(row?.total_kotor);
}

export function resolveTotalNilaiBersihMitra(row) {
  if (row?.total_nilai_bersih != null && !hasStaleZeroFeeSnapshot(row)) return toNumber(row.total_nilai_bersih);

  const hargaBersih = resolveHargaBersihPerKg(row);
  if (hargaBersih > 0) return Math.round(toNumber(row?.tonase) * hargaBersih);

  return toNumber(row?.total_kotor);
}

export function resolveEffectiveMitraFeeSnapshot({ mitraId, tanggal, mitras = [], feeHistories = [] }) {
  const fallbackMitra = mitras.find(item => item.id === mitraId);
  const masterFee = toNumber(fallbackMitra?.fee_per_kg);
  const tanggalValue = tanggal;
  const history = feeHistories.find(item => {
    if (item.master_mitra_id !== mitraId) return false;
    if (item.berlaku_mulai && tanggalValue < item.berlaku_mulai) return false;
    if (item.berlaku_sampai && tanggalValue > item.berlaku_sampai) return false;
    return true;
  });
  const historyFee = toNumber(history?.fee_per_kg);
  const isInitialSnapshot = String(history?.alasan_perubahan || '').startsWith('Snapshot awal Fee Owner');
  const sameFeeHistory = feeHistories.find(item => {
    if (item.master_mitra_id !== mitraId) return false;
    if (toNumber(item.fee_per_kg) !== masterFee) return false;
    if (item.berlaku_mulai && tanggalValue < item.berlaku_mulai) return false;
    if (item.berlaku_sampai && tanggalValue > item.berlaku_sampai) return false;
    return true;
  });
  const hasStaleHistoryFee = Boolean(history && masterFee > 0 && historyFee === 0);
  const shouldPreferMaster = Boolean(
    masterFee > 0
    && (
      !history
      || hasStaleHistoryFee
      || (isInitialSnapshot && historyFee !== masterFee)
    )
  );

  if (shouldPreferMaster) {
    return {
      fee: masterFee,
      historyId: sameFeeHistory?.id || '',
    };
  }

  return {
    fee: historyFee,
    historyId: history.id || '',
  };
}
