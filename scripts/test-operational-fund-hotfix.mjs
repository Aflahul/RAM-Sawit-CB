import assert from 'node:assert/strict';

import {
  kalkulasiTransaksiMitra,
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

assert.equal(calculation.sewaArmadaTotal, 1_639_500);
assert.equal(calculation.danaOperasionalTrip, 750_000);
assert.equal(
  calculation.marginArmadaSetelahDanaTrip,
  889_500,
  'Margin armada harus memperhitungkan Dana Trip tanpa mengubah hak mitra dua kali.',
);
assert.equal(
  calculation.totalBersihSetelahSewaArmada,
  calculation.totalNilaiBersih - calculation.sewaArmadaTotal,
  'Dana Trip dibayar terpisah dan tidak boleh dipotong lagi dari kwitansi mitra.',
);

console.log('operational_fund_hotfix_js_ok');
