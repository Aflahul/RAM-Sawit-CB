'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CheckCircle2, CreditCard, MessageCircle, Printer, RotateCcw, Send, X } from 'lucide-react';
import BrandMark from '@/components/branding/BrandMark';
import AppShell from '@/components/layout/AppShell';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import PromptDialog from '@/components/ui/PromptDialog';
import { formatMitraLabel, getMitraSearchText } from '@/lib/display-labels';
import { canApproveCorrections, canRecordMitraPayment, normalizeRole } from '@/lib/roles';
import { supabase } from '@/lib/supabase';
import {
  resolveBeratDibayar,
  resolveBeratNettoPabrik,
  resolveBiayaSewaArmada,
  resolveDanaOperasionalTrip,
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

function toNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function compactJoin(values, separator = ', ') {
  return values.map(value => String(value || '').trim()).filter(Boolean).join(separator);
}

function getRowMitraId(row) {
  return row?.master_mitra_id || row?.mitra_id || row?.master_mitra?.id || row?.transaksi?.mitra_id || '';
}

function getRowMitraLabel(row, selectedMitras = []) {
  const mitraId = getRowMitraId(row);
  const selectedMitra = selectedMitras.find(mitra => mitra.id === mitraId);
  return row?.mitra_label || row?.mitra_label_snapshot || formatMitraLabel(row?.master_mitra) || formatMitraLabel(selectedMitra) || 'Mitra';
}

function mapPaymentItemToRow(item) {
  const transaksi = item?.transaksi || {};
  const sewaSnapshot = toNumber(item.biaya_sewa_armada_snapshot);

  return {
    id: item.transaksi_mitra_id,
    master_mitra_id: item.master_mitra_id || transaksi.mitra_id || transaksi.master_mitra?.id,
    mitra_label: item.mitra_label_snapshot || formatMitraLabel(transaksi.master_mitra),
    tanggal: item.tanggal,
    created_at: item.waktu_transaksi,
    // berat (P0) — baca dari snapshot dulu, fallback ke transaksi live
    tonase: item.tonase_snapshot,
    berat_netto_pabrik_kg: item.berat_netto_snapshot ?? item.tonase_snapshot,
    potongan_pabrik_kg: item.potongan_snapshot ?? 0,
    berat_dibayar_kg: item.berat_dibayar_snapshot ?? item.tonase_snapshot,
    pakai_sewa_armada_bl: item.pakai_sewa_armada_snapshot ?? false,
    biaya_sewa_armada_total: sewaSnapshot,
    biaya_sewa_armada_kotor: sewaSnapshot,
    menggunakan_armada_cb_snapshot: Boolean(item.dana_operasional_trip_snapshot) || Boolean(item.pakai_sewa_armada_snapshot),
    catat_dana_operasional_trip: toNumber(item.dana_operasional_trip_snapshot) > 0,
    dana_operasional_trip_snapshot: item.dana_operasional_trip_snapshot ?? 0,
    tarif_sewa_angkut_per_kg_snapshot: item.tarif_sewa_angkut_per_kg_snapshot ?? 0,
    biaya_sewa_armada_standar_snapshot: item.biaya_sewa_armada_standar_snapshot ?? sewaSnapshot,
    selisih_sewa_armada_historis_snapshot: item.selisih_sewa_armada_historis_snapshot ?? 0,
    metode_sewa_armada_snapshot: item.metode_sewa_armada_snapshot || 'legacy_snapshot',
    is_kwitansi_snapshot: true,
    harga_bersih_per_kg: item.harga_bersih_per_kg_snapshot,
    total_nilai_bersih: item.total_nilai_bersih_snapshot,
    plat_nomor: item.plat_nomor,
    sopir_aktual_nama: item.sopir_aktual_nama,
    sopir_default_nama: '',
    sopir_diganti_dari_default: false,
    catatan_sopir: '',
    transaksi,
  };
}

function getSewaFormulaLabel(rows) {
  const sewaRows = rows.filter(row => resolveBiayaSewaArmada(row) > 0);
  if (sewaRows.length === 0) return '';

  if (sewaRows.some(row => row.metode_sewa_armada_snapshot === 'legacy_snapshot')) {
    return 'Nominal sesuai kwitansi saat diterbitkan';
  }

  const tariffs = [...new Set(
    sewaRows
      .map(row => toNumber(row.tarif_sewa_angkut_per_kg_snapshot))
      .filter(value => value > 0)
      .map(value => value.toFixed(2))
  )];

  if (tariffs.length === 1) {
    const totalBeratNetto = sewaRows.reduce(
      (sum, row) => sum + toNumber(resolveBeratNettoPabrik(row) || row.berat_netto_pabrik_kg || row.tonase),
      0
    );
    return `${formatNumber(totalBeratNetto)} kg x ${formatRupiah(Number(tariffs[0]))}/kg`;
  }

  return `Total ${sewaRows.length} transaksi sesuai tarif masing-masing`;
}

function buildWhatsappCaption({ appName, recipientLabel, dateFrom, dateTo, totalBeratNetto, totalBeratDibayar, totalNilaiBersih, totalPanjar, totalSewaArmada, sisaBersih }) {
  return [
    `Kwitansi Pembayaran ${appName}`,
    `Mitra: ${recipientLabel || '-'}`,
    `Periode: ${formatDateRangeDisplay(dateFrom, dateTo)}`,
    `Total Berat Netto: ${formatNumber(totalBeratNetto)} Kg`,
    `Total Berat Dibayar: ${formatNumber(totalBeratDibayar)} Kg`,
    `Total Nilai Bersih TBS: ${formatRupiah(totalNilaiBersih)}`,
    `Potongan Panjar Mitra: ${formatRupiah(totalPanjar)}`,
    `Potongan Sewa Armada CB: ${formatRupiah(totalSewaArmada)}`,
    `Sisa Dibayar ke Mitra: ${formatRupiah(sisaBersih)}`,
    '',
    'Mohon dicek. PDF kwitansi pembayaran terlampir.',
  ].join('\n');
}

export default function KwitansiMitraPage() {
  const { branding } = useBrandingSettings();
  const [mitras, setMitras] = useState([]);
  const [mitraPickerValue, setMitraPickerValue] = useState('');
  const [selectedMitraIds, setSelectedMitraIds] = useState([]);
  const [dateFrom, setDateFrom] = useState(getTodayISO);
  const [dateTo, setDateTo] = useState(getTodayISO);

  const [transaksi, setTransaksi] = useState([]);
  const [panjars, setPanjars] = useState([]);
  const [payment, setPayment] = useState(null);
  const [paymentHistoryCount, setPaymentHistoryCount] = useState(0);
  const [userRole, setUserRole] = useState(null);
  const [loading, setLoading] = useState(false);
  const [savingPayment, setSavingPayment] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [showWhatsappPreview, setShowWhatsappPreview] = useState(false);
  const [showPaymentModal, setShowPaymentModal] = useState(false);
  const [showCancelPayment, setShowCancelPayment] = useState(false);
  const [cancelingPayment, setCancelingPayment] = useState(false);
  const [paymentForm, setPaymentForm] = useState({ metode_bayar: 'tunai', catatan: '', penerima_label: '' });

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const mitraId = params.get('mitra');
    const dari = params.get('dari');
    const sampai = params.get('sampai');

    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (mitraId) setSelectedMitraIds([mitraId]);
    if (/^\d{4}-\d{2}-\d{2}$/.test(dari || '')) setDateFrom(dari);
    if (/^\d{4}-\d{2}-\d{2}$/.test(sampai || '')) setDateTo(sampai);
  }, []);

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

  const selectedMitras = useMemo(() => {
    const selectedSet = new Set(selectedMitraIds);
    return selectedMitraIds
      .map(id => mitras.find(mitra => mitra.id === id))
      .filter(Boolean)
      .filter(mitra => selectedSet.has(mitra.id));
  }, [mitras, selectedMitraIds]);

  const availableMitras = useMemo(() => {
    const selectedSet = new Set(selectedMitraIds);
    return mitras.filter(mitra => !selectedSet.has(mitra.id));
  }, [mitras, selectedMitraIds]);

  const isCombinedReceipt = selectedMitraIds.length > 1;
  const selectedMitraData = selectedMitras[0] || null;
  const selectedRecipientLabel = compactJoin(selectedMitras.map(formatMitraLabel));
  const recipientLabel = payment?.penerima_label || paymentForm.penerima_label.trim() || selectedRecipientLabel;

  const loadKwitansiData = useCallback(async () => {
    const mitraIds = selectedMitraIds.filter(Boolean);

    if (mitraIds.length === 0 || !dateFrom || !dateTo) {
      setTransaksi([]);
      setPanjars([]);
      setPayment(null);
      setPaymentHistoryCount(0);
      setErrorMsg('');
      return;
    }

    if (dateTo < dateFrom) {
      setTransaksi([]);
      setPanjars([]);
      setPayment(null);
      setPaymentHistoryCount(0);
      setErrorMsg('Tanggal akhir tidak boleh lebih awal dari tanggal awal.');
      return;
    }

    setLoading(true);
    setErrorMsg('');

    const [
      trxResult,
      paidItemResult,
      panjarResult,
      paymentResult,
    ] = await Promise.all([
      supabase
        .from('transaksi_mitra')
        .select(`
          id, mitra_id, tanggal, tonase, harga_harian, total_kotor,
          created_at,
          harga_pabrik_per_kg, fee_owner_per_kg, harga_bersih_per_kg,
          total_fee_owner, total_nilai_bersih, plat_nomor,
          berat_netto_pabrik_kg, potongan_pabrik_kg, berat_dibayar_kg,
          pakai_sewa_armada_bl, biaya_sewa_armada_total,
          biaya_sewa_armada_kotor, tarif_sewa_angkut_per_kg_snapshot,
          menggunakan_armada_cb_snapshot, catat_dana_operasional_trip,
          dana_operasional_trip_snapshot, total_biaya_sopir_cb_snapshot,
          sopir_default_nama, sopir_aktual_nama, sopir_diganti_dari_default, catatan_sopir,
          master_mitra ( id, kode, alamat, nama, fee_per_kg )
        `)
        .in('mitra_id', mitraIds)
        .gte('tanggal', dateFrom)
        .lte('tanggal', dateTo)
        .neq('status', 'dibatalkan')
        .order('tanggal', { ascending: true })
        .order('created_at', { ascending: true }),
      supabase
        .from('pembayaran_mitra_kwitansi_item')
        .select(`
          transaksi_mitra_id,
          master_mitra_id,
          pembayaran:pembayaran_id (
            id, status, tanggal_bayar, dibayar_at, metode_bayar, nominal_dibayar, penerima_label, mode_pembayaran
          )
        `)
        .in('master_mitra_id', mitraIds)
        .gte('tanggal', dateFrom)
        .lte('tanggal', dateTo),
      supabase
        .from('panjar_mitra')
        .select('id, mitra_id, tanggal, jumlah, keterangan, status, pembayaran_mitra_kwitansi_id, created_at')
        .in('mitra_id', mitraIds)
        .eq('status', 'belum_lunas')
        .order('tanggal', { ascending: true })
        .order('created_at', { ascending: true }),
      supabase
        .from('pembayaran_mitra_kwitansi')
        .select(`
          id, master_mitra_id, status, periode_dari, periode_sampai, tanggal_bayar, dibayar_at, metode_bayar,
          mode_pembayaran, mitra_ids, penerima_label, jumlah_mitra,
          total_tonase, total_berat_netto, total_berat_dibayar, total_nilai_bersih, total_panjar, total_sewa_armada, nominal_dibayar, jumlah_transaksi,
          nomor_bukti, review_reason, alasan_batal, reversal_kas_ledger_id,
          panjar_snapshot_json, transaksi_snapshot_json, catatan, created_at, rekening_kas_id, kas_ledger_id,
          items:pembayaran_mitra_kwitansi_item (
            transaksi_mitra_id, master_mitra_id, mitra_label_snapshot, tanggal, waktu_transaksi,
            sopir_aktual_nama, plat_nomor, tonase_snapshot, harga_bersih_per_kg_snapshot,
            total_nilai_bersih_snapshot, status_transaksi_snapshot,
            berat_netto_snapshot, potongan_snapshot, berat_dibayar_snapshot,
            pakai_sewa_armada_snapshot, biaya_sewa_armada_snapshot,
            dana_operasional_trip_snapshot,
            tarif_sewa_angkut_per_kg_snapshot, biaya_sewa_armada_standar_snapshot,
            selisih_sewa_armada_historis_snapshot, metode_sewa_armada_snapshot,
            transaksi:transaksi_mitra (
              id, mitra_id, status, updated_at,
              master_mitra ( id, kode, alamat, nama, fee_per_kg )
            )
          ),
          mitras:pembayaran_mitra_kwitansi_mitra (
            master_mitra_id, mitra_label_snapshot, total_tonase, total_berat_netto, total_berat_dibayar, total_nilai_bersih, jumlah_transaksi
          )
        `)
        .eq('periode_dari', dateFrom)
        .eq('periode_sampai', dateTo)
        .neq('status', 'dibatalkan')
        .order('created_at', { ascending: false })
        .limit(50),
    ]);

    const error = trxResult.error || paidItemResult.error || panjarResult.error || paymentResult.error;

    if (error) {
      console.error('Gagal memuat kwitansi mitra:', error);
      setTransaksi([]);
      setPanjars([]);
      setPayment(null);
      setPaymentHistoryCount(0);
      setErrorMsg(error.message);
      setLoading(false);
      return;
    }

    const paidTransactionIds = new Set(
      (paidItemResult.data || [])
        .filter(item => item.pembayaran && item.pembayaran.status !== 'dibatalkan')
        .map(item => item.transaksi_mitra_id)
    );
    const unpaidTransactions = (trxResult.data || []).filter(row => !paidTransactionIds.has(row.id));
    const selectedSet = new Set(mitraIds);
    const relatedPayments = (paymentResult.data || []).filter((row) => {
      const paymentMitraIds = [
        row.master_mitra_id,
        ...(row.mitra_ids || []),
        ...(row.items || []).map(item => item.master_mitra_id),
        ...(row.mitras || []).map(item => item.master_mitra_id),
      ].filter(Boolean);
      return paymentMitraIds.some(id => selectedSet.has(id));
    });

    setTransaksi(unpaidTransactions);
    setPanjars(panjarResult.data || []);
    setPayment(relatedPayments[0] || null);
    setPaymentHistoryCount(relatedPayments.length);
    setLoading(false);
  }, [dateFrom, dateTo, selectedMitraIds]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadMitras();
    checkRole();
  }, [checkRole, loadMitras]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadKwitansiData();
  }, [loadKwitansiData]);

  const isShowingPaidSnapshot = transaksi.length === 0 && Boolean(payment);
  const kwitansiRows = useMemo(() => {
    if (transaksi.length > 0) {
      return transaksi.map(row => ({
        ...row,
        master_mitra_id: row.mitra_id,
        mitra_label: formatMitraLabel(row.master_mitra),
      }));
    }

    if (!payment) return [];

    return [...(payment.items || [])]
      .sort((a, b) => `${a.mitra_label_snapshot || ''} ${a.tanggal || ''} ${a.waktu_transaksi || ''}`
        .localeCompare(`${b.mitra_label_snapshot || ''} ${b.tanggal || ''} ${b.waktu_transaksi || ''}`))
      .map(mapPaymentItemToRow);
  }, [payment, transaksi]);

  const panjarRows = useMemo(() => {
    if (!isShowingPaidSnapshot) {
      return panjars
        .filter(row => row.status === 'belum_lunas')
        .map(row => ({
          ...row,
          master_mitra_id: row.mitra_id,
          mitra_label: getRowMitraLabel({ ...row, master_mitra_id: row.mitra_id }, selectedMitras),
        }));
    }

    const panjarById = new Map(panjars.map(row => [row.id, row]));
    const paymentMitraIds = [...new Set([
      payment?.master_mitra_id,
      ...(payment?.mitra_ids || []),
      ...(payment?.items || []).map(item => item.master_mitra_id),
      ...(payment?.mitras || []).map(item => item.master_mitra_id),
    ].filter(Boolean))];
    const singlePaymentMitraId = paymentMitraIds.length === 1 ? paymentMitraIds[0] : '';
    const snapshot = Array.isArray(payment?.panjar_snapshot_json) ? payment.panjar_snapshot_json : [];
    return snapshot.map(row => {
      const linkedPanjar = panjarById.get(row.id);
      const masterMitraId = row.master_mitra_id || row.mitra_id || linkedPanjar?.mitra_id || singlePaymentMitraId;
      return {
        ...row,
        master_mitra_id: masterMitraId,
        mitra_label: row.mitra_label || getRowMitraLabel({ ...linkedPanjar, master_mitra_id: masterMitraId }, selectedMitras),
      };
    });
  }, [isShowingPaidSnapshot, panjars, payment, selectedMitras]);

  const kwitansiGrouping = useMemo(() => {
    const groups = new Map();
    const unassignedPanjars = [];
    const selectedOrder = new Map(selectedMitraIds.map((id, index) => [id, index]));

    function ensureGroup(row) {
      const mitraId = getRowMitraId(row);
      const selectedMitra = selectedMitras.find(mitra => mitra.id === mitraId);
      const mitra = row?.master_mitra || row?.transaksi?.master_mitra || selectedMitra;
      const label = getRowMitraLabel(row, selectedMitras);
      const safeId = mitraId || `unknown-${label || groups.size}`;
      if (!groups.has(safeId)) {
        groups.set(safeId, {
          mitraId: safeId,
          label: label || 'Mitra',
          nama: mitra?.nama || '',
          kodeLabel: compactJoin([mitra?.kode, mitra?.alamat]) || label || 'Mitra',
          rows: [],
          panjars: [],
          totalBeratNetto: 0,
          totalBeratDibayar: 0,
          totalNilaiBersih: 0,
          totalPanjar: 0,
          totalDanaOperasionalTrip: 0,
        });
      } else {
        const group = groups.get(safeId);
        if (!group.nama && mitra?.nama) group.nama = mitra.nama;
        if ((!group.kodeLabel || group.kodeLabel === group.label) && (mitra?.kode || mitra?.alamat)) {
          group.kodeLabel = compactJoin([mitra?.kode, mitra?.alamat]);
        }
      }

      return groups.get(safeId);
    }

    kwitansiRows.forEach((row) => {
      const group = ensureGroup(row);
      const totalNilaiBersih = resolveTotalNilaiBersihMitra(row);
      const sewaArmada = resolveBiayaSewaArmada(row);
      const danaOperasionalTrip = resolveDanaOperasionalTrip(row);

      group.rows.push(row);
      group.totalBeratNetto += resolveBeratNettoPabrik(row);
      group.totalBeratDibayar += resolveBeratDibayar(row);
      group.totalNilaiBersih += totalNilaiBersih;
      group.totalSewaArmada = (group.totalSewaArmada || 0) + sewaArmada;
      group.totalDanaOperasionalTrip += danaOperasionalTrip;
    });

    panjarRows.forEach((row) => {
      const mitraId = getRowMitraId(row);
      const group = groups.get(mitraId)
        || (!mitraId && groups.size === 1 ? groups.values().next().value : null);

      if (!group) {
        unassignedPanjars.push(row);
        return;
      }

      const jumlah = toNumber(row.jumlah);

      group.panjars.push(row);
      group.totalPanjar += jumlah;
    });

    const sortedGroups = [...groups.values()]
      .filter(group => group.rows.length > 0)
      .sort((a, b) => {
        const aOrder = selectedOrder.has(a.mitraId) ? selectedOrder.get(a.mitraId) : 999;
        const bOrder = selectedOrder.has(b.mitraId) ? selectedOrder.get(b.mitraId) : 999;
        if (aOrder !== bOrder) return aOrder - bOrder;
        return a.label.localeCompare(b.label);
      });

    return { groups: sortedGroups, unassignedPanjars };
  }, [kwitansiRows, panjarRows, selectedMitraIds, selectedMitras]);

  const kwitansiGroups = kwitansiGrouping.groups;
  const unassignedPanjars = kwitansiGrouping.unassignedPanjars;

  const currentTotalBeratNetto = kwitansiGroups.reduce((sum, group) => sum + group.totalBeratNetto, 0);
  const currentTotalBeratDibayar = kwitansiGroups.reduce((sum, group) => sum + group.totalBeratDibayar, 0);
  const currentTotalNilaiBersih = kwitansiGroups.reduce((sum, group) => sum + group.totalNilaiBersih, 0);
  const currentTotalPanjar = kwitansiGroups.reduce((sum, group) => sum + group.totalPanjar, 0);
  const currentTotalSewaArmada = kwitansiGroups.reduce((sum, group) => sum + (group.totalSewaArmada || 0), 0);
  const displayTotalDanaOperasionalTrip = kwitansiGroups.reduce(
    (sum, group) => sum + (group.totalDanaOperasionalTrip || 0),
    0,
  );
  const displayTotalBeratNetto = isShowingPaidSnapshot
    ? toNumber(payment?.total_berat_netto ?? payment?.total_tonase)
    : currentTotalBeratNetto;
  const displayTotalBeratDibayar = isShowingPaidSnapshot
    ? toNumber(payment?.total_berat_dibayar ?? payment?.total_tonase)
    : currentTotalBeratDibayar;
  const displayTotalNilaiBersih = isShowingPaidSnapshot ? toNumber(payment?.total_nilai_bersih) : currentTotalNilaiBersih;
  const displayTotalPanjar = isShowingPaidSnapshot ? toNumber(payment?.total_panjar) : currentTotalPanjar;
  const displayTotalSewaArmada = isShowingPaidSnapshot ? toNumber(payment?.total_sewa_armada) : currentTotalSewaArmada;
  const totalSelisihSewaHistoris = isShowingPaidSnapshot
    ? kwitansiRows.reduce((sum, row) => sum + toNumber(row.selisih_sewa_armada_historis_snapshot), 0)
    : 0;
  const sisaBersih = isShowingPaidSnapshot
    ? toNumber(payment?.nominal_dibayar)
    : displayTotalNilaiBersih - displayTotalPanjar - displayTotalSewaArmada;
  const isPaymentCashMissing = Boolean(isShowingPaidSnapshot && toNumber(payment?.nominal_dibayar) > 0 && !payment?.kas_ledger_id);
  const canRecordPayment = canRecordMitraPayment(userRole);
  const canCancelPayment = canApproveCorrections(userRole);
  const displayPeriode = formatDateRangeDisplay(dateFrom, dateTo);
  const hasNewUnpaidAfterPayment = Boolean(payment && transaksi.length > 0);
  const groupsOverPayable = kwitansiGroups.filter(group => (
    group.totalPanjar + (group.totalSewaArmada || 0) > group.totalNilaiBersih
  ));
  const hasDraftAllocationIssue = !isShowingPaidSnapshot
    && (unassignedPanjars.length > 0 || groupsOverPayable.length > 0);

  const paymentReview = useMemo(() => {
    if (hasNewUnpaidAfterPayment) {
      return {
        status: 'perlu_review',
        label: 'Ada Kwitansi Sebelumnya',
        reason: 'Data di bawah hanya transaksi baru yang belum dibayar. Transaksi yang sudah masuk kwitansi lama tidak ikut lagi.',
      };
    }

    if (payment) {
      return {
        status: payment.status === 'perlu_review' ? 'perlu_review' : 'dibayar',
        label: payment.status === 'perlu_review' ? 'Perlu Review' : 'Sudah Dibayar',
        reason: payment.status === 'perlu_review' ? (payment.review_reason || 'Kwitansi lama perlu dicek ulang.') : '',
      };
    }

    return {
      status: 'belum_dibayar',
      label: transaksi.length > 0 ? 'Belum Dibayar' : 'Belum Ada Transaksi Baru',
      reason: transaksi.length > 0
        ? 'Klik Tandai Dibayar setelah owner benar-benar membayar mitra.'
        : 'Pilih periode lain atau tunggu transaksi baru masuk.',
    };
  }, [hasNewUnpaidAfterPayment, payment, transaksi.length]);

  const whatsappNumber = normalizeWhatsappNumber(selectedMitraData?.no_hp);
  const whatsappNumberValid = isValidWhatsappNumber(whatsappNumber);
  const whatsappCaption = buildWhatsappCaption({
    appName: branding.appName,
    recipientLabel,
    dateFrom,
    dateTo,
    totalBeratNetto: displayTotalBeratNetto,
    totalBeratDibayar: displayTotalBeratDibayar,
    totalNilaiBersih: displayTotalNilaiBersih,
    totalPanjar: displayTotalPanjar,
    totalSewaArmada: displayTotalSewaArmada,
    sisaBersih,
  });
  const canSendWhatsapp = Boolean(isShowingPaidSnapshot && selectedMitraIds.length === 1 && kwitansiRows.length > 0 && whatsappNumberValid);
  const whatsappWarning = !isShowingPaidSnapshot && kwitansiRows.length > 0
    ? 'WhatsApp resmi tersedia setelah pembayaran disimpan. Draft tetap dapat dicetak dengan cap belum dibayar.'
    : selectedMitraIds.length > 1 && kwitansiRows.length > 0
    ? 'WhatsApp otomatis hanya untuk satu mitra. Untuk kwitansi gabungan, cetak atau simpan PDF lalu kirim manual.'
    : selectedMitraIds.length === 1 && kwitansiRows.length > 0 && !whatsappNumberValid
      ? selectedMitraData?.no_hp
        ? 'Nomor WA penanggung jawab mitra belum valid. Perbarui nomor di menu Mitra.'
        : 'Nomor WA penanggung jawab mitra belum diisi. Lengkapi nomor di menu Mitra.'
      : '';

  function addSelectedMitra(mitraId) {
    if (!mitraId) return;
    setSelectedMitraIds(current => current.includes(mitraId) ? current : [...current, mitraId]);
    setMitraPickerValue('');
  }

  function removeSelectedMitra(mitraId) {
    setSelectedMitraIds(current => current.filter(id => id !== mitraId));
    setPaymentForm(current => ({ ...current, penerima_label: '' }));
  }

  const handlePrint = () => {
    window.print();
  };

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
    if (selectedMitraIds.length === 0 || transaksi.length === 0 || savingPayment || hasDraftAllocationIssue) return;

    const finalRecipientLabel = paymentForm.penerima_label.trim() || selectedRecipientLabel;

    setSavingPayment(true);
    setErrorMsg('');

    const { error } = await supabase.rpc('create_pembayaran_mitra_kwitansi', {
      p_master_mitra_id: selectedMitraIds[0],
      p_master_mitra_ids: selectedMitraIds,
      p_penerima_label: finalRecipientLabel,
      p_periode_dari: dateFrom,
      p_periode_sampai: dateTo,
      p_metode_bayar: paymentForm.metode_bayar,
      p_catatan: paymentForm.catatan || null,
    });

    if (error) {
      setErrorMsg(`Gagal menandai dibayar: ${error.message}`);
      setSavingPayment(false);
      return;
    }

    setShowPaymentModal(false);
    setPaymentForm({ metode_bayar: 'tunai', catatan: '', penerima_label: '' });
    await loadKwitansiData();
    setSavingPayment(false);
  };

  const handleCancelPayment = async (reason) => {
    if (!payment?.id || cancelingPayment) return;

    setCancelingPayment(true);
    setErrorMsg('');
    const { error } = await supabase.rpc('cancel_pembayaran_mitra_kwitansi', {
      p_payment_id: payment.id,
      p_reason: reason,
    });

    if (error) {
      setErrorMsg(`Gagal membatalkan kwitansi: ${error.message}`);
      setCancelingPayment(false);
      return;
    }

    setShowCancelPayment(false);
    await loadKwitansiData();
    setCancelingPayment(false);
  };

  return (
    <AppShell title="Kwitansi Mitra" subtitle="Dashboard & Cetak Invoice Mitra">
      <div className="page-header no-print">
        <div>
          <p className="page-description">Pilih satu atau beberapa mitra, lalu sistem hanya mengambil transaksi yang belum dibayar.</p>
        </div>
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
          {canRecordPayment && (
            <button
              className="btn btn-outline"
              onClick={() => setShowPaymentModal(true)}
              disabled={selectedMitraIds.length === 0 || transaksi.length === 0 || savingPayment || hasDraftAllocationIssue}
            >
              <CreditCard size={16} />
              Tandai Dibayar
            </button>
          )}
          {canCancelPayment && isShowingPaidSnapshot && payment?.status !== 'dibatalkan' && (
            <button className="btn btn-outline" onClick={() => setShowCancelPayment(true)} disabled={cancelingPayment}>
              <RotateCcw size={16} />
              Batalkan Pembayaran
            </button>
          )}
          <button className="btn btn-outline" onClick={handleOpenWhatsappPreview} disabled={!canSendWhatsapp}>
            <MessageCircle size={16} />
            Kirim WhatsApp
          </button>
          <button className="btn btn-primary" onClick={handlePrint} disabled={selectedMitraIds.length === 0 || kwitansiRows.length === 0}>
            <Printer size={16} />
            Cetak PDF / Struk
          </button>
        </div>
      </div>

      <div className="toolbar no-print card" style={{ padding: 'var(--space-md)', marginBottom: 'var(--space-lg)', display: 'grid', gap: 16, gridTemplateColumns: 'minmax(260px, 1fr) auto auto' }}>
        <div style={{ minWidth: 0 }}>
          <label style={{ display: 'block', fontSize: 14, fontWeight: 600, marginBottom: 8 }}>Mitra untuk Kwitansi</label>
          <SearchableCombobox
            value={mitraPickerValue}
            options={availableMitras}
            onChange={addSelectedMitra}
            getOptionLabel={formatMitraLabel}
            getSearchText={getMitraSearchText}
            placeholder="Cari dan tambah mitra..."
            emptyLabel="Semua mitra sudah dipilih"
          />
          {selectedMitras.length > 0 && (
            <div className="kwitansi-selected-mitras">
              {selectedMitras.map(mitra => (
                <span key={mitra.id} className="kwitansi-mitra-chip">
                  {formatMitraLabel(mitra)}
                  <button type="button" onClick={() => removeSelectedMitra(mitra.id)} aria-label={`Hapus ${formatMitraLabel(mitra)}`}>
                    <X size={14} />
                  </button>
                </span>
              ))}
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => setSelectedMitraIds([])}>
                Bersihkan
              </button>
            </div>
          )}
        </div>
        <div>
          <label style={{ display: 'block', fontSize: 14, fontWeight: 600, marginBottom: 8 }}>Dari Tanggal</label>
          <input type="date" className="form-input" value={dateFrom} onChange={event => setDateFrom(event.target.value)} />
        </div>
        <div>
          <label style={{ display: 'block', fontSize: 14, fontWeight: 600, marginBottom: 8 }}>Sampai Tanggal</label>
          <input type="date" className="form-input" value={dateTo} onChange={event => setDateTo(event.target.value)} />
        </div>
      </div>

      {loading && <div style={{ textAlign: 'center', padding: 40 }}>Memuat data kwitansi...</div>}

      {!loading && errorMsg && (
        <div className="alert alert-warning no-print">
          <AlertTriangle size={18} />
          <div>{errorMsg}</div>
        </div>
      )}

      {!loading && !errorMsg && whatsappWarning && (
        <div className="alert alert-warning no-print">
          <div>
            <strong>Pengiriman WhatsApp perlu manual.</strong>
            <div style={{ marginTop: 4 }}>{whatsappWarning}</div>
          </div>
        </div>
      )}

      {!loading && !errorMsg && unassignedPanjars.length > 0 && (
        <div className="alert alert-warning no-print">
          <AlertTriangle size={18} />
          <div>
            <strong>Ada panjar yang belum dapat dipasangkan ke mitra transaksi.</strong>
            <div style={{ marginTop: 4 }}>
              Panjar tidak dibuat sebagai blok mitra kosong dan pembayaran baru dikunci. Periksa pemilik panjar dari menu Pinjaman & Panjar.
            </div>
          </div>
        </div>
      )}

      {!loading && !errorMsg && groupsOverPayable.length > 0 && (
        <div className="alert alert-warning no-print">
          <AlertTriangle size={18} />
          <div>
            <strong>Potongan salah satu mitra melebihi hak pembayarannya.</strong>
            <div style={{ marginTop: 4 }}>
              {groupsOverPayable.map(group => group.nama || group.label).join(', ')} harus diselesaikan sendiri; hak mitra lain dalam kwitansi gabungan tidak boleh dipakai menutup panjarnya.
            </div>
          </div>
        </div>
      )}

      {!loading && !errorMsg && selectedMitraIds.length > 0 && (
        <div className={`alert no-print ${paymentReview.status === 'dibayar' ? 'alert-success' : paymentReview.status === 'perlu_review' ? 'alert-warning' : 'alert-info'}`}>
          {paymentReview.status === 'dibayar' ? <CheckCircle2 size={18} /> : paymentReview.status === 'perlu_review' ? <AlertTriangle size={18} /> : <CreditCard size={18} />}
          <div>
            <strong>Status Pembayaran: {paymentReview.label}</strong>
            {payment ? (
              <div style={{ marginTop: 4 }}>
                Kwitansi terakhir dibayar {formatDateDisplay(payment.tanggal_bayar)} {formatWaktu(payment.dibayar_at)} via {payment.metode_bayar}
                {' '}sebesar <span className="table-mono">{formatRupiah(payment.nominal_dibayar)}</span>.
                {paymentHistoryCount > 1 ? ` Ada ${paymentHistoryCount} kwitansi pada periode ini.` : ''}
                {paymentReview.reason ? ` ${paymentReview.reason}` : ''}
              </div>
            ) : (
              <div style={{ marginTop: 4 }}>{paymentReview.reason}</div>
            )}
          </div>
        </div>
      )}

      {!loading && !errorMsg && selectedMitraIds.length > 0 && isPaymentCashMissing && (
        <div className="alert alert-warning no-print">
          <AlertTriangle size={18} />
          <div>
            <strong>Kas keluar belum tercatat di Buku Kas.</strong>
            <div style={{ marginTop: 4 }}>
              Kwitansi ini sudah dibayar, tetapi belum terhubung ke mutasi kas. Jalankan migration backfill agar pembayaran muncul di Buku Kas dan Laba/Rugi.
            </div>
          </div>
        </div>
      )}

      {!loading && !errorMsg && isShowingPaidSnapshot && Math.abs(totalSelisihSewaHistoris) > 0.01 && (
        <div className="alert alert-info no-print">
          <AlertTriangle size={18} />
          <div>
            <strong>Kwitansi memakai nilai historis yang sudah dibekukan.</strong>
            <div style={{ marginTop: 4 }}>
              Ada selisih perhitungan sewa {formatRupiah(Math.abs(totalSelisihSewaHistoris))} terhadap rumus sekarang. Nilai kwitansi dan Buku Kas tetap mengikuti nominal saat pembayaran dibuat.
            </div>
          </div>
        </div>
      )}

      {!loading && !errorMsg && selectedMitraIds.length > 0 && (
        <div className="print-area card kwitansi-preview" style={{ padding: 'var(--space-xl)' }}>
          <div className="kwitansi-doc-header">
            <BrandMark branding={branding} mode="print" size={120} className="kwitansi-logo" />
            <div className="kwitansi-header-info">
              <div className="kwitansi-title-block">
                <h1 className="kwitansi-title">
                  <span>KWITANSI PEMBAYARAN TBS</span>
                </h1>
                <p className="kwitansi-brand-name">{branding.appName}</p>
              </div>
              {payment ? (
                <div className="kwitansi-paid-stamp" style={{ marginLeft: 'auto' }}>
                  {paymentReview.status === 'perlu_review' ? 'PERLU REVIEW' : 'SUDAH DIBAYAR'}
                </div>
              ) : kwitansiRows.length > 0 ? (
                <div className="kwitansi-paid-stamp kwitansi-draft-stamp" style={{ marginLeft: 'auto' }}>DRAFT - BELUM DIBAYAR</div>
              ) : null}
            </div>
          </div>

          {kwitansiRows.length === 0 ? (
            <div className="kwitansi-empty">
              Tidak ada transaksi baru yang belum dibayar pada periode ini.
            </div>
          ) : (
            <>
              {kwitansiGroups.map((group) => (
                <section key={group.mitraId} className="kwitansi-group">
                  <div className="kwitansi-group-header" style={{ display: 'flex', flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: '8px 16px', justifyContent: 'space-between', marginBottom: 12 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
                      <div>
                        <h3 style={{ margin: 0, fontSize: 15 }}>{group.nama || 'Nama mitra belum diisi'}</h3>
                        <div style={{ color: 'var(--text-secondary)', fontSize: 12, fontWeight: 700, marginTop: 2 }}>{group.kodeLabel}</div>
                      </div>
                      <div style={{ color: 'var(--text-secondary)', fontSize: 12, fontWeight: 600 }}>Periode: {displayPeriode}</div>
                      <div style={{ color: 'var(--text-tertiary)', fontSize: 12 }}>{group.rows.length} transaksi, {formatNumber(group.totalBeratDibayar)} kg dibayar</div>
                    </div>
                    <div className="kwitansi-group-subtotal" style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 'auto', textAlign: 'right' }}>
                      <span style={{ fontSize: 12, display: 'inline', color: 'var(--text-tertiary)' }}>Bayar ke mitra:</span>
                      <strong style={{ fontSize: 14, display: 'inline', marginTop: 0, color: 'var(--color-success)' }}>{formatRupiah(group.totalNilaiBersih - group.totalPanjar - (group.totalSewaArmada || 0))}</strong>
                    </div>
                  </div>

                  <div className="kwitansi-table-wrap">
                    <table className="kwitansi-detail-table">
                      <thead>
                        <tr>
                          <th>Tanggal</th>
                          <th>Armada</th>
                          <th style={{ textAlign: 'right' }}>Tonase</th>
                          <th style={{ textAlign: 'right' }}>Harga/Kg</th>
                          <th style={{ textAlign: 'right' }}>Bersih</th>
                        </tr>
                      </thead>
                      <tbody>
                        {group.rows.map((row) => {
                          const beratNetto   = resolveBeratNettoPabrik(row);
                          const potongan     = toNumber(row.potongan_pabrik_kg);
                          const beratDibayar = resolveBeratDibayar(row);
                          const sewaArmada   = resolveBiayaSewaArmada(row);
                          return (
                          <tr key={row.id}>
                            <td>
                              <div style={{ fontWeight: 700 }}>{formatDateDisplay(row.tanggal)}</div>
                              <div className="table-mono" style={{ marginTop: 4, fontSize: 12, color: 'var(--text-tertiary)' }}>{formatWaktu(row.created_at)}</div>
                            </td>
                            <td>
                              <div style={{ fontWeight: 600 }}>{row.sopir_aktual_nama || row.sopir_default_nama || '-'}</div>
                              <div className="table-mono" style={{ marginTop: 4, fontSize: 12, color: 'var(--text-tertiary)' }}>{row.plat_nomor || '-'}</div>
                              {row.sopir_diganti_dari_default && (
                                <div style={{ fontSize: 10, fontStyle: 'italic', color: 'var(--text-tertiary)', marginTop: 2, lineHeight: 1.2 }}>
                                  Pengganti dari {row.sopir_default_nama || '-'}
                                  {row.catatan_sopir ? ` - ${row.catatan_sopir}` : ''}
                                </div>
                              )}
                            </td>
                            <td style={{ textAlign: 'right' }}>
                              <div>{formatNumber(beratNetto)}</div>
                              {potongan > 0 && <div style={{ fontSize: 11, color: 'var(--color-warning)' }}>-{formatNumber(potongan)} ptg</div>}
                              <div style={{ fontWeight: 700 }}>{formatNumber(beratDibayar)}</div>
                            </td>
                            <td style={{ textAlign: 'right' }} className="table-mono">{formatRupiah(resolveHargaBersihPerKg(row))}</td>
                            <td style={{ textAlign: 'right' }} className="table-mono">
                              {formatRupiah(resolveTotalNilaiBersihMitra(row))}
                            </td>
                          </tr>
                          );
                        })}
                      </tbody>
                      <tfoot>
                        <tr>
                          <td colSpan={2} style={{ textAlign: 'right' }}>Subtotal nilai bersih:</td>
                          <td style={{ textAlign: 'right' }}>
                            <div>{formatNumber(group.totalBeratNetto)} kg netto</div>
                            <strong>{formatNumber(group.totalBeratDibayar)} kg dibayar</strong>
                          </td>
                          <td></td>
                          <td style={{ textAlign: 'right' }} className="table-mono">{formatRupiah(group.totalNilaiBersih)}</td>
                        </tr>
                      </tfoot>
                    </table>
                  </div>



                  {group.panjars.length > 0 && (
                    <div className="kwitansi-panjar-list">
                      <strong>Rincian panjar:</strong>
                      {group.panjars.map(panjar => (
                        <span key={panjar.id}>
                          {formatDateDisplay(panjar.tanggal)} - {formatRupiah(panjar.jumlah)}
                          {panjar.keterangan ? ` (${panjar.keterangan})` : ''}
                        </span>
                      ))}
                    </div>
                  )}
                </section>
              ))}

              <div className="kwitansi-total-row">
                <div className="kwitansi-total-box">
                  <div>
                    <span>Total Berat Netto</span>
                    <strong className="table-mono">{formatNumber(displayTotalBeratNetto)} kg</strong>
                  </div>
                  <div>
                    <span>Total Berat Dibayar</span>
                    <strong className="table-mono">{formatNumber(displayTotalBeratDibayar)} kg</strong>
                  </div>
                  <div>
                    <span>Total Nilai Bersih TBS</span>
                    <strong className="table-mono">{formatRupiah(displayTotalNilaiBersih)}</strong>
                  </div>
                  {displayTotalSewaArmada > 0 && (
                    kwitansiGroups.length > 1
                      ? kwitansiGroups.filter(g => (g.totalSewaArmada || 0) > 0).map(g => {
                          return (
                            <div key={g.mitraId}>
                              <span>
                                Potongan Sewa Armada CB
                                <span style={{ fontSize: 10, color: 'var(--text-tertiary)', display: 'block', fontWeight: 400 }}>{g.label}</span>
                                <span style={{ display: 'block', fontSize: 10, color: 'var(--text-tertiary)', marginTop: 2, fontWeight: 'normal', border: 'none', padding: 0, background: 'transparent' }}>
                                  {getSewaFormulaLabel(g.rows)}
                                </span>
                              </span>
                              <strong className="table-mono danger-text">- {formatRupiah(g.totalSewaArmada || 0)}</strong>
                            </div>
                          );
                        })
                      : (
                            <div>
                              <span>
                                Potongan Sewa Armada CB
                                <span style={{ display: 'block', fontSize: 10, color: 'var(--text-tertiary)', marginTop: 2, fontWeight: 'normal', border: 'none', padding: 0, background: 'transparent' }}>
                                  {getSewaFormulaLabel(kwitansiRows)}
                                </span>
                              </span>
                              <strong className="table-mono danger-text">- {formatRupiah(displayTotalSewaArmada)}</strong>
                            </div>
                        )
                  )}
                  {displayTotalPanjar > 0 && (
                    kwitansiGroups.length > 1
                      ? kwitansiGroups.filter(g => g.totalPanjar > 0).map(g => (
                          <div key={g.mitraId}>
                            <span>
                              Potongan Panjar Mitra
                              <span style={{ fontSize: 10, color: 'var(--text-tertiary)', display: 'block', fontWeight: 400 }}>{g.label}</span>
                            </span>
                            <strong className="table-mono danger-text">- {formatRupiah(g.totalPanjar)}</strong>
                          </div>
                        ))
                      : <div>
                          <span>Potongan Panjar Mitra</span>
                          <strong className="table-mono danger-text">- {formatRupiah(displayTotalPanjar)}</strong>
                        </div>
                  )}
                  {displayTotalDanaOperasionalTrip > 0 && (
                    kwitansiGroups.length > 1
                      ? kwitansiGroups.filter(g => (g.totalDanaOperasionalTrip || 0) > 0).map(g => (
                          <div key={g.mitraId}>
                            <span>
                              Dana Operasional Trip
                              <span style={{ fontSize: 10, color: 'var(--text-tertiary)', display: 'block', fontWeight: 400 }}>
                                {g.label} · biaya CB, dibayar terpisah
                              </span>
                            </span>
                            <strong className="table-mono">{formatRupiah(g.totalDanaOperasionalTrip)}</strong>
                          </div>
                        ))
                      : <div>
                          <span>
                            Dana Operasional Trip
                            <span style={{ fontSize: 10, color: 'var(--text-tertiary)', display: 'block', fontWeight: 400 }}>
                              Biaya CB, dibayar terpisah; bukan potongan tambahan mitra
                            </span>
                          </span>
                          <strong className="table-mono">{formatRupiah(displayTotalDanaOperasionalTrip)}</strong>
                        </div>
                  )}
                  <div className="kwitansi-total-divider"></div>
                  <div className="kwitansi-final-total">
                    <span>Sisa Dibayar ke Mitra</span>
                    <strong className="table-mono">{formatRupiah(sisaBersih)}</strong>
                  </div>
                </div>
              </div>
            </>
          )}

          {payment && (
            <div className="kwitansi-payment-note">
              <strong>Status Pembayaran:</strong>{' '}
              {paymentReview.status === 'perlu_review' ? 'Perlu review' : 'Sudah dibayar'} pada {formatDateDisplay(payment.tanggal_bayar)} {formatWaktu(payment.dibayar_at)} via {payment.metode_bayar}.
              {payment.catatan ? ` Catatan: ${payment.catatan}` : ''}
            </div>
          )}

          <div className="kwitansi-print-footer">
            Dicetak otomatis oleh Sistem {branding.appName} pada {formatDateTimeDisplay(new Date())}
          </div>
        </div>
      )}

      <style jsx global>{`
        .kwitansi-selected-mitras {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
          margin-top: 10px;
        }
        .kwitansi-mitra-chip {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          max-width: 100%;
          padding: 6px 10px;
          border: 1px solid var(--border-default);
          border-radius: 999px;
          background: var(--bg-surface);
          color: var(--text-primary);
          font-size: 13px;
          line-height: 1.25;
        }
        .kwitansi-mitra-chip button {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 20px;
          height: 20px;
          border: 0;
          border-radius: 999px;
          background: transparent;
          color: var(--text-tertiary);
          cursor: pointer;
        }
        .kwitansi-mitra-chip button:hover {
          background: var(--bg-input);
          color: var(--text-primary);
        }
        .kwitansi-draft-stamp {
          border-color: var(--color-warning) !important;
          color: var(--color-warning) !important;
        }
        .kwitansi-doc-header {
          display: flex;
          align-items: center;
          gap: 16px;
          padding-bottom: 20px;
          margin-bottom: 20px;
          border-bottom: 2px dashed var(--border-default);
        }
        .kwitansi-header-info {
          display: flex;
          align-items: flex-start;
          gap: 24px;
          flex: 1 1 auto;
          min-width: 0;
        }
        .kwitansi-title-block {
          flex: 0 0 auto;
        }
        .kwitansi-title {
          display: flex;
          flex-direction: column;
          gap: 2px;
          margin: 0;
          font-size: 22px;
          line-height: 1.18;
          color: var(--text-primary);
        }
        .kwitansi-brand-name {
          margin: 6px 0 0;
          color: var(--text-secondary);
        }
        .kwitansi-recipient {
          margin-left: auto;
          text-align: left;
          max-width: 460px;
        }
        .kwitansi-recipient h2 {
          margin: 4px 0 0;
          font-size: 20px;
          line-height: 1.25;
          color: var(--text-primary);
        }
        .kwitansi-paid-stamp {
          display: inline-flex;
          margin-top: 10px;
          padding: 6px 10px;
          border: 1px solid #111;
          border-radius: 6px;
          color: #111;
          font-weight: 800;
        }
        .kwitansi-empty {
          padding: 32px;
          text-align: center;
          color: var(--text-tertiary);
          border: 1px dashed var(--border-default);
          border-radius: 8px;
        }
        .kwitansi-group {
          padding: 18px 0;
        }
        .kwitansi-group:first-of-type {
          padding-top: 0;
        }
        .kwitansi-group-header {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: 16px;
          margin-bottom: 12px;
        }
        .kwitansi-group-header h3 {
          margin: 0;
          font-size: 16px;
          color: var(--text-primary);
        }
        .kwitansi-group-header p {
          margin: 4px 0 0;
          color: var(--text-tertiary);
          font-size: 13px;
        }
        .kwitansi-group-subtotal {
          min-width: 180px;
          text-align: right;
        }
        .kwitansi-group-subtotal span {
          display: block;
          color: var(--text-tertiary);
          font-size: 12px;
        }
        .kwitansi-group-subtotal strong {
          display: block;
          margin-top: 3px;
          font-size: 16px;
          color: var(--color-success);
        }
        .kwitansi-table-wrap {
          overflow-x: auto;
        }
        .kwitansi-detail-table {
          width: 100%;
          min-width: 620px;
          border-collapse: collapse;
          margin-bottom: 12px;
          font-size: 13px;
        }
        .kwitansi-detail-table th,
        .kwitansi-detail-table td {
          padding: 10px 12px;
          border-bottom: 1px solid var(--border-default);
          vertical-align: top;
        }
        .kwitansi-detail-table thead tr,
        .kwitansi-detail-table tfoot tr {
          background: var(--bg-surface);
          font-weight: 800;
        }
        .kwitansi-group-breakdown {
          display: grid;
          grid-template-columns: repeat(3, minmax(160px, 1fr));
          gap: 10px;
          margin-top: 12px;
        }
        .kwitansi-group-breakdown div {
          padding: 12px;
          border: 1px solid var(--border-default);
          border-radius: 8px;
          background: var(--bg-surface);
        }
        .kwitansi-group-breakdown span {
          display: block;
          color: var(--text-tertiary);
          font-size: 12px;
          margin-bottom: 4px;
        }
        .kwitansi-panjar-list {
          display: flex;
          flex-wrap: wrap;
          gap: 8px 12px;
          margin-top: 12px;
          color: var(--text-secondary);
          font-size: 13px;
        }
        .kwitansi-total-row {
          display: flex;
          justify-content: flex-end;
          margin-top: 12px;
        }
        .kwitansi-total-box {
          width: min(440px, 100%);
          padding: 20px;
          border: 1px solid var(--border-default);
          border-radius: 8px;
          background: var(--bg-surface);
        }
        .kwitansi-total-box > div:not(.kwitansi-total-divider) {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 8px;
          margin-bottom: 6px;
        }
        .kwitansi-total-divider {
          border-top: 2px solid var(--border-default);
          margin: 8px 0;
        }
        .kwitansi-final-total span {
          font-size: 14px;
          font-weight: 700;
        }
        .kwitansi-final-total strong {
          font-size: 14px;
          font-weight: 700;
          color: var(--color-success);
        }
        .danger-text {
          color: var(--color-danger) !important;
        }
        .success-text {
          color: var(--color-success) !important;
        }
        .kwitansi-payment-note {
          margin-top: 24px;
          padding: 16px;
          border: 1px solid var(--border-default);
          border-radius: 8px;
          color: var(--text-secondary);
        }
        .kwitansi-print-footer {
          margin-top: 40px;
          text-align: center;
          color: var(--text-tertiary);
          font-size: 12px;
        }
        @media (max-width: 920px) {
          .toolbar.no-print.card {
            grid-template-columns: 1fr !important;
          }
          .kwitansi-header-info {
            align-items: center;
          }
          .kwitansi-recipient {
            max-width: none;
            margin-left: 0;
          }
          .kwitansi-group-subtotal {
            text-align: left;
          }
          .kwitansi-group-breakdown {
            grid-template-columns: 1fr;
          }
          .kwitansi-preview {
            font-size: 12px;
          }
          .kwitansi-detail-table {
            font-size: 12px;
          }
          .kwitansi-detail-table th,
          .kwitansi-detail-table td {
            padding: 8px 10px;
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
          .bottom-nav,
          .no-print {
            display: none !important;
          }
          body * {
            visibility: hidden;
          }
          .print-area,
          .print-area * {
            visibility: visible;
            color: #000 !important;
            background: #fff !important;
          }
          .print-area {
            position: static !important;
            left: auto !important;
            top: auto !important;
            width: 794px !important;
            max-width: 794px !important;
            box-shadow: none !important;
            border: 0 !important;
            border-radius: 0 !important;
            margin: 0 !important;
            padding: 0 !important;
            transform: none !important;
            font-size: 9.5px !important;
          }
          .kwitansi-doc-header {
            border-bottom: 1.5px dashed #111 !important;
            padding-bottom: 12px !important;
            margin-bottom: 12px !important;
            display: flex !important;
            flex-direction: row !important;
            align-items: center !important;
          }
          .kwitansi-logo {
            width: 90px !important;
            height: 90px !important;
            flex: 0 0 90px !important;
          }
          .kwitansi-title {
            font-size: 17px !important;
          }
          .kwitansi-recipient h2 {
            font-size: 13px !important;
          }
          .kwitansi-table-wrap {
            overflow: visible !important;
          }
          .kwitansi-detail-table {
            min-width: 0 !important;
            font-size: 10px !important;
          }
          .kwitansi-detail-table th,
          .kwitansi-detail-table td {
            padding: 4px 5px !important;
            font-size: 9px !important;
            border-bottom: 1px solid #b8b8b8 !important;
          }
          .kwitansi-total-box,
          .kwitansi-payment-note {
            border: 1px solid #111 !important;
            border-radius: 4px !important;
          }
          .kwitansi-total-row {
            margin-top: 4px !important;
          }
          .kwitansi-total-box {
            width: 440px !important;
            padding: 10px 12px !important;
          }
          .kwitansi-final-total span,
          .kwitansi-final-total strong {
            font-size: 12px !important;
            font-weight: 700 !important;
          }
          .kwitansi-total-box > div:not(.kwitansi-total-divider) > span,
          .kwitansi-total-box > div:not(.kwitansi-total-divider) > strong {
            font-size: 12px !important;
          }
        }
      `}</style>

      {showPaymentModal && (
        <div className="modal-overlay no-print" onClick={() => !savingPayment && setShowPaymentModal(false)}>
          <div className="modal" onClick={event => event.stopPropagation()} style={{ maxWidth: 680 }}>
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
                      Sistem akan menyimpan transaksi yang tampil saat ini saja. Jika mitra mengirim lagi setelah dibayar, transaksi baru itu akan masuk kwitansi berikutnya.
                    </div>
                  </div>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 12, marginBottom: 16 }}>
                  <div className="card" style={{ padding: 14, borderRadius: 8 }}>
                    <div className="text-tertiary" style={{ fontSize: 12 }}>Total Nilai Bersih</div>
                    <div className="table-mono" style={{ fontWeight: 800 }}>{formatRupiah(displayTotalNilaiBersih)}</div>
                  </div>
                  <div className="card" style={{ padding: 14, borderRadius: 8 }}>
                    <div className="text-tertiary" style={{ fontSize: 12 }}>Potongan Panjar</div>
                    <div className="table-mono" style={{ fontWeight: 800, color: 'var(--color-danger)' }}>{formatRupiah(displayTotalPanjar)}</div>
                  </div>
                  <div className="card" style={{ padding: 14, borderRadius: 8 }}>
                    <div className="text-tertiary" style={{ fontSize: 12 }}>Potongan Sewa Armada</div>
                    <div className="table-mono" style={{ fontWeight: 800, color: 'var(--color-danger)' }}>{formatRupiah(displayTotalSewaArmada)}</div>
                  </div>
                  <div className="card" style={{ padding: 14, borderRadius: 8 }}>
                    <div className="text-tertiary" style={{ fontSize: 12 }}>Dibayar ke Mitra</div>
                    <div className="table-mono" style={{ fontWeight: 900, color: 'var(--color-success)' }}>{formatRupiah(sisaBersih)}</div>
                  </div>
                </div>

                <div style={{ display: 'grid', gap: 8, marginBottom: 16 }}>
                  {kwitansiGroups.map(group => (
                    <div key={group.mitraId} style={{ display: 'flex', justifyContent: 'space-between', gap: 12, padding: 12, border: '1px solid var(--border-default)', borderRadius: 8 }}>
                      <div>
                        <div style={{ fontWeight: 700 }}>{group.nama || 'Nama mitra belum diisi'}</div>
                        <div style={{ color: 'var(--text-secondary)', fontSize: 12, fontWeight: 600 }}>{group.kodeLabel}</div>
                        <div style={{ color: 'var(--text-tertiary)', fontSize: 12 }}>
                          {group.rows.length} transaksi, panjar {formatRupiah(group.totalPanjar)}, sewa {formatRupiah(group.totalSewaArmada || 0)}
                        </div>
                      </div>
                      <div className="table-mono" style={{ fontWeight: 800 }}>{formatRupiah(group.totalNilaiBersih - group.totalPanjar - (group.totalSewaArmada || 0))}</div>
                    </div>
                  ))}
                </div>

                {isCombinedReceipt && (
                  <div className="form-group">
                    <label className="form-label">Nama Penerima di Kwitansi Gabungan</label>
                    <input
                      className="form-input"
                      value={paymentForm.penerima_label}
                      onChange={event => setPaymentForm(current => ({ ...current, penerima_label: event.target.value }))}
                      placeholder={selectedRecipientLabel || 'Contoh: Gabungan SL/MD dan BL/LR'}
                    />
                  </div>
                )}

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
                <button type="submit" className="btn btn-primary" disabled={savingPayment || transaksi.length === 0 || hasDraftAllocationIssue}>
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

      <PromptDialog
        open={showCancelPayment}
        title="Batalkan Pembayaran Kwitansi"
        message="Sistem tidak menghapus riwayat. Kas keluar akan dibuatkan transaksi balik, panjar akan dikembalikan, dan transaksi dapat masuk ke kwitansi baru."
        label="Alasan pembatalan"
        placeholder="Contoh: nominal transfer salah"
        confirmText="Batalkan Pembayaran"
        loading={cancelingPayment}
        onCancel={() => setShowCancelPayment(false)}
        onConfirm={handleCancelPayment}
      />
    </AppShell>
  );
}
