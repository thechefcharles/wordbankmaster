-- ============================================================
-- WordBank: Security hardening for the leaderboard economy
-- Run in Supabase SQL Editor AFTER supabase-daily-leaderboard.sql
-- ============================================================
--
-- Problem this fixes:
--   The game economy (bankroll, streaks, wins) is computed in the browser and was
--   written to the database either by direct table writes or by SECURITY DEFINER RPCs
--   that trusted a client-supplied user id and value. Because the anon key ships in the
--   client bundle, ANY visitor could:
--     - call record_daily_result / record_arcade_result with any user id + any bankroll,
--     - directly INSERT fake rows into game_results (the leaderboard source),
--     - directly UPDATE their own profiles.arcade_bankroll to any value,
--     - pre-seed daily_puzzle_schedule.
--
-- Fix strategy:
--   1. All economy writes now go through SECURITY DEFINER RPCs that use auth.uid()
--      (see supabase-daily-leaderboard.sql) and clamp/validate inputs.
--   2. Revoke direct write privileges on the underlying tables from the client roles
--      (anon, authenticated) so the RPCs are the ONLY write path. The RPCs run as the
--      function owner and are unaffected by these REVOKEs.
--   3. Drop the now-misleading permissive write policies.
--
-- SELECT stays open where leaderboards/UI need it; only writes are locked down.

-- ---- profiles -------------------------------------------------------------
-- Clients may still INSERT their own row (creation fallback) and SELECT for the UI,
-- but may NOT UPDATE/DELETE: bankroll & stats are written only by the SECURITY DEFINER RPCs.
REVOKE UPDATE, DELETE ON public.profiles FROM anon, authenticated;
-- Existing permissive UPDATE policy (confirmed present in prod) — the direct bankroll-write hole.
DROP POLICY IF EXISTS "Update own profile" ON public.profiles;

-- ---- game_results (leaderboard source of truth) ---------------------------
-- No direct client writes at all; only record_daily_result / record_arcade_result insert.
REVOKE INSERT, UPDATE, DELETE ON public.game_results FROM anon, authenticated;
DROP POLICY IF EXISTS "Users can insert own game results" ON public.game_results;

-- ---- user_weekly_stats ----------------------------------------------------
-- Written only by record_daily_result. Reads stay open for the weekly leaderboard.
REVOKE INSERT, UPDATE, DELETE ON public.user_weekly_stats FROM anon, authenticated;
DROP POLICY IF EXISTS "Users can insert own weekly stats" ON public.user_weekly_stats;
DROP POLICY IF EXISTS "Users can update own weekly stats" ON public.user_weekly_stats;

-- ---- daily_puzzle_schedule ------------------------------------------------
-- Assigned only by get_todays_puzzle (SECURITY DEFINER). No client inserts.
REVOKE INSERT, UPDATE, DELETE ON public.daily_puzzle_schedule FROM anon, authenticated;
DROP POLICY IF EXISTS "Service can insert daily puzzle schedule" ON public.daily_puzzle_schedule;

-- ---- Ensure the RPCs are callable by signed-in users ----------------------
GRANT EXECUTE ON FUNCTION public.record_daily_result(UUID, BOOLEAN, INT)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_arcade_result(UUID, BOOLEAN, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_arcade_bankroll(INT)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_daily_status(UUID)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_played_daily_today(UUID)            TO authenticated;
