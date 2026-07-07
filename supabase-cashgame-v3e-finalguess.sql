-- Cash Game V3e: phrase-blind "final guess" endgame + hard $0 floor.
--
-- Restores the dramatic endgame V3 removed, but WITHOUT the answer leak. The old trigger
-- was "can't afford the cheapest letter IN THE PHRASE" — that leaked which letters were in
-- the answer. The new trigger is "can't afford the cheapest letter you could still BUY on
-- the keyboard" (min letter_cost × stake, minus letters you've already tried/revealed) —
-- purely a function of your Wallet and your own moves, never the hidden phrase.
--
-- Rules:
--   • Wallet never goes negative. Buying is blocked when you can't afford it; the capped
--     wrong-guess penalty (≤ ½ Wallet) can't drop you below ~½ your Wallet.
--   • When Wallet < cheapest buyable letter → you're on your FINAL GUESS. A wrong guess
--     there → BUST (forfeit the remaining Wallet, run ends). Solve → win. Cash Out → bank it.
--   • While you can still afford a letter, a wrong guess just drains the capped penalty
--     (grinds you toward the final-guess threshold; keeps guessing from being free).
--   • No 'stuck' state machine — `final_guess` is computed on the fly from the Wallet.
-- Spec: chat decision 2026-07-07. PITR point logged before apply.

BEGIN;

-- Cheapest letter you could still BUY (phrase-blind): min letter_cost × stake over letters
-- not yet tried (incorrect) and not yet revealed. Uses only the player's own known moves.
CREATE OR REPLACE FUNCTION public._cg_cheapest(cs public.climb_state)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
AS $function$
  SELECT MIN(
    CASE WHEN 'half_off' = ANY(COALESCE(cs.active_powerups, '{}'::text[]))
      THEN CEIL(public.letter_cost(x.l) * st.stake * 0.5)::int
      ELSE public.letter_cost(x.l) * st.stake END)
  FROM (SELECT chr(65 + gs) AS l FROM generate_series(0, 25) gs) x
  CROSS JOIN (SELECT COALESCE((public._cg_tier(cs.tier)->>'stake')::int, 1) AS stake) st
  WHERE x.l <> ALL(COALESCE(cs.incorrect_letters, '{}'::text[]))
    AND x.l NOT IN (
      SELECT DISTINCT substr(upper(dp.phrase), p + 1, 1)
      FROM public.daily_puzzles dp, unnest(COALESCE(cs.revealed_positions, '{}'::int[])) AS p
      WHERE dp.id = cs.puzzle_id
    );
$function$;

-- Board: expose `cheapest` + `final_guess` (Wallet can't buy any letter → do-or-die).
CREATE OR REPLACE FUNCTION public._climb_board(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_state TEXT; v_board JSONB; v_tier JSONB; v_k NUMERIC; v_stake INT; v_bounty INT; v_pen INT; v_cheapest INT;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_tier := public._cg_tier(cs.tier);
  v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_stake := COALESCE((v_tier->>'stake')::int, 1);
  SELECT upper(phrase), category, COALESCE(subcategory,'') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_state := CASE cs.state WHEN 'solved' THEN 'won' WHEN 'busted' THEN 'lost' ELSE 'active' END;
  v_bounty := public._climb_bounty(cs.puzzle_id, v_k) * v_stake;
  v_pen := GREATEST(10, LEAST((round(0.2 * v_bounty / 10.0) * 10)::int, (round(cs.bankroll / 2.0 / 10.0) * 10)::int));
  v_cheapest := public._cg_cheapest(cs);
  v_board := public._daily_board(v_phrase, v_state, cs.bankroll::int, 99, cs.revealed_positions, cs.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('climb', jsonb_build_object(
    'bankroll', cs.bankroll, 'bounty', v_bounty, 'heat', cs.heat_x100,
    'heat_cap', (v_tier->>'heat_cap')::int, 'tier', cs.tier, 'buy_in', cs.buy_in, 'tier_label', v_tier->>'label',
    'stake', v_stake,
    'spent', cs.spent, 'position', cs.position, 'last_gain', cs.last_gain,
    'wrong_penalty', v_pen, 'cheapest', v_cheapest,
    'final_guess', (cs.state = 'active' AND (v_cheapest IS NULL OR cs.bankroll < v_cheapest)),
    'state', cs.state, 'pups_locked', cs.pups_locked, 'equipped', to_jsonb(cs.active_powerups),
    'run_solves', cs.run_solves, 'run_profit', cs.bankroll - cs.buy_in));
END; $function$;

-- Submit a guess: correct → solve. Wrong → if you can't afford the cheapest letter, that
-- was your FINAL GUESS → bust; else drain the capped penalty (Wallet never goes negative).
CREATE OR REPLACE FUNCTION public.climb_submit_guess(p_guess jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}';
  v_all BOOLEAN := true; pos INT; v_ch TEXT; v_tier JSONB; v_k NUMERIC; v_stake INT; v_bounty INT; v_pen INT; v_cheapest INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_submit_guess: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'climb_submit_guess: no run'; END IF;
  IF cs.state <> 'active' THEN RETURN public._climb_board(v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1,1) <> ' ' AND NOT (g.i = ANY(cs.revealed_positions));
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable,1) THEN RETURN public._climb_board(v_uid); END IF;
  FOREACH pos IN ARRAY v_editable LOOP
    v_ch := upper(p_guess ->> pos::text);
    IF v_ch IS NULL THEN v_all := false;
    ELSIF v_ch = substr(v_phrase, pos+1, 1) THEN v_correct := v_correct || pos;
    ELSE v_all := false; END IF;
  END LOOP;
  IF v_all THEN
    cs.revealed_positions := ARRAY(SELECT DISTINCT unnest(cs.revealed_positions || v_correct) ORDER BY 1);
    UPDATE public.climb_state SET revealed_positions = cs.revealed_positions, updated_at = now() WHERE user_id = v_uid;
    RETURN public._climb_resolve(v_uid);
  END IF;
  -- Wrong guess. Phrase-blind endgame: can't afford the cheapest buyable letter → this was
  -- your final guess → BUST. Otherwise drain the capped penalty and play on.
  v_cheapest := public._cg_cheapest(cs);
  IF v_cheapest IS NULL OR cs.bankroll < v_cheapest THEN
    RETURN public._cg_bust(v_uid);
  END IF;
  v_tier := public._cg_tier(cs.tier); v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_stake := COALESCE((v_tier->>'stake')::int, 1);
  v_bounty := public._climb_bounty(cs.puzzle_id, v_k) * v_stake;
  v_pen := GREATEST(10, LEAST((round(0.2 * v_bounty / 10.0) * 10)::int, (round(cs.bankroll / 2.0 / 10.0) * 10)::int));
  cs.bankroll := GREATEST(0, cs.bankroll - v_pen);
  UPDATE public.climb_state SET bankroll = cs.bankroll, updated_at = now() WHERE user_id = v_uid;
  RETURN public._climb_resolve(v_uid);
END; $function$;

COMMIT;
