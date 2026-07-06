-- V2 Phase 3: Cash Game V2 — the Tiered-Run redesign.
--
-- Turns the endless global-Cash climb into a contained, tiered BUY-IN RUN:
--   pick a tier → stake a buy-in → grow a run bankroll by solving efficiently →
--   CASH OUT anytime to bank it, or BUST and lose the buy-in.
--   • climb_state.bankroll = the run bankroll (from the buy-in); tier + buy_in stored.
--   • Buying letters + wrong-guess penalties drain the bankroll (never global Cash).
--   • Bounty = round_$10(k_tier × Σ distinct-letter-costs); k drops with tier (0.90→0.55).
--   • Solve → bankroll += bounty × heat; heat +0.1, capped at the tier ceiling (×2.0→×3.0).
--   • Wrong guess → bankroll −= GREATEST($10, round(0.2×bounty/10)×10); stuck (bankroll <
--     cheapest buyable) → one final guess; wrong there → BUST (run ends, buy-in lost).
--   • cashgame_cashout: bank the bankroll to Cash (loan auto-skim applies), record stats + mastery.
--   • Skip → new puzzle, heat resets ×1.0, forfeit spend. Double-or-Nothing retired.
--   • Tiers unlock via mastery (3 profitable cash-outs at the tier below). Loans fund buy-ins.
-- Spec: Notion "Cash Game V2". PITR point logged before apply.

BEGIN;

-- Close the 11 legacy V1 runs (played on global Cash; no buy-in to migrate).
DELETE FROM public.climb_state;

-- Run-model + stats columns.
ALTER TABLE public.climb_state ADD COLUMN IF NOT EXISTS bankroll bigint;
ALTER TABLE public.climb_state ADD COLUMN IF NOT EXISTS tier text;
ALTER TABLE public.climb_state ADD COLUMN IF NOT EXISTS buy_in bigint;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS cg_wins jsonb DEFAULT '{}'::jsonb;      -- {tier: profitable_cashouts} → mastery
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS cg_run_streak int DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS cg_best_run_streak int DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS cg_best_run bigint DEFAULT 0;           -- biggest cash-out
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS cg_best_multiple_x100 int DEFAULT 0;    -- best cash-out ÷ buy-in
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS cg_best_heat_x100 int DEFAULT 100;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS cg_lifetime_net bigint DEFAULT 0;       -- winnings − buy-ins

-- Tier config: buy-in, k (bounty factor), heat ceiling (×100).
CREATE OR REPLACE FUNCTION public._cg_tier(p_tier text)
 RETURNS jsonb LANGUAGE sql IMMUTABLE
AS $function$
  SELECT CASE lower(p_tier)
    WHEN 'micro'  THEN jsonb_build_object('buy_in', 100,   'k', 0.90, 'heat_cap', 200, 'label', '🪙 Micro',  'order', 1)
    WHEN 'bronze' THEN jsonb_build_object('buy_in', 500,   'k', 0.85, 'heat_cap', 250, 'label', '🥉 Bronze', 'order', 2)
    WHEN 'silver' THEN jsonb_build_object('buy_in', 2000,  'k', 0.70, 'heat_cap', 275, 'label', '🥈 Silver', 'order', 3)
    WHEN 'gold'   THEN jsonb_build_object('buy_in', 10000, 'k', 0.55, 'heat_cap', 300, 'label', '🥇 Gold',   'order', 4)
    ELSE NULL END;
$function$;

-- Mastery gate: Micro/Bronze default; Silver after 3 profitable Bronze cash-outs; Gold after 3 Silver.
CREATE OR REPLACE FUNCTION public._cg_unlocked(p_uid uuid, p_tier text)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
AS $function$
  SELECT CASE lower(p_tier)
    WHEN 'micro'  THEN true
    WHEN 'bronze' THEN true
    WHEN 'silver' THEN COALESCE((SELECT (cg_wins->>'bronze')::int FROM public.profiles WHERE id = p_uid), 0) >= 3
    WHEN 'gold'   THEN COALESCE((SELECT (cg_wins->>'silver')::int FROM public.profiles WHERE id = p_uid), 0) >= 3
    ELSE false END;
$function$;

-- Bounty at a given k (per-tier). k < 1 → buying everything loses.
DROP FUNCTION IF EXISTS public._climb_bounty(uuid);
CREATE OR REPLACE FUNCTION public._climb_bounty(p_pid uuid, p_k numeric)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
AS $function$
  SELECT (round(p_k * COALESCE(SUM(public.letter_cost(t.ch)), 0) / 10.0) * 10)::int
  FROM (
    SELECT DISTINCT substr(upper(dp.phrase), g.i + 1, 1) AS ch
    FROM public.daily_puzzles dp, generate_series(0, length(dp.phrase) - 1) g(i)
    WHERE dp.id = p_pid AND substr(upper(dp.phrase), g.i + 1, 1) ~ '[A-Z]'
  ) t;
$function$;

-- Cheapest still-buyable (unrevealed) letter for the current run puzzle (half_off aware).
CREATE OR REPLACE FUNCTION public._climb_cheapest(cs public.climb_state, p_phrase text)
 RETURNS integer LANGUAGE sql STABLE
AS $function$
  SELECT MIN(CASE WHEN 'half_off' = ANY(cs.active_powerups) THEN CEIL(public.letter_cost(t.ch) * 0.5)::int ELSE public.letter_cost(t.ch) END)
  FROM (
    SELECT DISTINCT substr(p_phrase, g.i + 1, 1) AS ch
    FROM generate_series(0, length(p_phrase) - 1) g(i)
    WHERE substr(p_phrase, g.i + 1, 1) ~ '[A-Z]' AND NOT (g.i = ANY(cs.revealed_positions))
  ) t;
$function$;

-- Board: bankroll = the RUN bankroll; carries tier / buy-in / heat ceiling / stuck.
CREATE OR REPLACE FUNCTION public._climb_board(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_state TEXT; v_board JSONB; v_tier JSONB; v_k NUMERIC;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_tier := public._cg_tier(cs.tier);
  v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  SELECT upper(phrase), category, COALESCE(subcategory,'') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_state := CASE cs.state WHEN 'solved' THEN 'won' WHEN 'busted' THEN 'lost' ELSE 'active' END;
  v_board := public._daily_board(v_phrase, v_state, cs.bankroll::int, 99, cs.revealed_positions, cs.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('climb', jsonb_build_object(
    'bankroll', cs.bankroll, 'bounty', public._climb_bounty(cs.puzzle_id, v_k), 'heat', cs.heat_x100,
    'heat_cap', (v_tier->>'heat_cap')::int, 'tier', cs.tier, 'buy_in', cs.buy_in, 'tier_label', v_tier->>'label',
    'spent', cs.spent, 'position', cs.position, 'stuck', cs.state = 'stuck', 'last_gain', cs.last_gain,
    'state', cs.state, 'pups_locked', cs.pups_locked, 'equipped', to_jsonb(cs.active_powerups),
    'run_solves', cs.run_solves, 'run_profit', cs.bankroll - cs.buy_in));
END; $function$;

-- Start a run at a tier: validate unlock + affordability, debit buy-in, seed the bankroll.
CREATE OR REPLACE FUNCTION public.cashgame_start(p_tier text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_tier JSONB; v_buy BIGINT; v_bank BIGINT; v_pid UUID; v_t text := lower(COALESCE(p_tier,''));
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'cashgame_start: not authenticated'; END IF;
  v_tier := public._cg_tier(v_t);
  IF v_tier IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'bad_tier'); END IF;
  IF NOT public._cg_unlocked(v_uid, v_t) THEN RETURN jsonb_build_object('ok', false, 'reason', 'locked'); END IF;
  IF EXISTS (SELECT 1 FROM public.climb_state WHERE user_id = v_uid AND state IN ('active','stuck')) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'run_active'); END IF;
  PERFORM public._ensure_bank(v_uid);
  v_buy := (v_tier->>'buy_in')::bigint;
  SELECT bank INTO v_bank FROM public.profiles WHERE id = v_uid;
  IF v_bank < v_buy THEN RETURN jsonb_build_object('ok', false, 'reason', 'insufficient', 'buy_in', v_buy, 'bank', v_bank); END IF;
  v_pid := public._pick_casual(v_uid, null, null, 0);
  IF v_pid IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_puzzles'); END IF;
  PERFORM public._bank_credit(v_uid, -v_buy, 'cashgame_buyin');       -- stake leaves Cash → the run
  DELETE FROM public.climb_state WHERE user_id = v_uid;              -- clear any finished remnant
  INSERT INTO public.climb_state(user_id, position, puzzle_id, bankroll, tier, buy_in, heat_x100, state)
    VALUES (v_uid, 1, v_pid, v_buy, v_t, v_buy, 100, 'active');
  PERFORM public._mark_seen(v_uid, v_pid);
  RETURN public._climb_board(v_uid) || jsonb_build_object('ok', true);
END; $function$;

-- Deprecated no-arg entry: return the live run if any, else signal the client to pick a tier.
CREATE OR REPLACE FUNCTION public.climb_start()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_board JSONB;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_start: not authenticated'; END IF;
  v_board := public._climb_board(v_uid);
  IF v_board IS NULL THEN RETURN jsonb_build_object('needs_tier', true); END IF;
  RETURN v_board;
END; $function$;

-- Buy a letter: spend from the RUN bankroll (never global Cash).
CREATE OR REPLACE FUNCTION public.climb_buy_letter(p_letter text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_letter TEXT; v_cost INT; v_positions INT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_buy_letter: not authenticated'; END IF;
  v_letter := upper(p_letter); v_cost := public.letter_cost(v_letter);
  IF v_cost IS NULL THEN RAISE EXCEPTION 'climb_buy_letter: invalid letter'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'climb_buy_letter: no run'; END IF;
  IF cs.state NOT IN ('active','stuck') THEN RETURN public._climb_board(v_uid); END IF;
  IF 'half_off' = ANY(cs.active_powerups) THEN v_cost := CEIL(v_cost * 0.5)::int; END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  IF v_letter = ANY(cs.incorrect_letters) OR cs.bankroll < v_cost THEN RETURN public._climb_board(v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1,1) = v_letter;
  IF v_positions IS NOT NULL AND v_positions <@ cs.revealed_positions THEN RETURN public._climb_board(v_uid); END IF;
  cs.bankroll := cs.bankroll - v_cost;
  IF v_positions IS NULL THEN cs.incorrect_letters := array_append(cs.incorrect_letters, v_letter);
  ELSE cs.revealed_positions := ARRAY(SELECT DISTINCT unnest(cs.revealed_positions || v_positions) ORDER BY 1); END IF;
  UPDATE public.climb_state SET bankroll = cs.bankroll, revealed_positions = cs.revealed_positions,
    incorrect_letters = cs.incorrect_letters, spent = cs.spent + v_cost, pups_locked = true, updated_at = now() WHERE user_id = v_uid;
  RETURN public._climb_resolve(v_uid);
END; $function$;

-- Submit a guess: wrong drains the bankroll; stuck + wrong → BUST.
CREATE OR REPLACE FUNCTION public.climb_submit_guess(p_guess jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}';
  v_all BOOLEAN := true; pos INT; v_ch TEXT; v_tier JSONB; v_k NUMERIC; v_bounty INT; v_cheapest INT; v_pen INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_submit_guess: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'climb_submit_guess: no run'; END IF;
  IF cs.state NOT IN ('active','stuck') THEN RETURN public._climb_board(v_uid); END IF;
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
  -- Wrong guess.
  v_tier := public._cg_tier(cs.tier); v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_cheapest := public._climb_cheapest(cs, v_phrase);
  IF v_cheapest IS NOT NULL AND cs.bankroll < v_cheapest THEN
    RETURN public._cg_bust(v_uid);                                   -- stuck + wrong → bust
  END IF;
  v_bounty := public._climb_bounty(cs.puzzle_id, v_k);
  v_pen := GREATEST(10, (round(0.2 * v_bounty / 10.0) * 10)::int);
  cs.bankroll := GREATEST(0, cs.bankroll - v_pen);
  UPDATE public.climb_state SET bankroll = cs.bankroll, updated_at = now() WHERE user_id = v_uid;
  RETURN public._climb_resolve(v_uid);
END; $function$;

-- Resolve after a move: solve grows the bankroll (bounty × heat); else mark stuck if broke.
CREATE OR REPLACE FUNCTION public._climb_resolve(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_won BOOLEAN; v_tier JSONB; v_k NUMERIC; v_cap INT; v_bounty INT; v_payout INT; v_cheapest INT; v_cat TEXT; v_time INT;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF cs.state NOT IN ('active','stuck') THEN RETURN public._climb_board(p_uid); END IF;
  v_tier := public._cg_tier(cs.tier); v_k := COALESCE((v_tier->>'k')::numeric, 0.85); v_cap := COALESCE((v_tier->>'heat_cap')::int, 250);
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(cs.revealed_positions)));
  IF v_won THEN
    v_bounty := public._climb_bounty(cs.puzzle_id, v_k);
    v_payout := round(v_bounty * cs.heat_x100 / 100.0)::int;
    v_time := LEAST(GREATEST(EXTRACT(epoch FROM (now() - COALESCE(cs.puzzle_started_at, cs.updated_at))) * 1000, 0), 1800000)::int;
    UPDATE public.climb_state SET state = 'solved', last_gain = v_payout,
      bankroll = cs.bankroll + v_payout,
      heat_x100 = LEAST(v_cap, cs.heat_x100 + 10),
      run_solves = cs.run_solves + 1, updated_at = now() WHERE user_id = p_uid;
    PERFORM public._log_game_result(p_uid,'climb','won', cs.puzzle_id, v_cat, 1, 1, cs.spent::int, v_payout, v_time);
  ELSE
    v_cheapest := public._climb_cheapest(cs, v_phrase);
    IF v_cheapest IS NULL OR cs.bankroll < v_cheapest THEN
      UPDATE public.climb_state SET state = 'stuck', updated_at = now() WHERE user_id = p_uid;   -- final guess
    ELSE
      UPDATE public.climb_state SET state = 'active', updated_at = now() WHERE user_id = p_uid;
    END IF;
  END IF;
  RETURN public._climb_board(p_uid);
END; $function$;

-- Advance to the next puzzle in the SAME run (heat + bankroll carry).
CREATE OR REPLACE FUNCTION public.climb_next()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_pid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_next: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state <> 'solved' THEN RETURN public._climb_board(v_uid); END IF;
  v_pid := public._pick_casual(v_uid, null, cs.puzzle_id, 0);
  IF v_pid IS NULL THEN RETURN public._climb_board(v_uid); END IF;
  UPDATE public.climb_state SET position = cs.position + 1, puzzle_id = v_pid, revealed_positions = '{}',
    incorrect_letters = '{}', spent = 0, last_gain = 0, active_powerups = '{}',
    pups_locked = false, state = 'active', puzzle_started_at = now(), updated_at = now() WHERE user_id = v_uid;
  PERFORM public._mark_seen(v_uid, v_pid);
  RETURN public._climb_board(v_uid);
END; $function$;

-- Skip: new puzzle, heat resets ×1.0, forfeit spend (bankroll already reduced). Run continues.
CREATE OR REPLACE FUNCTION public.climb_skip()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_pid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_skip: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state NOT IN ('active','stuck') THEN RETURN public._climb_board(v_uid); END IF;
  v_pid := public._pick_casual(v_uid, null, cs.puzzle_id, 0);
  IF v_pid IS NULL THEN RETURN public._climb_board(v_uid); END IF;
  UPDATE public.climb_state SET puzzle_id = v_pid, revealed_positions = '{}', incorrect_letters = '{}',
    spent = 0, last_gain = 0, active_powerups = '{}', pups_locked = false,
    heat_x100 = 100, state = 'active', puzzle_started_at = now(), updated_at = now() WHERE user_id = v_uid;
  PERFORM public._mark_seen(v_uid, v_pid);
  RETURN public._climb_board(v_uid);
END; $function$;

-- Cash out: bank the run bankroll to global Cash (loan auto-skim applies), record stats + mastery, end the run.
CREATE OR REPLACE FUNCTION public.cashgame_cashout()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_profit BIGINT; v_mult INT; v_wins jsonb; v_streak INT; v_bestrs INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'cashgame_cashout: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state NOT IN ('active','stuck','solved') THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_run'); END IF;
  v_profit := cs.bankroll - cs.buy_in;
  v_mult := CASE WHEN cs.buy_in > 0 THEN round(cs.bankroll * 100.0 / cs.buy_in)::int ELSE 0 END;
  IF cs.bankroll > 0 THEN PERFORM public._bank_credit(v_uid, cs.bankroll, 'cashgame_cashout'); END IF;
  -- stats + mastery (a profitable cash-out counts toward tier mastery + run streak)
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
    'multiple_x100', v_mult, 'solves', cs.run_solves, 'tier', cs.tier, 'heat', cs.heat_x100);
END; $function$;

-- Bust: run ends, bankroll lost, buy-in gone. Run streak resets.
CREATE OR REPLACE FUNCTION public._cg_bust(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase text; v_all int[]; v_cat text; v_board jsonb;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid FOR UPDATE;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  SELECT array_agg(g.i) INTO v_all FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1,1) <> ' ';
  UPDATE public.profiles SET cg_run_streak = 0, cg_lifetime_net = COALESCE(cg_lifetime_net,0) - cs.buy_in WHERE id = p_uid;
  PERFORM public._log_game_result(p_uid,'climb','lost', cs.puzzle_id, v_cat, 0, 1, cs.spent::int, 0);
  v_board := public._daily_board(v_phrase, 'lost', 0, 99, COALESCE(v_all,'{}'), cs.incorrect_letters, v_cat, '')
    || jsonb_build_object('climb', jsonb_build_object('bankroll', 0, 'state', 'busted', 'tier', cs.tier,
         'buy_in', cs.buy_in, 'run_solves', cs.run_solves, 'busted', true, 'position', cs.position));
  DELETE FROM public.climb_state WHERE user_id = p_uid;
  RETURN v_board;
END; $function$;

-- Leave = pause (the run persists; resume via get_open_games). No reset, no forfeit.
CREATE OR REPLACE FUNCTION public.climb_leave()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  RETURN public._climb_board(v_uid);
END; $function$;

-- Double-or-Nothing retired in V2 (cash-out + run structure IS the press-your-luck valve).
CREATE OR REPLACE FUNCTION public.climb_double_or_nothing()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
BEGIN RETURN public._climb_board(auth.uid()); END; $function$;

-- Cash Game meta for the tier-select screen: which tiers are unlocked + stats.
CREATE OR REPLACE FUNCTION public.get_cashgame_meta()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); p public.profiles; v_tiers jsonb := '[]'::jsonb; t text; cfg jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT * INTO p FROM public.profiles WHERE id = v_uid;
  FOREACH t IN ARRAY ARRAY['micro','bronze','silver','gold'] LOOP
    cfg := public._cg_tier(t);
    v_tiers := v_tiers || jsonb_build_array(cfg || jsonb_build_object('tier', t,
      'unlocked', public._cg_unlocked(v_uid, t),
      'wins', COALESCE((p.cg_wins->>t)::int, 0)));
  END LOOP;
  RETURN jsonb_build_object('bank', COALESCE(p.bank,0), 'loan', COALESCE(p.loan,0), 'tiers', v_tiers,
    'run_streak', COALESCE(p.cg_run_streak,0), 'best_run_streak', COALESCE(p.cg_best_run_streak,0),
    'best_run', COALESCE(p.cg_best_run,0), 'best_multiple_x100', COALESCE(p.cg_best_multiple_x100,0),
    'best_heat_x100', COALESCE(p.cg_best_heat_x100,100), 'lifetime_net', COALESCE(p.cg_lifetime_net,0));
END; $function$;

-- Best-run leaderboard: rank by best CASH-OUT (what you banked), cross-tier; + best multiple.
CREATE OR REPLACE FUNCTION public.get_climb_run_leaderboard(p_scope text DEFAULT 'friends'::text, p_group uuid DEFAULT NULL::uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  WITH pool AS (
    SELECT pr.id, pr.cg_best_run, pr.cg_best_multiple_x100, pr.cg_run_streak
    FROM public.profiles pr
    WHERE pr.cg_best_run > 0 AND (
         p_scope = 'global' OR pr.id = v_uid
      OR (p_scope = 'friends' AND pr.id IN (SELECT friend_id FROM public.friendships WHERE user_id = v_uid))
      OR (p_scope = 'group'   AND pr.id IN (SELECT user_id FROM public.group_members WHERE group_id = p_group)))
  ),
  ranked AS (SELECT *, row_number() OVER (ORDER BY cg_best_run DESC, cg_best_multiple_x100 DESC) AS rank
             FROM pool ORDER BY cg_best_run DESC LIMIT 50)
  SELECT jsonb_agg(jsonb_build_object('rank', rank, 'name', public._display_name(id),
    'best_run', cg_best_run, 'best_multiple_x100', cg_best_multiple_x100, 'run_streak', cg_run_streak,
    'is_me', id = v_uid) ORDER BY rank) INTO v_rows FROM ranked;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $function$;

COMMIT;
