'use client';

import { useState, useEffect } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, getTodayDate } from '@/lib/utils';

export default function KwitansiMitraPage() {
  const [mitras, setMitras] = useState([]);
  const [selectedMitra, setSelectedMitra] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  
  const [transaksi, setTransaksi] = useState([]);
  const [panjars, setPanjars] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const today = new Date().toISOString().split('T')[0];
    setDateFrom(today);
    setDateTo(today);
    loadMitras();
  }, []);

  useEffect(() => {
    if (selectedMitra && dateFrom && dateTo) {
      loadKwitansiData();
    } else {
      setTransaksi([]);
      setPanjars([]);
    }
  }, [selectedMitra, dateFrom, dateTo]);

  async function loadMitras() {
    const { data } = await supabase.from('master_mitra').select('id, nama').order('nama');
    setMitras(data || []);
  }

  async function loadKwitansiData() {
    setLoading(true);
    
    // 1. Fetch Transaksi Masuk
    const { data: trxData } = await supabase
      .from('transaksi_mitra')
      .select(`
        id, tanggal, tonase, harga_harian, total_kotor, plat_nomor,
        sopir ( nama )
      `)
      .eq('mitra_id', selectedMitra)
      .gte('tanggal', dateFrom)
      .lte('tanggal', dateTo)
      .order('tanggal', { ascending: true });
      
    setTransaksi(trxData || []);

    // 2. Fetch Panjar Belum Lunas
    const { data: pjrData } = await supabase
      .from('panjar_mitra')
      .select('*')
      .eq('mitra_id', selectedMitra)
      .eq('status', 'belum_lunas');
      
    setPanjars(pjrData || []);
    
    setLoading(false);
  }

  const handlePrint = () => {
    window.print();
  };

  const totalTonase = transaksi.reduce((sum, t) => sum + Number(t.tonase), 0);
  const totalKotor = transaksi.reduce((sum, t) => sum + Number(t.total_kotor), 0);
  const totalPanjar = panjars.reduce((sum, p) => sum + Number(p.jumlah), 0);
  const sisaBersih = totalKotor - totalPanjar;

  return (
    <AppShell title="Kwitansi Mitra" subtitle="Dashboard & Cetak Invoice Mitra">
      <div className="page-header no-print">
        <div>
          <h2 className="page-title">Kwitansi Mitra (MVP)</h2>
          <p className="page-description">Rekapitulasi otomatis armada dan panjar</p>
        </div>
        <button className="btn btn-primary" onClick={handlePrint} disabled={!selectedMitra || transaksi.length === 0}>
          🖨️ Cetak PDF / Struk
        </button>
      </div>

      <div className="toolbar no-print card" style={{ padding: 'var(--space-md)', marginBottom: 'var(--space-lg)', display: 'flex', gap: 16, flexWrap: 'wrap' }}>
        <div style={{ flex: 1, minWidth: 200 }}>
          <label style={{ display: 'block', fontSize: 14, fontWeight: 500, marginBottom: 8 }}>Nama Mitra</label>
          <select className="form-input" value={selectedMitra} onChange={e => setSelectedMitra(e.target.value)}>
            <option value="">-- Pilih Mitra --</option>
            {mitras.map(m => (
              <option key={m.id} value={m.id}>{m.nama}</option>
            ))}
          </select>
        </div>
        <div>
          <label style={{ display: 'block', fontSize: 14, fontWeight: 500, marginBottom: 8 }}>Dari Tanggal</label>
          <input type="date" className="form-input" value={dateFrom} onChange={e => setDateFrom(e.target.value)} />
        </div>
        <div>
          <label style={{ display: 'block', fontSize: 14, fontWeight: 500, marginBottom: 8 }}>Sampai Tanggal</label>
          <input type="date" className="form-input" value={dateTo} onChange={e => setDateTo(e.target.value)} />
        </div>
      </div>

      {loading && <div style={{ textAlign: 'center', padding: 40 }}>Memuat data kwitansi...</div>}

      {!loading && selectedMitra && (
        <div className="print-area card" style={{ padding: 'var(--space-2xl)' }}>
          <div style={{ borderBottom: '2px dashed var(--border-default)', paddingBottom: 24, marginBottom: 24, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <h1 style={{ margin: 0, fontSize: 24, color: 'var(--text-primary)' }}>INVOICE PEMBELIAN TBS</h1>
              <p style={{ margin: '8px 0 0', color: 'var(--text-secondary)' }}>Pabrik Kelapa Sawit (SAWIT CB)</p>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{ fontSize: 14, color: 'var(--text-secondary)' }}>Kepada Yth. Mitra:</div>
              <h2 style={{ margin: '4px 0 0', fontSize: 20, color: 'var(--text-primary)' }}>{mitras.find(m => m.id === selectedMitra)?.nama}</h2>
              <div style={{ fontSize: 14, color: 'var(--text-secondary)', marginTop: 4 }}>
                Periode: {dateFrom} s/d {dateTo}
              </div>
            </div>
          </div>

          <h3 style={{ fontSize: 16, marginBottom: 16 }}>Rincian Armada Masuk:</h3>
          <table style={{ width: '100%', borderCollapse: 'collapse', marginBottom: 32 }}>
            <thead>
              <tr style={{ background: 'var(--bg-surface)', borderBottom: '2px solid var(--border-default)' }}>
                <th style={{ padding: 12, textAlign: 'left' }}>Tanggal</th>
                <th style={{ padding: 12, textAlign: 'left' }}>Nama Sopir</th>
                <th style={{ padding: 12, textAlign: 'left' }}>Plat Armada</th>
                <th style={{ padding: 12, textAlign: 'right' }}>Tonase (Kg)</th>
                <th style={{ padding: 12, textAlign: 'right' }}>Harga/Kg</th>
                <th style={{ padding: 12, textAlign: 'right' }}>Total (Rp)</th>
              </tr>
            </thead>
            <tbody>
              {transaksi.length === 0 ? (
                <tr><td colSpan={6} style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)' }}>Tidak ada transaksi pada periode ini</td></tr>
              ) : (
                transaksi.map((t, i) => (
                  <tr key={i} style={{ borderBottom: '1px solid var(--border-default)' }}>
                    <td style={{ padding: 12 }}>{t.tanggal}</td>
                    <td style={{ padding: 12 }}>{t.sopir?.nama || '-'}</td>
                    <td style={{ padding: 12 }} className="table-mono">{t.plat_nomor || '-'}</td>
                    <td style={{ padding: 12, textAlign: 'right' }}>{Number(t.tonase).toLocaleString('id-ID')}</td>
                    <td style={{ padding: 12, textAlign: 'right' }} className="table-mono">{formatRupiah(t.harga_harian)}</td>
                    <td style={{ padding: 12, textAlign: 'right' }} className="table-mono">{formatRupiah(t.total_kotor)}</td>
                  </tr>
                ))
              )}
            </tbody>
            <tfoot>
              <tr style={{ background: 'var(--bg-surface)', fontWeight: 'bold' }}>
                <td colSpan={3} style={{ padding: 12, textAlign: 'right' }}>TOTAL TRANSAKSI KOTOR:</td>
                <td style={{ padding: 12, textAlign: 'right' }}>{totalTonase.toLocaleString('id-ID')} Kg</td>
                <td style={{ padding: 12, textAlign: 'right' }}></td>
                <td style={{ padding: 12, textAlign: 'right', color: 'var(--text-primary)', fontSize: 16 }}>{formatRupiah(totalKotor)}</td>
              </tr>
            </tfoot>
          </table>

          <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 32 }}>
            <div style={{ width: 400, background: 'var(--bg-surface)', padding: 24, borderRadius: 8, border: '1px solid var(--border-default)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
                <span style={{ color: 'var(--text-secondary)' }}>Total Tagihan Kotor:</span>
                <span style={{ fontWeight: 600 }} className="table-mono">{formatRupiah(totalKotor)}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12, color: '#ef4444' }}>
                <span>Dikurangi Panjar (Belum Lunas):</span>
                <span style={{ fontWeight: 600 }} className="table-mono">- {formatRupiah(totalPanjar)}</span>
              </div>
              <div style={{ borderTop: '2px solid var(--border-default)', margin: '16px 0' }}></div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: 18, fontWeight: 'bold' }}>SISA BAYAR BERSIH:</span>
                <span style={{ fontSize: 24, fontWeight: 'bold', color: 'var(--color-success)' }} className="table-mono">
                  {formatRupiah(sisaBersih)}
                </span>
              </div>
            </div>
          </div>
          
          <div style={{ marginTop: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 12 }}>
            Dicetak secara otomatis oleh Sistem SAWIT CB pada {new Date().toLocaleString('id-ID')}
          </div>
        </div>
      )}

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
