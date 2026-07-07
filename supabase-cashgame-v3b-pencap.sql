-- Cash Game V3b: cap the wrong-guess penalty at half your Wallet.
--
-- Problem: the wrong-guess penalty is 0.2 × bounty, but bounty is puzzle-driven and
-- Micro has the HIGHEST k (0.90 → biggest bounties → biggest penalties) yet the SMALLEST
-- buy-in ($100). Across the 1,200-puzzle pool, 63% of Micro puzzles have a penalty ≥ $100,
-- so a single wrong guess instantly busts the run.
--
-- Fix (all tiers, phrase-blind): a wrong guess can never cost more than HALF your current
-- Wallet, floored at $10. The cap is a no-op at healthy Wallets (the 0.2×bounty term wins);
-- it only bites when you're low relative to the bounty — exactly the Micro case — so it can
-- only ever REDUCE a penalty. The $10 floor guarantees the run still busts to $0 eventually.
--   penalty = GREATEST($10, LEAST( round_$10(0.2 × bounty), round_$10(Wallet ÷ 2) ))
-- Spec: chat decision 2026-07-07. PITR point logged before apply.

BEGIN;

-- Board: expose the CAPPED wrong-guess penalty + a bust_risk that reflects it.
CREATE OR REPLACE FUNCTION public._climb_board(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_state TEXT; v_board JSONB; v_tier JSONB; v_k NUMERIC; v_bounty INT; v_pen INT;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_tier := public._cg_tier(cs.tier);
  v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  SELECT upper(phrase), category, COALESCE(subcategory,'') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_state := CASE cs.state WHEN 'solved' THEN 'won' WHEN 'busted' THEN 'lost' ELSE 'active' END;
  v_bounty := public._climb_bounty(cs.puzzle_id, v_k);
  v_pen := GREATEST(10, LEAST((round(0.2 * v_bounty / 10.0) * 10)::int, (round(cs.bankroll / 2.0 / 10.0) * 10)::int));
  v_board := public._daily_board(v_phrase, v_state, cs.bankroll::int, 99, cs.revealed_positions, cs.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('climb', jsonb_build_object(
    'bankroll', cs.bankroll, 'bounty', v_bounty, 'heat', cs.heat_x100,
    'heat_cap', (v_tier->>'heat_cap')::int, 'tier', cs.tier, 'buy_in', cs.buy_in, 'tier_label', v_tier->>'label',
    'spent', cs.spent, 'position', cs.position, 'last_gain', cs.last_gain,
    'wrong_penalty', v_pen, 'bust_risk', (cs.state = 'active' AND cs.bankroll <= v_pen),
    'state', cs.state, 'pups_locked', cs.pups_locked, 'equipped', to_jsonb(cs.active_powerups),
    'run_solves', cs.run_solves, 'run_profit', cs.bankroll - cs.buy_in));
END; $function$;

-- Submit a guess: wrong drains the CAPPED penalty; if that empties the Wallet → BUST.
CREATE OR REPLACE FUNCTION public.climb_submit_guess(p_guess jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}';
  v_all BOOLEAN := true; pos INT; v_ch TEXT; v_tier JSONB; v_k NUMERIC; v_bounty INT; v_pen INT;
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
  -- Wrong guess: penalty = min(0.2×bounty, half the Wallet), floored $10. Empties Wallet → bust.
  v_tier := public._cg_tier(cs.tier); v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_bounty := public._climb_bounty(cs.puzzle_id, v_k);
  v_pen := GREATEST(10, LEAST((round(0.2 * v_bounty / 10.0) * 10)::int, (round(cs.bankroll / 2.0 / 10.0) * 10)::int));
  IF cs.bankroll - v_pen <= 0 THEN
    RETURN public._cg_bust(v_uid);
  END IF;
  cs.bankroll := cs.bankroll - v_pen;
  UPDATE public.climb_state SET bankroll = cs.bankroll, updated_at = now() WHERE user_id = v_uid;
  RETURN public._climb_resolve(v_uid);
END; $function$;

COMMIT;
