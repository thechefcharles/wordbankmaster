-- Cash Game V3d: per-tier stake multiplier — make the buy-in a true stakes multiplier.
--
-- Before: buy-ins scaled but letter costs + bounty were tier-flat, so a bigger buy-in only
-- bought SAFETY (more letters/wrong-guesses absorbed), not bigger stakes — and lower k at
-- higher tiers meant a Gold solve paid LESS than a Micro solve. Tension + difficulty +
-- payout were all inverted.
--
-- Fix: give each tier a stake multiplier M (Micro ×1, Bronze ×4, Silver ×10, Gold ×20 —
-- exactly buy_in ÷ 250). Multiply BOTH letter costs and bounty by M inside Cash Game. Now:
--   • Wallet ($250·M) ÷ letter cost (·M) is constant → identical tension + difficulty at
--     every tier; the game plays the same, just for M× the dollars.
--   • Per-solve payout scales ·M → higher tiers genuinely pay bigger (a Gold solve ≈ 12×
--     a Micro solve).
--   • k still sets the efficiency/skill gradient (bounty ÷ full-reveal = k), heat cap still
--     sets the streak ceiling. The penalty cap (½ Wallet) scales cleanly too.
-- Board now exposes `stake` so the client keyboard can show M-scaled letter prices.
-- Spec: chat decision 2026-07-07. PITR point logged before apply.

BEGIN;

-- Tier config gains a `stake` multiplier (= buy_in / 250).
CREATE OR REPLACE FUNCTION public._cg_tier(p_tier text)
 RETURNS jsonb LANGUAGE sql IMMUTABLE
AS $function$
  SELECT CASE lower(p_tier)
    WHEN 'micro'  THEN jsonb_build_object('buy_in', 250,  'k', 0.90, 'heat_cap', 200, 'stake', 1,  'label', '🪙 Micro',  'order', 1)
    WHEN 'bronze' THEN jsonb_build_object('buy_in', 1000, 'k', 0.85, 'heat_cap', 250, 'stake', 4,  'label', '🥉 Bronze', 'order', 2)
    WHEN 'silver' THEN jsonb_build_object('buy_in', 2500, 'k', 0.70, 'heat_cap', 275, 'stake', 10, 'label', '🥈 Silver', 'order', 3)
    WHEN 'gold'   THEN jsonb_build_object('buy_in', 5000, 'k', 0.55, 'heat_cap', 300, 'stake', 20, 'label', '🥇 Gold',   'order', 4)
    ELSE NULL END;
$function$;

-- Buy a letter: cost = base letter_cost × tier stake (then half_off).
CREATE OR REPLACE FUNCTION public.climb_buy_letter(p_letter text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_letter TEXT; v_cost INT; v_stake INT; v_positions INT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_buy_letter: not authenticated'; END IF;
  v_letter := upper(p_letter);
  IF public.letter_cost(v_letter) IS NULL THEN RAISE EXCEPTION 'climb_buy_letter: invalid letter'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'climb_buy_letter: no run'; END IF;
  IF cs.state <> 'active' THEN RETURN public._climb_board(v_uid); END IF;
  v_stake := COALESCE((public._cg_tier(cs.tier)->>'stake')::int, 1);
  v_cost := public.letter_cost(v_letter) * v_stake;
  IF 'half_off' = ANY(cs.active_powerups) THEN v_cost := CEIL(v_cost * 0.5)::int; END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  IF v_letter = ANY(cs.incorrect_letters) OR cs.bankroll < v_cost THEN RETURN public._climb_board(v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1,1) = v_letter;
  IF v_positions IS NOT NULL AND v_positions <@ cs.revealed_positions THEN RETURN public._climb_board(v_uid); END IF;
  cs.bankroll := cs.bankroll - v_cost;
  IF v_positions IS NULL THEN cs.incorrect_letters := array_append(cs.incorrect_letters, v_letter);
  ELSE cs.revealed_positions := ARRAY(SELECT DISTINCT unnest(cs.revealed_positions || v_positions) ORDER BY 1); END IF;
  UPDATE public.climb_state SET bankroll = cs.bankroll, revealed_positions = cs.revealed_positions,
    incorrect_letters = cs.incorrect_letters, spent = cs.spent + v_cost, pups_locked = true, updated_at = now() WHERE user_id = v_uid;
  RETURN public._climb_resolve(v_uid);
END; $function$;

-- Board: bounty × stake; expose `stake` for the client keyboard.
CREATE OR REPLACE FUNCTION public._climb_board(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_state TEXT; v_board JSONB; v_tier JSONB; v_k NUMERIC; v_stake INT; v_bounty INT; v_pen INT;
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
  v_board := public._daily_board(v_phrase, v_state, cs.bankroll::int, 99, cs.revealed_positions, cs.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('climb', jsonb_build_object(
    'bankroll', cs.bankroll, 'bounty', v_bounty, 'heat', cs.heat_x100,
    'heat_cap', (v_tier->>'heat_cap')::int, 'tier', cs.tier, 'buy_in', cs.buy_in, 'tier_label', v_tier->>'label',
    'stake', v_stake,
    'spent', cs.spent, 'position', cs.position, 'last_gain', cs.last_gain,
    'wrong_penalty', v_pen, 'bust_risk', (cs.state = 'active' AND cs.bankroll <= v_pen),
    'state', cs.state, 'pups_locked', cs.pups_locked, 'equipped', to_jsonb(cs.active_powerups),
    'run_solves', cs.run_solves, 'run_profit', cs.bankroll - cs.buy_in));
END; $function$;

-- Resolve: solve payout = bounty × stake × heat.
CREATE OR REPLACE FUNCTION public._climb_resolve(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_won BOOLEAN; v_tier JSONB; v_k NUMERIC; v_stake INT; v_cap INT; v_bounty INT; v_payout INT; v_cat TEXT; v_time INT;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF cs.state <> 'active' THEN RETURN public._climb_board(p_uid); END IF;
  v_tier := public._cg_tier(cs.tier); v_k := COALESCE((v_tier->>'k')::numeric, 0.85); v_cap := COALESCE((v_tier->>'heat_cap')::int, 250);
  v_stake := COALESCE((v_tier->>'stake')::int, 1);
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(cs.revealed_positions)));
  IF v_won THEN
    v_bounty := public._climb_bounty(cs.puzzle_id, v_k) * v_stake;
    v_payout := round(v_bounty * cs.heat_x100 / 100.0)::int;
    v_time := LEAST(GREATEST(EXTRACT(epoch FROM (now() - COALESCE(cs.puzzle_started_at, cs.updated_at))) * 1000, 0), 1800000)::int;
    UPDATE public.climb_state SET state = 'solved', last_gain = v_payout,
      bankroll = cs.bankroll + v_payout,
      heat_x100 = LEAST(v_cap, cs.heat_x100 + 10),
      run_solves = cs.run_solves + 1, updated_at = now() WHERE user_id = p_uid;
    PERFORM public._log_game_result(p_uid,'climb','won', cs.puzzle_id, v_cat, 1, 1, cs.spent::int, v_payout, v_time);
  ELSE
    UPDATE public.climb_state SET state = 'active', updated_at = now() WHERE user_id = p_uid;
  END IF;
  RETURN public._climb_board(p_uid);
END; $function$;

-- Submit a guess: wrong-guess penalty from bounty × stake (still capped at ½ Wallet).
CREATE OR REPLACE FUNCTION public.climb_submit_guess(p_guess jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}';
  v_all BOOLEAN := true; pos INT; v_ch TEXT; v_tier JSONB; v_k NUMERIC; v_stake INT; v_bounty INT; v_pen INT;
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
  -- Wrong guess: penalty = min(0.2×bounty·stake, half the Wallet), floored $10. Empties Wallet → bust.
  v_tier := public._cg_tier(cs.tier); v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_stake := COALESCE((v_tier->>'stake')::int, 1);
  v_bounty := public._climb_bounty(cs.puzzle_id, v_k) * v_stake;
  v_pen := GREATEST(10, LEAST((round(0.2 * v_bounty / 10.0) * 10)::int, (round(cs.bankroll / 2.0 / 10.0) * 10)::int));
  IF cs.bankroll - v_pen <= 0 THEN
    RETURN public._cg_bust(v_uid);
  END IF;
  cs.bankroll := cs.bankroll - v_pen;
  UPDATE public.climb_state SET bankroll = cs.bankroll, updated_at = now() WHERE user_id = v_uid;
  RETURN public._climb_resolve(v_uid);
END; $function$;

COMMIT;
