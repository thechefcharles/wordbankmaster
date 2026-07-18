-- Cash Game receipt: run-total "interest earned $" + "spent this run" (2026-07-17).
--
-- The receipt's "Interest · Solves +26% · 3" line only showed the RATE, and the +% shown is
-- actually next puzzle's heat (heat ticks up each solve), so it can't be turned into dollars
-- client-side. And run-total spend wasn't tracked (only the current puzzle's `spent`).
--
-- Add two run-cumulative counters on climb_state, accumulated on each solve:
--   run_interest = Σ (bounty-with-heat − base bounty)  → real dollars interest earned this run
--   run_spent    = Σ (this puzzle's spend)             → total spent this run (letters+guess pen.)
-- cashgame_start already DELETEs + re-INSERTs a fresh row, so a new run resets these to the
-- column default (0) automatically — no change needed there.

ALTER TABLE public.climb_state
  ADD COLUMN IF NOT EXISTS run_interest bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS run_spent    bigint NOT NULL DEFAULT 0;

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
      run_interest = cs.run_interest + v_interest,   -- ← accumulate interest $ earned this run
      run_spent = cs.run_spent + cs.spent,           -- ← accumulate total spent this run
      next_puzzle_id = v_next, updated_at = now() WHERE user_id = p_uid;
    PERFORM public._record_category_solve(p_uid, v_cat);
    PERFORM public._log_game_result(p_uid,'climb','won', cs.puzzle_id, v_cat, 1, 1, cs.spent::int, v_keep, v_time);
  ELSE
    UPDATE public.climb_state SET state = 'active', updated_at = now() WHERE user_id = p_uid;
  END IF;
  RETURN public._climb_board(p_uid);
END; $function$;

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
  -- Heat now multiplies the bounty as it's injected (one-number model).
  v_bounty := round(public._climb_bounty(cs.puzzle_id, v_k) * v_stake * cs.heat_x100 / 100.0)::int;
  -- Only an ACTIVE puzzle has a spendable budget; once solved it's folded into bankroll
  -- (its budget must NOT be re-counted into the Balance, else it double-counts at the bumped heat).
  v_budget_left := CASE WHEN cs.state = 'active' THEN GREATEST(0, v_bounty - cs.spent) ELSE 0 END;
  v_cheapest := public._cg_cheapest(cs);
  v_balance := cs.bankroll + v_budget_left;             -- the ONE number the HUD shows
  v_solve_reward := v_budget_left;                      -- back-compat: what solving secures
  -- Between-round peek: next puzzle's bounty at the heat you'll have (heat+10), + its category.
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
    'run_interest', cs.run_interest, 'run_spent', cs.run_spent,   -- ← new run totals
    'next_bounty', v_next_bounty, 'next_category', v_next_cat));
END; $function$;

-- Internal helpers — keep them un-callable by clients (audit convention).
REVOKE EXECUTE ON FUNCTION public._climb_resolve(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._climb_board(uuid) FROM PUBLIC, anon, authenticated;
