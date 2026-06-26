-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Daily: no broke timer — unfinished puzzles expire as a loss at day's end    ║
-- ║  (migration: expire_stale_dailies_2026_06 — applied via psql)               ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- The Daily no longer has a broke auto-fold timer (guesses are free + unlimited,
-- so being out of Cash isn't a dead end). The only way to "lose" the Daily is to
-- not solve it before the day ends. Because letters are paid from your real
-- profiles.bank, the Cash you spent is already gone — not solving forfeits it.
--
-- No pg_cron here, so this finalizes lazily: the client calls expire_stale_dailies()
-- on app open. Any of the caller's still-active sessions from a PRIOR day are marked
-- lost, the answer is revealed, and a game_results 'lost' row is logged so it shows
-- (with the answer) in History. Streaks are intentionally NOT touched — the date-gap
-- logic in daily_start/get_daily_status already handles streak breaks, and we must not
-- retroactively zero a streak the player has since rebuilt.
-- Idempotent: only 'active' prior-day sessions are processed, then flipped to 'lost'.

CREATE OR REPLACE FUNCTION public.expire_stale_dailies()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); r public.daily_sessions; v_phrase text; v_cat text; v_all int[]; v_n int := 0;
BEGIN
  IF v_uid IS NULL THEN RETURN 0; END IF;
  FOR r IN SELECT * FROM public.daily_sessions
           WHERE user_id = v_uid AND state = 'active' AND puzzle_date < CURRENT_DATE
           FOR UPDATE LOOP
    SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = r.puzzle_id;
    SELECT array_agg(g.i) INTO v_all FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1, 1) <> ' ';
    UPDATE public.daily_sessions
      SET state = 'lost', finished_at = (r.puzzle_date + 1)::timestamptz,
          revealed_positions = COALESCE(v_all, '{}'), updated_at = now()
      WHERE user_id = v_uid AND puzzle_date = r.puzzle_date;
    INSERT INTO public.game_results
      (user_id, played_at, won, bankroll_left, game_mode, score, outcome, puzzle_id, category,
       solved_count, puzzle_count, spent, earned, net)
    VALUES
      (v_uid, (r.puzzle_date + 1)::timestamptz, false, 0, 'daily', -r.spent, 'lost', r.puzzle_id, v_cat,
       0, 1, r.spent, 0, -r.spent);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END; $function$;
