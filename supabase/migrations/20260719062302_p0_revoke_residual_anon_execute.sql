-- Close residual function privileges discovered by the hosted staging audit.
-- The operational RPC requires an authenticated actor; trigger functions are
-- invoked by PostgreSQL and must not be directly callable by application roles.

REVOKE ALL ON FUNCTION public.create_pengiriman_lokal(date, uuid, numeric, text, uuid, uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_pengiriman_lokal(date, uuid, numeric, text, uuid, uuid)
TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.enforce_kwitansi_aggregates()
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.enforce_tbs_snapshot_calculation()
FROM PUBLIC, anon, authenticated;
