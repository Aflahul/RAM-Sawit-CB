'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const navItems = [
  { href: '/dashboard', icon: '🏠', label: 'Home' },
  { href: '/transaksi/beli', icon: '📦', label: 'TBS' },
  { href: '/transaksi/kirim', icon: '🚚', label: 'Kirim' },
  { href: '/keuangan/hutang', icon: '💳', label: 'Hutang' },
  { href: '/laporan/harian', icon: '📊', label: 'Laporan' },
];

export default function BottomNav() {
  const pathname = usePathname();

  return (
    <nav className="bottom-nav">
      {navItems.map((item) => (
        <Link
          key={item.href}
          href={item.href}
          className={`bottom-nav-item ${pathname === item.href || pathname.startsWith(item.href + '/') ? 'active' : ''}`}
        >
          <span className="bottom-nav-icon">{item.icon}</span>
          <span>{item.label}</span>
        </Link>
      ))}
    </nav>
  );
}
