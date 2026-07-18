-- Daily: make wrong phrase guesses FREE (2026-07-17).
--
-- Previously a wrong Daily guess drained 20% of remaining budget (min $10) — same penalty
-- shape as Cash Game / Match. Daily is meant to be the low-pressure mode, and wrong guesses
-- reveal nothing (no guess-and-check exploit) and don't affect the multiplier or payout, so
-- the drain just punished careless taps. Removing it.
--
-- KEPT UNCHANGED: the broke "last-guess" wall — if you can't afford the cheapest remaining
-- letter and guess wrong, you still LOSE (bank $0). You reach broke by BUYING letters, so
-- that danger state still triggers and still ends the game; guesses just no longer push you
-- toward it. Only the non-broke drain is removed.

CREATE OR REPLACE FUNCTION public.daily_submit_guess(p_guess jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); s public.daily_sessions; v_phrase TEXT; v_cat TEXT; v_sub TEXT;
  v_editable INT[]; v_correct INT[] := '{}'; v_all_correct BOOLEAN := true; pos INT; v_guess_char TEXT;
  v_cheapest INT; v_all INT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_submit_guess: not authenticated'; END IF;
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'daily_submit_guess: no active session'; END IF;
  SELECT upper(phrase), category, COALESCE(subcategory, '') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;
  IF s.state <> 'active' THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions));
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable, 1) THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;
  FOREACH pos IN ARRAY v_editable LOOP
    v_guess_char := upper(p_guess ->> pos::text);
    IF v_guess_char IS NULL THEN v_all_correct := false;
    ELSIF v_guess_char = substr(v_phrase, pos+1, 1) THEN v_correct := v_correct || pos;
    ELSE v_all_correct := false; END IF;
  END LOOP;
  IF v_all_correct THEN
    s.revealed_positions := ARRAY(SELECT DISTINCT unnest(s.revealed_positions || v_correct) ORDER BY 1);
    UPDATE public.daily_sessions SET revealed_positions = s.revealed_positions, updated_at = NOW()
      WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
    RETURN public._daily_resolve_and_return(v_uid, v_phrase, v_cat, v_sub);
  END IF;
  -- Wrong guess.
  s.p_wrong_guesses := s.p_wrong_guesses + 1;
  v_cheapest := public._daily_cheapest_buyable(s, v_phrase);
  IF v_cheapest IS NOT NULL AND s.bankroll < v_cheapest THEN
    -- Final-guess wall (UNCHANGED): can't afford any letter and guessed wrong → fail (bank $0).
    SELECT array_agg(g.i) INTO v_all FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1, 1) <> ' ';
    UPDATE public.daily_sessions SET state = 'lost', finished_at = NOW(),
      revealed_positions = COALESCE(v_all, '{}'), p_wrong_guesses = s.p_wrong_guesses, updated_at = NOW()
      WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
    PERFORM public._finalize_daily(v_uid, false, s.spent, 0, COALESCE(array_length(s.incorrect_letters,1),0));
    RETURN public._daily_board(v_phrase, 'lost', s.bankroll, s.guesses_remaining, COALESCE(v_all,'{}'), s.incorrect_letters, v_cat, v_sub)
      || jsonb_build_object('live', public._daily_live(s.bankroll, public._daily_bounty_mult(v_uid)),
           'base', public._daily_reward(s.puzzle_id), 'modifier', s.active_powerups[1], 'twist_used', s.twist_used,
           'bounty_mult', public._daily_bounty_mult(v_uid), 'wrong_guesses', s.p_wrong_guesses,
           'daily_result', jsonb_build_object('won', false, 'base', public._daily_reward(s.puzzle_id),
             'spent', s.spent, 'kept', 0, 'mult', public._daily_bounty_mult(v_uid), 'winnings', 0, 'banked', 0, 'score', 0,
             'reward', 0, 'net', 0));
  END IF;
  -- Otherwise: guesses are FREE now. Track the count (stats only), NO budget drain.
  UPDATE public.daily_sessions SET p_wrong_guesses = s.p_wrong_guesses, updated_at = NOW()
    WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
  RETURN public._daily_resolve_and_return(v_uid, v_phrase, v_cat, v_sub);
END; $function$;

REVOKE EXECUTE ON FUNCTION public.daily_submit_guess(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.daily_submit_guess(jsonb) TO authenticated;
