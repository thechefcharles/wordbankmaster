-- ============================================================================
-- Cash Game: a wrong guess no longer busts the whole run while you can still
-- afford letters. Mirrors Daily: a wrong guess DRAINS budget (a penalty) and
-- you keep playing; you BUST only when you're out of budget (can't afford the
-- cheapest letter) and guess wrong — the "one last guess or you lose" wall.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.climb_submit_guess(p_guess jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}';
  v_all BOOLEAN := true; pos INT; v_ch TEXT;
  v_tier JSONB; v_k NUMERIC; v_stake INT; v_bounty INT; v_budget_left INT; v_cheapest INT; v_pen INT;
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

  -- ── Wrong guess ──────────────────────────────────────────────────────────
  v_tier := public._cg_tier(cs.tier);
  v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_stake := COALESCE((v_tier->>'stake')::int, 1);
  v_bounty := round(public._climb_bounty(cs.puzzle_id, v_k) * v_stake * cs.heat_x100 / 100.0)::int;
  v_budget_left := GREATEST(0, v_bounty - cs.spent);
  v_cheapest := public._cg_cheapest(cs);
  IF v_cheapest IS NULL OR v_budget_left < v_cheapest THEN
    -- Out of budget: this was your last guess → bust the run.
    RETURN public._cg_bust(v_uid);
  END IF;
  -- Still have budget: drain a penalty (≥ one letter, or 20% of what's left) and keep playing.
  v_pen := LEAST(v_budget_left, GREATEST(v_cheapest, (round(0.2 * v_budget_left / 10.0) * 10)::int));
  UPDATE public.climb_state SET spent = cs.spent + v_pen, pups_locked = true, updated_at = now()
    WHERE user_id = v_uid;
  RETURN public._climb_board(v_uid);
END; $function$;

COMMIT;
