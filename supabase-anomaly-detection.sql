-- ============================================================
-- WordBank: Lightweight daily anomaly detection (admin-only)
-- Run in Supabase SQL Editor (project: wordbankmaster).
-- ============================================================
--
-- Read-only analysis over data the server already holds (daily_sessions). No
-- gameplay changes, no new columns. Two SECURITY DEFINER functions, callable ONLY
-- by the service role (never by clients), since they expose other users' data.
--
-- IMPORTANT — what these can and cannot catch:
--   * Server-authoritative scoring already makes score FABRICATION impossible.
--   * These functions look for SOLVING-ASSISTANCE / automation patterns.
--   * In this game the optimal honest strategy (guess early, spend little) looks
--     like AI-assisted play, so EFFICIENCY is a weak signal (expect false positives
--     on the 'won_minimal_info' flag from genuinely skilled players).
--   * TIMING (superhuman speed) and CROSS-DAY CONSISTENCY are the real signals.
--   * Treat all output as advisory for MANUAL REVIEW. Never auto-punish.

-- ------------------------------------------------------------
-- 1. Per-game flags for finished daily sessions in a date range.
--    Only returns rows that tripped at least one flag.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_daily_anomalies(
  p_from DATE DEFAULT CURRENT_DATE,
  p_to   DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  puzzle_date DATE,
  user_id UUID,
  display_name TEXT,
  state TEXT,
  duration_seconds INT,
  amount_spent INT,
  incorrect_count INT,
  revealed_count INT,
  flags TEXT[]
) LANGUAGE plpgsql SECURITY DEFINER AS $fn$
BEGIN
  RETURN QUERY
  WITH base AS (
    SELECT
      s.puzzle_date,
      s.user_id,
      s.state,
      GREATEST(0, EXTRACT(EPOCH FROM (s.finished_at - s.created_at)))::INT AS dur,
      (1000 - s.bankroll)::INT AS spent,
      COALESCE(array_length(s.incorrect_letters, 1), 0)::INT AS inc,
      COALESCE(array_length(s.revealed_positions, 1), 0)::INT AS rev
    FROM public.daily_sessions s
    WHERE s.puzzle_date BETWEEN p_from AND p_to
      AND s.finished_at IS NOT NULL
  ),
  flagged AS (
    SELECT b.*,
      (
             CASE WHEN b.state = 'won' AND b.dur < 8                         THEN ARRAY['instant_solve']     ELSE ARRAY[]::TEXT[] END
          || CASE WHEN b.state = 'won' AND b.dur >= 8 AND b.dur < 20         THEN ARRAY['fast_solve']        ELSE ARRAY[]::TEXT[] END
          || CASE WHEN b.state = 'won' AND b.inc = 0 AND b.spent < 150       THEN ARRAY['won_minimal_info']  ELSE ARRAY[]::TEXT[] END
      ) AS f
    FROM base b
  )
  SELECT
    fl.puzzle_date,
    fl.user_id,
    COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email', '@', 1), 'Player')::TEXT,
    fl.state,
    fl.dur,
    fl.spent,
    fl.inc,
    fl.rev,
    fl.f
  FROM flagged fl
  LEFT JOIN auth.users au ON au.id = fl.user_id
  WHERE cardinality(fl.f) > 0
  ORDER BY fl.puzzle_date DESC, fl.dur ASC;
END;
$fn$;

-- ------------------------------------------------------------
-- 2. Per-player rollup over the last N days. Ranks players by a simple
--    suspicion ordering (high win rate + many fast wins). This cross-day
--    consistency view is the stronger signal — review the top of the list.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_player_anomaly_summary(p_days INT DEFAULT 30)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  games INT,
  wins INT,
  win_rate NUMERIC,
  avg_duration_seconds NUMERIC,
  fast_wins INT,        -- wins solved in < 20s
  instant_wins INT,     -- wins solved in < 8s
  flawless_wins INT,    -- wins with zero incorrect letters
  current_streak INT
) LANGUAGE plpgsql SECURITY DEFINER AS $fn$
BEGIN
  RETURN QUERY
  WITH g AS (
    SELECT
      s.user_id,
      s.state,
      GREATEST(0, EXTRACT(EPOCH FROM (s.finished_at - s.created_at)))::INT AS dur,
      COALESCE(array_length(s.incorrect_letters, 1), 0)::INT AS inc
    FROM public.daily_sessions s
    WHERE s.finished_at IS NOT NULL
      AND s.puzzle_date >= CURRENT_DATE - (GREATEST(p_days, 1) - 1)
  ),
  agg AS (
    SELECT
      g.user_id,
      COUNT(*)::INT AS games,
      COUNT(*) FILTER (WHERE g.state = 'won')::INT AS wins,
      ROUND(AVG(g.dur) FILTER (WHERE g.state = 'won'), 1) AS avg_dur,
      COUNT(*) FILTER (WHERE g.state = 'won' AND g.dur < 20)::INT AS fast_wins,
      COUNT(*) FILTER (WHERE g.state = 'won' AND g.dur < 8)::INT AS instant_wins,
      COUNT(*) FILTER (WHERE g.state = 'won' AND g.inc = 0)::INT AS flawless_wins
    FROM g
    GROUP BY g.user_id
  )
  SELECT
    a.user_id,
    COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email', '@', 1), 'Player')::TEXT,
    a.games,
    a.wins,
    (CASE WHEN a.games > 0 THEN ROUND((a.wins::NUMERIC / a.games) * 100, 1) ELSE 0 END),
    a.avg_dur,
    a.fast_wins,
    a.instant_wins,
    a.flawless_wins,
    COALESCE(p.current_win_streak, 0)::INT
  FROM agg a
  LEFT JOIN auth.users au ON au.id = a.user_id
  LEFT JOIN public.profiles p ON p.id = a.user_id
  ORDER BY a.instant_wins DESC, a.fast_wins DESC, (a.wins::NUMERIC / NULLIF(a.games, 0)) DESC NULLS LAST;
END;
$fn$;

-- ------------------------------------------------------------
-- Admin-only: clients must NOT be able to call these (they expose other users).
-- ------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.get_daily_anomalies(DATE, DATE)        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_player_anomaly_summary(INT)        FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.get_daily_anomalies(DATE, DATE)        TO service_role;
GRANT  EXECUTE ON FUNCTION public.get_player_anomaly_summary(INT)        TO service_role;
