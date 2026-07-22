-- ============================================================================
-- LAUNCH DAY-1 RESET  ·  ⚠️ DESTRUCTIVE — READ BEFORE RUNNING  ·  DO NOT AUTO-APPLY
-- ============================================================================
-- Purpose: wipe all game / economy / social / leaderboard history and reset every
-- kept account to the exact state of a brand-new signup, so a public launch starts
-- fair and clean. New users already start fresh (per-user state) — this only cleans
-- up the ~40 pre-launch accounts so testers don't sit atop the launch leaderboards.
--
-- WHAT IT DOES
--   1. Deletes ONLY the obvious junk/test accounts listed in step 1 (edit the list).
--      Everyone else — including your real friends/family signups — is KEPT.
--   2. Wipes ALL game/economy/social/challenge/group/notification history for everyone.
--   3. Resets every kept profile to the fresh-signup baseline (bank 2000, credit 650,
--      current_bankroll 1000, all streaks/stats/cosmetics/loans zeroed).
--   4. Clears the Daily schedule so the Daily restarts from launch day.
--
-- WHAT IT PRESERVES (never touched):
--   • Puzzle content/config:  daily_puzzles, puzzles, climb_sequence, daily_puzzle_schedule*
--   • Catalogs:               powerups, cosmetics
--   • Config:                 app_secrets
--   • Accounts kept:          auth.users + profiles (RESET, not deleted) for everyone
--                             except the junk list; their username / friend_code /
--                             account_number / member_no / timezone / push_prefs stay.
--   • device_tokens:          kept accounts keep their push registration.
--   (* daily_puzzle_schedule IS cleared in step 4 so the Daily restarts — that's intended.)
--
-- ⏱️ TIMING: run this at GO-LIVE — AFTER Apple approval + TestFlight, immediately before
--    you flip the app to publicly available (use a manual/phased release). Running it now
--    just gets re-dirtied by review + testing. Keep one working demo account for Apple.
--
-- ▶️ DRY RUN FIRST: change the final `COMMIT;` to `ROLLBACK;` and run — you'll see the
--    BEFORE/AFTER summaries with zero changes committed. Then flip back to COMMIT.
-- ============================================================================
BEGIN;

-- ── STEP 1 · Junk accounts to DELETE outright (everyone else is kept + reset). ──────
-- Edit freely. Leave the list empty to keep ALL accounts and only reset their data.
CREATE TEMP TABLE _drop ON COMMIT DROP AS
  SELECT p.id
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE lower(u.email) IN (
    'test7@gmail.com',
    'hi@jim.com',
    'jim@gmail.com',
    'jim@beam.com',
    'dummyproofcrypto@gmail.com',
    'chatgptvsgrok@gmail.com',
    'char4man77@yahoo.com'      -- username "chuckles" (owner alt)
    -- NOTE: sfforema@gmail.com is the owner's brother — KEEP (reset to baseline, not deleted).
  );

-- Safety: NEVER drop the owner account, and never let this delete everyone.
DELETE FROM _drop WHERE id IN (
  SELECT p.id FROM public.profiles p JOIN auth.users u ON u.id = p.id
  WHERE lower(u.email) = 'charlieforeman77@gmail.com'
);
DO $$
BEGIN
  IF (SELECT count(*) FROM _drop) >= (SELECT count(*) FROM public.profiles) THEN
    RAISE EXCEPTION 'Refusing to run: the drop-list covers every account. Edit step 1.';
  END IF;
END $$;

-- ── BEFORE summary ──────────────────────────────────────────────────────────────────
SELECT 'BEFORE' AS phase,
       (SELECT count(*) FROM public.profiles)  AS accounts,
       (SELECT count(*) FROM _drop)            AS to_delete,
       (SELECT count(*) FROM public.game_results) AS game_results,
       (SELECT count(*) FROM public.bank_ledger)  AS ledger_rows;

-- ── STEP 2 · Wipe ALL game / economy / social / challenge / group history ───────────
-- CASCADE resolves FK ordering automatically. device_tokens is intentionally excluded
-- so kept accounts keep push. daily_puzzle_schedule cleared here = Daily restarts.
TRUNCATE
  public.bank_ledger,
  public.blitz_runs,
  public.category_stats,
  public.challenge_matches,
  public.challenge_participants,
  public.challenge_pack,
  public.challenge_plays,
  public.challenges,
  public.climb_state,
  public.credit_history,
  public.daily_sessions,
  public.daily_stats,
  public.daily_puzzle_schedule,
  public.events,
  public.friendships,
  public.friend_requests,
  public.game_results,
  public.group_members,
  public.group_messages,
  public.group_join_requests,
  public.groups,
  public.match_messages,
  public.networth_snapshots,
  public.notifications,
  public.push_log,
  public.user_badges,
  public.user_cosmetics,
  public.user_powerups,
  public.user_powerups_v2,
  public.user_seen_puzzles,
  public.user_weekly_stats
  CASCADE;

-- ── STEP 3 · Delete the junk accounts (cascades their profile + device_tokens) ──────
DELETE FROM auth.users u WHERE u.id IN (SELECT id FROM _drop);

-- ── STEP 4 · Reset every remaining profile to the fresh-signup baseline ─────────────
-- Mirrors handle_new_user() (bank = 2000) + the column defaults. Keeps id, username,
-- friend_code, account_number, member_no, timezone, push_prefs.
UPDATE public.profiles SET
  current_bankroll           = 1000,
  bank                       = 2000,
  loan                       = NULL,
  loan_principal             = NULL,
  loan_rate_bp               = NULL,
  loan_taken_at              = NULL,
  loan_accrued_at            = NULL,
  auto_repay                 = false,
  last_bankruptcy_at         = NULL,
  credit_score               = 650,
  credit_updated_at          = NULL,
  credit_derog_until         = NULL,
  total_games_played         = 0,
  total_games_won            = 0,
  total_games_lost           = 0,
  total_puzzles_correct      = 0,
  total_puzzles_incorrect    = 0,
  total_cash_accrued         = 0,
  total_cash_spent           = 0,
  most_puzzles_in_one_day    = 0,
  highest_daily_bankroll     = 0,
  daily_bankroll             = 0,
  current_daily_play_streak  = 0,
  best_daily_play_streak     = 0,
  current_daily_solve_streak = 0,
  best_daily_solve_streak    = 0,
  last_daily_play_date       = NULL,
  last_daily_win_date        = NULL,
  last_daily_solve_date      = NULL,
  last_daily_won             = NULL,
  streak_freezes             = 0,
  equipped_title             = NULL,
  equipped_color             = NULL,
  avatar                     = NULL,
  cg_wins                    = '{}'::jsonb,
  cg_run_streak              = 0,
  cg_best_run_streak         = 0,
  cg_best_run                = 0,
  cg_best_multiple_x100      = 0,
  cg_best_heat_x100          = 100,
  cg_lifetime_net            = 0,
  bz_best_run                = 0,
  bz_best_combo_x100         = 100,
  bz_best_payout             = 0,
  bz_lifetime_net            = 0,
  bz_runs                    = 0,
  bz_highest_tier            = NULL;

-- ── AFTER summary ───────────────────────────────────────────────────────────────────
SELECT 'AFTER' AS phase,
       (SELECT count(*) FROM public.profiles)                       AS accounts,
       (SELECT count(*) FROM public.game_results)                   AS game_results,
       (SELECT count(*) FROM public.bank_ledger)                    AS ledger_rows,
       (SELECT count(*) FROM public.daily_puzzle_schedule)          AS daily_days,
       (SELECT count(*) FILTER (WHERE bank <> 2000 OR credit_score <> 650) FROM public.profiles) AS non_baseline_profiles;

-- Change to ROLLBACK; for a dry run. COMMIT; to apply for real.
COMMIT;
