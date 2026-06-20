-- ============================================================
-- WordBank V2 Phase 3b: pre-game power-ups (+$250 Start, Discount)
-- Run AFTER supabase-powerups.sql. Adds session-scoped active power-ups, a
-- pre-game selection entry point, the discount effect, and a random grant on win.
-- ============================================================

ALTER TABLE public.daily_sessions ADD COLUMN IF NOT EXISTS active_powerups TEXT[] NOT NULL DEFAULT '{}';

CREATE OR REPLACE FUNCTION public.daily_session_exists()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER AS $fn$
  SELECT EXISTS (SELECT 1 FROM public.daily_sessions WHERE user_id = auth.uid() AND puzzle_date = CURRENT_DATE);
$fn$;
GRANT EXECUTE ON FUNCTION public.daily_session_exists() TO authenticated;

-- Random power-up grant from the pool (used by _finalize_daily on a win).
CREATE OR REPLACE FUNCTION public._grant_random_powerup(p_uid UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE pool TEXT[] := ARRAY['free_reveal', 'extra_bank', 'discount', 'insurance', 'vowel_vision'];
BEGIN
  PERFORM public._grant_powerup(p_uid, pool[1 + floor(random() * array_length(pool, 1))::int], 3);
END;
$fn$;
REVOKE EXECUTE ON FUNCTION public._grant_random_powerup(UUID) FROM anon, authenticated;

-- daily_start activates selected pre-game power-ups on a fresh session.
DROP FUNCTION IF EXISTS public.daily_start();
DROP FUNCTION IF EXISTS public.daily_start(TEXT[]);
CREATE OR REPLACE FUNCTION public.daily_start(p_powerups TEXT[] DEFAULT '{}')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID := auth.uid();
  v_pid UUID; v_phrase TEXT; v_cat TEXT; v_sub TEXT;
  s public.daily_sessions;
  v_bonus INT := 0; v_active TEXT[] := '{}'; v_pu TEXT; v_owned INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_start: not authenticated'; END IF;
  v_pid := public._todays_puzzle_id();
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
  IF NOT FOUND THEN
    IF v_pid IS NULL THEN RAISE EXCEPTION 'daily_start: no puzzle available'; END IF;
    IF p_powerups IS NOT NULL THEN
      FOREACH v_pu IN ARRAY p_powerups LOOP
        IF v_pu IN ('extra_bank', 'discount', 'insurance', 'vowel_vision') AND NOT (v_pu = ANY(v_active)) THEN
          SELECT count INTO v_owned FROM public.user_powerups WHERE user_id = v_uid AND powerup = v_pu;
          IF COALESCE(v_owned, 0) > 0 THEN
            UPDATE public.user_powerups SET count = count - 1 WHERE user_id = v_uid AND powerup = v_pu;
            v_active := v_active || v_pu;
            IF v_pu = 'extra_bank' THEN v_bonus := v_bonus + 250; END IF;
          END IF;
        END IF;
      END LOOP;
    END IF;
    INSERT INTO public.daily_sessions (user_id, puzzle_date, puzzle_id, bankroll, guesses_remaining, active_powerups)
    VALUES (v_uid, CURRENT_DATE, v_pid, 1000 + v_bonus, 3, v_active)
    RETURNING * INTO s;
  END IF;
  SELECT upper(phrase), category, COALESCE(subcategory, '')
  INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;
  RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
                             s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.daily_start(TEXT[]) TO authenticated;

-- daily_buy_letter applies the Discount power-up (-25%, rounded up).
CREATE OR REPLACE FUNCTION public.daily_buy_letter(p_letter TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
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

  IF 'discount' = ANY(s.active_powerups) THEN v_cost := CEIL(v_cost * 0.75)::INT; END IF;
  IF 'vowel_vision' = ANY(s.active_powerups) AND v_letter IN ('A','E','I','O','U') THEN v_cost := CEIL(v_cost * 0.5)::INT; END IF;

  SELECT upper(phrase), category, COALESCE(subcategory, '')
  INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;

  IF s.state <> 'active' OR v_letter = ANY(s.incorrect_letters) OR s.bankroll < v_cost THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
                               s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;

  SELECT array_agg(g.i) INTO v_positions
  FROM generate_series(0, length(v_phrase) - 1) g(i)
  WHERE substr(v_phrase, g.i + 1, 1) = v_letter;

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
$fn$;
GRANT EXECUTE ON FUNCTION public.daily_buy_letter(TEXT) TO authenticated;

-- daily_submit_guess applies Insurance (first wrong guess free; consumes the power-up).
CREATE OR REPLACE FUNCTION public.daily_submit_guess(p_guess JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_uid UUID := auth.uid();
  s public.daily_sessions;
  v_phrase TEXT; v_cat TEXT; v_sub TEXT;
  v_editable INT[]; v_correct INT[] := '{}'; v_all_correct BOOLEAN := true;
  pos INT; v_guess_char TEXT;
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
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable
  FROM generate_series(0, length(v_phrase) - 1) g(i)
  WHERE substr(v_phrase, g.i + 1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions));
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable, 1) THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
                               s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;
  FOREACH pos IN ARRAY v_editable LOOP
    v_guess_char := upper(p_guess ->> pos::text);
    IF v_guess_char IS NULL THEN v_all_correct := false;
    ELSIF v_guess_char = substr(v_phrase, pos + 1, 1) THEN v_correct := v_correct || pos;
    ELSE v_all_correct := false; END IF;
  END LOOP;
  IF array_length(v_correct, 1) > 0 THEN
    s.revealed_positions := ARRAY(SELECT DISTINCT unnest(s.revealed_positions || v_correct) ORDER BY 1);
  END IF;
  IF NOT v_all_correct THEN
    IF 'insurance' = ANY(s.active_powerups) THEN
      s.active_powerups := array_remove(s.active_powerups, 'insurance');
    ELSE
      s.guesses_remaining := GREATEST(0, s.guesses_remaining - 1);
    END IF;
  END IF;
  UPDATE public.daily_sessions SET
    revealed_positions = s.revealed_positions, guesses_remaining = s.guesses_remaining,
    active_powerups = s.active_powerups, updated_at = NOW()
  WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
  RETURN public._daily_resolve_and_return(v_uid, v_phrase, v_cat, v_sub);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.daily_submit_guess(JSONB) TO authenticated;

-- NOTE: _finalize_daily grants a RANDOM power-up on win (PERFORM _grant_random_powerup);
-- full body in supabase-powerups.sql.
