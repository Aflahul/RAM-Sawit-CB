import {
  assertNoSensitiveLocalDevelopmentValues,
  assertSafeDevelopmentSupabaseTarget,
} from './scripts/lib/local-supabase-environment.mjs';

assertSafeDevelopmentSupabaseTarget({
  nodeEnv: process.env.NODE_ENV,
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL,
});
assertNoSensitiveLocalDevelopmentValues({
  nodeEnv: process.env.NODE_ENV,
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL,
  environment: process.env,
});

/** @type {import('next').NextConfig} */
const nextConfig = {
  /* config options here */
};

export default nextConfig;
