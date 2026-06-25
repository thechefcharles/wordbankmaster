-- 🟰 Flat Daily bounty (migration `daily_flat_bounty`, 2026-06-25)
--
-- Using a Twist no longer changes the bounty. _daily_reward_eff(pid, twist) now
-- always returns the base _daily_reward(pid) (the p_twist arg is ignored, kept for
-- callers). bounty_mult in the board emitters (daily_start, _daily_resolve_and_return)
-- is now hard-coded 1.0.
--
-- The reason to SKIP the Twist is the cross-mode carry-over (banked as a power-up on a
-- pure win — see supabase-daily-twist-carryover.sql), NOT a multiplier. Replaces the old
-- ×1.5 "go pure" leveler, which read like a penalty for using a free helper.
--
-- Client: removed the ×1.5 opening badge + the ×1.5 win fly-in; the fly-in now celebrates
-- a CLEAN solve (no wrong letters). Solve-to-Earn shows the flat base in-play.

CREATE OR REPLACE FUNCTION public._daily_reward_eff(p_pid uuid, p_twist boolean)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
AS $function$
  SELECT public._daily_reward(p_pid);
$function$;
-- (daily_start + _daily_resolve_and_return also re-deployed with bounty_mult => 1.0;
--  daily_start still carries the test1 auto-replay hook — see wordbank-test1-hook.)
