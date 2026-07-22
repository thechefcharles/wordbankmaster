-- ============================================================================
-- Cash Game wrong-solve v2: escalating, budget-only, bounty-based penalty.
--   Miss 1 = 20% of bounty, Miss 2 = 50% of bounty, Miss 3 = BUST.
--   Also busts early if a penalty is bigger than the remaining budget (you spent
--   too much on letters to cover it). Penalties come from BUDGET only — a wrong
--   guess never chips the Run Bankroll; only a bust (existing forfeit) loses it.
-- Adds board flags for the UI: bust_on_wrong, wrong_next_cost, wrong_guess_num,
-- wrong_pen1/2 (so the ⓘ breakdown + red "Wrong = bust" confirm can render live).
-- ============================================================================
BEGIN;

-- Penalty for the n-th wrong guess of a puzzle, rounded to $10. NULL = auto-bust (3rd+).
CREATE OR REPLACE FUNCTION public._cg_wrong_pen(p_bounty int, p_n int)
 RETURNS int LANGUAGE sql IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_n <= 1 THEN (round(GREATEST(0, p_bounty) * 0.20 / 10.0) * 10)::int
    WHEN p_n = 2 THEN (round(GREATEST(0, p_bounty) * 0.50 / 10.0) * 10)::int
    ELSE NULL          -- 3rd wrong guess (or beyond) = bust, no survivable penalty
  END;
$function$;
REVOKE EXECUTE ON FUNCTION public._cg_wrong_pen(int, int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._cg_wrong_pen(int, int) FROM anon;

CREATE OR REPLACE FUNCTION public.climb_submit_guess(p_guess jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}';
  v_all BOOLEAN := true; pos INT; v_ch TEXT;
  v_tier JSONB; v_k NUMERIC; v_stake INT; v_bounty INT; v_budget_left INT; v_n INT; v_pen INT; v_shield JSONB;
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
  -- Escalating, budget-only penalty tied to the bounty: miss 1 = 20%, miss 2 = 50%,
  -- miss 3 (or a penalty the budget can't cover) = BUST. Run bankroll is never chipped.
  v_tier := public._cg_tier(cs.tier);
  v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_stake := COALESCE((v_tier->>'stake')::int, 1);
  v_bounty := round(public._climb_bounty(cs.puzzle_id, v_k) * v_stake * cs.heat_x100 / 100.0)::int;
  v_budget_left := GREATEST(0, v_bounty - cs.spent);
  v_n := cs.wrong_count + 1;                          -- which wrong guess this is
  v_pen := public._cg_wrong_pen(v_bounty, v_n);       -- NULL on the 3rd+ (auto-bust)
  IF v_pen IS NULL OR v_pen > v_budget_left THEN
    -- Fatal: 3rd strike, or the penalty can't be covered by budget → bust (shield may save).
    v_shield := public._cg_try_shield(v_uid);
    IF v_shield IS NOT NULL THEN RETURN v_shield; END IF;
    RETURN public._cg_bust(v_uid);
  END IF;
  UPDATE public.climb_state SET
    spent = cs.spent + v_pen,                         -- budget only, never bankroll
    wrong_count = cs.wrong_count + 1,
    wrong_spent = cs.wrong_spent + v_pen,
    pups_locked = true, updated_at = now()
    WHERE user_id = v_uid;
  RETURN public._climb_board(v_uid);
END; $function$;

CREATE OR REPLACE FUNCTION public._climb_board(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_state TEXT; v_board JSONB; v_tier JSONB;
  v_k NUMERIC; v_stake INT; v_cap INT; v_bounty INT; v_budget_left INT; v_cheapest INT; v_balance INT;
  v_solve_reward INT; v_next_cat TEXT; v_next_bounty INT;
  v_wrong_n INT; v_wrong_next INT; v_pen1 INT; v_pen2 INT; v_bust_on_wrong BOOLEAN;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_tier := public._cg_tier(cs.tier);
  v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_stake := COALESCE((v_tier->>'stake')::int, 1);
  v_cap := COALESCE((v_tier->>'heat_cap')::int, 250);
  SELECT upper(phrase), category, COALESCE(subcategory,'') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_state := CASE cs.state WHEN 'solved' THEN 'won' WHEN 'busted' THEN 'lost' ELSE 'active' END;
  v_bounty := round(public._climb_bounty(cs.puzzle_id, v_k) * v_stake * cs.heat_x100 / 100.0)::int;
  v_budget_left := CASE WHEN cs.state = 'active' THEN GREATEST(0, v_bounty - cs.spent) ELSE 0 END;
  v_cheapest := public._cg_cheapest(cs);
  v_balance := cs.bankroll + v_budget_left;
  v_solve_reward := v_budget_left;
  -- Wrong-solve schedule for the UI (ⓘ breakdown + red "Wrong = bust" confirm).
  v_wrong_n := cs.wrong_count + 1;
  v_wrong_next := public._cg_wrong_pen(v_bounty, v_wrong_n);      -- NULL = next wrong busts
  v_pen1 := public._cg_wrong_pen(v_bounty, 1);
  v_pen2 := public._cg_wrong_pen(v_bounty, 2);
  v_bust_on_wrong := (cs.state = 'active' AND (v_wrong_next IS NULL OR v_wrong_next > v_budget_left));
  IF cs.state = 'solved' AND cs.next_puzzle_id IS NOT NULL THEN
    SELECT category INTO v_next_cat FROM public.daily_puzzles WHERE id = cs.next_puzzle_id;
    v_next_bounty := round(public._climb_bounty(cs.next_puzzle_id, v_k) * v_stake * LEAST(v_cap, cs.heat_x100 + 10) / 100.0)::int;
  END IF;
  v_board := public._daily_board(v_phrase, v_state, cs.bankroll::int, 99, cs.revealed_positions, cs.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('climb', jsonb_build_object(
    'wallet', cs.bankroll, 'bankroll', cs.bankroll, 'balance', v_balance,
    'bounty', v_bounty, 'budget_left', v_budget_left, 'solve_reward', v_solve_reward, 'spent', cs.spent,
    'heat', cs.heat_x100, 'heat_cap', v_cap, 'tier', cs.tier, 'buy_in', cs.buy_in,
    'tier_label', v_tier->>'label', 'stake', v_stake, 'cheapest', v_cheapest,
    'must_guess', (cs.state = 'active' AND (v_cheapest IS NULL OR v_budget_left < v_cheapest)),
    -- Wrong-solve UI: is the NEXT wrong guess fatal, what does it cost, and the schedule.
    'bust_on_wrong', v_bust_on_wrong, 'wrong_next_cost', v_wrong_next, 'wrong_guess_num', v_wrong_n,
    'wrong_pen1', v_pen1, 'wrong_pen2', v_pen2,
    'position', cs.position, 'last_gain', cs.last_gain, 'state', cs.state,
    'pups_locked', cs.pups_locked, 'equipped', to_jsonb(cs.active_powerups), 'half_off_left', cs.half_off_left,
    'run_solves', cs.run_solves, 'run_profit', cs.bankroll - cs.buy_in,
    'run_interest', cs.run_interest, 'run_spent', cs.run_spent,
    'wrong_count', cs.wrong_count, 'wrong_spent', cs.wrong_spent,
    'last_interest', cs.last_interest,
    'next_bounty', v_next_bounty, 'next_category', v_next_cat));
END; $function$;

COMMIT;
