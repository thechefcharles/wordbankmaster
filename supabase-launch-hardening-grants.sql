-- Tier 0 launch-readiness hardening — security audit 2026-07-16.
--
-- Root cause: early blanket GRANTs (EXECUTE ON ALL FUNCTIONS; INSERT/UPDATE/DELETE ON ALL TABLES)
-- to anon/authenticated exposed internal `_`-prefixed helper RPCs — callable directly with the
-- anon key shipped in the client bundle — and left one table (credit_history) RLS-off with public
-- write grants.
--
-- Safe because: all gameplay writes flow through SECURITY DEFINER *public* entrypoints, which run
-- as the owner and call the helpers internally (unaffected by caller grants). The client calls ZERO
-- `_`-prefixed RPCs and makes exactly one direct table write — profiles INSERT of its own row,
-- gated by the RLS `with_check (auth.uid() = id)` policy — which is preserved below.

BEGIN;

-- 1) Revoke direct EXECUTE on every internal (`_`-prefixed) helper from the public API roles.
--    Closes: CRITICAL _finalize_daily (unlimited virtual-currency mint), HIGH _cg_bust /
--    _cg_try_shield (sabotage any opponent's Cash Game run), and _grant_title / _mark_seen* /
--    _pick_casual* / _accrue_loan. Must revoke from PUBLIC too: Postgres grants EXECUTE to PUBLIC
--    by default on every function, so anon/authenticated inherit it via PUBLIC unless that is
--    revoked (this is the actual root cause of the exposure). Idempotent.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname LIKE '\_%'
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated;', r.sig);
  END LOOP;
END $$;

-- 2) credit_history: enable RLS (was OFF), revoke public writes, allow self-SELECT only.
--    Writes come exclusively from the definer _recompute_credit (runs as owner).
ALTER TABLE public.credit_history ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.credit_history FROM anon, authenticated;
DROP POLICY IF EXISTS credit_history_self_select ON public.credit_history;
CREATE POLICY credit_history_self_select ON public.credit_history
  FOR SELECT TO authenticated USING ((select auth.uid()) = user_id);

-- 3) Defense-in-depth: strip direct table write grants from the public roles (all real writes are
--    definer RPCs). Preserve the one legitimate client write: profiles INSERT (own row, RLS-gated).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
GRANT INSERT ON public.profiles TO authenticated;

-- Verification (aborts the transaction if any invariant is violated).
DO $$
DECLARE n_helpers int;
BEGIN
  SELECT count(*) INTO n_helpers
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname LIKE '\_%'
    AND (has_function_privilege('anon', p.oid, 'EXECUTE')
      OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  IF n_helpers <> 0 THEN
    RAISE EXCEPTION 'FAIL: % internal helper(s) still executable by anon/authenticated', n_helpers;
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.daily_buy_letter'::regproc, 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: authenticated lost EXECUTE on public entrypoint daily_buy_letter';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.profiles', 'INSERT') THEN
    RAISE EXCEPTION 'FAIL: authenticated lost INSERT on profiles (signup would break)';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.credit_history'::regclass) THEN
    RAISE EXCEPTION 'FAIL: credit_history RLS not enabled';
  END IF;
  RAISE NOTICE 'OK: 0 helpers exposed; public entrypoints intact; profiles INSERT preserved; credit_history RLS on';
END $$;

COMMIT;
