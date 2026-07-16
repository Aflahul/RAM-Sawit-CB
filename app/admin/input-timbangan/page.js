'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import AppShell from '@/components/layout/AppShell';
import SearchableCombobox from '@/components/ui/SearchableCombobox';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import FormPengirimanModal from '@/components/transaksi/FormPengirimanModal';
import {
  formatMitraLabel,
  formatSopirArmadaDescription,
  formatSopirArmadaLabel,
  getMitraSearchText,
  getSopirArmadaSearchText,
} from '@/lib/display-labels';
import { paginateRows } from '@/lib/pagination-utils';
import { getNextSort, sortRows } from '@/lib/sort-utils';
import { supabase } from '@/lib/supabase';
import {
  resolveBeratDibayar,
  resolveBeratNettoPabrik,
  resolveBiayaSewaArmada,
  resolveEffectiveMitraFeeSnapshot,
  resolveTotalNilaiBersihMitra,
} from '@/lib/transaksi-mitra-calculations';
import { formatDateDisplay, formatRupiah, formatWaktu, getTimestampMs, getTodayISO } from '@/lib/utils';
import { Ban, Pencil, ReceiptText, RefreshCw, Plus } from 'lucide-react';

const SOPIR_AKTUAL_DEFAULT = 'default';
const SOPIR_AKTUAL_MASTER = 'master';
const SOPIR_AKTUAL_MANUAL = 'manual';
const TABLE_PAGE_SIZE = 20;

const emptyEditForm = {
  tanggal: '',
  sopir_default_id: '',
  sopir_default_nama: '',
  mitra_id: '',
  plat_nomor: '',
  sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
  sopir_aktual_id: '',
  sopir_aktual_nama: '',
  sopir_aktual_no_hp: '',
  catatan_sopir: '',
  berat_netto: '',
  potongan_pabrik: '0',
  harga_dasar: 0,
  fee_owner_history_id: '',
  fee_owner_per_kg: 0,
  harga_harian: 0,
  total_kotor: 0,
  total_fee_owner: 0,
  total_nilai_bersih: 0,
  menggunakan_armada_cb_snapshot: false,
  pakai_sewa_armada_bl: false,
  kenakan_sewa_armada_cb: false,
  catat_dana_operasional_trip: false,
  alasan_tanpa_sewa_armada_cb: '',
  alasan_tanpa_dana_operasional_trip: '',
  dana_operasional_trip: 0,
  tarif_sewa_angkut_per_kg: 0,
  biaya_sewa_armada_total: 0,
  alasan_edit: '',
};

function toNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function getRowSearchText(row) {
  return [
    row.tanggal,
    formatDateDisplay(row.tanggal),
    formatMitraLabel(row.master_mitra),
    row.sopir_default_nama,
    row.sopir_aktual_nama,
    row.plat_nomor,
    row.status,
    row.payment_status,
    row.payment?.penerima_label,
    row.payment?.metode_bayar,
    row.alasan_batal,
    row.alasan_edit,
    row.alasan_tanpa_sewa_armada_cb,
    row.alasan_tanpa_dana_operasional_trip,
    row.alasan_review_armada_cb,
  ].filter(Boolean).join(' ').toLowerCase();
}

const riwayatSortAccessors = {
  tanggal: row => row.tanggal,
  waktu: row => getTimestampMs(row.created_at || row.tanggal),
  mitra: row => formatMitraLabel(row.master_mitra),
  sopir: row => row.sopir_aktual_nama || row.sopir_default_nama,
  plat: row => row.plat_nomor,
  status: row => row.status,
  berat_netto: row => resolveBeratNettoPabrik(row),
  berat_dibayar: row => resolveBeratDibayar(row),
  harga_bersih: row => toNumber(row.harga_bersih_per_kg ?? row.harga_harian),
  nilai_bersih: row => toNumber(row.total_nilai_bersih ?? row.total_kotor),
  pembayaran: row => row.payment_status || 'belum_dibayar',
};

function getPaymentBadge(row) {
  if (row.payment_status === 'perlu_review') {
    return {
      className: 'badge-warning',
      label: 'Perlu Cek',
      detail: row.payment_review_reason || 'Data pembayaran perlu diperiksa',
    };
  }

  if (row.payment_status === 'sudah_dibayar') {
    return {
      className: 'badge-success',
      label: 'Sudah Dibayar',
      detail: row.payment
        ? `${formatDateDisplay(row.payment.tanggal_bayar)} ${formatWaktu(row.payment.dibayar_at)} via ${row.payment.metode_bayar || '-'}`
        : 'Sudah masuk kwitansi',
    };
  }

  return {
    className: 'badge-neutral',
    label: 'Belum Dibayar',
    detail: 'Belum masuk kwitansi',
  };
}

function getKwitansiHref(row) {
  const params = new URLSearchParams();
  if (row.mitra_id) params.set('mitra', row.mitra_id);
  if (row.payment?.periode_dari || row.tanggal) params.set('dari', row.payment?.periode_dari || row.tanggal);
  if (row.payment?.periode_sampai || row.tanggal) params.set('sampai', row.payment?.periode_sampai || row.tanggal);
  return `/owner/kwitansi-mitra?${params.toString()}`;
}

function getTransactionLockReason(row) {
  if (row.payment_status === 'sudah_dibayar' || row.payment_status === 'perlu_review') {
    return 'Sudah masuk kwitansi. Batalkan pembayaran kwitansi terlebih dahulu.';
  }
  if (row.pembayaran_pabrik_status) {
    return 'Sudah dicocokkan dengan pembayaran pabrik. Batalkan pembayaran pabrik terlebih dahulu.';
  }
  if (row.biaya_sopir_dibayar_at) {
    return 'Dana Operasional Trip sudah dibayar. Koreksi pembayaran Dana Trip terlebih dahulu.';
  }
  return '';
}

export default function RiwayatPengirimanMitraPage() {
  const [dateFrom, setDateFrom] = useState(getTodayISO);
  const [dateTo, setDateTo] = useState(getTodayISO);
  const [statusFilter, setStatusFilter] = useState('aktif');
  const [search, setSearch] = useState('');
  const [transaksi, setTransaksi] = useState([]);
  const [mitras, setMitras] = useState([]);
  const [sopirs, setSopirs] = useState([]);
  const [feeHistories, setFeeHistories] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [editTarget, setEditTarget] = useState(null);
  const [editForm, setEditForm] = useState(emptyEditForm);
  const [cancelTarget, setCancelTarget] = useState(null);
  const [cancelReason, setCancelReason] = useState('');
  const [sort, setSort] = useState({ key: 'waktu', direction: 'desc' });
  const [page, setPage] = useState(1);
  const [toast, setToast] = useState(null);
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);

  useEffect(() => {
    const requestedStatus = new URLSearchParams(window.location.search).get('status');
    if (requestedStatus === 'review_armada_cb') {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setStatusFilter('review_armada_cb');
    }
  }, []);

  const loadData = useCallback(async () => {
    setLoading(true);
    setErrorMsg('');

    let transaksiQuery = supabase
      .from('transaksi_mitra')
      .select(`
        id, tanggal, sopir_id, mitra_id, plat_nomor, tonase, harga_harian, total_kotor,
        harga_pabrik_per_kg, fee_owner_per_kg, harga_bersih_per_kg, total_fee_owner,
        total_nilai_bersih, fee_owner_history_id,
        berat_netto_pabrik_kg, potongan_pabrik_kg, berat_dibayar_kg,
        menggunakan_armada_cb_snapshot, pakai_sewa_armada_bl,
        kenakan_sewa_armada_cb, catat_dana_operasional_trip,
        alasan_tanpa_sewa_armada_cb, alasan_tanpa_dana_operasional_trip,
        armada_cb_perlu_review, alasan_review_armada_cb,
        biaya_sewa_armada_per_kg, biaya_sewa_armada_total,
        tarif_sewa_angkut_per_kg_snapshot, biaya_sewa_armada_kotor,
        dana_operasional_trip_snapshot, upah_sopir_cb_snapshot, uang_jalan_sopir_cb_snapshot, total_biaya_sopir_cb_snapshot,
        tagihan_sopir_ledger_id, biaya_sopir_operasional_id, biaya_sopir_dibayar_at,
        status, created_at, updated_at, updated_by, alasan_edit, dibatalkan_at, dibatalkan_by, alasan_batal,
        sopir_default_id, sopir_default_nama, sopir_aktual_id, sopir_aktual_nama,
        sopir_aktual_no_hp, sopir_aktual_source, sopir_diganti_dari_default, catatan_sopir,
        master_mitra ( id, kode, alamat, nama, fee_per_kg )
      `)
      .order('created_at', { ascending: false });

    if (statusFilter === 'review_armada_cb') {
      transaksiQuery = transaksiQuery
        .eq('status', 'aktif')
        .eq('armada_cb_perlu_review', true);
    } else {
      transaksiQuery = transaksiQuery
        .gte('tanggal', dateFrom)
        .lte('tanggal', dateTo);
    }

    if (!['semua', 'review_armada_cb'].includes(statusFilter)) {
      transaksiQuery = transaksiQuery.eq('status', statusFilter);
    }

    const [
      { data: trxData, error: trxError },
      { data: mitraData, error: mitraError },
      { data: sopirData, error: sopirError },
      { data: feeHistoryData, error: feeHistoryError },
    ] = await Promise.all([
      transaksiQuery,
      supabase
        .from('master_mitra')
        .select('id, kode, alamat, nama, fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip')
        .eq('aktif', true)
        .order('kode'),
      supabase
        .from('sopir')
        .select(`
          id, nama, no_hp, plat_nomor, mitra_id, is_armada_cb,
          master_mitra ( id, kode, alamat, nama, fee_per_kg )
        `)
        .eq('aktif', true)
        .order('nama'),
      supabase
        .from('fee_owner_mitra_history')
        .select('id, master_mitra_id, fee_per_kg, tarif_sewa_angkut_per_kg, dana_operasional_trip, berlaku_mulai, berlaku_sampai, aktif, alasan_perubahan')
        .eq('aktif', true)
        .order('berlaku_mulai', { ascending: false }),
    ]);

    const error = trxError || mitraError || sopirError;
    if (error) {
      console.error('Gagal memuat riwayat pengiriman mitra:', error);
      setErrorMsg(error.message);
      setTransaksi([]);
    } else {
      let rows = trxData || [];

      if (rows.length > 0) {
        const trxIds = rows.map(row => row.id);
        const [paymentResult, factoryPaymentResult] = await Promise.all([
          supabase
            .from('pembayaran_mitra_kwitansi_item')
            .select(`
            transaksi_mitra_id,
            tonase_snapshot,
            berat_netto_snapshot,
            potongan_snapshot,
            berat_dibayar_snapshot,
            total_nilai_bersih_snapshot,
            pembayaran:pembayaran_mitra_kwitansi (
              id, status, tanggal_bayar, dibayar_at, metode_bayar, nominal_dibayar,
              kas_ledger_id, penerima_label, mode_pembayaran, review_reason,
              periode_dari, periode_sampai
            )
            `)
            .in('transaksi_mitra_id', trxIds),
          supabase
            .from('pembayaran_pabrik_item')
            .select(`
              transaksi_mitra_id,
              pembayaran:pembayaran_pabrik_batch ( id, status, tanggal_bayar )
            `)
            .in('transaksi_mitra_id', trxIds),
        ]);

        const paymentItems = paymentResult.data || [];
        const paymentError = paymentResult.error;
        const factoryPaymentItems = factoryPaymentResult.data || [];

        if (paymentError) {
          console.error('Gagal memuat status bayar riwayat mitra:', paymentError);
        }
        if (factoryPaymentResult.error) {
          console.error('Gagal memuat status pembayaran pabrik:', factoryPaymentResult.error);
        }

        const paymentMap = new Map(paymentItems.filter((item) => {
          const payment = Array.isArray(item.pembayaran) ? item.pembayaran[0] : item.pembayaran;
          return payment && payment.status !== 'dibatalkan';
        }).map((item) => {
          const payment = Array.isArray(item.pembayaran) ? item.pembayaran[0] : item.pembayaran;
          return [item.transaksi_mitra_id, { ...item, pembayaran: payment }];
        }));
        const factoryPaymentMap = new Map(factoryPaymentItems.flatMap((item) => {
          const factoryPayment = Array.isArray(item.pembayaran) ? item.pembayaran[0] : item.pembayaran;
          return factoryPayment && factoryPayment.status !== 'dibatalkan'
            ? [[item.transaksi_mitra_id, factoryPayment]]
            : [];
        }));

        rows = rows.map((row) => {
          const paymentItem = paymentMap.get(row.id);
          const payment = paymentItem?.pembayaran;
          const hasMissingCashLedger = payment?.status === 'dibayar'
            && Number(payment?.nominal_dibayar || 0) > 0
            && !payment?.kas_ledger_id;
          const hasWeightChanged = Boolean(payment)
            && Math.round(resolveBeratDibayar(row) * 100)
              !== Math.round(Number(paymentItem.berat_dibayar_snapshot ?? paymentItem.tonase_snapshot ?? 0) * 100);
          const hasValueChanged = Boolean(payment)
            && Math.round(resolveTotalNilaiBersihMitra(row))
              !== Math.round(Number(paymentItem.total_nilai_bersih_snapshot || 0));
          const hasChangedAfterPayment = hasWeightChanged || hasValueChanged;
          const reviewReasons = [
            payment?.status === 'perlu_review'
              ? payment.review_reason || 'Kwitansi ditandai untuk diperiksa oleh bagian keuangan'
              : '',
            hasWeightChanged ? 'Berat transaksi berbeda dari berat pada kwitansi' : '',
            hasValueChanged ? 'Nilai transaksi berbeda dari nilai pada kwitansi' : '',
            hasMissingCashLedger ? 'Pembayaran belum terhubung ke Buku Kas' : '',
          ].filter(Boolean);

          return {
            ...row,
            payment,
            pembayaran_pabrik_status: factoryPaymentMap.get(row.id)?.status || '',
            payment_review_reason: reviewReasons.join('. '),
            payment_status: payment?.status === 'perlu_review' || hasChangedAfterPayment || hasMissingCashLedger
              ? 'perlu_review'
              : payment?.status === 'dibayar'
                ? 'sudah_dibayar'
                : 'belum_dibayar',
          };
        });
      }

      setTransaksi(rows);
      setMitras(mitraData || []);
      setSopirs(sopirData || []);
      setFeeHistories(feeHistoryError ? [] : feeHistoryData || []);
    }

    setLoading(false);
  }, [dateFrom, dateTo, statusFilter]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  const filteredTransaksi = useMemo(() => {
    const keyword = search.trim().toLowerCase();
    if (!keyword) return transaksi;
    return transaksi.filter(row => getRowSearchText(row).includes(keyword));
  }, [search, transaksi]);
  const sortedTransaksi = useMemo(() => {
    return sortRows(filteredTransaksi, sort, riwayatSortAccessors);
  }, [filteredTransaksi, sort]);
  const paginatedTransaksi = useMemo(() => {
    return paginateRows(sortedTransaksi, page, TABLE_PAGE_SIZE);
  }, [page, sortedTransaksi]);

  const totals = useMemo(() => {
    return filteredTransaksi
      .filter(row => row.status !== 'dibatalkan')
      .reduce((acc, row) => ({
        berat_netto: acc.berat_netto + resolveBeratNettoPabrik(row),
        berat_dibayar: acc.berat_dibayar + resolveBeratDibayar(row),
        total: acc.total + toNumber(row.total_nilai_bersih ?? row.total_kotor),
        sewa_armada: acc.sewa_armada + resolveBiayaSewaArmada(row),
      }), { berat_netto: 0, berat_dibayar: 0, total: 0, sewa_armada: 0 });
  }, [filteredTransaksi]);
  const editFeeOwner = toNumber(editForm.fee_owner_per_kg);
  const editUsesArmadaCb = Boolean(editForm.menggunakan_armada_cb_snapshot);

  function handleSort(key) {
    setPage(1);
    setSort(current => getNextSort(current, key, ['tanggal', 'waktu'].includes(key) ? 'desc' : 'asc'));
  }

  function showToast(message, type = 'error') {
    setToast({ message, type });
    setTimeout(() => setToast(null), type === 'error' ? 5000 : 3000);
  }

  function getEffectiveFeeSnapshot(mitraId, tanggal) {
    return resolveEffectiveMitraFeeSnapshot({
      mitraId,
      tanggal: tanggal || getTodayISO(),
      mitras,
      feeHistories,
    });
  }

  function applyFeeSnapshot(nextForm, mitraId = nextForm.mitra_id, tanggal = nextForm.tanggal) {
    const snapshot = getEffectiveFeeSnapshot(mitraId, tanggal);

    return {
      ...nextForm,
      mitra_id: mitraId,
      fee_owner_per_kg: snapshot.fee,
      fee_owner_history_id: snapshot.historyId,
      tarif_sewa_angkut_per_kg: snapshot.tarifSewaAngkut || 0,
      dana_operasional_trip: snapshot.danaOperasionalTrip || 0,
    };
  }

  function recalculateTotals(nextForm) {
    const feeOwner    = toNumber(nextForm.fee_owner_per_kg);
    const hargaPabrik = toNumber(nextForm.harga_dasar);
    const hargaBersih = Math.max(hargaPabrik - feeOwner, 0);
    const beratNetto  = Math.max(0, parseFloat(nextForm.berat_netto) || 0);
    const potongan    = Math.max(0, parseFloat(nextForm.potongan_pabrik) || 0);
    const beratDibayar = Math.max(0, beratNetto - potongan);

    // Deteksi sewa armada dari form state (pakai_sewa_armada_bl sudah dihitung di openEdit)
    const sewaArmadaTotal = nextForm.menggunakan_armada_cb_snapshot && nextForm.kenakan_sewa_armada_cb
      ? Math.round(beratNetto * toNumber(nextForm.tarif_sewa_angkut_per_kg))
      : 0;

    return {
      ...nextForm,
      harga_harian: hargaBersih,
      total_kotor:        Math.round(beratDibayar * hargaPabrik),
      total_fee_owner:    Math.round(beratDibayar * feeOwner),
      total_nilai_bersih: Math.round(beratDibayar * hargaBersih),
      biaya_sewa_armada_total: sewaArmadaTotal,
    };
  }

  function openEdit(row) {
    const isManual  = row.sopir_aktual_source === 'manual';
    const isDefault = !isManual && String(row.sopir_aktual_id || '') === String(row.sopir_default_id || row.sopir_id || '');
    const effectiveFee = getEffectiveFeeSnapshot(row.mitra_id, row.tanggal);
    const fallbackFee  = toNumber(row.fee_owner_per_kg ?? effectiveFee.fee ?? row.master_mitra?.fee_per_kg);
    const hargaDasar   = toNumber(row.harga_pabrik_per_kg ?? (toNumber(row.harga_harian) + fallbackFee));
    const beratNetto   = resolveBeratNettoPabrik(row);
    const potongan     = toNumber(row.potongan_pabrik_kg);
    const beratDibayar = resolveBeratDibayar(row);
    const menggunakanArmadaCb = Boolean(row.menggunakan_armada_cb_snapshot ?? row.pakai_sewa_armada_bl);
    const pakaiSewa    = menggunakanArmadaCb && Boolean(row.kenakan_sewa_armada_cb ?? row.pakai_sewa_armada_bl);
    const tarifSewa    = toNumber(row.tarif_sewa_angkut_per_kg_snapshot ?? row.biaya_sewa_armada_per_kg);
    const sewaTotal    = pakaiSewa ? Math.round(beratNetto * tarifSewa) : 0;

    setEditTarget(row);
    setEditForm({
      tanggal: row.tanggal || '',
      sopir_default_id: row.sopir_default_id || row.sopir_id || '',
      sopir_default_nama: row.sopir_default_nama || '',
      mitra_id: row.mitra_id || '',
      plat_nomor: row.plat_nomor || '',
      sopir_aktual_mode: isManual ? SOPIR_AKTUAL_MANUAL : isDefault ? SOPIR_AKTUAL_DEFAULT : SOPIR_AKTUAL_MASTER,
      sopir_aktual_id: row.sopir_aktual_id || '',
      sopir_aktual_nama: row.sopir_aktual_nama || '',
      sopir_aktual_no_hp: row.sopir_aktual_no_hp || '',
      catatan_sopir: row.catatan_sopir || '',
      berat_netto: String(beratNetto || ''),
      potongan_pabrik: String(potongan),
      harga_dasar: hargaDasar,
      fee_owner_history_id: row.fee_owner_history_id || effectiveFee.historyId,
      fee_owner_per_kg: fallbackFee,
      harga_harian: toNumber(row.harga_bersih_per_kg ?? row.harga_harian),
      total_kotor:        Math.round(beratDibayar * hargaDasar),
      total_fee_owner:    toNumber(row.total_fee_owner),
      total_nilai_bersih: toNumber(row.total_nilai_bersih ?? row.total_kotor),
      menggunakan_armada_cb_snapshot: menggunakanArmadaCb,
      pakai_sewa_armada_bl: pakaiSewa,
      kenakan_sewa_armada_cb: pakaiSewa,
      catat_dana_operasional_trip: menggunakanArmadaCb
        && Boolean(row.catat_dana_operasional_trip ?? toNumber(row.dana_operasional_trip_snapshot) > 0),
      alasan_tanpa_sewa_armada_cb: row.alasan_tanpa_sewa_armada_cb || '',
      alasan_tanpa_dana_operasional_trip: row.alasan_tanpa_dana_operasional_trip || '',
      dana_operasional_trip: toNumber(row.dana_operasional_trip_snapshot ?? effectiveFee.danaOperasionalTrip),
      tarif_sewa_angkut_per_kg: tarifSewa,
      biaya_sewa_armada_total: sewaTotal,
      alasan_edit: '',
    });
  }

  function handleEditSopirDefaultChange(sopirId) {
    const sopir = sopirs.find(item => item.id === sopirId);
    if (!sopir) {
      setEditForm({
        ...editForm,
        sopir_default_id: '',
        sopir_default_nama: '',
        plat_nomor: '',
        sopir_aktual_id: '',
        sopir_aktual_nama: '',
        sopir_aktual_no_hp: '',
        menggunakan_armada_cb_snapshot: false,
        pakai_sewa_armada_bl: false,
        kenakan_sewa_armada_cb: false,
        catat_dana_operasional_trip: false,
        alasan_tanpa_sewa_armada_cb: '',
        alasan_tanpa_dana_operasional_trip: '',
      });
      return;
    }

    const nextForm = {
      ...editForm,
      sopir_default_id: sopir.id,
      sopir_default_nama: sopir.nama,
      plat_nomor: sopir.plat_nomor || '',
      mitra_id: editForm.mitra_id || sopir.mitra_id || '',
      sopir_aktual_mode: SOPIR_AKTUAL_DEFAULT,
      sopir_aktual_id: sopir.id,
      sopir_aktual_nama: sopir.nama,
      sopir_aktual_no_hp: sopir.no_hp || '',
      menggunakan_armada_cb_snapshot: Boolean(sopir.is_armada_cb),
      pakai_sewa_armada_bl: Boolean(sopir.is_armada_cb),
      kenakan_sewa_armada_cb: Boolean(sopir.is_armada_cb),
      catat_dana_operasional_trip: Boolean(sopir.is_armada_cb),
      alasan_tanpa_sewa_armada_cb: '',
      alasan_tanpa_dana_operasional_trip: '',
    };

    setEditForm(recalculateTotals(applyFeeSnapshot(nextForm, nextForm.mitra_id, editForm.tanggal)));
  }

  function handleEditMitraChange(mitraId) {
    setEditForm(recalculateTotals(applyFeeSnapshot({ ...editForm }, mitraId, editForm.tanggal)));
  }

  function handleEditTanggalChange(tanggal) {
    setEditForm(recalculateTotals(applyFeeSnapshot({ ...editForm, tanggal }, editForm.mitra_id, tanggal)));
  }

  function handleEditBeratNettoChange(value) {
    setEditForm(recalculateTotals({ ...editForm, berat_netto: value }));
  }

  function handleEditPotonganChange(value) {
    setEditForm(recalculateTotals({ ...editForm, potongan_pabrik: value }));
  }

  function handleEditHargaDasarChange(value) {
    setEditForm(recalculateTotals({ ...editForm, harga_dasar: value }));
  }

  function handleSyncFeeFromMaster() {
    if (!editTarget) return;

    const nextForm = applyFeeSnapshot({ ...editForm }, editForm.mitra_id, editForm.tanggal);
    setEditForm(recalculateTotals({
      ...nextForm,
      alasan_edit: editForm.alasan_edit || 'Sinkronisasi Fee Owner dari master mitra.',
    }));
  }

  function handleEditSopirAktualModeChange(mode) {
    const defaultSopir = sopirs.find(item => item.id === editForm.sopir_default_id);
    const nextForm = {
      ...editForm,
      sopir_aktual_mode: mode,
      catatan_sopir: mode === SOPIR_AKTUAL_DEFAULT ? '' : editForm.catatan_sopir,
    };

    if (mode === SOPIR_AKTUAL_DEFAULT && defaultSopir) {
      nextForm.sopir_aktual_id = defaultSopir.id;
      nextForm.sopir_aktual_nama = defaultSopir.nama;
      nextForm.sopir_aktual_no_hp = defaultSopir.no_hp || '';
    }

    if (mode === SOPIR_AKTUAL_MASTER || mode === SOPIR_AKTUAL_MANUAL) {
      nextForm.sopir_aktual_id = '';
      nextForm.sopir_aktual_nama = '';
      nextForm.sopir_aktual_no_hp = '';
    }

    setEditForm(nextForm);
  }

  function handleEditSopirAktualMasterChange(sopirId) {
    const sopir = sopirs.find(item => item.id === sopirId);
    setEditForm({
      ...editForm,
      sopir_aktual_id: sopirId,
      sopir_aktual_nama: sopir?.nama || '',
      sopir_aktual_no_hp: sopir?.no_hp || '',
    });
  }

  async function handleSaveEdit(event) {
    event.preventDefault();
    if (!editTarget || saving) return;

    const beratNetto  = parseFloat(editForm.berat_netto) || 0;
    const potongan    = parseFloat(editForm.potongan_pabrik) || 0;
    const beratDibayar = Math.max(0, beratNetto - potongan);

    if (!editForm.sopir_default_id) return showToast('Pilih armada / sopir default.');
    if (!editForm.mitra_id) return showToast('Pilih mitra transaksi.');
    if (!editForm.sopir_aktual_nama.trim()) return showToast('Sopir aktual wajib diisi.');
    if (beratNetto <= 0) return showToast('Berat Netto dari Pabrik harus lebih dari 0.');
    if (potongan < 0) return showToast('Potongan Pabrik tidak boleh negatif.');
    if (potongan > beratNetto) return showToast('Potongan Pabrik tidak boleh lebih besar dari Berat Netto.');
    if (editUsesArmadaCb && editForm.kenakan_sewa_armada_cb && toNumber(editForm.tarif_sewa_angkut_per_kg) <= 0) {
      return showToast('Tarif sewa Armada CB untuk mitra ini belum diisi.');
    }
    if (editUsesArmadaCb && editForm.catat_dana_operasional_trip && toNumber(editForm.dana_operasional_trip) <= 0) {
      return showToast('Dana Operasional Trip untuk mitra ini belum diisi.');
    }
    if (editUsesArmadaCb && !editForm.kenakan_sewa_armada_cb && !editForm.alasan_tanpa_sewa_armada_cb.trim()) {
      return showToast('Alasan tanpa potongan sewa wajib diisi.');
    }
    if (editUsesArmadaCb && !editForm.catat_dana_operasional_trip && !editForm.alasan_tanpa_dana_operasional_trip.trim()) {
      return showToast('Alasan tanpa Dana Operasional Trip wajib diisi.');
    }
    if (!editForm.alasan_edit.trim()) return showToast('Alasan edit wajib diisi.');

    setSaving(true);
    const sopirDiganti = editForm.sopir_aktual_mode === SOPIR_AKTUAL_MANUAL
      || (editForm.sopir_aktual_mode === SOPIR_AKTUAL_MASTER && editForm.sopir_aktual_id !== editForm.sopir_default_id);
    const sopirAktualId = editForm.sopir_aktual_mode === SOPIR_AKTUAL_DEFAULT
      ? editForm.sopir_default_id
      : editForm.sopir_aktual_mode === SOPIR_AKTUAL_MASTER
        ? editForm.sopir_aktual_id
        : null;

    const payload = {
      tanggal: editForm.tanggal,
      sopir_id: editForm.sopir_default_id,
      sopir_default_id: editForm.sopir_default_id,
      sopir_default_nama: editForm.sopir_default_nama,
      mitra_id: editForm.mitra_id,
      plat_nomor: editForm.plat_nomor || null,
      sopir_aktual_id: sopirAktualId,
      sopir_aktual_nama: editForm.sopir_aktual_nama.trim(),
      sopir_aktual_no_hp: editForm.sopir_aktual_no_hp || null,
      sopir_aktual_source: editForm.sopir_aktual_mode === SOPIR_AKTUAL_MANUAL ? 'manual' : 'master',
      sopir_diganti_dari_default: sopirDiganti,
      catatan_sopir: editForm.catatan_sopir || null,
      // Field berat (P0) — tonase backward-compat
      tonase:                beratNetto,
      berat_netto_pabrik_kg: beratNetto,
      potongan_pabrik_kg:    potongan,
      berat_dibayar_kg:      beratDibayar,
      // Snapshot harga
      harga_harian:        toNumber(editForm.harga_dasar),
      harga_pabrik_per_kg: toNumber(editForm.harga_dasar),
      fee_owner_per_kg:    toNumber(editForm.fee_owner_per_kg),
      harga_bersih_per_kg: editForm.harga_harian,
      fee_owner_history_id: editForm.fee_owner_history_id || null,
      // Total nilai (basis berat_dibayar)
      total_kotor:        editForm.total_kotor,
      total_fee_owner:    editForm.total_fee_owner,
      total_nilai_bersih: editForm.total_nilai_bersih,
      // Perjalanan Armada CB, potongan sewa, dan Dana Trip adalah keputusan terpisah.
      kenakan_sewa_armada_cb: editUsesArmadaCb && editForm.kenakan_sewa_armada_cb,
      catat_dana_operasional_trip: editUsesArmadaCb && editForm.catat_dana_operasional_trip,
      alasan_tanpa_sewa_armada_cb: editUsesArmadaCb && !editForm.kenakan_sewa_armada_cb
        ? editForm.alasan_tanpa_sewa_armada_cb.trim()
        : null,
      alasan_tanpa_dana_operasional_trip: editUsesArmadaCb && !editForm.catat_dana_operasional_trip
        ? editForm.alasan_tanpa_dana_operasional_trip.trim()
        : null,
      pakai_sewa_armada_bl: editUsesArmadaCb && editForm.kenakan_sewa_armada_cb,
      biaya_sewa_armada_per_kg: editUsesArmadaCb && editForm.kenakan_sewa_armada_cb ? editForm.tarif_sewa_angkut_per_kg : 0,
      tarif_sewa_angkut_per_kg_snapshot: editUsesArmadaCb && editForm.kenakan_sewa_armada_cb ? editForm.tarif_sewa_angkut_per_kg : 0,
      biaya_sewa_armada_kotor:  editForm.biaya_sewa_armada_total,
      biaya_sewa_armada_total:  editForm.biaya_sewa_armada_total,
    };

    const { error } = await supabase.rpc('update_transaksi_mitra_controlled', {
      p_transaksi_id: editTarget.id,
      p_changes: payload,
      p_alasan: editForm.alasan_edit.trim(),
    });

    if (error) {
      showToast(`Gagal menyimpan edit: ${error.message}`);
      setSaving(false);
      return;
    }

    setEditTarget(null);
    setEditForm(emptyEditForm);
    await loadData();
    setSaving(false);
  }

  async function handleCancelTransaction(event) {
    event.preventDefault();
    if (!cancelTarget || saving) return;
    if (!cancelReason.trim()) return showToast('Alasan batal wajib diisi.');

    setSaving(true);
    const { error } = await supabase.rpc('cancel_transaksi_mitra_controlled', {
      p_transaksi_id: cancelTarget.id,
      p_alasan: cancelReason.trim(),
    });

    if (error) {
      showToast(`Gagal membatalkan transaksi: ${error.message}`);
      setSaving(false);
      return;
    }

    setCancelTarget(null);
    setCancelReason('');
    await loadData();
    setSaving(false);
  }

  return (
    <AppShell title="Pengiriman Mitra" subtitle="Kelola transaksi pengiriman mitra ke pabrik">
      <FormPengirimanModal open={isAddModalOpen} onClose={() => setIsAddModalOpen(false)} onSuccess={() => { loadData(); }} />
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <div>
          <p className="page-description">Daftar transaksi detail untuk koreksi input dan pembatalan tanpa hapus data</p>
        </div>
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
          <Link className="btn btn-outline" href="/owner/kwitansi-mitra">
            <ReceiptText size={18} /> Buka Kwitansi Mitra
          </Link>
          <button className="btn btn-outline" onClick={loadData} disabled={loading}>
            <RefreshCw size={18} /> Muat Ulang
          </button>
          <button className="btn btn-primary" onClick={() => setIsAddModalOpen(true)}>
            <Plus size={18} /> Tambah Pengiriman
          </button>
        </div>
      </div>

      <div className="card" style={{ padding: 'var(--space-md)', marginBottom: 'var(--space-lg)' }}>
        <div className="form-grid" style={{ alignItems: 'end' }}>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Dari Tanggal</label>
            <input type="date" className="form-input" value={dateFrom} disabled={statusFilter === 'review_armada_cb'} onChange={event => setDateFrom(event.target.value)} />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Sampai Tanggal</label>
            <input type="date" className="form-input" value={dateTo} disabled={statusFilter === 'review_armada_cb'} onChange={event => setDateTo(event.target.value)} />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Status</label>
            <select className="form-input" value={statusFilter} onChange={event => setStatusFilter(event.target.value)}>
              <option value="aktif">Aktif</option>
              <option value="dibatalkan">Dibatalkan</option>
              <option value="review_armada_cb">Perlu Cek Armada CB</option>
              <option value="semua">Semua</option>
            </select>
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Cari</label>
            <input
              className="form-input"
              value={search}
              onChange={event => {
                setSearch(event.target.value);
                setPage(1);
              }}
              placeholder="Cari mitra, sopir, plat..."
            />
          </div>
        </div>
      </div>

      <div className="card" style={{ padding: 'var(--space-md)', marginBottom: 'var(--space-lg)' }}>
        <div style={{ display: 'flex', gap: 20, flexWrap: 'wrap' }}>
          <div>
            <div className="text-tertiary" style={{ fontSize: 12 }}>Transaksi Tampil</div>
            <div style={{ fontWeight: 800, fontSize: 20 }}>{filteredTransaksi.length}</div>
          </div>
          <div>
            <div className="text-tertiary" style={{ fontSize: 12 }}>Total Berat Netto Aktif</div>
            <div style={{ fontWeight: 800, fontSize: 20 }}>{totals.berat_netto.toLocaleString('id-ID')} Kg</div>
          </div>
          <div>
            <div className="text-tertiary" style={{ fontSize: 12 }}>Total Berat Dibayar Aktif</div>
            <div style={{ fontWeight: 800, fontSize: 20 }}>{totals.berat_dibayar.toLocaleString('id-ID')} Kg</div>
          </div>
          <div>
            <div className="text-tertiary" style={{ fontSize: 12 }}>Total Nilai Bersih</div>
            <div style={{ fontWeight: 800, fontSize: 20 }}>{formatRupiah(totals.total)}</div>
          </div>
          {totals.sewa_armada > 0 && (
            <div>
              <div className="text-tertiary" style={{ fontSize: 12 }}>Sewa Armada CB</div>
              <div style={{ fontWeight: 800, fontSize: 20, color: 'var(--color-warning)' }}>{formatRupiah(totals.sewa_armada)}</div>
            </div>
          )}
        </div>
      </div>

      <div className="table-container">
        <table className="table">
          <thead>
            <tr>
              <SortableHeader label="Tanggal" sortKey="waktu" sort={sort} onSort={handleSort} />
              <SortableHeader label="Mitra" sortKey="sopir" sort={sort} onSort={handleSort} />
              <SortableHeader label="Status" sortKey="status" sort={sort} onSort={handleSort} />
              <SortableHeader label="Pembayaran" sortKey="pembayaran" sort={sort} onSort={handleSort} />
              <SortableHeader label="Berat Netto" sortKey="berat_netto" sort={sort} onSort={handleSort} align="right" />
              <SortableHeader label="Berat Dibayar" sortKey="berat_dibayar" sort={sort} onSort={handleSort} align="right" />
              <SortableHeader label="Harga/Kg" sortKey="harga_bersih" sort={sort} onSort={handleSort} align="right" />
              <SortableHeader label="Bersih" sortKey="nilai_bersih" sort={sort} onSort={handleSort} align="right" />
              <th style={{ textAlign: 'center' }}>Aksi</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={9} style={{ padding: 24, textAlign: 'center' }}>Memuat riwayat...</td></tr>
            ) : errorMsg ? (
              <tr><td colSpan={9} style={{ padding: 24, textAlign: 'center', color: 'var(--color-danger)' }}>Gagal memuat riwayat: {errorMsg}</td></tr>
            ) : sortedTransaksi.length === 0 ? (
              <tr><td colSpan={9} style={{ padding: 24, textAlign: 'center', color: 'var(--text-tertiary)' }}>Tidak ada transaksi pada filter ini</td></tr>
            ) : (
              paginatedTransaksi.rows.map((row) => {
                const paymentBadge = getPaymentBadge(row);
                const lockReason = getTransactionLockReason(row);

                return (
                <tr key={row.id} style={row.status === 'dibatalkan' ? { opacity: 0.62 } : undefined}>
                  <td>
                    <div style={{ fontWeight: 700 }}>{formatDateDisplay(row.tanggal)}</div>
                    <div className="table-mono" style={{ marginTop: 4, color: 'var(--text-tertiary)', fontSize: 12 }}>{formatWaktu(row.created_at)}</div>
                  </td>
                  <td>
                    <div style={{ fontWeight: 700 }}>{row.sopir_aktual_nama || row.sopir_default_nama || '-'}</div>
                    <div style={{ marginTop: 4, color: 'var(--text-tertiary)', fontSize: 12 }}>
                      {row.master_mitra?.kode || '-'} - <span className="table-mono">{row.plat_nomor || 'Tanpa plat'}</span>
                    </div>
                    {row.sopir_diganti_dari_default && (
                      <div style={{ color: 'var(--text-tertiary)', fontSize: 12 }}>Default: {row.sopir_default_nama || '-'}</div>
                    )}
                  </td>
                  <td>
                    <span className={`badge ${row.status === 'dibatalkan' ? 'badge-danger' : 'badge-success'}`}>
                      {row.status === 'dibatalkan' ? 'Dibatalkan' : 'Aktif'}
                    </span>
                    {row.menggunakan_armada_cb_snapshot && (
                      <div style={{ marginTop: 5 }}>
                        <span className="badge badge-neutral">Trip Armada CB</span>
                      </div>
                    )}
                    {row.armada_cb_perlu_review && (
                      <div style={{ color: 'var(--color-warning)', fontSize: 12, marginTop: 5, fontWeight: 700 }}>
                        Perlu cek perlakuan Armada CB
                      </div>
                    )}
                    {row.alasan_batal && (
                      <div style={{ color: 'var(--text-tertiary)', fontSize: 12, marginTop: 4 }}>{row.alasan_batal}</div>
                    )}
                  </td>
                  <td>
                    <span className={`badge ${paymentBadge.className}`}>
                      {paymentBadge.label}
                    </span>
                    <div style={{ color: 'var(--text-tertiary)', fontSize: 12, marginTop: 4 }}>
                      {paymentBadge.detail}
                    </div>
                    {row.payment?.penerima_label && (
                      <div style={{ color: 'var(--text-tertiary)', fontSize: 12, marginTop: 2 }}>
                        {row.payment.penerima_label}
                      </div>
                    )}
                    {row.payment_status === 'perlu_review' && (
                      <Link
                        href={getKwitansiHref(row)}
                        style={{ display: 'inline-flex', alignItems: 'center', gap: 5, marginTop: 7, fontSize: 12, fontWeight: 700 }}
                      >
                        <ReceiptText size={14} /> Periksa kwitansi
                      </Link>
                    )}
                  </td>
                  <td style={{ textAlign: 'right', fontWeight: 700 }}>
                    {resolveBeratNettoPabrik(row).toLocaleString('id-ID')}
                    {toNumber(row.potongan_pabrik_kg) > 0 && (
                      <div style={{ fontSize: 11, color: 'var(--color-warning)', fontWeight: 400 }}>−{toNumber(row.potongan_pabrik_kg).toLocaleString('id-ID')} ptg</div>
                    )}
                  </td>
                  <td style={{ textAlign: 'right', fontWeight: 700 }}>
                    {resolveBeratDibayar(row).toLocaleString('id-ID')}
                    {row.menggunakan_armada_cb_snapshot && (
                      <div style={{ fontSize: 11, color: row.kenakan_sewa_armada_cb ? 'var(--color-warning)' : 'var(--text-tertiary)', fontWeight: 400 }}>
                        {row.kenakan_sewa_armada_cb ? 'sewa dipotong' : 'tanpa potongan sewa'}
                      </div>
                    )}
                  </td>
                  <td style={{ textAlign: 'right' }} className="table-mono">{formatRupiah(row.harga_bersih_per_kg ?? row.harga_harian)}</td>
                  <td style={{ textAlign: 'right' }} className="table-mono">{formatRupiah(row.total_nilai_bersih ?? row.total_kotor)}</td>
                  <td>
                    <div style={{ display: 'flex', gap: 8, justifyContent: 'center' }}>
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        title={lockReason || 'Edit transaksi'}
                        disabled={row.status === 'dibatalkan' || Boolean(lockReason)}
                        onClick={() => openEdit(row)}
                      >
                        <Pencil size={16} />
                      </button>
                      <button
                        type="button"
                        className="btn btn-ghost btn-sm"
                        title={lockReason || 'Batalkan transaksi'}
                        disabled={row.status === 'dibatalkan' || Boolean(lockReason)}
                        onClick={() => {
                          setCancelTarget(row);
                          setCancelReason('');
                        }}
                      >
                        <Ban size={16} />
                      </button>
                    </div>
                  </td>
                </tr>
                );
              })
            )}
          </tbody>
        </table>
        <TablePagination
          page={paginatedTransaksi.page}
          totalPages={paginatedTransaksi.totalPages}
          totalItems={sortedTransaksi.length}
          startIndex={paginatedTransaksi.startIndex}
          endIndex={paginatedTransaksi.endIndex}
          onPageChange={setPage}
        />
      </div>

      {editTarget && (
        <div className="modal-overlay" onClick={() => !saving && setEditTarget(null)}>
          <div className="modal" onClick={event => event.stopPropagation()} style={{ maxWidth: 760 }}>
            <div className="modal-header">
              <h3 className="modal-title">Edit Pengiriman Mitra</h3>
              <button className="modal-close" disabled={saving} onClick={() => setEditTarget(null)}>x</button>
            </div>
            <form onSubmit={handleSaveEdit}>
              <div className="modal-body">
                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Tanggal</label>
                    <input className="form-input" type="date" required value={editForm.tanggal} onChange={event => handleEditTanggalChange(event.target.value)} />
                  </div>
                  <div className="form-group">
                    <label className="form-label form-label-required">Berat Netto dari Pabrik (kg)</label>
                    <input className="form-input form-input-mono" type="number" required min={1} value={editForm.berat_netto} onChange={event => handleEditBeratNettoChange(event.target.value)} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Potongan Pabrik (kg)</label>
                    <input className="form-input form-input-mono" type="number" min={0} value={editForm.potongan_pabrik} onChange={event => handleEditPotonganChange(event.target.value)} />
                  </div>
                </div>

                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Harga Pabrik / TWB (Rp/Kg)</label>
                    <input
                      className="form-input form-input-mono"
                      type="number"
                      required
                      min={0}
                      value={editForm.harga_dasar}
                      onChange={event => handleEditHargaDasarChange(event.target.value)}
                    />
                    <div className="form-hint">Harga ini akan dikurangi Fee Owner aktif untuk menghitung Harga Bersih/Kg ke mitra.</div>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Fee Owner Aktif (Rp/Kg)</label>
                    <input className="form-input form-input-mono" value={formatRupiah(editFeeOwner)} readOnly />
                    <div className="form-hint">Diambil dari master mitra saat koreksi dilakukan.</div>
                  </div>
                </div>

                <div className="alert alert-info">
                  <div>
                    <strong>Sinkronkan Fee Owner dari master</strong>
                    <div style={{ marginTop: 4 }}>
                      Jika transaksi ini masih memakai Fee Owner 0 atau snapshot lama, klik tombol ini agar Fee Owner mengikuti master mitra untuk tanggal transaksi ini. Harga Bersih/Kg akan dihitung ulang dari Harga Pabrik/TWB dikurangi Fee Owner.
                    </div>
                    <button
                      type="button"
                      className="btn btn-outline btn-sm"
                      style={{ marginTop: 12 }}
                      onClick={handleSyncFeeFromMaster}
                    >
                      Sinkronkan Fee dari Master
                    </button>
                  </div>
                </div>

                <div className="form-group">
                  <label className="form-label form-label-required">Armada / Sopir Default</label>
                  <SearchableCombobox
                    value={editForm.sopir_default_id}
                    options={sopirs}
                    onChange={handleEditSopirDefaultChange}
                    getOptionLabel={formatSopirArmadaLabel}
                    getOptionDescription={formatSopirArmadaDescription}
                    getSearchText={getSopirArmadaSearchText}
                    placeholder="Cari sopir, plat, atau mitra..."
                    emptyLabel="Armada / sopir tidak ditemukan"
                  />
                </div>

                <div className="form-grid">
                  <div className="form-group">
                    <label className="form-label form-label-required">Plat Armada</label>
                    <input className="form-input form-input-mono" required value={editForm.plat_nomor} onChange={event => setEditForm({ ...editForm, plat_nomor: event.target.value })} />
                  </div>
                  <div className="form-group">
                    <label className="form-label form-label-required">Mitra Transaksi</label>
                    <SearchableCombobox
                      value={editForm.mitra_id}
                      options={mitras}
                      onChange={handleEditMitraChange}
                      getOptionLabel={formatMitraLabel}
                      getSearchText={getMitraSearchText}
                      placeholder="Cari kode, alamat, atau nama mitra..."
                      emptyLabel="Mitra tidak ditemukan"
                    />
                  </div>
                </div>

                {editUsesArmadaCb && (
                  <div style={{ border: '1px solid var(--color-info)', borderRadius: 8, padding: 16, marginBottom: 'var(--space-lg)' }}>
                    <div style={{ fontWeight: 700, marginBottom: 4 }}>Perlakuan Armada CB</div>
                    <div className="text-sm text-tertiary" style={{ marginBottom: 14 }}>
                      Perjalanan ini tetap masuk hitungan trip dan muatan Armada CB. Atur perlakuan uangnya di bawah ini.
                    </div>

                    <label style={{ display: 'flex', alignItems: 'flex-start', gap: 10, cursor: 'pointer', marginBottom: 12 }}>
                      <input
                        type="checkbox"
                        checked={editForm.kenakan_sewa_armada_cb}
                        onChange={event => setEditForm(recalculateTotals({
                          ...editForm,
                          pakai_sewa_armada_bl: event.target.checked,
                          kenakan_sewa_armada_cb: event.target.checked,
                          alasan_tanpa_sewa_armada_cb: event.target.checked ? '' : editForm.alasan_tanpa_sewa_armada_cb,
                        }))}
                        style={{ marginTop: 3 }}
                      />
                      <span>
                        <strong>Potong sewa dari pembayaran mitra</strong>
                        <span className="text-sm text-tertiary" style={{ display: 'block' }}>
                          {formatRupiah(editForm.tarif_sewa_angkut_per_kg)}/kg dari Berat Netto Pabrik
                        </span>
                      </span>
                    </label>

                    {!editForm.kenakan_sewa_armada_cb && (
                      <div className="form-group" style={{ marginLeft: 26 }}>
                        <label className="form-label form-label-required">Alasan tanpa potongan sewa</label>
                        <input
                          className="form-input"
                          list="edit-alasan-tanpa-sewa-armada"
                          required
                          value={editForm.alasan_tanpa_sewa_armada_cb}
                          onChange={event => setEditForm({ ...editForm, alasan_tanpa_sewa_armada_cb: event.target.value })}
                          placeholder="Pilih atau tulis alasan"
                        />
                        <datalist id="edit-alasan-tanpa-sewa-armada">
                          <option value="Bantuan armada tanpa biaya sewa" />
                          <option value="Mitra internal, sewa tidak dipotong" />
                          <option value="Keputusan Owner" />
                        </datalist>
                      </div>
                    )}

                    <label style={{ display: 'flex', alignItems: 'flex-start', gap: 10, cursor: 'pointer' }}>
                      <input
                        type="checkbox"
                        checked={editForm.catat_dana_operasional_trip}
                        onChange={event => setEditForm({
                          ...editForm,
                          catat_dana_operasional_trip: event.target.checked,
                          alasan_tanpa_dana_operasional_trip: event.target.checked ? '' : editForm.alasan_tanpa_dana_operasional_trip,
                        })}
                        style={{ marginTop: 3 }}
                      />
                      <span>
                        <strong>Buat Dana Operasional Trip</strong>
                        <span className="text-sm text-tertiary" style={{ display: 'block' }}>
                          {formatRupiah(editForm.dana_operasional_trip)} untuk satu kali jalan
                        </span>
                      </span>
                    </label>

                    {!editForm.catat_dana_operasional_trip && (
                      <div className="form-group" style={{ marginLeft: 26, marginTop: 12, marginBottom: 0 }}>
                        <label className="form-label form-label-required">Alasan tanpa Dana Operasional Trip</label>
                        <input
                          className="form-input"
                          list="edit-alasan-tanpa-dana-trip"
                          required
                          value={editForm.alasan_tanpa_dana_operasional_trip}
                          onChange={event => setEditForm({ ...editForm, alasan_tanpa_dana_operasional_trip: event.target.value })}
                          placeholder="Pilih atau tulis alasan"
                        />
                        <datalist id="edit-alasan-tanpa-dana-trip">
                          <option value="Dana dibayar di luar transaksi ini" />
                          <option value="Tidak ada Dana Operasional Trip" />
                          <option value="Keputusan Owner" />
                        </datalist>
                      </div>
                    )}
                  </div>
                )}

                <div className="form-group">
                  <label className="form-label form-label-required">Sopir Aktual</label>
                  <select className="form-input" value={editForm.sopir_aktual_mode} onChange={event => handleEditSopirAktualModeChange(event.target.value)}>
                    <option value={SOPIR_AKTUAL_DEFAULT}>Sama dengan sopir default</option>
                    <option value={SOPIR_AKTUAL_MASTER}>Pilih sopir lain dari master</option>
                    <option value={SOPIR_AKTUAL_MANUAL}>Input sopir pengganti manual</option>
                  </select>
                </div>

                {editForm.sopir_aktual_mode === SOPIR_AKTUAL_MASTER && (
                  <div className="form-group">
                    <label className="form-label form-label-required">Pilih Sopir Pengganti</label>
                    <SearchableCombobox
                      value={editForm.sopir_aktual_id}
                      options={sopirs}
                      onChange={handleEditSopirAktualMasterChange}
                      getOptionLabel={formatSopirArmadaLabel}
                      getOptionDescription={formatSopirArmadaDescription}
                      getSearchText={getSopirArmadaSearchText}
                      placeholder="Cari sopir pengganti..."
                      emptyLabel="Sopir tidak ditemukan"
                    />
                  </div>
                )}

                {editForm.sopir_aktual_mode === SOPIR_AKTUAL_MANUAL && (
                  <div className="form-grid">
                    <div className="form-group">
                      <label className="form-label form-label-required">Nama Sopir Pengganti</label>
                      <input className="form-input" required value={editForm.sopir_aktual_nama} onChange={event => setEditForm({ ...editForm, sopir_aktual_nama: event.target.value })} />
                    </div>
                    <div className="form-group">
                      <label className="form-label">No. HP</label>
                      <input className="form-input" value={editForm.sopir_aktual_no_hp} onChange={event => setEditForm({ ...editForm, sopir_aktual_no_hp: event.target.value })} />
                    </div>
                  </div>
                )}

                {editForm.sopir_aktual_mode !== SOPIR_AKTUAL_DEFAULT && (
                  <div className="form-group">
                    <label className="form-label">Catatan Pergantian Sopir</label>
                    <input className="form-input" value={editForm.catatan_sopir} onChange={event => setEditForm({ ...editForm, catatan_sopir: event.target.value })} />
                  </div>
                )}

                <div className="card" style={{ padding: 'var(--space-md)', marginBottom: 'var(--space-lg)' }}>
                  {(() => {
                    const beratNetto   = parseFloat(editForm.berat_netto) || 0;
                    const potongan     = parseFloat(editForm.potongan_pabrik) || 0;
                    const beratDibayar = Math.max(0, beratNetto - potongan);
                    return (
                      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                          <span style={{ color: 'var(--text-tertiary)', fontSize: 13 }}>Berat Netto dari Pabrik:</span>
                          <strong>{beratNetto.toLocaleString('id-ID')} kg</strong>
                        </div>
                        {potongan > 0 && (
                          <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                            <span style={{ color: 'var(--color-warning)', fontSize: 13 }}>Potongan Pabrik:</span>
                            <strong style={{ color: 'var(--color-warning)' }}>−{potongan.toLocaleString('id-ID')} kg</strong>
                          </div>
                        )}
                        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, borderTop: '1px solid var(--border-default)', paddingTop: 6 }}>
                          <span style={{ fontSize: 13, fontWeight: 600 }}>Berat Dibayar:</span>
                          <strong>{beratDibayar.toLocaleString('id-ID')} kg</strong>
                        </div>
                        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap', paddingTop: 6, borderTop: '1px solid var(--border-default)' }}>
                          <span style={{ fontSize: 13 }}>Harga Pabrik/TWB: <strong>{formatRupiah(editForm.harga_dasar)}</strong></span>
                          <span style={{ fontSize: 13 }}>Fee Owner: <strong>{formatRupiah(editFeeOwner)}</strong></span>
                          <span style={{ fontSize: 13 }}>Harga Bersih/Kg: <strong>{formatRupiah(editForm.harga_harian)}</strong></span>
                        </div>
                        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' }}>
                          <span style={{ fontSize: 13 }}>Total Kotor: <strong>{formatRupiah(editForm.total_kotor)}</strong></span>
                          <span style={{ fontSize: 13 }}>Nilai Bersih Mitra: <strong style={{ color: 'var(--color-success)' }}>{formatRupiah(editForm.total_nilai_bersih)}</strong></span>
                          {editUsesArmadaCb && editForm.kenakan_sewa_armada_cb && (
                            <span style={{ fontSize: 13 }}>Sewa Armada CB: <strong style={{ color: 'var(--color-warning)' }}>{formatRupiah(editForm.biaya_sewa_armada_total)}</strong></span>
                          )}
                        </div>
                      </div>
                    );
                  })()}
                </div>

                <div className="form-group">
                  <label className="form-label form-label-required">Alasan Edit</label>
                  <textarea
                    className="form-input"
                    required
                    rows={3}
                    value={editForm.alasan_edit}
                    onChange={event => setEditForm({ ...editForm, alasan_edit: event.target.value })}
                    placeholder="Contoh: salah pilih plat / tonase typo"
                  />
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" disabled={saving} onClick={() => setEditTarget(null)}>Batal</button>
                <button type="submit" className="btn btn-primary" disabled={saving}>
                  {saving ? 'Menyimpan...' : 'Simpan Perubahan'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {cancelTarget && (
        <div className="modal-overlay" onClick={() => !saving && setCancelTarget(null)}>
          <div className="modal" onClick={event => event.stopPropagation()} style={{ maxWidth: 520 }}>
            <div className="modal-header">
              <h3 className="modal-title">Batalkan Pengiriman</h3>
              <button className="modal-close" disabled={saving} onClick={() => setCancelTarget(null)}>x</button>
            </div>
            <form onSubmit={handleCancelTransaction}>
              <div className="modal-body">
                <p className="text-secondary" style={{ marginBottom: 16 }}>
                  Transaksi {formatDateDisplay(cancelTarget.tanggal)} - {formatMitraLabel(cancelTarget.master_mitra)} akan ditandai dibatalkan. Data tidak dihapus.
                </p>
                <div className="form-group">
                  <label className="form-label form-label-required">Alasan Batal</label>
                  <textarea
                    className="form-input"
                    required
                    rows={3}
                    value={cancelReason}
                    onChange={event => setCancelReason(event.target.value)}
                    placeholder="Contoh: double input / salah transaksi"
                  />
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" disabled={saving} onClick={() => setCancelTarget(null)}>Kembali</button>
                <button type="submit" className="btn btn-danger" disabled={saving}>
                  {saving ? 'Membatalkan...' : 'Batalkan Transaksi'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AppShell>
  );
}

