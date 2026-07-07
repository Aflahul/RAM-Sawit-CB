'use client';

import { useState } from 'react';

export default function ConfirmDialog({ open, title, message, confirmText, cancelText, variant, onConfirm, onCancel }) {
  if (!open) return null;

  const variantStyles = {
    danger: { color: 'var(--color-danger)', bg: 'var(--color-danger-bg)' },
    warning: { color: 'var(--color-warning)', bg: 'var(--color-warning-bg)' },
    info: { color: 'var(--color-primary-400)', bg: 'var(--color-primary-700)' },
  };

  const style = variantStyles[variant] || variantStyles.danger;

  return (
    <div className="modal-overlay" onClick={onCancel}>
      <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: 420 }}>
        <div className="modal-body" style={{ textAlign: 'center', paddingTop: 'var(--space-xl)' }}>
          <div style={{
            width: 56, height: 56, borderRadius: '50%',
            background: style.bg, display: 'flex', alignItems: 'center',
            justifyContent: 'center', margin: '0 auto var(--space-md)',
            fontSize: 28,
          }}>
            {variant === 'danger' ? '⚠️' : variant === 'warning' ? '❓' : 'ℹ️'}
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
