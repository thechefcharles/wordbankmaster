-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Fix: Daily shown as "complete + lost" after playing another mode           ║
-- ║  (migration: daily_status_in_progress_2026_06 — applied via psql)           ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- ROOT CAUSE: the client decided "Daily in progress vs finished" from a SINGLE
-- shared localStorage slot (wordbank_game_state_<uid>), which every mode's
-- goToMainMenu() overwrites. After starting a Daily (server session = 'active',
-- so has_played_today=true) then playing Cash Game, that slot held climb state →
-- the menu computed dailyInProgress=false → dailyDone=true → and since the still-
-- active Daily isn't won (last_daily_won=false) it rendered the ❌ "lost" chip and
-- refused to resume. has_played_today means "started today", NOT "finished today",
-- so an active Daily and a finished-lost Daily were indistinguishable to the client.
--
-- FIX: expose SERVER truth. get_daily_status now returns daily_in_progress (today's
-- session exists and is still 'active'). The client derives dailyInProgress from
-- this instead of the clobberable localStorage, so it resumes correctly regardless
-- of what other mode was played in between.
--
-- Adds an OUT column → must DROP then CREATE (REPLACE can't change return type).

DROP FUNCTION IF EXISTS public.get_daily_status(uuid);

CREATE FUNCTION public.get_daily_status(p_user_id uuid)
 RETURNS TABLE(has_played_today boolean, last_daily_won boolean, daily_bankroll integer,
               arcade_bankroll integer, current_streak integer, streak_freezes integer,
               today_score integer, win_streak integer, daily_in_progress boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    -- 🔁 test1 auto-replay: always report not-played so the client re-enters Daily (testing only).
    (CASE WHEN v_uid = 'a5832b8b-278d-4f66-9ef3-b2067fe8312d'::uuid THEN false
          ELSE (p.last_daily_play_date = CURRENT_DATE) END) AS has_played_today,
    EXISTS (SELECT 1 FROM public.game_results gr WHERE gr.user_id = v_uid AND gr.game_mode = 'daily'
      AND gr.played_at::date = CURRENT_DATE AND gr.outcome = 'won') AS last_daily_won,
    COALESCE(p.daily_bankroll, 0)::INT, COALESCE(p.arcade_bankroll, 1000)::INT,
    COALESCE(p.current_win_streak, 0)::INT AS current_streak,
    COALESCE(p.streak_freezes, 0)::INT,
    COALESCE((SELECT gr.score FROM public.game_results gr WHERE gr.user_id = v_uid AND gr.game_mode = 'daily'
      AND gr.played_at::date = CURRENT_DATE ORDER BY gr.played_at DESC LIMIT 1), 0)::INT AS today_score,
    (CASE WHEN p.last_daily_solve_date >= CURRENT_DATE - 1 THEN COALESCE(p.current_solve_streak,0) ELSE 0 END)::INT AS win_streak,
    -- ✅ SERVER truth for "resume vs finished": today's session still open?
    EXISTS (SELECT 1 FROM public.daily_sessions ds
            WHERE ds.user_id = v_uid AND ds.puzzle_date = CURRENT_DATE AND ds.state = 'active') AS daily_in_progress
  FROM public.profiles p WHERE p.id = v_uid;
END; $function$;
