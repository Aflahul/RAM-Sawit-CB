'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { BadgeDollarSign, FileText, LayoutDashboard, Store, Truck } from 'lucide-react';

const navItems = [
  { href: '/dashboard', icon: <LayoutDashboard size={22} />, label: 'Hari Ini' },
  { href: '/admin/input-timbangan', icon: <Truck size={22} />, label: 'Mitra' },
  { href: '/transaksi/beli', icon: <Store size={22} />, label: 'Petani' },
  { href: '/keuangan/kas', icon: <BadgeDollarSign size={22} />, label: 'Kas' },
  { href: '/owner/laporan-mitra', icon: <FileText size={22} />, label: 'Laporan' },
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
