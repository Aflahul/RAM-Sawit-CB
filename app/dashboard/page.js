'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import AppShell from '@/components/layout/AppShell';
import { canManageBusinessSettings, canManageFinance, canViewProfit, normalizeRole } from '@/lib/roles';
import { supabase } from '@/lib/supabase';
import { formatDateDisplay, formatNumber, formatRupiah, getTodayISO } from '@/lib/utils';
import { resolveTotalFeeOwner } from '@/lib/transaksi-mitra-calculations';
import {
  AlertTriangle,
  BadgeDollarSign,
  Box,
  CheckCircle2,
  Clock3,
  CreditCard,
  FileText,
  ReceiptText,
  Scale,
  Store,
  Truck,
  Wallet,
} from 'lucide-react';

function getLastSevenDays() {
  const days = [];
  for (let i = 6; i >= 0; i -= 1) {
    const date = new Date(new Date().getTime() + 8 * 60 * 60 * 1000);
    date.setUTCDate(date.getUTCDate() - i);
    days.push(date.toISOString().split('T')[0]);
  }
  return days;
}

function dayLabel(dateString) {
  return formatDateDisplay(dateString).slice(0, 5);
}

function formatCompactRupiah(value) {
  const amount = Number(value || 0);
  if (amount >= 1000000000) return `Rp${(amount / 1000000000).toLocaleString('id-ID', { maximumFractionDigits: 1 })}M`;
  if (amount >= 1000000) return `Rp${(amount / 1000000).toLocaleString('id-ID', { maximumFractionDigits: 1 })}jt`;
  if (amount >= 1000) return `Rp${Math.round(amount / 1000).toLocaleString('id-ID')}rb`;
  return formatRupiah(amount);
}

function getSignedStok(row) {
  const berat = Number(row.berat_kg || 0);
  if (row.tipe === 'masuk') return Math.abs(berat);
  if (row.tipe === 'keluar') return -Math.abs(berat);
  return berat;
}

function getSignedKas(row) {
  const jumlah = Number(row.jumlah || 0);
  if (['masuk', 'transfer_masuk'].includes(row.tipe)) return jumlah;
  if (['keluar', 'transfer_keluar'].includes(row.tipe)) return -jumlah;
  if (row.tipe === 'reversal') return jumlah;
  return row.sumber === 'reversal' ? jumlah : 0;
}

function getPartyKey(row) {
  return [
    row.pihak_type || 'lainnya',
    row.petani_id || row.master_mitra_id || row.mitra_id || row.sopir_id || row.pihak_nama_manual || 'manual',
  ].join(':');
}

function MetricCard({ title, value, label, icon, tone = 'neutral', href }) {
  const toneClass = {
    success: 'text-success',
    danger: 'text-danger',
    warning: 'text-warning',
    info: '',
    neutral: '',
  }[tone] || '';

  const body = (
    <div className="card dashboard-card">
      <div className="card-header">
        <span className="card-title">{title}</span>
        <div className={`card-icon ${tone === 'danger' ? 'card-icon-red' : tone === 'warning' ? 'card-icon-gold' : tone === 'info' ? 'card-icon-blue' : 'card-icon-green'}`}>
          {icon}
        </div>
      </div>
      <div className={`card-value ${toneClass}`}>{value}</div>
      <div className="card-label">{label}</div>
    </div>
  );

  if (!href) return body;

  return (
    <Link href={href} className="dashboard-card-link">
      {body}
    </Link>
  );
}

function StatusPill({ ok, children }) {
  return (
    <span className={`badge ${ok ? 'badge-success' : 'badge-warning'}`}>
      {ok ? <CheckCircle2 size={14} /> : <AlertTriangle size={14} />}
      {children}
    </span>
  );
}

function PendingItem({ title, value, description, href, tone = 'warning' }) {
  return (
    <Link href={href} className={`pending-item pending-item-${tone}`}>
      <div className="pending-item-main">
        <div className="pending-item-title">{title}</div>
        <div className="pending-item-description">{description}</div>
      </div>
      <div className="pending-item-value">{value}</div>
    </Link>
  );
}

function QuickAction({ href, icon, title, description, tone = 'primary' }) {
  return (
    <Link href={href} className={`quick-action quick-action-${tone}`}>
      <span className="quick-action-icon">{icon}</span>
      <span>
        <span className="quick-action-title">{title}</span>
        <span className="quick-action-description">{description}</span>
      </span>
    </Link>
  );
}

function Sparkline({ values = [], tone = 'success' }) {
  const width = 130;
  const height = 48;
  const normalizedValues = values.length > 0 ? values.map((value) => Number(value || 0)) : [0, 0];
  const max = Math.max(...normalizedValues, 1);
  const min = Math.min(...normalizedValues, 0);
  const range = Math.max(max - min, 1);
  const step = normalizedValues.length > 1 ? width / (normalizedValues.length - 1) : width;
  const points = normalizedValues.map((value, index) => {
    const x = index * step;
    const y = height - ((value - min) / range) * (height - 8) - 4;
    return `${x},${y}`;
  }).join(' ');
  const areaPoints = `0,${height} ${points} ${width},${height}`;

  return (
    <svg className={`overview-sparkline overview-sparkline-${tone}`} viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" aria-hidden="true">
      <polygon points={areaPoints} />
      <polyline points={points} />
    </svg>
  );
}

function OverviewCard({ title, value, badge, badgeTone = 'neutral', caption, chartData, chartTone = 'success', children }) {
  return (
    <div className="overview-card">
      <div className="overview-card-main">
        <div className="overview-card-copy">
          <div className="overview-card-title-row">
            <span className="overview-card-title">{title}</span>
            {badge && <span className={`overview-card-badge overview-card-badge-${badgeTone}`}>{badge}</span>}
          </div>
          <div className="overview-card-value">{value}</div>
          {caption && <div className="overview-card-caption">{caption}</div>}
        </div>
        <div className="overview-card-chart">
          <Sparkline values={chartData} tone={chartTone} />
        </div>
      </div>
      {children && <div className="overview-card-action">{children}</div>}
    </div>
  );
}

const initialStats = {
  tbsMasukKg: 0,
  tbsMasukRp: 0,
  jumlahTransaksi: 0,
  stokLokalKg: 0,
  hutangAktif: 0,
  jumlahPihakHutang: 0,
  totalBiaya: 0,
  kasMasuk: 0,
  kasKeluar: 0,
  tbsMitraKg: 0,
  jumlahMitraMengirim: 0,
  kwitansiBelumDibayar: 0,
  kwitansiBelumDibayarKg: 0,
  kwitansiPerluReview: 0,
  mitraPerluVerifikasi: 0,
  armadaPerluVerifikasi: 0,
};

export default function DashboardPage() {
  const [stats, setStats] = useState(initialStats);
  const [hargaAktif, setHargaAktif] = useState(null);
  const [hargaPabrik, setHargaPabrik] = useState(null);
  const [hargaPabrikEdit, setHargaPabrikEdit] = useState('');
  const [hargaPabrikEditing, setHargaPabrikEditing] = useState(false);
  const [hargaPabrikSaving, setHargaPabrikSaving] = useState(false);
  const [revenueSevenDays, setRevenueSevenDays] = useState([]);
  const [ownerRevenueRows, setOwnerRevenueRows] = useState([]);
  const [mitraSevenDays, setMitraSevenDays] = useState([]);
  const [focusMitraId, setFocusMitraId] = useState('');
  const [userRole, setUserRole] = useState('admin_operasional');
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState(null);

  const canSeeFinance = canManageFinance(userRole);
  const canSeeProfit = canViewProfit(userRole);
  const canEditBusinessSettings = canManageBusinessSettings(userRole);

  const loadDashboard = useCallback(async () => {
    setLoading(true);
    const today = getTodayISO();
    const days = getLastSevenDays();
    const firstDayWeek = days[0];

    const { data: { session } } = await supabase.auth.getSession();
    let resolvedRole = 'admin_operasional';
    if (session) {
      const { data: user } = await supabase
        .from('users')
        .select('role')
        .eq('id', session.user.id)
        .maybeSingle();
      resolvedRole = normalizeRole(user?.role);
    }

    setUserRole(resolvedRole);
    const canQueryFinance = canManageFinance(resolvedRole);
    const canQueryProfit = canViewProfit(resolvedRole);

    const [
      tbsToday,
      ownerRevenueWeek,
      mitraWeekRows,
      stokLedger,
      hutangLedger,
      biayaToday,
      harga,
      trxMitraToday,
      hargaPabrikData,
      workflowPending,
      kasToday,
    ] = await Promise.all([
      supabase
        .from('transaksi_beli_tbs')
        .select('berat_bersih_kg, total_harga')
        .eq('tanggal', today)
        .neq('status', 'dibatalkan'),
      canQueryProfit
        ? supabase
          .from('transaksi_mitra')
          .select(`
            tanggal, mitra_id, tonase, harga_harian, total_kotor,
            harga_pabrik_per_kg, fee_owner_per_kg, harga_bersih_per_kg,
            total_fee_owner, total_nilai_bersih,
            master_mitra ( fee_per_kg )
          `)
          .gte('tanggal', firstDayWeek)
          .lte('tanggal', today)
          .neq('status', 'dibatalkan')
        : Promise.resolve({ data: [], error: null }),
      supabase
        .from('transaksi_mitra')
        .select('id, mitra_id, tanggal, tonase, created_at, master_mitra(id, kode, nama, alamat)')
        .gte('tanggal', firstDayWeek)
        .lte('tanggal', today)
        .neq('status', 'dibatalkan'),
      supabase
        .from('stok_tbs_lokal_ledger')
        .select('tipe, berat_kg'),
      supabase
        .from('hutang_ledger')
        .select('pihak_type, petani_id, master_mitra_id, mitra_id, sopir_id, pihak_nama_manual, tipe, jumlah')
        .neq('status', 'dibatalkan'),
      supabase
        .from('biaya_operasional')
        .select('jumlah')
        .eq('tanggal', today)
        .neq('status', 'dibatalkan'),
      supabase
        .from('harga_tbs_lokal')
        .select('*')
        .eq('aktif', true)
        .order('berlaku_mulai', { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from('transaksi_mitra')
        .select('mitra_id, tonase')
        .eq('tanggal', today)
        .neq('status', 'dibatalkan'),
      supabase
        .from('harga_tbs')
        .select('harga_per_kg')
        .order('tanggal', { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase.rpc('get_dashboard_pending_summary'),
      canQueryFinance
        ? supabase
          .from('kas_ledger')
          .select('tipe, sumber, jumlah')
          .eq('tanggal', today)
          .neq('status', 'dibatalkan')
        : Promise.resolve({ data: [], error: null }),
    ]);

    const firstError = [
      tbsToday,
      ownerRevenueWeek,
      mitraWeekRows,
      stokLedger,
      hutangLedger,
      biayaToday,
      harga,
      trxMitraToday,
      hargaPabrikData,
      workflowPending,
      kasToday,
    ].find((result) => result?.error);

    if (firstError?.error) {
      setToast({ type: 'error', message: `Sebagian data dashboard gagal dimuat: ${firstError.error.message}` });
      setTimeout(() => setToast(null), 5000);
    }

    const todayRows = tbsToday.data || [];
    const tbsMasukKg = todayRows.reduce((sum, item) => sum + Number(item.berat_bersih_kg || 0), 0);
    const tbsMasukRp = todayRows.reduce((sum, item) => sum + Number(item.total_harga || 0), 0);
    const stokLokalKg = (stokLedger.data || []).reduce((sum, item) => sum + getSignedStok(item), 0);
    const totalBiaya = (biayaToday.data || []).reduce((sum, item) => sum + Number(item.jumlah || 0), 0);

    const transaksiMitraToday = trxMitraToday?.data || [];
    const tbsMitraKg = transaksiMitraToday.reduce((sum, item) => sum + Number(item.tonase || 0), 0);
    const uniqueMitraIds = new Set(transaksiMitraToday.map((item) => item.mitra_id).filter(Boolean));
    const jumlahMitraMengirim = uniqueMitraIds.size;

    const debtGroups = new Map();
    (hutangLedger.data || []).forEach((item) => {
      const key = getPartyKey(item);
      const current = debtGroups.get(key) || 0;
      const signed = item.tipe === 'debit' ? Number(item.jumlah || 0) : -Number(item.jumlah || 0);
      debtGroups.set(key, current + signed);
    });
    const activeDebtBalances = Array.from(debtGroups.values()).filter((saldo) => saldo > 0);

    const kasRows = kasToday.data || [];
    const kasMasuk = kasRows
      .map(getSignedKas)
      .filter((amount) => amount > 0)
      .reduce((sum, amount) => sum + amount, 0);
    const kasKeluar = kasRows
      .map(getSignedKas)
      .filter((amount) => amount < 0)
      .reduce((sum, amount) => sum + Math.abs(amount), 0);

    const pendingSummary = workflowPending.data || {};

    setStats({
      tbsMasukKg,
      tbsMasukRp,
      jumlahTransaksi: todayRows.length,
      stokLokalKg,
      hutangAktif: activeDebtBalances.reduce((sum, saldo) => sum + saldo, 0),
      jumlahPihakHutang: activeDebtBalances.length,
      totalBiaya,
      kasMasuk,
      kasKeluar,
      tbsMitraKg,
      jumlahMitraMengirim,
      kwitansiBelumDibayar: Number(pendingSummary.kwitansi_belum_dibayar || 0),
      kwitansiBelumDibayarKg: Number(pendingSummary.kwitansi_belum_dibayar_kg || 0),
      kwitansiPerluReview: Number(pendingSummary.kwitansi_perlu_review || 0),
      mitraPerluVerifikasi: Number(pendingSummary.mitra_perlu_verifikasi || 0),
      armadaPerluVerifikasi: Number(pendingSummary.armada_perlu_verifikasi || 0),
    });

    setRevenueSevenDays(days.map((date) => {
      const rows = canQueryProfit ? (ownerRevenueWeek.data || []).filter((item) => item.tanggal === date) : [];
      return {
        date,
        label: dayLabel(date),
        amount: rows.reduce((sum, item) => sum + resolveTotalFeeOwner(item), 0),
        tonase: rows.reduce((sum, item) => sum + Number(item.tonase || 0), 0),
      };
    }));
    setOwnerRevenueRows(canQueryProfit ? ownerRevenueWeek.data || [] : []);
    setMitraSevenDays(mitraWeekRows.data || []);

    setHargaAktif(harga.data || null);
    setHargaPabrik(hargaPabrikData.data || null);
    setHargaPabrikEdit(hargaPabrikData.data?.harga_per_kg ? String(hargaPabrikData.data.harga_per_kg) : '');
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadDashboard();
  }, [loadDashboard]);

  async function simpanHargaPabrik(e) {
    e.preventDefault();
    if (!canEditBusinessSettings) return;
    const nilai = Number(hargaPabrikEdit);
    if (!nilai || nilai <= 0) return;

    setHargaPabrikSaving(true);
    const today = getTodayISO();

    const { error } = await supabase.from('harga_tbs').upsert(
      { tanggal: today, harga_per_kg: nilai },
      { onConflict: 'tanggal' }
    );

    if (error) {
      setToast({ type: 'error', message: `Gagal menyimpan harga pabrik: ${error.message}` });
    } else {
      setToast({ type: 'success', message: 'Harga Pabrik (TWB) berhasil diperbarui.' });
      setHargaPabrikEditing(false);
      await loadDashboard();
    }
    setHargaPabrikSaving(false);
  }

  const today = getTodayISO();
  const ownerRevenueToday = revenueSevenDays.find((item) => item.date === today)?.amount || 0;
  const mitraVolumeSevenDays = useMemo(() => (
    getLastSevenDays().map((date) => {
      const rows = mitraSevenDays.filter((item) => item.tanggal === date);
      return {
        date,
        label: dayLabel(date),
        tonase: rows.reduce((sum, item) => sum + Number(item.tonase || 0), 0),
      };
    })
  ), [mitraSevenDays]);
  const mitraVolumeSparkData = mitraVolumeSevenDays.map((item) => item.tonase);
  const focusMitraGroups = useMemo(() => {
    const groups = new Map();

    mitraSevenDays.forEach((row) => {
      const key = row.mitra_id || 'tanpa-mitra';
      const current = groups.get(key) || {
        mitraId: key,
        label: row.master_mitra?.kode || row.master_mitra?.nama || 'Tanpa mitra',
        subtitle: row.master_mitra?.alamat || row.master_mitra?.nama || '',
        tonase: 0,
        transaksi: 0,
      };

      current.tonase += Number(row.tonase || 0);
      current.transaksi += 1;
      groups.set(key, current);
    });

    return Array.from(groups.values())
      .sort((a, b) => b.tonase - a.tonase)
      .slice(0, 6);
  }, [mitraSevenDays]);
  const selectedFocusMitraId = focusMitraGroups.some((item) => item.mitraId === focusMitraId)
    ? focusMitraId
    : focusMitraGroups[0]?.mitraId;
  const activeMitraGroup = focusMitraGroups.find((item) => item.mitraId === selectedFocusMitraId);
  const focusMitraTrend = useMemo(() => {
    const activeId = activeMitraGroup?.mitraId;
    if (!activeId) return [];

    return getLastSevenDays().map((date) => {
      const volumeRows = mitraSevenDays.filter((item) => item.tanggal === date && (item.mitra_id || 'tanpa-mitra') === activeId);
      const profitRows = ownerRevenueRows.filter((item) => item.tanggal === date && (item.mitra_id || 'tanpa-mitra') === activeId);

      return {
        date,
        label: dayLabel(date),
        tonase: volumeRows.reduce((sum, item) => sum + Number(item.tonase || 0), 0),
        revenue: canSeeProfit ? profitRows.reduce((sum, item) => sum + resolveTotalFeeOwner(item), 0) : 0,
      };
    });
  }, [activeMitraGroup, canSeeProfit, mitraSevenDays, ownerRevenueRows]);
  const focusChartValues = focusMitraTrend.map((item) => (canSeeProfit ? item.revenue : item.tonase));
  const maxFocusChartValue = Math.max(...focusChartValues, 1);
  const focusTotalTonase = focusMitraTrend.reduce((sum, item) => sum + item.tonase, 0);
  const focusTotalRevenue = focusMitraTrend.reduce((sum, item) => sum + item.revenue, 0);

  const pendingItems = useMemo(() => {
    const items = [];

    if (!hargaPabrik) {
      items.push({
        title: 'Harga Pabrik / TWB',
        value: 'Belum diset',
        description: 'Set harga pabrik sebelum input pengiriman mitra hari ini.',
        href: '/dashboard',
        tone: 'warning',
      });
    }

    if (stats.kwitansiBelumDibayar > 0) {
      items.push({
        title: 'Kwitansi Mitra Belum Dibayar',
        value: stats.kwitansiBelumDibayar,
        description: `${formatNumber(stats.kwitansiBelumDibayarKg)} kg transaksi mitra belum masuk batch pembayaran.`,
        href: '/owner/kwitansi-mitra',
        tone: 'warning',
      });
    }

    if (stats.kwitansiPerluReview > 0) {
      items.push({
        title: 'Kwitansi Perlu Review',
        value: stats.kwitansiPerluReview,
        description: 'Batch pembayaran yang perlu dicek ulang karena koreksi/perubahan data.',
        href: '/owner/kwitansi-mitra',
        tone: 'danger',
      });
    }

    if (stats.mitraPerluVerifikasi > 0) {
      items.push({
        title: 'Mitra Perlu Verifikasi',
        value: stats.mitraPerluVerifikasi,
        description: 'Periksa data mitra baru atau hasil koreksi Admin.',
        href: '/owner/master-data',
        tone: 'warning',
      });
    }

    if (stats.armadaPerluVerifikasi > 0) {
      items.push({
        title: 'Sopir/Armada Perlu Verifikasi',
        value: stats.armadaPerluVerifikasi,
        description: 'Periksa plat, sopir tetap, afiliasi, dan status Armada CB.',
        href: '/master/armada',
        tone: 'warning',
      });
    }

    if (stats.jumlahPihakHutang > 0) {
      items.push({
        title: 'Sisa Hutang/Panjar',
        value: stats.jumlahPihakHutang,
        description: `${formatRupiah(stats.hutangAktif)} masih harus dipotong atau dilunasi.`,
        href: '/keuangan/hutang',
        tone: 'warning',
      });
    }

    return items;
  }, [hargaPabrik, stats]);

  return (
    <AppShell title="Dashboard Hari Ini" subtitle="Kontrol operasional, kas, dan pending review">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <div>
          <p className="page-description">{formatDateDisplay(today)} - ringkasan kerja harian RAM Sawit CB.</p>
        </div>
        <div className="dashboard-status-row">
          <StatusPill ok={Boolean(hargaPabrik)}>Harga Pabrik</StatusPill>
          <StatusPill ok={stats.kwitansiPerluReview === 0}>Review</StatusPill>
        </div>
      </div>

      <section className="dashboard-section dashboard-overview-section">
        <div className="overview-strip">
          <OverviewCard
            title="Harga Pabrik / TWB"
            value={hargaPabrik ? `${formatRupiah(hargaPabrik.harga_per_kg)}/kg` : '-'}
            badge={hargaPabrik ? 'Siap' : 'Belum diset'}
            badgeTone={hargaPabrik ? 'success' : 'warning'}
            caption="Snapshot utama pengiriman mitra"
            chartData={mitraVolumeSparkData}
            chartTone={hargaPabrik ? 'success' : 'warning'}
          >
            {canEditBusinessSettings && hargaPabrikEditing ? (
              <form onSubmit={simpanHargaPabrik} className="overview-edit-form">
                <input
                  type="number"
                  className="form-input form-input-mono"
                  value={hargaPabrikEdit}
                  onChange={(event) => setHargaPabrikEdit(event.target.value)}
                  min={0}
                  step={1}
                  required
                  autoFocus
                />
                <button type="submit" className="btn btn-primary btn-sm" disabled={hargaPabrikSaving}>
                  {hargaPabrikSaving ? 'Menyimpan' : 'Simpan'}
                </button>
                <button type="button" className="btn btn-ghost btn-sm" onClick={() => setHargaPabrikEditing(false)}>
                  Batal
                </button>
              </form>
            ) : canEditBusinessSettings ? (
              <button className="btn btn-outline btn-sm" onClick={() => setHargaPabrikEditing(true)}>
                {hargaPabrik ? 'Ubah' : 'Set Harga'}
              </button>
            ) : null}
          </OverviewCard>

          <OverviewCard
            title="Pengiriman Mitra"
            value={<>{formatNumber(stats.tbsMitraKg)} kg</>}
            badge={`${stats.jumlahMitraMengirim} mitra`}
            badgeTone={stats.jumlahMitraMengirim > 0 ? 'success' : 'neutral'}
            caption="Tonase masuk hari ini"
            chartData={mitraVolumeSparkData}
            chartTone="success"
          >
            <Link className="overview-card-link" href="/admin/input-timbangan">Input Pengiriman</Link>
          </OverviewCard>

          <OverviewCard
            title="Pendapatan Owner"
            value={canSeeProfit ? formatRupiah(ownerRevenueToday) : 'Terbatas'}
            badge="Owner"
            badgeTone={canSeeProfit ? 'success' : 'neutral'}
            caption="Estimasi fee owner dari pengiriman mitra"
            chartData={canSeeProfit ? revenueSevenDays.map((item) => item.amount) : []}
            chartTone="success"
          >
            {canSeeProfit ? (
              <Link className="overview-card-link" href="/owner/pendapatan-owner">Lihat Detail</Link>
            ) : (
              <span className="overview-card-muted">Owner/Super Admin</span>
            )}
          </OverviewCard>

          <OverviewCard
            title="Kwitansi Pending"
            value={stats.kwitansiBelumDibayar}
            badge={stats.kwitansiPerluReview > 0 ? `${stats.kwitansiPerluReview} review` : 'Terkontrol'}
            badgeTone={stats.kwitansiPerluReview > 0 ? 'danger' : stats.kwitansiBelumDibayar > 0 ? 'warning' : 'success'}
            caption={`${formatNumber(stats.kwitansiBelumDibayarKg)} kg belum masuk batch`}
            chartData={[stats.kwitansiBelumDibayarKg, stats.kwitansiBelumDibayar, stats.kwitansiPerluReview, stats.jumlahPihakHutang]}
            chartTone={stats.kwitansiPerluReview > 0 ? 'danger' : 'warning'}
          >
            <Link className="overview-card-link" href="/owner/kwitansi-mitra">Buka Kwitansi</Link>
          </OverviewCard>
        </div>
      </section>

      <section className="dashboard-section">
        <div className="section-heading">
          <div>
            <h2>Fokus Mitra</h2>
            <p>Daftar mitra paling aktif dan grafik 7 hari untuk membaca ritme pengiriman.</p>
          </div>
        </div>

        <div className="stock-style-focus">
          <div className="card dashboard-card focus-list-panel">
            <div className="focus-panel-title">Mitra 7 Hari Terakhir</div>
            <div className="focus-mitra-list">
              {focusMitraGroups.length === 0 && (
                <div className="empty-compact">Belum ada pengiriman mitra dalam 7 hari terakhir.</div>
              )}
              {focusMitraGroups.map((mitra) => (
                <button
                  key={mitra.mitraId}
                  type="button"
                  className={`focus-mitra-row ${activeMitraGroup?.mitraId === mitra.mitraId ? 'active' : ''}`}
                  onClick={() => setFocusMitraId(mitra.mitraId)}
                >
                  <span>
                    <strong>{mitra.label}</strong>
                    <small>{mitra.subtitle || `${mitra.transaksi} transaksi`}</small>
                  </span>
                  <span className="focus-mitra-row-stat">
                    <b>{formatNumber(mitra.tonase)} kg</b>
                    <small>{mitra.transaksi} transaksi</small>
                  </span>
                </button>
              ))}
            </div>
          </div>

          <div className="card dashboard-card focus-detail-panel">
            {activeMitraGroup ? (
              <>
                <div className="focus-detail-header">
                  <div>
                    <div className="focus-detail-label">Mitra aktif</div>
                    <h2>{activeMitraGroup.label}</h2>
                    <p>{activeMitraGroup.subtitle || 'Pengiriman mitra 7 hari terakhir'}</p>
                  </div>
                  <div className="focus-detail-actions">
                    <Link className="btn btn-outline btn-sm" href="/owner/laporan-mitra">Laporan Mitra</Link>
                    <Link className="btn btn-primary btn-sm" href="/owner/kwitansi-mitra">Kwitansi</Link>
                  </div>
                </div>

                <div className="focus-detail-stats">
                  <div>
                    <span>Total Tonase</span>
                    <strong>{formatNumber(focusTotalTonase)} kg</strong>
                  </div>
                  <div>
                    <span>Transaksi</span>
                    <strong>{activeMitraGroup.transaksi}</strong>
                  </div>
                  <div>
                    <span>Pendapatan Owner</span>
                    <strong>{canSeeProfit ? formatRupiah(focusTotalRevenue) : 'Terbatas'}</strong>
                  </div>
                </div>

                <div className="focus-chart">
                  {focusMitraTrend.map((item) => {
                    const value = canSeeProfit ? item.revenue : item.tonase;
                    return (
                      <div className="focus-chart-bar" key={item.date}>
                        <div
                          title={canSeeProfit ? `${formatRupiah(item.revenue)} / ${formatNumber(item.tonase)} kg` : `${formatNumber(item.tonase)} kg`}
                          style={{ height: Math.max(8, (value / maxFocusChartValue) * 160) }}
                        />
                        <span>{item.label}</span>
                        <strong>{canSeeProfit ? formatCompactRupiah(item.revenue) : formatNumber(item.tonase)}</strong>
                      </div>
                    );
                  })}
                </div>
              </>
            ) : (
              <div className="empty-compact">Belum ada data mitra untuk ditampilkan.</div>
            )}
          </div>
        </div>
      </section>

      <section className="dashboard-section">
        <div className="section-heading">
          <div>
            <h2>Data Pendukung</h2>
            <p>Informasi yang belum terwakili di ringkasan atas: modul lokal, kas, biaya, dan panjar.</p>
          </div>
        </div>

        <div className="stats-grid dashboard-metrics support-metrics">
          <MetricCard
            title="Pembelian Petani"
            value={<>{formatNumber(stats.tbsMasukKg)} <span>kg</span></>}
            label={`Coming Soon - ${formatRupiah(stats.tbsMasukRp)} / ${stats.jumlahTransaksi} transaksi`}
            icon={<Scale size={20} />}
            href="/transaksi/beli"
            tone="info"
          />
          <MetricCard
            title="Stok Lokal"
            value={<>{formatNumber(stats.stokLokalKg)} <span>kg</span></>}
            label="Coming Soon - saldo ledger hanya konteks"
            icon={<Box size={20} />}
            href="/laporan/stok"
            tone={stats.stokLokalKg < 0 ? 'danger' : 'neutral'}
          />
          <MetricCard
            title="Kas Masuk Hari Ini"
            value={canSeeFinance ? formatRupiah(stats.kasMasuk) : 'Terbatas'}
            label={canSeeFinance ? 'Dari buku kas aktual' : 'Hanya Admin Keuangan, Owner, dan Super Admin'}
            icon={<BadgeDollarSign size={20} />}
            href="/keuangan/kas"
            tone="success"
          />
          <MetricCard
            title="Kas Keluar Hari Ini"
            value={canSeeFinance ? formatRupiah(stats.kasKeluar) : 'Terbatas'}
            label={canSeeFinance ? 'Pembelian, biaya, panjar, dan pembayaran' : 'Data kas disembunyikan dari role ini'}
            icon={<CreditCard size={20} />}
            href="/keuangan/kas"
            tone="danger"
          />
          <MetricCard
            title="Biaya Operasional"
            value={formatRupiah(stats.totalBiaya)}
            label="Pengeluaran operasional tanggal ini"
            icon={<Wallet size={20} />}
            href="/keuangan/biaya"
            tone="danger"
          />
          <MetricCard
            title="Sisa Hutang/Panjar"
            value={formatRupiah(stats.hutangAktif)}
            label={`${stats.jumlahPihakHutang} pihak masih harus dipantau`}
            icon={<Clock3 size={20} />}
            href="/keuangan/hutang"
            tone={stats.jumlahPihakHutang > 0 ? 'warning' : 'success'}
          />
        </div>
      </section>

      <section className="dashboard-section dashboard-two-col">
        <div className="card dashboard-card">
          <div className="section-heading compact">
            <div>
              <h2>Pending Review</h2>
              <p>Daftar hal yang perlu dibereskan sebelum akhir operasional.</p>
            </div>
          </div>
          <div className="pending-list">
            {pendingItems.length > 0 ? (
              pendingItems.map((item) => (
                <PendingItem key={item.title} {...item} />
              ))
            ) : (
              <div className="empty-compact">Tidak ada pending utama untuk ditindaklanjuti.</div>
            )}
          </div>
        </div>

        <div className="card dashboard-card">
          <div className="section-heading compact">
            <div>
              <h2>Aksi Cepat</h2>
              <p>Jalur kerja yang paling sering dipakai hari ini.</p>
            </div>
          </div>
          <div className="quick-action-grid">
            <QuickAction href="/admin/input-timbangan" icon={<Truck size={20} />} title="Pengiriman Mitra" description="Input armada mitra masuk" />
            <QuickAction href="/transaksi/beli" icon={<Store size={20} />} title="Pembelian Petani" description="Coming Soon - hanya lihat konteks" />
            <QuickAction href="/owner/kwitansi-mitra" icon={<ReceiptText size={20} />} title="Kwitansi Mitra" description="Cetak, bayar, kirim WA" />
            {canSeeFinance && (
              <QuickAction href="/owner/pembayaran-pabrik" icon={<BadgeDollarSign size={20} />} title="Pembayaran Pabrik" description="Catat uang masuk pabrik" />
            )}
            <QuickAction href="/keuangan/hutang" icon={<Wallet size={20} />} title="Hutang & Panjar" description="Catat kasbon dan pelunasan" tone="gold" />
            <QuickAction href="/owner/laporan-mitra" icon={<FileText size={20} />} title="Laporan Mitra" description="Rekap dan status bayar mitra" tone="outline" />
          </div>
        </div>
      </section>

      <style jsx global>{`
        .dashboard-section {
          margin-bottom: var(--space-xl);
        }

        .section-heading {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: var(--space-md);
          margin-bottom: var(--space-md);
        }

        .section-heading.compact {
          margin-bottom: var(--space-lg);
        }

        .section-heading h2 {
          margin: 0;
          color: var(--text-primary);
          font-size: var(--text-lg);
          font-weight: 800;
        }

        .section-heading p {
          margin: 4px 0 0;
          color: var(--text-tertiary);
          font-size: var(--text-sm);
        }

        .dashboard-status-row {
          display: flex;
          gap: var(--space-sm);
          flex-wrap: wrap;
          justify-content: flex-end;
        }

        .dashboard-card-link {
          display: block;
          color: inherit;
          text-decoration: none;
        }

        .dashboard-card:hover {
          transform: none;
          border-color: var(--border-hover);
          box-shadow: var(--shadow-md);
        }

        .dashboard-card .card-value span {
          font-size: var(--text-base);
          font-weight: 500;
        }

        .dashboard-two-col {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: var(--space-lg);
        }

        .overview-strip {
          display: grid;
          grid-template-columns: repeat(4, minmax(240px, 1fr));
          gap: var(--space-md);
          overflow-x: auto;
          padding-bottom: 2px;
        }

        .overview-card {
          min-width: 240px;
          padding: 18px;
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          background: rgba(15, 23, 42, 0.5);
        }

        .overview-card-main {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--space-lg);
          min-height: 78px;
        }

        .overview-card-copy {
          min-width: 0;
        }

        .overview-card-title-row {
          display: flex;
          align-items: center;
          gap: 8px;
          flex-wrap: wrap;
          margin-bottom: 7px;
        }

        .overview-card-title {
          color: var(--text-tertiary);
          font-size: var(--text-sm);
          font-weight: 800;
          white-space: nowrap;
        }

        .overview-card-badge {
          display: inline-flex;
          align-items: center;
          min-height: 22px;
          padding: 2px 8px;
          border: 1px solid var(--border-default);
          border-radius: var(--radius-sm);
          font-size: var(--text-xs);
          font-weight: 800;
          line-height: 1;
        }

        .overview-card-badge-success {
          color: var(--color-success);
          border-color: rgba(46, 204, 113, 0.35);
          background: rgba(46, 204, 113, 0.08);
        }

        .overview-card-badge-warning {
          color: var(--color-warning);
          border-color: rgba(240, 165, 0, 0.35);
          background: rgba(240, 165, 0, 0.08);
        }

        .overview-card-badge-danger {
          color: var(--color-danger);
          border-color: rgba(231, 76, 60, 0.35);
          background: rgba(231, 76, 60, 0.08);
        }

        .overview-card-badge-neutral {
          color: var(--text-tertiary);
          background: rgba(148, 163, 184, 0.08);
        }

        .overview-card-value {
          font-family: var(--font-mono);
          color: var(--text-primary);
          font-size: var(--text-xl);
          font-weight: 900;
          line-height: 1.1;
        }

        .overview-card-caption {
          margin-top: 7px;
          color: var(--text-tertiary);
          font-size: var(--text-xs);
          line-height: 1.35;
        }

        .overview-card-chart {
          width: 112px;
          height: 46px;
          flex: 0 0 112px;
        }

        .overview-sparkline {
          width: 100%;
          height: 100%;
          overflow: visible;
        }

        .overview-sparkline polygon {
          fill: rgba(46, 204, 113, 0.12);
        }

        .overview-sparkline polyline {
          fill: none;
          stroke: var(--color-success);
          stroke-width: 3;
          stroke-linecap: round;
          stroke-linejoin: round;
        }

        .overview-sparkline-warning polygon {
          fill: rgba(240, 165, 0, 0.1);
        }

        .overview-sparkline-warning polyline {
          stroke: var(--color-warning);
        }

        .overview-sparkline-danger polygon {
          fill: rgba(231, 76, 60, 0.1);
        }

        .overview-sparkline-danger polyline {
          stroke: var(--color-danger);
        }

        .overview-sparkline-neutral polygon {
          fill: rgba(148, 163, 184, 0.1);
        }

        .overview-sparkline-neutral polyline {
          stroke: var(--text-tertiary);
        }

        .overview-card-action {
          margin-top: 14px;
        }

        .overview-card-link,
        .overview-card-muted {
          color: var(--color-primary-400);
          font-size: var(--text-xs);
          font-weight: 800;
          text-decoration: none;
        }

        .overview-card-muted {
          color: var(--text-tertiary);
        }

        .overview-edit-form {
          display: flex;
          gap: 8px;
          flex-wrap: wrap;
        }

        .overview-edit-form input {
          min-width: 120px;
          flex: 1 1 120px;
          height: 34px;
          font-size: var(--text-sm);
        }

        .stock-style-focus {
          display: grid;
          grid-template-columns: minmax(280px, 0.8fr) minmax(0, 1.7fr);
          gap: var(--space-lg);
          align-items: stretch;
        }

        .focus-list-panel,
        .focus-detail-panel {
          min-height: 360px;
        }

        .focus-panel-title {
          margin-bottom: var(--space-md);
          color: var(--text-secondary);
          font-size: var(--text-xs);
          font-weight: 900;
          text-transform: uppercase;
        }

        .focus-mitra-list {
          display: flex;
          flex-direction: column;
          gap: 10px;
        }

        .focus-mitra-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--space-md);
          width: 100%;
          min-height: 78px;
          padding: 12px 14px;
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          background: rgba(15, 23, 42, 0.38);
          color: var(--text-primary);
          text-align: left;
          cursor: pointer;
        }

        .focus-mitra-row.active {
          border-color: var(--color-primary-400);
          background: rgba(59, 171, 113, 0.1);
          box-shadow: inset 3px 0 0 var(--color-primary-400);
        }

        .focus-mitra-row strong,
        .focus-mitra-row small {
          display: block;
          min-width: 0;
        }

        .focus-mitra-row strong {
          font-size: var(--text-sm);
          font-weight: 900;
        }

        .focus-mitra-row small {
          margin-top: 4px;
          color: var(--text-tertiary);
          font-size: var(--text-xs);
          line-height: 1.3;
        }

        .focus-mitra-row-stat {
          flex: 0 0 auto;
          text-align: right;
        }

        .focus-mitra-row-stat b {
          display: block;
          font-family: var(--font-mono);
          font-size: var(--text-sm);
        }

        .focus-detail-panel {
          display: flex;
          flex-direction: column;
          gap: var(--space-lg);
        }

        .focus-detail-header {
          display: flex;
          justify-content: space-between;
          gap: var(--space-lg);
          align-items: flex-start;
        }

        .focus-detail-label {
          color: var(--color-primary-400);
          font-size: var(--text-xs);
          font-weight: 900;
          text-transform: uppercase;
        }

        .focus-detail-header h2 {
          margin: 5px 0 0;
          color: var(--text-primary);
          font-size: var(--text-2xl);
          font-weight: 900;
        }

        .focus-detail-header p {
          margin: 5px 0 0;
          color: var(--text-tertiary);
          font-size: var(--text-sm);
        }

        .focus-detail-actions {
          display: flex;
          gap: 8px;
          flex-wrap: wrap;
          justify-content: flex-end;
        }

        .focus-detail-stats {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          gap: var(--space-sm);
        }

        .focus-detail-stats div {
          padding: 12px;
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          background: rgba(15, 23, 42, 0.32);
        }

        .focus-detail-stats span,
        .focus-detail-stats strong {
          display: block;
        }

        .focus-detail-stats span {
          color: var(--text-tertiary);
          font-size: var(--text-xs);
        }

        .focus-detail-stats strong {
          margin-top: 5px;
          color: var(--text-primary);
          font-family: var(--font-mono);
          font-size: var(--text-base);
          font-weight: 900;
        }

        .focus-chart {
          display: grid;
          grid-template-columns: repeat(7, 1fr);
          gap: 12px;
          align-items: end;
          min-height: 220px;
          padding-top: var(--space-md);
          border-top: 1px solid var(--border-default);
        }

        .focus-chart-bar {
          display: flex;
          min-width: 0;
          flex-direction: column;
          justify-content: flex-end;
          gap: 8px;
        }

        .focus-chart-bar div {
          border-radius: var(--radius-sm);
          background: linear-gradient(180deg, var(--color-primary-400), var(--color-primary-800));
        }

        .focus-chart-bar span,
        .focus-chart-bar strong {
          text-align: center;
          font-size: var(--text-xs);
        }

        .focus-chart-bar span {
          color: var(--text-tertiary);
        }

        .focus-chart-bar strong {
          color: var(--text-secondary);
          font-family: var(--font-mono);
          font-weight: 800;
        }

        .dashboard-metrics {
          grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
          margin-bottom: var(--space-lg);
        }

        .support-metrics {
          margin-bottom: 0;
        }

        .pending-list,
        .quick-action-grid {
          display: flex;
          flex-direction: column;
          gap: var(--space-sm);
        }

        .pending-item {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--space-md);
          padding: 12px 14px;
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          background: rgba(15, 23, 42, 0.38);
          color: var(--text-primary);
          text-decoration: none;
        }

        .pending-item:hover {
          border-color: var(--border-hover);
          background: var(--bg-card-hover);
        }

        .pending-item-warning .pending-item-value {
          color: var(--color-warning);
        }

        .pending-item-danger .pending-item-value {
          color: var(--color-danger);
        }

        .pending-item-success .pending-item-value {
          color: var(--color-success);
        }

        .pending-item-title {
          font-weight: 800;
          font-size: var(--text-sm);
        }

        .pending-item-description {
          margin-top: 3px;
          color: var(--text-tertiary);
          font-size: var(--text-xs);
          line-height: 1.4;
        }

        .pending-item-value {
          flex: 0 0 auto;
          font-family: var(--font-mono);
          font-weight: 900;
          font-size: var(--text-lg);
          text-align: right;
        }

        .quick-action-grid {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }

        .quick-action {
          display: flex;
          align-items: center;
          gap: var(--space-md);
          min-height: 76px;
          padding: 12px;
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          background: rgba(15, 23, 42, 0.38);
          color: var(--text-primary);
          text-decoration: none;
        }

        .quick-action:hover {
          border-color: var(--color-primary-400);
          background: rgba(59, 171, 113, 0.1);
        }

        .quick-action-gold:hover {
          border-color: var(--color-gold-500);
          background: rgba(240, 165, 0, 0.1);
        }

        .quick-action-outline:hover {
          border-color: var(--border-hover);
          background: var(--bg-card-hover);
        }

        .quick-action-icon {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 38px;
          height: 38px;
          flex: 0 0 38px;
          border-radius: var(--radius-md);
          color: var(--color-primary-400);
          background: rgba(59, 171, 113, 0.12);
        }

        .quick-action-title,
        .quick-action-description {
          display: block;
        }

        .quick-action-title {
          font-weight: 800;
          font-size: var(--text-sm);
        }

        .quick-action-description {
          margin-top: 2px;
          color: var(--text-tertiary);
          font-size: var(--text-xs);
          line-height: 1.35;
        }

        .empty-compact {
          padding: 18px 0;
          color: var(--text-tertiary);
          font-size: var(--text-sm);
        }

        @media (max-width: 1180px) {
          .overview-strip {
            grid-template-columns: repeat(2, minmax(0, 1fr));
            overflow-x: visible;
          }

          .stock-style-focus {
            grid-template-columns: 1fr;
          }

          .focus-list-panel,
          .focus-detail-panel {
            min-height: auto;
          }
        }

        @media (max-width: 900px) {
          .dashboard-two-col {
            grid-template-columns: 1fr;
          }

          .quick-action-grid {
            grid-template-columns: 1fr;
          }

          .focus-detail-header {
            flex-direction: column;
          }

          .focus-detail-actions {
            justify-content: flex-start;
          }
        }

        @media (max-width: 560px) {
          .dashboard-status-row {
            justify-content: flex-start;
          }

          .overview-strip {
            grid-template-columns: 1fr;
          }

          .overview-card-main {
            align-items: flex-start;
          }

          .overview-card-chart {
            width: 96px;
            flex-basis: 96px;
          }

          .focus-mitra-row {
            align-items: flex-start;
            flex-direction: column;
          }

          .focus-mitra-row-stat {
            text-align: left;
          }

          .focus-detail-stats {
            grid-template-columns: 1fr;
          }

          .focus-chart {
            gap: 7px;
            min-height: 190px;
          }

          .focus-chart-bar strong {
            font-size: 10px;
          }

          .pending-item {
            align-items: flex-start;
            flex-direction: column;
          }

          .pending-item-value {
            text-align: left;
          }
        }
      `}</style>
    </AppShell>
  );
}
