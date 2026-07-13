function compactJoin(parts, separator = ' - ') {
  return parts
    .map(part => (part == null ? '' : String(part).trim()))
    .filter(Boolean)
    .join(separator);
}

export const MITRA_TYPES = {
  EKSTERNAL: 'eksternal',
  INTERNAL_OWNER: 'internal_owner',
};

export function getMitraTypeLabel(type) {
  if (type === MITRA_TYPES.INTERNAL_OWNER) return 'Internal Owner';
  return 'Mitra Eksternal';
}

export function getMitraTypeBadgeClass(type) {
  if (type === MITRA_TYPES.INTERNAL_OWNER) return 'badge-info';
  return 'badge-neutral';
}

export function formatMitraLabel(mitra) {
  return compactJoin([mitra?.kode, mitra?.alamat, mitra?.nama]);
}

export function formatSopirArmadaLabel(sopir) {
  return compactJoin([sopir?.nama, sopir?.plat_nomor]);
}

export function formatSopirArmadaDescription(sopir) {
  return formatMitraLabel(sopir?.master_mitra) || 'Tanpa default / armada bersama';
}

export function getMitraSearchText(mitra) {
  return compactJoin([
    mitra?.kode,
    mitra?.alamat,
    mitra?.nama,
    mitra?.penanggung_jawab,
    mitra?.no_hp,
    getMitraTypeLabel(mitra?.tipe_mitra),
  ], ' ');
}

export function getSopirArmadaSearchText(sopir) {
  return compactJoin([
    sopir?.nama,
    sopir?.plat_nomor,
    sopir?.no_hp,
    getMitraSearchText(sopir?.master_mitra),
  ], ' ');
}
