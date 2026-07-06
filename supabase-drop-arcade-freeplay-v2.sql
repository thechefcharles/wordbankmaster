-- V2 Phase 0 (DB): drop the retired Arcade + Free Play systems.
--
-- Companion to PR #361 (code-side removal). Both modes are fully removed from the
-- client; this drops their now-orphaned server objects. Also retires the vestigial
-- `arcade_bankroll` profile column (always 1000, never drove gameplay — real Cash is
-- `profiles.bank`) and makes the $2,000 V2 start explicit in handle_new_user.
--
-- Verified before writing:
--   • arcade_runs referenced only by arcade_* funcs; freeplay_sessions only by
--     freeplay_* funcs + get_open_games (updated below first).
--   • _arcade_*/_freeplay_* helpers referenced only within their own clusters.
--   • arcade_bankroll referenced only by get_daily_status + handle_new_user (both
--     updated below); the other 3 arcade columns referenced by nothing.
--   • 0 game_results rows with game_mode in ('arcade','freeplay') — no history lost.
--   • _ensure_bank already seeds bank=2000; handle_new_user now sets it directly.
-- PITR rollback point logged before apply: 2026-07-06 21:05:45 UTC.

BEGIN;

-- 1) get_open_games: drop the Free Play UNION branch (freeplay_sessions is going away).
CREATE OR REPLACE FUNCTION public.get_open_games()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.updated_at DESC), '[]'::jsonb) INTO v
  FROM (
    SELECT 'daily'::text AS mode, ds.updated_at
      FROM public.daily_sessions ds
      WHERE ds.user_id = v_uid AND ds.puzzle_date = CURRENT_DATE AND ds.state = 'active'
    UNION ALL
    SELECT 'climb', cs.updated_at
      FROM public.climb_state cs
      WHERE cs.user_id = v_uid AND cs.state IN ('active','stuck')
  ) t;
  RETURN v;
END; $function$;

-- 2) handle_new_user: V2 start = $2,000 Cash; stop seeding the vestigial arcade_bankroll.
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO public.profiles (id, bank)
  VALUES (NEW.id, 2000)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$function$;

-- 3) get_daily_status: replace the vestigial arcade_bankroll output with the real bank.
--    (Return-type change → DROP + CREATE; verified no DB callers.)
DROP FUNCTION IF EXISTS public.get_daily_status(uuid);
CREATE FUNCTION public.get_daily_status(p_user_id uuid)
 RETURNS TABLE(has_played_today boolean, last_daily_won boolean, daily_bankroll integer, bank bigint, current_streak integer, streak_freezes integer, today_score integer, win_streak integer, daily_in_progress boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    (p.last_daily_play_date = CURRENT_DATE) AS has_played_today,
    EXISTS (SELECT 1 FROM public.game_results gr WHERE gr.user_id = v_uid AND gr.game_mode = 'daily'
      AND gr.played_at::date = CURRENT_DATE AND gr.outcome = 'won') AS last_daily_won,
    COALESCE(p.daily_bankroll, 0)::INT, COALESCE(p.bank, 2000)::BIGINT AS bank,
    COALESCE(p.current_daily_play_streak, 0)::INT AS current_streak,
    COALESCE(p.streak_freezes, 0)::INT,
    COALESCE((SELECT gr.score FROM public.game_results gr WHERE gr.user_id = v_uid AND gr.game_mode = 'daily'
      AND gr.played_at::date = CURRENT_DATE ORDER BY gr.played_at DESC LIMIT 1), 0)::INT AS today_score,
    (CASE WHEN p.last_daily_solve_date >= CURRENT_DATE - 1 THEN COALESCE(p.current_daily_solve_streak,0) ELSE 0 END)::INT AS win_streak,
    EXISTS (SELECT 1 FROM public.daily_sessions ds
            WHERE ds.user_id = v_uid AND ds.puzzle_date = CURRENT_DATE AND ds.state = 'active') AS daily_in_progress
  FROM public.profiles p WHERE p.id = v_uid;
END; $function$;

-- 4) Drop the Arcade function cluster (RPCs + internal helpers + leaderboard).
DROP FUNCTION IF EXISTS public.arcade_start();
DROP FUNCTION IF EXISTS public.arcade_buy_letter(p_letter text);
DROP FUNCTION IF EXISTS public.arcade_reveal();
DROP FUNCTION IF EXISTS public.arcade_submit_guess(p_guess jsonb);
DROP FUNCTION IF EXISTS public.arcade_next();
DROP FUNCTION IF EXISTS public.arcade_use_powerup(p_powerup text);
DROP FUNCTION IF EXISTS public.arcade_cashout();
DROP FUNCTION IF EXISTS public.arcade_clue();
DROP FUNCTION IF EXISTS public.get_arcade_gauntlet_leaderboard(p_period text);
DROP FUNCTION IF EXISTS public._arcade_resolve(p_uid uuid);
DROP FUNCTION IF EXISTS public._arcade_response(p_uid uuid);
DROP FUNCTION IF EXISTS public._arcade_puzzle_at(p_position integer, p_seed text);
DROP FUNCTION IF EXISTS public._arcade_ladder_size();
DROP FUNCTION IF EXISTS public._arcade_earn_for_solve(p_position integer);

-- 5) Drop the Free Play function cluster (RPCs + internal helpers).
DROP FUNCTION IF EXISTS public.freeplay_start(p_category text);
DROP FUNCTION IF EXISTS public.freeplay_next();
DROP FUNCTION IF EXISTS public.freeplay_resume();
DROP FUNCTION IF EXISTS public.freeplay_buy_letter(p_letter text);
DROP FUNCTION IF EXISTS public.freeplay_reveal();
DROP FUNCTION IF EXISTS public.freeplay_submit_guess(p_guess jsonb);
DROP FUNCTION IF EXISTS public.freeplay_clue();
DROP FUNCTION IF EXISTS public.freeplay_cashout(p_amount integer);
DROP FUNCTION IF EXISTS public.freeplay_cashout_status();
DROP FUNCTION IF EXISTS public._freeplay_resolve(p_uid uuid);
DROP FUNCTION IF EXISTS public._freeplay_response(p_uid uuid);

-- 6) Drop the state tables (no rows worth keeping; 0 historical game_results).
DROP TABLE IF EXISTS public.arcade_runs;
DROP TABLE IF EXISTS public.freeplay_sessions;

-- 7) Drop the retired arcade profile columns.
ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS arcade_bankroll,
  DROP COLUMN IF EXISTS arcade_win_streak,
  DROP COLUMN IF EXISTS highest_arcade_bankroll,
  DROP COLUMN IF EXISTS highest_arcade_streak;

COMMIT;
