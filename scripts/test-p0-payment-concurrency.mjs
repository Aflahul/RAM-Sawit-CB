import { readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';

const container = 'supabase_db_RAM-Sawit-CB';
const fixturePath = new URL('../supabase/tests/p0_payment_concurrency_fixture.sql', import.meta.url);
const cleanupPath = new URL('../supabase/tests/p0_payment_concurrency_cleanup.sql', import.meta.url);
const ownerId = '11000000-0000-0000-0000-000000000002';
const mitraId = '21000000-0000-4000-8000-000000000001';

function runPsql(sql) {
  return new Promise((resolve) => {
    const child = spawn('docker', [
      'exec', '-i', container,
      'psql', '-U', 'postgres', '-d', 'postgres',
      '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
    ], { stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
    child.on('close', (code) => resolve({ code, stdout, stderr }));
    child.stdin.end(sql);
  });
}

function startFirstPayment() {
  const sql = `
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '${ownerId}', true);
SELECT (public.create_pembayaran_mitra_kwitansi(
  '${mitraId}', DATE '2026-02-02', DATE '2026-02-02',
  'tunai', 'QA concurrency first', NULL, NULL
)).id;
SELECT 'FIRST_PAYMENT_READY';
SELECT pg_sleep(3);
COMMIT;
`;

  const child = spawn('docker', [
    'exec', '-i', container,
    'psql', '-U', 'postgres', '-d', 'postgres',
    '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
  ], { stdio: ['pipe', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  let readyResolve;
  let readyReject;
  let reachedReady = false;
  const ready = new Promise((resolve, reject) => {
    readyResolve = resolve;
    readyReject = reject;
  });
  const completed = new Promise((resolve) => {
    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
      if (stdout.includes('FIRST_PAYMENT_READY')) {
        reachedReady = true;
        readyResolve();
      }
    });
    child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
    child.on('close', (code) => {
      if (!reachedReady) {
        readyReject(new Error(`First payment exited before ready marker (${code}): ${stderr.trim()}`));
      }
      resolve({ code, stdout, stderr });
    });
  });
  child.stdin.end(sql);
  return { ready, completed };
}

const secondPaymentSql = `
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '${ownerId}', true);
SELECT (public.create_pembayaran_mitra_kwitansi(
  '${mitraId}', DATE '2026-02-02', DATE '2026-02-02',
  'tunai', 'QA concurrency second', NULL, NULL
)).id;
COMMIT;
`;

const assertionSql = `
SELECT json_build_object(
  'payments', (
    SELECT count(*) FROM public.pembayaran_mitra_kwitansi
    WHERE master_mitra_id = '${mitraId}' AND status <> 'dibatalkan'
  ),
  'items', (
    SELECT count(*) FROM public.pembayaran_mitra_kwitansi_item
    WHERE master_mitra_id = '${mitraId}'
  ),
  'cash_entries', (
    SELECT count(*) FROM public.kas_ledger
    WHERE source_table = 'pembayaran_mitra_kwitansi'
      AND created_by = '${ownerId}'
      AND status <> 'dibatalkan'
  )
);
`;

const fixtureSql = await readFile(fixturePath, 'utf8');
const cleanupSql = await readFile(cleanupPath, 'utf8');
let testFailure;

try {
  const preCleanup = await runPsql(cleanupSql);
  if (preCleanup.code !== 0) throw new Error(`Pre-cleanup failed: ${preCleanup.stderr.trim()}`);

  const fixture = await runPsql(fixtureSql);
  if (fixture.code !== 0) throw new Error(`Fixture failed: ${fixture.stderr.trim()}`);

  const first = startFirstPayment();
  await Promise.race([
    first.ready,
    new Promise((_, reject) => setTimeout(() => reject(new Error('First payment did not reach ready marker.')), 15_000)),
  ]);

  const secondResultPromise = runPsql(secondPaymentSql);
  const [firstResult, secondResult] = await Promise.all([first.completed, secondResultPromise]);
  const assertion = await runPsql(assertionSql);
  if (assertion.code !== 0) throw new Error(`Assertion query failed: ${assertion.stderr.trim()}`);

  const counts = JSON.parse(assertion.stdout.trim());
  const successfulCalls = [firstResult, secondResult].filter((result) => result.code === 0).length;
  const rejectedCalls = [firstResult, secondResult].filter((result) => result.code !== 0).length;

  if (successfulCalls !== 1 || rejectedCalls !== 1
      || counts.payments !== 1 || counts.items !== 1 || counts.cash_entries !== 1) {
    throw new Error(JSON.stringify({
      expected: { successfulCalls: 1, rejectedCalls: 1, payments: 1, items: 1, cash_entries: 1 },
      actual: { successfulCalls, rejectedCalls, ...counts },
    }));
  }

  const sequentialRetry = await runPsql(secondPaymentSql);
  if (sequentialRetry.code === 0
      || !sequentialRetry.stderr.includes('Tidak ada transaksi baru yang belum dibayar')) {
    throw new Error(JSON.stringify({
      expected: { sequentialRetryRejected: true, reason: 'no unpaid transaction remains' },
      actual: { code: sequentialRetry.code, stderr: sequentialRetry.stderr.trim() },
    }));
  }

  console.log(JSON.stringify({
    concurrency_guard: true,
    sequential_retry_rejected: true,
    successful_calls: successfulCalls,
    rejected_calls: rejectedCalls,
    ...counts,
  }));
} catch (error) {
  testFailure = error;
} finally {
  const cleanup = await runPsql(cleanupSql);
  if (cleanup.code !== 0 && !testFailure) {
    testFailure = new Error(`Cleanup failed: ${cleanup.stderr.trim()}`);
  }
}

if (testFailure) throw testFailure;
