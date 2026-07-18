-- Cash Game receipt: expose PER-PUZZLE interest so the "this solve" math is explicit (2026-07-18).
--
-- Interest is baked INTO the bounty (value = base_bounty × heat). The receipt showed only the
-- heat-inflated "Puzzle value $403", then a DISCONNECTED cumulative "Interest earned +$83" down
-- in the run section — using the post-solve (next puzzle's) heat %, no less. Players couldn't see
-- that the interest was already inside the value, so nothing reconciled.
--
-- Fix: surface this puzzle's interest ($ and it derives its own %) so the slip can show the full
-- build-up as one equation:  Base value + Interest = Puzzle value − Letters − Wrong = Kept.
-- Track last_interest per puzzle (= v_interest at solve), reset each puzzle, expose on the board.

ALTER TABLE public.climb_state
  ADD COLUMN IF NOT EXISTS last_interest bigint NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public._climb_resolve(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_won BOOLEAN; v_tier JSONB; v_k NUMERIC; v_stake INT; v_cap INT;
  v_bounty INT; v_keep INT; v_cat TEXT; v_time INT; v_next UUID;
  v_eff NUMERIC; v_ctier TEXT; v_cbonus INT; v_gain INT;
  v_base INT; v_interest INT;
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
    -- Interest dollars THIS puzzle = bounty-with-heat minus the base bounty (heat = 100).
    v_base := round(public._climb_bounty(cs.puzzle_id, v_k) * v_stake)::int;
    v_interest := GREATEST(0, v_bounty - v_base);
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
      run_solves = cs.run_solves + 1,
      run_interest = cs.run_interest + v_interest,   -- accumulate interest $ earned this run
      run_spent = cs.run_spent + cs.spent,           -- accumulate total spent this run
      last_interest = v_interest,                    -- ← THIS puzzle's interest $ (for the slip)
      next_puzzle_id = v_next, updated_at = now() WHERE user_id = p_uid;
    PERFORM public._record_category_solve(p_uid, v_cat);
    PERFORM public._log_game_result(p_uid,'climb','won', cs.puzzle_id, v_cat, 1, 1, cs.spent::int, v_keep, v_time);
  ELSE
    UPDATE public.climb_state SET state = 'active', updated_at = now() WHERE user_id = p_uid;
  END IF;
  RETURN public._climb_board(p_uid);
END; $function$;

-- Reset the per-puzzle interest when a new puzzle loads (alongside spent/wrong counters).
CREATE OR REPLACE FUNCTION public.climb_next()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_pid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_next: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state <> 'solved' THEN RETURN public._climb_board(v_uid); END IF;
  v_pid := COALESCE(cs.next_puzzle_id, public._pick_casual(v_uid, null, cs.puzzle_id, 0));
  IF v_pid IS NULL THEN RETURN public._climb_board(v_uid); END IF;
  UPDATE public.climb_state SET position = cs.position + 1, puzzle_id = v_pid, revealed_positions = '{}',
    incorrect_letters = '{}', spent = 0, last_gain = 0, active_powerups = '{}', next_puzzle_id = NULL,
    wrong_count = 0, wrong_spent = 0, last_interest = 0,
    pups_locked = false, state = 'active', puzzle_started_at = now(), updated_at = now() WHERE user_id = v_uid;
  PERFORM public._mark_seen(v_uid, v_pid);
  RETURN public._climb_board(v_uid);
END; $function$;

-- Expose last_interest on the board.
CREATE OR REPLACE FUNCTION public._climb_board(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_state TEXT; v_board JSONB; v_tier JSONB;
  v_k NUMERIC; v_stake INT; v_cap INT; v_bounty INT; v_budget_left INT; v_cheapest INT; v_balance INT;
  v_solve_reward INT; v_next_cat TEXT; v_next_bounty INT;
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
    'must_guess', (cs.state = 'active' AND (v_cheapest IS NULL OR v_balance < v_cheapest)),
    'position', cs.position, 'last_gain', cs.last_gain, 'state', cs.state,
    'pups_locked', cs.pups_locked, 'equipped', to_jsonb(cs.active_powerups),
    'run_solves', cs.run_solves, 'run_profit', cs.bankroll - cs.buy_in,
    'run_interest', cs.run_interest, 'run_spent', cs.run_spent,
    'wrong_count', cs.wrong_count, 'wrong_spent', cs.wrong_spent,
    'last_interest', cs.last_interest,                              -- ← this puzzle's interest $
    'next_bounty', v_next_bounty, 'next_category', v_next_cat));
END; $function$;

REVOKE EXECUTE ON FUNCTION public._climb_board(uuid) FROM PUBLIC, anon, authenticated;
