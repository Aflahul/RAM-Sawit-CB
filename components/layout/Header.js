'use client';

import { supabase } from '@/lib/supabase';
import { useRouter } from 'next/navigation';
import { formatTanggal } from '@/lib/utils';

export default function Header({ title, subtitle, onMenuToggle }) {
  const router = useRouter();

  async function handleLogout() {
    await supabase.auth.signOut();
    router.push('/login');
    router.refresh();
  }

  return (
    <header className="header">
      <div className="flex items-center gap-md">
        <button
          className="header-menu-btn"
          onClick={onMenuToggle}
          aria-label="Toggle menu"
        >
          Menu
        </button>
        <div>
          <h1 className="header-title">{title || 'Dashboard'}</h1>
          <p className="header-subtitle">
            {subtitle || formatTanggal(new Date())}
          </p>
        </div>
      </div>
      <div className="header-actions">
        <button
          className="btn btn-ghost btn-sm"
          onClick={handleLogout}
          title="Keluar"
        >
          Keluar
        </button>
      </div>
    </header>
  );
}
