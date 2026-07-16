import { createClient } from '@/utils/supabase/middleware';
import { NextResponse } from 'next/server';

const PROFIT_PATHS = ['/owner/pendapatan-owner', '/laporan/laba-rugi'];
const BUSINESS_SETTINGS_PATHS = ['/owner/pengaturan-web', '/master/harga'];
const FINANCE_PATHS = [
  '/owner/kwitansi-mitra',
  '/owner/pembayaran-pabrik',
  '/owner/laporan-armada-cb',
  '/keuangan',
];

function startsWithAny(pathname, paths) {
  return paths.some(path => pathname === path || pathname.startsWith(`${path}/`));
}

function copySessionCookies(source, target) {
  source.cookies.getAll().forEach(cookie => target.cookies.set(cookie));
  return target;
}

export async function proxy(request) {
  const { supabase, getResponse } = createClient(request);
  const pathname = request.nextUrl.pathname;
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    if (pathname === '/login') return getResponse();
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = '/login';
    loginUrl.search = '';
    return copySessionCookies(getResponse(), NextResponse.redirect(loginUrl));
  }

  if (pathname === '/login') {
    const dashboardUrl = request.nextUrl.clone();
    dashboardUrl.pathname = '/dashboard';
    dashboardUrl.search = '';
    return copySessionCookies(getResponse(), NextResponse.redirect(dashboardUrl));
  }

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .maybeSingle();

  const role = profile?.role === 'admin' ? 'admin_operasional' : profile?.role;
  const isOwner = role === 'owner' || role === 'super_admin';
  const canUseFinance = isOwner || role === 'admin_operasional' || role === 'admin_keuangan';
  const denied = (startsWithAny(pathname, PROFIT_PATHS) && !isOwner)
    || (startsWithAny(pathname, BUSINESS_SETTINGS_PATHS) && !isOwner)
    || (startsWithAny(pathname, FINANCE_PATHS) && !canUseFinance);

  if (!profile || denied) {
    const dashboardUrl = request.nextUrl.clone();
    dashboardUrl.pathname = '/dashboard';
    dashboardUrl.searchParams.set('akses', 'ditolak');
    return copySessionCookies(getResponse(), NextResponse.redirect(dashboardUrl));
  }

  return getResponse();
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
};
