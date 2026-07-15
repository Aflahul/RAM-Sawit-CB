// ============================================================================
// Sawit CB — Kalkulasi Transaksi Mitra
// ============================================================================
//
// RUMUS BISNIS (P0):
//   berat_dibayar      = berat_netto_pabrik_kg - potongan_pabrik_kg
//   total_kotor        = berat_dibayar x harga_pabrik_per_kg
//   total_nilai_bersih = berat_dibayar x (harga_pabrik - fee_owner)
//   total_fee_owner    = berat_dibayar x fee_owner_per_kg
//   biaya_sewa_armada  = berat_netto_pabrik_kg x TARIF_SEWA_ARMADA_CB_PER_KG
//
// Semua fungsi "resolve*" menyediakan fallback ke field lama (tonase) agar
// data sebelum migration tetap terbaca dengan benar.
// ============================================================================

// ---------------------------------------------------------------------------
// Konstanta bisnis
// ---------------------------------------------------------------------------

/** 
 * Konstanta tarif sewa armada telah dihapus (P1). 
 * Tarif sekarang bersifat dinamis per Mitra dan ditarik dari history/master.
 */

// ---------------------------------------------------------------------------
// Helpers dasar
// ---------------------------------------------------------------------------

export function toNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

// ---------------------------------------------------------------------------
// Resolver berat
// ---------------------------------------------------------------------------

/**
 * Berat netto dari pabrik (angka di nota/timbangan pabrik).
 * Fallback ke tonase lama untuk data sebelum migration.
 */
export function resolveBeratNettoPabrik(row) {
  if (row?.berat_netto_pabrik_kg != null) return toNumber(row.berat_netto_pabrik_kg);
  return toNumber(row?.tonase);
}

/**
 * Berat dibayar = berat netto - potongan pabrik.
 * Ini basis semua kalkulasi uang (fee, nilai bersih, total kotor).
 * Fallback ke tonase lama untuk data sebelum migration.
 */
export function resolveBeratDibayar(row) {
  if (row?.berat_dibayar_kg != null) return toNumber(row.berat_dibayar_kg);
  // Hitung dari netto dan potongan jika tersedia
  if (row?.berat_netto_pabrik_kg != null) {
    return Math.max(0, toNumber(row.berat_netto_pabrik_kg) - toNumber(row.potongan_pabrik_kg));
  }
  return toNumber(row?.tonase);
}

/**
 * Potongan pabrik dalam kg.
 */
export function resolvePotonganPabrik(row) {
  return toNumber(row?.potongan_pabrik_kg);
}

// ---------------------------------------------------------------------------
// Resolver sewa Armada CB
// ---------------------------------------------------------------------------

/**
 * Apakah transaksi ini memakai Armada CB?
 */
export function isPakaiSewaArmadaBL(row) {
  return Boolean(row?.pakai_sewa_armada_bl);
}

/**
 * Total biaya sewa Armada CB.
 * Dihitung dari BERAT NETTO (bukan berat dibayar).
 * Uang jalan/perongkosan adalah biaya sopir yang terpisah dan tidak mengurangi
 * sewa yang dibebankan kepada mitra.
 */
export function resolveBiayaSewaArmada(row) {
  if (row?.pakai_sewa_armada_bl) {
    if (row?.biaya_sewa_armada_kotor != null) return toNumber(row.biaya_sewa_armada_kotor);

    const tarif = toNumber(
      row?.tarif_sewa_angkut_per_kg_snapshot
      ?? row?.biaya_sewa_armada_per_kg
    );
    if (tarif > 0) return Math.round(resolveBeratNettoPabrik(row) * tarif);

    return toNumber(row?.biaya_sewa_armada_total);
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Resolver fee dan harga
// ---------------------------------------------------------------------------

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
  const beratDibayar = resolveBeratDibayar(row);
  const masterFee = resolveMasterFeePerKg(row);

  if (hasStaleZeroFeeSnapshot(row)) return masterFee;

  if (row?.fee_owner_per_kg != null) return toNumber(row.fee_owner_per_kg);
  if (row?.total_fee_owner != null && beratDibayar > 0) {
    return toNumber(row.total_fee_owner) / beratDibayar;
  }
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

// ---------------------------------------------------------------------------
// Resolver total nilai (semua memakai BERAT DIBAYAR)
// ---------------------------------------------------------------------------

/**
 * Total fee owner. Basis: berat_dibayar x fee_owner_per_kg.
 */
export function resolveTotalFeeOwner(row) {
  if (row?.total_fee_owner != null && !hasStaleZeroFeeSnapshot(row)) return toNumber(row.total_fee_owner);
  return Math.round(resolveBeratDibayar(row) * resolveFeePerKg(row));
}

/**
 * Total kotor pabrik = berat_dibayar x harga_pabrik_per_kg.
 * Ini mencerminkan nilai aktual yang pabrik bayarkan ke owner.
 */
export function resolveTotalKotorPabrik(row) {
  const hargaPabrik = resolveHargaPabrikPerKg(row);
  if (hargaPabrik > 0) return Math.round(resolveBeratDibayar(row) * hargaPabrik);
  return toNumber(row?.total_kotor);
}

/**
 * Total nilai bersih mitra = berat_dibayar x harga_bersih_per_kg.
 * Ini hak mitra sebelum dipotong panjar dan sewa armada.
 */
export function resolveTotalNilaiBersihMitra(row) {
  if (row?.total_nilai_bersih != null && !hasStaleZeroFeeSnapshot(row)) return toNumber(row.total_nilai_bersih);

  const hargaBersih = resolveHargaBersihPerKg(row);
  if (hargaBersih > 0) return Math.round(resolveBeratDibayar(row) * hargaBersih);

  return toNumber(row?.total_kotor);
}

// ---------------------------------------------------------------------------
// Kalkulasi lengkap satu baris transaksi
// ---------------------------------------------------------------------------

/**
 * Hitung semua nilai dari satu baris transaksi mitra.
 * Gunakan ini saat membutuhkan semua angka sekaligus (form review, kwitansi, laporan).
 *
 * @param {object} row - baris transaksi_mitra (atau form state)
 * @param {number} [hargaPabrikOverride] - override harga pabrik (untuk form input real-time)
 * @param {number} [feeOwnerOverride]    - override fee owner (untuk form input real-time)
 * @returns {object} semua nilai kalkulasi
 */
export function kalkulasiTransaksiMitra(row, hargaPabrikOverride, feeOwnerOverride) {
  const beratNetto   = resolveBeratNettoPabrik(row);
  const potongan     = resolvePotonganPabrik(row);
  const beratDibayar = Math.max(0, beratNetto - potongan);

  const hargaPabrik  = hargaPabrikOverride != null ? toNumber(hargaPabrikOverride) : resolveHargaPabrikPerKg(row);
  const feeOwner     = feeOwnerOverride    != null ? toNumber(feeOwnerOverride)    : resolveFeePerKg(row);
  const hargaBersih  = Math.max(0, hargaPabrik - feeOwner);

  const totalKotor       = Math.round(beratDibayar * hargaPabrik);
  const totalFeeOwner    = Math.round(beratDibayar * feeOwner);
  const totalNilaiBersih = Math.round(beratDibayar * hargaBersih);

  const pakaiSewaArmada  = isPakaiSewaArmadaBL(row);
  
  const sewaAngkutPerKg = toNumber(row?.tarif_sewa_angkut_per_kg_snapshot);
  const biayaSewaArmadaKotor = pakaiSewaArmada ? Math.round(beratNetto * sewaAngkutPerKg) : 0;
  const sewaArmadaTotal  = pakaiSewaArmada ? biayaSewaArmadaKotor : 0;

  // Uang yang benar-benar diterima mitra setelah semua potongan kwitansi
  // (panjar dipotong terpisah saat kwitansi dibayar, bukan di sini)
  const totalBersihSetelahSewaArmada = totalNilaiBersih - sewaArmadaTotal;

  return {
    beratNetto,
    potongan,
    beratDibayar,
    hargaPabrik,
    feeOwner,
    hargaBersih,
    totalKotor,
    totalFeeOwner,
    totalNilaiBersih,
    pakaiSewaArmada,
    sewaAngkutPerKg,
    biayaSewaArmadaKotor,
    sewaArmadaTotal,
    totalBersihSetelahSewaArmada,
  };
}

// ---------------------------------------------------------------------------
// Deteksi sewa Armada CB


/**
 * Hitung apakah transaksi ini kena sewa armada, dan berapa biayanya.
 *
 * @param {object} params
 * @param {boolean} params.isArmadaCB - flag apakah sopir ini armada CB
 * @param {number} params.beratNettoPabrikKg - berat netto dari pabrik (untuk hitung biaya)
 * @returns {{ pakaiSewaArmada: boolean, biayaSewaArmadaPerKg: number, biayaSewaArmadaTotal: number }}
 */
export function hitungSewaArmadaCB({ isArmadaCB, beratNettoPabrikKg, tarifSewaAngkut = 0 }) {
  const berat = toNumber(beratNettoPabrikKg);

  if (!isArmadaCB) {
    return { pakaiSewaArmada: false, biayaSewaArmadaKotor: 0, biayaSewaArmadaTotal: 0 };
  }

  const biayaSewaArmadaKotor = Math.round(berat * tarifSewaAngkut);

  return {
    pakaiSewaArmada: true,
    biayaSewaArmadaKotor,
    biayaSewaArmadaTotal: biayaSewaArmadaKotor,
  };
}

// ---------------------------------------------------------------------------
// Resolve fee snapshot history (tidak berubah dari versi sebelumnya)
// ---------------------------------------------------------------------------

export function resolveEffectiveMitraFeeSnapshot({ mitraId, tanggal, mitras = [], feeHistories = [] }) {
  const fallbackMitra = mitras.find(item => item.id === mitraId);
  if (!mitraId || !fallbackMitra) {
    return {
      fee: 0,
      tarifSewaAngkut: 0,
      historyId: '',
    };
  }

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
      tarifSewaAngkut: toNumber(fallbackMitra?.tarif_sewa_angkut_per_kg),
      historyId: sameFeeHistory?.id || '',
    };
  }

  return {
    fee: history ? historyFee : masterFee,
    tarifSewaAngkut: toNumber(history?.tarif_sewa_angkut_per_kg ?? fallbackMitra?.tarif_sewa_angkut_per_kg),
    historyId: history?.id || '',
  };
}
