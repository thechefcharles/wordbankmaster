-- ============================================================================
-- Phase 3 — Cash Game: bank only BETWEEN puzzles + next-puzzle peek.
-- (spec: docs/superpowers/specs/2026-07-09-economy-rework-cashgame-challenge.md)
--
-- Today cashgame_cashout allows state IN ('active','solved') — i.e. you can bank
-- MID-puzzle, a free penalty-free cop-out when you don't know the answer. Fix:
--   * cashout is allowed ONLY at the between-puzzle decision point (state='solved').
--     Mid-puzzle ('active') your only outs are solve or bust.
--   * On solve we PRE-PICK the next puzzle and store climb_state.next_puzzle_id, so
--     the "Bank or Push" peek (next bounty + category) is truthful; climb_next deals
--     that exact puzzle.
-- No new economy math — the 'solved' between-state already exists. PITR logged.
-- ============================================================================
BEGIN;

ALTER TABLE public.climb_state ADD COLUMN IF NOT EXISTS next_puzzle_id uuid;

-- 1) On solve: bank leftover (unchanged) + PRE-PICK the next puzzle for the peek.
CREATE OR REPLACE FUNCTION public._climb_resolve(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_won BOOLEAN; v_tier JSONB; v_k NUMERIC; v_stake INT; v_cap INT;
  v_bounty INT; v_keep INT; v_payout INT; v_cat TEXT; v_time INT; v_next UUID;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF cs.state <> 'active' THEN RETURN public._climb_board(p_uid); END IF;
  v_tier := public._cg_tier(cs.tier); v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_cap := COALESCE((v_tier->>'heat_cap')::int, 250); v_stake := COALESCE((v_tier->>'stake')::int, 1);
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(cs.revealed_positions)));
  IF v_won THEN
    v_bounty := public._climb_bounty(cs.puzzle_id, v_k) * v_stake;
    v_keep := GREATEST(0, v_bounty - cs.spent);
    v_payout := round(v_keep * cs.heat_x100 / 100.0)::int;
    v_time := LEAST(GREATEST(EXTRACT(epoch FROM (now() - COALESCE(cs.puzzle_started_at, cs.updated_at))) * 1000, 0), 1800000)::int;
    -- Pre-pick the next puzzle now so the between-round peek matches what you'll get.
    v_next := public._pick_casual(p_uid, null, cs.puzzle_id, 0);
    UPDATE public.climb_state SET state = 'solved', last_gain = v_payout,
      bankroll = cs.bankroll + v_payout,
      heat_x100 = LEAST(v_cap, cs.heat_x100 + 10),
      run_solves = cs.run_solves + 1, next_puzzle_id = v_next, updated_at = now() WHERE user_id = p_uid;
    PERFORM public._log_game_result(p_uid,'climb','won', cs.puzzle_id, v_cat, 1, 1, cs.spent::int, v_payout, v_time);
  ELSE
    UPDATE public.climb_state SET state = 'active', updated_at = now() WHERE user_id = p_uid;
  END IF;
  RETURN public._climb_board(p_uid);
END; $function$;

-- 2) Push: deal the pre-picked next puzzle (fallback to a fresh pick), clear it.
CREATE OR REPLACE FUNCTION public.climb_next()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_pid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_next: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state <> 'solved' THEN RETURN public._climb_board(v_uid); END IF;
  v_pid := COALESCE(cs.next_puzzle_id, public._pick_casual(v_uid, null, cs.puzzle_id, 0));
  IF v_pid IS NULL THEN RETURN public._climb_board(v_uid); END IF;
  UPDATE public.climb_state SET position = cs.position + 1, puzzle_id = v_pid, revealed_positions = '{}',
    incorrect_letters = '{}', spent = 0, last_gain = 0, active_powerups = '{}', next_puzzle_id = NULL,
    pups_locked = false, state = 'active', puzzle_started_at = now(), updated_at = now() WHERE user_id = v_uid;
  PERFORM public._mark_seen(v_uid, v_pid);
  RETURN public._climb_board(v_uid);
END; $function$;

-- 3) Board: expose the next puzzle's bounty + category as the between-round peek.
CREATE OR REPLACE FUNCTION public._climb_board(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_state TEXT; v_board JSONB; v_tier JSONB;
  v_k NUMERIC; v_stake INT; v_bounty INT; v_budget_left INT; v_cheapest INT; v_solve_reward INT;
  v_next_cat TEXT; v_next_bounty INT;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_tier := public._cg_tier(cs.tier);
  v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_stake := COALESCE((v_tier->>'stake')::int, 1);
  SELECT upper(phrase), category, COALESCE(subcategory,'') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_state := CASE cs.state WHEN 'solved' THEN 'won' WHEN 'busted' THEN 'lost' ELSE 'active' END;
  v_bounty := public._climb_bounty(cs.puzzle_id, v_k) * v_stake;
  v_budget_left := GREATEST(0, v_bounty - cs.spent);
  v_cheapest := public._cg_cheapest(cs);
  v_solve_reward := round(v_budget_left * cs.heat_x100 / 100.0)::int;
  -- Between-round peek: what the next puzzle is worth + its category (no phrase/answer).
  IF cs.state = 'solved' AND cs.next_puzzle_id IS NOT NULL THEN
    SELECT category INTO v_next_cat FROM public.daily_puzzles WHERE id = cs.next_puzzle_id;
    v_next_bounty := public._climb_bounty(cs.next_puzzle_id, v_k) * v_stake;
  END IF;
  v_board := public._daily_board(v_phrase, v_state, cs.bankroll::int, 99, cs.revealed_positions, cs.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('climb', jsonb_build_object(
    'wallet', cs.bankroll, 'bankroll', cs.bankroll,
    'bounty', v_bounty, 'budget_left', v_budget_left, 'solve_reward', v_solve_reward, 'spent', cs.spent,
    'heat', cs.heat_x100, 'heat_cap', (v_tier->>'heat_cap')::int, 'tier', cs.tier, 'buy_in', cs.buy_in,
    'tier_label', v_tier->>'label', 'stake', v_stake, 'cheapest', v_cheapest,
    'must_guess', (cs.state = 'active' AND (v_cheapest IS NULL OR v_budget_left < v_cheapest)),
    'position', cs.position, 'last_gain', cs.last_gain, 'state', cs.state,
    'pups_locked', cs.pups_locked, 'equipped', to_jsonb(cs.active_powerups),
    'run_solves', cs.run_solves, 'run_profit', cs.bankroll - cs.buy_in,
    'next_bounty', v_next_bounty, 'next_category', v_next_cat));
END; $function$;

-- 4) Cashout: allowed ONLY between puzzles (state='solved'); mid-puzzle = solve or bust.
CREATE OR REPLACE FUNCTION public.cashgame_cashout()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_profit BIGINT; v_mult INT; v_wins jsonb; v_streak INT; v_bestrs INT; v_phrase TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'cashgame_cashout: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_run'); END IF;
  IF cs.state <> 'solved' THEN RETURN jsonb_build_object('ok', false, 'reason', 'in_puzzle'); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_profit := cs.bankroll - cs.buy_in;
  v_mult := CASE WHEN cs.buy_in > 0 THEN round(cs.bankroll * 100.0 / cs.buy_in)::int ELSE 0 END;
  IF cs.bankroll > 0 THEN PERFORM public._bank_credit(v_uid, cs.bankroll, 'cashgame_cashout'); END IF;
  SELECT COALESCE(cg_wins,'{}'::jsonb), COALESCE(cg_run_streak,0), COALESCE(cg_best_run_streak,0)
    INTO v_wins, v_streak, v_bestrs FROM public.profiles WHERE id = v_uid;
  IF v_profit > 0 THEN
    v_wins := jsonb_set(v_wins, ARRAY[cs.tier], to_jsonb(COALESCE((v_wins->>cs.tier)::int,0) + 1), true);
    v_streak := v_streak + 1;
  ELSE
    v_streak := 0;
  END IF;
  UPDATE public.profiles SET
    cg_wins = v_wins,
    cg_run_streak = v_streak,
    cg_best_run_streak = GREATEST(v_bestrs, v_streak),
    cg_best_run = GREATEST(COALESCE(cg_best_run,0), cs.bankroll),
    cg_best_multiple_x100 = GREATEST(COALESCE(cg_best_multiple_x100,0), v_mult),
    cg_best_heat_x100 = GREATEST(COALESCE(cg_best_heat_x100,100), cs.heat_x100),
    cg_lifetime_net = COALESCE(cg_lifetime_net,0) + v_profit
    WHERE id = v_uid;
  DELETE FROM public.climb_state WHERE user_id = v_uid;
  RETURN jsonb_build_object('ok', true, 'banked', cs.bankroll, 'buy_in', cs.buy_in, 'profit', v_profit,
    'multiple_x100', v_mult, 'solves', cs.run_solves, 'tier', cs.tier, 'heat', cs.heat_x100, 'phrase', v_phrase);
END; $function$;

COMMIT;
