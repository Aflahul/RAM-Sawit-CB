export const BRANDING_SETTING_KEY = 'web_branding';
export const BRANDING_BUCKET = 'branding';

export const DEFAULT_BRANDING = {
  appName: 'SAWIT CB',
  appSubtitle: 'Manajemen RAM',
  logoColorPath: '',
  logoPrintPath: '',
  logoColorUrl: '',
  logoPrintUrl: '',
  logoColorDataUrl: '',
  logoPrintDataUrl: '',
  printLogoMode: 'auto_black',
};

export function normalizeBranding(value) {
  const branding = value && typeof value === 'object' ? value : {};

  return {
    ...DEFAULT_BRANDING,
    ...branding,
    appName: String(branding.appName || DEFAULT_BRANDING.appName).trim() || DEFAULT_BRANDING.appName,
    appSubtitle: String(branding.appSubtitle || DEFAULT_BRANDING.appSubtitle).trim() || DEFAULT_BRANDING.appSubtitle,
    logoColorPath: String(branding.logoColorPath || ''),
    logoPrintPath: String(branding.logoPrintPath || ''),
    logoColorUrl: String(branding.logoColorUrl || ''),
    logoPrintUrl: String(branding.logoPrintUrl || ''),
    logoColorDataUrl: String(branding.logoColorDataUrl || ''),
    logoPrintDataUrl: String(branding.logoPrintDataUrl || ''),
    printLogoMode: branding.printLogoMode === 'original' ? 'original' : 'auto_black',
  };
}

export function getScreenLogoSource(value) {
  const branding = normalizeBranding(value);
  return branding.logoColorUrl || branding.logoColorDataUrl || '';
}

export function getPrintLogoSource(value) {
  const branding = normalizeBranding(value);
  return branding.logoPrintUrl || branding.logoPrintDataUrl || getScreenLogoSource(branding);
}

export function shouldAutoBlackPrintLogo(value) {
  const branding = normalizeBranding(value);
  return Boolean(
    getScreenLogoSource(branding)
    && !branding.logoPrintUrl
    && !branding.logoPrintDataUrl
    && branding.printLogoMode === 'auto_black'
  );
}

export function serializeBrandingSettings(value) {
  const branding = normalizeBranding(value);

  return {
    appName: branding.appName,
    appSubtitle: branding.appSubtitle,
    logoColorPath: branding.logoColorPath,
    logoPrintPath: branding.logoPrintPath,
    printLogoMode: branding.printLogoMode,
  };
}
