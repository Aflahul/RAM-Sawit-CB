'use client';

import { useEffect, useState } from 'react';
import { AlertTriangle, FileText, X } from 'lucide-react';

export default function PromptDialog({
  open,
  title,
  message,
  label = 'Alasan',
  placeholder = 'Tulis alasan...',
  defaultValue = '',
  confirmText = 'Simpan',
  cancelText = 'Batal',
  variant = 'danger',
  required = true,
  multiline = true,
  loading = false,
  onConfirm,
  onCancel,
}) {
  const [value, setValue] = useState(defaultValue);
  const [error, setError] = useState('');

  useEffect(() => {
    if (open) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setValue(defaultValue);
      setError('');
    }
  }, [defaultValue, open]);

  if (!open) return null;

  const Icon = variant === 'danger' ? AlertTriangle : FileText;

  function handleSubmit(event) {
    event.preventDefault();
    const trimmed = value.trim();

    if (required && !trimmed) {
      setError(`${label} wajib diisi.`);
      return;
    }

    onConfirm?.(trimmed);
  }

  return (
    <div className="modal-overlay" onClick={() => !loading && onCancel?.()}>
      <div className="modal" onClick={(event) => event.stopPropagation()} style={{ maxWidth: 480 }}>
        <div className="modal-header">
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-sm)' }}>
            <span className={variant === 'danger' ? 'text-danger' : 'text-primary'}>
              <Icon size={22} />
            </span>
            <h3 className="modal-title">{title || 'Isi Alasan'}</h3>
          </div>
          <button className="modal-close" onClick={onCancel} disabled={loading} aria-label="Tutup">
            <X size={18} />
          </button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="modal-body" style={{ maxHeight: 'min(68vh, 520px)', overflowY: 'auto' }}>
            {message && (
              <p className="text-secondary" style={{ marginBottom: 'var(--space-md)', fontSize: 'var(--text-sm)', lineHeight: 1.6 }}>
                {message}
              </p>
            )}
            <div className="form-group">
              <label className={`form-label ${required ? 'form-label-required' : ''}`}>{label}</label>
              {multiline ? (
                <textarea
                  className="form-input"
                  value={value}
                  onChange={(event) => {
                    setValue(event.target.value);
                    setError('');
                  }}
                  placeholder={placeholder}
                  rows={4}
                  autoFocus
                />
              ) : (
                <input
                  className="form-input"
                  value={value}
                  onChange={(event) => {
                    setValue(event.target.value);
                    setError('');
                  }}
                  placeholder={placeholder}
                  autoFocus
                />
              )}
              {error && <div className="form-error">{error}</div>}
            </div>
          </div>
          <div className="modal-footer">
            <button type="button" className="btn btn-outline" onClick={onCancel} disabled={loading}>
              {cancelText}
            </button>
            <button type="submit" className={`btn ${variant === 'danger' ? 'btn-danger' : 'btn-primary'}`} disabled={loading}>
              {loading ? 'Memproses...' : confirmText}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
