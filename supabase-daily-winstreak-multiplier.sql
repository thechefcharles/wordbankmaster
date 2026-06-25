-- ⭐ Win-streak bounty multiplier (migration `daily_winstreak_multiplier`, 2026-06-25)
--
-- The Daily bounty is multiplied by your WIN streak (consecutive solves):
--   bounty_mult = 1.0 + min(0.1 × win_streak, 0.5)   → ×1.5 cap at a 5-win streak.
-- Uses the streak COMING IN (today not yet solved) so the gold ×N badge shown at
-- puzzle start matches the payout. Win streak chosen over play streak because play
-- streak already pays attendance $; the bounty bonus rewards actually solving.
--
-- New helpers:
CREATE OR REPLACE FUNCTION public._daily_bounty_mult(p_uid uuid)
 RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT 1.0 + LEAST(0.1 * GREATEST(0, COALESCE(
    (SELECT CASE WHEN last_daily_solve_date >= CURRENT_DATE - 1 THEN current_solve_streak ELSE 0 END
     FROM public.profiles WHERE id = p_uid), 0)), 0.5);
$$;
CREATE OR REPLACE FUNCTION public._daily_reward_final(p_uid uuid, p_pid uuid)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT (round(public._daily_reward(p_pid) * public._daily_bounty_mult(p_uid) / 10.0) * 10)::int;
$$;
-- daily_start / _daily_resolve_and_return / _finalize_daily now use _daily_reward_final
-- for the bounty and emit bounty_mult = _daily_bounty_mult(uid). (daily_start keeps the
-- test1 auto-replay hook; _finalize_daily keeps the Twist carry-over.) The flat ×1.0
-- _daily_reward_eff is now unused for the bounty.
--
-- NEXT: Bounty Boost power-ups (active, bought) that STACK on top of this streak bonus.
