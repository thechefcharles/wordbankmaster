-- Daily day-boundary → US Eastern (was UTC) (2026-07-18).
--
-- The Daily is a single global puzzle keyed by CURRENT_DATE, which is UTC — so it reset at
-- UTC midnight = 8 PM Eastern. Anyone who played in the evening (past 8 PM ET) had it count as
-- the NEXT day, then saw "already played" the next local morning. Anchor the daily "day" to
-- US Eastern instead: ALTER each daily function to run with timezone='America/New_York', so
-- CURRENT_DATE and every ::date cast inside resolve to the Eastern calendar date. No function
-- bodies change; DST is handled automatically by the named zone. (Non-daily date logic — loans,
-- credit, period leaderboards, casual-pool seeding — is deliberately left on UTC.)

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname = ANY (ARRAY[
        '_daily_modifier','_daily_resolve_and_return','_finalize_daily','_daily_interest_parts',
        '_todays_puzzle_id','get_todays_puzzle','has_played_daily_today','expire_stale_dailies',
        'daily_start','daily_submit_guess','daily_buy_letter','daily_clue','daily_fold','daily_reveal',
        'daily_session_exists','daily_use_boost','daily_use_free_reveal','daily_use_twist',
        'get_daily_status','get_daily_board','get_daily_ghost','get_daily_leaderboard',
        'get_friends_daily_leaderboard','get_my_daily_rank','get_daily_avail_boosts','get_daily_anomalies',
        'get_streak_overview','makeup_start'
      ])
  LOOP
    EXECUTE format('ALTER FUNCTION public.%I(%s) SET timezone = %L', r.proname, r.args, 'America/New_York');
  END LOOP;
END $$;

-- Correct existing play/solve dates to the Eastern basis. Evening plays were stored a day ahead
-- (UTC date), which is why the "already played today" check was stuck. Recompute the most-recent
-- play/solve date from game_results using the Eastern calendar date. Only touches users with
-- logged daily results; preserves the existing value when there's nothing to recompute from.
UPDATE public.profiles p SET
  last_daily_play_date  = COALESCE(sub.play_date,  p.last_daily_play_date),
  last_daily_solve_date = COALESCE(sub.solve_date, p.last_daily_solve_date)
FROM (
  SELECT user_id,
    MAX((played_at AT TIME ZONE 'America/New_York')::date) AS play_date,
    MAX((played_at AT TIME ZONE 'America/New_York')::date) FILTER (WHERE won) AS solve_date
  FROM public.game_results
  WHERE game_mode = 'daily'
  GROUP BY user_id
) sub
WHERE p.id = sub.user_id;
