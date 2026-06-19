-- ============================================================
-- WordBank V2 Phase 3a: power-up framework + Free Reveal
-- Run AFTER supabase-streak-freeze.sql (redefines _finalize_daily to also grant
-- a Free Reveal on each win).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_powerups (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  powerup TEXT NOT NULL,
  count INT NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, powerup)
);
ALTER TABLE public.user_powerups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "read own powerups" ON public.user_powerups;
CREATE POLICY "read own powerups" ON public.user_powerups FOR SELECT USING (auth.uid() = user_id);
REVOKE INSERT, UPDATE, DELETE ON public.user_powerups FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public._grant_powerup(p_uid UUID, p_powerup TEXT, p_cap INT DEFAULT 3)
RETURNS void LANGUAGE sql SECURITY DEFINER AS $fn$
  INSERT INTO public.user_powerups (user_id, powerup, count) VALUES (p_uid, p_powerup, 1)
  ON CONFLICT (user_id, powerup) DO UPDATE SET count = LEAST(public.user_powerups.count + 1, p_cap);
$fn$;
REVOKE EXECUTE ON FUNCTION public._grant_powerup(UUID, TEXT, INT) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_user_powerups()
RETURNS TABLE (powerup TEXT, count INT) LANGUAGE sql SECURITY DEFINER AS $fn$
  SELECT up.powerup, up.count FROM public.user_powerups up
  WHERE up.user_id = auth.uid() AND up.count > 0 ORDER BY up.powerup;
$fn$;
GRANT EXECUTE ON FUNCTION public.get_user_powerups() TO authenticated;

-- Free Reveal: a free smart reveal that consumes one 'free_reveal' power-up.
CREATE OR REPLACE FUNCTION public.daily_use_free_reveal()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID := auth.uid();
  s public.daily_sessions;
  v_phrase TEXT; v_cat TEXT; v_sub TEXT;
  v_letter TEXT; v_positions INT[]; v_owned INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_use_free_reveal: not authenticated'; END IF;

  SELECT count INTO v_owned FROM public.user_powerups WHERE user_id = v_uid AND powerup = 'free_reveal';

  SELECT * INTO s FROM public.daily_sessions
  WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'daily_use_free_reveal: no active session'; END IF;

  SELECT upper(phrase), category, COALESCE(subcategory, '')
  INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;

  SELECT t.ch INTO v_letter FROM (
    SELECT substr(v_phrase, g.i + 1, 1) AS ch, count(*) AS c
    FROM generate_series(0, length(v_phrase) - 1) g(i)
    WHERE substr(v_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions))
    GROUP BY substr(v_phrase, g.i + 1, 1) ORDER BY c DESC, ch LIMIT 1
  ) t;

  IF s.state <> 'active' OR COALESCE(v_owned, 0) <= 0 OR v_letter IS NULL THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
                               s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;

  SELECT array_agg(g.i) INTO v_positions
  FROM generate_series(0, length(v_phrase) - 1) g(i)
  WHERE substr(v_phrase, g.i + 1, 1) = v_letter;

  s.revealed_positions := ARRAY(SELECT DISTINCT unnest(s.revealed_positions || v_positions) ORDER BY 1);
  UPDATE public.daily_sessions SET revealed_positions = s.revealed_positions, updated_at = NOW()
  WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;

  UPDATE public.user_powerups SET count = count - 1 WHERE user_id = v_uid AND powerup = 'free_reveal';

  RETURN public._daily_resolve_and_return(v_uid, v_phrase, v_cat, v_sub);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.daily_use_free_reveal() TO authenticated;

-- _finalize_daily also grants a Free Reveal on each win (capped at 3).
-- (Full body lives here as the latest definition; supersedes earlier versions.)
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
    PERFORM public._grant_random_powerup(p_uid);  -- Phase 3b: random from pool (defined in supabase-pregame-powerups.sql)
  END IF;
END;
$fn$;
