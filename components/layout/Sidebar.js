'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const menuSections = [
  {
    title: 'Utama',
    items: [
      { href: '/dashboard', icon: '🏠', label: 'Dashboard' },
    ],
  },
  {
    title: 'Operasional',
    items: [
      { href: '/transaksi/beli', icon: '📦', label: 'Input TBS' },
      { href: '/transaksi/kirim', icon: '🚚', label: 'Pengiriman' },
    ],
  },
  {
    title: 'Keuangan',
    items: [
      { href: '/keuangan/hutang', icon: '💳', label: 'Hutang Petani' },
      { href: '/keuangan/biaya', icon: '🔧', label: 'Biaya Operasional' },
    ],
  },
  {
    title: 'Laporan',
    items: [
      { href: '/laporan/harian', icon: '📊', label: 'Laporan Harian' },
      { href: '/laporan/laba-rugi', icon: '💰', label: 'Laba / Rugi', ownerOnly: true },
    ],
  },
  {
    title: 'Master Data',
    items: [
      { href: '/master/petani', icon: '👥', label: 'Petani / Mitra' },
      { href: '/master/armada', icon: '🚛', label: 'Armada & Sopir' },
      { href: '/master/pabrik', icon: '🏭', label: 'Pabrik Tujuan' },
      { href: '/master/harga', icon: '💲', label: 'Harga TBS' },
    ],
  },
];

export default function Sidebar({ isOpen, onClose, user }) {
  const pathname = usePathname();
  const userRole = user?.role || 'admin';

  return (
    <>
      {/* Overlay for mobile */}
      {isOpen && (
        <div
          className="modal-overlay"
          style={{ zIndex: 99, background: 'rgba(0,0,0,0.5)' }}
          onClick={onClose}
        />
      )}

      <aside className={`sidebar ${isOpen ? 'open' : ''}`}>
        {/* Logo */}
        <div className="sidebar-logo">
          <div className="sidebar-logo-icon">🌿</div>
          <div>
            <div className="sidebar-logo-text">SAWIT CB</div>
            <div className="sidebar-logo-sub">Manajemen RAM</div>
          </div>
        </div>

        {/* Navigation */}
        <nav className="sidebar-nav">
          {menuSections.map((section) => (
            <div className="sidebar-section" key={section.title}>
              <div className="sidebar-section-title">{section.title}</div>
              {section.items
                .filter((item) => !item.ownerOnly || userRole === 'owner')
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
                      <span className="sidebar-link-badge">{item.badge}</span>
                    )}
                  </Link>
                ))}
            </div>
          ))}
        </nav>

        {/* User */}
        <div className="sidebar-user">
          <div className="sidebar-avatar">
            {user?.nama ? user.nama.charAt(0).toUpperCase() : 'U'}
          </div>
          <div>
            <div className="sidebar-user-name">{user?.nama || 'User'}</div>
            <div className="sidebar-user-role">
              {userRole === 'owner' ? '👑 Owner' : '📋 Admin'}
            </div>
          </div>
        </div>
      </aside>
    </>
  );
}
