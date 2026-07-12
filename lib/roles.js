export const ROLES = {
  OWNER: 'owner',
  SUPER_ADMIN: 'super_admin',
  ADMIN_OPERASIONAL: 'admin_operasional',
  ADMIN_KEUANGAN: 'admin_keuangan',
};

const ROLE_LABELS = {
  [ROLES.OWNER]: 'Owner',
  [ROLES.SUPER_ADMIN]: 'Super Admin',
  [ROLES.ADMIN_OPERASIONAL]: 'Admin Operasional',
  [ROLES.ADMIN_KEUANGAN]: 'Admin Keuangan',
};

export function normalizeRole(role) {
  if (role === 'admin') return ROLES.ADMIN_OPERASIONAL;
  if (Object.values(ROLES).includes(role)) return role;
  return ROLES.ADMIN_OPERASIONAL;
}

export function getRoleLabel(role) {
  return ROLE_LABELS[normalizeRole(role)];
}

export function canViewProfit(role) {
  return [ROLES.OWNER, ROLES.SUPER_ADMIN].includes(normalizeRole(role));
}

export function canManageUsers(role) {
  return normalizeRole(role) === ROLES.SUPER_ADMIN;
}

export function canManageBusinessSettings(role) {
  return [ROLES.OWNER, ROLES.SUPER_ADMIN].includes(normalizeRole(role));
}
