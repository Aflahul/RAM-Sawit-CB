import { spawn } from 'node:child_process';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(scriptDirectory, '..');
const port = Number(process.env.LOCAL_APP_SMOKE_PORT || 3199);
const baseUrl = `http://127.0.0.1:${port}`;

if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error('LOCAL_APP_SMOKE_PORT harus berupa port non-privileged yang valid.');
}

const child = spawn(
  process.execPath,
  [path.join(scriptDirectory, 'dev-local.mjs'), '--port', String(port), '--hostname', '127.0.0.1'],
  {
    cwd: projectDirectory,
    env: process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  },
);

let output = '';
child.stdout.on('data', (chunk) => { output += chunk.toString(); });
child.stderr.on('data', (chunk) => { output += chunk.toString(); });

const exited = new Promise((resolve) => child.once('exit', (code, signal) => resolve({ code, signal })));

async function waitForLogin() {
  const deadline = Date.now() + 30_000;

  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(`Server lokal berhenti sebelum siap.\n${output.slice(-2000)}`);
    }

    try {
      const response = await fetch(`${baseUrl}/login`, { redirect: 'manual' });
      if (response.status === 200) return response;
    } catch {
      // Server masih memulai; coba kembali sampai deadline.
    }

    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  throw new Error(`Server lokal tidak siap dalam 30 detik.\n${output.slice(-2000)}`);
}

async function stopServer() {
  if (child.exitCode !== null) return;

  child.kill('SIGTERM');
  const result = await Promise.race([
    exited,
    new Promise((resolve) => setTimeout(() => resolve(null), 5_000)),
  ]);

  if (result === null && child.exitCode === null) {
    child.kill('SIGKILL');
    await exited;
  }
}

try {
  const loginResponse = await waitForLogin();
  const rootResponse = await fetch(`${baseUrl}/`, { redirect: 'manual' });
  const location = rootResponse.headers.get('location');

  if (rootResponse.status !== 307 || location !== '/login') {
    throw new Error(
      `Flow pengguna tanpa sesi tidak sesuai: status=${rootResponse.status}, location=${location}`,
    );
  }

  console.log(JSON.stringify({
    target: 'local-loopback',
    login_http: loginResponse.status,
    root_http: rootResponse.status,
    root_location: location,
  }));
} finally {
  await stopServer();
}
