-- ============================================================================
-- Prune too-short puzzles: remove every phrase ≤4 letters (spaces excluded).
-- These are guessable without buying any letters (Nike, Uber, URL, API, BP, Coco,
-- Jaws, Ace…) and undermine the buy-letters mechanic. Keeps 5+ as the floor.
-- daily_puzzles is referenced by 5 FKs: climb_sequence + user_seen_puzzles CASCADE;
-- daily_puzzle_schedule / daily_sessions / challenges are RESTRICT/NO-ACTION, so we
-- clear those refs first. All that ref data is test-only and cleared by the launch
-- reset anyway. Data-only, applied to prod. ~67 rows removed (2100 → ~2033).
-- ============================================================================
BEGIN;

CREATE TEMP TABLE _short ON COMMIT DROP AS
  SELECT id FROM public.daily_puzzles
  WHERE char_length(replace(phrase, ' ', '')) <= 4;

-- clear references that would otherwise block the delete
DELETE FROM public.daily_puzzle_schedule WHERE puzzle_id IN (SELECT id FROM _short);
DELETE FROM public.daily_sessions        WHERE puzzle_id IN (SELECT id FROM _short);
DELETE FROM public.challenge_pack         WHERE puzzle_id IN (SELECT id FROM _short);
DELETE FROM public.challenges             WHERE puzzle_id IN (SELECT id FROM _short);

-- delete the short puzzles (cascades climb_sequence + user_seen_puzzles)
DELETE FROM public.daily_puzzles WHERE id IN (SELECT id FROM _short);

COMMIT;
