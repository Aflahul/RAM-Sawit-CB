'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import BrandMark from '@/components/branding/BrandMark';
import { useBrandingSettings } from '@/lib/use-branding-settings';
import { canManageBusinessSettings, canManageFinance, canViewProfit, canManageUsers, getRoleLabel, isOperationalAdmin, normalizeRole } from '@/lib/roles';
import {
  LayoutDashboard, Truck, ReceiptText, Database, Store,
  Wallet, Calculator, FileText, Users, Box, TrendingUp, MapPin, Tag, ClipboardList, BadgeDollarSign, Settings, ChevronDown
} from 'lucide-react';

const SIDEBAR_SCROLL_KEY = 'sawit-cb.sidebar.scrollTop';
const SIDEBAR_SECTION_KEY = 'sawit-cb.sidebar.expandedSections';

const menuSections = [
  {
    title: 'Dashboard',
    items: [
      { href: '/dashboard', icon: <LayoutDashboard size={20} />, label: 'Dashboard' },
    ],
  },
  {
    title: 'Operasi',
    items: [
      { href: '/admin/input-timbangan', icon: <Truck size={20} />, label: 'Pengiriman Mitra' },
      { href: '/transaksi/beli', icon: <Store size={20} />, label: 'Pembelian Petani Lokal', badge: 'comingsoon' },
    ],
  },
  {
    title: 'Keuangan',
    items: [
      { href: '/owner/kwitansi-mitra', icon: <ReceiptText size={20} />, label: 'Kwitansi & Pembayaran Mitra' },
      { href: '/owner/pembayaran-pabrik', icon: <BadgeDollarSign size={20} />, label: 'Pembayaran Pabrik', financeOnly: true },
      { href: '/keuangan/kas', icon: <BadgeDollarSign size={20} />, label: 'Buku Kas', financeOnly: true },
      { href: '/keuangan/hutang', icon: <Wallet size={20} />, label: 'Pinjaman & Panjar', financeOnly: true },
      { href: '/keuangan/biaya', icon: <Calculator size={20} />, label: 'Biaya Operasional' },
    ],
  },
  {
    title: 'Master Data',
    items: [
      { href: '/owner/master-data', icon: <Database size={20} />, label: 'Mitra' },
      { href: '/master/armada', icon: <Truck size={20} />, label: 'Armada' },
      { href: '/master/petani', icon: <Users size={20} />, label: 'Petani Lokal', badge: 'comingsoon' },
      { href: '/master/pabrik', icon: <MapPin size={20} />, label: 'Pabrik Tujuan' },
      { href: '/master/harga', icon: <Tag size={20} />, label: 'Harga TBS Lokal', settingsOnly: true },
    ],
  },
  {
    title: 'Laporan',
    items: [
      { href: '/owner/laporan-mitra', icon: <FileText size={20} />, label: 'Laporan Mitra' },
      { href: '/owner/laporan-armada-cb', icon: <Truck size={20} />, label: 'Laporan Armada CB', armadaReport: true },
      { href: '/laporan/petani', icon: <Users size={20} />, label: 'Laporan Petani', badge: 'comingsoon' },
      { href: '/laporan/stok', icon: <Box size={20} />, label: 'Stok Lokal', badge: 'comingsoon' },
      { href: '/owner/pendapatan-owner', icon: <BadgeDollarSign size={20} />, label: 'Pendapatan Owner', profitOnly: true },
      { href: '/laporan/laba-rugi', icon: <TrendingUp size={20} />, label: 'Ringkasan Arus Kas', profitOnly: true },
    ],
  },
  {
    title: 'Admin Sistem',
    items: [
      { href: '/superadmin/users', icon: <Users size={20} />, label: 'Kelola Pengguna', superAdminOnly: true },
      { href: '/owner/pengaturan-web', icon: <Settings size={20} />, label: 'Pengaturan Web', settingsOnly: true },
    ],
  },
];

function canSeeMenuItem(item, role) {
  if (item.superAdminOnly) return canManageUsers(role);
  if (item.armadaReport) return canManageFinance(role) || canViewProfit(role);
  if (item.profitOnly) return canViewProfit(role);
  if (item.settingsOnly) return canManageBusinessSettings(role);
  if (item.financeOnly) return canManageFinance(role);
  return true;
}

function isActivePath(pathname, href) {
  return pathname === href || pathname?.startsWith(`${href}/`);
}

function getStoredSections() {
  if (typeof window === 'undefined') return {};

  try {
    return JSON.parse(window.sessionStorage.getItem(SIDEBAR_SECTION_KEY) || '{}');
  } catch {
    return {};
  }
}

export default function Sidebar({ isOpen, onClose, user }) {
  const pathname = usePathname();
  const userRole = normalizeRole(user?.role);
  const { branding } = useBrandingSettings();
  const navRef = useRef(null);
  const [expandedSections, setExpandedSections] = useState({});

  const visibleSections = useMemo(() => (
    menuSections
      .map((section) => ({
        ...section,
        title: section.title === 'Laporan' && isOperationalAdmin(userRole) ? 'Rekap Operasional' : section.title,
        items: section.items
          .filter((item) => canSeeMenuItem(item, userRole))
          .map((item) => {
            if (!isOperationalAdmin(userRole)) return item;
            if (item.href === '/owner/laporan-mitra') return { ...item, label: 'Rekap Mitra' };
            if (item.href === '/owner/laporan-armada-cb') return { ...item, label: 'Rekap Armada CB' };
            return item;
          }),
      }))
      .filter((section) => section.items.length > 0)
  ), [userRole]);

  const activeSectionTitle = useMemo(() => (
    visibleSections.find((section) => (
      section.items.some((item) => isActivePath(pathname, item.href))
    ))?.title
  ), [pathname, visibleSections]);

  useEffect(() => {
    if (typeof window === 'undefined') return undefined;

    const frameId = window.requestAnimationFrame(() => {
      setExpandedSections((current) => {
        const stored = Object.keys(current).length === 0 ? getStoredSections() : {};
        const source = Object.keys(stored).length > 0 ? stored : current;
        const next = {};
        const hasSource = Object.keys(source).length > 0;
        const isCompact = window.matchMedia('(max-width: 768px)').matches;

        visibleSections.forEach((section) => {
          if (typeof source[section.title] === 'boolean') {
            next[section.title] = source[section.title];
          } else if (hasSource) {
            next[section.title] = false;
          } else {
            next[section.title] = isCompact
              ? section.title === 'Dashboard' || section.title === activeSectionTitle
              : true;
          }
        });

        if (activeSectionTitle) next[activeSectionTitle] = true;

        window.sessionStorage.setItem(SIDEBAR_SECTION_KEY, JSON.stringify(next));

        return next;
      });
    });

    return () => window.cancelAnimationFrame(frameId);
  }, [activeSectionTitle, visibleSections]);

  useEffect(() => {
    const nav = navRef.current;
    if (!nav || typeof window === 'undefined') return;

    const savedScroll = Number(window.sessionStorage.getItem(SIDEBAR_SCROLL_KEY) || 0);
    window.requestAnimationFrame(() => {
      nav.scrollTop = Number.isFinite(savedScroll) ? savedScroll : 0;
    });
  }, [pathname, visibleSections.length]);

  function persistSidebarScroll() {
    if (!navRef.current || typeof window === 'undefined') return;
    window.sessionStorage.setItem(SIDEBAR_SCROLL_KEY, String(navRef.current.scrollTop));
  }

  function toggleSection(title) {
    setExpandedSections((current) => {
      const next = { ...current, [title]: !current[title] };

      if (typeof window !== 'undefined') {
        window.sessionStorage.setItem(SIDEBAR_SECTION_KEY, JSON.stringify(next));
      }

      return next;
    });
  }

  function handleNavigate() {
    persistSidebarScroll();
    onClose();
  }

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

        <nav className="sidebar-nav" ref={navRef} onScroll={persistSidebarScroll}>
          {visibleSections.map((section) => {
            const isExpanded = expandedSections[section.title] !== false;
            const sectionId = `sidebar-section-${section.title.toLowerCase().replace(/\s+/g, '-')}`;

            return (
              <div className="sidebar-section" key={section.title}>
                <button
                  type="button"
                  className={`sidebar-section-toggle ${isExpanded ? 'open' : ''}`}
                  aria-expanded={isExpanded}
                  aria-controls={sectionId}
                  onClick={() => toggleSection(section.title)}
                >
                  <span className="sidebar-section-title">{section.title}</span>
                  <ChevronDown className="sidebar-section-chevron" size={16} />
                </button>

                <div id={sectionId} className="sidebar-section-items" hidden={!isExpanded}>
                  {section.items.map((item) => {
                    const isComingSoon = item.badge === 'comingsoon';
                    if (isComingSoon) return null; // HIDE COMING SOON MODULES

                    const linkContent = (
                      <>
                        <span className="sidebar-link-icon">{item.icon}</span>
                        <span className="sidebar-link-label">{item.label}</span>
                        {item.badge && (
                          <span
                            className="sidebar-link-badge"
                            style={item.badge === 'shortcut' ? { fontSize: '0.65rem', fontStyle: 'italic', background: 'transparent', color: '#94a3b8', border: '1px solid #475569', padding: '2px 6px' } : {}}
                          >
                            {item.badge}
                          </span>
                        )}
                      </>
                    );

                    return (
                      <Link
                        key={item.href}
                        href={item.href}
                        className={`sidebar-link ${isActivePath(pathname, item.href) ? 'active' : ''}`}
                        aria-current={isActivePath(pathname, item.href) ? 'page' : undefined}
                        onClick={handleNavigate}
                      >
                        {linkContent}
                      </Link>
                    );
                  })}
                </div>
              </div>
            );
          })}
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

