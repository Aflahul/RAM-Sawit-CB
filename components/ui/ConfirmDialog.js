'use client';

import { AlertTriangle, CircleHelp, Info } from 'lucide-react';

export default function ConfirmDialog({
  open,
  title,
  message,
  confirmText,
  cancelText,
  variant = 'danger',
  onConfirm,
  onCancel,
}) {
  if (!open) return null;

  const variantStyles = {
    danger: { color: 'var(--color-danger)', bg: 'var(--color-danger-bg)', icon: AlertTriangle },
    warning: { color: 'var(--color-warning)', bg: 'var(--color-warning-bg)', icon: CircleHelp },
    info: { color: 'var(--color-primary-400)', bg: 'var(--color-primary-700)', icon: Info },
  };

  const style = variantStyles[variant] || variantStyles.danger;
  const Icon = style.icon;

  return (
    <div className="modal-overlay" onClick={onCancel}>
      <div className="modal" onClick={(event) => event.stopPropagation()} style={{ maxWidth: 420 }}>
        <div className="modal-body" style={{ textAlign: 'center', paddingTop: 'var(--space-xl)' }}>
          <div style={{
            width: 56,
            height: 56,
            borderRadius: '50%',
            background: style.bg,
            color: style.color,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            margin: '0 auto var(--space-md)',
          }}>
            <Icon size={28} />
          </div>
          <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-sm)' }}>
            {title || 'Konfirmasi'}
          </h3>
          <p className="text-secondary" style={{ fontSize: 'var(--text-sm)', lineHeight: 1.6 }}>
            {message || 'Apakah Anda yakin?'}
          </p>
        </div>
        <div className="modal-footer" style={{ justifyContent: 'center' }}>
          <button className="btn btn-outline" onClick={onCancel}>
            {cancelText || 'Batal'}
          </button>
          <button
            className={`btn ${variant === 'danger' ? 'btn-danger' : 'btn-primary'}`}
            onClick={onConfirm}
          >
            {confirmText || 'Ya, Lanjutkan'}
          </button>
        </div>
      </div>
    </div>
  );
}
