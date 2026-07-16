-- Keep explicit audit actions for the loan workflow while preserving every
-- previously allowed action.

ALTER TABLE public.audit_log
  DROP CONSTRAINT IF EXISTS audit_log_action_check;

ALTER TABLE public.audit_log
  ADD CONSTRAINT audit_log_action_check
  CHECK (action IN (
    'create',
    'update',
    'delete',
    'cancel',
    'approve',
    'export',
    'override',
    'verify',
    'cancel_payment',
    'reverse_manual_cash',
    'reverse_dana_trip',
    'create_request',
    'setujui',
    'tolak',
    'disburse',
    'repayment',
    'reconcile_legacy_opening'
  ));
