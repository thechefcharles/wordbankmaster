-- ============================================================
-- WordBank V2 Phase 2b: streak freeze
-- Run AFTER supabase-badges.sql (redefines _finalize_daily with freeze logic;
-- updates get_daily_status to return current_streak + streak_freezes).
-- ============================================================
--
-- A freeze auto-bridges a single MISSED day so a long streak survives. Players
-- earn one at every 7-day milestone (capped at 3). A freeze is only consumed for
-- a genuine miss (streak still > 0), never wasted after a loss.

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS streak_freezes INT NOT NULL DEFAULT 0;

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
      v_freezes := v_freezes - 1;                 -- freeze bridges one missed day
      v_current_streak := v_current_streak + 1;
    ELSIF v_last_win IS DISTINCT FROM CURRENT_DATE THEN
      v_current_streak := 1;
    END IF;

    IF v_current_streak > 0 AND v_current_streak % 7 = 0 THEN
      v_freezes := LEAST(v_freezes + 1, 3);       -- earn a freeze every 7 days (cap 3)
    END IF;

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

-- get_daily_status returns streak + freezes for the My Account panel.
DROP FUNCTION IF EXISTS public.get_daily_status(UUID);
CREATE OR REPLACE FUNCTION public.get_daily_status(p_user_id UUID)
RETURNS TABLE (
  has_played_today BOOLEAN, last_daily_won BOOLEAN, daily_bankroll INT, arcade_bankroll INT,
  current_streak INT, streak_freezes INT
) AS $fn$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  RETURN QUERY
  SELECT
    (p.last_daily_play_date = CURRENT_DATE) AS has_played_today,
    COALESCE(p.last_daily_won, false) AS last_daily_won,
    COALESCE(p.daily_bankroll, 0)::INT AS daily_bankroll,
    COALESCE(p.arcade_bankroll, 1000)::INT AS arcade_bankroll,
    COALESCE(p.current_win_streak, 0)::INT AS current_streak,
    COALESCE(p.streak_freezes, 0)::INT AS streak_freezes
  FROM public.profiles p WHERE p.id = v_uid;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.get_daily_status(UUID) TO authenticated;
