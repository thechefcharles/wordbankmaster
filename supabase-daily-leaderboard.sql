-- ============================================================
-- WordBank: Daily Puzzle, Stats & Weekly Leaderboard
-- Run in Supabase SQL Editor (Dashboard → SQL Editor)
-- ============================================================

-- 1. Extend profiles with stats and dual bankrolls
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS current_win_streak INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS highest_win_streak INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_daily_win_date DATE,
ADD COLUMN IF NOT EXISTS last_daily_play_date DATE,
ADD COLUMN IF NOT EXISTS daily_bankroll INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_daily_won BOOLEAN,
ADD COLUMN IF NOT EXISTS arcade_bankroll INT DEFAULT 1000,
ADD COLUMN IF NOT EXISTS highest_arcade_bankroll INT DEFAULT 1000,
ADD COLUMN IF NOT EXISTS arcade_win_streak INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS highest_arcade_streak INT DEFAULT 0;

-- 2. Create user_weekly_stats for leaderboard aggregation
CREATE TABLE IF NOT EXISTS public.user_weekly_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  puzzles_completed INT DEFAULT 0,
  bankroll_earned INT DEFAULT 0,
  highest_bankroll INT DEFAULT 0,
  total_wins INT DEFAULT 0,
  total_played INT DEFAULT 0,
  win_streak INT DEFAULT 0,
  UNIQUE(user_id, week_start)
);

-- 3. RLS for user_weekly_stats
ALTER TABLE public.user_weekly_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own weekly stats" ON public.user_weekly_stats;
CREATE POLICY "Users can read own weekly stats"
  ON public.user_weekly_stats FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own weekly stats" ON public.user_weekly_stats;
CREATE POLICY "Users can insert own weekly stats"
  ON public.user_weekly_stats FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own weekly stats" ON public.user_weekly_stats;
CREATE POLICY "Users can update own weekly stats"
  ON public.user_weekly_stats FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Anyone can read weekly stats for leaderboard" ON public.user_weekly_stats;
CREATE POLICY "Anyone can read weekly stats for leaderboard"
  ON public.user_weekly_stats FOR SELECT
  USING (true);

-- 3b. Create game_results for period-based leaderboards (daily + arcade)
CREATE TABLE IF NOT EXISTS public.game_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  played_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  won BOOLEAN NOT NULL,
  bankroll_left INT NOT NULL,
  game_mode TEXT NOT NULL DEFAULT 'daily'
);
ALTER TABLE public.game_results ADD COLUMN IF NOT EXISTS game_mode TEXT NOT NULL DEFAULT 'daily';

CREATE INDEX IF NOT EXISTS idx_game_results_user_played ON public.game_results(user_id, played_at);
ALTER TABLE public.game_results ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read game results" ON public.game_results;
CREATE POLICY "Anyone can read game results" ON public.game_results FOR SELECT USING (true);
DROP POLICY IF EXISTS "Users can insert own game results" ON public.game_results;
CREATE POLICY "Users can insert own game results" ON public.game_results FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 3c. Daily puzzle pool and schedule (rotation, never reuse)
-- Add puzzles to daily_puzzles; get_todays_puzzle picks one deterministically per day
-- and records it in daily_puzzle_schedule so the same puzzle is never used again.
CREATE TABLE IF NOT EXISTS public.daily_puzzles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phrase TEXT NOT NULL,
  category TEXT NOT NULL,
  subcategory TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS public.daily_puzzle_schedule (
  scheduled_date DATE PRIMARY KEY,
  puzzle_id UUID NOT NULL REFERENCES public.daily_puzzles(id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_daily_puzzle_schedule_date ON public.daily_puzzle_schedule(scheduled_date);
ALTER TABLE public.daily_puzzle_schedule ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read daily puzzle schedule" ON public.daily_puzzle_schedule;
CREATE POLICY "Anyone can read daily puzzle schedule" ON public.daily_puzzle_schedule FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service can insert daily puzzle schedule" ON public.daily_puzzle_schedule;
CREATE POLICY "Service can insert daily puzzle schedule" ON public.daily_puzzle_schedule FOR INSERT WITH CHECK (true);

ALTER TABLE public.daily_puzzles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read daily puzzles" ON public.daily_puzzles;
CREATE POLICY "Anyone can read daily puzzles" ON public.daily_puzzles FOR SELECT USING (true);

-- 4. RPC: Get today's daily puzzle (rotation, same puzzle never used twice)
CREATE OR REPLACE FUNCTION public.get_todays_puzzle()
RETURNS TABLE (id UUID, phrase TEXT, category TEXT, subcategory TEXT) AS $$
BEGIN
  -- Ensure today has a puzzle assigned (atomic: first caller wins, others get same)
  INSERT INTO public.daily_puzzle_schedule (scheduled_date, puzzle_id)
  SELECT v_date, v_pid FROM (
    SELECT CURRENT_DATE AS v_date,
      (SELECT p2.id FROM public.daily_puzzles p2
       WHERE p2.id NOT IN (SELECT puzzle_id FROM public.daily_puzzle_schedule)
       ORDER BY md5(CURRENT_DATE::text || p2.id::text)
       LIMIT 1) AS v_pid
  ) sub
  WHERE v_pid IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.daily_puzzle_schedule WHERE scheduled_date = CURRENT_DATE)
  ON CONFLICT (scheduled_date) DO NOTHING;

  RETURN QUERY
  SELECT gen_random_uuid() AS id, p.phrase, p.category, COALESCE(p.subcategory, '')::TEXT AS subcategory
  FROM public.daily_puzzle_schedule s
  JOIN public.daily_puzzles p ON p.id = s.puzzle_id
  WHERE s.scheduled_date = CURRENT_DATE
  LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4b. RPC: Check if user has already played daily today
CREATE OR REPLACE FUNCTION public.has_played_daily_today(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_user_id AND last_daily_play_date = CURRENT_DATE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4c. RPC: Get daily status and bankrolls for select page
CREATE OR REPLACE FUNCTION public.get_daily_status(p_user_id UUID)
RETURNS TABLE (
  has_played_today BOOLEAN,
  last_daily_won BOOLEAN,
  daily_bankroll INT,
  arcade_bankroll INT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    (p.last_daily_play_date = CURRENT_DATE) AS has_played_today,
    COALESCE(p.last_daily_won, false) AS last_daily_won,
    COALESCE(p.daily_bankroll, 0)::INT AS daily_bankroll,
    COALESCE(p.arcade_bankroll, 1000)::INT AS arcade_bankroll
  FROM public.profiles p
  WHERE p.id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4d. RPC: Daily leaderboard (bankroll, current/highest streak, puzzles, win %; sortable)
DROP FUNCTION IF EXISTS public.get_daily_leaderboard(TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.get_daily_leaderboard(p_period TEXT DEFAULT 'daily', p_order_by TEXT DEFAULT 'bankroll')
RETURNS TABLE (
  rank BIGINT,
  user_id UUID,
  display_name TEXT,
  bankroll_left INT,
  current_streak INT,
  highest_streak INT,
  total_played INT,
  total_wins INT,
  win_rate NUMERIC
) AS $$
DECLARE
  v_start TIMESTAMPTZ;
  v_end TIMESTAMPTZ;
BEGIN
  CASE p_period
    WHEN 'daily' THEN
      v_start := date_trunc('day', CURRENT_DATE) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '1 day';
    WHEN 'weekly' THEN
      v_start := (date_trunc('week', CURRENT_DATE)::DATE + 1)::TIMESTAMPTZ;
      v_end := v_start + INTERVAL '7 days';
    WHEN 'monthly' THEN
      v_start := date_trunc('month', CURRENT_DATE) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '1 month';
    WHEN 'yearly' THEN
      v_start := date_trunc('year', CURRENT_DATE) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '1 year';
    ELSE
      v_start := date_trunc('day', CURRENT_DATE) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '1 day';
  END CASE;

  RETURN QUERY
  WITH agg AS (
    SELECT
      gr.user_id,
      MAX(gr.bankroll_left)::INT AS bankroll_left,
      COUNT(*)::INT AS total_played,
      COUNT(*) FILTER (WHERE gr.won)::INT AS total_wins
    FROM public.game_results gr
    WHERE gr.played_at >= v_start AND gr.played_at < v_end
      AND (gr.game_mode = 'daily' OR gr.game_mode IS NULL)
    GROUP BY gr.user_id
  ),
  base AS (
    SELECT
      prof.id AS user_id,
      COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email', '@', 1), 'Player')::TEXT AS display_name,
      agg.bankroll_left,
      COALESCE(prof.current_win_streak, 0)::INT AS current_streak,
      COALESCE(prof.highest_win_streak, 0)::INT AS highest_streak,
      agg.total_played,
      agg.total_wins,
      (CASE WHEN agg.total_played > 0 THEN ROUND((agg.total_wins::NUMERIC / agg.total_played) * 100, 1) ELSE 0 END)::NUMERIC AS win_rate
    FROM agg
    JOIN public.profiles prof ON prof.id = agg.user_id
    LEFT JOIN auth.users au ON au.id = prof.id
  )
  SELECT
    ROW_NUMBER() OVER (
      ORDER BY
        CASE WHEN p_order_by = 'bankroll' THEN base.bankroll_left END DESC NULLS LAST,
        CASE WHEN p_order_by = 'streak' THEN base.current_streak END DESC NULLS LAST,
        CASE WHEN p_order_by = 'highest_streak' THEN base.highest_streak END DESC NULLS LAST,
        CASE WHEN p_order_by = 'puzzles' THEN base.total_played END DESC NULLS LAST,
        CASE WHEN p_order_by = 'win_pct' THEN base.win_rate END DESC NULLS LAST,
        base.bankroll_left DESC NULLS LAST
    )::BIGINT AS rank,
    base.user_id,
    base.display_name,
    base.bankroll_left,
    base.current_streak,
    base.highest_streak,
    base.total_played,
    base.total_wins,
    base.win_rate
  FROM base
  ORDER BY
    CASE WHEN p_order_by = 'bankroll' THEN base.bankroll_left END DESC NULLS LAST,
    CASE WHEN p_order_by = 'streak' THEN base.current_streak END DESC NULLS LAST,
    CASE WHEN p_order_by = 'highest_streak' THEN base.highest_streak END DESC NULLS LAST,
    CASE WHEN p_order_by = 'puzzles' THEN base.total_played END DESC NULLS LAST,
    CASE WHEN p_order_by = 'win_pct' THEN base.win_rate END DESC NULLS LAST,
    base.bankroll_left DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4e. RPC: Arcade leaderboard (bankroll, streaks, puzzles, win %; period + sortable)
DROP FUNCTION IF EXISTS public.get_arcade_leaderboard(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.get_arcade_leaderboard();
CREATE OR REPLACE FUNCTION public.get_arcade_leaderboard(p_period TEXT DEFAULT 'all', p_order_by TEXT DEFAULT 'bankroll')
RETURNS TABLE (
  rank BIGINT,
  user_id UUID,
  display_name TEXT,
  current_bankroll INT,
  highest_bankroll INT,
  current_streak INT,
  highest_streak INT,
  total_played INT,
  total_wins INT,
  win_rate NUMERIC
) AS $$
DECLARE
  v_start TIMESTAMPTZ;
  v_end TIMESTAMPTZ;
BEGIN
  IF p_period != 'all' THEN
    CASE p_period
      WHEN 'daily' THEN
        v_start := date_trunc('day', CURRENT_DATE) AT TIME ZONE 'UTC';
        v_end := v_start + INTERVAL '1 day';
      WHEN 'weekly' THEN
        v_start := (date_trunc('week', CURRENT_DATE)::DATE + 1)::TIMESTAMPTZ;
        v_end := v_start + INTERVAL '7 days';
      WHEN 'monthly' THEN
        v_start := date_trunc('month', CURRENT_DATE) AT TIME ZONE 'UTC';
        v_end := v_start + INTERVAL '1 month';
      WHEN 'yearly' THEN
        v_start := date_trunc('year', CURRENT_DATE) AT TIME ZONE 'UTC';
        v_end := v_start + INTERVAL '1 year';
      ELSE
        v_start := NULL;
        v_end := NULL;
    END CASE;
  END IF;

  RETURN QUERY
  WITH period_agg AS (
    SELECT
      gr.user_id,
      COUNT(*)::INT AS total_played,
      COUNT(*) FILTER (WHERE gr.won)::INT AS total_wins,
      (CASE WHEN COUNT(*) > 0 THEN ROUND((COUNT(*) FILTER (WHERE gr.won)::NUMERIC / COUNT(*)) * 100, 1) ELSE 0 END)::NUMERIC AS win_rate
    FROM public.game_results gr
    WHERE gr.game_mode = 'arcade'
      AND (v_start IS NULL OR (gr.played_at >= v_start AND gr.played_at < v_end))
    GROUP BY gr.user_id
  ),
  base AS (
    SELECT
      prof.id AS user_id,
      COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email', '@', 1), 'Player')::TEXT AS display_name,
      COALESCE(prof.arcade_bankroll, 1000)::INT AS current_bankroll,
      COALESCE(prof.highest_arcade_bankroll, 1000)::INT AS highest_bankroll,
      COALESCE(prof.arcade_win_streak, 0)::INT AS current_streak,
      COALESCE(prof.highest_arcade_streak, 0)::INT AS highest_streak,
      COALESCE(pa.total_played, 0)::INT AS total_played,
      COALESCE(pa.total_wins, 0)::INT AS total_wins,
      COALESCE(pa.win_rate, 0)::NUMERIC AS win_rate
    FROM public.profiles prof
    LEFT JOIN auth.users au ON au.id = prof.id
    LEFT JOIN period_agg pa ON pa.user_id = prof.id
    WHERE (v_start IS NULL) OR pa.user_id IS NOT NULL
  )
  SELECT
    ROW_NUMBER() OVER (
      ORDER BY
        CASE WHEN p_order_by = 'bankroll' THEN base.current_bankroll END DESC NULLS LAST,
        CASE WHEN p_order_by = 'highest_bankroll' THEN base.highest_bankroll END DESC NULLS LAST,
        CASE WHEN p_order_by = 'streak' THEN base.current_streak END DESC NULLS LAST,
        CASE WHEN p_order_by = 'highest_streak' THEN base.highest_streak END DESC NULLS LAST,
        CASE WHEN p_order_by = 'puzzles' THEN base.total_played END DESC NULLS LAST,
        CASE WHEN p_order_by = 'win_pct' THEN base.win_rate END DESC NULLS LAST,
        base.current_bankroll DESC NULLS LAST
    )::BIGINT AS rank,
    base.user_id,
    base.display_name,
    base.current_bankroll,
    base.highest_bankroll,
    base.current_streak,
    base.highest_streak,
    base.total_played,
    base.total_wins,
    base.win_rate
  FROM base
  ORDER BY
    CASE WHEN p_order_by = 'bankroll' THEN base.current_bankroll END DESC NULLS LAST,
    CASE WHEN p_order_by = 'highest_bankroll' THEN base.highest_bankroll END DESC NULLS LAST,
    CASE WHEN p_order_by = 'streak' THEN base.current_streak END DESC NULLS LAST,
    CASE WHEN p_order_by = 'highest_streak' THEN base.highest_streak END DESC NULLS LAST,
    CASE WHEN p_order_by = 'puzzles' THEN base.total_played END DESC NULLS LAST,
    CASE WHEN p_order_by = 'win_pct' THEN base.win_rate END DESC NULLS LAST,
    base.current_bankroll DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RPC: Record daily game result and update weekly stats
CREATE OR REPLACE FUNCTION public.record_daily_result(
  p_user_id UUID,
  p_won BOOLEAN,
  p_bankroll_left INT
)
RETURNS void AS $$
DECLARE
  v_week_start DATE;
  v_current_streak INT;
  v_highest_streak INT;
  v_last_win DATE;
BEGIN
  v_week_start := date_trunc('week', CURRENT_DATE)::DATE + 1; -- Monday

  -- Get current streak from profiles
  SELECT current_win_streak, highest_win_streak, last_daily_win_date
  INTO v_current_streak, v_highest_streak, v_last_win
  FROM public.profiles WHERE id = p_user_id;

  -- Update streak, daily bankroll, and last result
  IF p_won THEN
    IF v_last_win = CURRENT_DATE - 1 THEN
      v_current_streak := COALESCE(v_current_streak, 0) + 1;
    ELSIF v_last_win != CURRENT_DATE THEN
      v_current_streak := 1;
    END IF;
    v_highest_streak := GREATEST(COALESCE(v_highest_streak, 0), v_current_streak);
    UPDATE public.profiles SET
      current_win_streak = v_current_streak,
      highest_win_streak = v_highest_streak,
      last_daily_win_date = CURRENT_DATE,
      last_daily_play_date = CURRENT_DATE,
      daily_bankroll = p_bankroll_left,
      last_daily_won = true
    WHERE id = p_user_id;
  ELSE
    UPDATE public.profiles SET
      current_win_streak = 0,
      last_daily_play_date = CURRENT_DATE,
      daily_bankroll = p_bankroll_left,
      last_daily_won = false
    WHERE id = p_user_id;
  END IF;

  -- Insert into game_results for period-based leaderboards
  INSERT INTO public.game_results (user_id, played_at, won, bankroll_left, game_mode)
  VALUES (p_user_id, NOW(), p_won, p_bankroll_left, 'daily');

  -- Upsert weekly stats
  INSERT INTO public.user_weekly_stats (user_id, week_start, puzzles_completed, bankroll_earned, highest_bankroll, total_wins, total_played, win_streak)
  VALUES (
    p_user_id, v_week_start,
    CASE WHEN p_won THEN 1 ELSE 0 END,
    CASE WHEN p_won THEN p_bankroll_left ELSE 0 END,
    p_bankroll_left,
    CASE WHEN p_won THEN 1 ELSE 0 END,
    1,
    COALESCE(v_current_streak, 0)
  )
  ON CONFLICT (user_id, week_start) DO UPDATE SET
    total_played = user_weekly_stats.total_played + 1,
    total_wins = user_weekly_stats.total_wins + CASE WHEN p_won THEN 1 ELSE 0 END,
    puzzles_completed = user_weekly_stats.puzzles_completed + CASE WHEN p_won THEN 1 ELSE 0 END,
    bankroll_earned = user_weekly_stats.bankroll_earned + CASE WHEN p_won THEN p_bankroll_left ELSE 0 END,
    highest_bankroll = GREATEST(user_weekly_stats.highest_bankroll, p_bankroll_left),
    win_streak = GREATEST(user_weekly_stats.win_streak, v_current_streak);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5b. RPC: Record arcade game result
CREATE OR REPLACE FUNCTION public.record_arcade_result(
  p_user_id UUID,
  p_won BOOLEAN,
  p_bankroll_left INT
)
RETURNS void AS $$
DECLARE
  v_arcade_streak INT;
  v_highest_arcade_streak INT;
BEGIN
  SELECT arcade_win_streak, highest_arcade_streak INTO v_arcade_streak, v_highest_arcade_streak
  FROM public.profiles WHERE id = p_user_id;

  IF p_won THEN
    v_arcade_streak := COALESCE(v_arcade_streak, 0) + 1;
    v_highest_arcade_streak := GREATEST(COALESCE(v_highest_arcade_streak, 0), v_arcade_streak);
  ELSE
    v_arcade_streak := 0;
  END IF;

  UPDATE public.profiles SET
    arcade_bankroll = p_bankroll_left,
    highest_arcade_bankroll = GREATEST(COALESCE(highest_arcade_bankroll, 1000), p_bankroll_left),
    arcade_win_streak = v_arcade_streak,
    highest_arcade_streak = COALESCE(v_highest_arcade_streak, highest_arcade_streak, 0)
  WHERE id = p_user_id;

  INSERT INTO public.game_results (user_id, played_at, won, bankroll_left, game_mode)
  VALUES (p_user_id, NOW(), p_won, p_bankroll_left, 'arcade');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RPC: Get weekly leaderboard
CREATE OR REPLACE FUNCTION public.get_weekly_leaderboard(p_limit INT DEFAULT 10)
RETURNS TABLE (
  rank BIGINT,
  user_id UUID,
  display_name TEXT,
  puzzles_completed INT,
  bankroll_earned INT,
  highest_bankroll INT,
  win_streak INT,
  win_rate NUMERIC
) AS $$
DECLARE
  v_week_start DATE;
BEGIN
  v_week_start := date_trunc('week', CURRENT_DATE)::DATE + 1;

  RETURN QUERY
  SELECT
    ROW_NUMBER() OVER (ORDER BY s.puzzles_completed DESC, s.bankroll_earned DESC)::BIGINT AS rank,
    s.user_id,
    COALESCE(p.raw_user_meta_data->>'full_name', split_part(p.raw_user_meta_data->>'email', '@', 1), 'Player')::TEXT AS display_name,
    s.puzzles_completed,
    s.bankroll_earned,
    s.highest_bankroll,
    s.win_streak,
    CASE WHEN s.total_played > 0 THEN ROUND((s.total_wins::NUMERIC / s.total_played) * 100, 1) ELSE 0 END AS win_rate
  FROM public.user_weekly_stats s
  LEFT JOIN auth.users p ON p.id = s.user_id
  WHERE s.week_start = v_week_start
  ORDER BY s.puzzles_completed DESC, s.bankroll_earned DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. RPC: Get ALL users with all stats (zeros when no weekly record)
CREATE OR REPLACE FUNCTION public.get_all_users_leaderboard()
RETURNS TABLE (
  rank BIGINT,
  user_id UUID,
  display_name TEXT,
  current_bankroll INT,
  current_win_streak INT,
  highest_win_streak INT,
  puzzles_completed INT,
  bankroll_earned INT,
  highest_bankroll INT,
  win_streak INT,
  total_wins INT,
  total_played INT,
  win_rate NUMERIC
) AS $$
DECLARE
  v_week_start DATE;
BEGIN
  v_week_start := date_trunc('week', CURRENT_DATE)::DATE + 1;

  RETURN QUERY
  SELECT
    ROW_NUMBER() OVER (ORDER BY COALESCE(s.puzzles_completed, 0) DESC, COALESCE(s.bankroll_earned, 0) DESC)::BIGINT AS rank,
    prof.id AS user_id,
    COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email', '@', 1), 'Player')::TEXT AS display_name,
    COALESCE(prof.current_bankroll, 1000)::INT AS current_bankroll,
    COALESCE(prof.current_win_streak, 0)::INT AS current_win_streak,
    COALESCE(prof.highest_win_streak, 0)::INT AS highest_win_streak,
    COALESCE(s.puzzles_completed, 0)::INT AS puzzles_completed,
    COALESCE(s.bankroll_earned, 0)::INT AS bankroll_earned,
    COALESCE(s.highest_bankroll, 0)::INT AS highest_bankroll,
    COALESCE(s.win_streak, 0)::INT AS win_streak,
    COALESCE(s.total_wins, 0)::INT AS total_wins,
    COALESCE(s.total_played, 0)::INT AS total_played,
    CASE WHEN COALESCE(s.total_played, 0) > 0 THEN ROUND((COALESCE(s.total_wins, 0)::NUMERIC / s.total_played) * 100, 1) ELSE 0 END AS win_rate
  FROM public.profiles prof
  LEFT JOIN auth.users au ON au.id = prof.id
  LEFT JOIN public.user_weekly_stats s ON s.user_id = prof.id AND s.week_start = v_week_start
  ORDER BY COALESCE(s.puzzles_completed, 0) DESC, COALESCE(s.bankroll_earned, 0) DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. RPC: Get leaderboard filtered by period (daily, weekly, monthly, yearly)
CREATE OR REPLACE FUNCTION public.get_leaderboard_by_period(p_period TEXT DEFAULT 'weekly')
RETURNS TABLE (
  rank BIGINT,
  user_id UUID,
  display_name TEXT,
  current_bankroll INT,
  current_win_streak INT,
  highest_win_streak INT,
  puzzles_completed INT,
  bankroll_earned INT,
  highest_bankroll INT,
  win_streak INT,
  total_wins INT,
  total_played INT,
  win_rate NUMERIC
) AS $$
DECLARE
  v_start TIMESTAMPTZ;
  v_end TIMESTAMPTZ;
BEGIN
  CASE p_period
    WHEN 'daily' THEN
      v_start := date_trunc('day', CURRENT_DATE) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '1 day';
    WHEN 'weekly' THEN
      v_start := (date_trunc('week', CURRENT_DATE)::DATE + 1)::TIMESTAMPTZ;
      v_end := v_start + INTERVAL '7 days';
    WHEN 'monthly' THEN
      v_start := date_trunc('month', CURRENT_DATE) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '1 month';
    WHEN 'yearly' THEN
      v_start := date_trunc('year', CURRENT_DATE) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '1 year';
    ELSE
      v_start := (date_trunc('week', CURRENT_DATE)::DATE + 1)::TIMESTAMPTZ;
      v_end := v_start + INTERVAL '7 days';
  END CASE;

  RETURN QUERY
  WITH period_agg AS (
    SELECT
      gr.user_id,
      COUNT(*) FILTER (WHERE gr.won)::INT AS puzzles_completed,
      COALESCE(SUM(gr.bankroll_left) FILTER (WHERE gr.won), 0)::INT AS bankroll_earned,
      COALESCE(MAX(gr.bankroll_left), 0)::INT AS highest_bankroll,
      COUNT(*)::INT AS total_played,
      COUNT(*) FILTER (WHERE gr.won)::INT AS total_wins
    FROM public.game_results gr
    WHERE gr.played_at >= v_start AND gr.played_at < v_end
    GROUP BY gr.user_id
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY COALESCE(prof.current_bankroll, 1000) DESC)::BIGINT AS rank,
    prof.id AS user_id,
    COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email', '@', 1), 'Player')::TEXT AS display_name,
    COALESCE(prof.current_bankroll, 1000)::INT AS current_bankroll,
    COALESCE(prof.current_win_streak, 0)::INT AS current_win_streak,
    COALESCE(prof.highest_win_streak, 0)::INT AS highest_win_streak,
    COALESCE(pa.puzzles_completed, 0)::INT AS puzzles_completed,
    COALESCE(pa.bankroll_earned, 0)::INT AS bankroll_earned,
    COALESCE(pa.highest_bankroll, 0)::INT AS highest_bankroll,
    COALESCE(pa.puzzles_completed, 0)::INT AS win_streak,
    COALESCE(pa.total_wins, 0)::INT AS total_wins,
    COALESCE(pa.total_played, 0)::INT AS total_played,
    CASE WHEN COALESCE(pa.total_played, 0) > 0 THEN ROUND((COALESCE(pa.total_wins, 0)::NUMERIC / pa.total_played) * 100, 1) ELSE 0 END AS win_rate
  FROM public.profiles prof
  LEFT JOIN auth.users au ON au.id = prof.id
  LEFT JOIN period_agg pa ON pa.user_id = prof.id
  ORDER BY COALESCE(prof.current_bankroll, 1000) DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
