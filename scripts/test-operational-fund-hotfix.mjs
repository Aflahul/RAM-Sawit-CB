import assert from 'node:assert/strict';

import {
  kalkulasiTransaksiMitra,
  resolveBiayaSewaArmada,
  resolveDanaOperasionalTrip,
} from '../lib/transaksi-mitra-calculations.js';

const transaction = {
  berat_netto_pabrik_kg: 10_930,
  potongan_pabrik_kg: 546,
  harga_pabrik_per_kg: 2_940,
  fee_owner_per_kg: 30,
  menggunakan_armada_cb_snapshot: true,
  pakai_sewa_armada_bl: true,
  kenakan_sewa_armada_cb: true,
  catat_dana_operasional_trip: true,
  tarif_sewa_angkut_per_kg_snapshot: 150,
  dana_operasional_trip_snapshot: 750_000,
};

assert.equal(
  resolveDanaOperasionalTrip(transaction),
  750_000,
  'Dana Operasional Trip yang dicentang harus terbaca dari snapshot transaksi.',
);
assert.equal(
  resolveDanaOperasionalTrip({
    ...transaction,
    dana_operasional_trip_snapshot: 0,
    total_biaya_sopir_cb_snapshot: 750_000,
  }),
  750_000,
  'Arsip transisi harus membaca snapshot kompatibilitas ketika snapshot utama masih nol.',
);

const calculation = kalkulasiTransaksiMitra(transaction);

assert.equal(calculation.danaOperasionalTrip, 750_000);
assert.equal(
  calculation.biayaSewaArmadaKotor,
  1_639_500,
  'Sewa kotor tetap harus tersedia sebagai dasar audit laporan armada.',
);
assert.equal(
  calculation.sewaArmadaTotal,
  889_500,
  'Potongan akhir sewa harus berupa sewa kotor dikurangi Dana Operasional yang dibayar Mitra.',
);
assert.equal(
  calculation.marginArmadaSetelahDanaTrip,
  889_500,
  'Sewa bersih CB sama dengan potongan akhir sewa setelah Dana Operasional.',
);
assert.equal(
  calculation.totalBersihSetelahSewaArmada,
  calculation.totalNilaiBersih - calculation.sewaArmadaTotal,
  'Kwitansi hanya boleh mengurangi potongan akhir sewa, bukan sewa kotor.',
);

assert.equal(
  resolveBiayaSewaArmada({
    ...transaction,
    biaya_sewa_armada_kotor: 1_639_500,
    biaya_sewa_armada_total: 1_639_500,
    dana_operasional_dibayar_mitra: null,
    biaya_sopir_dibayar_at: '2026-07-22T16:42:52.347183Z',
    status: 'aktif',
  }),
  889_500,
  'Transaksi aktif mengikuti keputusan Owner: Dana Operasional selalu sudah dibayar Mitra sebelum berangkat.',
);

assert.equal(
  resolveBiayaSewaArmada({
    ...transaction,
    biaya_sewa_armada_kotor: 1_639_500,
    biaya_sewa_armada_total: 1_639_500,
    dana_operasional_dibayar_mitra_snapshot: false,
    metode_sewa_armada_snapshot: 'legacy_snapshot',
    is_kwitansi_snapshot: true,
  }),
  1_639_500,
  'Kwitansi historis yang sudah terbit tetap memakai snapshot sumber dana saat diterbitkan.',
);

const calculationWithLargeOperationalFund = kalkulasiTransaksiMitra({
  ...transaction,
  dana_operasional_trip_snapshot: 2_000_000,
});
assert.equal(
  calculationWithLargeOperationalFund.sewaArmadaTotal,
  0,
  'Potongan akhir sewa tidak boleh menjadi negatif ketika Dana Operasional melebihi sewa kotor.',
);

console.log('operational_fund_hotfix_js_ok');
