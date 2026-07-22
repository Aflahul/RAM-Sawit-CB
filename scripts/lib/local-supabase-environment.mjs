const LOOPBACK_HOSTS = new Set(['127.0.0.1', 'localhost', '::1']);
const LOCAL_PUBLIC_VARIABLES = new Set([
  'NEXT_PUBLIC_SUPABASE_URL',
  'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',
]);
const SENSITIVE_VARIABLE_PATTERN = /(?:API_KEY|ACCESS_KEY|CREDENTIAL|DATABASE_URL|DB_URL|PASSWORD|PRIVATE_KEY|SECRET|SERVICE_ROLE|TOKEN)/i;

export function isLoopbackUrl(value) {
  if (!value) return false;

  try {
    const url = new URL(value);
    const hostname = url.hostname.startsWith('[') && url.hostname.endsWith(']')
      ? url.hostname.slice(1, -1)
      : url.hostname;
    return (url.protocol === 'http:' || url.protocol === 'https:')
      && LOOPBACK_HOSTS.has(hostname);
  } catch {
    return false;
  }
}

export function assertSafeDevelopmentSupabaseTarget({ nodeEnv, supabaseUrl }) {
  if (nodeEnv !== 'development') return;

  if (!supabaseUrl) {
    throw new Error(
      'Development diblokir: NEXT_PUBLIC_SUPABASE_URL belum tersedia. '
      + 'Aktifkan Supabase Docker lalu jalankan `npm run dev:local`.',
    );
  }

  if (!isLoopbackUrl(supabaseUrl)) {
    throw new Error(
      'Development diblokir karena target Supabase bukan loopback/local. '
      + 'Gunakan `npm run dev:local`; jangan menjalankan development terhadap project hosted/production.',
    );
  }
}

export function publicLocalEnvironmentFromStatus(status) {
  if (!status || typeof status !== 'object') {
    throw new Error('Status Supabase lokal tidak valid.');
  }

  const supabaseUrl = status.API_URL;
  const publishableKey = status.PUBLISHABLE_KEY || status.ANON_KEY;

  if (!isLoopbackUrl(supabaseUrl)) {
    throw new Error('Supabase CLI tidak mengembalikan API URL loopback/local.');
  }

  if (typeof publishableKey !== 'string' || publishableKey.length === 0) {
    throw new Error('Supabase CLI tidak mengembalikan publishable/anon key lokal.');
  }

  return {
    NEXT_PUBLIC_SUPABASE_URL: supabaseUrl,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: publishableKey,
  };
}

export function environmentFileVariableNames(contents) {
  if (typeof contents !== 'string') return [];

  return contents
    .split(/\r?\n/)
    .map((line) => line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/)?.[1])
    .filter(Boolean);
}

export function sanitizeLocalDevelopmentEnvironment(
  inheritedEnvironment,
  environmentFileNames = [],
) {
  const sanitized = { ...inheritedEnvironment };
  const namesToBlank = new Set([
    ...Object.keys(sanitized).filter((name) => (
      (name.startsWith('SUPABASE_') && !LOCAL_PUBLIC_VARIABLES.has(name))
      || SENSITIVE_VARIABLE_PATTERN.test(name)
    )),
    ...environmentFileNames.filter((name) => !LOCAL_PUBLIC_VARIABLES.has(name)),
  ]);

  for (const name of namesToBlank) sanitized[name] = '';

  return sanitized;
}

export function assertNoSensitiveLocalDevelopmentValues({ nodeEnv, supabaseUrl, environment }) {
  if (nodeEnv !== 'development' || !isLoopbackUrl(supabaseUrl)) return;

  const exposedNames = Object.entries(environment)
    .filter(([name, value]) => value && (
      (name.startsWith('SUPABASE_') && !LOCAL_PUBLIC_VARIABLES.has(name))
      || SENSITIVE_VARIABLE_PATTERN.test(name)
    ))
    .map(([name]) => name);

  if (exposedNames.length > 0) {
    throw new Error(
      `Development lokal diblokir karena credential sensitif masih aktif: ${exposedNames.join(', ')}.`,
    );
  }
}
