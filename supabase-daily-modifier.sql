-- ============================================================
-- WordBank V2 Phase 6a: Daily Modifier (shared, fair)
-- Run AFTER supabase-powerups.sql and supabase-pregame-powerups.sql.
--
-- A ranked daily must be identical for everyone, so the old "random power-up
-- grant on win" is removed. Instead, ONE modifier is active for every player
-- that day, chosen deterministically from the date (rotates daily). It is
-- applied to the daily session's active_powerups at start, so the existing
-- discount / vowel_vision / insurance / extra_bank effects "just work".
-- ============================================================

-- Today's modifier id — same for everyone, rotates by date.
CREATE OR REPLACE FUNCTION public._daily_modifier()
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT (ARRAY['discount','vowel_vision','extra_bank','insurance'])[
    1 + (get_byte(decode(md5(CURRENT_DATE::text), 'hex'), 0) % 4)
  ];
$$;

-- Public accessor so the client can show "Today's twist".
CREATE OR REPLACE FUNCTION public.get_daily_modifier()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT public._daily_modifier();
$$;
GRANT EXECUTE ON FUNCTION public.get_daily_modifier() TO authenticated, anon;

-- daily_start applies the shared modifier (ignores client-supplied power-ups —
-- daily no longer has a personal inventory). p_powerups kept for signature compat.
DROP FUNCTION IF EXISTS public.daily_start(TEXT[]);
CREATE OR REPLACE FUNCTION public.daily_start(p_powerups TEXT[] DEFAULT '{}')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID := auth.uid();
  v_pid UUID; v_phrase TEXT; v_cat TEXT; v_sub TEXT;
  s public.daily_sessions;
  v_mod TEXT; v_bonus INT := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_start: not authenticated'; END IF;
  v_pid := public._todays_puzzle_id();
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
  IF NOT FOUND THEN
    IF v_pid IS NULL THEN RAISE EXCEPTION 'daily_start: no puzzle available'; END IF;
    v_mod := public._daily_modifier();
    IF v_mod = 'extra_bank' THEN v_bonus := 250; END IF;
    INSERT INTO public.daily_sessions (user_id, puzzle_date, puzzle_id, bankroll, guesses_remaining, active_powerups)
    VALUES (v_uid, CURRENT_DATE, v_pid, 1000 + v_bonus, 3, ARRAY[v_mod])
    RETURNING * INTO s;
  END IF;
  SELECT upper(phrase), category, COALESCE(subcategory, '')
  INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;
  RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
                             s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.daily_start(TEXT[]) TO authenticated;

-- _finalize_daily WITHOUT the random power-up grant (daily is now fair/shared).
-- Otherwise identical to the supabase-powerups.sql version.
CREATE OR REPLACE FUNCTION public._finalize_daily(p_uid UUID, p_won BOOLEAN, p_bankroll INT, p_incorrect_count INT DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_week_start DATE; v_current_streak INT; v_highest_streak INT; v_last_win DATE;
  v_bankroll INT; v_score INT; v_freezes INT;
BEGIN
  v_bankroll := LEAST(GREATEST(COALESCE(p_bankroll, 0), 0), 1000);
  v_week_start := date_trunc('week', CURRENT_DATE)::DATE + 1;

  SELECT current_win_streak, highest_win_streak, last_daily_win_date, COALESCE(streak_freezes, 0)
  INTO v_current_streak, v_highest_streak, v_last_win, v_freezes
  FROM public.profiles WHERE id = p_uid;

  IF p_won THEN
    IF v_last_win = CURRENT_DATE - 1 THEN
      v_current_streak := COALESCE(v_current_streak, 0) + 1;
    ELSIF v_last_win = CURRENT_DATE - 2 AND v_freezes > 0 AND COALESCE(v_current_streak, 0) > 0 THEN
      v_freezes := v_freezes - 1; v_current_streak := v_current_streak + 1;
    ELSIF v_last_win IS DISTINCT FROM CURRENT_DATE THEN
      v_current_streak := 1;
    END IF;
    IF v_current_streak > 0 AND v_current_streak % 7 = 0 THEN v_freezes := LEAST(v_freezes + 1, 3); END IF;
    v_highest_streak := GREATEST(COALESCE(v_highest_streak, 0), v_current_streak);
    UPDATE public.profiles SET
      current_win_streak = v_current_streak, highest_win_streak = v_highest_streak,
      last_daily_win_date = CURRENT_DATE, last_daily_play_date = CURRENT_DATE,
      daily_bankroll = v_bankroll, last_daily_won = true, streak_freezes = v_freezes
    WHERE id = p_uid;
  ELSE
    v_current_streak := 0;
    UPDATE public.profiles SET
      current_win_streak = 0, last_daily_play_date = CURRENT_DATE,
      daily_bankroll = v_bankroll, last_daily_won = false
    WHERE id = p_uid;
  END IF;

  v_score := ROUND(v_bankroll * (1 + LEAST(GREATEST(COALESCE(v_current_streak, 0) - 1, 0), 10) * 0.1))::INT;

  INSERT INTO public.game_results (user_id, played_at, won, bankroll_left, game_mode, score)
  VALUES (p_uid, NOW(), p_won, v_bankroll, 'daily', v_score);

  INSERT INTO public.user_weekly_stats (user_id, week_start, puzzles_completed, bankroll_earned, highest_bankroll, total_wins, total_played, win_streak)
  VALUES (p_uid, v_week_start,
    CASE WHEN p_won THEN 1 ELSE 0 END, CASE WHEN p_won THEN v_bankroll ELSE 0 END, v_bankroll,
    CASE WHEN p_won THEN 1 ELSE 0 END, 1, COALESCE(v_current_streak, 0))
  ON CONFLICT (user_id, week_start) DO UPDATE SET
    total_played = user_weekly_stats.total_played + 1,
    total_wins = user_weekly_stats.total_wins + CASE WHEN p_won THEN 1 ELSE 0 END,
    puzzles_completed = user_weekly_stats.puzzles_completed + CASE WHEN p_won THEN 1 ELSE 0 END,
    bankroll_earned = user_weekly_stats.bankroll_earned + CASE WHEN p_won THEN v_bankroll ELSE 0 END,
    highest_bankroll = GREATEST(user_weekly_stats.highest_bankroll, v_bankroll),
    win_streak = GREATEST(user_weekly_stats.win_streak, v_current_streak);

  IF p_won THEN
    IF COALESCE(p_incorrect_count, 0) = 0 THEN PERFORM public._award_badge(p_uid, 'flawless'); END IF;
    IF v_bankroll >= 700 THEN PERFORM public._award_badge(p_uid, 'gold_bank'); END IF;
    IF v_current_streak >= 7 THEN PERFORM public._award_badge(p_uid, 'streak_7'); END IF;
    IF v_current_streak >= 30 THEN PERFORM public._award_badge(p_uid, 'streak_30'); END IF;
  END IF;
END;
$fn$;
