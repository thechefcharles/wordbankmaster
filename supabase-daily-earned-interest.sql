-- ============================================================================
-- Daily: bring back "Interest" as an EARNED loyalty/creditworthiness rate.
-- ============================================================================
-- The Daily deposit multiplier is now:  mult = 1 + interest, where
--   interest = streak + credit + boosts   (clamped so mult stays in [1.0, 3.0])
--     • streak  = +2% per consecutive Daily solve, capped +15% (current_daily_solve_streak)
--     • credit  = tier bonus: Excellent +10%, Good +5%, Fair +2%, Poor/Bad +0%
--     • boosts  = the 💥/💎 Interest Boost power-ups you buy + tap in (daily_sessions.bounty_boost)
-- "Interest" is one unified concept with three sources; the 💥/💎 boosts literally
-- boost your interest. Earned interest (streak+credit) caps at +25%; boosts stack on top.
-- Single source of truth = _daily_interest_parts(uid); _daily_bounty_mult sums its 'total'.
-- get_daily_interest() exposes the breakdown for the HUD 'Interest' modal.
-- ============================================================================
BEGIN;

-- Component breakdown (fractions, e.g. 0.10 = +10%). Single source of truth.
CREATE OR REPLACE FUNCTION public._daily_interest_parts(p_uid uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  WITH p AS (
    SELECT
      COALESCE(pr.current_daily_solve_streak, 0) AS ws,
      public._credit_tier(COALESCE(pr.credit_score, 650)) AS tier
    FROM public.profiles pr WHERE pr.id = p_uid
  ),
  parts AS (
    SELECT
      p.ws,
      p.tier,
      LEAST(0.15, 0.02 * p.ws) AS streak,
      CASE p.tier
        WHEN 'Excellent' THEN 0.10
        WHEN 'Good'      THEN 0.05
        WHEN 'Fair'      THEN 0.02
        ELSE 0.0
      END AS credit,
      COALESCE((SELECT bounty_boost FROM public.daily_sessions
                WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE), 0)::numeric AS boost
    FROM p
  )
  SELECT jsonb_build_object(
    'win_streak', parts.ws,
    'tier',       parts.tier,
    'streak',     parts.streak,
    'credit',     parts.credit,
    'boost',      parts.boost,
    'total',      parts.streak + parts.credit + parts.boost
  ) FROM parts;
$function$;

-- Deposit multiplier = 1 + total interest, clamped to [1.0, 3.0].
CREATE OR REPLACE FUNCTION public._daily_bounty_mult(p_uid uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT GREATEST(1.0, LEAST(3.0,
    1.0 + COALESCE((public._daily_interest_parts(p_uid)->>'total')::numeric, 0)
  ));
$function$;

-- Thin RPC for the HUD 'Interest' modal breakdown.
CREATE OR REPLACE FUNCTION public.get_daily_interest()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT public._daily_interest_parts(auth.uid());
$function$;

GRANT EXECUTE ON FUNCTION public.get_daily_interest() TO authenticated;

COMMIT;
