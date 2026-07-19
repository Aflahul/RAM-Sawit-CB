-- Pin legacy helper functions to an empty search path so object resolution
-- cannot be influenced by caller-controlled schemas.
ALTER FUNCTION public.next_no_struk_tbs(date) SET search_path = '';
ALTER FUNCTION public.normalize_plat_nomor(text) SET search_path = '';
ALTER FUNCTION public.require_factory_payment_proof() SET search_path = '';
ALTER FUNCTION public.set_updated_at() SET search_path = '';
