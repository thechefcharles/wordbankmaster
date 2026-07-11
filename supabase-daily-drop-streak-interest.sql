-- ============================================================================
-- Daily: drop the win-streak "interest" from the deposit multiplier.
-- ============================================================================
-- The daily multiplier was 1.0 + min(0.1×streak, 0.5) + bounty_boost. Removing
-- the streak term makes the daily SCORE = bounty − spent for normal play (a fair,
-- same-for-everyone leaderboard), while keeping the 💥/💎 boost power-ups working
-- as an optional, deliberate multiplier. So: mult = 1.0 + bounty_boost.
-- Streak rewards still exist via the attendance milestones (separate, credited at
-- daily_start). No other function changes — _daily_resolve_and_return already does
-- winnings = round(kept × mult), which now equals kept when no boost is active.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public._daily_bounty_mult(p_uid uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT GREATEST(1.0, LEAST(3.0,
    1.0
    + COALESCE((SELECT bounty_boost FROM public.daily_sessions
                WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE), 0)
  ));
$function$;

COMMIT;
