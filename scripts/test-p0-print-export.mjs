import { spawn } from 'node:child_process';
import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { promisify } from 'node:util';
import { createClient } from '@supabase/supabase-js';
import { chromium } from 'playwright';

const execFileAsync = promisify(execFile);
const stagingRef = 'mfxyeybmjpcdckajfjen';
const productionRef = 'yavntiympbrjlouzkhnl';
const stagingUrl = `https://${stagingRef}.supabase.co`;
const appPort = Number(process.env.P0_UI_PORT || 3119);
const appUrl = `http://127.0.0.1:${appPort}`;
const chromePath = process.env.P0_CHROME_PATH
  || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const runId = crypto.randomUUID().replaceAll('-', '').slice(0, 12);
const fixtureDate = '2099-11-29';
const email = `qa-print-export-${runId}@example.invalid`;
const password = `Qa-${crypto.randomUUID()}-9!`;
const userId = crypto.randomUUID();
const mitraId = crypto.randomUUID();
const sopirId = crypto.randomUUID();
const hargaId = crypto.randomUUID();
const mitraCode = `QA-PE-${runId.toUpperCase()}`;
const mitraName = `QA Print Export ${runId}`;

let appProcess;
let browser;
let admin;
let fixtureCreated = false;
let workDirectory;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function getStagingKeys() {
  const { stdout } = await execFileAsync(
    process.execPath,
    ['node_modules/supabase/dist/supabase.js', 'projects', 'api-keys', '--project-ref', stagingRef, '-o', 'json'],
    { windowsHide: true, maxBuffer: 2 * 1024 * 1024 },
  );
  const keys = JSON.parse(stdout);
  const publishableKey = keys.find((key) => key.name === 'anon')?.api_key
    || keys.find((key) => key.type === 'publishable')?.api_key;
  const serviceKey = keys.find((key) => key.name === 'service_role')?.api_key
    || keys.find((key) => key.type === 'secret')?.api_key;
  assert(publishableKey, 'Staging publishable/anon key tidak ditemukan.');
  assert(serviceKey, 'Staging secret/service-role key tidak ditemukan.');
  return { publishableKey, serviceKey };
}

async function expectNoError(result, label) {
  if (result.error) throw new Error(`${label}: ${result.error.message}`);
  return result.data;
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
    nama: 'QA Print Export',
    username: `qa_pe_${runId}`,
    role: 'owner',
  }), 'Membuat profil QA');

  await expectNoError(await admin.from('master_mitra').insert({
    id: mitraId,
    nama: mitraName,
    kode: mitraCode,
    penanggung_jawab: 'QA Otomatis',
    no_hp: '081234567890',
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
    nama: 'QA Sopir Print Export',
    no_hp: '081234567891',
    mitra_id: mitraId,
    plat_nomor: `QA ${runId.slice(0, 4).toUpperCase()} PE`,
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
    tanggal: fixtureDate,
    sopir_id: sopirId,
    mitra_id: mitraId,
    plat_nomor: `QA ${runId.slice(0, 4).toUpperCase()} PE`,
    tonase: 1000,
    harga_harian: 0,
    total_kotor: 0,
    created_by: userId,
    sopir_default_id: sopirId,
    sopir_default_nama: 'QA Sopir Print Export',
    sopir_aktual_id: sopirId,
    sopir_aktual_nama: 'QA Sopir Print Export',
    sopir_aktual_source: 'master',
    sopir_diganti_dari_default: false,
    berat_netto_pabrik_kg: 1000,
    potongan_pabrik_kg: 100,
    menggunakan_armada_cb_snapshot: false,
    kenakan_sewa_armada_cb: false,
    catat_dana_operasional_trip: false,
  }), 'Membuat transaksi QA');
}

async function cleanupFixture() {
  if (!fixtureCreated || !admin) return;
  const cleanupSteps = [
    ['transaksi_mitra', admin.from('transaksi_mitra').delete().eq('mitra_id', mitraId)],
    ['fee_owner_mitra_history', admin.from('fee_owner_mitra_history').delete().eq('master_mitra_id', mitraId)],
    ['sopir', admin.from('sopir').delete().eq('id', sopirId)],
    ['harga_tbs', admin.from('harga_tbs').delete().eq('id', hargaId)],
    ['master_mitra', admin.from('master_mitra').delete().eq('id', mitraId)],
    ['users', admin.from('users').delete().eq('id', userId)],
  ];

  const failures = [];
  for (const [label, operation] of cleanupSteps) {
    const { error } = await operation;
    if (error) failures.push(`${label}: ${error.message}`);
  }
  const { error: authError } = await admin.auth.admin.deleteUser(userId);
  if (authError && !authError.message.toLowerCase().includes('not found')) {
    failures.push(`auth.users: ${authError.message}`);
  }

  const residueChecks = await Promise.all([
    admin.from('transaksi_mitra').select('id', { count: 'exact', head: true }).eq('mitra_id', mitraId),
    admin.from('master_mitra').select('id', { count: 'exact', head: true }).eq('id', mitraId),
    admin.from('users').select('id', { count: 'exact', head: true }).eq('id', userId),
    admin.from('audit_log').select('id', { count: 'exact', head: true }).eq('actor_user_id', userId),
  ]);
  const labels = ['transaksi', 'mitra', 'profil', 'audit'];
  residueChecks.forEach((result, index) => {
    if (result.error) failures.push(`cek ${labels[index]}: ${result.error.message}`);
    else if (result.count !== 0) failures.push(`residu ${labels[index]}=${result.count}`);
  });
  if (failures.length > 0) throw new Error(`Cleanup fixture gagal: ${failures.join('; ')}`);
}

async function startApp(publishableKey) {
  appProcess = spawn(process.execPath, ['node_modules/next/dist/bin/next', 'dev', '-p', String(appPort), '-H', '127.0.0.1'], {
    cwd: process.cwd(),
    windowsHide: true,
    env: {
      ...process.env,
      NEXT_PUBLIC_SUPABASE_URL: stagingUrl,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: publishableKey,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  appProcess.stdout.on('data', (chunk) => { output += chunk.toString(); });
  appProcess.stderr.on('data', (chunk) => { output += chunk.toString(); });

  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    if (appProcess.exitCode !== null) {
      throw new Error(`Next dev berhenti sebelum siap (${appProcess.exitCode}): ${output.slice(-4000)}`);
    }
    try {
      const response = await fetch(`${appUrl}/login`, { redirect: 'manual' });
      if (response.status < 500) return;
    } catch {
      // Server masih mulai.
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`Next dev tidak siap dalam 90 detik: ${output.slice(-4000)}`);
}

async function stopApp() {
  if (!appProcess || appProcess.exitCode !== null) return;
  appProcess.kill('SIGTERM');
  await Promise.race([
    new Promise((resolvePromise) => appProcess.once('exit', resolvePromise)),
    new Promise((resolvePromise) => setTimeout(resolvePromise, 5_000)),
  ]);
  if (appProcess.exitCode === null) appProcess.kill('SIGKILL');
}

async function runBrowserChecks() {
  browser = await chromium.launch({ executablePath: chromePath, headless: true });
  const context = await browser.newContext({ acceptDownloads: true, locale: 'id-ID' });
  const page = await context.newPage();
  const runtimeErrors = [];
  page.on('pageerror', (error) => runtimeErrors.push(`pageerror: ${error.message}`));
  page.on('response', (response) => {
    if (response.status() >= 500) runtimeErrors.push(`HTTP ${response.status()}: ${response.url()}`);
  });
  await page.addInitScript(() => {
    window.__p0PrintCalls = 0;
    window.print = () => { window.__p0PrintCalls += 1; };
  });

  await page.goto(`${appUrl}/login`, { waitUntil: 'domcontentloaded' });
  await page.getByLabel('Email').fill(email);
  await page.locator('#password').fill(password);
  await Promise.all([
    page.waitForURL(/\/dashboard(?:\?|$)/, { timeout: 30_000 }),
    page.getByRole('button', { name: /masuk/i }).click(),
  ]);

  const receiptUrl = `${appUrl}/owner/kwitansi-mitra?mitra=${mitraId}&dari=${fixtureDate}&sampai=${fixtureDate}`;
  await page.goto(receiptUrl, { waitUntil: 'domcontentloaded' });
  const printButton = page.getByRole('button', { name: 'Cetak PDF / Struk' }).first();
  await printButton.waitFor({ state: 'visible', timeout: 30_000 });
  await page.getByText(mitraCode, { exact: false }).first().waitFor({ state: 'visible', timeout: 30_000 });
  await page.getByText('QA Sopir Print Export', { exact: false }).first().waitFor({ state: 'visible' });
  await printButton.click();
  assert(await page.evaluate(() => window.__p0PrintCalls) === 1, 'Tombol cetak tidak memanggil window.print tepat satu kali.');

  const pdfPath = join(workDirectory, 'kwitansi.pdf');
  await page.emulateMedia({ media: 'print' });
  await page.pdf({ path: pdfPath, format: 'A4', printBackground: true });
  const pdf = await readFile(pdfPath);
  assert(pdf.subarray(0, 4).toString() === '%PDF', 'Artefak cetak bukan PDF valid.');
  assert(pdf.length > 5_000, `PDF terlalu kecil (${pdf.length} byte).`);
  await page.emulateMedia({ media: 'screen' });

  await page.goto(`${appUrl}/owner/master-data`, { waitUntil: 'domcontentloaded' });
  const search = page.getByPlaceholder('Cari nama, kode, atau lokasi mitra...');
  await search.fill(mitraCode);
  await page.getByText(mitraCode, { exact: true }).waitFor({ state: 'visible', timeout: 30_000 });
  const downloadPromise = page.waitForEvent('download', { timeout: 30_000 });
  await page.getByRole('button', { name: 'Export Excel' }).click();
  const download = await downloadPromise;
  const xlsxPath = join(workDirectory, download.suggestedFilename());
  await download.saveAs(xlsxPath);
  const xlsx = await readFile(xlsxPath);
  assert(download.suggestedFilename().toLowerCase().endsWith('.xlsx'), 'Nama ekspor tidak berakhiran .xlsx.');
  assert(xlsx.subarray(0, 2).toString() === 'PK', 'Berkas ekspor bukan kontainer XLSX/ZIP valid.');
  assert((await stat(xlsxPath)).size > 3_000, `XLSX terlalu kecil (${xlsx.length} byte).`);
  assert(runtimeErrors.length === 0, `Error runtime UI: ${runtimeErrors.join('; ')}`);

  return {
    print_invoked: true,
    pdf_valid: true,
    pdf_bytes: pdf.length,
    xlsx_valid: true,
    xlsx_bytes: xlsx.length,
  };
}

async function removeWorkDirectory() {
  if (!workDirectory) return;
  const resolvedWork = resolve(workDirectory);
  const resolvedTemp = resolve(tmpdir());
  assert(resolvedWork.startsWith(`${resolvedTemp}\\`) || resolvedWork.startsWith(`${resolvedTemp}/`), 'Direktori sementara berada di luar temp OS.');
  await rm(resolvedWork, { recursive: true, force: true });
}

assert(!stagingUrl.includes(productionRef), 'Ref produksi terdeteksi; pengujian dihentikan.');
assert(stagingUrl === `https://${stagingRef}.supabase.co`, 'Target harus staging yang disetujui.');

let primaryError;
let result;
const finalizationErrors = [];
try {
  workDirectory = await mkdtemp(join(tmpdir(), 'sawit-cb-p0-print-export-'));
  const { publishableKey, serviceKey } = await getStagingKeys();
  await createFixture(serviceKey);
  await startApp(publishableKey);
  result = await runBrowserChecks();
} catch (error) {
  primaryError = error;
} finally {
  if (browser) await browser.close().catch(() => {});
  await stopApp().catch((error) => finalizationErrors.push(`stop app: ${error.message}`));
  await cleanupFixture().catch((error) => finalizationErrors.push(`cleanup fixture: ${error.message}`));
  await removeWorkDirectory().catch((error) => finalizationErrors.push(`hapus temp: ${error.message}`));
}

if (finalizationErrors.length > 0) {
  const message = [primaryError?.message, ...finalizationErrors].filter(Boolean).join('; ');
  primaryError = new Error(message, { cause: primaryError });
}
if (primaryError) throw primaryError;
console.log(JSON.stringify({ target: 'staging', cleanup_residue: 0, ...result }));
