-- One-time cleanup: friendly (wager 0) challenge matches are not supposed to count toward any
-- global stats. Task 4 (supabase-friendly-no-stats.sql) gates the WRITE side going forward, but
-- 12 legacy rows (3 won / 9 lost, 6 matches, 12 users) were written before the gate and still feed
-- the challenge leaderboard, best-bounty, wealth board, and play-log. Purge them.
--
-- Safe: friendly game_results carry no money (net/spent/earned all NULL for these rows — verified),
-- so no ledger/balance is affected. Already-granted cosmetic badges (first_blood/hustler) and past
-- category-solve counts are intentionally left as-is (grandfathered) — clawing back an earned badge
-- is worse UX than the leaderboard pollution this removes, and the win counts here are tiny.

DELETE FROM public.game_results gr
USING public.challenge_matches cm
WHERE cm.id = gr.match_id
  AND gr.game_mode = 'challenge'
  AND COALESCE(cm.wager, 0) = 0;
