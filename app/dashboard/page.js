'use client';

import { useState, useEffect, useCallback } from 'react';
import AppShell from '@/components/layout/AppShell';
import { supabase } from '@/lib/supabase';
import { formatRupiah, formatNumber, getTodayISO } from '@/lib/utils';
import Link from 'next/link';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, PieChart, Pie, Cell,
} from 'recharts';

const CHART_COLORS = ['#2ecc71', '#f1c40f', '#e74c3c', '#3498db', '#9b59b6', '#1abc9c'];

export default function DashboardPage() {
  const [stats, setStats] = useState({
    tbsMasukKg: 0, tbsMasukRp: 0, jumlahTransaksi: 0,
    hutangAktif: 0, jumlahPetaniHutang: 0, totalBiaya: 0, pengirimanPending: 0,
  });
  const [recentTransactions, setRecentTransactions] = useState([]);
  const [chartTBS, setChartTBS] = useState([]);
  const [chartBiaya, setChartBiaya] = useState([]);
  const [hargaHariIni, setHargaHariIni] = useState(null);
  const [hargaEdit, setHargaEdit] = useState('');
  const [hargaEditing, setHargaEditing] = useState(false);
  const [hargaSaving, setHargaSaving] = useState(false);
  const [loading, setLoading] = useState(true);
  const [hargaBanner, setHargaBanner] = useState(false); // banner peringatan harga

  const loadDashboard = useCallback(async () => {
    try {
      const today = getTodayISO();

      // Hitung tanggal 7 hari terakhir untuk chart
      const days = [];
      for (let i = 6; i >= 0; i--) {
        // Gunakan WITA offset untuk konsistensi
        const d = new Date(new Date().getTime() + 8 * 60 * 60 * 1000);
        d.setUTCDate(d.getUTCDate() - i);
        days.push(d.toISOString().split('T')[0]);
      }
      const firstDayWeek = days[0];
      const firstDayMonth = `${today.slice(0, 7)}-01`;

      // ── Paralelkan semua query sekaligus ──────────────────────────────
      const [
        tbsToday,
        tbsWeekRes,
        hutangRes,
        hutangLogRes,
        tbsPotonganRes,
        biayaToday,
        biayaBulanRes,
        pengirimanRes,
        recentRes,
        hargaRes,
      ] = await Promise.all([
        // TBS masuk hari ini
        supabase
          .from('transaksi_beli')
          .select('berat_bersih, total_harga')
          .eq('tanggal', today),

        // TBS 7 hari untuk chart
        supabase
          .from('transaksi_beli')
          .select('tanggal, berat_bersih, total_harga')
          .gte('tanggal', firstDayWeek)
          .lte('tanggal', today),

        // Total hutang per petani (pokok)
        supabase
          .from('hutang')
          .select('petani_id, jumlah'),

        // Total pembayaran hutang via hutang_log
        supabase
          .from('hutang_log')
          .select('petani_id, jumlah_bayar'),

        // Total potongan hutang via transaksi TBS (juga merupakan pembayaran)
        supabase
          .from('transaksi_beli')
          .select('petani_id, potongan_hutang')
          .gt('potongan_hutang', 0),

        // Biaya hari ini
        supabase
          .from('biaya_operasional')
          .select('jumlah')
          .eq('tanggal', today),

        // Biaya per kategori bulan ini (untuk pie chart)
        supabase
          .from('biaya_operasional')
          .select('kategori, jumlah')
          .gte('tanggal', firstDayMonth)
          .lte('tanggal', today),

        // Pengiriman pending (count only)
        supabase
          .from('pengiriman')
          .select('*', { count: 'exact', head: true })
          .in('status', ['dikirim', 'diterima']),

        // 5 transaksi terbaru
        supabase
          .from('transaksi_beli')
          .select('*, petani:petani_id(nama)')
          .order('created_at', { ascending: false })
          .limit(5),

        // Harga TBS hari ini
        supabase
          .from('harga_tbs')
          .select('*')
          .eq('tanggal', today)
          .maybeSingle(),
      ]);

      // ── Kalkulasi stats TBS ──────────────────────────────────────────
      const tbsMasukKg = tbsToday.data?.reduce((s, t) => s + (t.berat_bersih || 0), 0) || 0;
      const tbsMasukRp = tbsToday.data?.reduce((s, t) => s + (t.total_harga || 0), 0) || 0;

      // ── Kalkulasi hutang aktif yang AKURAT ────────────────────────────
      // Total pokok hutang per petani
      const hutangPerPetani = {};
      (hutangRes.data || []).forEach(h => {
        hutangPerPetani[h.petani_id] = (hutangPerPetani[h.petani_id] || 0) + (h.jumlah || 0);
      });

      // Kurangi pembayaran via hutang_log
      (hutangLogRes.data || []).forEach(h => {
        if (hutangPerPetani[h.petani_id] !== undefined) {
          hutangPerPetani[h.petani_id] -= (h.jumlah_bayar || 0);
        }
      });

      // Kurangi potongan hutang via transaksi TBS
      (tbsPotonganRes.data || []).forEach(t => {
        if (hutangPerPetani[t.petani_id] !== undefined) {
          hutangPerPetani[t.petani_id] -= (t.potongan_hutang || 0);
        }
      });

      // Hutang aktif = jumlah per petani yang masih positif
      let hutangAktif = 0;
      let jumlahPetaniHutang = 0;
      Object.values(hutangPerPetani).forEach(saldo => {
        if (saldo > 0) {
          hutangAktif += saldo;
          jumlahPetaniHutang++;
        }
      });

      // ── Biaya ───────────────────────────────────────────────────────
      const totalBiaya = biayaToday.data?.reduce((s, b) => s + (b.jumlah || 0), 0) || 0;

      // ── Chart TBS ─────────────────────────────────────────────────
      const kategoriLabel = {
        solar: 'Solar', gaji_sopir: 'Gaji Sopir', kuli: 'Kuli',
        retribusi: 'Retribusi', perawatan: 'Perawatan', lainnya: 'Lainnya',
      };
      const tbsChart = days.map(d => {
        const dayData = (tbsWeekRes.data || []).filter(t => t.tanggal === d);
        const dayName = (() => {
          // Parse tanggal tanpa shift timezone
          const [y, m, day] = d.split('-').map(Number);
          return new Date(y, m - 1, day).toLocaleDateString('id-ID', { weekday: 'short' });
        })();
        return {
          name: dayName,
          kg: dayData.reduce((s, t) => s + (t.berat_bersih || 0), 0),
          rp: dayData.reduce((s, t) => s + (t.total_harga || 0), 0),
        };
      });
      setChartTBS(tbsChart);

      // ── Chart Biaya ─────────────────────────────────────────────
      const biayaMap = {};
      (biayaBulanRes.data || []).forEach(b => {
        const label = kategoriLabel[b.kategori] || b.kategori;
        biayaMap[label] = (biayaMap[label] || 0) + (b.jumlah || 0);
      });
      setChartBiaya(Object.entries(biayaMap).map(([name, value]) => ({ name, value })));

      // ── Harga TBS ─────────────────────────────────────────────
      const harga = hargaRes.data;
      setHargaHariIni(harga);
      if (harga) {
        setHargaEdit(harga.harga_per_kg.toString());
        setHargaBanner(false);
      } else {
        setHargaEdit('');
        setHargaBanner(true); // tampilkan banner jika belum ada harga hari ini
      }

      setStats({
        tbsMasukKg, tbsMasukRp,
        jumlahTransaksi: tbsToday.data?.length || 0,
        hutangAktif, jumlahPetaniHutang,
        totalBiaya,
        pengirimanPending: pengirimanRes.count || 0,
      });
      setRecentTransactions(recentRes.data || []);
    } catch (err) {
      console.error('Error loading dashboard:', err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadDashboard(); }, [loadDashboard]);

  async function simpanHarga(e) {
    e.preventDefault();
    const nilai = parseFloat(hargaEdit);
    if (!nilai || nilai <= 0) return;
    setHargaSaving(true);
    const today = getTodayISO();
    try {
      if (hargaHariIni) {
        await supabase.from('harga_tbs').update({ harga_per_kg: nilai }).eq('id', hargaHariIni.id);
      } else {
        await supabase.from('harga_tbs').insert({ tanggal: today, harga_per_kg: nilai });
      }
      // Refresh harga dari DB
      const { data } = await supabase.from('harga_tbs').select('*').eq('tanggal', today).maybeSingle();
      setHargaHariIni(data);
      setHargaEdit(data?.harga_per_kg?.toString() || '');
      setHargaBanner(false);
      setHargaEditing(false);
    } catch (err) {
      console.error('Error simpan harga:', err);
    } finally {
      setHargaSaving(false);
    }
  }

  const CustomTooltip = ({ active, payload, label }) => {
    if (!active || !payload?.length) return null;
    return (
      <div style={{
        background: 'var(--bg-card)', border: '1px solid var(--border-default)',
        borderRadius: 8, padding: '8px 12px', fontSize: 'var(--text-xs)',
        boxShadow: 'var(--shadow-md)',
      }}>
        <div style={{ fontWeight: 600, marginBottom: 4 }}>{label}</div>
        {payload.map((p, i) => (
          <div key={i} style={{ color: p.color }}>
            {p.name === 'kg' ? `${formatNumber(p.value)} kg` : formatRupiah(p.value)}
          </div>
        ))}
      </div>
    );
  };

  return (
    <AppShell title="Dashboard" subtitle="Ringkasan operasional hari ini">

      {/* ── BANNER PERINGATAN HARGA ─────────────────────────────── */}
      {hargaBanner && !loading && (
        <div className="alert alert-warning" style={{
          marginBottom: 'var(--space-lg)',
          position: 'sticky',
          top: 0,
          zIndex: 40,
          borderRadius: 'var(--radius-md)',
          boxShadow: 'var(--shadow-md)',
          animation: 'slideUp var(--transition-base)',
        }}>
          <span className="alert-icon">⚠️</span>
          <div style={{ flex: 1 }}>
            <strong>Harga TBS belum diset untuk hari ini!</strong>
            <div style={{ fontSize: 'var(--text-xs)', marginTop: 2, opacity: 0.85 }}>
              Pastikan harga sudah diperbarui sebelum mencatat transaksi pembelian.
            </div>
          </div>
          <button
            className="btn btn-gold btn-sm"
            onClick={() => setHargaEditing(true)}
            style={{ flexShrink: 0 }}
          >
            💲 Set Harga Sekarang
          </button>
        </div>
      )}

      {/* ── HARGA SAWIT HARI INI ────────────────────────────────── */}
      <div className="card" style={{ marginBottom: 'var(--space-xl)', background: 'linear-gradient(135deg, rgba(27,94,59,0.3), rgba(26,35,50,1))', borderColor: 'rgba(59,171,113,0.25)' }}>
        <div className="card-header" style={{ marginBottom: hargaEditing ? 'var(--space-md)' : 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-md)' }}>
            <div className="card-icon card-icon-green" style={{ fontSize: '1.4rem' }}>💲</div>
            <div>
              <div className="card-title">Harga TBS Hari Ini</div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)', marginTop: 2 }}>
                {new Date().toLocaleDateString('id-ID', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Asia/Makassar' })}
              </div>
            </div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-sm)' }}>
            {loading ? (
              <div className="skeleton" style={{ width: 140, height: 36, borderRadius: 8 }} />
            ) : hargaHariIni && !hargaEditing ? (
              <>
                <div style={{ fontFamily: 'var(--font-mono)', fontSize: 'var(--text-2xl)', fontWeight: 800, color: 'var(--color-primary-400)' }}>
                  {formatRupiah(hargaHariIni.harga_per_kg)}<span style={{ fontSize: 'var(--text-sm)', fontWeight: 400, color: 'var(--text-tertiary)' }}>/kg</span>
                </div>
                <button
                  className="btn btn-outline btn-sm"
                  onClick={() => { setHargaEditing(true); setHargaEdit(hargaHariIni.harga_per_kg.toString()); }}
                >
                  ✏️ Edit
                </button>
              </>
            ) : !hargaHariIni && !hargaEditing ? (
              <button className="btn btn-gold btn-sm" onClick={() => setHargaEditing(true)}>
                💲 Set Harga
              </button>
            ) : null}
          </div>
        </div>

        {/* Form Edit Harga Inline */}
        {hargaEditing && (
          <form onSubmit={simpanHarga} style={{ display: 'flex', alignItems: 'flex-end', gap: 'var(--space-md)', flexWrap: 'wrap' }}>
            <div style={{ flex: 1, minWidth: 180 }}>
              <label className="form-label">Harga per kg (Rp)</label>
              <input
                type="number"
                className="form-input form-input-mono"
                value={hargaEdit}
                onChange={e => setHargaEdit(e.target.value)}
                placeholder="contoh: 2500"
                min={1}
                step={10}
                required
                autoFocus
              />
            </div>
            <div style={{ display: 'flex', gap: 'var(--space-sm)', paddingBottom: 2 }}>
              <button type="submit" className="btn btn-primary" disabled={hargaSaving}>
                {hargaSaving ? (
                  <><span className="spinner" style={{ width: 16, height: 16, borderWidth: 2 }} /> Menyimpan...</>
                ) : (
                  <><span>✅</span> Simpan Harga</>
                )}
              </button>
              <button type="button" className="btn btn-ghost" onClick={() => setHargaEditing(false)}>
                Batal
              </button>
            </div>
          </form>
        )}
      </div>

      {/* ── STATS GRID ─────────────────────────────────────────── */}
      <div className="stats-grid">
        <div className="card">
          <div className="card-header">
            <span className="card-title">TBS Masuk Hari Ini</span>
            <div className="card-icon card-icon-green">📦</div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '60%', marginBottom: 8 }} />
          ) : (
            <>
              <div className="card-value">{formatNumber(stats.tbsMasukKg)} <span style={{ fontSize: 'var(--text-base)', fontWeight: 400 }}>kg</span></div>
              <div className="card-label">{formatRupiah(stats.tbsMasukRp)} • {stats.jumlahTransaksi} transaksi</div>
            </>
          )}
          <div className="card-footer">
            <Link href="/transaksi/beli" className="btn btn-ghost btn-sm">+ Input TBS</Link>
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">Hutang Aktif Petani</span>
            <div className="card-icon card-icon-gold">💳</div>
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
            <Link href="/keuangan/hutang" className="btn btn-ghost btn-sm">Lihat Detail →</Link>
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">Biaya Hari Ini</span>
            <div className="card-icon card-icon-red">🔧</div>
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
            <Link href="/keuangan/biaya" className="btn btn-ghost btn-sm">+ Input Biaya</Link>
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <span className="card-title">Pengiriman Pending</span>
            <div className="card-icon card-icon-blue">🚚</div>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 48, width: '30%', marginBottom: 8 }} />
          ) : (
            <>
              <div className="card-value">{stats.pengirimanPending}</div>
              <div className="card-label">Belum selesai / belum dibayar</div>
            </>
          )}
          <div className="card-footer">
            <Link href="/transaksi/kirim" className="btn btn-ghost btn-sm">Lihat Pengiriman →</Link>
          </div>
        </div>
      </div>

      {/* ── CHARTS ─────────────────────────────────────────────── */}
      <div style={{ display: 'grid', gridTemplateColumns: chartBiaya.length > 0 ? '2fr 1fr' : '1fr', gap: 'var(--space-lg)', marginTop: 'var(--space-lg)' }}>
        {/* TBS 7 Hari */}
        <div className="card">
          <div className="card-header">
            <span className="card-title">📈 TBS Masuk (7 Hari Terakhir)</span>
          </div>
          {loading ? (
            <div className="skeleton" style={{ height: 220 }} />
          ) : chartTBS.every(d => d.kg === 0) ? (
            <div className="empty-state" style={{ padding: 'var(--space-xl)' }}>
              <div className="empty-state-icon">📈</div>
              <div className="empty-state-title">Belum ada data</div>
              <div className="empty-state-text">Grafik akan muncul setelah ada transaksi TBS</div>
            </div>
          ) : (
            <div style={{ width: '100%', height: 240 }}>
              <ResponsiveContainer>
                <AreaChart data={chartTBS} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="gradTBS" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#2ecc71" stopOpacity={0.3} />
                      <stop offset="95%" stopColor="#2ecc71" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
                  <XAxis dataKey="name" tick={{ fill: 'var(--text-tertiary)', fontSize: 12 }} axisLine={false} tickLine={false} />
                  <YAxis tick={{ fill: 'var(--text-tertiary)', fontSize: 11 }} axisLine={false} tickLine={false} width={50} />
                  <Tooltip content={<CustomTooltip />} />
                  <Area type="monotone" dataKey="kg" name="kg" stroke="#2ecc71" fill="url(#gradTBS)" strokeWidth={2.5} dot={{ r: 4, fill: '#2ecc71' }} />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          )}
        </div>

        {/* Biaya Pie Chart */}
        {chartBiaya.length > 0 && (
          <div className="card">
            <div className="card-header">
              <span className="card-title">🔧 Biaya Bulan Ini</span>
            </div>
            <div style={{ width: '100%', height: 240 }}>
              <ResponsiveContainer>
                <PieChart>
                  <Pie data={chartBiaya} cx="50%" cy="50%" innerRadius={55} outerRadius={85}
                    paddingAngle={3} dataKey="value" nameKey="name"
                    label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                    labelLine={false}
                  >
                    {chartBiaya.map((_, i) => (
                      <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(v) => formatRupiah(v)} />
                </PieChart>
              </ResponsiveContainer>
            </div>
          </div>
        )}
      </div>

      {/* ── TRANSAKSI TERAKHIR ──────────────────────────────────── */}
      <div className="card" style={{ marginTop: 'var(--space-lg)' }}>
        <div className="card-header">
          <span className="card-title">Transaksi Terakhir</span>
          <Link href="/transaksi/beli" className="btn btn-outline btn-sm">Lihat Semua</Link>
        </div>
        {loading ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {[1, 2, 3].map(i => <div key={i} className="skeleton" style={{ height: 44 }} />)}
          </div>
        ) : recentTransactions.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-icon">📦</div>
            <div className="empty-state-title">Belum ada transaksi</div>
            <div className="empty-state-text">Mulai input pembelian TBS dari petani</div>
          </div>
        ) : (
          <div className="table-container" style={{ border: 'none' }}>
            <table className="table">
              <thead>
                <tr>
                  <th>No. Struk</th><th>Petani</th>
                  <th style={{ textAlign: 'right' }}>Berat (kg)</th>
                  <th style={{ textAlign: 'right' }}>Total</th>
                </tr>
              </thead>
              <tbody>
                {recentTransactions.map(t => (
                  <tr key={t.id}>
                    <td className="table-mono">{t.no_struk || '-'}</td>
                    <td>{t.petani?.nama || '-'}</td>
                    <td className="table-mono" style={{ textAlign: 'right' }}>{formatNumber(t.berat_bersih)}</td>
                    <td className="table-mono" style={{ textAlign: 'right' }}>{formatRupiah(t.total_harga)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* ── AKSI CEPAT ─────────────────────────────────────────── */}
      <div style={{ marginTop: 'var(--space-xl)' }}>
        <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600, marginBottom: 'var(--space-md)', color: 'var(--text-secondary)' }}>
          Aksi Cepat
        </h3>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 'var(--space-md)' }}>
          <Link href="/transaksi/beli" className="card" style={{ textAlign: 'center', textDecoration: 'none', cursor: 'pointer' }}>
            <div style={{ fontSize: '2rem', marginBottom: 8 }}>📦</div>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Input TBS</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)' }}>Pembelian dari petani</div>
          </Link>
          <Link href="/keuangan/hutang" className="card" style={{ textAlign: 'center', textDecoration: 'none', cursor: 'pointer' }}>
            <div style={{ fontSize: '2rem', marginBottom: 8 }}>💳</div>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Kasbon Petani</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)' }}>Tambah hutang / panjar</div>
          </Link>
          <Link href="/transaksi/kirim" className="card" style={{ textAlign: 'center', textDecoration: 'none', cursor: 'pointer' }}>
            <div style={{ fontSize: '2rem', marginBottom: 8 }}>🚚</div>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Kirim ke Pabrik</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)' }}>Catat pengiriman TBS</div>
          </Link>
          <Link href="/keuangan/biaya" className="card" style={{ textAlign: 'center', textDecoration: 'none', cursor: 'pointer' }}>
            <div style={{ fontSize: '2rem', marginBottom: 8 }}>🔧</div>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Biaya Operasional</div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-tertiary)' }}>Solar, gaji, retribusi</div>
          </Link>
          <Link href="/master/harga" className="card" style={{ textAlign: 'center', textDecoration: 'none', cursor: 'pointer', borderColor: hargaHariIni ? 'var(--border-default)' : 'rgba(240,165,0,0.4)', background: hargaHariIni ? undefined : 'rgba(240,165,0,0.05)' }}>
            <div style={{ fontSize: '2rem', marginBottom: 8 }}>💲</div>
            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>Harga TBS</div>
            <div style={{ fontSize: 'var(--text-xs)', color: hargaHariIni ? 'var(--text-tertiary)' : 'var(--color-warning)' }}>
              {hargaHariIni ? `${formatRupiah(hargaHariIni.harga_per_kg)}/kg` : '⚠️ Belum diset'}
            </div>
          </Link>
        </div>
      </div>
    </AppShell>
  );
}
