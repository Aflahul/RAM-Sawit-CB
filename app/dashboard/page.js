'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, formatNumber, getTodayISO } from '@/lib/utils';
import { exportLaporanHarian } from '@/lib/export';
import { Factory, Users, Scale, Box, CreditCard, Calculator } from 'lucide-react';

function LockedWrapper({ children }) {
  return (
    <div style={{ position: 'relative', height: '100%' }}>
      <div style={{ position: 'absolute', inset: -4, zIndex: 10, background: 'rgba(2, 6, 23, 0.4)', backdropFilter: 'blur(2px)', display: 'flex', alignItems: 'center', justifyContent: 'center', borderRadius: 12 }}>
         <div style={{ background: 'var(--bg-card)', padding: '4px 12px', borderRadius: 20, fontSize: 'var(--text-xs)', color: 'var(--color-gold-400)', border: '1px solid var(--color-gold-500)', fontWeight: 600 }}>Tahap 2</div>
      </div>
      <div style={{ opacity: 0.3, pointerEvents: 'none', filter: 'grayscale(1)', height: '100%' }}>
        {children}
      </div>
    </div>
  );
}

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
  const [year, month, day] = dateString.split('-').map(Number);
  return new Date(year, month - 1, day).toLocaleDateString('id-ID', { weekday: 'short' });
}

export default function DashboardPage() {
  const [stats, setStats] = useState({
    tbsMasukKg: 0,
    tbsMasukRp: 0,
    jumlahTransaksi: 0,
    stokLokalKg: 0,
    hutangAktif: 0,
    jumlahPetaniHutang: 0,
    totalBiaya: 0,
    pengirimanPending: 0,
    // MVP Mitra
    tbsMitraKg: 0,
    jumlahMitraMengirim: 0,
    totalMitra: 0,
    totalPengirimanPabrikKg: 0,
    pengirimanLokalToday: 0,
  });
  const [hargaAktif, setHargaAktif] = useState(null);
  const [hargaEdit, setHargaEdit] = useState('');
  const [hargaEditing, setHargaEditing] = useState(false);
  const [hargaSaving, setHargaSaving] = useState(false);

  // MVP Harga Pabrik
  const [hargaPabrik, setHargaPabrik] = useState(null);
  const [hargaPabrikEdit, setHargaPabrikEdit] = useState('');
  const [hargaPabrikEditing, setHargaPabrikEditing] = useState(false);
  const [hargaPabrikSaving, setHargaPabrikSaving] = useState(false);

  const [tbsSevenDays, setTbsSevenDays] = useState([]);
  const [recentTransactions, setRecentTransactions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState(null);

  const loadDashboard = useCallback(async () => {
    setLoading(true);
    const today = getTodayISO();
    const days = getLastSevenDays();
    const firstDayWeek = days[0];

    const [
      tbsToday,
      tbsWeek,
      stokLedger,
      hutangLedger,
      biayaToday,
      pengirimanPending,
      recent,
      harga,
      trxMitra,
      masterMitra,
      pengirimanToday,
      hargaPabrikData,
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
        .select('berat_kg'),
      supabase
        .from('hutang_ledger')
        .select('petani_id, tipe, jumlah')
        .eq('pihak_type', 'petani'),
      supabase
        .from('biaya_operasional')
        .select('jumlah')
        .eq('tanggal', today)
        .neq('status', 'dibatalkan'),
      supabase
        .from('pengiriman')
        .select('id', { count: 'exact', head: true })
        .in('status', ['dikirim', 'diterima', 'diterima_pabrik', 'menunggu_pembayaran_pabrik']),
      supabase
        .from('transaksi_beli_tbs')
        .select('id, no_struk, petani:petani_id(nama), berat_bersih_kg, total_harga, created_at')
        .neq('status', 'dibatalkan')
        .order('created_at', { ascending: false })
        .limit(10),
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
        .from('pengiriman')
        .select('tonase_kirim')
        .eq('tanggal', today)
        .neq('status', 'dibatalkan'),
      supabase
        .from('harga_tbs')
        .select('harga_per_kg')
        .order('tanggal', { ascending: false })
        .limit(1)
        .maybeSingle(),
    ]);

    if (tbsToday.error || tbsWeek.error || stokLedger.error || hutangLedger.error || biayaToday.error || recent.error || harga.error || trxMitra.error) {
      setToast({ type: 'error', message: 'Sebagian data dashboard gagal dimuat.' });
    }

    const todayRows = tbsToday.data || [];
    const tbsMasukKg = todayRows.reduce((sum, item) => sum + Number(item.berat_bersih_kg || 0), 0);
    const tbsMasukRp = todayRows.reduce((sum, item) => sum + Number(item.total_harga || 0), 0);
    const stokLokalKg = (stokLedger.data || []).reduce((sum, item) => sum + Number(item.berat_kg || 0), 0);
    const totalBiaya = (biayaToday.data || []).reduce((sum, item) => sum + Number(item.jumlah || 0), 0);

    const transaksiMitraToday = trxMitra?.data || [];
    const tbsMitraKg = transaksiMitraToday.reduce((sum, item) => sum + Number(item.tonase || 0), 0);
    const uniqueMitraIds = new Set(transaksiMitraToday.map(item => item.mitra_id).filter(Boolean));
    const jumlahMitraMengirim = uniqueMitraIds.size;
    const totalMitra = masterMitra?.count || 0;
    
    const pengirimanLokalToday = (pengirimanToday?.data || []).reduce((sum, item) => sum + Number(item.tonase_kirim || 0), 0);
    const totalPengirimanPabrikKg = tbsMitraKg + pengirimanLokalToday;

    const hutangPerPetani = {};
    (hutangLedger.data || []).forEach((item) => {
      const value = Number(item.jumlah || 0);
      hutangPerPetani[item.petani_id] = (hutangPerPetani[item.petani_id] || 0) + (item.tipe === 'debit' ? value : -value);
    });
    const saldoHutang = Object.values(hutangPerPetani).filter((saldo) => saldo > 0);

    setStats({
      tbsMasukKg,
      tbsMasukRp,
      jumlahTransaksi: todayRows.length,
      stokLokalKg,
      hutangAktif: saldoHutang.reduce((sum, saldo) => sum + saldo, 0),
      jumlahPetaniHutang: saldoHutang.length,
      totalBiaya,
      pengirimanPending: pengirimanPending.count || 0,
      tbsMitraKg,
      jumlahMitraMengirim,
      totalMitra,
      totalPengirimanPabrikKg,
      pengirimanLokalToday
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

    setRecentTransactions(recent.data || []);
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

  return (
    <AppShell title="Dashboard" subtitle="Ringkasan operasional hari ini">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      {!hargaAktif && !loading && (
        <div className="alert alert-warning" style={{ marginBottom: 'var(--space-lg)' }}>
          <span>
            Harga TBS lokal aktif belum diset. Input pembelian petani akan terkunci sampai harga tersedia.
          </span>
        </div>
      )}

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: 'var(--space-lg)', marginBottom: 'var(--space-xl)' }}>
        {/* Harga Pabrik (MVP) */}
        <div className="card">
          <div className="card-header" style={{ marginBottom: hargaPabrikEditing ? 'var(--space-md)' : 0 }}>
            <div>
              <div className="card-title">Harga Pabrik (TWB)</div>
              <div className="card-label">
                Untuk transaksi penerimaan Mitra hari ini.
              </div>
            </div>
            {!hargaPabrikEditing && (
              <div className="flex items-center gap-sm">
                <div className="text-mono" style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--color-primary-600)' }}>
                  {hargaPabrik ? `${formatRupiah(hargaPabrik.harga_per_kg)}/kg` : '-'}
                </div>
                <button className="btn btn-primary btn-sm" onClick={() => setHargaPabrikEditing(true)}>
                  {hargaPabrik ? 'Ubah' : 'Set Harga'}
                </button>
              </div>
            )}
          </div>

          {hargaPabrikEditing && (
            <form onSubmit={simpanHargaPabrik} className="flex items-end gap-md" style={{ flexWrap: 'wrap' }}>
              <div style={{ flex: 1, minWidth: 200 }}>
                <label className="form-label">Harga Pabrik (Rp/Kg)</label>
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
              </div>
              <button type="submit" className="btn btn-primary" disabled={hargaPabrikSaving}>
                {hargaPabrikSaving ? 'Menyimpan...' : 'Simpan'}
              </button>
              <button type="button" className="btn btn-ghost" onClick={() => setHargaPabrikEditing(false)}>
                Batal
              </button>
            </form>
          )}
        </div>

        {/* Harga TBS Lokal (Tahap 2) */}
        <LockedWrapper>
        <div className="card" style={{ height: '100%' }}>
          <div className="card-header" style={{ marginBottom: hargaEditing ? 'var(--space-md)' : 0 }}>
            <div>
              <div className="card-title">Harga Beli Lokal (Tahap 2)</div>
              <div className="card-label">
                Untuk pembelian TBS dari petani lokal.
              </div>
            </div>
            {!hargaEditing && (
              <div className="flex items-center gap-sm">
                <div className="text-mono" style={{ fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--text-secondary)' }}>
                  {hargaAktif ? `${formatRupiah(hargaAktif.harga_per_kg)}/kg` : '-'}
                </div>
                <button className="btn btn-outline btn-sm" onClick={() => setHargaEditing(true)}>
                  {hargaAktif ? 'Ubah' : 'Set Harga'}
                </button>
              </div>
            )}
          </div>

          {hargaEditing && (
            <form onSubmit={simpanHarga} className="flex items-end gap-md" style={{ flexWrap: 'wrap' }}>
              <div style={{ flex: 1, minWidth: 200 }}>
                <label className="form-label">Harga Beli Petani (Rp)</label>
                <input
                  type="number"
                  className="form-input form-input-mono"
                  value={hargaEdit}
                  onChange={(event) => setHargaEdit(event.target.value)}
                  min={0}
                  step={1}
                  required
                />
              </div>
              <button type="submit" className="btn btn-primary" disabled={hargaSaving}>
                {hargaSaving ? 'Menyimpan...' : 'Simpan'}
              </button>
              <button type="button" className="btn btn-ghost" onClick={() => setHargaEditing(false)}>
                Batal
              </button>
            </form>
          )}
        </div>
        </LockedWrapper>
      </div>

      <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 600, marginBottom: 'var(--space-md)', color: 'var(--text-primary)' }}>
        Ringkasan Mitra & Pabrik (MVP)
      </h3>
      <div className="stats-grid" style={{ marginBottom: 'var(--space-xl)' }}>
        <div className="card">
          <div className="card-header">
            <span className="card-title">Total Pengiriman ke Pabrik</span>
            <div className="card-icon card-icon-green"><Factory size={20} /></div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '60%', marginBottom: 8 }} />
          ) : (
            <>
              <div className="card-value">{formatNumber(stats.totalPengirimanPabrikKg)} <span style={{ fontSize: 'var(--text-base)', fontWeight: 400 }}>kg</span></div>
              <div className="card-label">Hari ini (Mitra: {formatNumber(stats.tbsMitraKg)} kg + Lokal: {formatNumber(stats.pengirimanLokalToday)} kg)</div>
            </>
          )}
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">Mitra Terdaftar</span>
            <div className="card-icon card-icon-blue"><Users size={20} /></div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '60%', marginBottom: 8 }} />
          ) : (
            <>
              <div className="card-value">{stats.totalMitra} <span style={{ fontSize: 'var(--text-base)', fontWeight: 400 }}>Mitra</span></div>
              <div className="card-label">{stats.jumlahMitraMengirim} mitra mengirim hari ini</div>
            </>
          )}
          <div className="card-footer">
            <Link href="/owner/master-data" className="btn btn-ghost btn-sm">Lihat Master Data</Link>
          </div>
        </div>
      </div>

      <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 600, marginBottom: 'var(--space-md)', color: 'var(--text-primary)' }}>
        Ringkasan Operasional Lokal (Tahap 2)
      </h3>
      <LockedWrapper>
      <div className="stats-grid">
        <div className="card">
          <div className="card-header">
            <span className="card-title">TBS Lokal Masuk</span>
            <div className="card-icon card-icon-green"><Scale size={20} /></div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '60%', marginBottom: 8 }} />
          ) : (
            <>
              <div className="card-value">{formatNumber(stats.tbsMasukKg)} <span style={{ fontSize: 'var(--text-base)', fontWeight: 400 }}>kg</span></div>
              <div className="card-label">{formatRupiah(stats.tbsMasukRp)} / {stats.jumlahTransaksi} transaksi</div>
            </>
          )}
          <div className="card-footer">
            <Link href="/transaksi/beli" className="btn btn-ghost btn-sm">Input TBS</Link>
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">Stok Lokal Sementara</span>
            <div className="card-icon card-icon-blue"><Box size={20} /></div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '60%', marginBottom: 8 }} />
          ) : (
            <>
              <div className="card-value">{formatNumber(stats.stokLokalKg)} <span style={{ fontSize: 'var(--text-base)', fontWeight: 400 }}>kg</span></div>
              <div className="card-label">Saldo dari ledger stok lokal</div>
            </>
          )}
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">Hutang Petani Aktif</span>
            <div className="card-icon card-icon-gold"><CreditCard size={20} /></div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '70%', marginBottom: 8 }} />
          ) : (
            <>
              <div className="card-value">{formatRupiah(stats.hutangAktif)}</div>
              <div className="card-label">{stats.jumlahPetaniHutang} petani memiliki hutang</div>
            </>
          )}
          <div className="card-footer">
            <Link href="/keuangan/hutang" className="btn btn-ghost btn-sm">Lihat Hutang</Link>
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">Biaya Hari Ini</span>
            <div className="card-icon card-icon-red"><Calculator size={20} /></div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '50%', marginBottom: 8 }} />
          ) : (
            <>
              <div className="card-value">{formatRupiah(stats.totalBiaya)}</div>
              <div className="card-label">Total pengeluaran operasional</div>
            </>
          )}
          <div className="card-footer">
            <Link href="/keuangan/biaya" className="btn btn-ghost btn-sm">Input Biaya</Link>
          </div>
        </div>
      </div>
      </LockedWrapper>

      <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr)', gap: 'var(--space-lg)', marginTop: 'var(--space-lg)' }}>
        <LockedWrapper>
        <div className="card">
          <div className="card-header">
            <span className="card-title">TBS Lokal Masuk 7 Hari</span>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 180 }} />
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 10, alignItems: 'end', minHeight: 190 }}>
              {tbsSevenDays.map((item) => (
                <div key={item.date} style={{ display: 'flex', flexDirection: 'column', gap: 8, justifyContent: 'flex-end' }}>
                  <div
                    title={`${formatNumber(item.kg)} kg / ${formatRupiah(item.rp)}`}
                    style={{
                      height: Math.max(8, (item.kg / maxTbs) * 130),
                      background: 'linear-gradient(180deg, var(--color-primary-400), var(--color-primary-700))',
                      borderRadius: 6,
                    }}
                  />
                  <div className="text-center text-tertiary text-sm">{item.label}</div>
                  <div className="text-center text-mono text-sm">{formatNumber(item.kg)}</div>
                </div>
              ))}
            </div>
          )}
        </div>
        </LockedWrapper>
      </div>

      <div style={{ marginTop: 'var(--space-lg)' }}>
        <LockedWrapper>
        <div className="card">
        <div className="card-header">
          <span className="card-title">Transaksi Terakhir</span>
          <Link href="/transaksi/beli" className="btn btn-outline btn-sm">Lihat Semua</Link>
        </div>
        {loading ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {[1, 2, 3].map((item) => <div key={item} className="skeleton" style={{ height: 44 }} />)}
          </div>
        ) : recentTransactions.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-title">Belum ada transaksi</div>
            <div className="empty-state-text">Mulai input pembelian TBS dari petani lokal</div>
          </div>
        ) : (
          <div className="table-container" style={{ border: 'none' }}>
            <table className="table">
              <thead>
                <tr>
                  <th>No. Struk</th>
                  <th>Petani</th>
                  <th style={{ textAlign: 'right' }}>Berat (kg)</th>
                  <th style={{ textAlign: 'right' }}>Total</th>
                </tr>
              </thead>
              <tbody>
                {recentTransactions.map((transaction) => (
                  <tr key={transaction.id}>
                    <td className="table-mono">{transaction.no_struk || '-'}</td>
                    <td>{transaction.petani?.nama || '-'}</td>
                    <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(transaction.berat_bersih_kg)}</td>
                    <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(transaction.total_harga)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        </div>
        </LockedWrapper>
      </div>

      <div style={{ marginTop: 'var(--space-xl)' }}>
        <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600, marginBottom: 'var(--space-md)', color: 'var(--text-secondary)' }}>
          Aksi Cepat
        </h3>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 'var(--space-md)' }}>
          <LockedWrapper>
          <div className="card" style={{ textAlign: 'center', textDecoration: 'none' }}>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Input TBS Lokal</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)', marginTop: 4 }}>Pembelian dari petani</div>
          </div>
          </LockedWrapper>
          <LockedWrapper>
          <div className="card" style={{ textAlign: 'center', textDecoration: 'none' }}>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Harga TBS</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)', marginTop: 4 }}>{hargaAktif ? `${formatRupiah(hargaAktif.harga_per_kg)}/kg` : 'Belum diset'}</div>
          </div>
          </LockedWrapper>
          <Link href="/admin/input-timbangan" className="card spring-transition" style={{ textAlign: 'center', textDecoration: 'none' }}>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Pengiriman Mitra</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)', marginTop: 4 }}>Input ke pabrik</div>
          </Link>
          <LockedWrapper>
          <div className="card" style={{ textAlign: 'center', textDecoration: 'none' }}>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Biaya Operasional</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)', marginTop: 4 }}>Solar, gaji, retribusi</div>
          </div>
          </LockedWrapper>
        </div>
      </div>
    </AppShell>
  );
}
