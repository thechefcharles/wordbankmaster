-- ============================================================
-- WordBank V2 Phase 2: achievement badges
-- Run AFTER supabase-daily-server-authoritative.sql (it redefines _finalize_daily
-- with a 4th arg and updates _daily_resolve_and_return to pass it).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_badges (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  badge TEXT NOT NULL,
  earned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, badge)
);
ALTER TABLE public.user_badges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read badges" ON public.user_badges;
CREATE POLICY "Anyone can read badges" ON public.user_badges FOR SELECT USING (true);
REVOKE INSERT, UPDATE, DELETE ON public.user_badges FROM anon, authenticated;

-- Idempotent award helper (only callable via SECURITY DEFINER functions).
CREATE OR REPLACE FUNCTION public._award_badge(p_uid UUID, p_badge TEXT)
RETURNS void LANGUAGE sql SECURITY DEFINER AS $fn$
  INSERT INTO public.user_badges (user_id, badge) VALUES (p_uid, p_badge)
  ON CONFLICT (user_id, badge) DO NOTHING;
$fn$;
REVOKE EXECUTE ON FUNCTION public._award_badge(UUID, TEXT) FROM anon, authenticated;

-- Read a user's badges (defaults to the caller).
CREATE OR REPLACE FUNCTION public.get_user_badges(p_user_id UUID DEFAULT NULL)
RETURNS TABLE (badge TEXT, earned_at TIMESTAMPTZ)
LANGUAGE sql SECURITY DEFINER AS $fn$
  SELECT ub.badge, ub.earned_at FROM public.user_badges ub
  WHERE ub.user_id = COALESCE(p_user_id, auth.uid())
  ORDER BY ub.earned_at;
$fn$;
GRANT EXECUTE ON FUNCTION public.get_user_badges(UUID) TO anon, authenticated;

-- _finalize_daily gains p_incorrect_count and awards daily badges. Drops the old 3-arg form.
DROP FUNCTION IF EXISTS public._finalize_daily(UUID, BOOLEAN, INT);
CREATE OR REPLACE FUNCTION public._finalize_daily(p_uid UUID, p_won BOOLEAN, p_bankroll INT, p_incorrect_count INT DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_week_start DATE; v_current_streak INT; v_highest_streak INT; v_last_win DATE; v_bankroll INT; v_score INT;
BEGIN
  v_bankroll := LEAST(GREATEST(COALESCE(p_bankroll, 0), 0), 1000);
  v_week_start := date_trunc('week', CURRENT_DATE)::DATE + 1;

  SELECT current_win_streak, highest_win_streak, last_daily_win_date
  INTO v_current_streak, v_highest_streak, v_last_win
  FROM public.profiles WHERE id = p_uid;

  IF p_won THEN
    IF v_last_win = CURRENT_DATE - 1 THEN
      v_current_streak := COALESCE(v_current_streak, 0) + 1;
    ELSIF v_last_win IS DISTINCT FROM CURRENT_DATE THEN
      v_current_streak := 1;
    END IF;
    v_highest_streak := GREATEST(COALESCE(v_highest_streak, 0), v_current_streak);
    UPDATE public.profiles SET
      current_win_streak = v_current_streak, highest_win_streak = v_highest_streak,
      last_daily_win_date = CURRENT_DATE, last_daily_play_date = CURRENT_DATE,
      daily_bankroll = v_bankroll, last_daily_won = true
    WHERE id = p_uid;
  ELSE
    v_current_streak := 0;
    UPDATE public.profiles SET
      current_win_streak = 0, last_daily_play_date = CURRENT_DATE,
      daily_bankroll = v_bankroll, last_daily_won = false
    WHERE id = p_uid;
  END IF;

  -- Streak multiplier: 0% at streak 1, +10%/day, capped at +100% (streak 11+).
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

-- Pass the wrong-letter count through from the session to the finalizer.
CREATE OR REPLACE FUNCTION public._daily_resolve_and_return(p_uid UUID, p_phrase TEXT, p_cat TEXT, p_sub TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE s public.daily_sessions; v_won BOOLEAN; v_lost BOOLEAN;
BEGIN
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;
  v_won := NOT EXISTS (
    SELECT 1 FROM generate_series(0, length(p_phrase) - 1) g(i)
    WHERE substr(p_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions)));
  v_lost := (s.bankroll < 30);
  IF v_won THEN s.state := 'won'; ELSIF v_lost THEN s.state := 'lost'; END IF;
  UPDATE public.daily_sessions SET
    bankroll = s.bankroll, guesses_remaining = s.guesses_remaining, revealed_positions = s.revealed_positions,
    incorrect_letters = s.incorrect_letters, state = s.state, updated_at = NOW(),
    finished_at = CASE WHEN s.state <> 'active' AND finished_at IS NULL THEN NOW() ELSE finished_at END
  WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;
  IF s.state <> 'active' THEN
    PERFORM public._finalize_daily(p_uid, s.state = 'won', s.bankroll, COALESCE(array_length(s.incorrect_letters, 1), 0));
  END IF;
  RETURN public._daily_board(p_phrase, s.state, s.bankroll, s.guesses_remaining,
                             s.revealed_positions, s.incorrect_letters, p_cat, p_sub);
END;
$fn$;
