import Link from 'next/link';
import { LayoutDashboard } from 'lucide-react';

export const metadata = {
  title: 'Laporan Harian (Usang)',
};

export default function LegacyLaporanHarianPage() {
  return (
    <div className="card" style={{ maxWidth: 500, margin: '40px auto', textAlign: 'center' }}>
      <div style={{ color: 'var(--color-gold-500)', marginBottom: 16 }}>
        <LayoutDashboard size={48} style={{ margin: '0 auto' }} />
      </div>
      <h2 style={{ marginBottom: 12 }}>Halaman Telah Dipindahkan</h2>
      <p style={{ color: 'var(--text-secondary)', marginBottom: 24 }}>
        Fitur <strong>Laporan Harian</strong> kini telah digabungkan ke dalam <strong>Dashboard Utama</strong> untuk memudahkan pemantauan harian.
      </p>
      <Link href="/dashboard" className="btn btn-primary" style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
        Ke Dashboard Utama
      </Link>
    </div>
  );
}
