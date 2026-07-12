BEGIN;

CREATE OR REPLACE FUNCTION public.climb_use_powerup(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_eff TEXT; v_qty INT; v_phrase TEXT; v_positions INT[];
  v_k NUMERIC; v_stake INT; v_bounty INT; v_budget_left INT; v_cheapest INT; v_next UUID;
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
  -- ⏭️ Free Skip: swap this puzzle for a fresh one, keeping your Interest, secured pile, and run.
  IF v_eff = 'free_skip' THEN
    SELECT qty INTO v_qty FROM public.user_powerups_v2 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
    IF COALESCE(v_qty,0) <= 0 THEN RETURN public._climb_board(v_uid); END IF;
    v_next := public._pick_casual(v_uid, null, cs.puzzle_id, 0);
    IF v_next IS NULL THEN RETURN public._climb_board(v_uid); END IF;   -- no fresh puzzle available -> don't consume
    UPDATE public.user_powerups_v2 SET qty = qty - 1 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
    -- New puzzle; reset per-puzzle progress. KEEP heat_x100, bankroll, run_solves, position.
    UPDATE public.climb_state SET puzzle_id = v_next, revealed_positions = '{}', incorrect_letters = '{}',
      spent = 0, last_gain = 0, active_powerups = '{}', next_puzzle_id = NULL, pups_locked = false,
      state = 'active', puzzle_started_at = now(), updated_at = now() WHERE user_id = v_uid;
    PERFORM public._mark_seen(v_uid, v_next);
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

-- New Cash Game power-up: Free Skip (expensive; anytime swap, keeps your streak).
INSERT INTO public.powerups (id, name, price, active, effect_key, kind, sort)
  VALUES ('free_skip', 'Free Skip', 300, true, 'free_skip', 'climb', 52)
  ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, price = EXCLUDED.price,
    active = EXCLUDED.active, effect_key = EXCLUDED.effect_key, kind = EXCLUDED.kind, sort = EXCLUDED.sort;

-- Blitz is being retired -- pull its power-ups from the store.
UPDATE public.powerups SET active = false WHERE kind = 'blitz';

COMMIT;
