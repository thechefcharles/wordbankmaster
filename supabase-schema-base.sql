-- ============================================================
-- WordBank: Base schema (run FIRST on a fresh database)
-- ============================================================
--
-- The `profiles` base table was originally created in the Supabase dashboard and
-- was never version-controlled, so the other migration files (which only ALTER /
-- reference profiles) fail on a fresh database with:
--   ERROR: relation "public.profiles" does not exist (SQLSTATE 42P01)
--
-- This file defines profiles exactly as it exists in production so the full set of
-- migrations is reproducible from scratch.
--
-- RUN ORDER on a fresh project:
--   1. supabase-schema-base.sql            (this file)
--   2. supabase-create-profile-trigger.sql
--   3. supabase-daily-leaderboard.sql
--   4. supabase-daily-server-authoritative.sql
--   5. supabase-security-hardening.sql     (REVOKEs — must be last)
--
-- On an EXISTING database that already has profiles, this file is a safe no-op
-- (every statement is IF NOT EXISTS / ADD COLUMN IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID NOT NULL DEFAULT auth.uid()
    REFERENCES auth.users(id) ON DELETE CASCADE,
  current_bankroll INT NOT NULL DEFAULT 1000,
  total_games_played INT DEFAULT 0,
  total_games_won INT DEFAULT 0,
  total_games_lost INT DEFAULT 0,
  highest_daily_bankroll INT DEFAULT 0,
  total_puzzles_correct INT DEFAULT 0,
  total_puzzles_incorrect INT DEFAULT 0,
  total_cash_accrued INT DEFAULT 0,
  total_cash_spent INT DEFAULT 0,
  most_puzzles_in_one_day INT DEFAULT 0,
  current_win_streak INT DEFAULT 0,
  highest_win_streak INT DEFAULT 0,
  last_daily_win_date DATE,
  last_daily_play_date DATE,
  daily_bankroll INT DEFAULT 0,
  last_daily_won BOOLEAN,
  arcade_bankroll INT DEFAULT 1000,
  highest_arcade_bankroll INT DEFAULT 1000,
  arcade_win_streak INT DEFAULT 0,
  highest_arcade_streak INT DEFAULT 0,
  CONSTRAINT profiles_pkey PRIMARY KEY (id)
);

-- RLS is enabled and policies are defined in supabase-create-profile-trigger.sql.
