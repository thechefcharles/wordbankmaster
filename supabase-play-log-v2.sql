-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Play Log v2 — game_results becomes the unified rich record (foundation)    ║
-- ║  migrations: play_log_v2_schema_helper_solo_writers                         ║
-- ║              play_log_v2_climb_challenge_match_writers   (both via MCP)     ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- Foundation for STATS_AND_HISTORY_DESIGN.md. One enriched row per completed game,
-- EVERY mode (daily, arcade, climb, challenge). Powers: career stats, /history +
-- filters, per-challenge detail, 1v1 head-to-head (query by opponent_id).
--
-- ADDITIVE & SAFE: legacy columns (won, bankroll_left, game_mode, score) keep their
-- EXACT prior meaning, so existing leaderboards (which filter by game_mode) are
-- untouched. New climb/challenge rows don't hit daily/arcade boards.
--
-- New columns on game_results (all nullable):
--   outcome (won|lost|tie), puzzle_id, category, solved_count, puzzle_count,
--   spent, earned, net, multiple_x100 (return multiple ×100), time_ms,
--   clean, first_try, no_reveals, no_vowels,
--   match_id, opponent_id, group_id, rank, field_size, pot, wager
-- Indexes: (user_id, opponent_id) [H2H], (match_id) [detail], (user_id, game_mode, played_at desc).
--
-- Writers:
--   • _finalize_daily   — own INSERT, extended (legacy bankroll_left=spent, score=net kept).
--                         Adds puzzle/category/solved/spent/earned/net/multiple/clean.
--   • record_arcade_result — own INSERT, extended with outcome + earned(=banked).
--   • _climb_resolve    — NEW: logs on solve (won, earned=payout, spent) AND on stuck (lost).
--   • _match_settle     — NEW: logs one row per done participant (rank, solved/pack, pot,
--                         wager, group_id, opponent_id for 1v1). spent/earned deferred.
--   • _challenge_settle — NEW (legacy 1v1): logs both players (outcome, pot, opponent).
--   All three settlers reproduced verbatim with ONLY _log_game_result() calls added.
--
-- Helper: _log_game_result(p_user, p_mode, p_outcome, p_puzzle_id, p_category,
--   p_solved, p_total, p_spent, p_earned, p_time_ms, p_clean, p_first_try,
--   p_no_reveals, p_no_vowels, p_match_id, p_opponent_id, p_group_id, p_rank,
--   p_field_size, p_pot, p_wager). Derives net + multiple_x100; sets legacy cols via
--   COALESCE(spent, earned, 0) → bankroll_left, COALESCE(net,0) → score.
--
-- Verified (rolled-back sims):
--   climb: spent 120 / earned 630 → net 510, multiple 525, solved 1/1.
--   daily (k=1.2): spent 140 / earned 830 → net 690, multiple 593, clean, category captured;
--          legacy bankroll_left=140, score=690 preserved.
--   get_daily_leaderboard still returns rows.

ALTER TABLE public.game_results
  ADD COLUMN IF NOT EXISTS outcome       TEXT,
  ADD COLUMN IF NOT EXISTS puzzle_id     UUID,
  ADD COLUMN IF NOT EXISTS category      TEXT,
  ADD COLUMN IF NOT EXISTS solved_count  INT,
  ADD COLUMN IF NOT EXISTS puzzle_count  INT,
  ADD COLUMN IF NOT EXISTS spent         INT,
  ADD COLUMN IF NOT EXISTS earned        INT,
  ADD COLUMN IF NOT EXISTS net           INT,
  ADD COLUMN IF NOT EXISTS multiple_x100 INT,
  ADD COLUMN IF NOT EXISTS time_ms       INT,
  ADD COLUMN IF NOT EXISTS clean         BOOLEAN,
  ADD COLUMN IF NOT EXISTS first_try     BOOLEAN,
  ADD COLUMN IF NOT EXISTS no_reveals    BOOLEAN,
  ADD COLUMN IF NOT EXISTS no_vowels     BOOLEAN,
  ADD COLUMN IF NOT EXISTS match_id      UUID,
  ADD COLUMN IF NOT EXISTS opponent_id   UUID,
  ADD COLUMN IF NOT EXISTS group_id      UUID,
  ADD COLUMN IF NOT EXISTS rank          INT,
  ADD COLUMN IF NOT EXISTS field_size    INT,
  ADD COLUMN IF NOT EXISTS pot           BIGINT,
  ADD COLUMN IF NOT EXISTS wager         BIGINT;

CREATE INDEX IF NOT EXISTS idx_game_results_opponent ON public.game_results (user_id, opponent_id) WHERE opponent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_game_results_match    ON public.game_results (match_id)            WHERE match_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_game_results_mode     ON public.game_results (user_id, game_mode, played_at DESC);

-- Full body of _log_game_result + the rewritten writers were applied via MCP; see the
-- two named migrations above and git history. Helper signature (canonical):
--   public._log_game_result(uuid, text, text, uuid, text, int, int, int, int, int,
--     boolean, boolean, boolean, boolean, uuid, uuid, uuid, int, int, bigint, bigint)

-- NEXT (per STATS_AND_HISTORY_DESIGN.md §8): get_history(filters,cursor),
--   get_game_detail(id), get_match_detail(id), get_head_to_head(opponent) → then /history UI.
