-- Fix Cash Game next-puzzle peek: heat is bumped on SOLVE (variable v_gain), and climb_next
-- does NOT change heat, so the next puzzle plays at cs.heat_x100 — not heat+10. The peek was
-- adding a spurious +10, overstating the next bounty vs what actually renders.
BEGIN;
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
    v_next_bounty := round(public._climb_bounty(cs.next_puzzle_id, v_k) * v_stake * cs.heat_x100 / 100.0)::int;
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
