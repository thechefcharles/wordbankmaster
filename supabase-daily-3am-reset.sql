-- Daily reset boundary: 3 AM Eastern + self-advancing (no player needed)
-- Applied to prod 2026-08-18. Server-side only — deploys over-the-air, NO app resubmission
-- (the Daily lives entirely in Postgres functions + pg_cron; the iOS app is a remote shell).
--
-- WHY America/Los_Angeles (this is DELIBERATE, not a bug):
--   The Daily "day" is derived from CURRENT_DATE inside 29 SECURITY DEFINER functions, each
--   pinned to a timezone via `SET "TimeZone"`. We want the new puzzle/leaderboard/streak day to
--   flip at 3 AM Eastern (chosen so it never rolls over during evening play). Midnight Pacific IS
--   3 AM Eastern year-round (Pacific is always Eastern-3h and both observe DST together), so
--   retargeting each function's TimeZone from America/New_York -> America/Los_Angeles moves the
--   boundary to 3 AM ET WITHOUT rewriting any function body. DST-safe (named zones, no fixed offset).
--   Do NOT "correct" this to America/New_York — that would revert the reset to midnight ET.

BEGIN;

-- 1) Retarget every daily-day function to the 3 AM ET (= midnight Pacific) boundary.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT 'public.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND array_to_string(p.proconfig, ',') ILIKE '%America/New_York%'
  LOOP
    EXECUTE 'ALTER FUNCTION ' || r.sig || ' SET "TimeZone" TO ''America/Los_Angeles''';
  END LOOP;
END $$;

-- 2) Self-advance: hourly idempotent tick creates the day's puzzle without waiting for a player.
--    _todays_puzzle_id() = INSERT ... ON CONFLICT (scheduled_date) DO NOTHING, now Pacific-dated.
SELECT cron.schedule('daily-advance', '7 * * * *', $$SELECT public._todays_puzzle_id();$$);

COMMIT;
