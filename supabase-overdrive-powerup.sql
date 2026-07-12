-- ============================================================================
-- 🏧 Overdrive — a Cash Game lifeline for the "out of money" moment.
-- Usable ONLY when you're stuck (can't afford any letter). Arms a single FREE
-- letter of your choice (any letter): tap Overdrive, then buy any letter for $0,
-- even with an empty budget. Consumed when that letter is bought.
-- ============================================================================
BEGIN;

INSERT INTO public.powerups (id, name, kind, effect_key, price, sort, active)
VALUES ('overdrive', 'Overdrive', 'climb', 'overdrive', 120, 50, true)
ON CONFLICT (id) DO UPDATE
  SET name = EXCLUDED.name, kind = EXCLUDED.kind, effect_key = EXCLUDED.effect_key,
      price = EXCLUDED.price, active = true;

-- ── Use: arm the free letter (stuck-only) ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.climb_use_powerup(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_eff TEXT; v_qty INT; v_phrase TEXT; v_positions INT[];
  v_k NUMERIC; v_stake INT; v_bounty INT; v_budget_left INT; v_cheapest INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_use_powerup: not authenticated'; END IF;
  SELECT effect_key INTO v_eff FROM public.powerups WHERE id = p_id AND kind = 'climb' AND active;
  IF v_eff IS NULL THEN RAISE EXCEPTION 'climb_use_powerup: invalid power-up'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state NOT IN ('active','stuck') THEN RETURN public._climb_board(v_uid); END IF;
  -- Heat Shield is a passive safety net (auto-consumed on a bust) — tapping it never burns it.
  IF v_eff = 'heat_shield' THEN RETURN public._climb_board(v_uid); END IF;
  -- 🏧 Overdrive: only usable when you're out of money; arms one free letter of your choice.
  IF v_eff = 'overdrive' THEN
    v_k := COALESCE((public._cg_tier(cs.tier)->>'k')::numeric, 0.85);
    v_stake := COALESCE((public._cg_tier(cs.tier)->>'stake')::int, 1);
    v_bounty := round(public._climb_bounty(cs.puzzle_id, v_k) * v_stake * cs.heat_x100 / 100.0)::int;
    v_budget_left := GREATEST(0, v_bounty - cs.spent);
    v_cheapest := public._cg_cheapest(cs);
    -- Not stuck (you can still afford a letter) → can't use it. Don't consume.
    IF v_cheapest IS NOT NULL AND v_budget_left >= v_cheapest THEN RETURN public._climb_board(v_uid); END IF;
    SELECT qty INTO v_qty FROM public.user_powerups_v2 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
    IF COALESCE(v_qty,0) <= 0 OR 'overdrive' = ANY(cs.active_powerups) THEN RETURN public._climb_board(v_uid); END IF;
    UPDATE public.user_powerups_v2 SET qty = qty - 1 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
    UPDATE public.climb_state SET active_powerups = array_append(active_powerups, 'overdrive') WHERE user_id = v_uid;
    RETURN public._climb_board(v_uid);
  END IF;
  -- Reveal-type power-ups (free_reveal, vowel_vision, reveal_word, …).
  SELECT qty INTO v_qty FROM public.user_powerups_v2 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
  IF COALESCE(v_qty,0) <= 0 THEN RETURN public._climb_board(v_uid); END IF;
  IF v_eff = ANY(cs.active_powerups) THEN RETURN public._climb_board(v_uid); END IF;
  UPDATE public.user_powerups_v2 SET qty = qty - 1 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
  UPDATE public.climb_state SET active_powerups = array_append(active_powerups, v_eff) WHERE user_id = v_uid;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_positions := public._powerup_reveal(v_phrase, v_eff, cs.revealed_positions);
  IF v_positions IS NOT NULL THEN
    UPDATE public.climb_state SET revealed_positions = ARRAY(SELECT DISTINCT unnest(revealed_positions || v_positions) ORDER BY 1) WHERE user_id = v_uid;
  END IF;
  RETURN public._climb_resolve(v_uid);
END; $function$;

-- ── Buy: an armed Overdrive makes the next letter free (any letter, even broke) ──
CREATE OR REPLACE FUNCTION public.climb_buy_letter(p_letter text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_letter TEXT; v_cost INT; v_stake INT;
  v_k NUMERIC; v_bounty INT; v_budget_left INT; v_positions INT[]; v_free BOOLEAN := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_buy_letter: not authenticated'; END IF;
  v_letter := upper(p_letter);
  IF public.letter_cost(v_letter) IS NULL THEN RAISE EXCEPTION 'climb_buy_letter: invalid letter'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'climb_buy_letter: no run'; END IF;
  IF cs.state <> 'active' THEN RETURN public._climb_board(v_uid); END IF;
  v_k := COALESCE((public._cg_tier(cs.tier)->>'k')::numeric, 0.85);
  v_stake := COALESCE((public._cg_tier(cs.tier)->>'stake')::int, 1);
  v_cost := public.letter_cost(v_letter) * v_stake;
  IF 'half_off' = ANY(cs.active_powerups) THEN v_cost := CEIL(v_cost * 0.5)::int; END IF;
  -- 🏧 Overdrive armed → this letter is free (any letter), even with an empty budget.
  v_free := 'overdrive' = ANY(cs.active_powerups);
  IF v_free THEN v_cost := 0; END IF;
  v_bounty := round(public._climb_bounty(cs.puzzle_id, v_k) * v_stake * cs.heat_x100 / 100.0)::int;
  v_budget_left := v_bounty - cs.spent;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  -- Overdrive letters bypass the budget check entirely (they're free even at $0 budget).
  IF v_letter = ANY(cs.incorrect_letters) OR (NOT v_free AND v_budget_left < v_cost) THEN RETURN public._climb_board(v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1,1) = v_letter;
  IF v_positions IS NOT NULL AND v_positions <@ cs.revealed_positions THEN RETURN public._climb_board(v_uid); END IF;
  IF v_positions IS NULL THEN cs.incorrect_letters := array_append(cs.incorrect_letters, v_letter);
  ELSE cs.revealed_positions := ARRAY(SELECT DISTINCT unnest(cs.revealed_positions || v_positions) ORDER BY 1); END IF;
  UPDATE public.climb_state SET revealed_positions = cs.revealed_positions,
    incorrect_letters = cs.incorrect_letters, spent = cs.spent + v_cost,
    active_powerups = CASE WHEN v_free THEN array_remove(cs.active_powerups, 'overdrive') ELSE cs.active_powerups END,
    pups_locked = true, updated_at = now() WHERE user_id = v_uid;
  RETURN public._climb_resolve(v_uid);
END; $function$;

COMMIT;
