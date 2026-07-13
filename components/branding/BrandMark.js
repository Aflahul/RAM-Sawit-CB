import Image from 'next/image';
import { normalizeBranding, getPrintLogoSource, getScreenLogoSource, shouldAutoBlackPrintLogo } from '@/lib/branding';

function LeafFallback() {
  return (
    <svg width="58%" height="58%" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z" />
      <path d="M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12" />
    </svg>
  );
}

export default function BrandMark({ branding: rawBranding, mode = 'screen', size = 40, className = '' }) {
  const branding = normalizeBranding(rawBranding);
  const isPrint = mode === 'print';
  const source = isPrint ? getPrintLogoSource(branding) : getScreenLogoSource(branding);
  const autoBlack = isPrint && shouldAutoBlackPrintLogo(branding);
  const fallbackClasses = [
    className,
    'brand-mark',
    isPrint ? 'brand-mark-print' : 'brand-mark-screen',
  ].filter(Boolean).join(' ');

  if (source) {
    return (
      <span
        className={fallbackClasses}
        style={{
          width: size,
          height: size,
          color: isPrint ? '#000' : undefined,
          background: isPrint ? '#fff' : 'rgba(15, 23, 42, 0.18)',
          boxShadow: isPrint ? 'none' : undefined,
        }}
      >
        <Image
          src={source}
          alt={`Logo ${branding.appName}`}
          width={size}
          height={size}
          unoptimized
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'contain',
            filter: autoBlack ? 'grayscale(1) brightness(0)' : undefined,
          }}
        />
      </span>
    );
  }

  return (
    <span
      className={fallbackClasses}
      style={{
        width: size,
        height: size,
        color: isPrint ? '#000' : undefined,
        background: isPrint ? '#fff' : undefined,
        boxShadow: isPrint ? 'none' : undefined,
        border: isPrint ? '1px solid #000' : undefined,
      }}
      aria-label={`Logo ${branding.appName}`}
    >
      <LeafFallback />
    </span>
  );
}
