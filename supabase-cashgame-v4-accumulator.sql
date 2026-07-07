-- Cash Game V4: the Accumulator — "Daily, strung into a banking run."
--
-- Reframes the run so the cash-out finally MATTERS:
--   • Buy-in is an ANTE (gone at start). Your Wallet starts at $0.
--   • Each puzzle hands you a BUDGET = k × Σ letter-costs × stake (k<1, so you can never
--     buy your way to certainty). You spend the BUDGET on letters — the Wallet is untouched.
--   • Solve → keep the leftover budget × heat, banked into your Wallet. Heat +0.1.
--   • Cash out ANYTIME → bank the Wallet, reveal the answer, end the run (profitable cash-out
--     extends your run streak). This is the safe bail.
--   • A WRONG GUESS wipes the Wallet ($0) and ends the run. Because you can always cash out
--     first, every wrong guess is a chosen gamble → fair. Max downside = the ante.
--   • No skip — cash-out is the graceful exit.
-- Supersedes the V3 penalty-cap + final-guess (those patched the old single-pool model).
-- Spec: chat decision 2026-07-07. PITR point logged before apply.

BEGIN;

-- Start: debit the ANTE, seed an EMPTY Wallet (bankroll = 0). buy_in stores the ante.
CREATE OR REPLACE FUNCTION public.cashgame_start(p_tier text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_tier JSONB; v_buy BIGINT; v_bank BIGINT; v_pid UUID; v_t text := lower(COALESCE(p_tier,''));
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'cashgame_start: not authenticated'; END IF;
  v_tier := public._cg_tier(v_t);
  IF v_tier IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'bad_tier'); END IF;
  IF NOT public._cg_unlocked(v_uid, v_t) THEN RETURN jsonb_build_object('ok', false, 'reason', 'locked'); END IF;
  IF EXISTS (SELECT 1 FROM public.climb_state WHERE user_id = v_uid AND state IN ('active','solved')) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'run_active'); END IF;
  PERFORM public._ensure_bank(v_uid);
  v_buy := (v_tier->>'buy_in')::bigint;
  SELECT bank INTO v_bank FROM public.profiles WHERE id = v_uid;
  IF v_bank < v_buy THEN RETURN jsonb_build_object('ok', false, 'reason', 'insufficient', 'buy_in', v_buy, 'bank', v_bank); END IF;
  v_pid := public._pick_casual(v_uid, null, null, 0);
  IF v_pid IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_puzzles'); END IF;
  PERFORM public._bank_credit(v_uid, -v_buy, 'cashgame_buyin');       -- ante leaves your Bank Account
  DELETE FROM public.climb_state WHERE user_id = v_uid;
  INSERT INTO public.climb_state(user_id, position, puzzle_id, bankroll, tier, buy_in, heat_x100, state)
    VALUES (v_uid, 1, v_pid, 0, v_t, v_buy, 100, 'active');           -- Wallet starts at $0
  PERFORM public._mark_seen(v_uid, v_pid);
  RETURN public._climb_board(v_uid) || jsonb_build_object('ok', true);
END; $function$;

-- Buy a letter: spend from the PUZZLE BUDGET (bounty − spent), NOT the Wallet.
CREATE OR REPLACE FUNCTION public.climb_buy_letter(p_letter text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_letter TEXT; v_cost INT; v_stake INT;
  v_k NUMERIC; v_bounty INT; v_budget_left INT; v_positions INT[];
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
  v_bounty := public._climb_bounty(cs.puzzle_id, v_k) * v_stake;
  v_budget_left := v_bounty - cs.spent;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  IF v_letter = ANY(cs.incorrect_letters) OR v_budget_left < v_cost THEN RETURN public._climb_board(v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1,1) = v_letter;
  IF v_positions IS NOT NULL AND v_positions <@ cs.revealed_positions THEN RETURN public._climb_board(v_uid); END IF;
  IF v_positions IS NULL THEN cs.incorrect_letters := array_append(cs.incorrect_letters, v_letter);
  ELSE cs.revealed_positions := ARRAY(SELECT DISTINCT unnest(cs.revealed_positions || v_positions) ORDER BY 1); END IF;
  UPDATE public.climb_state SET revealed_positions = cs.revealed_positions,
    incorrect_letters = cs.incorrect_letters, spent = cs.spent + v_cost, pups_locked = true, updated_at = now() WHERE user_id = v_uid;
  RETURN public._climb_resolve(v_uid);
END; $function$;

-- Submit a guess: all-correct → solve. Anything else → WRONG → wipe the Wallet, end the run.
CREATE OR REPLACE FUNCTION public.climb_submit_guess(p_guess jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}';
  v_all BOOLEAN := true; pos INT; v_ch TEXT;
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
  RETURN public._cg_bust(v_uid);    -- wrong guess → wipe the Wallet, reveal the answer, run over
END; $function$;

-- Resolve after a move: solve → keep the leftover BUDGET × heat, banked into the Wallet.
CREATE OR REPLACE FUNCTION public._climb_resolve(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_won BOOLEAN; v_tier JSONB; v_k NUMERIC; v_stake INT; v_cap INT;
  v_bounty INT; v_keep INT; v_payout INT; v_cat TEXT; v_time INT;
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
    v_keep := GREATEST(0, v_bounty - cs.spent);                      -- leftover budget you keep
    v_payout := round(v_keep * cs.heat_x100 / 100.0)::int;           -- × heat → into the Wallet
    v_time := LEAST(GREATEST(EXTRACT(epoch FROM (now() - COALESCE(cs.puzzle_started_at, cs.updated_at))) * 1000, 0), 1800000)::int;
    UPDATE public.climb_state SET state = 'solved', last_gain = v_payout,
      bankroll = cs.bankroll + v_payout,
      heat_x100 = LEAST(v_cap, cs.heat_x100 + 10),
      run_solves = cs.run_solves + 1, updated_at = now() WHERE user_id = p_uid;
    PERFORM public._log_game_result(p_uid,'climb','won', cs.puzzle_id, v_cat, 1, 1, cs.spent::int, v_payout, v_time);
  ELSE
    UPDATE public.climb_state SET state = 'active', updated_at = now() WHERE user_id = p_uid;
  END IF;
  RETURN public._climb_board(p_uid);
END; $function$;

-- Board: Wallet (accumulated) + this puzzle's budget_left + solve_reward preview + must_guess.
CREATE OR REPLACE FUNCTION public._climb_board(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_state TEXT; v_board JSONB; v_tier JSONB;
  v_k NUMERIC; v_stake INT; v_bounty INT; v_budget_left INT; v_cheapest INT; v_solve_reward INT;
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
  -- Base board shows the WALLET (accumulated winnings) as the headline number.
  v_board := public._daily_board(v_phrase, v_state, cs.bankroll::int, 99, cs.revealed_positions, cs.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('climb', jsonb_build_object(
    'wallet', cs.bankroll, 'bankroll', cs.bankroll,
    'bounty', v_bounty, 'budget_left', v_budget_left, 'solve_reward', v_solve_reward, 'spent', cs.spent,
    'heat', cs.heat_x100, 'heat_cap', (v_tier->>'heat_cap')::int, 'tier', cs.tier, 'buy_in', cs.buy_in,
    'tier_label', v_tier->>'label', 'stake', v_stake, 'cheapest', v_cheapest,
    'must_guess', (cs.state = 'active' AND (v_cheapest IS NULL OR v_budget_left < v_cheapest)),
    'position', cs.position, 'last_gain', cs.last_gain, 'state', cs.state,
    'pups_locked', cs.pups_locked, 'equipped', to_jsonb(cs.active_powerups),
    'run_solves', cs.run_solves, 'run_profit', cs.bankroll - cs.buy_in));
END; $function$;

-- Cash out: bank the Wallet, reveal the answer, extend the streak if profitable, end the run.
CREATE OR REPLACE FUNCTION public.cashgame_cashout()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_profit BIGINT; v_mult INT; v_wins jsonb; v_streak INT; v_bestrs INT; v_phrase TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'cashgame_cashout: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state NOT IN ('active','solved') THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_run'); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_profit := cs.bankroll - cs.buy_in;                              -- Wallet banked minus the ante
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

-- Bust (wrong guess) = wipe the Wallet, reveal the answer, run over. Carries the wiped amount.
CREATE OR REPLACE FUNCTION public._cg_bust(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase text; v_all int[]; v_cat text; v_board jsonb; v_wiped bigint;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid FOR UPDATE;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_wiped := cs.bankroll;                                            -- accumulated Wallet, now lost
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  SELECT array_agg(g.i) INTO v_all FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1,1) <> ' ';
  UPDATE public.profiles SET cg_run_streak = 0, cg_lifetime_net = COALESCE(cg_lifetime_net,0) - cs.buy_in WHERE id = p_uid;
  PERFORM public._log_game_result(p_uid,'climb','lost', cs.puzzle_id, v_cat, 0, 1, cs.spent::int, 0);
  v_board := public._daily_board(v_phrase, 'lost', 0, 99, COALESCE(v_all,'{}'), cs.incorrect_letters, v_cat, '')
    || jsonb_build_object('climb', jsonb_build_object('wallet', 0, 'bankroll', 0, 'state', 'busted', 'tier', cs.tier,
         'buy_in', cs.buy_in, 'run_solves', cs.run_solves, 'busted', true, 'wiped', v_wiped, 'position', cs.position));
  DELETE FROM public.climb_state WHERE user_id = p_uid;
  RETURN v_board;
END; $function$;

-- Skip retired in V4 — cash-out is the graceful bail. No-op (returns the board unchanged).
CREATE OR REPLACE FUNCTION public.climb_skip()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
BEGIN RETURN public._climb_board(auth.uid()); END; $function$;

COMMIT;
