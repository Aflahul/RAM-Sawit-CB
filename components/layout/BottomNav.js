'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { BadgeDollarSign, FileText, LayoutDashboard, Store, Truck } from 'lucide-react';
import { useContext } from 'react';
import { UserContext } from '@/contexts/UserContext';
import { canManageFinance, canViewProfit } from '@/lib/roles';

const navItems = [
  { href: '/dashboard', icon: <LayoutDashboard size={22} />, label: 'Hari Ini' },
  { href: '/admin/input-timbangan', icon: <Truck size={22} />, label: 'Mitra' },
  { href: '/transaksi/beli', icon: <Store size={22} />, label: 'Petani', comingSoon: true },
  { href: '/keuangan/kas', icon: <BadgeDollarSign size={22} />, label: 'Kas', financeOnly: true },
  { href: '/owner/laporan-mitra', icon: <FileText size={22} />, label: 'Laporan' },
];

function canSeeNavItem(item, role) {
  if (item.financeOnly) return canManageFinance(role);
  if (item.profitOnly) return canViewProfit(role);
  return true;
}

export default function BottomNav() {
  const pathname = usePathname();
  const user = useContext(UserContext);
  const userRole = user?.role;

  const visibleItems = navItems.filter((item) => canSeeNavItem(item, userRole));

  return (
    <nav className="bottom-nav">
      {visibleItems.map((item) => {
        const isActive = pathname === item.href || pathname.startsWith(item.href + '/');

        if (item.comingSoon) {
          return null; // HIDE COMING SOON MODULES
        }

        return (
          <Link
            key={item.href}
            href={item.href}
            className={`bottom-nav-item ${isActive ? 'active' : ''}`}
            aria-current={isActive ? 'page' : undefined}
          >
            <span className="bottom-nav-icon">{item.icon}</span>
            <span>{item.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
