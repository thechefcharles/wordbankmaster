-- Cash Game receipt: track WRONG solves per puzzle (2026-07-18).
--
-- The receipt's "Solves ×N −$run_spent" line conflated the count of SUCCESSFUL solves
-- with total run spend, which reads like "those 4 solves cost $130". The player wants
-- the per-puzzle breakdown of what WRONG guesses cost. So track, per puzzle:
--   wrong_count = number of wrong guesses on the current puzzle
--   wrong_spent = $ drained by those wrong guesses (the budget-side penalty, so the
--                 receipt equation stays exact: value − letters − wrong = kept)
-- Both reset when a new puzzle loads (climb_next); a fresh run INSERTs defaults (0).

ALTER TABLE public.climb_state
  ADD COLUMN IF NOT EXISTS wrong_count int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS wrong_spent int NOT NULL DEFAULT 0;

-- ── Wrong-guess tracking on submit ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.climb_submit_guess(p_guess jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}';
  v_all BOOLEAN := true; pos INT; v_ch TEXT;
  v_tier JSONB; v_k NUMERIC; v_stake INT; v_bounty INT; v_budget_left INT; v_cheapest INT; v_pen INT; v_add INT; v_shield JSONB;
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
  IF v_cheapest IS NULL OR (cs.bankroll + v_budget_left) < v_cheapest THEN
    -- Out of budget: this was your last guess → bust — unless a Heat Shield saves you.
    v_shield := public._cg_try_shield(v_uid);
    IF v_shield IS NOT NULL THEN RETURN v_shield; END IF;
    RETURN public._cg_bust(v_uid);
  END IF;
  -- Still have budget: drain a penalty (≥ one letter, or 20% of what's left) and keep playing.
  v_pen := LEAST(cs.bankroll + v_budget_left, GREATEST(v_cheapest, (round(0.2 * v_budget_left / 10.0) * 10)::int));
  v_add := LEAST(v_pen, GREATEST(0, v_budget_left));   -- budget-side portion (goes into `spent`)
  UPDATE public.climb_state SET
    spent = cs.spent + v_add,
    wrong_count = cs.wrong_count + 1,                  -- ← count this wrong guess
    wrong_spent = cs.wrong_spent + v_add,              -- ← $ this wrong guess cost (budget side)
    bankroll = cs.bankroll - GREATEST(0, v_pen - v_add),
    pups_locked = true, updated_at = now()
    WHERE user_id = v_uid;
  RETURN public._climb_board(v_uid);
END; $function$;

-- ── Reset the per-puzzle wrong counters when a new puzzle loads ─────────────
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
    wrong_count = 0, wrong_spent = 0,
    pups_locked = false, state = 'active', puzzle_started_at = now(), updated_at = now() WHERE user_id = v_uid;
  PERFORM public._mark_seen(v_uid, v_pid);
  RETURN public._climb_board(v_uid);
END; $function$;

-- ── Expose the per-puzzle wrong counters on the board ──────────────────────
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
    'run_interest', cs.run_interest, 'run_spent', cs.run_spent,
    'wrong_count', cs.wrong_count, 'wrong_spent', cs.wrong_spent,   -- ← per-puzzle wrong solves
    'next_bounty', v_next_bounty, 'next_category', v_next_cat));
END; $function$;

-- Internal helpers stay un-callable by clients; client RPCs stay granted to authenticated.
REVOKE EXECUTE ON FUNCTION public._climb_board(uuid) FROM PUBLIC, anon, authenticated;
