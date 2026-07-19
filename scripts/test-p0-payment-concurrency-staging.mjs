import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createClient } from '@supabase/supabase-js';

const execFileAsync = promisify(execFile);
const stagingRef = 'mfxyeybmjpcdckajfjen';
const productionRef = 'yavntiympbrjlouzkhnl';
const stagingUrl = `https://${stagingRef}.supabase.co`;
const runId = crypto.randomUUID().replaceAll('-', '').slice(0, 12);
const dayOffset = Number.parseInt(runId.slice(0, 4), 16) % 6900;
const fixtureDate = new Date(Date.UTC(2080, 0, 1 + dayOffset)).toISOString().slice(0, 10);
const email = `qa-payment-concurrency-${runId}@example.invalid`;
const password = `Qa-${crypto.randomUUID()}-9!`;
const userId = crypto.randomUUID();
const mitraId = crypto.randomUUID();
const sopirId = crypto.randomUUID();
const hargaId = crypto.randomUUID();
const rekeningId = crypto.randomUUID();

let admin;
let fixtureCreated = false;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function expectNoError(result, label) {
  if (result.error) throw new Error(`${label}: ${result.error.message}`);
  return result.data;
}

async function getStagingKeys() {
  const { stdout } = await execFileAsync(process.execPath, [
    'node_modules/supabase/dist/supabase.js',
    'projects', 'api-keys', '--project-ref', stagingRef, '-o', 'json',
  ], { windowsHide: true, maxBuffer: 2 * 1024 * 1024 });
  const keys = JSON.parse(stdout);
  const anonKey = keys.find((key) => key.name === 'anon')?.api_key
    || keys.find((key) => key.type === 'publishable')?.api_key;
  const serviceKey = keys.find((key) => key.name === 'service_role')?.api_key
    || keys.find((key) => key.type === 'secret')?.api_key;
  assert(anonKey && serviceKey, 'Kunci API staging tidak lengkap.');
  return { anonKey, serviceKey };
}

async function createFixture(serviceKey) {
  admin = createClient(stagingUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  await expectNoError(await admin.auth.admin.createUser({
    id: userId,
    email,
    password,
    email_confirm: true,
  }), 'Membuat pengguna QA');
  fixtureCreated = true;
  await expectNoError(await admin.from('users').insert({
    id: userId,
    nama: 'QA Payment Concurrency',
    username: `qa_pay_${runId}`,
    role: 'owner',
  }), 'Membuat profil QA');
  await expectNoError(await admin.from('master_mitra').insert({
    id: mitraId,
    nama: `QA Payment ${runId}`,
    kode: `QA-PAY-${runId.toUpperCase()}`,
    alamat: 'Fixture sementara staging',
    no_hp: '081234567892',
    fee_per_kg: 100,
    aktif: true,
    tipe_mitra: 'eksternal',
    tarif_sewa_angkut_per_kg: 0,
    dana_operasional_trip: 0,
    status_verifikasi: 'terverifikasi',
    dibuat_oleh: userId,
    diverifikasi_oleh: userId,
    diverifikasi_at: new Date().toISOString(),
  }), 'Membuat mitra QA');
  await expectNoError(await admin.from('sopir').insert({
    id: sopirId,
    nama: 'QA Sopir Payment',
    no_hp: '081234567893',
    mitra_id: mitraId,
    plat_nomor: `QA ${runId.slice(0, 4).toUpperCase()} PY`,
    is_armada_cb: false,
    aktif: true,
    status_verifikasi: 'terverifikasi',
    dibuat_oleh: userId,
    diverifikasi_oleh: userId,
    diverifikasi_at: new Date().toISOString(),
  }), 'Membuat sopir QA');
  await expectNoError(await admin.from('harga_tbs').insert({
    id: hargaId,
    tanggal: fixtureDate,
    harga_per_kg: 3000,
    set_oleh: userId,
  }), 'Membuat harga QA');
  await expectNoError(await admin.from('rekening_kas').insert({
    id: rekeningId,
    nama: `Kas QA ${runId}`,
    tipe: 'kas',
    saldo_awal: 0,
    aktif: true,
    is_default: true,
    catatan: 'Fixture concurrency staging',
    created_by: userId,
  }), 'Membuat rekening QA');
}

async function authenticatedClient(anonKey) {
  const client = createClient(stagingUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  await expectNoError(await client.auth.signInWithPassword({ email, password }), 'Login QA');
  return client;
}

async function cleanupFixture() {
  if (!fixtureCreated || !admin) return;
  const failures = [];
  const paymentIdsResult = await admin
    .from('pembayaran_mitra_kwitansi')
    .select('id')
    .eq('master_mitra_id', mitraId);
  if (paymentIdsResult.error) failures.push(`baca pembayaran: ${paymentIdsResult.error.message}`);
  const paymentIds = (paymentIdsResult.data || []).map((row) => row.id);

  const steps = [
    ['payment items', admin.from('pembayaran_mitra_kwitansi_item').delete().eq('master_mitra_id', mitraId)],
    ['payment mitras', admin.from('pembayaran_mitra_kwitansi_mitra').delete().eq('master_mitra_id', mitraId)],
  ];
  if (paymentIds.length > 0) {
    steps.push([
      'payment references',
      admin.from('pembayaran_mitra_kwitansi').update({
        kas_ledger_id: null,
        reversal_kas_ledger_id: null,
        rekening_kas_id: null,
      }).in('id', paymentIds),
    ]);
  }
  steps.push(
    ['cash ledger', admin.from('kas_ledger').delete().eq('created_by', userId)],
    ['payments', admin.from('pembayaran_mitra_kwitansi').delete().eq('master_mitra_id', mitraId)],
    ['transactions', admin.from('transaksi_mitra').delete().eq('mitra_id', mitraId)],
    ['rekening', admin.from('rekening_kas').delete().eq('id', rekeningId)],
    ['harga', admin.from('harga_tbs').delete().eq('id', hargaId)],
    ['sopir', admin.from('sopir').delete().eq('id', sopirId)],
    ['fee history', admin.from('fee_owner_mitra_history').delete().eq('master_mitra_id', mitraId)],
    ['mitra', admin.from('master_mitra').delete().eq('id', mitraId)],
    ['profile', admin.from('users').delete().eq('id', userId)],
  );
  for (const [label, operation] of steps) {
    const { error } = await operation;
    if (error) failures.push(`${label}: ${error.message}`);
  }
  const { error: authError } = await admin.auth.admin.deleteUser(userId);
  if (authError && !authError.message.toLowerCase().includes('not found')) {
    failures.push(`auth user: ${authError.message}`);
  }

  const residue = await Promise.all([
    admin.from('pembayaran_mitra_kwitansi').select('id', { count: 'exact', head: true }).eq('master_mitra_id', mitraId),
    admin.from('transaksi_mitra').select('id', { count: 'exact', head: true }).eq('mitra_id', mitraId),
    admin.from('master_mitra').select('id', { count: 'exact', head: true }).eq('id', mitraId),
    admin.from('users').select('id', { count: 'exact', head: true }).eq('id', userId),
    admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('actor_user_id', userId),
  ]);
  const residueLabels = ['payments', 'transactions', 'mitra', 'profile', 'audit'];
  residue.forEach((result, index) => {
    if (result.error) failures.push(`cek ${residueLabels[index]}: ${result.error.message}`);
    else if (result.count !== 0) failures.push(`residu ${residueLabels[index]}=${result.count}`);
  });
  if (failures.length > 0) throw new Error(`Cleanup staging gagal: ${failures.join('; ')}`);
}

assert(!stagingUrl.includes(productionRef), 'Ref produksi terdeteksi; pengujian dihentikan.');
assert(stagingUrl === `https://${stagingRef}.supabase.co`, 'Target harus staging yang disetujui.');

let primaryError;
let result;
try {
  const { anonKey, serviceKey } = await getStagingKeys();
  await createFixture(serviceKey);
  const firstClient = await authenticatedClient(anonKey);
  const secondClient = await authenticatedClient(anonKey);
  const transactionId = await expectNoError(await firstClient.rpc('save_transaksi_mitra_operational', {
    payload: {
      tanggal: fixtureDate,
      sopir_id: sopirId,
      mitra_id: mitraId,
      plat_nomor: `QA ${runId.slice(0, 4).toUpperCase()} PY`,
      sopir_default_id: sopirId,
      sopir_default_nama: 'QA Sopir Payment',
      sopir_aktual_id: sopirId,
      sopir_aktual_nama: 'QA Sopir Payment',
      sopir_aktual_source: 'master',
      sopir_diganti_dari_default: false,
      berat_netto_pabrik_kg: 1000,
      potongan_pabrik_kg: 100,
      menggunakan_armada_cb_snapshot: false,
      kenakan_sewa_armada_cb: false,
      catat_dana_operasional_trip: false,
    },
  }), 'Membuat transaksi QA');
  assert(/^[0-9a-f-]{36}$/i.test(transactionId), 'RPC transaksi tidak mengembalikan UUID.');

  const paymentPayload = {
    p_master_mitra_id: mitraId,
    p_periode_dari: fixtureDate,
    p_periode_sampai: fixtureDate,
    p_metode_bayar: 'tunai',
    p_catatan: 'QA concurrency staging',
  };
  const calls = await Promise.all([
    firstClient.rpc('create_pembayaran_mitra_kwitansi', paymentPayload),
    secondClient.rpc('create_pembayaran_mitra_kwitansi', paymentPayload),
  ]);
  const successes = calls.filter((call) => !call.error);
  const rejections = calls.filter((call) => call.error);
  assert(successes.length === 1 && rejections.length === 1,
    `Hasil konkurensi salah: sukses=${successes.length}, ditolak=${rejections.length}.`);

  const retry = await firstClient.rpc('create_pembayaran_mitra_kwitansi', paymentPayload);
  assert(retry.error, 'Retry berurutan seharusnya ditolak.');

  const [payments, items, cash] = await Promise.all([
    admin.from('pembayaran_mitra_kwitansi')
      .select('id,total_nilai_bersih,nominal_dibayar')
      .eq('master_mitra_id', mitraId)
      .neq('status', 'dibatalkan'),
    admin.from('pembayaran_mitra_kwitansi_item')
      .select('id', { count: 'exact' })
      .eq('master_mitra_id', mitraId),
    admin.from('kas_ledger')
      .select('id,jumlah', { count: 'exact' })
      .eq('created_by', userId)
      .neq('status', 'dibatalkan'),
  ]);
  await expectNoError(payments, 'Membaca pembayaran');
  await expectNoError(items, 'Membaca item pembayaran');
  await expectNoError(cash, 'Membaca kas');
  assert(payments.data.length === 1, `Jumlah pembayaran aktif=${payments.data.length}.`);
  assert(items.count === 1, `Jumlah item=${items.count}.`);
  assert(cash.count === 1, `Jumlah mutasi kas=${cash.count}.`);
  assert(Number(payments.data[0].total_nilai_bersih) === 2_610_000, 'Total nilai bersih header tidak cocok.');
  assert(Number(payments.data[0].nominal_dibayar) === 2_610_000, 'Nominal dibayar header tidak cocok.');
  assert(Number(cash.data[0].jumlah) === 2_610_000, 'Nominal kas tidak cocok dengan pembayaran.');

  result = {
    target: 'staging',
    transaction_id_verified: true,
    successful_calls: successes.length,
    rejected_calls: rejections.length,
    sequential_retry_rejected: true,
    payments: payments.data.length,
    items: items.count,
    cash_entries: cash.count,
    reconciled_amount: 2_610_000,
  };
} catch (error) {
  primaryError = error;
} finally {
  await cleanupFixture().catch((error) => {
    primaryError = new Error(
      [primaryError?.message, error.message].filter(Boolean).join('; '),
      { cause: primaryError },
    );
  });
}

if (primaryError) throw primaryError;
console.log(JSON.stringify({ ...result, cleanup_residue: 0 }));
