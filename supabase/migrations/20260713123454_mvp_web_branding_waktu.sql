-- Sawit CB - Pengaturan branding web dan index waktu transaksi MVP
-- Non-destruktif: memakai created_at transaksi_mitra sebagai kolom "Waktu".

BEGIN;

ALTER TABLE IF EXISTS public.transaksi_mitra
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_transaksi_mitra_tanggal_created_at
  ON public.transaksi_mitra (tanggal DESC, created_at DESC);

INSERT INTO public.pengaturan_bisnis (key, value_json, scope, aktif)
SELECT
  'web_branding',
  '{
    "appName": "SAWIT CB",
    "appSubtitle": "Manajemen RAM",
    "logoColorPath": "",
    "logoPrintPath": "",
    "printLogoMode": "auto_black"
  }'::jsonb,
  'global',
  true
WHERE EXISTS (
  SELECT 1
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name = 'pengaturan_bisnis'
)
AND NOT EXISTS (
  SELECT 1
  FROM public.pengaturan_bisnis
  WHERE key = 'web_branding'
    AND scope = 'global'
    AND aktif = true
);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('branding', 'branding', true, 819200, ARRAY['image/png'])
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "branding_owner_insert" ON storage.objects;
CREATE POLICY "branding_owner_insert"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'branding'
  AND public.has_app_role(ARRAY['owner', 'super_admin'])
);

DROP POLICY IF EXISTS "branding_owner_delete" ON storage.objects;
CREATE POLICY "branding_owner_delete"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'branding'
  AND public.has_app_role(ARRAY['owner', 'super_admin'])
);

COMMIT;
