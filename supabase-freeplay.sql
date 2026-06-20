-- ============================================================
-- Free Play: pick a category and solve endless puzzles from it, unranked.
-- Same masked-board economy ($1000, buy letters, reveal, 3 tries) as daily/
-- arcade, but no banking, multiplier, streaks, or leaderboard. One session
-- per user, replaced when a new category is started.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.freeplay_sessions (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  puzzle_id UUID NOT NULL REFERENCES public.daily_puzzles(id) ON DELETE CASCADE,
  bankroll INT NOT NULL DEFAULT 1000,
  guesses_remaining INT NOT NULL DEFAULT 3,
  revealed_positions INT[] NOT NULL DEFAULT '{}',
  incorrect_letters TEXT[] NOT NULL DEFAULT '{}',
  state TEXT NOT NULL DEFAULT 'active',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.freeplay_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "read own freeplay" ON public.freeplay_sessions;
CREATE POLICY "read own freeplay" ON public.freeplay_sessions FOR SELECT USING (auth.uid() = user_id);
REVOKE INSERT, UPDATE, DELETE ON public.freeplay_sessions FROM anon, authenticated;

-- _freeplay_response / _freeplay_resolve / freeplay_start / freeplay_next /
-- freeplay_buy_letter / freeplay_reveal / freeplay_submit_guess / freeplay_clue
-- are defined in the daily/arcade style (masked board via _daily_board).
-- See migration "freeplay_engine" for the full function bodies (applied to prod).
