'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import AppShell from '@/components/layout/AppShell';
import { canManageFinance, normalizeRole } from '@/lib/roles';
import { supabase } from '@/lib/supabase';
import { formatDateDisplay, formatNumber, formatRupiah, getTodayISO } from '@/lib/utils';
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
  Users,
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
  totalMitra: 0,
  kwitansiBelumDibayar: 0,
  kwitansiBelumDibayarKg: 0,
  kwitansiPerluReview: 0,
};

export default function DashboardPage() {
  const [stats, setStats] = useState(initialStats);
  const [hargaAktif, setHargaAktif] = useState(null);
  const [hargaEdit, setHargaEdit] = useState('');
  const [hargaEditing, setHargaEditing] = useState(false);
  const [hargaSaving, setHargaSaving] = useState(false);
  const [hargaPabrik, setHargaPabrik] = useState(null);
  const [hargaPabrikEdit, setHargaPabrikEdit] = useState('');
  const [hargaPabrikEditing, setHargaPabrikEditing] = useState(false);
  const [hargaPabrikSaving, setHargaPabrikSaving] = useState(false);
  const [tbsSevenDays, setTbsSevenDays] = useState([]);
  const [recentTransactions, setRecentTransactions] = useState([]);
  const [recentMitra, setRecentMitra] = useState([]);
  const [userRole, setUserRole] = useState('admin_operasional');
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState(null);

  const canSeeFinance = canManageFinance(userRole);

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

    const [
      tbsToday,
      tbsWeek,
      stokLedger,
      hutangLedger,
      biayaToday,
      recentLocal,
      recentMitraRows,
      harga,
      trxMitraToday,
      masterMitra,
      hargaPabrikData,
      transaksiMitraOpen,
      paidMitraItems,
      kwitansiReview,
      kasToday,
    ] = await Promise.all([
      supabase
        .from('transaksi_beli_tbs')
        .select('berat_bersih_kg, total_harga')
        .eq('tanggal', today)
        .neq('status', 'dibatalkan'),
      supabase
        .from('transaksi_beli_tbs')
        .select('tanggal, berat_bersih_kg, total_harga')
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
        .from('transaksi_beli_tbs')
        .select('id, no_struk, petani:petani_id(nama), berat_bersih_kg, total_harga, created_at')
        .neq('status', 'dibatalkan')
        .order('created_at', { ascending: false })
        .limit(8),
      supabase
        .from('transaksi_mitra')
        .select('id, tanggal, tonase, total_nilai_bersih, created_at, master_mitra(id, kode, nama, alamat)')
        .neq('status', 'dibatalkan')
        .order('created_at', { ascending: false })
        .limit(8),
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
        .from('master_mitra')
        .select('id', { count: 'exact', head: true })
        .eq('aktif', true),
      supabase
        .from('harga_tbs')
        .select('harga_per_kg')
        .order('tanggal', { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from('transaksi_mitra')
        .select('id, mitra_id, tonase')
        .neq('status', 'dibatalkan')
        .limit(1500),
      supabase
        .from('pembayaran_mitra_kwitansi_item')
        .select('transaksi_mitra_id')
        .limit(3000),
      supabase
        .from('pembayaran_mitra_kwitansi')
        .select('id', { count: 'exact', head: true })
        .eq('status', 'perlu_review'),
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
      tbsWeek,
      stokLedger,
      hutangLedger,
      biayaToday,
      recentLocal,
      recentMitraRows,
      harga,
      trxMitraToday,
      masterMitra,
      hargaPabrikData,
      transaksiMitraOpen,
      paidMitraItems,
      kwitansiReview,
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
    const totalMitra = masterMitra?.count || 0;

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

    const paidIds = new Set((paidMitraItems.data || []).map((item) => item.transaksi_mitra_id));
    const unpaidMitra = new Map();
    let kwitansiBelumDibayarKg = 0;
    (transaksiMitraOpen.data || []).forEach((item) => {
      if (paidIds.has(item.id)) return;
      kwitansiBelumDibayarKg += Number(item.tonase || 0);
      if (item.mitra_id) unpaidMitra.set(item.mitra_id, true);
    });

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
      totalMitra,
      kwitansiBelumDibayar: unpaidMitra.size,
      kwitansiBelumDibayarKg,
      kwitansiPerluReview: kwitansiReview.count || 0,
    });

    setTbsSevenDays(days.map((date) => {
      const rows = (tbsWeek.data || []).filter((item) => item.tanggal === date);
      return {
        date,
        label: dayLabel(date),
        kg: rows.reduce((sum, item) => sum + Number(item.berat_bersih_kg || 0), 0),
        rp: rows.reduce((sum, item) => sum + Number(item.total_harga || 0), 0),
      };
    }));

    setRecentTransactions(recentLocal.data || []);
    setRecentMitra(recentMitraRows.data || []);
    setHargaAktif(harga.data || null);
    setHargaEdit(harga.data?.harga_per_kg ? String(harga.data.harga_per_kg) : '');
    setHargaPabrik(hargaPabrikData.data || null);
    setHargaPabrikEdit(hargaPabrikData.data?.harga_per_kg ? String(hargaPabrikData.data.harga_per_kg) : '');
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadDashboard();
  }, [loadDashboard]);

  async function simpanHarga(e) {
    e.preventDefault();
    const nilai = Number(hargaEdit);
    if (!nilai || nilai <= 0) return;

    setHargaSaving(true);
    const { error } = await supabase.rpc('set_harga_tbs_lokal', {
      p_harga_per_kg: nilai,
      p_alasan_override: 'Diubah dari dashboard',
    });

    if (error) {
      setToast({ type: 'error', message: `Gagal menyimpan harga: ${error.message}` });
      setHargaSaving(false);
      return;
    }

    setToast({ type: 'success', message: 'Harga TBS lokal berhasil diperbarui.' });
    setHargaEditing(false);
    await loadDashboard();
    setHargaSaving(false);
  }

  async function simpanHargaPabrik(e) {
    e.preventDefault();
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

  const maxTbs = Math.max(...tbsSevenDays.map((item) => item.kg), 1);
  const today = getTodayISO();
  const pendingItems = useMemo(() => ([
    {
      title: 'Harga Pabrik / TWB',
      value: hargaPabrik ? 'Siap' : 'Belum diset',
      description: hargaPabrik
        ? `${formatRupiah(hargaPabrik.harga_per_kg)}/kg dipakai untuk pengiriman mitra.`
        : 'Set harga pabrik sebelum input pengiriman mitra hari ini.',
      href: '/dashboard',
      tone: hargaPabrik ? 'success' : 'warning',
    },
    {
      title: 'Harga Beli Petani',
      value: hargaAktif ? 'Siap' : 'Belum diset',
      description: hargaAktif
        ? `${formatRupiah(hargaAktif.harga_per_kg)}/kg dipakai untuk pembelian petani lokal.`
        : 'Pembelian TBS lokal terkunci sampai harga aktif tersedia.',
      href: '/master/harga',
      tone: hargaAktif ? 'success' : 'warning',
    },
    {
      title: 'Kwitansi Mitra Belum Dibayar',
      value: stats.kwitansiBelumDibayar,
      description: `${formatNumber(stats.kwitansiBelumDibayarKg)} kg transaksi mitra belum masuk batch pembayaran.`,
      href: '/owner/kwitansi-mitra',
      tone: stats.kwitansiBelumDibayar > 0 ? 'warning' : 'success',
    },
    {
      title: 'Kwitansi Perlu Review',
      value: stats.kwitansiPerluReview,
      description: 'Batch pembayaran yang perlu dicek ulang karena koreksi/perubahan data.',
      href: '/owner/kwitansi-mitra',
      tone: stats.kwitansiPerluReview > 0 ? 'danger' : 'success',
    },
    {
      title: 'Sisa Hutang/Panjar',
      value: stats.jumlahPihakHutang,
      description: `${formatRupiah(stats.hutangAktif)} masih harus dipotong atau dilunasi.`,
      href: '/keuangan/hutang',
      tone: stats.jumlahPihakHutang > 0 ? 'warning' : 'success',
    },
  ]), [hargaAktif, hargaPabrik, stats]);

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
          <StatusPill ok={Boolean(hargaAktif)}>Harga Petani</StatusPill>
          <StatusPill ok={stats.kwitansiPerluReview === 0}>Review</StatusPill>
        </div>
      </div>

      <section className="dashboard-section">
        <div className="section-heading">
          <div>
            <h2>Harga Aktif</h2>
            <p>Harga ini menjadi snapshot transaksi, jadi wajib dicek sebelum input.</p>
          </div>
        </div>

        <div className="price-grid">
          <div className="card dashboard-card">
            <div className="price-card-header">
              <div>
                <div className="card-title">Harga Pabrik / TWB</div>
                <div className="card-label">Untuk pengiriman mitra hari ini.</div>
              </div>
              {!hargaPabrikEditing && (
                <button className="btn btn-primary btn-sm" onClick={() => setHargaPabrikEditing(true)}>
                  {hargaPabrik ? 'Ubah' : 'Set Harga'}
                </button>
              )}
            </div>
            {hargaPabrikEditing ? (
              <form onSubmit={simpanHargaPabrik} className="inline-edit-form">
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
                <button type="submit" className="btn btn-primary" disabled={hargaPabrikSaving}>
                  {hargaPabrikSaving ? 'Menyimpan...' : 'Simpan'}
                </button>
                <button type="button" className="btn btn-ghost" onClick={() => setHargaPabrikEditing(false)}>
                  Batal
                </button>
              </form>
            ) : (
              <div className="price-value">{hargaPabrik ? `${formatRupiah(hargaPabrik.harga_per_kg)}/kg` : '-'}</div>
            )}
          </div>

          <div className="card dashboard-card">
            <div className="price-card-header">
              <div>
                <div className="card-title">Harga Beli Petani</div>
                <div className="card-label">Untuk pembelian TBS dari petani lokal.</div>
              </div>
              {!hargaEditing && (
                <button className="btn btn-outline btn-sm" onClick={() => setHargaEditing(true)}>
                  {hargaAktif ? 'Ubah' : 'Set Harga'}
                </button>
              )}
            </div>
            {hargaEditing ? (
              <form onSubmit={simpanHarga} className="inline-edit-form">
                <input
                  type="number"
                  className="form-input form-input-mono"
                  value={hargaEdit}
                  onChange={(event) => setHargaEdit(event.target.value)}
                  min={0}
                  step={1}
                  required
                />
                <button type="submit" className="btn btn-primary" disabled={hargaSaving}>
                  {hargaSaving ? 'Menyimpan...' : 'Simpan'}
                </button>
                <button type="button" className="btn btn-ghost" onClick={() => setHargaEditing(false)}>
                  Batal
                </button>
              </form>
            ) : (
              <div className="price-value muted">{hargaAktif ? `${formatRupiah(hargaAktif.harga_per_kg)}/kg` : '-'}</div>
            )}
          </div>
        </div>
      </section>

      <section className="dashboard-section">
        <div className="section-heading">
          <div>
            <h2>Hari Ini</h2>
            <p>Aktivitas utama yang perlu dipantau operator dan keuangan.</p>
          </div>
        </div>

        <div className="stats-grid dashboard-metrics">
          <MetricCard
            title="Pengiriman Mitra"
            value={<>{formatNumber(stats.tbsMitraKg)} <span>kg</span></>}
            label={`${stats.jumlahMitraMengirim} mitra mengirim, termasuk mitra internal`}
            icon={<Truck size={20} />}
            href="/admin/input-timbangan"
          />
          <MetricCard
            title="Pembelian Petani"
            value={<>{formatNumber(stats.tbsMasukKg)} <span>kg</span></>}
            label={`${formatRupiah(stats.tbsMasukRp)} / ${stats.jumlahTransaksi} transaksi`}
            icon={<Scale size={20} />}
            href="/transaksi/beli"
            tone="info"
          />
          <MetricCard
            title="Stok Lokal"
            value={<>{formatNumber(stats.stokLokalKg)} <span>kg</span></>}
            label="Saldo dari ledger stok lokal"
            icon={<Box size={20} />}
            href="/laporan/stok"
            tone={stats.stokLokalKg < 0 ? 'danger' : 'neutral'}
          />
          <MetricCard
            title="Mitra Aktif Hari Ini"
            value={stats.jumlahMitraMengirim}
            label={`${stats.totalMitra} mitra terdaftar aktif`}
            icon={<Users size={20} />}
            href="/owner/laporan-mitra"
            tone="info"
          />
        </div>

        <div className="stats-grid dashboard-metrics finance-metrics">
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
              <p>Daftar hal yang perlu dibereskan sebelum tutup hari.</p>
            </div>
          </div>
          <div className="pending-list">
            {pendingItems.map((item) => (
              <PendingItem key={item.title} {...item} />
            ))}
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
            <QuickAction href="/transaksi/beli" icon={<Store size={20} />} title="Pembelian Petani" description="Catat TBS petani lokal" />
            <QuickAction href="/owner/kwitansi-mitra" icon={<ReceiptText size={20} />} title="Kwitansi Mitra" description="Cetak, bayar, kirim WA" />
            <QuickAction href="/keuangan/hutang" icon={<Wallet size={20} />} title="Hutang & Panjar" description="Catat kasbon dan pelunasan" tone="gold" />
            <QuickAction href="/laporan/harian" icon={<FileText size={20} />} title="Laporan Harian" description="Review sebelum tutup hari" tone="outline" />
          </div>
        </div>
      </section>

      <section className="dashboard-section dashboard-two-col">
        <div className="card dashboard-card">
          <div className="section-heading compact">
            <div>
              <h2>Tren Pembelian Petani 7 Hari</h2>
              <p>Pembelian TBS lokal berdasarkan transaksi aktif.</p>
            </div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 180 }} />
          ) : (
            <div className="mini-chart">
              {tbsSevenDays.map((item) => (
                <div key={item.date} className="mini-chart-bar">
                  <div
                    title={`${formatNumber(item.kg)} kg / ${formatRupiah(item.rp)}`}
                    style={{ height: Math.max(8, (item.kg / maxTbs) * 128) }}
                  />
                  <span>{item.label}</span>
                  <strong>{formatNumber(item.kg)}</strong>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="card dashboard-card">
          <div className="section-heading compact">
            <div>
              <h2>Aktivitas Terbaru</h2>
              <p>Transaksi lokal dan mitra terakhir untuk orientasi cepat.</p>
            </div>
          </div>
          <div className="recent-grid">
            <div>
              <div className="recent-title">Pembelian Petani</div>
              <div className="recent-list">
                {recentTransactions.length === 0 && <div className="empty-compact">Belum ada pembelian.</div>}
                {recentTransactions.map((transaction) => (
                  <Link href="/transaksi/beli" className="recent-row" key={transaction.id}>
                    <span>
                      <strong>{transaction.no_struk || '-'}</strong>
                      <small>{transaction.petani?.nama || '-'}</small>
                    </span>
                    <b>{formatNumber(transaction.berat_bersih_kg)} kg</b>
                  </Link>
                ))}
              </div>
            </div>
            <div>
              <div className="recent-title">Pengiriman Mitra</div>
              <div className="recent-list">
                {recentMitra.length === 0 && <div className="empty-compact">Belum ada pengiriman mitra.</div>}
                {recentMitra.map((transaction) => (
                  <Link href="/owner/riwayat-pengiriman-mitra" className="recent-row" key={transaction.id}>
                    <span>
                      <strong>{transaction.master_mitra?.kode || transaction.master_mitra?.nama || '-'}</strong>
                      <small>{formatDateDisplay(transaction.tanggal)}</small>
                    </span>
                    <b>{formatNumber(transaction.tonase)} kg</b>
                  </Link>
                ))}
              </div>
            </div>
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

        .price-grid,
        .dashboard-two-col {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: var(--space-lg);
        }

        .price-card-header,
        .inline-edit-form {
          display: flex;
          align-items: flex-end;
          justify-content: space-between;
          gap: var(--space-md);
          flex-wrap: wrap;
        }

        .inline-edit-form {
          margin-top: var(--space-md);
        }

        .inline-edit-form input {
          flex: 1 1 220px;
        }

        .price-value {
          margin-top: var(--space-lg);
          font-family: var(--font-mono);
          color: var(--color-primary-400);
          font-size: var(--text-3xl);
          font-weight: 900;
        }

        .price-value.muted {
          color: var(--text-primary);
        }

        .dashboard-metrics {
          grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
          margin-bottom: var(--space-lg);
        }

        .finance-metrics {
          margin-bottom: 0;
        }

        .pending-list,
        .quick-action-grid,
        .recent-list {
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

        .mini-chart {
          display: grid;
          grid-template-columns: repeat(7, 1fr);
          gap: 10px;
          align-items: end;
          min-height: 190px;
        }

        .mini-chart-bar {
          display: flex;
          flex-direction: column;
          justify-content: flex-end;
          gap: 8px;
          min-width: 0;
        }

        .mini-chart-bar div {
          border-radius: var(--radius-sm);
          background: linear-gradient(180deg, var(--color-primary-400), var(--color-primary-700));
        }

        .mini-chart-bar span,
        .mini-chart-bar strong {
          text-align: center;
          font-size: var(--text-xs);
        }

        .mini-chart-bar span {
          color: var(--text-tertiary);
        }

        .mini-chart-bar strong {
          color: var(--text-secondary);
          font-family: var(--font-mono);
          font-weight: 700;
        }

        .recent-grid {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: var(--space-lg);
        }

        .recent-title {
          margin-bottom: var(--space-sm);
          color: var(--text-secondary);
          font-size: var(--text-xs);
          font-weight: 800;
          text-transform: uppercase;
        }

        .recent-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--space-md);
          padding: 10px 0;
          border-bottom: 1px solid var(--border-default);
          color: var(--text-primary);
          text-decoration: none;
        }

        .recent-row:hover {
          color: var(--color-primary-400);
        }

        .recent-row span,
        .recent-row small {
          display: block;
          min-width: 0;
        }

        .recent-row strong,
        .recent-row b {
          font-family: var(--font-mono);
          font-size: var(--text-sm);
        }

        .recent-row small {
          margin-top: 2px;
          color: var(--text-tertiary);
          font-size: var(--text-xs);
        }

        .recent-row b {
          flex: 0 0 auto;
          color: var(--text-secondary);
        }

        .empty-compact {
          padding: 18px 0;
          color: var(--text-tertiary);
          font-size: var(--text-sm);
        }

        @media (max-width: 900px) {
          .price-grid,
          .dashboard-two-col,
          .recent-grid {
            grid-template-columns: 1fr;
          }

          .quick-action-grid {
            grid-template-columns: 1fr;
          }
        }

        @media (max-width: 560px) {
          .dashboard-status-row {
            justify-content: flex-start;
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
