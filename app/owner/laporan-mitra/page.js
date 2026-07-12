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

      <div className="no-print card date-filter-container">
        <div className="date-filter-item">
          <label className="date-filter-label">Dari Tanggal</label>
          <input type="date" className="form-input date-filter-input" value={dateFrom} onChange={e => setDateFrom(e.target.value)} />
        </div>
        <div className="date-filter-item">
          <label className="date-filter-label">Sampai Tanggal</label>
          <input type="date" className="form-input date-filter-input" value={dateTo} onChange={e => setDateTo(e.target.value)} />
        </div>
      </div>

      <div className="print-area card" style={{ padding: 0, overflow: 'hidden' }}>
        <div className="only-print" style={{ textAlign: 'center', marginBottom: 24, borderBottom: '2px solid var(--border-default)', paddingBottom: 16 }}>
          <h2 style={{ margin: 0, fontSize: 22 }}>LAPORAN HARIAN PENGIRIMAN MITRA</h2>
          <p style={{ margin: '4px 0 0', color: 'var(--text-secondary)' }}>Periode: {dateFrom} s/d {dateTo}</p>
        </div>

        {loading ? (
          <div style={{ textAlign: 'center', padding: 40 }}>Memuat laporan...</div>
        ) : (
          <div className="table-container">
            <table className="table">
              <thead>
                <tr>
                  <th>Tanggal</th>
                  <th>Mitra / Afiliasi</th>
                  <th>Sopir</th>
                  <th>Plat Nomor</th>
                  <th style={{ textAlign: 'right' }}>Tonase (Kg)</th>
                  <th style={{ textAlign: 'right' }}>Hrg Bersih</th>
                  <th style={{ textAlign: 'right' }}>Total (Rp)</th>
                </tr>
              </thead>
              <tbody>
                {transaksi.length === 0 ? (
                  <tr><td colSpan={7} style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)' }}>Tidak ada transaksi pada periode ini</td></tr>
                ) : (
                  transaksi.map((t, i) => (
                    <tr key={i}>
                      <td>{t.tanggal}</td>
                      <td style={{ fontWeight: 600 }}>{t.master_mitra?.nama}</td>
                      <td>{t.sopir?.nama || '-'}</td>
                      <td className="table-mono">{t.plat_nomor || '-'}</td>
                      <td style={{ textAlign: 'right', fontWeight: 'bold', color: 'var(--text-primary)' }}>{Number(t.tonase).toLocaleString('id-ID')}</td>
                      <td style={{ textAlign: 'right' }} className="table-mono">{formatRupiah(t.harga_harian)}</td>
                      <td style={{ textAlign: 'right' }} className="table-mono">{formatRupiah(t.total_kotor)}</td>
                    </tr>
                  ))
                )}
              </tbody>
              {transaksi.length > 0 && (
                <tfoot>
                  <tr>
                    <td colSpan={4} style={{ textAlign: 'right', fontWeight: 'bold' }}>GRAND TOTAL:</td>
                    <td style={{ textAlign: 'right', fontWeight: 'bold', color: 'var(--color-success)' }}>{totalTonase.toLocaleString('id-ID')} Kg</td>
                    <td></td>
                    <td style={{ textAlign: 'right', fontWeight: 'bold' }}>{formatRupiah(grandTotal)}</td>
                  </tr>
                </tfoot>
              )}
            </table>
          </div>
        )}
      </div>

      <style jsx global>{`
        .date-filter-container {
          margin: 0 auto var(--space-lg) auto;
          padding: var(--space-sm);
          display: flex;
          gap: 8px;
        }
        .date-filter-item {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
        }
        .date-filter-label {
          display: block;
          font-size: 11px;
          font-weight: 500;
          margin-bottom: 4px;
          white-space: nowrap;
          flex-shrink: 0;
        }
        .date-filter-input {
          padding: 6px 4px;
          font-size: 11px;
          width: 100%;
          min-width: 0;
        }

        /* Mode Tablet dan Laptop (768px ke atas) */
        @media (min-width: 768px) {
          .date-filter-container {
            padding: var(--space-md);
            gap: 24px;
          }
          .date-filter-item {
            flex-direction: row;
            align-items: center;
            gap: 12px;
          }
          .date-filter-label {
            margin-bottom: 0;
            font-size: 13px;
          }
          .date-filter-input {
            padding: 8px 12px;
            font-size: 14px;
          }
        }

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
