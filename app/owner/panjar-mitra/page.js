import Link from 'next/link';
import { Wallet } from 'lucide-react';

export const metadata = {
  title: 'Panjar Mitra (Usang)',
};

export default function LegacyPanjarMitraPage() {
  return (
    <div className="card" style={{ maxWidth: 500, margin: '40px auto', textAlign: 'center' }}>
      <div style={{ color: 'var(--color-gold-500)', marginBottom: 16 }}>
        <Wallet size={48} style={{ margin: '0 auto' }} />
      </div>
      <h2 style={{ marginBottom: 12 }}>Halaman Telah Dipindahkan</h2>
      <p style={{ color: 'var(--text-secondary)', marginBottom: 24 }}>
        Fitur <strong>Panjar Mitra</strong> kini telah dipindahkan ke menu <strong>Keuangan &gt; Pinjaman &amp; Panjar</strong> untuk mengkonsolidasikan semua catatan hutang/piutang.
      </p>
      <Link href="/keuangan/hutang" className="btn btn-primary" style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
        Ke Halaman Pinjaman &amp; Panjar
      </Link>
    </div>
  );
}
