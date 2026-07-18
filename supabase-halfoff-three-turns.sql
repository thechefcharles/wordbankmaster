-- Half Off → 3 turns + $250 (2026-07-18). Was: -50% letters for the whole puzzle (via the
-- active_powerups array). Now: -50% for your next 3 letter buys, via a half_off_left counter
-- (mirrors tax_left) that carries until spent. Touches the use + buy fns in both modes; the
-- counter is set to 3 on use and decrements per buy. Settlement core untouched.

ALTER TABLE public.climb_state             ADD COLUMN IF NOT EXISTS half_off_left int NOT NULL DEFAULT 0;
ALTER TABLE public.challenge_participants  ADD COLUMN IF NOT EXISTS half_off_left int NOT NULL DEFAULT 0;
UPDATE public.powerups SET price = 250 WHERE id = 'half_off';

CREATE OR REPLACE FUNCTION public.climb_use_powerup(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_eff TEXT; v_qty INT; v_phrase TEXT; v_positions INT[];
  v_k NUMERIC; v_stake INT; v_bounty INT; v_budget_left INT; v_cheapest INT; v_next UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_use_powerup: not authenticated'; END IF;
  SELECT effect_key INTO v_eff FROM public.powerups WHERE id = p_id AND kind = 'climb' AND active;
  IF v_eff IS NULL THEN RAISE EXCEPTION 'climb_use_powerup: invalid power-up'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state NOT IN ('active','stuck') THEN RETURN public._climb_board(v_uid); END IF;
  -- Heat Shield is a passive safety net (auto-consumed on a bust) — tapping it never burns it.
  IF v_eff = 'heat_shield' THEN RETURN public._climb_board(v_uid); END IF;
  -- 🏧 Overdrive: only usable when you're out of money; arms one free letter of your choice.
  IF v_eff = 'overdrive' THEN
    v_k := COALESCE((public._cg_tier(cs.tier)->>'k')::numeric, 0.85);
    v_stake := COALESCE((public._cg_tier(cs.tier)->>'stake')::int, 1);
    v_bounty := round(public._climb_bounty(cs.puzzle_id, v_k) * v_stake * cs.heat_x100 / 100.0)::int;
    v_budget_left := GREATEST(0, v_bounty - cs.spent);
    v_cheapest := public._cg_cheapest(cs);
    -- Not stuck (you can still afford a letter) → can't use it. Don't consume.
    IF v_cheapest IS NOT NULL AND v_budget_left >= v_cheapest THEN RETURN public._climb_board(v_uid); END IF;
    SELECT qty INTO v_qty FROM public.user_powerups_v2 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
    IF COALESCE(v_qty,0) <= 0 OR 'overdrive' = ANY(cs.active_powerups) THEN RETURN public._climb_board(v_uid); END IF;
    UPDATE public.user_powerups_v2 SET qty = qty - 1 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
    UPDATE public.climb_state SET active_powerups = array_append(active_powerups, 'overdrive') WHERE user_id = v_uid;
    RETURN public._climb_board(v_uid);
  END IF;
  -- ⏭️ Free Skip: swap this puzzle for a fresh one, keeping your Interest, secured pile, and run.
  IF v_eff = 'free_skip' THEN
    SELECT qty INTO v_qty FROM public.user_powerups_v2 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
    IF COALESCE(v_qty,0) <= 0 THEN RETURN public._climb_board(v_uid); END IF;
    v_next := public._pick_casual(v_uid, null, cs.puzzle_id, 0);
    IF v_next IS NULL THEN RETURN public._climb_board(v_uid); END IF;   -- no fresh puzzle available -> don't consume
    UPDATE public.user_powerups_v2 SET qty = qty - 1 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
    -- New puzzle; reset per-puzzle progress. KEEP heat_x100, bankroll, run_solves, position.
    UPDATE public.climb_state SET puzzle_id = v_next, revealed_positions = '{}', incorrect_letters = '{}',
      spent = 0, last_gain = 0, active_powerups = '{}', next_puzzle_id = NULL, pups_locked = false,
      state = 'active', puzzle_started_at = now(), updated_at = now() WHERE user_id = v_uid;
    PERFORM public._mark_seen(v_uid, v_next);
    RETURN public._climb_board(v_uid);
  END IF;
  -- Reveal-type power-ups (free_reveal, vowel_vision, reveal_word, …).
  SELECT qty INTO v_qty FROM public.user_powerups_v2 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
  IF COALESCE(v_qty,0) <= 0 THEN RETURN public._climb_board(v_uid); END IF;
  IF v_eff = ANY(cs.active_powerups) THEN RETURN public._climb_board(v_uid); END IF;
  -- One power-up per puzzle (matches Challenges). Already used one this puzzle → block.
  IF COALESCE(array_length(cs.active_powerups,1),0) >= 1 THEN RETURN public._climb_board(v_uid); END IF;
  UPDATE public.user_powerups_v2 SET qty = qty - 1 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
  UPDATE public.climb_state SET active_powerups = array_append(active_powerups, v_eff),
    half_off_left = CASE WHEN v_eff = 'half_off' THEN 3 ELSE half_off_left END WHERE user_id = v_uid;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_positions := public._powerup_reveal(v_phrase, v_eff, cs.revealed_positions);
  IF v_positions IS NOT NULL THEN
    UPDATE public.climb_state SET revealed_positions = ARRAY(SELECT DISTINCT unnest(revealed_positions || v_positions) ORDER BY 1) WHERE user_id = v_uid;
  END IF;
  RETURN public._climb_resolve(v_uid);
END; $function$

;

CREATE OR REPLACE FUNCTION public.climb_buy_letter(p_letter text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_phrase TEXT; v_letter TEXT; v_cost INT; v_stake INT;
  v_k NUMERIC; v_bounty INT; v_budget_left INT; v_positions INT[]; v_free BOOLEAN := false; v_from_budget INT; v_from_bank INT;
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
  IF cs.half_off_left > 0 THEN v_cost := CEIL(v_cost * 0.5)::int; END IF;
  -- 🏧 Overdrive armed → this letter is free (any letter), even with an empty budget.
  v_free := 'overdrive' = ANY(cs.active_powerups);
  IF v_free THEN v_cost := 0; END IF;
  v_bounty := round(public._climb_bounty(cs.puzzle_id, v_k) * v_stake * cs.heat_x100 / 100.0)::int;
  v_budget_left := v_bounty - cs.spent;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  -- Overdrive letters bypass the budget check entirely (they're free even at $0 budget).
  IF v_letter = ANY(cs.incorrect_letters) OR (NOT v_free AND (cs.bankroll + v_budget_left) < v_cost) THEN RETURN public._climb_board(v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1,1) = v_letter;
  IF v_positions IS NOT NULL AND v_positions <@ cs.revealed_positions THEN RETURN public._climb_board(v_uid); END IF;
  IF v_positions IS NULL THEN cs.incorrect_letters := array_append(cs.incorrect_letters, v_letter);
  ELSE cs.revealed_positions := ARRAY(SELECT DISTINCT unnest(cs.revealed_positions || v_positions) ORDER BY 1); END IF;
  v_from_budget := LEAST(v_cost, GREATEST(0, v_budget_left)); v_from_bank := v_cost - v_from_budget;
  UPDATE public.climb_state SET revealed_positions = cs.revealed_positions,
    incorrect_letters = cs.incorrect_letters, spent = cs.spent + v_from_budget, bankroll = cs.bankroll - v_from_bank,
    active_powerups = CASE WHEN v_free THEN array_remove(cs.active_powerups, 'overdrive') ELSE cs.active_powerups END,
    half_off_left = GREATEST(0, cs.half_off_left - 1),
    pups_locked = true, updated_at = now() WHERE user_id = v_uid;
  RETURN public._climb_resolve(v_uid);
END; $function$

;

CREATE OR REPLACE FUNCTION public.match_use_powerup(p_id uuid, p_powerup text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); m public.challenge_matches; cp public.challenge_participants; v_eff TEXT; v_name TEXT; v_qty INT; v_phrase TEXT; v_positions INT[]; r RECORD;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'match_use_powerup: not authenticated'; END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND OR NOT COALESCE(m.items_allowed,false) THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT effect_key, name INTO v_eff, v_name FROM public.powerups WHERE id = p_powerup AND kind = 'climb' AND active;
  IF v_eff IS NULL THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cp.state <> 'active' THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT qty INTO v_qty FROM public.user_powerups_v2 WHERE user_id = v_uid AND powerup_id = p_powerup AND pool = 'cash';
  IF COALESCE(v_qty,0) <= 0 THEN RETURN public._match_board(p_id, v_uid); END IF;
  IF COALESCE(array_length(cp.active_powerups,1),0) >= 1 THEN RETURN public._match_board(p_id, v_uid) || jsonb_build_object('powerup_reason','one_per_puzzle'); END IF;
  UPDATE public.user_powerups_v2 SET qty = qty - 1 WHERE user_id = v_uid AND powerup_id = p_powerup AND pool = 'cash';
  UPDATE public.challenge_participants SET active_powerups = array_append(active_powerups, v_eff),
    half_off_left = CASE WHEN v_eff = 'half_off' THEN 3 ELSE half_off_left END WHERE match_id = p_id AND user_id = v_uid;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = public._match_pid(p_id, cp.position);
  v_positions := public._powerup_reveal(v_phrase, v_eff, cp.revealed_positions);
  IF v_positions IS NOT NULL THEN
    UPDATE public.challenge_participants SET
      revealed_positions = ARRAY(SELECT DISTINCT unnest(revealed_positions || v_positions) ORDER BY 1),
      reveal_order = reveal_order || ARRAY(
        SELECT q.l FROM (
          SELECT substr(v_phrase, p+1, 1) AS l, min(p) AS firstpos
          FROM unnest(v_positions) p
          WHERE substr(v_phrase, p+1, 1) ~ '[A-Z]'
          GROUP BY substr(v_phrase, p+1, 1)
        ) q
        WHERE q.l <> ALL(reveal_order)
        ORDER BY q.firstpos)
    WHERE match_id = p_id AND user_id = v_uid;
  END IF;
  FOR r IN SELECT user_id FROM public.challenge_participants WHERE match_id = p_id AND user_id <> v_uid AND state IN ('active','done') LOOP
    PERFORM public._notify(r.user_id, 'powerup_used', '💥 Power-up used',
      public._display_name(v_uid) || ' used ' || COALESCE(v_name, 'a power-up'), jsonb_build_object('match_id', p_id));
  END LOOP;
  RETURN public._match_resolve_and_advance(p_id, v_uid);
END; $function$

;

CREATE OR REPLACE FUNCTION public.match_buy_letter(p_id uuid, p_letter text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cp public.challenge_participants; v_phrase TEXT; v_letter TEXT; v_cost INT; v_positions INT[]; v_debuffs text[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'match_buy_letter: not authenticated'; END IF;
  IF public._match_tick(p_id, v_uid) THEN RETURN public._match_board(p_id, v_uid); END IF;
  v_letter := upper(p_letter); v_cost := public.letter_cost(v_letter);
  IF v_cost IS NULL THEN RAISE EXCEPTION 'match_buy_letter: invalid letter'; END IF;
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cp.state <> 'active' THEN RETURN public._match_board(p_id, v_uid); END IF;
  v_debuffs := COALESCE(cp.debuffs, '{}');
  IF cp.half_off_left > 0 THEN v_cost := CEIL(v_cost * 0.5)::int; END IF;
  IF cp.tax_left > 0 THEN v_cost := CEIL(v_cost * 1.5)::int; END IF;
  IF v_letter IN ('A','E','I','O','U') AND cp.vowel_block_left > 0 THEN v_cost := v_cost * 3; END IF;
  IF 'toll' = ANY(v_debuffs) THEN v_cost := v_cost * 3; v_debuffs := array_remove(v_debuffs, 'toll'); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = public._match_pid(p_id, cp.position);
  IF v_letter = ANY(cp.incorrect_letters) OR cp.bankroll < v_cost THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1,1) = v_letter;
  IF v_positions IS NOT NULL AND v_positions <@ cp.revealed_positions THEN RETURN public._match_board(p_id, v_uid); END IF;
  IF v_letter IN ('A','E','I','O','U') THEN cp.p_vowels := cp.p_vowels + 1; END IF;
  IF v_positions IS NULL THEN cp.incorrect_letters := array_append(cp.incorrect_letters, v_letter);
  ELSE cp.revealed_positions := ARRAY(SELECT DISTINCT unnest(cp.revealed_positions || v_positions) ORDER BY 1);
    cp.reveal_order := CASE WHEN v_letter = ANY(cp.reveal_order) THEN cp.reveal_order ELSE array_append(cp.reveal_order, v_letter) END; END IF;
  UPDATE public.challenge_participants SET bankroll = cp.bankroll - v_cost, incorrect_letters = cp.incorrect_letters,
    revealed_positions = cp.revealed_positions, reveal_order = cp.reveal_order, p_vowels = cp.p_vowels, debuffs = v_debuffs,
    fog_buys_left = GREATEST(0, cp.fog_buys_left - 1), vowel_block_left = GREATEST(0, cp.vowel_block_left - 1),
    tax_left = GREATEST(0, cp.tax_left - 1), half_off_left = GREATEST(0, cp.half_off_left - 1) WHERE match_id = p_id AND user_id = v_uid;
  RETURN public._match_resolve_and_advance(p_id, v_uid);
END; $function$

;

REVOKE EXECUTE ON FUNCTION public.climb_buy_letter(text) FROM PUBLIC, anon;
