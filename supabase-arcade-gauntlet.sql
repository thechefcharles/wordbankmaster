-- ============================================================
-- WordBank V2 Phase 4a: Arcade Press-Your-Luck gauntlet (server engine)
-- Run AFTER the daily server-authoritative + powerups files (reuses letter_cost,
-- _daily_board, _todays_puzzle_id).
-- ============================================================
--
-- Shared daily ladder: a deterministic ordering of the puzzle pool (excluding
-- today's Daily) that's identical for everyone. Climb it; each solve auto-banks
-- leftover × multiplier; the multiplier rises on clean streaks and resets on a
-- bust; busting lets you retry the same puzzle. Server-authoritative.

CREATE TABLE IF NOT EXISTS public.arcade_runs (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  run_date DATE NOT NULL DEFAULT CURRENT_DATE,
  position INT NOT NULL DEFAULT 0,
  puzzle_id UUID NOT NULL REFERENCES public.daily_puzzles(id) ON DELETE RESTRICT,
  bankroll INT NOT NULL DEFAULT 1000,
  guesses_remaining INT NOT NULL DEFAULT 3,
  revealed_positions INT[] NOT NULL DEFAULT '{}',
  incorrect_letters TEXT[] NOT NULL DEFAULT '{}',
  active_powerups TEXT[] NOT NULL DEFAULT '{}',
  multiplier_x100 INT NOT NULL DEFAULT 100,
  banked INT NOT NULL DEFAULT 0,
  furthest INT NOT NULL DEFAULT 0,
  last_gain INT NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'active',   -- active | solved | busted | complete
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, run_date)
);
ALTER TABLE public.arcade_runs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "read own arcade run" ON public.arcade_runs;
CREATE POLICY "read own arcade run" ON public.arcade_runs FOR SELECT USING (auth.uid() = user_id);
REVOKE INSERT, UPDATE, DELETE ON public.arcade_runs FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public._arcade_ladder_size()
RETURNS INT LANGUAGE sql STABLE SECURITY DEFINER AS $fn$
  SELECT count(*)::INT FROM public.daily_puzzles
  WHERE id NOT IN (SELECT puzzle_id FROM public.daily_puzzle_schedule WHERE scheduled_date = CURRENT_DATE);
$fn$;

CREATE OR REPLACE FUNCTION public._arcade_puzzle_at(p_position INT)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER AS $fn$
  SELECT id FROM (
    SELECT id, (row_number() OVER (ORDER BY md5(CURRENT_DATE::text || id::text)) - 1) AS pos
    FROM public.daily_puzzles
    WHERE id NOT IN (SELECT puzzle_id FROM public.daily_puzzle_schedule WHERE scheduled_date = CURRENT_DATE)
  ) t WHERE t.pos = p_position;
$fn$;

CREATE OR REPLACE FUNCTION public._arcade_response(p_uid UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE r public.arcade_runs; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_bstate TEXT;
BEGIN
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = p_uid AND run_date = CURRENT_DATE;
  SELECT upper(phrase), category, COALESCE(subcategory, '')
  INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = r.puzzle_id;
  v_bstate := CASE r.state WHEN 'solved' THEN 'won' WHEN 'complete' THEN 'won' WHEN 'busted' THEN 'lost' ELSE 'active' END;
  RETURN jsonb_build_object(
    'board', public._daily_board(v_phrase, v_bstate, r.bankroll, r.guesses_remaining, r.revealed_positions, r.incorrect_letters, v_cat, v_sub),
    'run', jsonb_build_object('state', r.state, 'banked', r.banked, 'multiplier', r.multiplier_x100,
                              'position', r.position, 'total', public._arcade_ladder_size(),
                              'furthest', r.furthest, 'last_gain', r.last_gain)
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public._arcade_resolve(p_uid UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE r public.arcade_runs; v_phrase TEXT; v_won BOOLEAN; v_lost BOOLEAN; v_gain INT;
BEGIN
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = p_uid AND run_date = CURRENT_DATE;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = r.puzzle_id;
  v_won := NOT EXISTS (
    SELECT 1 FROM generate_series(0, length(v_phrase) - 1) g(i)
    WHERE substr(v_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions)));
  v_lost := (r.bankroll < 30) AND NOT v_won;
  IF v_won THEN
    v_gain := ROUND(r.bankroll * r.multiplier_x100 / 100.0)::INT;
    UPDATE public.arcade_runs SET state = 'solved', banked = banked + v_gain, last_gain = v_gain,
      multiplier_x100 = LEAST(multiplier_x100 + 25, 500),
      furthest = GREATEST(furthest, position + 1), updated_at = NOW()
    WHERE user_id = p_uid AND run_date = CURRENT_DATE;
  ELSIF v_lost THEN
    UPDATE public.arcade_runs SET state = 'busted', multiplier_x100 = 100, updated_at = NOW()
    WHERE user_id = p_uid AND run_date = CURRENT_DATE;
  END IF;
  RETURN public._arcade_response(p_uid);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.arcade_start()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_pid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_start: not authenticated'; END IF;
  PERFORM public._todays_puzzle_id();  -- ensure today's Daily is assigned so the ladder excludes it
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  IF NOT FOUND THEN
    v_pid := public._arcade_puzzle_at(0);
    IF v_pid IS NULL THEN RAISE EXCEPTION 'arcade_start: no puzzles available'; END IF;
    INSERT INTO public.arcade_runs (user_id, run_date, position, puzzle_id) VALUES (v_uid, CURRENT_DATE, 0, v_pid);
  END IF;
  RETURN public._arcade_response(v_uid);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.arcade_start() TO authenticated;

CREATE OR REPLACE FUNCTION public.arcade_next()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_next UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_next: not authenticated'; END IF;
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'arcade_next: no run'; END IF;
  IF r.state = 'solved' THEN
    IF r.position + 1 >= public._arcade_ladder_size() THEN
      UPDATE public.arcade_runs SET state = 'complete', updated_at = NOW() WHERE user_id = v_uid AND run_date = CURRENT_DATE;
    ELSE
      v_next := public._arcade_puzzle_at(r.position + 1);
      UPDATE public.arcade_runs SET position = position + 1, puzzle_id = v_next, bankroll = 1000,
        guesses_remaining = 3, revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}',
        last_gain = 0, state = 'active', updated_at = NOW() WHERE user_id = v_uid AND run_date = CURRENT_DATE;
    END IF;
  ELSIF r.state = 'busted' THEN
    UPDATE public.arcade_runs SET bankroll = 1000, guesses_remaining = 3, revealed_positions = '{}',
      incorrect_letters = '{}', active_powerups = '{}', state = 'active', updated_at = NOW()
    WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  END IF;
  RETURN public._arcade_response(v_uid);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.arcade_next() TO authenticated;

CREATE OR REPLACE FUNCTION public.arcade_buy_letter(p_letter TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_phrase TEXT; v_letter TEXT; v_cost INT; v_positions INT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_buy_letter: not authenticated'; END IF;
  v_letter := upper(p_letter); v_cost := public.letter_cost(v_letter);
  IF v_cost IS NULL THEN RAISE EXCEPTION 'arcade_buy_letter: invalid letter'; END IF;
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'arcade_buy_letter: no run'; END IF;
  IF r.state <> 'active' THEN RETURN public._arcade_response(v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = r.puzzle_id;
  IF v_letter = ANY(r.incorrect_letters) OR r.bankroll < v_cost THEN RETURN public._arcade_response(v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase) - 1) g(i)
  WHERE substr(v_phrase, g.i + 1, 1) = v_letter;
  IF v_positions IS NOT NULL AND v_positions <@ r.revealed_positions THEN RETURN public._arcade_response(v_uid); END IF;
  r.bankroll := r.bankroll - v_cost;
  IF v_positions IS NULL THEN r.incorrect_letters := array_append(r.incorrect_letters, v_letter);
  ELSE r.revealed_positions := ARRAY(SELECT DISTINCT unnest(r.revealed_positions || v_positions) ORDER BY 1); END IF;
  UPDATE public.arcade_runs SET bankroll = r.bankroll, incorrect_letters = r.incorrect_letters,
    revealed_positions = r.revealed_positions, updated_at = NOW() WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  RETURN public._arcade_resolve(v_uid);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.arcade_buy_letter(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.arcade_reveal()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_phrase TEXT; v_letter TEXT; v_positions INT[]; v_cost INT := 150;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_reveal: not authenticated'; END IF;
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'arcade_reveal: no run'; END IF;
  IF r.state <> 'active' THEN RETURN public._arcade_response(v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = r.puzzle_id;
  SELECT t.ch INTO v_letter FROM (
    SELECT substr(v_phrase, g.i + 1, 1) AS ch, count(*) AS c
    FROM generate_series(0, length(v_phrase) - 1) g(i)
    WHERE substr(v_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions))
    GROUP BY substr(v_phrase, g.i + 1, 1) ORDER BY c DESC, ch LIMIT 1) t;
  IF r.bankroll < v_cost OR v_letter IS NULL THEN RETURN public._arcade_response(v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase) - 1) g(i)
  WHERE substr(v_phrase, g.i + 1, 1) = v_letter;
  r.bankroll := r.bankroll - v_cost;
  r.revealed_positions := ARRAY(SELECT DISTINCT unnest(r.revealed_positions || v_positions) ORDER BY 1);
  UPDATE public.arcade_runs SET bankroll = r.bankroll, revealed_positions = r.revealed_positions, updated_at = NOW()
  WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  RETURN public._arcade_resolve(v_uid);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.arcade_reveal() TO authenticated;

CREATE OR REPLACE FUNCTION public.arcade_submit_guess(p_guess JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_phrase TEXT;
  v_editable INT[]; v_correct INT[] := '{}'; v_all_correct BOOLEAN := true; pos INT; v_guess_char TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_submit_guess: not authenticated'; END IF;
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'arcade_submit_guess: no run'; END IF;
  IF r.state <> 'active' OR r.guesses_remaining <= 0 THEN RETURN public._arcade_response(v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = r.puzzle_id;
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable FROM generate_series(0, length(v_phrase) - 1) g(i)
  WHERE substr(v_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions));
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable, 1) THEN
    RETURN public._arcade_response(v_uid);
  END IF;
  FOREACH pos IN ARRAY v_editable LOOP
    v_guess_char := upper(p_guess ->> pos::text);
    IF v_guess_char IS NULL THEN v_all_correct := false;
    ELSIF v_guess_char = substr(v_phrase, pos + 1, 1) THEN v_correct := v_correct || pos;
    ELSE v_all_correct := false; END IF;
  END LOOP;
  IF array_length(v_correct, 1) > 0 THEN
    r.revealed_positions := ARRAY(SELECT DISTINCT unnest(r.revealed_positions || v_correct) ORDER BY 1);
  END IF;
  IF NOT v_all_correct THEN r.guesses_remaining := GREATEST(0, r.guesses_remaining - 1); END IF;
  UPDATE public.arcade_runs SET revealed_positions = r.revealed_positions,
    guesses_remaining = r.guesses_remaining, updated_at = NOW() WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  RETURN public._arcade_resolve(v_uid);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.arcade_submit_guess(JSONB) TO authenticated;
