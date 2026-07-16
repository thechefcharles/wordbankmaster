-- Perf indexes from the 2026-07-16 audit. Cheap to add now while tables are small; prevents
-- silent leaderboard/settle degradation as game_results and challenge_participants grow.
-- Serves the daily-window + challenge-filter leaderboard aggregates:
CREATE INDEX IF NOT EXISTS idx_game_results_mode_played
  ON public.game_results (game_mode, played_at DESC);
-- Removes the seq scan of challenge_participants in the _match_settle win-count subquery
-- (pkey is (match_id, user_id), so WHERE user_id = ... had no usable index):
CREATE INDEX IF NOT EXISTS idx_challenge_participants_user
  ON public.challenge_participants (user_id);
