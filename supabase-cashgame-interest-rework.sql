-- ============================================================================
-- Cash Game interest rework: the per-solve interest (heat) gain is now EARNED,
-- not a flat +10%. Plus: the Heat Shield power-up finally does something.
-- ============================================================================
-- gain per solve = 5 (base) + efficiency (0-10) + credit (0-4), capped by tier:
--   • efficiency = how cheaply you solved (kept / bounty), rounded ×10  → +0..+10
--   • credit     = your credit tier: Excellent +4, Good +2, Fair +1, else +0
-- So a cheap solve with great credit ≈ +19%; a sloppy one ≈ +5%. Tier still caps
-- the ceiling (Micro +100% → Gold +200%).
--
-- Heat Shield (was dead in Cash Game): if OWNED, it auto-saves you from a bust —
-- when a wrong guess would end the run, it's consumed instead and you jump to a
-- fresh puzzle keeping your Payout AND your interest. The one thing that wipes
-- your interest is a bust, so this is the true "protect your interest" power-up.
-- ============================================================================
BEGIN;

-- ── Dynamic interest gain on solve ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._climb_resolve(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_won BOOLEAN; v_tier JSONB; v_k NUMERIC; v_stake INT; v_cap INT;
  v_bounty INT; v_keep INT; v_cat TEXT; v_time INT; v_next UUID;
  v_eff NUMERIC; v_ctier TEXT; v_cbonus INT; v_gain INT;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF cs.state <> 'active' THEN RETURN public._climb_board(p_uid); END IF;
  v_tier := public._cg_tier(cs.tier); v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_cap := COALESCE((v_tier->>'heat_cap')::int, 250); v_stake := COALESCE((v_tier->>'stake')::int, 1);
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(cs.revealed_positions)));
  IF v_won THEN
    -- Heat is baked into the bounty; keep = what carries into the Balance. No 2nd ×heat.
    v_bounty := round(public._climb_bounty(cs.puzzle_id, v_k) * v_stake * cs.heat_x100 / 100.0)::int;
    v_keep := GREATEST(0, v_bounty - cs.spent);
    -- Earned interest gain: base + efficiency (how cheaply you solved) + credit standing.
    v_eff := CASE WHEN v_bounty > 0 THEN LEAST(1.0, v_keep::numeric / v_bounty) ELSE 0 END;
    v_ctier := public._credit_tier((SELECT COALESCE(credit_score, 650) FROM public.profiles WHERE id = p_uid));
    v_cbonus := CASE v_ctier WHEN 'Excellent' THEN 4 WHEN 'Good' THEN 2 WHEN 'Fair' THEN 1 ELSE 0 END;
    v_gain := 5 + round(10 * v_eff)::int + v_cbonus;
    v_time := LEAST(GREATEST(EXTRACT(epoch FROM (now() - COALESCE(cs.puzzle_started_at, cs.updated_at))) * 1000, 0), 1800000)::int;
    v_next := public._pick_casual(p_uid, null, cs.puzzle_id, 0);
    UPDATE public.climb_state SET state = 'solved', last_gain = v_keep,
      bankroll = cs.bankroll + v_keep,
      heat_x100 = LEAST(v_cap, cs.heat_x100 + v_gain),
      run_solves = cs.run_solves + 1, next_puzzle_id = v_next, updated_at = now() WHERE user_id = p_uid;
    PERFORM public._record_category_solve(p_uid, v_cat);
    PERFORM public._log_game_result(p_uid,'climb','won', cs.puzzle_id, v_cat, 1, 1, cs.spent::int, v_keep, v_time);
  ELSE
    UPDATE public.climb_state SET state = 'active', updated_at = now() WHERE user_id = p_uid;
  END IF;
  RETURN public._climb_board(p_uid);
END; $function$;

-- ── Heat Shield: auto-save from a bust (keep Payout + interest, jump to a fresh puzzle) ──
CREATE OR REPLACE FUNCTION public._cg_try_shield(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_qty INT; v_pid UUID;
BEGIN
  SELECT qty INTO v_qty FROM public.user_powerups_v2
    WHERE user_id = p_uid AND powerup_id = 'heat_shield' AND pool = 'cash';
  IF COALESCE(v_qty, 0) <= 0 THEN RETURN NULL; END IF;                 -- no shield owned → let it bust
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid FOR UPDATE;
  IF NOT FOUND OR cs.state <> 'active' THEN RETURN NULL; END IF;
  v_pid := public._pick_casual(p_uid, null, cs.puzzle_id, 0);
  IF v_pid IS NULL THEN RETURN NULL; END IF;                           -- nowhere to advance → bust
  UPDATE public.user_powerups_v2 SET qty = qty - 1
    WHERE user_id = p_uid AND powerup_id = 'heat_shield' AND pool = 'cash';
  -- Escape: fresh puzzle, per-puzzle fields reset, but bankroll (Payout) + heat_x100 (interest) kept.
  UPDATE public.climb_state SET position = cs.position + 1, puzzle_id = v_pid, revealed_positions = '{}',
    incorrect_letters = '{}', spent = 0, last_gain = 0, active_powerups = '{}', next_puzzle_id = NULL,
    pups_locked = false, state = 'active', puzzle_started_at = now(), updated_at = now() WHERE user_id = p_uid;
  PERFORM public._mark_seen(p_uid, v_pid);
  RETURN public._climb_board(p_uid) || jsonb_build_object('shielded', true);
END; $function$;

-- ── Wire the shield into the bust wall ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.climb_submit_guess(p_guess jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}';
  v_all BOOLEAN := true; pos INT; v_ch TEXT;
  v_tier JSONB; v_k NUMERIC; v_stake INT; v_bounty INT; v_budget_left INT; v_cheapest INT; v_pen INT; v_shield JSONB;
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
    -- Out of budget: this was your last guess → bust — unless a Heat Shield saves you.
    v_shield := public._cg_try_shield(v_uid);
    IF v_shield IS NOT NULL THEN RETURN v_shield; END IF;
    RETURN public._cg_bust(v_uid);
  END IF;
  -- Still have budget: drain a penalty (≥ one letter, or 20% of what's left) and keep playing.
  v_pen := LEAST(v_budget_left, GREATEST(v_cheapest, (round(0.2 * v_budget_left / 10.0) * 10)::int));
  UPDATE public.climb_state SET spent = cs.spent + v_pen, pups_locked = true, updated_at = now()
    WHERE user_id = v_uid;
  RETURN public._climb_board(v_uid);
END; $function$;

COMMIT;
