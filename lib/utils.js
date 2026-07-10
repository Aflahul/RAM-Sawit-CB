/**
 * Utility functions for Sawit CB
 */

/**
 * Format angka ke format Rupiah Indonesia
 * @param {number} amount
 * @returns {string} contoh: "Rp 1.250.000"
 */
export function formatRupiah(amount) {
  if (amount == null || isNaN(amount)) return 'Rp 0';
  return 'Rp ' + new Intl.NumberFormat('id-ID').format(Math.round(amount));
}

/**
 * Format angka dengan separator ribuan (tanpa "Rp")
 * @param {number} num
 * @returns {string} contoh: "1.250.000"
 */
export function formatNumber(num) {
  if (num == null || isNaN(num)) return '0';
  return new Intl.NumberFormat('id-ID').format(num);
}

/**
 * Format tanggal ke format Indonesia
 * @param {string|Date} date
 * @param {object} options
 * @returns {string} contoh: "Senin, 07 Juli 2025"
 */
export function formatTanggal(date, options = {}) {
  const d = new Date(date);
  const defaultOptions = {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    ...options,
  };
  return d.toLocaleDateString('id-ID', defaultOptions);
}

/**
 * Format tanggal pendek
 * @param {string|Date} date
 * @returns {string} contoh: "07/07/2025"
 */
export function formatTanggalPendek(date) {
  const d = new Date(date);
  return d.toLocaleDateString('id-ID', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });
}

/**
 * Format waktu
 * @param {string|Date} date
 * @returns {string} contoh: "14:32"
 */
export function formatWaktu(date) {
  const d = new Date(date);
  return d.toLocaleTimeString('id-ID', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
}

/**
 * Generate nomor struk otomatis
 * @param {string} prefix - contoh: "TBS"
 * @param {number} sequence - nomor urut hari itu
 * @returns {string} contoh: "TBS-20250707-001"
 */
export function generateNoStruk(prefix = 'TBS', sequence = 1) {
  const today = new Date();
  const dateStr =
    today.getFullYear().toString() +
    (today.getMonth() + 1).toString().padStart(2, '0') +
    today.getDate().toString().padStart(2, '0');
  return `${prefix}-${dateStr}-${sequence.toString().padStart(3, '0')}`;
}

/**
 * Hitung berat bersih
 * @param {number} beratKotor - kg
 * @param {number} persenPotongan - % (contoh: 2 untuk 2%)
 * @returns {number} berat bersih
 */
export function hitungBeratBersih(beratKotor, persenPotongan = 2) {
  return beratKotor * (1 - persenPotongan / 100);
}

/**
 * Hitung total harga TBS
 * @param {number} beratBersih - kg
 * @param {number} hargaPerKg - Rp
 * @returns {number}
 */
export function hitungTotalHarga(beratBersih, hargaPerKg) {
  return Math.round(beratBersih * hargaPerKg);
}

/**
 * Get tanggal hari ini dalam format YYYY-MM-DD (untuk input[type="date"])
 * Menggunakan timezone WITA (UTC+8)
 * @returns {string} contoh: "2025-07-10"
 */
export function getTodayISO() {
  // WITA = UTC+8 → offset 8 jam
  const WITA_OFFSET_MS = 8 * 60 * 60 * 1000;
  const nowUTC = new Date();
  const nowWITA = new Date(nowUTC.getTime() + WITA_OFFSET_MS);
  return nowWITA.toISOString().split('T')[0];
}

/**
 * Truncate text
 * @param {string} text
 * @param {number} maxLength
 * @returns {string}
 */
export function truncate(text, maxLength = 30) {
  if (!text) return '';
  if (text.length <= maxLength) return text;
  return text.substring(0, maxLength) + '...';
}

/**
 * Debounce function
 * @param {Function} fn
 * @param {number} delay
 * @returns {Function}
 */
export function debounce(fn, delay = 300) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
}

/**
 * Kapitalisasi kata pertama
 * @param {string} str
 * @returns {string}
 */
export function capitalize(str) {
  if (!str) return '';
  return str.charAt(0).toUpperCase() + str.slice(1).toLowerCase();
}
