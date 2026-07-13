'use client';

import { useCallback, useEffect, useState } from 'react';
import { MessageCircle, Printer, Send, X } from 'lucide-react';
import BrandMark from '@/components/branding/BrandMark';
import AppShell from '@/components/layout/AppShell';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import { formatMitraLabel, getMitraSearchText } from '@/lib/display-labels';
import { supabase } from '@/lib/supabase';
import { useBrandingSettings } from '@/lib/use-branding-settings';
import { formatNumber, formatRupiah, formatWaktu, getTodayISO } from '@/lib/utils';

function normalizeWhatsappNumber(phone) {
  const digits = String(phone || '').replace(/\D/g, '');

  if (!digits) return '';
  if (digits.startsWith('0')) return `62${digits.slice(1)}`;
  if (digits.startsWith('62')) return digits;
  if (digits.startsWith('8')) return `62${digits}`;

  return digits;
}

function isValidWhatsappNumber(phone) {
  return /^62\d{8,13}$/.test(phone);
}

function buildWhatsappCaption({ appName, mitra, dateFrom, dateTo, totalTonase, totalNilaiBersih, totalPanjar, sisaBersih }) {
  return [
    `Kwitansi Pembayaran ${appName}`,
    `Mitra: ${formatMitraLabel(mitra) || '-'}`,
    `Periode: ${dateFrom} s/d ${dateTo}`,
    `Total Tonase: ${formatNumber(totalTonase)} Kg`,
    `Total Nilai Bersih TBS: ${formatRupiah(totalNilaiBersih)}`,
    `Potongan Panjar Mitra: ${formatRupiah(totalPanjar)}`,
    `Sisa Dibayar ke Mitra: ${formatRupiah(sisaBersih)}`,
    '',
    'Mohon dicek. PDF kwitansi pembayaran terlampir.',
  ].join('\n');
}

export default function KwitansiMitraPage() {
  const { branding } = useBrandingSettings();
  const [mitras, setMitras] = useState([]);
  const [selectedMitra, setSelectedMitra] = useState('');
  const [dateFrom, setDateFrom] = useState(getTodayISO);
  const [dateTo, setDateTo] = useState(getTodayISO);
  
  const [transaksi, setTransaksi] = useState([]);
  const [panjars, setPanjars] = useState([]);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [showWhatsappPreview, setShowWhatsappPreview] = useState(false);

  const loadMitras = useCallback(async () => {
    const { data } = await supabase
      .from('master_mitra')
      .select('id, kode, alamat, nama, penanggung_jawab, no_hp')
      .eq('aktif', true)
      .order('kode');
    setMitras(data || []);
  }, []);

  const loadKwitansiData = useCallback(async () => {
    setLoading(true);
    setErrorMsg('');
    
    // 1. Fetch Transaksi Masuk
    const { data: trxData, error: trxError } = await supabase
      .from('transaksi_mitra')
      .select(`
        id, tanggal, tonase, harga_harian, total_kotor,
        created_at,
        harga_bersih_per_kg, total_nilai_bersih, plat_nomor,
        sopir_default_nama, sopir_aktual_nama, sopir_diganti_dari_default, catatan_sopir
      `)
      .eq('mitra_id', selectedMitra)
      .gte('tanggal', dateFrom)
      .lte('tanggal', dateTo)
      .neq('status', 'dibatalkan')
      .order('tanggal', { ascending: true })
      .order('created_at', { ascending: true });

    if (trxError) {
      console.error('Gagal memuat transaksi kwitansi mitra:', trxError);
      setTransaksi([]);
      setPanjars([]);
      setErrorMsg(trxError.message);
      setLoading(false);
      return;
    }
      
    setTransaksi(trxData || []);

    // 2. Fetch panjar mitra yang masih menjadi potongan pembayaran
    const { data: pjrData, error: panjarError } = await supabase
      .from('panjar_mitra')
      .select('*')
      .eq('mitra_id', selectedMitra)
      .eq('status', 'belum_lunas');

    if (panjarError) {
      console.error('Gagal memuat panjar mitra:', panjarError);
      setPanjars([]);
      setErrorMsg(panjarError.message);
      setLoading(false);
      return;
    }
      
    setPanjars(pjrData || []);
    
    setLoading(false);
  }, [dateFrom, dateTo, selectedMitra]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadMitras();
  }, [loadMitras]);

  useEffect(() => {
    if (selectedMitra && dateFrom && dateTo) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      loadKwitansiData();
    } else {
      setTransaksi([]);
      setPanjars([]);
      setErrorMsg('');
    }
  }, [selectedMitra, dateFrom, dateTo, loadKwitansiData]);

  const handlePrint = () => {
    window.print();
  };

  const totalTonase = transaksi.reduce((sum, t) => sum + Number(t.tonase), 0);
  const totalNilaiBersih = transaksi.reduce((sum, t) => sum + Number(t.total_nilai_bersih ?? t.total_kotor), 0);
  const totalPanjar = panjars.reduce((sum, p) => sum + Number(p.jumlah), 0);
  const sisaBersih = totalNilaiBersih - totalPanjar;
  const selectedMitraData = mitras.find(m => m.id === selectedMitra);
  const whatsappNumber = normalizeWhatsappNumber(selectedMitraData?.no_hp);
  const whatsappNumberValid = isValidWhatsappNumber(whatsappNumber);
  const whatsappCaption = buildWhatsappCaption({
    appName: branding.appName,
    mitra: selectedMitraData,
    dateFrom,
    dateTo,
    totalTonase,
    totalNilaiBersih,
    totalPanjar,
    sisaBersih,
  });
  const canSendWhatsapp = Boolean(selectedMitra && transaksi.length > 0 && whatsappNumberValid);
  const whatsappWarning = selectedMitra && transaksi.length > 0 && !whatsappNumberValid
    ? selectedMitraData?.no_hp
      ? 'Nomor WA penanggung jawab mitra belum valid. Perbarui nomor di Master Mitra.'
      : 'Nomor WA penanggung jawab mitra belum diisi. Lengkapi nomor di Master Mitra.'
    : '';

  const handleOpenWhatsappPreview = () => {
    if (!canSendWhatsapp) return;
    setShowWhatsappPreview(true);
  };

  const handleOpenWhatsapp = () => {
    const whatsappUrl = `https://wa.me/${whatsappNumber}?text=${encodeURIComponent(whatsappCaption)}`;
    window.open(whatsappUrl, '_blank', 'noopener,noreferrer');
    setShowWhatsappPreview(false);
  };

  return (
    <AppShell title="Kwitansi Mitra" subtitle="Dashboard & Cetak Invoice Mitra">
      <div className="page-header no-print">
        <div>
          <h2 className="page-title">Kwitansi Mitra (MVP)</h2>
          <p className="page-description">Rekapitulasi otomatis armada dan panjar</p>
        </div>
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
          <button className="btn btn-outline" onClick={handleOpenWhatsappPreview} disabled={!canSendWhatsapp}>
            <MessageCircle size={16} />
            Kirim WhatsApp
          </button>
          <button className="btn btn-primary" onClick={handlePrint} disabled={!selectedMitra || transaksi.length === 0}>
            <Printer size={16} />
            Cetak PDF / Struk
          </button>
        </div>
      </div>

      <div className="toolbar no-print card" style={{ padding: 'var(--space-md)', marginBottom: 'var(--space-lg)', display: 'flex', gap: 16, flexWrap: 'wrap' }}>
        <div style={{ flex: 1, minWidth: 200 }}>
          <label style={{ display: 'block', fontSize: 14, fontWeight: 500, marginBottom: 8 }}>Nama Mitra</label>
          <SearchableCombobox
            value={selectedMitra}
            options={mitras}
            onChange={setSelectedMitra}
            getOptionLabel={formatMitraLabel}
            getSearchText={getMitraSearchText}
            placeholder="Cari kode, alamat, atau nama mitra..."
            emptyLabel="Mitra tidak ditemukan"
          />
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

      {!loading && errorMsg && (
        <div className="card" style={{ padding: 24, color: 'var(--color-danger)', textAlign: 'center' }}>
          Gagal memuat kwitansi: {errorMsg}
        </div>
      )}

      {!loading && !errorMsg && whatsappWarning && (
        <div className="alert alert-warning no-print">
          <div>
            <strong>WhatsApp belum bisa digunakan.</strong>
            <div style={{ marginTop: 4 }}>{whatsappWarning}</div>
          </div>
        </div>
      )}

      {!loading && !errorMsg && selectedMitra && (
        <div className="print-area card" style={{ padding: 'var(--space-2xl)' }}>
          <div style={{ borderBottom: '2px dashed var(--border-default)', paddingBottom: 24, marginBottom: 24, display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 20 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 16, minWidth: 0 }}>
              <BrandMark branding={branding} mode="print" size={58} />
              <div>
                <h1 style={{ margin: 0, fontSize: 24, color: 'var(--text-primary)' }}>KWITANSI PEMBAYARAN TBS</h1>
                <p style={{ margin: '8px 0 0', color: 'var(--text-secondary)' }}>{branding.appName}</p>
              </div>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{ fontSize: 14, color: 'var(--text-secondary)' }}>Kepada Yth. Mitra:</div>
              <h2 style={{ margin: '4px 0 0', fontSize: 20, color: 'var(--text-primary)' }}>{selectedMitraData?.nama}</h2>
              <div style={{ fontSize: 13, color: 'var(--text-tertiary)', marginTop: 4 }}>
                {formatMitraLabel(selectedMitraData)}
              </div>
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
                <th style={{ padding: 12, textAlign: 'left' }}>Waktu</th>
                <th style={{ padding: 12, textAlign: 'left' }}>Sopir Aktual</th>
                <th style={{ padding: 12, textAlign: 'left' }}>Plat Armada</th>
                <th style={{ padding: 12, textAlign: 'right' }}>Tonase (Kg)</th>
                <th style={{ padding: 12, textAlign: 'right' }}>Harga Bersih/Kg</th>
                <th style={{ padding: 12, textAlign: 'right' }}>Nilai Bersih (Rp)</th>
              </tr>
            </thead>
            <tbody>
              {transaksi.length === 0 ? (
                <tr><td colSpan={7} style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)' }}>Tidak ada transaksi pada periode ini</td></tr>
              ) : (
                transaksi.map((t, i) => (
                  <tr key={i} style={{ borderBottom: '1px solid var(--border-default)' }}>
                    <td style={{ padding: 12 }}>{t.tanggal}</td>
                    <td style={{ padding: 12 }} className="table-mono">{formatWaktu(t.created_at)}</td>
                    <td style={{ padding: 12 }}>
                      <div style={{ fontWeight: 600 }}>{t.sopir_aktual_nama || t.sopir_default_nama || '-'}</div>
                      {t.sopir_diganti_dari_default && (
                        <div style={{ fontSize: 12, color: 'var(--text-tertiary)', marginTop: 4 }}>
                          Pengganti dari {t.sopir_default_nama || '-'}
                          {t.catatan_sopir ? ` - ${t.catatan_sopir}` : ''}
                        </div>
                      )}
                    </td>
                    <td style={{ padding: 12 }} className="table-mono">{t.plat_nomor || '-'}</td>
                    <td style={{ padding: 12, textAlign: 'right' }}>{Number(t.tonase).toLocaleString('id-ID')}</td>
                    <td style={{ padding: 12, textAlign: 'right' }} className="table-mono">{formatRupiah(t.harga_bersih_per_kg ?? t.harga_harian)}</td>
                    <td style={{ padding: 12, textAlign: 'right' }} className="table-mono">{formatRupiah(t.total_nilai_bersih ?? t.total_kotor)}</td>
                  </tr>
                ))
              )}
            </tbody>
            <tfoot>
              <tr style={{ background: 'var(--bg-surface)', fontWeight: 'bold' }}>
                <td colSpan={4} style={{ padding: 12, textAlign: 'right' }}>TOTAL NILAI BERSIH TBS:</td>
                <td style={{ padding: 12, textAlign: 'right' }}>{totalTonase.toLocaleString('id-ID')} Kg</td>
                <td style={{ padding: 12, textAlign: 'right' }}></td>
                <td style={{ padding: 12, textAlign: 'right', color: 'var(--text-primary)', fontSize: 16 }}>{formatRupiah(totalNilaiBersih)}</td>
              </tr>
            </tfoot>
          </table>

          <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 32 }}>
            <div style={{ width: 400, background: 'var(--bg-surface)', padding: 24, borderRadius: 8, border: '1px solid var(--border-default)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
                <span style={{ color: 'var(--text-secondary)' }}>Total Nilai Bersih TBS:</span>
                <span style={{ fontWeight: 600 }} className="table-mono">{formatRupiah(totalNilaiBersih)}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12, color: '#ef4444' }}>
                <span>Potongan Panjar Mitra:</span>
                <span style={{ fontWeight: 600 }} className="table-mono">- {formatRupiah(totalPanjar)}</span>
              </div>
              <div style={{ borderTop: '2px solid var(--border-default)', margin: '16px 0' }}></div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: 18, fontWeight: 'bold' }}>SISA DIBAYAR KE MITRA:</span>
                <span style={{ fontSize: 24, fontWeight: 'bold', color: 'var(--color-success)' }} className="table-mono">
                  {formatRupiah(sisaBersih)}
                </span>
              </div>
            </div>
          </div>
          
          <div style={{ marginTop: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 12 }}>
            Dicetak secara otomatis oleh Sistem {branding.appName} pada {new Date().toLocaleString('id-ID')}
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

      {showWhatsappPreview && (
        <div className="modal-overlay no-print" onClick={() => setShowWhatsappPreview(false)}>
          <div className="modal" onClick={event => event.stopPropagation()} style={{ maxWidth: 680 }}>
            <div className="modal-header">
              <h3 className="modal-title">Kirim Kwitansi via WhatsApp</h3>
              <button className="modal-close" onClick={() => setShowWhatsappPreview(false)} aria-label="Tutup">
                <X size={18} />
              </button>
            </div>

            <div className="modal-body">
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 12, marginBottom: 16 }}>
                <div style={{ padding: 14, border: '1px solid var(--border-default)', borderRadius: 8, background: 'var(--bg-surface)' }}>
                  <div style={{ fontSize: 12, color: 'var(--text-tertiary)', marginBottom: 6 }}>Mitra</div>
                  <div style={{ fontWeight: 700 }}>{formatMitraLabel(selectedMitraData) || '-'}</div>
                </div>
                <div style={{ padding: 14, border: '1px solid var(--border-default)', borderRadius: 8, background: 'var(--bg-surface)' }}>
                  <div style={{ fontSize: 12, color: 'var(--text-tertiary)', marginBottom: 6 }}>Penerima</div>
                  <div style={{ fontWeight: 700 }}>{selectedMitraData?.penanggung_jawab || selectedMitraData?.nama || '-'}</div>
                  <div className="table-mono" style={{ marginTop: 4, color: 'var(--text-secondary)' }}>{whatsappNumber}</div>
                </div>
              </div>

              <div className="alert alert-info" style={{ marginBottom: 16 }}>
                <div>
                  <strong>PDF dilampirkan dari hasil cetak/simpan.</strong>
                  <div style={{ marginTop: 4 }}>Buka WhatsApp akan mengisi pesan otomatis; lampirkan PDF kwitansi pembayaran sebelum dikirim.</div>
                </div>
              </div>

              <label style={{ display: 'block', fontSize: 14, fontWeight: 600, marginBottom: 8 }}>Preview Pesan</label>
              <pre style={{
                whiteSpace: 'pre-wrap',
                wordBreak: 'break-word',
                margin: 0,
                padding: 16,
                borderRadius: 8,
                border: '1px solid var(--border-default)',
                background: 'var(--bg-input)',
                color: 'var(--text-primary)',
                fontFamily: 'var(--font-mono)',
                fontSize: 13,
                lineHeight: 1.6,
              }}>{whatsappCaption}</pre>
            </div>

            <div className="modal-footer">
              <button className="btn btn-outline" onClick={() => setShowWhatsappPreview(false)}>
                Batal
              </button>
              <button className="btn btn-outline" onClick={handlePrint}>
                <Printer size={16} />
                Cetak / Simpan PDF
              </button>
              <button className="btn btn-primary" onClick={handleOpenWhatsapp}>
                <Send size={16} />
                Buka WhatsApp
              </button>
            </div>
          </div>
        </div>
      )}
    </AppShell>
  );
}
