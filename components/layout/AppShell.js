'use client';

import { useState, useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { normalizeRole } from '@/lib/roles';
import Sidebar from '@/components/layout/Sidebar';
import Header from '@/components/layout/Header';
import BottomNav from '@/components/layout/BottomNav';
import { motion, AnimatePresence } from 'motion/react';

export default function AppShell({ children, title, subtitle }) {
  const router = useRouter();
  const pathname = usePathname();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function getUser() {
      try {
        const { data: { session } } = await supabase.auth.getSession();

        if (!session) {
          router.push('/login');
          return;
        }

        const { data: userData } = await supabase
          .from('users')
          .select('*')
          .eq('id', session.user.id)
          .single();

        setUser(
          userData
            ? { ...userData, role: normalizeRole(userData.role) }
            : { nama: session.user.email, role: 'admin_operasional' }
        );
      } catch (err) {
        console.error('Error fetching user:', err);
        router.push('/login');
      } finally {
        setLoading(false);
      }
    }

    getUser();

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event) => {
        if (event === 'SIGNED_OUT') {
          router.push('/login');
        }
      }
    );

    return () => subscription.unsubscribe();
  }, [router]);

  if (loading) {
    return (
      <div
        style={{
          minHeight: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: 'var(--bg-body)',
        }}
      >
        <div style={{ textAlign: 'center' }}>
          <div className="spinner spinner-lg" style={{ margin: '0 auto 16px' }}></div>
          <p className="text-secondary">Memuat Sawit CB...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="app-shell cinematic-bg">
      <Sidebar
        isOpen={sidebarOpen}
        onClose={() => setSidebarOpen(false)}
        user={user}
      />
      <div className="main-content">
        <Header
          title={title}
          subtitle={subtitle}
          onMenuToggle={() => setSidebarOpen(!sidebarOpen)}
        />
        <AnimatePresence mode="wait">
          <motion.main
            key={title}
            className="page-content"
            style={{ position: 'relative' }}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
          >
            {(() => {
              const lockedPaths = [
              ];
              const isLocked = lockedPaths.some((p) => pathname?.startsWith(p));
              
              if (isLocked) {
                return (
                  <>
                    <div style={{ position: 'absolute', inset: 0, zIndex: 50, background: 'rgba(2, 6, 23, 0.7)', backdropFilter: 'blur(3px)', display: 'flex', alignItems: 'flex-start', justifyContent: 'center', paddingTop: '15vh' }}>
                      <div className="card" style={{ textAlign: 'center', border: '1px solid var(--color-gold-500)', boxShadow: 'var(--shadow-glow-gold)', maxWidth: 400, margin: '0 20px' }}>
                        <div style={{ color: 'var(--color-gold-500)', marginBottom: 12 }}>
                          <svg width="48" height="48" fill="none" stroke="currentColor" viewBox="0 0 24 24" style={{ margin: '0 auto' }}>
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                          </svg>
                        </div>
                        <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, color: 'var(--color-gold-400)', marginBottom: 8 }}>Tahap 2: Dalam Pengembangan</h3>
                        <p style={{ color: 'var(--text-secondary)', fontSize: 'var(--text-sm)', lineHeight: 1.5 }}>
                          Fitur ini sedang dibangun dan akan tersedia pada rilis operasional lokal berikutnya.
                        </p>
                      </div>
                    </div>
                    <div style={{ opacity: 0.2, pointerEvents: 'none', filter: 'grayscale(1)' }}>
                      {children}
                    </div>
                  </>
                );
              }
              return children;
            })()}
          </motion.main>
        </AnimatePresence>
      </div>
      <BottomNav />
    </div>
  );
}
