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

  -- Both a solve and a bust move on to the next rung (you never replay a
  -- puzzle whose answer you've already seen). The only difference is the
  -- multiplier: grown on solve, reset to x1 on bust in _arcade_resolve.
  IF r.state IN ('solved', 'busted') THEN
    IF r.position + 1 >= public._arcade_ladder_size() THEN
      UPDATE public.arcade_runs SET state = 'complete', updated_at = NOW()
      WHERE user_id = v_uid AND run_date = CURRENT_DATE;
    ELSE
      v_next := public._arcade_puzzle_at(r.position + 1);
      UPDATE public.arcade_runs SET position = position + 1, puzzle_id = v_next, bankroll = 1000,
        guesses_remaining = 3, revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}',
        last_gain = 0, state = 'active', updated_at = NOW()
      WHERE user_id = v_uid AND run_date = CURRENT_DATE;
    END IF;
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

-- ============================================================
-- Phase 4c: Arcade gauntlet leaderboard (best banked run + furthest reached)
-- Ranks each user by their best banked run over the period window, tie-break
-- on how far they climbed. 'daily' = today; weekly/monthly/yearly/all windows.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_arcade_gauntlet_leaderboard(p_period text DEFAULT 'daily')
  RETURNS TABLE(rank bigint, user_id uuid, display_name text, banked integer, furthest integer, total integer)
  LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_start DATE; v_end DATE;
BEGIN
  CASE p_period
    WHEN 'weekly' THEN
      v_start := date_trunc('week', CURRENT_DATE)::DATE + 1; v_end := v_start + 7;
    WHEN 'monthly' THEN
      v_start := date_trunc('month', CURRENT_DATE)::DATE; v_end := (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::DATE;
    WHEN 'yearly' THEN
      v_start := date_trunc('year', CURRENT_DATE)::DATE; v_end := (date_trunc('year', CURRENT_DATE) + INTERVAL '1 year')::DATE;
    WHEN 'all' THEN
      v_start := DATE '1970-01-01'; v_end := DATE '9999-12-31';
    ELSE  -- daily / today
      v_start := CURRENT_DATE; v_end := CURRENT_DATE + 1;
  END CASE;

  RETURN QUERY
  WITH agg AS (
    SELECT ar.user_id, MAX(ar.banked)::INT AS banked, MAX(ar.furthest)::INT AS furthest
    FROM public.arcade_runs ar
    WHERE ar.run_date >= v_start AND ar.run_date < v_end
    GROUP BY ar.user_id
  ),
  base AS (
    SELECT a.user_id,
      COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email', '@', 1), 'Player')::TEXT AS display_name,
      a.banked, a.furthest
    FROM agg a LEFT JOIN auth.users au ON au.id = a.user_id
  )
  SELECT ROW_NUMBER() OVER (ORDER BY base.banked DESC, base.furthest DESC)::BIGINT AS rank,
    base.user_id, base.display_name, base.banked, base.furthest, public._arcade_ladder_size()
  FROM base
  ORDER BY base.banked DESC, base.furthest DESC;
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.get_arcade_gauntlet_leaderboard(text) TO authenticated;

-- ============================================================
-- Phase 6b: Arcade per-run roguelike power-ups.
-- Start each run empty, EARN one power-up on every solve (deterministic
-- schedule), SPEND them during the run. inventory = earned {id:count};
-- active_powerups = effects on the CURRENT puzzle. Redefines the response /
-- resolve / buy / guess / next functions and adds arcade_use_powerup.
-- ============================================================

ALTER TABLE public.arcade_runs ADD COLUMN IF NOT EXISTS inventory JSONB NOT NULL DEFAULT '{}';
ALTER TABLE public.arcade_runs ADD COLUMN IF NOT EXISTS last_earn TEXT;

CREATE OR REPLACE FUNCTION public._arcade_earn_for_solve(p_position INT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $fn$
  SELECT (ARRAY['free_reveal','extra_bank','multiplier_boost','discount','shield',
                'double_payout','extra_try','vowel_vision','skip','insurance'])[1 + (p_position % 10)];
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
                              'furthest', r.furthest, 'last_gain', r.last_gain,
                              'inventory', r.inventory, 'active', to_jsonb(r.active_powerups), 'last_earn', r.last_earn)
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public._arcade_resolve(p_uid UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE r public.arcade_runs; v_phrase TEXT; v_won BOOLEAN; v_lost BOOLEAN; v_gain INT; v_earn TEXT; v_inv JSONB;
BEGIN
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = p_uid AND run_date = CURRENT_DATE;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = r.puzzle_id;
  v_won := NOT EXISTS (
    SELECT 1 FROM generate_series(0, length(v_phrase) - 1) g(i)
    WHERE substr(v_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions)));
  v_lost := (r.bankroll < 30) AND NOT v_won;
  IF v_won THEN
    v_gain := ROUND(r.bankroll * r.multiplier_x100 / 100.0)::INT;
    IF 'double_payout' = ANY(r.active_powerups) THEN v_gain := v_gain * 2; END IF;
    v_earn := public._arcade_earn_for_solve(r.position);
    v_inv := jsonb_set(COALESCE(r.inventory, '{}'::jsonb), ARRAY[v_earn],
                       to_jsonb(COALESCE((r.inventory ->> v_earn)::int, 0) + 1), true);
    UPDATE public.arcade_runs SET state = 'solved', banked = banked + v_gain, last_gain = v_gain,
      multiplier_x100 = LEAST(multiplier_x100 + 25, 500),
      furthest = GREATEST(furthest, position + 1), inventory = v_inv, last_earn = v_earn, updated_at = NOW()
    WHERE user_id = p_uid AND run_date = CURRENT_DATE;
  ELSIF v_lost THEN
    IF 'shield' = ANY(r.active_powerups) THEN
      UPDATE public.arcade_runs SET state = 'busted', last_earn = NULL, updated_at = NOW()
      WHERE user_id = p_uid AND run_date = CURRENT_DATE;
    ELSE
      UPDATE public.arcade_runs SET state = 'busted', multiplier_x100 = 100, last_earn = NULL, updated_at = NOW()
      WHERE user_id = p_uid AND run_date = CURRENT_DATE;
    END IF;
  END IF;
  RETURN public._arcade_response(p_uid);
END;
$fn$;

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
  IF 'discount' = ANY(r.active_powerups) THEN v_cost := CEIL(v_cost * 0.75)::INT; END IF;
  IF 'vowel_vision' = ANY(r.active_powerups) AND v_letter IN ('A','E','I','O','U') THEN v_cost := CEIL(v_cost * 0.5)::INT; END IF;
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
  IF NOT v_all_correct THEN
    IF 'insurance' = ANY(r.active_powerups) THEN r.active_powerups := array_remove(r.active_powerups, 'insurance');
    ELSE r.guesses_remaining := GREATEST(0, r.guesses_remaining - 1); END IF;
  END IF;
  UPDATE public.arcade_runs SET revealed_positions = r.revealed_positions,
    guesses_remaining = r.guesses_remaining, active_powerups = r.active_powerups, updated_at = NOW()
  WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  RETURN public._arcade_resolve(v_uid);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.arcade_submit_guess(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.arcade_next()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_next UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_next: not authenticated'; END IF;
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'arcade_next: no run'; END IF;
  IF r.state IN ('solved', 'busted') THEN
    IF r.position + 1 >= public._arcade_ladder_size() THEN
      UPDATE public.arcade_runs SET state = 'complete', last_earn = NULL, updated_at = NOW()
      WHERE user_id = v_uid AND run_date = CURRENT_DATE;
    ELSE
      v_next := public._arcade_puzzle_at(r.position + 1);
      UPDATE public.arcade_runs SET position = position + 1, puzzle_id = v_next, bankroll = 1000,
        guesses_remaining = 3, revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}',
        last_gain = 0, last_earn = NULL, state = 'active', updated_at = NOW()
      WHERE user_id = v_uid AND run_date = CURRENT_DATE;
    END IF;
  END IF;
  RETURN public._arcade_response(v_uid);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.arcade_next() TO authenticated;

-- Spend an earned power-up during the run.
CREATE OR REPLACE FUNCTION public.arcade_use_powerup(p_powerup TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_have INT; v_phrase TEXT; v_letter TEXT;
  v_positions INT[]; v_next UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_use_powerup: not authenticated'; END IF;
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'arcade_use_powerup: no run'; END IF;
  IF r.state <> 'active' THEN RETURN public._arcade_response(v_uid); END IF;
  v_have := COALESCE((r.inventory ->> p_powerup)::int, 0);
  IF v_have <= 0 THEN RETURN public._arcade_response(v_uid); END IF;
  IF p_powerup IN ('discount','vowel_vision','insurance','double_payout','shield')
     AND p_powerup = ANY(r.active_powerups) THEN
    RETURN public._arcade_response(v_uid);
  END IF;
  r.inventory := jsonb_set(r.inventory, ARRAY[p_powerup], to_jsonb(v_have - 1), true);

  IF p_powerup = 'extra_bank' THEN
    r.bankroll := r.bankroll + 250;
  ELSIF p_powerup = 'multiplier_boost' THEN
    r.multiplier_x100 := LEAST(r.multiplier_x100 + 50, 500);
  ELSIF p_powerup = 'extra_try' THEN
    r.guesses_remaining := r.guesses_remaining + 1;
  ELSIF p_powerup IN ('discount','vowel_vision','insurance','double_payout','shield') THEN
    r.active_powerups := r.active_powerups || p_powerup;
  ELSIF p_powerup = 'free_reveal' THEN
    SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = r.puzzle_id;
    SELECT t.ch INTO v_letter FROM (
      SELECT substr(v_phrase, g.i + 1, 1) AS ch, count(*) AS c
      FROM generate_series(0, length(v_phrase) - 1) g(i)
      WHERE substr(v_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions))
      GROUP BY substr(v_phrase, g.i + 1, 1) ORDER BY c DESC, ch LIMIT 1) t;
    IF v_letter IS NOT NULL THEN
      SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase) - 1) g(i)
      WHERE substr(v_phrase, g.i + 1, 1) = v_letter;
      r.revealed_positions := ARRAY(SELECT DISTINCT unnest(r.revealed_positions || v_positions) ORDER BY 1);
    END IF;
  ELSIF p_powerup = 'skip' THEN
    IF r.position + 1 >= public._arcade_ladder_size() THEN
      UPDATE public.arcade_runs SET inventory = r.inventory, state = 'complete', updated_at = NOW()
      WHERE user_id = v_uid AND run_date = CURRENT_DATE;
      RETURN public._arcade_response(v_uid);
    END IF;
    v_next := public._arcade_puzzle_at(r.position + 1);
    UPDATE public.arcade_runs SET position = position + 1, puzzle_id = v_next, bankroll = 1000,
      guesses_remaining = 3, revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}',
      last_gain = 0, last_earn = NULL, inventory = r.inventory, state = 'active', updated_at = NOW()
    WHERE user_id = v_uid AND run_date = CURRENT_DATE;
    RETURN public._arcade_response(v_uid);
  ELSE
    RETURN public._arcade_response(v_uid);
  END IF;

  UPDATE public.arcade_runs SET bankroll = r.bankroll, multiplier_x100 = r.multiplier_x100,
    guesses_remaining = r.guesses_remaining, active_powerups = r.active_powerups,
    revealed_positions = r.revealed_positions, inventory = r.inventory, updated_at = NOW()
  WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  RETURN public._arcade_resolve(v_uid);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.arcade_use_powerup(TEXT) TO authenticated;

-- ============================================================
-- Endless arcade: no "gauntlet cleared" cap. The ladder wraps once the library
-- is exhausted (position % size), so a run keeps going — how far you climb is
-- the score. Redefines _arcade_puzzle_at (wrap), arcade_next + skip (never
-- 'complete'). Seeding more puzzles pushes the loop point far out.
-- ============================================================

CREATE OR REPLACE FUNCTION public._arcade_puzzle_at(p_position INT)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER AS $fn$
  SELECT id FROM (
    SELECT id, (row_number() OVER (ORDER BY md5(CURRENT_DATE::text || id::text)) - 1) AS pos
    FROM public.daily_puzzles
    WHERE id NOT IN (SELECT puzzle_id FROM public.daily_puzzle_schedule WHERE scheduled_date = CURRENT_DATE)
  ) t
  WHERE t.pos = (p_position % NULLIF(public._arcade_ladder_size(), 0));
$fn$;

CREATE OR REPLACE FUNCTION public.arcade_next()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_next UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_next: not authenticated'; END IF;
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'arcade_next: no run'; END IF;
  IF r.state IN ('solved', 'busted') THEN
    v_next := public._arcade_puzzle_at(r.position + 1);
    UPDATE public.arcade_runs SET position = position + 1, puzzle_id = v_next, bankroll = 1000,
      guesses_remaining = 3, revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}',
      last_gain = 0, last_earn = NULL, state = 'active', updated_at = NOW()
    WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  END IF;
  RETURN public._arcade_response(v_uid);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.arcade_next() TO authenticated;

CREATE OR REPLACE FUNCTION public.arcade_use_powerup(p_powerup TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_have INT; v_phrase TEXT; v_letter TEXT;
  v_positions INT[]; v_next UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_use_powerup: not authenticated'; END IF;
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'arcade_use_powerup: no run'; END IF;
  IF r.state <> 'active' THEN RETURN public._arcade_response(v_uid); END IF;
  v_have := COALESCE((r.inventory ->> p_powerup)::int, 0);
  IF v_have <= 0 THEN RETURN public._arcade_response(v_uid); END IF;
  IF p_powerup IN ('discount','vowel_vision','insurance','double_payout','shield')
     AND p_powerup = ANY(r.active_powerups) THEN
    RETURN public._arcade_response(v_uid);
  END IF;
  r.inventory := jsonb_set(r.inventory, ARRAY[p_powerup], to_jsonb(v_have - 1), true);

  IF p_powerup = 'extra_bank' THEN
    r.bankroll := r.bankroll + 250;
  ELSIF p_powerup = 'multiplier_boost' THEN
    r.multiplier_x100 := LEAST(r.multiplier_x100 + 50, 500);
  ELSIF p_powerup = 'extra_try' THEN
    r.guesses_remaining := r.guesses_remaining + 1;
  ELSIF p_powerup IN ('discount','vowel_vision','insurance','double_payout','shield') THEN
    r.active_powerups := r.active_powerups || p_powerup;
  ELSIF p_powerup = 'free_reveal' THEN
    SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = r.puzzle_id;
    SELECT t.ch INTO v_letter FROM (
      SELECT substr(v_phrase, g.i + 1, 1) AS ch, count(*) AS c
      FROM generate_series(0, length(v_phrase) - 1) g(i)
      WHERE substr(v_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions))
      GROUP BY substr(v_phrase, g.i + 1, 1) ORDER BY c DESC, ch LIMIT 1) t;
    IF v_letter IS NOT NULL THEN
      SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase) - 1) g(i)
      WHERE substr(v_phrase, g.i + 1, 1) = v_letter;
      r.revealed_positions := ARRAY(SELECT DISTINCT unnest(r.revealed_positions || v_positions) ORDER BY 1);
    END IF;
  ELSIF p_powerup = 'skip' THEN
    v_next := public._arcade_puzzle_at(r.position + 1);
    UPDATE public.arcade_runs SET position = position + 1, puzzle_id = v_next, bankroll = 1000,
      guesses_remaining = 3, revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}',
      last_gain = 0, last_earn = NULL, inventory = r.inventory, state = 'active', updated_at = NOW()
    WHERE user_id = v_uid AND run_date = CURRENT_DATE;
    RETURN public._arcade_response(v_uid);
  ELSE
    RETURN public._arcade_response(v_uid);
  END IF;

  UPDATE public.arcade_runs SET bankroll = r.bankroll, multiplier_x100 = r.multiplier_x100,
    guesses_remaining = r.guesses_remaining, active_powerups = r.active_powerups,
    revealed_positions = r.revealed_positions, inventory = r.inventory, updated_at = NOW()
  WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  RETURN public._arcade_resolve(v_uid);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.arcade_use_powerup(TEXT) TO authenticated;

-- ============================================================
-- REDESIGN Phase 1: rolling-bankroll survival (supersedes the gauntlet economy
-- above). bankroll = rolling balance (carries over), multiplier_x100 = streak,
-- banked = PEAK bankroll, guesses_remaining = run-level pool (start 5, carries).
-- Solve pays $500 × streak; wrong guess resets streak; run ends broke + no
-- guesses. Power-up earning is removed here (Phase 2 re-adds the 3 feat-based
-- earns); the category-solve badge hook stays.
-- ============================================================

CREATE OR REPLACE FUNCTION public._arcade_resolve(p_uid UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE r public.arcade_runs; v_phrase TEXT; v_cat TEXT; v_won BOOLEAN; v_payout INT; v_min_needed INT;
BEGIN
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = p_uid AND run_date = CURRENT_DATE;
  IF r.state <> 'active' THEN RETURN public._arcade_response(p_uid); END IF;  -- never re-resolve
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = r.puzzle_id;
  v_won := NOT EXISTS (
    SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions)));
  IF v_won THEN
    v_payout := ROUND(500 * r.multiplier_x100 / 100.0)::INT;
    UPDATE public.arcade_runs SET state = 'solved', bankroll = r.bankroll + v_payout,
      banked = GREATEST(r.banked, r.bankroll + v_payout), last_gain = v_payout,
      multiplier_x100 = LEAST(r.multiplier_x100 + 25, 500), furthest = GREATEST(r.furthest, r.position + 1), updated_at = NOW()
    WHERE user_id = p_uid AND run_date = CURRENT_DATE;
    PERFORM public._record_category_solve(p_uid, v_cat);
  ELSE
    SELECT min(public.letter_cost(t.ch)) INTO v_min_needed FROM (
      SELECT DISTINCT substr(v_phrase, g.i+1, 1) AS ch
      FROM generate_series(0, length(v_phrase)-1) g(i)
      WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions))
    ) t;
    IF r.guesses_remaining <= 0 AND (v_min_needed IS NULL OR r.bankroll < v_min_needed) THEN
      UPDATE public.arcade_runs SET state = 'over', last_gain = 0, updated_at = NOW()
      WHERE user_id = p_uid AND run_date = CURRENT_DATE;
    END IF;
  END IF;
  RETURN public._arcade_response(p_uid);
END; $fn$;

CREATE OR REPLACE FUNCTION public.arcade_start()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_pid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_start: not authenticated'; END IF;
  PERFORM public._todays_puzzle_id();
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  IF NOT FOUND THEN
    v_pid := public._arcade_puzzle_at(0);
    IF v_pid IS NULL THEN RAISE EXCEPTION 'arcade_start: no puzzles available'; END IF;
    INSERT INTO public.arcade_runs (user_id, run_date, position, puzzle_id, bankroll, banked, multiplier_x100, guesses_remaining, furthest, last_gain, state)
    VALUES (v_uid, CURRENT_DATE, 0, v_pid, 1500, 1500, 100, 5, 0, 0, 'active');
  ELSIF r.state = 'over' THEN
    v_pid := public._arcade_puzzle_at(0);
    UPDATE public.arcade_runs SET position = 0, puzzle_id = v_pid, bankroll = 1500, multiplier_x100 = 100,
      guesses_remaining = 5, last_gain = 0, revealed_positions = '{}', incorrect_letters = '{}',
      active_powerups = '{}', inventory = '{}', last_earn = NULL, state = 'active', updated_at = NOW()
    WHERE user_id = v_uid AND run_date = CURRENT_DATE;  -- banked + furthest kept (day bests)
  END IF;
  RETURN public._arcade_response(v_uid);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.arcade_start() TO authenticated;

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
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable FROM generate_series(0, length(v_phrase)-1) g(i)
  WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions));
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable, 1) THEN
    RETURN public._arcade_response(v_uid);
  END IF;
  FOREACH pos IN ARRAY v_editable LOOP
    v_guess_char := upper(p_guess ->> pos::text);
    IF v_guess_char IS NULL THEN v_all_correct := false;
    ELSIF v_guess_char = substr(v_phrase, pos+1, 1) THEN v_correct := v_correct || pos;
    ELSE v_all_correct := false; END IF;
  END LOOP;
  IF array_length(v_correct, 1) > 0 THEN
    r.revealed_positions := ARRAY(SELECT DISTINCT unnest(r.revealed_positions || v_correct) ORDER BY 1);
  END IF;
  IF NOT v_all_correct THEN
    r.guesses_remaining := GREATEST(0, r.guesses_remaining - 1);
    r.multiplier_x100 := 100;  -- wrong guess resets the streak
  END IF;
  UPDATE public.arcade_runs SET revealed_positions = r.revealed_positions,
    guesses_remaining = r.guesses_remaining, multiplier_x100 = r.multiplier_x100, updated_at = NOW()
  WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  RETURN public._arcade_resolve(v_uid);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.arcade_submit_guess(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.arcade_next()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_next UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_next: not authenticated'; END IF;
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'arcade_next: no run'; END IF;
  IF r.state = 'solved' THEN
    -- Bankroll, streak multiplier AND guess pool carry over (no reset).
    v_next := public._arcade_puzzle_at(r.position + 1);
    UPDATE public.arcade_runs SET position = position + 1, puzzle_id = v_next,
      revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}',
      last_gain = 0, last_earn = NULL, state = 'active', updated_at = NOW()
    WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  END IF;
  RETURN public._arcade_response(v_uid);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.arcade_next() TO authenticated;

-- ============================================================
-- Arcade Phase 2: earned power-ups + Hot Hand (later defs win).
-- 3 power-ups, each earned by a special feat (most solves earn nothing):
--   ⚡ Multiplier Boost ← Blind Solve (bought 0 letters, no Reveal)
--   💎 Double Payout    ← Consonant King (flawless, ≥1 letter, 0 vowels, no Reveal)
--   ❤️ Extra Guess      ← Hot Streak (3 solves in a row, no wrong guess)
-- 💰 Hot Hand: +$250 cash per 3 correct letters bought in a row (not a power-up).
-- Per-puzzle counters reset on advance; clean_streak is run-level.
-- ============================================================
ALTER TABLE public.arcade_runs ADD COLUMN IF NOT EXISTS p_buys INT NOT NULL DEFAULT 0;
ALTER TABLE public.arcade_runs ADD COLUMN IF NOT EXISTS p_vowels INT NOT NULL DEFAULT 0;
ALTER TABLE public.arcade_runs ADD COLUMN IF NOT EXISTS p_reveals INT NOT NULL DEFAULT 0;
ALTER TABLE public.arcade_runs ADD COLUMN IF NOT EXISTS p_wrong_guess BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.arcade_runs ADD COLUMN IF NOT EXISTS p_combo INT NOT NULL DEFAULT 0;
ALTER TABLE public.arcade_runs ADD COLUMN IF NOT EXISTS clean_streak INT NOT NULL DEFAULT 0;

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
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i)
  WHERE substr(v_phrase, g.i+1, 1) = v_letter;
  IF v_positions IS NOT NULL AND v_positions <@ r.revealed_positions THEN RETURN public._arcade_response(v_uid); END IF;
  r.bankroll := r.bankroll - v_cost;
  r.p_buys := r.p_buys + 1;
  IF v_letter IN ('A','E','I','O','U') THEN r.p_vowels := r.p_vowels + 1; END IF;
  IF v_positions IS NULL THEN
    r.incorrect_letters := array_append(r.incorrect_letters, v_letter);
    r.p_combo := 0;
  ELSE
    r.revealed_positions := ARRAY(SELECT DISTINCT unnest(r.revealed_positions || v_positions) ORDER BY 1);
    r.p_combo := r.p_combo + 1;
    IF r.p_combo % 3 = 0 THEN r.bankroll := r.bankroll + 250; END IF;  -- Hot Hand
  END IF;
  r.banked := GREATEST(r.banked, r.bankroll);
  UPDATE public.arcade_runs SET bankroll = r.bankroll, incorrect_letters = r.incorrect_letters,
    revealed_positions = r.revealed_positions, p_buys = r.p_buys, p_vowels = r.p_vowels,
    p_combo = r.p_combo, banked = r.banked, updated_at = NOW() WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  RETURN public._arcade_resolve(v_uid);
END; $fn$;
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
    SELECT substr(v_phrase, g.i+1, 1) AS ch, count(*) AS c FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions))
    GROUP BY substr(v_phrase, g.i+1, 1) ORDER BY c DESC, ch LIMIT 1) t;
  IF r.bankroll < v_cost OR v_letter IS NULL THEN RETURN public._arcade_response(v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i)
  WHERE substr(v_phrase, g.i+1, 1) = v_letter;
  UPDATE public.arcade_runs SET bankroll = r.bankroll - v_cost, p_reveals = r.p_reveals + 1, p_combo = 0,
    revealed_positions = ARRAY(SELECT DISTINCT unnest(r.revealed_positions || v_positions) ORDER BY 1), updated_at = NOW()
  WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  RETURN public._arcade_resolve(v_uid);
END; $fn$;
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
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable FROM generate_series(0, length(v_phrase)-1) g(i)
  WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions));
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable, 1) THEN
    RETURN public._arcade_response(v_uid);
  END IF;
  FOREACH pos IN ARRAY v_editable LOOP
    v_guess_char := upper(p_guess ->> pos::text);
    IF v_guess_char IS NULL THEN v_all_correct := false;
    ELSIF v_guess_char = substr(v_phrase, pos+1, 1) THEN v_correct := v_correct || pos;
    ELSE v_all_correct := false; END IF;
  END LOOP;
  IF array_length(v_correct, 1) > 0 THEN
    r.revealed_positions := ARRAY(SELECT DISTINCT unnest(r.revealed_positions || v_correct) ORDER BY 1);
  END IF;
  IF NOT v_all_correct THEN
    r.guesses_remaining := GREATEST(0, r.guesses_remaining - 1);
    r.multiplier_x100 := 100;
    r.p_wrong_guess := true;
  END IF;
  UPDATE public.arcade_runs SET revealed_positions = r.revealed_positions, guesses_remaining = r.guesses_remaining,
    multiplier_x100 = r.multiplier_x100, p_wrong_guess = r.p_wrong_guess, updated_at = NOW()
  WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  RETURN public._arcade_resolve(v_uid);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.arcade_submit_guess(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public._arcade_resolve(p_uid UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE r public.arcade_runs; v_phrase TEXT; v_cat TEXT; v_won BOOLEAN; v_payout INT; v_min_needed INT;
  v_streak INT; v_earn TEXT; v_flawless BOOLEAN; v_active TEXT[]; v_inv JSONB;
BEGIN
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = p_uid AND run_date = CURRENT_DATE;
  IF r.state <> 'active' THEN RETURN public._arcade_response(p_uid); END IF;
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = r.puzzle_id;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions)));
  IF v_won THEN
    v_payout := ROUND(500 * r.multiplier_x100 / 100.0)::INT;
    v_active := r.active_powerups;
    IF 'double_payout' = ANY(v_active) THEN v_payout := v_payout * 2; v_active := array_remove(v_active, 'double_payout'); END IF;
    IF r.p_wrong_guess THEN v_streak := 0; ELSE v_streak := r.clean_streak + 1; END IF;
    v_flawless := COALESCE(array_length(r.incorrect_letters, 1), 0) = 0 AND NOT r.p_wrong_guess;
    v_earn := NULL;
    IF r.p_buys = 0 AND r.p_reveals = 0 THEN v_earn := 'multiplier_boost';            -- Blind Solve
    ELSIF v_streak >= 3 THEN v_earn := 'extra_guess'; v_streak := 0;                    -- Hot Streak
    ELSIF v_flawless AND r.p_buys >= 1 AND r.p_vowels = 0 AND r.p_reveals = 0 THEN
      v_earn := 'double_payout';                                                       -- Consonant King
    END IF;
    v_inv := r.inventory;
    IF v_earn IS NOT NULL THEN
      v_inv := jsonb_set(COALESCE(v_inv, '{}'::jsonb), ARRAY[v_earn], to_jsonb(COALESCE((v_inv ->> v_earn)::int, 0) + 1), true);
    END IF;
    UPDATE public.arcade_runs SET state = 'solved', bankroll = r.bankroll + v_payout,
      banked = GREATEST(r.banked, r.bankroll + v_payout), last_gain = v_payout,
      multiplier_x100 = LEAST(r.multiplier_x100 + 25, 500), furthest = GREATEST(r.furthest, r.position + 1),
      clean_streak = v_streak, active_powerups = v_active, inventory = v_inv, last_earn = v_earn, updated_at = NOW()
    WHERE user_id = p_uid AND run_date = CURRENT_DATE;
    PERFORM public._record_category_solve(p_uid, v_cat);
  ELSE
    SELECT min(public.letter_cost(t.ch)) INTO v_min_needed FROM (
      SELECT DISTINCT substr(v_phrase, g.i+1, 1) AS ch FROM generate_series(0, length(v_phrase)-1) g(i)
      WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions))) t;
    IF r.guesses_remaining <= 0 AND (v_min_needed IS NULL OR r.bankroll < v_min_needed) THEN
      UPDATE public.arcade_runs SET state = 'over', last_gain = 0, updated_at = NOW()
      WHERE user_id = p_uid AND run_date = CURRENT_DATE;
    END IF;
  END IF;
  RETURN public._arcade_response(p_uid);
END; $fn$;

CREATE OR REPLACE FUNCTION public.arcade_next()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_next UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_next: not authenticated'; END IF;
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'arcade_next: no run'; END IF;
  IF r.state = 'solved' THEN
    v_next := public._arcade_puzzle_at(r.position + 1);
    UPDATE public.arcade_runs SET position = position + 1, puzzle_id = v_next,
      revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}',
      p_buys = 0, p_vowels = 0, p_reveals = 0, p_wrong_guess = false, p_combo = 0,
      last_gain = 0, last_earn = NULL, state = 'active', updated_at = NOW()
    WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  END IF;
  RETURN public._arcade_response(v_uid);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.arcade_next() TO authenticated;

CREATE OR REPLACE FUNCTION public.arcade_use_powerup(p_powerup TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_have INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_use_powerup: not authenticated'; END IF;
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'arcade_use_powerup: no run'; END IF;
  IF r.state <> 'active' THEN RETURN public._arcade_response(v_uid); END IF;
  v_have := COALESCE((r.inventory ->> p_powerup)::int, 0);
  IF v_have <= 0 THEN RETURN public._arcade_response(v_uid); END IF;
  IF p_powerup = 'double_payout' AND 'double_payout' = ANY(r.active_powerups) THEN
    RETURN public._arcade_response(v_uid);
  END IF;
  r.inventory := jsonb_set(r.inventory, ARRAY[p_powerup], to_jsonb(v_have - 1), true);
  IF p_powerup = 'multiplier_boost' THEN
    r.multiplier_x100 := LEAST(r.multiplier_x100 + 50, 500);
  ELSIF p_powerup = 'extra_guess' THEN
    r.guesses_remaining := LEAST(r.guesses_remaining + 1, 8);
  ELSIF p_powerup = 'double_payout' THEN
    r.active_powerups := array_append(r.active_powerups, 'double_payout');
  ELSE
    RETURN public._arcade_response(v_uid);
  END IF;
  UPDATE public.arcade_runs SET multiplier_x100 = r.multiplier_x100, guesses_remaining = r.guesses_remaining,
    active_powerups = r.active_powerups, inventory = r.inventory, updated_at = NOW()
  WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  RETURN public._arcade_response(v_uid);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.arcade_use_powerup(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.arcade_start()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_uid UUID := auth.uid(); r public.arcade_runs; v_pid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'arcade_start: not authenticated'; END IF;
  PERFORM public._todays_puzzle_id();
  SELECT * INTO r FROM public.arcade_runs WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  IF NOT FOUND THEN
    v_pid := public._arcade_puzzle_at(0);
    IF v_pid IS NULL THEN RAISE EXCEPTION 'arcade_start: no puzzles available'; END IF;
    INSERT INTO public.arcade_runs (user_id, run_date, position, puzzle_id, bankroll, banked, multiplier_x100, guesses_remaining, furthest, last_gain, state)
    VALUES (v_uid, CURRENT_DATE, 0, v_pid, 1500, 1500, 100, 5, 0, 0, 'active');
  ELSIF r.state = 'over' THEN
    v_pid := public._arcade_puzzle_at(0);
    UPDATE public.arcade_runs SET position = 0, puzzle_id = v_pid, bankroll = 1500, multiplier_x100 = 100,
      guesses_remaining = 5, last_gain = 0, revealed_positions = '{}', incorrect_letters = '{}',
      active_powerups = '{}', inventory = '{}', last_earn = NULL, clean_streak = 0,
      p_buys = 0, p_vowels = 0, p_reveals = 0, p_wrong_guess = false, p_combo = 0,
      state = 'active', updated_at = NOW()
    WHERE user_id = v_uid AND run_date = CURRENT_DATE;
  END IF;
  RETURN public._arcade_response(v_uid);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.arcade_start() TO authenticated;
