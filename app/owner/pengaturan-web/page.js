'use client';

import { useCallback, useEffect, useState } from 'react';
import { AlertCircle, CheckCircle2, ImagePlus, Printer, Save, Trash2, Upload } from 'lucide-react';
import BrandMark from '@/components/branding/BrandMark';
import AppShell from '@/components/layout/AppShell';
import { DEFAULT_BRANDING, normalizeBranding } from '@/lib/branding';
import { canManageBusinessSettings, normalizeRole } from '@/lib/roles';
import { supabase } from '@/lib/supabase';
import { saveBrandingSettings, uploadBrandingLogo, useBrandingSettings } from '@/lib/use-branding-settings';

const MAX_LOGO_BYTES = 800 * 1024;

export default function PengaturanWebPage() {
  const { branding, loading: brandingLoading, reloadBranding } = useBrandingSettings();
  const [form, setForm] = useState(DEFAULT_BRANDING);
  const [userRole, setUserRole] = useState(null);
  const [saving, setSaving] = useState(false);
  const [uploadingLogo, setUploadingLogo] = useState('');
  const [message, setMessage] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

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

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    checkRole();
  }, [checkRole]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setForm(normalizeBranding(branding));
  }, [branding]);

  async function handleLogoUpload(event, kind) {
    const file = event.target.files?.[0];
    event.target.value = '';
    setMessage('');
    setErrorMsg('');

    if (!file) return;
    if (file.type !== 'image/png') {
      setErrorMsg('Logo harus berupa file PNG. Gunakan PNG transparan agar hasil cetak lebih bersih.');
      return;
    }
    if (file.size > MAX_LOGO_BYTES) {
      setErrorMsg('Ukuran logo maksimal 800 KB agar aplikasi tetap ringan.');
      return;
    }

    try {
      setUploadingLogo(kind);
      const uploaded = await uploadBrandingLogo(file, kind);
      setForm(current => kind === 'print'
        ? { ...current, logoPrintPath: uploaded.path, logoPrintUrl: uploaded.url }
        : { ...current, logoColorPath: uploaded.path, logoColorUrl: uploaded.url }
      );
      setMessage('Logo berhasil diupload ke Storage. Klik Simpan Pengaturan untuk memakai logo ini.');
    } catch (error) {
      setErrorMsg(`Gagal upload logo: ${error.message}`);
    } finally {
      setUploadingLogo('');
    }
  }

  async function handleSave(event) {
    event.preventDefault();
    if (saving) return;

    setSaving(true);
    setMessage('');
    setErrorMsg('');

    try {
      const saved = await saveBrandingSettings(form);
      setForm(saved);
      await reloadBranding();
      setMessage('Pengaturan web berhasil disimpan.');
    } catch (error) {
      setErrorMsg(`Gagal menyimpan pengaturan: ${error.message}`);
    } finally {
      setSaving(false);
    }
  }

  if (userRole !== null && !canManageBusinessSettings(userRole)) {
    return (
      <AppShell title="Pengaturan Web" subtitle="Akses terbatas">
        <div className="empty-state" style={{ marginTop: 'var(--space-3xl)' }}>
          <div className="empty-state-title">Akses Ditolak</div>
          <div className="empty-state-text">
            Pengaturan Web hanya dapat diakses oleh Owner dan Super Admin.
          </div>
        </div>
      </AppShell>
    );
  }

  if (userRole === null || brandingLoading) {
    return (
      <AppShell title="Pengaturan Web">
        <div style={{ textAlign: 'center', padding: 'var(--space-3xl)' }}>
          <div className="spinner spinner-lg" style={{ margin: '0 auto' }} />
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title="Pengaturan Web" subtitle="Logo dan identitas aplikasi">
      <div className="page-header">
        <div>
          <h2 className="page-title">Pengaturan Web</h2>
          <p className="page-description">Atur nama aplikasi, logo website, dan logo kwitansi cetak</p>
        </div>
      </div>

      {message && (
        <div className="alert alert-success">
          <CheckCircle2 size={18} />
          <div>{message}</div>
        </div>
      )}

      {errorMsg && (
        <div className="alert alert-danger">
          <AlertCircle size={18} />
          <div>{errorMsg}</div>
        </div>
      )}

      <form onSubmit={handleSave} className="web-settings-layout">
        <div className="card web-settings-panel">
          <div className="form-grid">
            <div className="form-group">
              <label className="form-label form-label-required">Nama Aplikasi</label>
              <input
                className="form-input"
                required
                value={form.appName}
                onChange={event => setForm(current => ({ ...current, appName: event.target.value }))}
              />
            </div>
            <div className="form-group">
              <label className="form-label form-label-required">Subjudul Aplikasi</label>
              <input
                className="form-input"
                required
                value={form.appSubtitle}
                onChange={event => setForm(current => ({ ...current, appSubtitle: event.target.value }))}
              />
            </div>
          </div>

          <div className="web-logo-grid">
            <div className="web-logo-control">
              <div className="web-logo-control-header">
                <ImagePlus size={18} />
                <div>
                  <strong>Logo Website Berwarna</strong>
                  <p>PNG transparan untuk sidebar dan identitas aplikasi.</p>
                </div>
              </div>
              <div className="web-logo-actions">
                <label className={`btn btn-outline ${uploadingLogo === 'color' ? 'disabled' : ''}`}>
                  <Upload size={16} />
                  {uploadingLogo === 'color' ? 'Mengupload...' : 'Upload PNG'}
                  <input
                    type="file"
                    accept="image/png"
                    hidden
                    disabled={Boolean(uploadingLogo)}
                    onChange={event => handleLogoUpload(event, 'color')}
                  />
                </label>
                <button
                  type="button"
                  className="btn btn-ghost btn-sm"
                  onClick={() => setForm(current => ({ ...current, logoColorPath: '', logoColorUrl: '', logoColorDataUrl: '' }))}
                >
                  <Trash2 size={16} />
                  Hapus
                </button>
              </div>
            </div>

            <div className="web-logo-control">
              <div className="web-logo-control-header">
                <Printer size={18} />
                <div>
                  <strong>Logo Kwitansi Hitam</strong>
                  <p>Opsional. Jika kosong, logo berwarna otomatis dibuat hitam saat cetak.</p>
                </div>
              </div>
              <div className="web-logo-actions">
                <label className={`btn btn-outline ${uploadingLogo === 'print' ? 'disabled' : ''}`}>
                  <Upload size={16} />
                  {uploadingLogo === 'print' ? 'Mengupload...' : 'Upload PNG'}
                  <input
                    type="file"
                    accept="image/png"
                    hidden
                    disabled={Boolean(uploadingLogo)}
                    onChange={event => handleLogoUpload(event, 'print')}
                  />
                </label>
                <button
                  type="button"
                  className="btn btn-ghost btn-sm"
                  onClick={() => setForm(current => ({ ...current, logoPrintPath: '', logoPrintUrl: '', logoPrintDataUrl: '' }))}
                >
                  <Trash2 size={16} />
                  Hapus
                </button>
              </div>
            </div>
          </div>

          <div className="form-group">
            <label className="form-label">Mode Logo Kwitansi Jika Tidak Ada Logo Hitam</label>
            <select
              className="form-input form-select"
              value={form.printLogoMode}
              onChange={event => setForm(current => ({ ...current, printLogoMode: event.target.value }))}
            >
              <option value="auto_black">Otomatis hitam dari logo berwarna</option>
              <option value="original">Pakai warna asli</option>
            </select>
            <div className="form-hint">
              Untuk kwitansi, pilihan terbaik adalah otomatis hitam atau upload PNG hitam khusus.
            </div>
          </div>

          <div className="form-actions">
            <button type="submit" className="btn btn-primary" disabled={saving || Boolean(uploadingLogo)}>
              <Save size={16} />
              {saving ? 'Menyimpan...' : 'Simpan Pengaturan'}
            </button>
          </div>
        </div>

        <div className="web-settings-preview">
          <div className="web-preview-block">
            <div className="web-preview-label">Preview Website</div>
            <div className="web-preview-sidebar">
              <BrandMark branding={form} size={48} />
              <div>
                <div className="web-preview-title">{form.appName}</div>
                <div className="web-preview-subtitle">{form.appSubtitle}</div>
              </div>
            </div>
          </div>

          <div className="web-preview-block web-preview-print">
            <div className="web-preview-label">Preview Kwitansi</div>
            <div className="web-preview-receipt">
              <BrandMark branding={form} mode="print" size={58} />
              <div>
                <div className="web-preview-receipt-title">KWITANSI PEMBAYARAN TBS</div>
                <div className="web-preview-receipt-subtitle">{form.appName}</div>
                <div className="web-preview-receipt-line" />
              </div>
            </div>
          </div>
        </div>
      </form>

      <style jsx global>{`
        .web-settings-layout {
          display: grid;
          grid-template-columns: minmax(0, 1.15fr) minmax(300px, 0.85fr);
          gap: var(--space-lg);
          align-items: start;
        }

        .web-settings-panel .form-group:last-child {
          margin-bottom: 0;
        }

        .web-logo-grid {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: var(--space-md);
          margin-bottom: var(--space-lg);
        }

        .web-logo-control {
          min-width: 0;
          padding: var(--space-md);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-md);
          background: rgba(15, 23, 42, 0.38);
        }

        .web-logo-control-header {
          display: flex;
          gap: var(--space-sm);
          align-items: flex-start;
          margin-bottom: var(--space-md);
        }

        .web-logo-control-header p {
          margin: 4px 0 0;
          color: var(--text-tertiary);
          font-size: var(--text-xs);
          line-height: 1.45;
        }

        .web-logo-actions {
          display: flex;
          flex-wrap: wrap;
          gap: var(--space-sm);
        }

        .web-logo-actions .btn.disabled {
          opacity: 0.55;
          pointer-events: none;
        }

        .web-settings-preview {
          display: grid;
          gap: var(--space-md);
        }

        .web-preview-block {
          padding: var(--space-lg);
          border: 1px solid var(--border-default);
          border-radius: var(--radius-lg);
          background: var(--glass-bg);
          box-shadow: var(--shadow-md);
        }

        .web-preview-label {
          margin-bottom: var(--space-md);
          color: var(--text-tertiary);
          font-size: var(--text-xs);
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }

        .web-preview-sidebar {
          display: flex;
          align-items: center;
          gap: var(--space-md);
        }

        .web-preview-title {
          color: var(--text-primary);
          font-size: var(--text-lg);
          font-weight: 800;
          line-height: 1.2;
        }

        .web-preview-subtitle {
          color: var(--text-tertiary);
          font-size: var(--text-sm);
        }

        .web-preview-print {
          background: #fff;
          color: #000;
        }

        .web-preview-print .web-preview-label {
          color: #555;
        }

        .web-preview-receipt {
          display: flex;
          align-items: center;
          gap: 16px;
        }

        .web-preview-receipt-title {
          font-size: 16px;
          font-weight: 900;
          letter-spacing: 0;
        }

        .web-preview-receipt-subtitle {
          margin-top: 3px;
          color: #333;
          font-size: 13px;
        }

        .web-preview-receipt-line {
          margin-top: 12px;
          width: min(220px, 44vw);
          border-top: 1px dashed #222;
        }

        @media (max-width: 960px) {
          .web-settings-layout,
          .web-logo-grid {
            grid-template-columns: 1fr;
          }
        }
      `}</style>
    </AppShell>
  );
}
