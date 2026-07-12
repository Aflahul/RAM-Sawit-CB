'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah } from '@/lib/utils';
import { FileText, Printer } from 'lucide-react';

export default function LaporanMitraPage() {
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [transaksi, setTransaksi] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const today = new Date().toISOString().split('T')[0];
    setDateFrom(today);
    setDateTo(today);
  }, []);

  useEffect(() => {
    if (dateFrom && dateTo) {
      loadLaporan();
    }
  }, [dateFrom, dateTo]);

  async function loadLaporan() {
    setLoading(true);
    const { data } = await supabase
      .from('transaksi_mitra')
      .select(`
        id, tanggal, tonase, harga_harian, total_kotor, plat_nomor,
        master_mitra ( nama, kode ),
        sopir ( nama )
      `)
      .gte('tanggal', dateFrom)
      .lte('tanggal', dateTo)
      .order('tanggal', { ascending: false });

    setTransaksi(data || []);
    setLoading(false);
  }

  const handlePrint = () => {
    window.print();
  };

  const totalTonase = transaksi.reduce((sum, t) => sum + Number(t.tonase), 0);
  const grandTotal = transaksi.reduce((sum, t) => sum + Number(t.total_kotor), 0);

  return (
    <AppShell title="Laporan Mitra" subtitle="Laporan harian seluruh pengiriman mitra">
      <div className="page-header no-print">
        <div>
          <h2 className="page-title">Laporan Pengiriman Mitra</h2>
          <p className="page-description">Rekap seluruh transaksi penerimaan TWB dari armada mitra</p>
        </div>
        <button className="btn btn-primary" onClick={handlePrint} disabled={transaksi.length === 0}>
          <Printer size={18} /> Cetak Laporan
        </button>
      </div>

      <div className="toolbar no-print card" style={{ padding: 'var(--space-md)', marginBottom: 'var(--space-lg)', display: 'flex', gap: 16, flexWrap: 'wrap' }}>
        <div>
          <label style={{ display: 'block', fontSize: 14, fontWeight: 500, marginBottom: 8 }}>Dari Tanggal</label>
          <input type="date" className="form-input" value={dateFrom} onChange={e => setDateFrom(e.target.value)} />
        </div>
        <div>
          <label style={{ display: 'block', fontSize: 14, fontWeight: 500, marginBottom: 8 }}>Sampai Tanggal</label>
          <input type="date" className="form-input" value={dateTo} onChange={e => setDateTo(e.target.value)} />
        </div>
      </div>

      <div className="print-area card" style={{ padding: 'var(--space-2xl)' }}>
        <div className="only-print" style={{ textAlign: 'center', marginBottom: 24, borderBottom: '2px solid var(--border-default)', paddingBottom: 16 }}>
          <h2 style={{ margin: 0, fontSize: 22 }}>LAPORAN HARIAN PENGIRIMAN MITRA</h2>
          <p style={{ margin: '4px 0 0', color: 'var(--text-secondary)' }}>Periode: {dateFrom} s/d {dateTo}</p>
        </div>

        {loading ? (
          <div style={{ textAlign: 'center', padding: 40 }}>Memuat laporan...</div>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr style={{ background: 'var(--bg-surface)', borderBottom: '2px solid var(--border-default)' }}>
                  <th style={{ padding: 12, textAlign: 'left' }}>Tanggal</th>
                  <th style={{ padding: 12, textAlign: 'left' }}>Mitra / Afiliasi</th>
                  <th style={{ padding: 12, textAlign: 'left' }}>Sopir</th>
                  <th style={{ padding: 12, textAlign: 'left' }}>Plat Nomor</th>
                  <th style={{ padding: 12, textAlign: 'right' }}>Tonase (Kg)</th>
                  <th style={{ padding: 12, textAlign: 'right' }}>Hrg Bersih</th>
                  <th style={{ padding: 12, textAlign: 'right' }}>Total (Rp)</th>
                </tr>
              </thead>
              <tbody>
                {transaksi.length === 0 ? (
                  <tr><td colSpan={7} style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)' }}>Tidak ada transaksi pada periode ini</td></tr>
                ) : (
                  transaksi.map((t, i) => (
                    <tr key={i} style={{ borderBottom: '1px solid var(--border-default)' }}>
                      <td style={{ padding: '12px 12px' }}>{t.tanggal}</td>
                      <td style={{ padding: '12px 12px', fontWeight: 600 }}>{t.master_mitra?.nama}</td>
                      <td style={{ padding: '12px 12px' }}>{t.sopir?.nama || '-'}</td>
                      <td style={{ padding: '12px 12px' }} className="table-mono">{t.plat_nomor || '-'}</td>
                      <td style={{ padding: '12px 12px', textAlign: 'right', fontWeight: 'bold', color: 'var(--text-primary)' }}>{Number(t.tonase).toLocaleString('id-ID')}</td>
                      <td style={{ padding: '12px 12px', textAlign: 'right' }} className="table-mono">{formatRupiah(t.harga_harian)}</td>
                      <td style={{ padding: '12px 12px', textAlign: 'right' }} className="table-mono">{formatRupiah(t.total_kotor)}</td>
                    </tr>
                  ))
                )}
              </tbody>
              {transaksi.length > 0 && (
                <tfoot>
                  <tr style={{ background: 'var(--bg-surface)', borderTop: '2px solid var(--border-default)' }}>
                    <td colSpan={4} style={{ padding: 16, textAlign: 'right', fontWeight: 'bold' }}>GRAND TOTAL:</td>
                    <td style={{ padding: 16, textAlign: 'right', fontWeight: 'bold', color: 'var(--color-success)' }}>{totalTonase.toLocaleString('id-ID')} Kg</td>
                    <td></td>
                    <td style={{ padding: 16, textAlign: 'right', fontWeight: 'bold' }}>{formatRupiah(grandTotal)}</td>
                  </tr>
                </tfoot>
              )}
            </table>
          </div>
        )}
      </div>

      <style jsx global>{`
        @media print {
          body * { visibility: hidden; }
          .print-area, .print-area * { visibility: visible; color: #000 !important; background: #fff !important; }
          .print-area { position: absolute; left: 0; top: 0; width: 100%; box-shadow: none !important; padding: 0 !important; }
          .no-print { display: none !important; }
        }
      `}</style>
    </AppShell>
  );
}
