export const PASSWORD_MIN_LENGTH = 12;
export const PASSWORD_HTML_PATTERN = '(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])(?=.*[^A-Za-z0-9]).{12,}';
export const PASSWORD_REQUIREMENTS_MESSAGE =
  'Password minimal 12 karakter dan wajib memuat huruf kecil, huruf besar, angka, serta simbol.';

const ALLOWED_PASSWORD_SYMBOLS = "!@#$%^&*()_+-=[]{};'\\:\"|?,./`~";

export function isStrongPassword(value) {
  return typeof value === 'string'
    && value.length >= PASSWORD_MIN_LENGTH
    && /[a-z]/.test(value)
    && /[A-Z]/.test(value)
    && /[0-9]/.test(value)
    && [...value].some(character => ALLOWED_PASSWORD_SYMBOLS.includes(character));
}
