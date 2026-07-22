import { spawn, spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import {
  environmentFileVariableNames,
  publicLocalEnvironmentFromStatus,
  sanitizeLocalDevelopmentEnvironment,
} from './lib/local-supabase-environment.mjs';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(scriptDirectory, '..');
const supabaseCli = path.join(projectDirectory, 'node_modules', 'supabase', 'dist', 'supabase.js');

const statusResult = spawnSync(
  process.execPath,
  [supabaseCli, 'status', '--output', 'json'],
  {
    cwd: projectDirectory,
    encoding: 'utf8',
    shell: false,
    windowsHide: true,
  },
);

if (statusResult.status !== 0) {
  console.error('Supabase lokal belum siap. Aktifkan Docker lalu jalankan `npx supabase start`.');
  process.exit(1);
}

let publicEnvironment;
try {
  publicEnvironment = publicLocalEnvironmentFromStatus(JSON.parse(statusResult.stdout));
} catch (error) {
  console.error(`Gagal membaca environment publik Supabase lokal: ${error.message}`);
  process.exit(1);
}

const nextCli = path.join(projectDirectory, 'node_modules', 'next', 'dist', 'bin', 'next');
const nextEnvironmentFiles = [
  '.env.development.local',
  '.env.local',
  '.env.development',
  '.env',
];
const environmentFileNames = nextEnvironmentFiles.flatMap((fileName) => {
  const filePath = path.join(projectDirectory, fileName);
  return existsSync(filePath)
    ? environmentFileVariableNames(readFileSync(filePath, 'utf8'))
    : [];
});
const childEnvironment = {
  ...sanitizeLocalDevelopmentEnvironment(process.env, environmentFileNames),
  ...publicEnvironment,
  NODE_ENV: 'development',
};

console.log(`Menjalankan Sawit CB dengan Supabase lokal di ${publicEnvironment.NEXT_PUBLIC_SUPABASE_URL}.`);

const nextProcess = spawn(
  process.execPath,
  [nextCli, 'dev', ...process.argv.slice(2)],
  {
    cwd: projectDirectory,
    env: childEnvironment,
    stdio: 'inherit',
    windowsHide: false,
  },
);

function stopNext(signal) {
  if (!nextProcess.killed) nextProcess.kill(signal);
}

process.once('SIGINT', () => stopNext('SIGINT'));
process.once('SIGTERM', () => stopNext('SIGTERM'));

nextProcess.on('error', (error) => {
  console.error(`Next.js lokal gagal dijalankan: ${error.message}`);
  process.exitCode = 1;
});

nextProcess.on('exit', (code, signal) => {
  if (signal) {
    process.exitCode = 1;
    return;
  }

  process.exitCode = code ?? 1;
});
