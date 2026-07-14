'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CheckCircle2, CreditCard, MessageCircle, Printer, Send, X } from 'lucide-react';
import BrandMark from '@/components/branding/BrandMark';
import AppShell from '@/components/layout/AppShell';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import { formatMitraLabel, getMitraSearchText } from '@/lib/display-labels';
import { canRecordMitraPayment, normalizeRole } from '@/lib/roles';
import { supabase } from '@/lib/supabase';
import {
  resolveHargaBersihPerKg,
  resolveTotalNilaiBersihMitra,
} from '@/lib/transaksi-mitra-calculations';
import { useBrandingSettings } from '@/lib/use-branding-settings';
import { formatDateDisplay, formatDateRangeDisplay, formatDateTimeDisplay, formatNumber, formatRupiah, formatWaktu, getTodayISO } from '@/lib/utils';

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
    `Periode: ${formatDateRangeDisplay(dateFrom, dateTo)}`,
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
  const [payment, setPayment] = useState(null);
  const [userRole, setUserRole] = useState(null);
  const [loading, setLoading] = useState(false);
  const [savingPayment, setSavingPayment] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [showWhatsappPreview, setShowWhatsappPreview] = useState(false);
  const [showPaymentModal, setShowPaymentModal] = useState(false);
  const [paymentForm, setPaymentForm] = useState({ metode_bayar: 'tunai', catatan: '' });

  const checkRole = useCallback(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return;

    const { data: user } = await supabase
      .from('users')
      .select('role')
      .eq('id', session.user.id)
      .single();

    setUserRole(normalizeRole(user?.role));
  }, []);

  const loadMitras = useCallback(async () => {
    const { data } = await supabase
      .from('master_mitra')
      .select('id, kode, alamat, nama, penanggung_jawab, no_hp, fee_per_kg')
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
        harga_pabrik_per_kg, fee_owner_per_kg, harga_bersih_per_kg,
        total_fee_owner, total_nilai_bersih, plat_nomor,
        sopir_default_nama, sopir_aktual_nama, sopir_diganti_dari_default, catatan_sopir,
        master_mitra ( id, kode, alamat, nama, fee_per_kg )
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

    const { data: paymentData, error: paymentError } = await supabase
      .from('pembayaran_mitra_kwitansi')
      .select(`
        id, status, periode_dari, periode_sampai, tanggal_bayar, dibayar_at, metode_bayar,
        total_tonase, total_nilai_bersih, total_panjar, nominal_dibayar, jumlah_transaksi,
        catatan, created_at,
        items:pembayaran_mitra_kwitansi_item (
          transaksi_mitra_id, tanggal, waktu_transaksi, sopir_aktual_nama, plat_nomor,
          tonase_snapshot, harga_bersih_per_kg_snapshot, total_nilai_bersih_snapshot, status_transaksi_snapshot,
          transaksi:transaksi_mitra (
            id, status, tonase, harga_harian, total_nilai_bersih, total_kotor,
            harga_pabrik_per_kg, fee_owner_per_kg, harga_bersih_per_kg, total_fee_owner,
            updated_at,
            master_mitra ( fee_per_kg )
          )
        )
      `)
      .eq('master_mitra_id', selectedMitra)
      .eq('periode_dari', dateFrom)
      .eq('periode_sampai', dateTo)
      .neq('status', 'dibatalkan')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (paymentError) {
      console.error('Gagal memuat status pembayaran kwitansi:', paymentError);
      setPayment(null);
      setErrorMsg(paymentError.message);
      setLoading(false);
      return;
    }

    setPayment(paymentData || null);
    
    setLoading(false);
  }, [dateFrom, dateTo, selectedMitra]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadMitras();
    checkRole();
  }, [checkRole, loadMitras]);

  useEffect(() => {
    if (selectedMitra && dateFrom && dateTo) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      loadKwitansiData();
    } else {
      setTransaksi([]);
      setPanjars([]);
      setPayment(null);
      setErrorMsg('');
    }
  }, [selectedMitra, dateFrom, dateTo, loadKwitansiData]);

  const handlePrint = () => {
    window.print();
  };

  const totalTonase = transaksi.reduce((sum, t) => sum + Number(t.tonase), 0);
  const totalNilaiBersih = transaksi.reduce((sum, t) => sum + resolveTotalNilaiBersihMitra(t), 0);
  const totalPanjar = panjars.reduce((sum, p) => sum + Number(p.jumlah), 0);
  const displayTotalTonase = payment ? Number(payment.total_tonase) : totalTonase;
  const displayTotalNilaiBersih = payment ? Number(payment.total_nilai_bersih) : totalNilaiBersih;
  const displayTotalPanjar = payment ? Number(payment.total_panjar) : totalPanjar;
  const sisaBersih = payment ? Number(payment.nominal_dibayar) : totalNilaiBersih - totalPanjar;
  const selectedMitraData = mitras.find(m => m.id === selectedMitra);
  const canRecordPayment = canRecordMitraPayment(userRole);
  const displayPeriode = formatDateRangeDisplay(dateFrom, dateTo);
  const kwitansiRows = useMemo(() => {
    if (!payment) return transaksi;

    return [...(payment.items || [])]
      .sort((a, b) => `${a.tanggal || ''} ${a.waktu_transaksi || ''}`.localeCompare(`${b.tanggal || ''} ${b.waktu_transaksi || ''}`))
      .map(item => ({
        id: item.transaksi_mitra_id,
        tanggal: item.tanggal,
        created_at: item.waktu_transaksi,
        tonase: item.tonase_snapshot,
        harga_bersih_per_kg: item.harga_bersih_per_kg_snapshot,
        total_nilai_bersih: item.total_nilai_bersih_snapshot,
        plat_nomor: item.plat_nomor,
        sopir_aktual_nama: item.sopir_aktual_nama,
        sopir_default_nama: '',
        sopir_diganti_dari_default: false,
        catatan_sopir: '',
      }));
  }, [payment, transaksi]);
  const paymentReview = useMemo(() => {
    if (!payment) return { status: 'belum_dibayar', label: 'Belum Dibayar', reason: '' };

    const paidItems = payment.items || [];
    const paidIds = new Set(paidItems.map(item => item.transaksi_mitra_id));
    const currentIds = new Set(transaksi.map(item => item.id));
    const hasNewTransaction = transaksi.some(item => !paidIds.has(item.id));
    const hasMissingPaidTransaction = paidItems.some(item => !currentIds.has(item.transaksi_mitra_id));
    const hasChangedTransaction = paidItems.some((item) => {
      const trx = item.transaksi;
      if (!trx || trx.status === 'dibatalkan') return true;

      const currentTonase = Number(trx.tonase || 0);
      const currentTotal = resolveTotalNilaiBersihMitra(trx);
      return Math.round(currentTonase * 100) !== Math.round(Number(item.tonase_snapshot || 0) * 100)
        || Math.round(currentTotal) !== Math.round(Number(item.total_nilai_bersih_snapshot || 0));
    });

    if (payment.status === 'perlu_review' || hasNewTransaction || hasMissingPaidTransaction || hasChangedTransaction) {
      return {
        status: 'perlu_review',
        label: 'Perlu Review',
        reason: hasNewTransaction
          ? 'Ada transaksi baru pada periode ini setelah kwitansi dibayar.'
          : hasMissingPaidTransaction
            ? 'Ada transaksi yang dulu dibayar tetapi sekarang tidak aktif/berubah filter.'
            : 'Ada transaksi yang berubah setelah kwitansi dibayar.',
      };
    }

    return { status: 'dibayar', label: 'Sudah Dibayar', reason: '' };
  }, [payment, transaksi]);
  const whatsappNumber = normalizeWhatsappNumber(selectedMitraData?.no_hp);
  const whatsappNumberValid = isValidWhatsappNumber(whatsappNumber);
  const whatsappCaption = buildWhatsappCaption({
    appName: branding.appName,
    mitra: selectedMitraData,
    dateFrom,
    dateTo,
    totalTonase: displayTotalTonase,
    totalNilaiBersih: displayTotalNilaiBersih,
    totalPanjar: displayTotalPanjar,
    sisaBersih,
  });
  const canSendWhatsapp = Boolean(selectedMitra && kwitansiRows.length > 0 && whatsappNumberValid);
  const whatsappWarning = selectedMitra && kwitansiRows.length > 0 && !whatsappNumberValid
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

  const handleMarkPaid = async (event) => {
    event.preventDefault();
    if (!selectedMitra || savingPayment || payment) return;

    setSavingPayment(true);
    const { error } = await supabase.rpc('create_pembayaran_mitra_kwitansi', {
      p_master_mitra_id: selectedMitra,
      p_periode_dari: dateFrom,
      p_periode_sampai: dateTo,
      p_metode_bayar: paymentForm.metode_bayar,
      p_catatan: paymentForm.catatan || null,
    });

    if (error) {
      alert(`Gagal menandai dibayar: ${error.message}`);
      setSavingPayment(false);
      return;
    }

    setShowPaymentModal(false);
    setPaymentForm({ metode_bayar: 'tunai', catatan: '' });
    await loadKwitansiData();
    setSavingPayment(false);
  };

  return (
    <AppShell title="Kwitansi Mitra" subtitle="Dashboard & Cetak Invoice Mitra">
      <div className="page-header no-print">
        <div>
          <p className="page-description">Rekapitulasi otomatis armada dan panjar</p>
        </div>
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
          {canRecordPayment && (
            <button
              className="btn btn-outline"
              onClick={() => setShowPaymentModal(true)}
              disabled={!selectedMitra || transaksi.length === 0 || Boolean(payment) || savingPayment}
            >
              <CreditCard size={16} />
              Tandai Dibayar
            </button>
          )}
          <button className="btn btn-outline" onClick={handleOpenWhatsappPreview} disabled={!canSendWhatsapp}>
            <MessageCircle size={16} />
            Kirim WhatsApp
          </button>
          <button className="btn btn-primary" onClick={handlePrint} disabled={!selectedMitra || kwitansiRows.length === 0}>
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
        <div className={`alert no-print ${paymentReview.status === 'dibayar' ? 'alert-success' : paymentReview.status === 'perlu_review' ? 'alert-warning' : 'alert-info'}`}>
          {paymentReview.status === 'dibayar' ? <CheckCircle2 size={18} /> : paymentReview.status === 'perlu_review' ? <AlertTriangle size={18} /> : <CreditCard size={18} />}
          <div>
            <strong>Status Pembayaran: {paymentReview.label}</strong>
            {payment ? (
              <div style={{ marginTop: 4 }}>
                Dibayar {formatDateDisplay(payment.tanggal_bayar)} {formatWaktu(payment.dibayar_at)} via {payment.metode_bayar}
                {' '}sebesar <span className="table-mono">{formatRupiah(payment.nominal_dibayar)}</span>.
                {paymentReview.reason ? ` ${paymentReview.reason}` : ''}
              </div>
            ) : (
              <div style={{ marginTop: 4 }}>
                Setelah owner membayar kwitansi ini, klik <strong>Tandai Dibayar</strong> agar sistem mencatat mitra/periode ini sudah dibayarkan.
              </div>
            )}
          </div>
        </div>
      )}

      {!loading && !errorMsg && selectedMitra && (
        <div className="print-area card kwitansi-preview" style={{ padding: 'var(--space-xl)' }}>
          <div className="kwitansi-doc-header" style={{ borderBottom: '2px dashed var(--border-default)', paddingBottom: 20, marginBottom: 20, display: 'flex', alignItems: 'center', gap: 16 }}>
            <BrandMark branding={branding} mode="print" size={120} className="kwitansi-logo" />
            <div className="kwitansi-header-info" style={{ display: 'flex', alignItems: 'flex-start', gap: 24, flex: '1 1 auto', minWidth: 0 }}>
              <div className="kwitansi-title-block">
                <h1 className="kwitansi-title" style={{ margin: 0, fontSize: 22, color: 'var(--text-primary)' }}>
                  <span className="kwitansi-title-line">KWITANSI</span>
                  <span className="kwitansi-title-line">PEMBAYARAN TBS</span>
                </h1>
                <p className="kwitansi-brand-name" style={{ margin: '6px 0 0', color: 'var(--text-secondary)' }}>{branding.appName}</p>
              </div>
              <div className="kwitansi-recipient" style={{ textAlign: 'left', marginLeft: 'auto' }}>
                <div style={{ fontSize: 14, color: 'var(--text-secondary)' }}>Mitra:</div>
                <h2 style={{ margin: '4px 0 0', fontSize: 20, color: 'var(--text-primary)' }}>{selectedMitraData?.nama}</h2>
                <div style={{ fontSize: 13, color: 'var(--text-tertiary)', marginTop: 4 }}>
                  {formatMitraLabel(selectedMitraData)}
                </div>
                <div style={{ fontSize: 14, color: 'var(--text-secondary)', marginTop: 4 }}>
                  Periode: {displayPeriode}
                </div>
                {payment && (
                  <div style={{ marginTop: 10, display: 'inline-flex', padding: '6px 10px', border: '1px solid #111', borderRadius: 6, fontWeight: 800, color: '#111' }}>
                    {paymentReview.status === 'perlu_review' ? 'PERLU REVIEW' : 'SUDAH DIBAYAR'}
                  </div>
                )}
              </div>
            </div>
          </div>

          <h3 style={{ fontSize: 16, marginBottom: 16 }}>Rincian Armada Masuk:</h3>
          <div className="kwitansi-table-wrap">
            <table className="kwitansi-detail-table" style={{ width: '100%', borderCollapse: 'collapse', marginBottom: 24 }}>
            <thead>
              <tr style={{ background: 'var(--bg-surface)', borderBottom: '2px solid var(--border-default)' }}>
                <th style={{ padding: 12, textAlign: 'left' }}>Tanggal</th>
                <th style={{ padding: 12, textAlign: 'left' }}>Armada</th>
                <th style={{ padding: 12, textAlign: 'right' }}>Tonase</th>
                <th style={{ padding: 12, textAlign: 'right' }}>Harga/Kg</th>
                <th style={{ padding: 12, textAlign: 'right' }}>Bersih</th>
              </tr>
            </thead>
            <tbody>
              {kwitansiRows.length === 0 ? (
                <tr><td colSpan={5} style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)' }}>Tidak ada transaksi pada periode ini</td></tr>
              ) : (
                kwitansiRows.map((t) => (
                  <tr key={t.id} style={{ borderBottom: '1px solid var(--border-default)' }}>
                    <td style={{ padding: 12 }}>
                      <div style={{ fontWeight: 700 }}>{formatDateDisplay(t.tanggal)}</div>
                    </td>
                    <td style={{ padding: 12 }}>
                      <div style={{ fontWeight: 600 }}>{t.sopir_aktual_nama || t.sopir_default_nama || '-'}</div>
                      <div className="table-mono" style={{ marginTop: 4, fontSize: 12, color: 'var(--text-tertiary)' }}>{t.plat_nomor || '-'}</div>
                      {t.sopir_diganti_dari_default && (
                        <div style={{ fontSize: 12, color: 'var(--text-tertiary)', marginTop: 4 }}>
                          Pengganti dari {t.sopir_default_nama || '-'}
                          {t.catatan_sopir ? ` - ${t.catatan_sopir}` : ''}
                        </div>
                      )}
                    </td>
                    <td style={{ padding: 12, textAlign: 'right' }}>{Number(t.tonase).toLocaleString('id-ID')}</td>
                    <td style={{ padding: 12, textAlign: 'right' }} className="table-mono">{formatRupiah(resolveHargaBersihPerKg(t))}</td>
                    <td style={{ padding: 12, textAlign: 'right' }} className="table-mono">{formatRupiah(resolveTotalNilaiBersihMitra(t))}</td>
                  </tr>
                ))
              )}
            </tbody>
            <tfoot>
              <tr style={{ background: 'var(--bg-surface)', fontWeight: 'bold' }}>
                <td colSpan={2} style={{ padding: 12, textAlign: 'right' }}>TOTAL NILAI BERSIH TBS:</td>
                <td style={{ padding: 12, textAlign: 'right' }}>{displayTotalTonase.toLocaleString('id-ID')} Kg</td>
                <td style={{ padding: 12, textAlign: 'right' }}></td>
                <td style={{ padding: 12, textAlign: 'right', color: 'var(--text-primary)', fontSize: 16 }}>{formatRupiah(displayTotalNilaiBersih)}</td>
              </tr>
            </tfoot>
            </table>
          </div>

          <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 24 }}>
            <div className="kwitansi-total-box" style={{ width: 400, background: 'var(--bg-surface)', padding: 20, borderRadius: 8, border: '1px solid var(--border-default)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
                <span style={{ color: 'var(--text-secondary)' }}>Total Nilai Bersih TBS:</span>
                <span style={{ fontWeight: 600 }} className="table-mono">{formatRupiah(displayTotalNilaiBersih)}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12, color: '#ef4444' }}>
                <span>Potongan Panjar Mitra:</span>
                <span style={{ fontWeight: 600 }} className="table-mono">- {formatRupiah(displayTotalPanjar)}</span>
              </div>
              <div className="kwitansi-total-divider" style={{ borderTop: '2px solid var(--border-default)', margin: '16px 0' }}></div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: 18, fontWeight: 'bold' }}>SISA DIBAYAR KE MITRA:</span>
                <span style={{ fontSize: 24, fontWeight: 'bold', color: 'var(--color-success)' }} className="table-mono">
                  {formatRupiah(sisaBersih)}
                </span>
              </div>
            </div>
          </div>

          {payment && (
            <div style={{ marginTop: 24, padding: 16, border: '1px solid var(--border-default)', borderRadius: 8, color: 'var(--text-secondary)' }}>
              <strong style={{ color: 'var(--text-primary)' }}>Status Pembayaran:</strong>{' '}
              {paymentReview.status === 'perlu_review' ? 'Perlu review' : 'Sudah dibayar'} pada {formatDateDisplay(payment.tanggal_bayar)} {formatWaktu(payment.dibayar_at)} via {payment.metode_bayar}.
              {payment.catatan ? ` Catatan: ${payment.catatan}` : ''}
            </div>
          )}
          
          <div style={{ marginTop: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 12 }}>
            Dicetak secara otomatis oleh Sistem {branding.appName} pada {formatDateTimeDisplay(new Date())}
          </div>
        </div>
      )}

      <style jsx global>{`
        .kwitansi-table-wrap {
          overflow-x: auto;
        }
        .kwitansi-title {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }
        .kwitansi-title-line {
          display: block;
          white-space: nowrap;
        }

        @media screen {
          .kwitansi-preview {
            padding: 24px !important;
            font-size: 13px !important;
          }
          .kwitansi-doc-header {
            padding-bottom: 18px !important;
            margin-bottom: 18px !important;
          }
          .kwitansi-header-info {
            flex-wrap: nowrap;
          }
          .kwitansi-title-block {
            flex: 0 0 auto;
            transform: translateY(12px);
          }
          .kwitansi-recipient {
            max-width: 300px;
            margin-left: auto;
          }
          .kwitansi-logo {
            width: 104px !important;
            height: 104px !important;
            flex: 0 0 104px !important;
          }
          .kwitansi-title {
            font-size: 20px !important;
            line-height: 1.2 !important;
          }
          .kwitansi-brand-name {
            font-size: 15px !important;
          }
          .kwitansi-recipient,
          .kwitansi-recipient div {
            font-size: 13px !important;
          }
          .kwitansi-recipient h2 {
            font-size: 18px !important;
          }
          .kwitansi-preview h3 {
            font-size: 14px !important;
            margin-bottom: 12px !important;
          }
          .kwitansi-detail-table {
            min-width: 620px;
            margin-bottom: 18px !important;
            font-size: 13px !important;
          }
          .kwitansi-detail-table th,
          .kwitansi-detail-table td {
            padding: 8px 10px !important;
            font-size: 13px !important;
            line-height: 1.35 !important;
          }
          .kwitansi-total-box {
            width: 360px !important;
            padding: 16px !important;
            font-size: 13px !important;
          }
          .kwitansi-total-box span {
            font-size: 13px !important;
          }
          .kwitansi-total-box span[style*="font-size: 18px"] {
            font-size: 15px !important;
          }
          .kwitansi-total-box span[style*="font-size: 24px"] {
            font-size: 19px !important;
          }
        }

        @media screen and (min-width: 768px) and (max-width: 1440px) {
          .kwitansi-preview {
            padding: 20px !important;
          }
          .kwitansi-doc-header {
            padding-bottom: 16px !important;
            margin-bottom: 16px !important;
          }
          .kwitansi-header-info {
            gap: 18px !important;
          }
          .kwitansi-title-block {
            transform: translateY(11px);
          }
          .kwitansi-recipient {
            margin-left: auto !important;
          }
          .kwitansi-logo {
            width: 96px !important;
            height: 96px !important;
            flex-basis: 96px !important;
          }
          .kwitansi-title {
            font-size: 18px !important;
            line-height: 1.2 !important;
          }
          .kwitansi-brand-name {
            font-size: 14px !important;
          }
          .kwitansi-recipient,
          .kwitansi-recipient div {
            font-size: 12px !important;
          }
          .kwitansi-recipient h2 {
            font-size: 16px !important;
          }
          .kwitansi-preview h3 {
            font-size: 14px !important;
            margin-bottom: 10px !important;
          }
          .kwitansi-detail-table {
            min-width: 620px;
            margin-bottom: 16px !important;
            font-size: 12px !important;
          }
          .kwitansi-detail-table th,
          .kwitansi-detail-table td {
            padding: 7px 9px !important;
            font-size: 12px !important;
            line-height: 1.35 !important;
          }
          .kwitansi-total-box {
            width: 340px !important;
            padding: 14px !important;
            font-size: 12px !important;
          }
          .kwitansi-total-box span {
            font-size: 12px !important;
          }
          .kwitansi-total-box span[style*="font-size: 18px"] {
            font-size: 14px !important;
          }
          .kwitansi-total-box span[style*="font-size: 24px"] {
            font-size: 18px !important;
          }
        }

        @media screen and (max-width: 767px) {
          .kwitansi-preview {
            padding: 16px !important;
          }
          .kwitansi-doc-header {
            flex-direction: column;
            align-items: flex-start !important;
          }
          .kwitansi-header-info {
            flex-direction: column;
            gap: 10px !important;
          }
          .kwitansi-title-block {
            transform: none;
          }
          .kwitansi-recipient {
            max-width: none !important;
            margin-left: 0 !important;
          }
          .kwitansi-logo {
            width: 84px !important;
            height: 84px !important;
            flex-basis: 84px !important;
          }
          .kwitansi-recipient {
            text-align: left !important;
          }
          .kwitansi-total-box {
            width: 100% !important;
          }
        }

        @page {
          margin: 12mm;
        }

        @media print {
          html,
          body {
            width: auto !important;
            background: #fff !important;
          }
          .app-shell,
          .main-content,
          .page-content {
            display: block !important;
            width: 100% !important;
            max-width: none !important;
            min-height: auto !important;
            margin: 0 !important;
            padding: 0 !important;
          }
          .main-content {
            margin-left: 0 !important;
          }
          .sidebar,
          .header,
          .bottom-nav {
            display: none !important;
          }
          body * { visibility: hidden; }
          .print-area, .print-area * { visibility: visible; color: #000 !important; background: #fff !important; }
          .print-area {
            position: static !important;
            left: auto !important;
            top: auto !important;
            width: 100% !important;
            max-width: none !important;
            box-shadow: none !important;
            border: 0 !important;
            border-radius: 0 !important;
            margin: 0 !important;
            padding: 0 !important;
            transform: none !important;
          }
          .kwitansi-preview {
            font-size: 11px !important;
          }
          .kwitansi-logo {
            width: 100px !important;
            height: 100px !important;
            flex: 0 0 100px !important;
          }
          .kwitansi-table-wrap { overflow: visible !important; }
          .kwitansi-doc-header {
            display: flex !important;
            flex-direction: row !important;
            align-items: center !important;
            justify-content: flex-start !important;
            border-bottom: 1.5px dashed #111 !important;
            gap: 14px !important;
            width: 100% !important;
            padding-bottom: 12px !important;
            margin-bottom: 12px !important;
          }
          .kwitansi-header-info {
            display: flex !important;
            flex-direction: row !important;
            align-items: flex-start !important;
            flex: 1 1 auto !important;
            flex-wrap: nowrap !important;
            gap: 18px !important;
            min-width: 0 !important;
          }
          .kwitansi-title-block {
            flex: 0 0 180px !important;
            min-width: 0 !important;
            transform: translateY(12px) !important;
          }
          .kwitansi-title {
            font-size: 18px !important;
            line-height: 1.05 !important;
            white-space: normal !important;
            gap: 1px !important;
          }
          .kwitansi-brand-name {
            font-size: 11px !important;
          }
          .kwitansi-preview h3 {
            font-size: 12px !important;
            margin-bottom: 8px !important;
          }
          .kwitansi-recipient {
            flex: 0 1 260px !important;
            min-width: 190px !important;
            max-width: 260px !important;
            margin-left: auto !important;
            padding-left: 0 !important;
            text-align: left !important;
          }
          .kwitansi-recipient,
          .kwitansi-recipient div {
            font-size: 10.5px !important;
            line-height: 1.35 !important;
          }
          .kwitansi-recipient h2 {
            font-size: 14px !important;
            line-height: 1.25 !important;
          }
          .kwitansi-detail-table {
            border-top: 1.5px solid #111 !important;
            border-bottom: 1.5px solid #111 !important;
            font-size: 10.5px !important;
            margin-bottom: 14px !important;
            min-width: 0 !important;
            width: 100% !important;
          }
          .kwitansi-detail-table th,
          .kwitansi-detail-table td {
            padding: 6px 8px !important;
            font-size: 10.5px !important;
            line-height: 1.3 !important;
          }
          .kwitansi-detail-table thead tr {
            border-bottom: 1.5px solid #111 !important;
          }
          .kwitansi-detail-table tbody tr {
            border-bottom: 1px solid #b8b8b8 !important;
          }
          .kwitansi-detail-table tbody tr:last-child {
            border-bottom: 1.5px solid #111 !important;
          }
          .kwitansi-detail-table tfoot tr {
            border-top: 2px solid #111 !important;
            border-bottom: 1.5px solid #111 !important;
          }
          .kwitansi-total-box {
            border: 1.5px solid #111 !important;
            width: 360px !important;
            padding: 12px !important;
            border-radius: 4px !important;
          }
          .kwitansi-total-box span {
            font-size: 10.5px !important;
          }
          .kwitansi-total-box span[style*="font-size: 18px"] {
            font-size: 13px !important;
          }
          .kwitansi-total-box span[style*="font-size: 24px"] {
            font-size: 16px !important;
          }
          .kwitansi-total-divider {
            border-top: 1.5px solid #111 !important;
          }
          .no-print { display: none !important; }
        }
      `}</style>

      {showPaymentModal && (
        <div className="modal-overlay no-print" onClick={() => !savingPayment && setShowPaymentModal(false)}>
          <div className="modal" onClick={event => event.stopPropagation()} style={{ maxWidth: 620 }}>
            <div className="modal-header">
              <h3 className="modal-title">Tandai Kwitansi Sudah Dibayar</h3>
              <button className="modal-close" disabled={savingPayment} onClick={() => setShowPaymentModal(false)} aria-label="Tutup">
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleMarkPaid}>
              <div className="modal-body">
                <div className="alert alert-info">
                  <div>
                    <strong>Kwitansi menjadi bukti pembayaran utama.</strong>
                    <div style={{ marginTop: 4 }}>
                      Sistem akan menyimpan snapshot transaksi periode ini dan menandai panjar yang dipotong sebagai lunas agar tidak terpotong lagi di kwitansi berikutnya.
                    </div>
                  </div>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 12, marginBottom: 16 }}>
                  <div className="card" style={{ padding: 14, borderRadius: 8 }}>
                    <div className="text-tertiary" style={{ fontSize: 12 }}>Total Nilai Bersih</div>
                    <div className="table-mono" style={{ fontWeight: 800 }}>{formatRupiah(totalNilaiBersih)}</div>
                  </div>
                  <div className="card" style={{ padding: 14, borderRadius: 8 }}>
                    <div className="text-tertiary" style={{ fontSize: 12 }}>Potongan Panjar</div>
                    <div className="table-mono" style={{ fontWeight: 800, color: 'var(--color-danger)' }}>{formatRupiah(totalPanjar)}</div>
                  </div>
                  <div className="card" style={{ padding: 14, borderRadius: 8 }}>
                    <div className="text-tertiary" style={{ fontSize: 12 }}>Dibayar ke Mitra</div>
                    <div className="table-mono" style={{ fontWeight: 900, color: 'var(--color-success)' }}>{formatRupiah(totalNilaiBersih - totalPanjar)}</div>
                  </div>
                </div>

                <div className="form-group">
                  <label className="form-label form-label-required">Metode Bayar</label>
                  <select
                    className="form-input form-select"
                    required
                    value={paymentForm.metode_bayar}
                    onChange={event => setPaymentForm(current => ({ ...current, metode_bayar: event.target.value }))}
                  >
                    <option value="tunai">Tunai</option>
                    <option value="transfer">Transfer</option>
                    <option value="lainnya">Lainnya</option>
                  </select>
                </div>

                <div className="form-group">
                  <label className="form-label">Catatan</label>
                  <textarea
                    className="form-input"
                    rows={3}
                    value={paymentForm.catatan}
                    onChange={event => setPaymentForm(current => ({ ...current, catatan: event.target.value }))}
                    placeholder="Contoh: dibayar tunai setelah cek kwitansi"
                  />
                </div>
              </div>

              <div className="modal-footer">
                <button type="button" className="btn btn-outline" disabled={savingPayment} onClick={() => setShowPaymentModal(false)}>
                  Batal
                </button>
                <button type="submit" className="btn btn-primary" disabled={savingPayment || transaksi.length === 0}>
                  <CheckCircle2 size={16} />
                  {savingPayment ? 'Menyimpan...' : 'Simpan Sudah Dibayar'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

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
