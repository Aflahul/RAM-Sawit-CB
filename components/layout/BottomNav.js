'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const navItems = [
  { href: '/dashboard', icon: 'DB', label: 'Home' },
  { href: '/transaksi/beli', icon: 'TB', label: 'TBS' },
  { href: '/transaksi/kirim', icon: 'DO', label: 'Kirim' },
  { href: '/keuangan/hutang', icon: 'HK', label: 'Hutang' },
  { href: '/laporan/harian', icon: 'LH', label: 'Laporan' },
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
