-- ============================================================================
-- Fix: matches only settled when a participant next opened their Challenges list
-- (get_my_matches was the only sweeper) — so if everyone stopped opening the app after
-- the response window, wagers stayed escrowed and refund/settled notifications never
-- fired. Add a pg_cron sweep that settles expired matches server-side on a schedule.
-- Applied to prod (idempotent — safe to re-run).
-- ============================================================================

-- Sweeper: settle every open match whose window has closed. auth-free → cron-safe.
CREATE OR REPLACE FUNCTION public.settle_expired_matches()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT id FROM public.challenge_matches WHERE status = 'open' AND settles_at < now() LOOP
    PERFORM public._match_settle(r.id);   -- _match_settle re-checks status='open', so it's safe/idempotent
    n := n + 1;
  END LOOP;
  RETURN n;
END; $function$;

-- Enable pg_cron (Supabase ships it; no-op if already enabled).
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Run every 5 minutes. cron.schedule upserts by job name, so re-running just updates it.
SELECT cron.schedule('settle-expired-matches', '*/5 * * * *', $$SELECT public.settle_expired_matches();$$);
