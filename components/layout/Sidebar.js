'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import BrandMark from '@/components/branding/BrandMark';
import { useBrandingSettings } from '@/lib/use-branding-settings';
import { canManageBusinessSettings, canViewProfit, getRoleLabel, normalizeRole } from '@/lib/roles';
import {
  LayoutDashboard, Truck, ReceiptText, Database, Store,
  Wallet, Calculator, FileText, Users, Box, TrendingUp, MapPin, Tag, ClipboardList, BadgeDollarSign, Settings
} from 'lucide-react';

const menuSections = [
  {
    title: 'MVP Utama',
    items: [
      { href: '/dashboard', icon: <LayoutDashboard size={20} />, label: 'Dashboard' },
      { href: '/admin/input-timbangan', icon: <Truck size={20} />, label: 'Pengiriman Mitra' },
      { href: '/owner/riwayat-pengiriman-mitra', icon: <ClipboardList size={20} />, label: 'Riwayat Pengiriman' },
      { href: '/owner/kwitansi-mitra', icon: <ReceiptText size={20} />, label: 'Kwitansi Mitra' },
      { href: '/owner/panjar-mitra', icon: <Wallet size={20} />, label: 'Panjar Mitra' },
      { href: '/owner/laporan-mitra', icon: <FileText size={20} />, label: 'Laporan Mitra' },
      { href: '/owner/pendapatan-owner', icon: <BadgeDollarSign size={20} />, label: 'Pendapatan Bruto', profitOnly: true },
    ],
  },
  {
    title: 'Master Data MVP',
    items: [
      { href: '/owner/master-data', icon: <Database size={20} />, label: 'Master Mitra & Sopir' },
      { href: '/owner/pengaturan-web', icon: <Settings size={20} />, label: 'Pengaturan Web', settingsOnly: true },
    ],
  },
  {
    title: 'Operasional (coming soon)',
    items: [
      { href: '/transaksi/beli', icon: <Store size={20} />, label: 'Input TBS Lokal', badge: 'comingsoon' },
      { href: '/transaksi/kirim', icon: <Truck size={20} />, label: 'Pengiriman Lokal', badge: 'comingsoon' },
    ],
  },
  {
    title: 'Keuangan (coming soon)',
    items: [
      { href: '/keuangan/hutang', icon: <Wallet size={20} />, label: 'Hutang Petani', badge: 'comingsoon' },
      { href: '/keuangan/biaya', icon: <Calculator size={20} />, label: 'Biaya Operasional', badge: 'comingsoon' },
    ],
  },
  {
    title: 'Laporan (coming soon)',
    items: [
      { href: '/laporan/harian', icon: <FileText size={20} />, label: 'Laporan Harian' },
      { href: '/laporan/petani', icon: <Users size={20} />, label: 'Laporan Petani', badge: 'comingsoon' },
      { href: '/laporan/stok', icon: <Box size={20} />, label: 'Stok Lokal', badge: 'comingsoon' },
      { href: '/laporan/laba-rugi', icon: <TrendingUp size={20} />, label: 'Laba / Rugi', profitOnly: true, badge: 'comingsoon' },
    ],
  },
  {
    title: 'Master Data (coming soon)',
    items: [
      { href: '/master/petani', icon: <Users size={20} />, label: 'Petani Lokal', badge: 'comingsoon' },
      { href: '/master/armada', icon: <Truck size={20} />, label: 'Armada & Sopir', badge: 'comingsoon' },
      { href: '/master/pabrik', icon: <MapPin size={20} />, label: 'Pabrik Tujuan', badge: 'comingsoon' },
      { href: '/master/harga', icon: <Tag size={20} />, label: 'Harga TBS', badge: 'comingsoon' },
    ],
  },
];

function canSeeMenuItem(item, role) {
  if (item.profitOnly) return canViewProfit(role);
  if (item.settingsOnly) return canManageBusinessSettings(role);
  return true;
}

export default function Sidebar({ isOpen, onClose, user }) {
  const pathname = usePathname();
  const userRole = normalizeRole(user?.role);
  const { branding } = useBrandingSettings();

  return (
    <>
      {isOpen && (
        <div
          className="modal-overlay"
          style={{ zIndex: 99, background: 'rgba(0,0,0,0.5)' }}
          onClick={onClose}
        />
      )}

      <aside className={`sidebar glass-panel ${isOpen ? 'open' : ''}`} style={{ borderRadius: 0, borderTop: 'none', borderBottom: 'none', borderLeft: 'none' }}>
        <div className="sidebar-logo">
          <BrandMark branding={branding} size={40} />
          <div>
            <div className="sidebar-logo-text">{branding.appName}</div>
            <div className="sidebar-logo-sub">{branding.appSubtitle}</div>
          </div>
        </div>

        <nav className="sidebar-nav">
          {menuSections.map((section) => (
            <div className="sidebar-section" key={section.title}>
              <div className="sidebar-section-title">{section.title}</div>
              {section.items
                .filter((item) => canSeeMenuItem(item, userRole))
                .map((item) => (
                  <Link
                    key={item.href}
                    href={item.href}
                    className={`sidebar-link ${pathname === item.href || pathname.startsWith(item.href + '/') ? 'active' : ''}`}
                    onClick={onClose}
                  >
                    <span className="sidebar-link-icon">{item.icon}</span>
                    <span>{item.label}</span>
                    {item.badge && (
                      <span 
                        className="sidebar-link-badge" 
                        style={item.badge === 'comingsoon' ? { fontSize: '0.65rem', fontStyle: 'italic', background: 'transparent', color: '#94a3b8', border: '1px solid #475569', padding: '2px 6px' } : {}}
                      >
                        {item.badge}
                      </span>
                    )}
                  </Link>
                ))}
            </div>
          ))}
        </nav>

        <div className="sidebar-user">
          <div className="sidebar-avatar">
            {user?.nama ? user.nama.charAt(0).toUpperCase() : 'U'}
          </div>
          <div>
            <div className="sidebar-user-name">{user?.nama || 'User'}</div>
            <div className="sidebar-user-role">{getRoleLabel(userRole)}</div>
          </div>
        </div>
      </aside>
    </>
  );
}
