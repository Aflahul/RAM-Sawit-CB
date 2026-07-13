'use client';

import { useCallback, useEffect, useState } from 'react';
import {
  BRANDING_BUCKET,
  BRANDING_SETTING_KEY,
  DEFAULT_BRANDING,
  normalizeBranding,
  serializeBrandingSettings,
} from '@/lib/branding';
import { supabase } from '@/lib/supabase';

function getPublicLogoUrl(path) {
  if (!path) return '';
  const { data } = supabase.storage.from(BRANDING_BUCKET).getPublicUrl(path);
  return data?.publicUrl || '';
}

function resolveBrandingStorageUrls(value) {
  const branding = normalizeBranding(value);

  return {
    ...branding,
    logoColorUrl: getPublicLogoUrl(branding.logoColorPath),
    logoPrintUrl: getPublicLogoUrl(branding.logoPrintPath),
  };
}

export function useBrandingSettings() {
  const [branding, setBranding] = useState(DEFAULT_BRANDING);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const loadBranding = useCallback(async () => {
    setLoading(true);
    setError('');

    const { data, error: loadError } = await supabase
      .from('pengaturan_bisnis')
      .select('value_json')
      .eq('key', BRANDING_SETTING_KEY)
      .eq('scope', 'global')
      .eq('aktif', true)
      .maybeSingle();

    if (loadError) {
      console.warn('Gagal memuat pengaturan branding:', loadError.message);
      setBranding(DEFAULT_BRANDING);
      setError(loadError.message);
      setLoading(false);
      return;
    }

    setBranding(resolveBrandingStorageUrls(data?.value_json));
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadBranding();
  }, [loadBranding]);

  return { branding, setBranding, loading, error, reloadBranding: loadBranding };
}

export async function saveBrandingSettings(nextBranding) {
  const branding = serializeBrandingSettings(nextBranding);
  const { data: { session } } = await supabase.auth.getSession();
  const updatedBy = session?.user?.id || null;

  const { data: existing, error: loadError } = await supabase
    .from('pengaturan_bisnis')
    .select('id')
    .eq('key', BRANDING_SETTING_KEY)
    .eq('scope', 'global')
    .eq('aktif', true)
    .maybeSingle();

  if (loadError) throw loadError;

  if (existing?.id) {
    const { error } = await supabase
      .from('pengaturan_bisnis')
      .update({
        value_json: branding,
        updated_at: new Date().toISOString(),
        updated_by: updatedBy,
      })
      .eq('id', existing.id);

    if (error) throw error;
    return resolveBrandingStorageUrls(branding);
  }

  const { error } = await supabase
    .from('pengaturan_bisnis')
    .insert({
      key: BRANDING_SETTING_KEY,
      scope: 'global',
      aktif: true,
      value_json: branding,
      updated_by: updatedBy,
    });

  if (error) throw error;
  return resolveBrandingStorageUrls(branding);
}

export async function uploadBrandingLogo(file, kind) {
  const suffix = kind === 'print' ? 'print' : 'color';
  const filename = `logos/${suffix}-${Date.now()}.png`;
  const { data, error } = await supabase.storage
    .from(BRANDING_BUCKET)
    .upload(filename, file, {
      cacheControl: '3600',
      contentType: 'image/png',
      upsert: false,
    });

  if (error) throw error;

  const path = data?.path || filename;
  return {
    path,
    url: getPublicLogoUrl(path),
  };
}

export async function removeBrandingLogo(path) {
  if (!path) return;
  const { error } = await supabase.storage.from(BRANDING_BUCKET).remove([path]);
  if (error) throw error;
}
