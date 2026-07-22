import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createClient } from '@supabase/supabase-js';
import { chromium } from 'playwright';
import { sanitizeLocalDevelopmentEnvironment } from './lib/local-supabase-environment.mjs';

const execFileAsync = promisify(execFile);
const stagingRef = 'mfxyeybmjpcdckajfjen';
const productionRef = 'yavntiympbrjlouzkhnl';
const stagingUrl = `https://${stagingRef}.supabase.co`;
const appPort = 3122;
const appUrl = `http://127.0.0.1:${appPort}`;
const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const runId = crypto.randomUUID().replaceAll('-', '').slice(0, 12);
const fixtureDate = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Jakarta',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
}).format(new Date());
const email = `qa-mitra-history-${runId}@example.invalid`;
const password = `Qa-${crypto.randomUUID()}-9!`;
const userId = crypto.randomUUID();
const mitraId = crypto.randomUUID();
const sopirId = crypto.randomUUID();
const hargaId = crypto.randomUUID();
const transactionId = crypto.randomUUID();
const mitraCode = `QA-HIST-${runId.toUpperCase()}`;
const mitraName = `QA History ${runId}`;

let admin;
let appProcess;
let browser;
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
  const publishableKey = keys.find((key) => key.name === 'anon')?.api_key
    || keys.find((key) => key.type === 'publishable')?.api_key;
  const serviceKey = keys.find((key) => key.name === 'service_role')?.api_key
    || keys.find((key) => key.type === 'secret')?.api_key;
  assert(publishableKey && serviceKey, 'Kunci staging tidak lengkap.');
  return { publishableKey, serviceKey };
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
  }), 'Membuat auth user QA');
  fixtureCreated = true;
  await expectNoError(await admin.from('users').insert({
    id: userId,
    nama: 'QA Mitra History',
    username: `qa_hist_${runId}`,
    role: 'owner',
  }), 'Membuat profil QA');
  await expectNoError(await admin.from('master_mitra').insert({
    id: mitraId,
    nama: mitraName,
    kode: mitraCode,
    penanggung_jawab: 'QA Otomatis',
    no_hp: '081234567894',
    alamat: 'Fixture sementara staging',
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
    nama: `QA Driver ${runId}`,
    no_hp: '081234567895',
    mitra_id: mitraId,
    plat_nomor: `QA ${runId.slice(0, 4).toUpperCase()} HS`,
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
  await expectNoError(await admin.from('transaksi_mitra').insert({
    id: transactionId,
    tanggal: fixtureDate,
    sopir_id: sopirId,
    mitra_id: mitraId,
    plat_nomor: `QA ${runId.slice(0, 4).toUpperCase()} HS`,
    tonase: 1000,
    harga_harian: 3000,
    total_kotor: 3000000,
    created_by: userId,
    sopir_default_id: sopirId,
    sopir_default_nama: `QA Driver ${runId}`,
    sopir_aktual_id: sopirId,
    sopir_aktual_nama: `QA Driver ${runId}`,
    sopir_aktual_source: 'master',
    sopir_diganti_dari_default: false,
    berat_netto_pabrik_kg: 1000,
    potongan_pabrik_kg: 0,
    menggunakan_armada_cb_snapshot: false,
    kenakan_sewa_armada_cb: false,
    catat_dana_operasional_trip: false,
  }), 'Membuat transaksi QA');
}

async function cleanupFixture() {
  if (!fixtureCreated || !admin) return;
  const failures = [];
  const steps = [
    ['transaksi', admin.from('transaksi_mitra').delete().eq('id', transactionId)],
    ['harga', admin.from('harga_tbs').delete().eq('id', hargaId)],
    ['sopir', admin.from('sopir').delete().eq('id', sopirId)],
    ['fee history', admin.from('fee_owner_mitra_history').delete().eq('master_mitra_id', mitraId)],
    ['mitra', admin.from('master_mitra').delete().eq('id', mitraId)],
    ['profil', admin.from('users').delete().eq('id', userId)],
  ];
  for (const [label, operation] of steps) {
    const { error } = await operation;
    if (error) failures.push(`${label}: ${error.message}`);
  }
  const { error: authError } = await admin.auth.admin.deleteUser(userId);
  if (authError && !authError.message.toLowerCase().includes('not found')) {
    failures.push(`auth: ${authError.message}`);
  }
  const residue = await Promise.all([
    admin.from('transaksi_mitra').select('id', { count: 'exact', head: true }).eq('id', transactionId),
    admin.from('master_mitra').select('id', { count: 'exact', head: true }).eq('id', mitraId),
    admin.from('users').select('id', { count: 'exact', head: true }).eq('id', userId),
  ]);
  residue.forEach((result, index) => {
    if (result.error) failures.push(`residue query ${index}: ${result.error.message}`);
    else if (result.count !== 0) failures.push(`residue ${index}: ${result.count}`);
  });
  if (failures.length > 0) throw new Error(`Cleanup gagal: ${failures.join('; ')}`);
}

function createAppEnvironment(publishableKey) {
  return {
    ...sanitizeLocalDevelopmentEnvironment(process.env),
    NODE_ENV: 'production',
    NEXT_PUBLIC_SUPABASE_URL: stagingUrl,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: publishableKey,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: publishableKey,
    SUPABASE_SERVICE_ROLE_KEY: '',
    VERCEL_OIDC_TOKEN: '',
  };
}

async function buildApp(publishableKey) {
  try {
    await execFileAsync(process.execPath, [
      'node_modules/next/dist/bin/next', 'build',
    ], {
      cwd: process.cwd(),
      windowsHide: true,
      env: createAppEnvironment(publishableKey),
      timeout: 120_000,
      maxBuffer: 10 * 1024 * 1024,
    });
  } catch (error) {
    const output = [error.stdout, error.stderr].filter(Boolean).join('\n');
    throw new Error(`Build Next staging gagal: ${output.slice(-4000) || error.message}`);
  }
}

async function startApp(publishableKey) {
  appProcess = spawn(process.execPath, [
    'node_modules/next/dist/bin/next', 'start', '-p', String(appPort), '-H', '127.0.0.1',
  ], {
    cwd: process.cwd(),
    windowsHide: true,
    env: createAppEnvironment(publishableKey),
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  appProcess.stdout.on('data', (chunk) => { output += chunk.toString(); });
  appProcess.stderr.on('data', (chunk) => { output += chunk.toString(); });
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    if (appProcess.exitCode !== null) {
      throw new Error(`Next berhenti (${appProcess.exitCode}): ${output.slice(-4000)}`);
    }
    try {
      const response = await fetch(`${appUrl}/login`, { redirect: 'manual' });
      if (response.status < 500) return;
    } catch {
      // Menunggu server siap.
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`Next tidak siap: ${output.slice(-4000)}`);
}

async function stopApp() {
  if (!appProcess || appProcess.exitCode !== null) return;
  appProcess.kill('SIGTERM');
  await Promise.race([
    new Promise((resolve) => appProcess.once('exit', resolve)),
    new Promise((resolve) => setTimeout(resolve, 5_000)),
  ]);
  if (appProcess.exitCode === null) appProcess.kill('SIGKILL');
}

async function reproduce() {
  browser = await chromium.launch({ executablePath: chromePath, headless: true });
  const context = await browser.newContext({
    locale: 'id-ID',
    timezoneId: 'Asia/Jakarta',
  });
  const page = await context.newPage();
  const runtimeErrors = [];
  const responseProbes = [];
  page.on('pageerror', (error) => runtimeErrors.push(`pageerror: ${error.message}`));
  page.on('response', (response) => {
    if (response.status() >= 400) {
      responseProbes.push(response.text()
        .then((body) => runtimeErrors.push(`HTTP ${response.status()}: ${response.url()} BODY ${body}`))
        .catch((error) => runtimeErrors.push(`HTTP ${response.status()}: ${response.url()} BODY-ERROR ${error.message}`)));
    }
  });

  await page.goto(`${appUrl}/login`, { waitUntil: 'domcontentloaded' });
  await page.getByLabel('Email').fill(email);
  await page.locator('#password').fill(password);
  await Promise.all([
    page.waitForURL(/\/dashboard(?:\?|$)/, { timeout: 30_000 }),
    page.getByRole('button', { name: /masuk/i }).click(),
  ]);
  await page.goto(`${appUrl}/admin/input-timbangan`, { waitUntil: 'domcontentloaded' });

  const loading = page.getByText('Memuat riwayat...', { exact: true });
  const fixtureRow = page.getByText(mitraCode, { exact: false }).first();
  let rowVisible = false;
  try {
    await fixtureRow.waitFor({ state: 'visible', timeout: 10_000 });
    rowVisible = true;
  } catch {
    // Assertion di bawah mencetak simptom yang terukur.
  }
  let editModalVisible = false;
  if (rowVisible) {
    const row = page.locator('tr').filter({ hasText: mitraCode }).first();
    await row.getByTitle('Edit transaksi').click();
    const editModal = page.getByRole('heading', { name: 'Edit Pengiriman Mitra' });
    await editModal.waitFor({ state: 'visible', timeout: 5_000 });
    editModalVisible = await editModal.isVisible();
  }
  await Promise.allSettled(responseProbes);
  const loadingVisible = await loading.isVisible().catch(() => false);
  const bodyText = await page.locator('body').innerText();
  const dateValues = await page.locator('input[type="date"]').evaluateAll((inputs) => inputs.map((input) => input.value));
  assert(rowVisible && editModalVisible && !loadingVisible && runtimeErrors.length === 0,
    `REPRO: riwayat/koreksi tidak siap (fixtureDate=${fixtureDate}, dateValues=${dateValues.join(',')}, rowVisible=${rowVisible}, editModalVisible=${editModalVisible}, loadingVisible=${loadingVisible}, errors=${runtimeErrors.join(' | ') || 'none'}, body=${bodyText.slice(-1500)}).`);
  return { rowVisible, editModalVisible, loadingVisible, runtimeErrors };
}

assert(stagingUrl === `https://${stagingRef}.supabase.co`, 'Target bukan staging.');
assert(!stagingUrl.includes(productionRef), 'Ref production terdeteksi.');

let primaryError;
let result;
const finalizationErrors = [];
try {
  const { publishableKey, serviceKey } = await getStagingKeys();
  await createFixture(serviceKey);
  await buildApp(publishableKey);
  await startApp(publishableKey);
  result = await reproduce();
} catch (error) {
  primaryError = error;
} finally {
  if (browser) await browser.close().catch(() => {});
  await stopApp().catch((error) => finalizationErrors.push(`stop app: ${error.message}`));
  await cleanupFixture().catch((error) => finalizationErrors.push(error.message));
}

if (finalizationErrors.length > 0) {
  primaryError = new Error([primaryError?.message, ...finalizationErrors].filter(Boolean).join('; '));
}
if (primaryError) throw primaryError;
console.log(JSON.stringify({ target: 'staging', fixtureDate, cleanupResidue: 0, ...result }));
