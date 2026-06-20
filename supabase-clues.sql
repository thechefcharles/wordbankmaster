-- ============================================================
-- Puzzle clues: a witty one-line hint shown during play (the daily_puzzles.clue
-- column). These RPCs return the clue for the caller's CURRENT puzzle only —
-- SECURITY DEFINER + auth.uid(), and the clue never reveals the answer.
-- ============================================================

CREATE OR REPLACE FUNCTION public.daily_clue()
RETURNS TEXT LANGUAGE sql SECURITY DEFINER AS $fn$
  SELECT dp.clue FROM public.daily_sessions s
  JOIN public.daily_puzzles dp ON dp.id = s.puzzle_id
  WHERE s.user_id = auth.uid() AND s.puzzle_date = CURRENT_DATE;
$fn$;
GRANT EXECUTE ON FUNCTION public.daily_clue() TO authenticated;

CREATE OR REPLACE FUNCTION public.arcade_clue()
RETURNS TEXT LANGUAGE sql SECURITY DEFINER AS $fn$
  SELECT dp.clue FROM public.arcade_runs r
  JOIN public.daily_puzzles dp ON dp.id = r.puzzle_id
  WHERE r.user_id = auth.uid() AND r.run_date = CURRENT_DATE;
$fn$;
GRANT EXECUTE ON FUNCTION public.arcade_clue() TO authenticated;
