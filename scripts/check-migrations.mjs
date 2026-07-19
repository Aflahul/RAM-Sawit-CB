import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';

const migrationsDirectory = path.resolve('supabase', 'migrations');
const files = (await readdir(migrationsDirectory))
  .filter((file) => file.endsWith('.sql'))
  .sort();
const seenVersions = new Set();
const errors = [];
const utf8Decoder = new TextDecoder('utf-8', { fatal: true });

for (const file of files) {
  const match = /^(\d{14})_[a-z0-9_]+\.sql$/.exec(file);
  if (!match) {
    errors.push(`${file}: nama file migration tidak valid`);
    continue;
  }

  const version = match[1];
  if (seenVersions.has(version)) errors.push(`${file}: versi migration duplikat ${version}`);
  seenVersions.add(version);

  const bytes = await readFile(path.join(migrationsDirectory, file));
  if (bytes.length === 0) {
    errors.push(`${file}: file kosong`);
    continue;
  }
  if ((bytes[0] === 0xff && bytes[1] === 0xfe) || (bytes[0] === 0xfe && bytes[1] === 0xff)) {
    errors.push(`${file}: UTF-16 tidak diizinkan; gunakan UTF-8 tanpa BOM`);
    continue;
  }
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    errors.push(`${file}: UTF-8 BOM tidak diizinkan`);
  }
  if (bytes.includes(0)) errors.push(`${file}: mengandung byte NUL`);

  try {
    const sql = utf8Decoder.decode(bytes);
    if (!sql.trim()) errors.push(`${file}: tidak berisi SQL`);
  } catch {
    errors.push(`${file}: encoding bukan UTF-8 valid`);
  }
}

if (errors.length > 0) {
  console.error(errors.join('\n'));
  process.exit(1);
}

console.log(`${files.length} migration files valid (UTF-8, non-empty, unique versions).`);
