-- V2 Phase 5: Blitz — the Speed-Run mode (new mode).
--
-- The time-twin of Cash Game: buy in, then race a live clock. Revealing letters costs
-- SECONDS (not Cash), solving adds seconds + a base_tier×combo Cash payout, and a combo
-- snowballs. Clock hits 0 → bank the winnings; net = winnings − buy-in.
--
-- Anti-cheat clock: the clock is server-authoritative via `ends_at` (an absolute timestamp).
-- Remaining = ends_at − now() on the SERVER; every action shifts ends_at by its ±seconds.
-- The client can't fake time — it only renders a countdown to ends_at. Once now() ≥ ends_at
-- the run auto-settles on the next action / board fetch.
-- Spec: Notion "Blitz". PITR point logged before apply.

BEGIN;

-- Run state (one active run per user).
CREATE TABLE IF NOT EXISTS public.blitz_runs (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tier text NOT NULL,
  buy_in bigint NOT NULL,
  ends_at timestamptz NOT NULL,
  combo_x100 int NOT NULL DEFAULT 100,
  solved int NOT NULL DEFAULT 0,
  winnings bigint NOT NULL DEFAULT 0,
  puzzle_id uuid,
  revealed_positions int[] NOT NULL DEFAULT '{}',
  incorrect_letters text[] NOT NULL DEFAULT '{}',
  state text NOT NULL DEFAULT 'active',
  started_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.blitz_runs ENABLE ROW LEVEL SECURITY;

-- Blitz stats.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bz_best_run int DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bz_best_combo_x100 int DEFAULT 100;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bz_best_payout bigint DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bz_lifetime_net bigint DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bz_runs int DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bz_highest_tier text;

-- Clock + combo constants (seconds).
--   START 45 · reveal −3 · wrong −5 · solve +8 · skip −3 · combo +0.25 cap ×5.

-- Tier config: buy-in + base reward per solve (× combo). No difficulty change; only money scales.
CREATE OR REPLACE FUNCTION public._blitz_tier(p_tier text)
 RETURNS jsonb LANGUAGE sql IMMUTABLE
AS $function$
  SELECT CASE lower(p_tier)
    WHEN 'bronze' THEN jsonb_build_object('buy_in', 500,   'base', 40,  'label', '🥉 Bronze', 'order', 1)
    WHEN 'silver' THEN jsonb_build_object('buy_in', 2000,  'base', 160, 'label', '🥈 Silver', 'order', 2)
    WHEN 'gold'   THEN jsonb_build_object('buy_in', 10000, 'base', 800, 'label', '🥇 Gold',   'order', 3)
    ELSE NULL END;
$function$;

-- Board: phrase display + the live Blitz HUD (remaining_ms, combo, winnings…).
CREATE OR REPLACE FUNCTION public._blitz_board(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE r public.blitz_runs; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_tier JSONB; v_rem int; v_board JSONB;
BEGIN
  SELECT * INTO r FROM public.blitz_runs WHERE user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_tier := public._blitz_tier(r.tier);
  v_rem := GREATEST(0, (EXTRACT(epoch FROM (r.ends_at - now())) * 1000)::int);
  SELECT upper(phrase), category, COALESCE(subcategory,'') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = r.puzzle_id;
  v_board := public._daily_board(v_phrase, 'active', 0, 99, r.revealed_positions, r.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('blitz', jsonb_build_object(
    'remaining_ms', v_rem, 'combo', r.combo_x100, 'solved', r.solved, 'winnings', r.winnings,
    'tier', r.tier, 'buy_in', r.buy_in, 'base', (v_tier->>'base')::int, 'tier_label', v_tier->>'label',
    'state', 'active'));
END; $function$;

-- Settle: bank winnings, record stats, end the run. Returns the result payload.
CREATE OR REPLACE FUNCTION public._blitz_settle(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE r public.blitz_runs; v_net bigint; v_tier_order int; v_cur_order int;
BEGIN
  SELECT * INTO r FROM public.blitz_runs WHERE user_id = p_uid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('blitz', jsonb_build_object('state','ended','ok',false)); END IF;
  v_net := r.winnings - r.buy_in;
  IF r.winnings > 0 THEN PERFORM public._bank_credit(p_uid, r.winnings, 'blitz_payout'); END IF;
  -- highest tier reached (order the tiers)
  v_tier_order := COALESCE((public._blitz_tier(r.tier)->>'order')::int, 0);
  v_cur_order  := COALESCE((public._blitz_tier((SELECT bz_highest_tier FROM public.profiles WHERE id = p_uid))->>'order')::int, 0);
  UPDATE public.profiles SET
    bz_best_run = GREATEST(COALESCE(bz_best_run,0), r.solved),
    bz_best_combo_x100 = GREATEST(COALESCE(bz_best_combo_x100,100), r.combo_x100),
    bz_best_payout = GREATEST(COALESCE(bz_best_payout,0), r.winnings),
    bz_lifetime_net = COALESCE(bz_lifetime_net,0) + v_net,
    bz_runs = COALESCE(bz_runs,0) + 1,
    bz_highest_tier = CASE WHEN v_tier_order > v_cur_order THEN r.tier ELSE bz_highest_tier END
    WHERE id = p_uid;
  DELETE FROM public.blitz_runs WHERE user_id = p_uid;
  RETURN jsonb_build_object('blitz', jsonb_build_object('state','ended','ok',true,
    'solved', r.solved, 'winnings', r.winnings, 'buy_in', r.buy_in, 'net', v_net,
    'best_combo', r.combo_x100, 'tier', r.tier));
END; $function$;

-- Start a run: debit buy-in, seed the 45s clock.
CREATE OR REPLACE FUNCTION public.blitz_start(p_tier text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_tier JSONB; v_buy BIGINT; v_bank BIGINT; v_pid UUID; v_t text := lower(COALESCE(p_tier,''));
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'blitz_start: not authenticated'; END IF;
  v_tier := public._blitz_tier(v_t);
  IF v_tier IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'bad_tier'); END IF;
  IF EXISTS (SELECT 1 FROM public.blitz_runs WHERE user_id = v_uid) THEN RETURN jsonb_build_object('ok', false, 'reason', 'run_active'); END IF;
  PERFORM public._ensure_bank(v_uid);
  v_buy := (v_tier->>'buy_in')::bigint;
  SELECT bank INTO v_bank FROM public.profiles WHERE id = v_uid;
  IF v_bank < v_buy THEN RETURN jsonb_build_object('ok', false, 'reason', 'insufficient', 'buy_in', v_buy, 'bank', v_bank); END IF;
  v_pid := public._pick_casual(v_uid, null, null, 0);
  IF v_pid IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_puzzles'); END IF;
  PERFORM public._bank_credit(v_uid, -v_buy, 'blitz_buyin');
  INSERT INTO public.blitz_runs(user_id, tier, buy_in, ends_at, puzzle_id)
    VALUES (v_uid, v_t, v_buy, now() + interval '45 seconds', v_pid);
  PERFORM public._mark_seen(v_uid, v_pid);
  RETURN public._blitz_board(v_uid) || jsonb_build_object('ok', true);
END; $function$;

-- Resolve after a move: a solved phrase pays base×combo, ticks combo, adds 8s, next puzzle.
CREATE OR REPLACE FUNCTION public._blitz_resolve(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE r public.blitz_runs; v_phrase TEXT; v_won BOOLEAN; v_base INT; v_payout INT; v_pid UUID;
BEGIN
  SELECT * INTO r FROM public.blitz_runs WHERE user_id = p_uid FOR UPDATE;
  IF NOT FOUND THEN RETURN public._blitz_settle(p_uid); END IF;
  IF now() >= r.ends_at THEN RETURN public._blitz_settle(p_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = r.puzzle_id;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions)));
  IF NOT v_won THEN RETURN public._blitz_board(p_uid); END IF;
  v_base := (public._blitz_tier(r.tier)->>'base')::int;
  v_payout := (round(v_base * r.combo_x100 / 100.0 / 10.0) * 10)::int;   -- $10-clean
  v_pid := public._pick_casual(p_uid, null, r.puzzle_id, 0);
  UPDATE public.blitz_runs SET
    winnings = r.winnings + v_payout,
    combo_x100 = LEAST(500, r.combo_x100 + 25),
    solved = r.solved + 1,
    ends_at = r.ends_at + interval '8 seconds',
    puzzle_id = COALESCE(v_pid, r.puzzle_id),
    revealed_positions = '{}', incorrect_letters = '{}'
    WHERE user_id = p_uid;
  IF v_pid IS NOT NULL THEN PERFORM public._mark_seen(p_uid, v_pid); END IF;
  RETURN public._blitz_board(p_uid);
END; $function$;

-- Reveal a letter → −3s.
CREATE OR REPLACE FUNCTION public.blitz_buy_letter(p_letter text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); r public.blitz_runs; v_phrase TEXT; v_letter TEXT; v_positions INT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'blitz_buy_letter: not authenticated'; END IF;
  v_letter := upper(p_letter);
  IF public.letter_cost(v_letter) IS NULL THEN RAISE EXCEPTION 'blitz_buy_letter: invalid letter'; END IF;
  SELECT * INTO r FROM public.blitz_runs WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'blitz_buy_letter: no run'; END IF;
  IF now() >= r.ends_at THEN RETURN public._blitz_settle(v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = r.puzzle_id;
  IF v_letter = ANY(r.incorrect_letters) THEN RETURN public._blitz_board(v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1,1) = v_letter;
  IF v_positions IS NOT NULL AND v_positions <@ r.revealed_positions THEN RETURN public._blitz_board(v_uid); END IF;
  IF v_positions IS NULL THEN r.incorrect_letters := array_append(r.incorrect_letters, v_letter);
  ELSE r.revealed_positions := ARRAY(SELECT DISTINCT unnest(r.revealed_positions || v_positions) ORDER BY 1); END IF;
  UPDATE public.blitz_runs SET revealed_positions = r.revealed_positions, incorrect_letters = r.incorrect_letters,
    ends_at = r.ends_at - interval '3 seconds' WHERE user_id = v_uid;
  RETURN public._blitz_resolve(v_uid);
END; $function$;

-- Submit a guess → wrong costs 5s; correct solves.
CREATE OR REPLACE FUNCTION public.blitz_submit_guess(p_guess jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); r public.blitz_runs; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}'; v_all BOOLEAN := true; pos INT; v_ch TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'blitz_submit_guess: not authenticated'; END IF;
  SELECT * INTO r FROM public.blitz_runs WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'blitz_submit_guess: no run'; END IF;
  IF now() >= r.ends_at THEN RETURN public._blitz_settle(v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = r.puzzle_id;
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1,1) <> ' ' AND NOT (g.i = ANY(r.revealed_positions));
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable,1) THEN RETURN public._blitz_board(v_uid); END IF;
  FOREACH pos IN ARRAY v_editable LOOP
    v_ch := upper(p_guess ->> pos::text);
    IF v_ch IS NULL THEN v_all := false;
    ELSIF v_ch = substr(v_phrase, pos+1, 1) THEN v_correct := v_correct || pos;
    ELSE v_all := false; END IF;
  END LOOP;
  IF v_all THEN
    UPDATE public.blitz_runs SET revealed_positions = ARRAY(SELECT DISTINCT unnest(r.revealed_positions || v_correct) ORDER BY 1) WHERE user_id = v_uid;
    RETURN public._blitz_resolve(v_uid);
  ELSE
    UPDATE public.blitz_runs SET ends_at = r.ends_at - interval '5 seconds' WHERE user_id = v_uid;
    IF now() >= (r.ends_at - interval '5 seconds') THEN RETURN public._blitz_settle(v_uid); END IF;
    RETURN public._blitz_board(v_uid);
  END IF;
END; $function$;

-- Skip → new puzzle, combo resets ×1.0, −3s.
CREATE OR REPLACE FUNCTION public.blitz_skip()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); r public.blitz_runs; v_pid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'blitz_skip: not authenticated'; END IF;
  SELECT * INTO r FROM public.blitz_runs WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'blitz_skip: no run'; END IF;
  IF now() >= r.ends_at THEN RETURN public._blitz_settle(v_uid); END IF;
  v_pid := public._pick_casual(v_uid, null, r.puzzle_id, 0);
  IF v_pid IS NULL THEN RETURN public._blitz_board(v_uid); END IF;
  UPDATE public.blitz_runs SET puzzle_id = v_pid, revealed_positions = '{}', incorrect_letters = '{}',
    combo_x100 = 100, ends_at = r.ends_at - interval '3 seconds' WHERE user_id = v_uid;
  PERFORM public._mark_seen(v_uid, v_pid);
  RETURN public._blitz_board(v_uid);
END; $function$;

-- Client calls this when its countdown reaches 0 (server re-validates via ends_at).
CREATE OR REPLACE FUNCTION public.blitz_end()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'blitz_end: not authenticated'; END IF;
  RETURN public._blitz_settle(v_uid);
END; $function$;

-- Tier-select meta (affordability + stats).
CREATE OR REPLACE FUNCTION public.get_blitz_meta()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); p public.profiles; v_tiers jsonb := '[]'::jsonb; t text; cfg jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT * INTO p FROM public.profiles WHERE id = v_uid;
  FOREACH t IN ARRAY ARRAY['bronze','silver','gold'] LOOP
    cfg := public._blitz_tier(t);
    v_tiers := v_tiers || jsonb_build_array(cfg || jsonb_build_object('tier', t, 'affordable', COALESCE(p.bank,0) >= (cfg->>'buy_in')::bigint));
  END LOOP;
  RETURN jsonb_build_object('bank', COALESCE(p.bank,0), 'loan', COALESCE(p.loan,0), 'tiers', v_tiers,
    'best_run', COALESCE(p.bz_best_run,0), 'best_combo_x100', COALESCE(p.bz_best_combo_x100,100),
    'best_payout', COALESCE(p.bz_best_payout,0), 'lifetime_net', COALESCE(p.bz_lifetime_net,0),
    'runs', COALESCE(p.bz_runs,0), 'highest_tier', p.bz_highest_tier);
END; $function$;

-- Leaderboard: most solved in a run (best_run), then best combo.
CREATE OR REPLACE FUNCTION public.get_blitz_leaderboard(p_scope text DEFAULT 'friends'::text, p_group uuid DEFAULT NULL::uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  WITH pool AS (
    SELECT pr.id, pr.bz_best_run, pr.bz_best_combo_x100, pr.bz_best_payout
    FROM public.profiles pr
    WHERE pr.bz_best_run > 0 AND (
         p_scope = 'global' OR pr.id = v_uid
      OR (p_scope = 'friends' AND pr.id IN (SELECT friend_id FROM public.friendships WHERE user_id = v_uid))
      OR (p_scope = 'group'   AND pr.id IN (SELECT user_id FROM public.group_members WHERE group_id = p_group)))
  ),
  ranked AS (SELECT *, row_number() OVER (ORDER BY bz_best_run DESC, bz_best_combo_x100 DESC) AS rank
             FROM pool ORDER BY bz_best_run DESC LIMIT 50)
  SELECT jsonb_agg(jsonb_build_object('rank', rank, 'name', public._display_name(id),
    'best_run', bz_best_run, 'best_combo_x100', bz_best_combo_x100, 'best_payout', bz_best_payout,
    'is_me', id = v_uid) ORDER BY rank) INTO v_rows FROM ranked;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $function$;

COMMIT;
