-- ============================================================
-- WordBank: Server-authoritative DAILY mode
-- Run in Supabase SQL Editor AFTER the other migrations.
-- ============================================================
--
-- Goal: the daily puzzle answer NEVER reaches the client. All scoring
-- (buying letters/hints/guesses, submitting a guess, win/loss, final bankroll)
-- is computed server-side from a per-user, per-day session row. The client is a
-- thin renderer that only ever sees revealed positions + board shape.
--
-- This makes the marketed competitive DAILY leaderboard trustless: a client can
-- no longer fabricate a bankroll or a win, because it never holds the phrase and
-- never writes the score.
--
-- Arcade mode is intentionally left client-side/casual and is unaffected.

-- ---- Per-day session state (server source of truth) -----------------------
CREATE TABLE IF NOT EXISTS public.daily_sessions (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  puzzle_date DATE NOT NULL DEFAULT CURRENT_DATE,
  puzzle_id UUID NOT NULL REFERENCES public.daily_puzzles(id) ON DELETE RESTRICT,
  bankroll INT NOT NULL DEFAULT 1000,
  guesses_remaining INT NOT NULL DEFAULT 3,   -- "attempts"; free, not purchasable
  revealed_positions INT[] NOT NULL DEFAULT '{}',   -- 0-indexed positions revealed so far
  incorrect_letters TEXT[] NOT NULL DEFAULT '{}',   -- letters bought that aren't in the phrase
  state TEXT NOT NULL DEFAULT 'active',              -- 'active' | 'won' | 'lost'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMPTZ,                           -- audit hook for future abuse analysis
  PRIMARY KEY (user_id, puzzle_date)
);

ALTER TABLE public.daily_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "read own daily session" ON public.daily_sessions;
CREATE POLICY "read own daily session" ON public.daily_sessions
  FOR SELECT USING (auth.uid() = user_id);
-- No client write policies: only the SECURITY DEFINER RPCs below mutate sessions.
REVOKE INSERT, UPDATE, DELETE ON public.daily_sessions FROM anon, authenticated;

-- ---- Letter costs live on the server (client can't be the pricing source) --
CREATE OR REPLACE FUNCTION public.letter_cost(p_letter TEXT)
RETURNS INT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE upper(p_letter)
    WHEN 'Q' THEN 30  WHEN 'W' THEN 50  WHEN 'E' THEN 140 WHEN 'R' THEN 120
    WHEN 'T' THEN 120 WHEN 'Y' THEN 60  WHEN 'U' THEN 80  WHEN 'I' THEN 110
    WHEN 'O' THEN 90  WHEN 'P' THEN 80  WHEN 'A' THEN 130 WHEN 'S' THEN 120
    WHEN 'D' THEN 80  WHEN 'F' THEN 60  WHEN 'G' THEN 70  WHEN 'H' THEN 70
    WHEN 'J' THEN 30  WHEN 'K' THEN 50  WHEN 'L' THEN 80  WHEN 'Z' THEN 40
    WHEN 'X' THEN 40  WHEN 'C' THEN 80  WHEN 'V' THEN 50  WHEN 'B' THEN 60
    WHEN 'N' THEN 100 WHEN 'M' THEN 70  ELSE NULL END;
$$;

-- ---- Ensure today's puzzle is assigned and return its id ------------------
CREATE OR REPLACE FUNCTION public._todays_puzzle_id()
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_pid UUID;
BEGIN
  -- First caller of the day assigns a not-yet-used puzzle deterministically; others no-op.
  INSERT INTO public.daily_puzzle_schedule (scheduled_date, puzzle_id)
  SELECT CURRENT_DATE, sub.pid FROM (
    SELECT (
      SELECT p2.id FROM public.daily_puzzles p2
      WHERE p2.id NOT IN (SELECT puzzle_id FROM public.daily_puzzle_schedule)
      ORDER BY md5(CURRENT_DATE::text || p2.id::text)
      LIMIT 1
    ) AS pid
  ) sub
  WHERE sub.pid IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.daily_puzzle_schedule WHERE scheduled_date = CURRENT_DATE)
  ON CONFLICT (scheduled_date) DO NOTHING;

  SELECT puzzle_id INTO v_pid
  FROM public.daily_puzzle_schedule WHERE scheduled_date = CURRENT_DATE;
  RETURN v_pid;
END;
$$;

-- ---- Build the masked board view returned to the client -------------------
-- Reveals letters ONLY for positions the player has earned; reveals the full
-- phrase once the game is over (so the client can show the answer on win/loss).
CREATE OR REPLACE FUNCTION public._daily_board(
  p_phrase TEXT, p_state TEXT, p_bankroll INT, p_guesses INT,
  p_revealed INT[], p_incorrect TEXT[], p_category TEXT, p_subcategory TEXT
)
RETURNS JSONB LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_word_lengths INT[];
  v_revealed JSONB := '{}'::jsonb;
  v_finished BOOLEAN := (p_state <> 'active');
  v_locked TEXT[];
  i INT;
BEGIN
  SELECT array_agg(length(x)) INTO v_word_lengths
  FROM unnest(string_to_array(p_phrase, ' ')) AS x;

  IF v_finished THEN
    FOR i IN 0 .. length(p_phrase) - 1 LOOP
      IF substr(p_phrase, i + 1, 1) <> ' ' THEN
        v_revealed := v_revealed || jsonb_build_object(i::text, substr(p_phrase, i + 1, 1));
      END IF;
    END LOOP;
  ELSIF p_revealed IS NOT NULL THEN
    FOREACH i IN ARRAY p_revealed LOOP
      v_revealed := v_revealed || jsonb_build_object(i::text, substr(p_phrase, i + 1, 1));
    END LOOP;
  END IF;

  -- Letters whose EVERY occurrence is revealed (safe to surface: reveals nothing hidden).
  -- Lets the keyboard green-out fully-solved letters without the client knowing the answer.
  SELECT array_agg(t.ch ORDER BY t.ch) INTO v_locked FROM (
    SELECT chpos.ch
    FROM (
      SELECT substr(p_phrase, g.i + 1, 1) AS ch, g.i AS pos
      FROM generate_series(0, length(p_phrase) - 1) g(i)
      WHERE substr(p_phrase, g.i + 1, 1) <> ' '
    ) chpos
    GROUP BY chpos.ch
    HAVING bool_and(v_finished OR (chpos.pos = ANY(p_revealed)))
  ) t;

  RETURN jsonb_build_object(
    'state', p_state,
    'bankroll', p_bankroll,
    'guesses_remaining', p_guesses,
    'category', p_category,
    'subcategory', COALESCE(p_subcategory, ''),
    'word_lengths', to_jsonb(COALESCE(v_word_lengths, '{}'::int[])),
    'revealed', v_revealed,
    'incorrect_letters', to_jsonb(COALESCE(p_incorrect, '{}'::text[])),
    'locked_letters', to_jsonb(COALESCE(v_locked, '{}'::text[])),
    'phrase', CASE WHEN v_finished THEN p_phrase ELSE NULL END
  );
END;
$$;

-- ---- Finalize: write streak / profile / game_results / weekly stats --------
-- Server-computed bankroll only; clamped to the legitimate daily range [0,1000].
CREATE OR REPLACE FUNCTION public._finalize_daily(p_uid UUID, p_won BOOLEAN, p_bankroll INT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_week_start DATE;
  v_current_streak INT;
  v_highest_streak INT;
  v_last_win DATE;
  v_bankroll INT;
BEGIN
  v_bankroll := LEAST(GREATEST(COALESCE(p_bankroll, 0), 0), 1000);
  v_week_start := date_trunc('week', CURRENT_DATE)::DATE + 1;

  SELECT current_win_streak, highest_win_streak, last_daily_win_date
  INTO v_current_streak, v_highest_streak, v_last_win
  FROM public.profiles WHERE id = p_uid;

  IF p_won THEN
    IF v_last_win = CURRENT_DATE - 1 THEN
      v_current_streak := COALESCE(v_current_streak, 0) + 1;
    ELSIF v_last_win IS DISTINCT FROM CURRENT_DATE THEN
      v_current_streak := 1;
    END IF;
    v_highest_streak := GREATEST(COALESCE(v_highest_streak, 0), v_current_streak);
    UPDATE public.profiles SET
      current_win_streak = v_current_streak,
      highest_win_streak = v_highest_streak,
      last_daily_win_date = CURRENT_DATE,
      last_daily_play_date = CURRENT_DATE,
      daily_bankroll = v_bankroll,
      last_daily_won = true
    WHERE id = p_uid;
  ELSE
    v_current_streak := 0;
    UPDATE public.profiles SET
      current_win_streak = 0,
      last_daily_play_date = CURRENT_DATE,
      daily_bankroll = v_bankroll,
      last_daily_won = false
    WHERE id = p_uid;
  END IF;

  INSERT INTO public.game_results (user_id, played_at, won, bankroll_left, game_mode)
  VALUES (p_uid, NOW(), p_won, v_bankroll, 'daily');

  INSERT INTO public.user_weekly_stats (user_id, week_start, puzzles_completed, bankroll_earned, highest_bankroll, total_wins, total_played, win_streak)
  VALUES (
    p_uid, v_week_start,
    CASE WHEN p_won THEN 1 ELSE 0 END,
    CASE WHEN p_won THEN v_bankroll ELSE 0 END,
    v_bankroll,
    CASE WHEN p_won THEN 1 ELSE 0 END,
    1,
    COALESCE(v_current_streak, 0)
  )
  ON CONFLICT (user_id, week_start) DO UPDATE SET
    total_played = user_weekly_stats.total_played + 1,
    total_wins = user_weekly_stats.total_wins + CASE WHEN p_won THEN 1 ELSE 0 END,
    puzzles_completed = user_weekly_stats.puzzles_completed + CASE WHEN p_won THEN 1 ELSE 0 END,
    bankroll_earned = user_weekly_stats.bankroll_earned + CASE WHEN p_won THEN v_bankroll ELSE 0 END,
    highest_bankroll = GREATEST(user_weekly_stats.highest_bankroll, v_bankroll),
    win_streak = GREATEST(user_weekly_stats.win_streak, v_current_streak);
END;
$$;

-- ---- Internal: recompute win/loss + persist + finalize, return board ------
CREATE OR REPLACE FUNCTION public._daily_resolve_and_return(p_uid UUID, p_phrase TEXT, p_cat TEXT, p_sub TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  s public.daily_sessions;
  v_won BOOLEAN;
  v_lost BOOLEAN;
BEGIN
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;

  -- Win = every non-space position revealed.
  v_won := NOT EXISTS (
    SELECT 1 FROM generate_series(0, length(p_phrase) - 1) g(i)
    WHERE substr(p_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions))
  );
  -- Loss = broke, or out of guesses and can't afford another ($150). Mirrors original game.
  v_lost := (s.bankroll < 30);  -- broke: can't afford the cheapest letter

  IF v_won THEN
    s.state := 'won';
  ELSIF v_lost THEN
    s.state := 'lost';
  END IF;

  UPDATE public.daily_sessions SET
    bankroll = s.bankroll,
    guesses_remaining = s.guesses_remaining,
    revealed_positions = s.revealed_positions,
    incorrect_letters = s.incorrect_letters,
    state = s.state,
    updated_at = NOW(),
    finished_at = CASE WHEN s.state <> 'active' AND finished_at IS NULL THEN NOW() ELSE finished_at END
  WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;

  IF s.state <> 'active' THEN
    PERFORM public._finalize_daily(p_uid, s.state = 'won', s.bankroll);
  END IF;

  RETURN public._daily_board(p_phrase, s.state, s.bankroll, s.guesses_remaining,
                             s.revealed_positions, s.incorrect_letters, p_cat, p_sub);
END;
$$;

-- ===================== Public RPCs (client entry points) ====================

-- Start or resume today's session; returns the masked board.
CREATE OR REPLACE FUNCTION public.daily_start()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_pid UUID;
  v_phrase TEXT; v_cat TEXT; v_sub TEXT;
  s public.daily_sessions;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_start: not authenticated'; END IF;

  v_pid := public._todays_puzzle_id();

  SELECT * INTO s FROM public.daily_sessions WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
  IF NOT FOUND THEN
    IF v_pid IS NULL THEN RAISE EXCEPTION 'daily_start: no puzzle available'; END IF;
    INSERT INTO public.daily_sessions (user_id, puzzle_date, puzzle_id, bankroll, guesses_remaining)
    VALUES (v_uid, CURRENT_DATE, v_pid, 1000, 3)
    RETURNING * INTO s;
  END IF;

  SELECT upper(phrase), category, COALESCE(subcategory, '')
  INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;

  RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
                             s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
END;
$$;

-- Buy a letter: reveal all matching positions, or mark incorrect. Server debits.
CREATE OR REPLACE FUNCTION public.daily_buy_letter(p_letter TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID := auth.uid();
  s public.daily_sessions;
  v_phrase TEXT; v_cat TEXT; v_sub TEXT;
  v_letter TEXT; v_cost INT; v_positions INT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_buy_letter: not authenticated'; END IF;
  v_letter := upper(p_letter);
  v_cost := public.letter_cost(v_letter);
  IF v_cost IS NULL THEN RAISE EXCEPTION 'daily_buy_letter: invalid letter'; END IF;

  SELECT * INTO s FROM public.daily_sessions
  WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'daily_buy_letter: no active session (call daily_start)'; END IF;

  SELECT upper(phrase), category, COALESCE(subcategory, '')
  INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;

  -- No-ops (return current board unchanged): finished, already incorrect, or can't afford.
  IF s.state <> 'active'
     OR v_letter = ANY(s.incorrect_letters)
     OR s.bankroll < v_cost THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
                               s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;

  SELECT array_agg(g.i) INTO v_positions
  FROM generate_series(0, length(v_phrase) - 1) g(i)
  WHERE substr(v_phrase, g.i + 1, 1) = v_letter;

  -- Letter already fully revealed -> treat as no-op (don't double-charge).
  IF v_positions IS NOT NULL AND v_positions <@ s.revealed_positions THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
                               s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;

  s.bankroll := s.bankroll - v_cost;
  IF v_positions IS NULL THEN
    s.incorrect_letters := array_append(s.incorrect_letters, v_letter);
  ELSE
    s.revealed_positions := ARRAY(SELECT DISTINCT unnest(s.revealed_positions || v_positions) ORDER BY 1);
  END IF;

  UPDATE public.daily_sessions SET
    bankroll = s.bankroll, incorrect_letters = s.incorrect_letters,
    revealed_positions = s.revealed_positions, updated_at = NOW()
  WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;

  RETURN public._daily_resolve_and_return(v_uid, v_phrase, v_cat, v_sub);
END;
$$;

-- Reveal ($150): reveal ALL instances of the most-frequent unrevealed letter.
-- Smart (not random) and a strict upgrade over the old single-tile hint.
CREATE OR REPLACE FUNCTION public.daily_reveal()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID := auth.uid();
  s public.daily_sessions;
  v_phrase TEXT; v_cat TEXT; v_sub TEXT;
  v_letter TEXT; v_positions INT[]; v_cost INT := 150;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_reveal: not authenticated'; END IF;

  SELECT * INTO s FROM public.daily_sessions
  WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'daily_reveal: no active session'; END IF;

  SELECT upper(phrase), category, COALESCE(subcategory, '')
  INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;

  SELECT t.ch INTO v_letter FROM (
    SELECT substr(v_phrase, g.i + 1, 1) AS ch, count(*) AS c
    FROM generate_series(0, length(v_phrase) - 1) g(i)
    WHERE substr(v_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions))
    GROUP BY substr(v_phrase, g.i + 1, 1)
    ORDER BY c DESC, ch
    LIMIT 1
  ) t;

  IF s.state <> 'active' OR s.bankroll < v_cost OR v_letter IS NULL THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
                               s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;

  SELECT array_agg(g.i) INTO v_positions
  FROM generate_series(0, length(v_phrase) - 1) g(i)
  WHERE substr(v_phrase, g.i + 1, 1) = v_letter;

  s.bankroll := s.bankroll - v_cost;
  s.revealed_positions := ARRAY(SELECT DISTINCT unnest(s.revealed_positions || v_positions) ORDER BY 1);

  UPDATE public.daily_sessions SET
    bankroll = s.bankroll, revealed_positions = s.revealed_positions, updated_at = NOW()
  WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;

  RETURN public._daily_resolve_and_return(v_uid, v_phrase, v_cat, v_sub);
END;
$$;

-- Submit a full guess. p_guess maps position (text key) -> guessed letter, for
-- every currently-unrevealed non-space position. Server reveals only correct ones.
-- Daily wager is 0, so bankroll is unchanged; a wrong/partial guess costs one guess.
CREATE OR REPLACE FUNCTION public.daily_submit_guess(p_guess JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID := auth.uid();
  s public.daily_sessions;
  v_phrase TEXT; v_cat TEXT; v_sub TEXT;
  v_editable INT[];
  v_correct INT[] := '{}';
  v_all_correct BOOLEAN := true;
  pos INT;
  v_guess_char TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_submit_guess: not authenticated'; END IF;

  SELECT * INTO s FROM public.daily_sessions
  WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'daily_submit_guess: no active session'; END IF;

  SELECT upper(phrase), category, COALESCE(subcategory, '')
  INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;

  IF s.state <> 'active' OR s.guesses_remaining <= 0 THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
                               s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;

  -- The set of positions the player must fill.
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable
  FROM generate_series(0, length(v_phrase) - 1) g(i)
  WHERE substr(v_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions));

  -- Require a complete guess (a value for every editable position); else no-op.
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable, 1) THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
                               s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;

  FOREACH pos IN ARRAY v_editable LOOP
    v_guess_char := upper(p_guess ->> pos::text);
    IF v_guess_char IS NULL THEN
      v_all_correct := false;            -- missing slot
    ELSIF v_guess_char = substr(v_phrase, pos + 1, 1) THEN
      v_correct := v_correct || pos;     -- correct: reveal it
    ELSE
      v_all_correct := false;            -- wrong
    END IF;
  END LOOP;

  IF array_length(v_correct, 1) > 0 THEN
    s.revealed_positions := ARRAY(SELECT DISTINCT unnest(s.revealed_positions || v_correct) ORDER BY 1);
  END IF;

  -- A non-winning guess consumes one guess.
  IF NOT v_all_correct THEN
    s.guesses_remaining := GREATEST(0, s.guesses_remaining - 1);
  END IF;

  UPDATE public.daily_sessions SET
    revealed_positions = s.revealed_positions, guesses_remaining = s.guesses_remaining, updated_at = NOW()
  WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;

  RETURN public._daily_resolve_and_return(v_uid, v_phrase, v_cat, v_sub);
END;
$$;

-- ---- Grants: signed-in users may call the public RPCs only -----------------
GRANT EXECUTE ON FUNCTION public.daily_start()                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.daily_buy_letter(TEXT)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.daily_reveal()                TO authenticated;
GRANT EXECUTE ON FUNCTION public.daily_submit_guess(JSONB)     TO authenticated;
-- Internal helpers are not granted to clients (called only via SECURITY DEFINER RPCs).
REVOKE EXECUTE ON FUNCTION public._todays_puzzle_id()                         FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._finalize_daily(UUID, BOOLEAN, INT)         FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._daily_resolve_and_return(UUID, TEXT, TEXT, TEXT) FROM anon, authenticated;
