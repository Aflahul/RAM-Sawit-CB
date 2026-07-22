import assert from 'node:assert/strict';
import test from 'node:test';

import {
  assertNoSensitiveLocalDevelopmentValues,
  assertSafeDevelopmentSupabaseTarget,
  environmentFileVariableNames,
  isLoopbackUrl,
  publicLocalEnvironmentFromStatus,
  sanitizeLocalDevelopmentEnvironment,
} from '../scripts/lib/local-supabase-environment.mjs';

test('recognizes only HTTP(S) loopback URLs as local', () => {
  assert.equal(isLoopbackUrl('http://127.0.0.1:54321'), true);
  assert.equal(isLoopbackUrl('http://localhost:54321'), true);
  assert.equal(isLoopbackUrl('https://[::1]:54321'), true);
  assert.equal(isLoopbackUrl('https://example.supabase.co'), false);
  assert.equal(isLoopbackUrl('not-a-url'), false);
});

test('blocks a hosted Supabase target during Next development', () => {
  assert.throws(
    () => assertSafeDevelopmentSupabaseTarget({
      nodeEnv: 'development',
      supabaseUrl: 'https://example.supabase.co',
    }),
    /Development diblokir/,
  );
});

test('allows local development and does not constrain production builds', () => {
  assert.doesNotThrow(() => assertSafeDevelopmentSupabaseTarget({
    nodeEnv: 'development',
    supabaseUrl: 'http://127.0.0.1:54321',
  }));
  assert.doesNotThrow(() => assertSafeDevelopmentSupabaseTarget({
    nodeEnv: 'production',
    supabaseUrl: 'https://example.supabase.co',
  }));
});

test('selects only public local values from Supabase status', () => {
  const environment = publicLocalEnvironmentFromStatus({
    API_URL: 'http://127.0.0.1:54321',
    PUBLISHABLE_KEY: 'sb_publishable_local',
    SECRET_KEY: 'must-not-be-forwarded',
    SERVICE_ROLE_KEY: 'must-not-be-forwarded',
  });

  assert.deepEqual(environment, {
    NEXT_PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321',
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_local',
  });
  assert.equal('SECRET_KEY' in environment, false);
  assert.equal('SERVICE_ROLE_KEY' in environment, false);
});

test('rejects a hosted status response and a missing public key', () => {
  assert.throws(
    () => publicLocalEnvironmentFromStatus({
      API_URL: 'https://example.supabase.co',
      PUBLISHABLE_KEY: 'sb_publishable_remote',
    }),
    /loopback\/local/,
  );
  assert.throws(
    () => publicLocalEnvironmentFromStatus({ API_URL: 'http://127.0.0.1:54321' }),
    /publishable\/anon key lokal/,
  );
});

test('extracts variable names without exposing environment file values', () => {
  assert.deepEqual(
    environmentFileVariableNames('PUBLIC_VALUE=ok\nexport PRIVATE_TOKEN="secret"\n# ignored\n'),
    ['PUBLIC_VALUE', 'PRIVATE_TOKEN'],
  );
});

test('blanks inherited and environment-file credentials before launching Next', () => {
  const sanitized = sanitizeLocalDevelopmentEnvironment({
    PATH: 'system-path',
    NEXT_PUBLIC_SUPABASE_URL: 'https://hosted.supabase.co',
    SUPABASE_SERVICE_ROLE_KEY: 'service-secret',
    VERCEL_OIDC_TOKEN: 'vercel-secret',
    APP_DISPLAY_MODE: 'compact',
  }, ['ANOTHER_PRIVATE_VALUE', 'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY']);

  assert.equal(sanitized.PATH, 'system-path');
  assert.equal(sanitized.APP_DISPLAY_MODE, 'compact');
  assert.equal(sanitized.SUPABASE_SERVICE_ROLE_KEY, '');
  assert.equal(sanitized.VERCEL_OIDC_TOKEN, '');
  assert.equal(sanitized.ANOTHER_PRIVATE_VALUE, '');
  assert.equal(sanitized.NEXT_PUBLIC_SUPABASE_URL, 'https://hosted.supabase.co');
});

test('blocks local Next config when a sensitive credential is still active', () => {
  assert.throws(
    () => assertNoSensitiveLocalDevelopmentValues({
      nodeEnv: 'development',
      supabaseUrl: 'http://127.0.0.1:54321',
      environment: { SUPABASE_SERVICE_ROLE_KEY: 'must-not-survive' },
    }),
    /credential sensitif/,
  );
  assert.doesNotThrow(() => assertNoSensitiveLocalDevelopmentValues({
    nodeEnv: 'development',
    supabaseUrl: 'http://127.0.0.1:54321',
    environment: {
      NEXT_PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321',
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_local',
      SUPABASE_SERVICE_ROLE_KEY: '',
    },
  }));
});
