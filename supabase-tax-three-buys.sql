-- Tax sabotage → 3 buys (2026-07-18). Was: +50% letters for the whole puzzle. Now: +50% for the
-- target's next 3 letter buys via a tax_left counter (mirrors Vowel Block). Touches match_sabotage
-- (set tax_left=3), match_buy_letter (apply + decrement), _match_board (show it). Settlement untouched.

ALTER TABLE public.challenge_participants ADD COLUMN IF NOT EXISTS tax_left int NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.match_sabotage(p_id uuid, p_target uuid, p_powerup text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); m public.challenge_matches; v_debuff TEXT; v_name TEXT; v_qty INT; v_tstate TEXT;
  tcp public.challenge_participants; v_phrase TEXT; v_lockletter TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'match_sabotage: not authenticated'; END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND OR NOT COALESCE(m.items_allowed,false) THEN RETURN public._match_board(p_id, v_uid); END IF;
  IF p_target = v_uid THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT effect_key, name INTO v_debuff, v_name FROM public.powerups WHERE id = p_powerup AND kind = 'sabotage' AND active;
  IF v_debuff IS NULL THEN RETURN public._match_board(p_id, v_uid); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid AND state = 'active') THEN
    RETURN public._match_board(p_id, v_uid); END IF;
  SELECT * INTO tcp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_target;
  IF tcp.user_id IS NULL OR tcp.state NOT IN ('active','invited') THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT qty INTO v_qty FROM public.user_powerups_v2 WHERE user_id = v_uid AND powerup_id = p_powerup AND pool = 'cash';
  IF COALESCE(v_qty,0) <= 0 THEN RETURN public._match_board(p_id, v_uid); END IF;
  -- One sabotage per opponent per puzzle: reject a repeat against the same
  -- target this puzzle (before decrement / effect, so it never charges).
  IF p_target = ANY(COALESCE((SELECT sabotaged_targets FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid), '{}'::uuid[])) THEN
    RETURN public._match_board(p_id, v_uid) || jsonb_build_object('sabotage_reason','already_sabotaged');
  END IF;
  -- Fog lands on the target's NEXT puzzle; reject (WITHOUT consuming the item) if
  -- they have no un-started next puzzle. Validate before decrementing inventory.
  IF v_debuff = 'fog' AND tcp.position >= m.pack_size THEN
    RETURN public._match_board(p_id, v_uid) || jsonb_build_object('sabotage_reason','no_next_puzzle');
  END IF;
  -- Erase with nothing revealed: reject (WITHOUT consuming the item) so we never charge for
  -- a no-op or fire a false "they wiped your letter" notify. Validate before the decrement.
  IF v_debuff = 'lock' AND COALESCE(array_length(tcp.reveal_order,1),0) = 0 THEN
    RETURN public._match_board(p_id, v_uid) || jsonb_build_object('sabotage_reason','nothing_to_erase');
  END IF;
  UPDATE public.user_powerups_v2 SET qty = qty - 1 WHERE user_id = v_uid AND powerup_id = p_powerup AND pool = 'cash';

  IF v_debuff = 'lock' THEN
    SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = public._match_pid(p_id, tcp.position);
    v_lockletter := tcp.reveal_order[array_length(tcp.reveal_order,1)];  -- most recently revealed
    IF v_lockletter IS NOT NULL THEN
      UPDATE public.challenge_participants SET
        revealed_positions = ARRAY(SELECT DISTINCT p FROM unnest(revealed_positions) p WHERE substr(v_phrase, p+1, 1) <> v_lockletter ORDER BY 1),
        reveal_order = reveal_order[1:array_length(reveal_order,1)-1]
      WHERE match_id = p_id AND user_id = p_target;
    END IF;
  ELSIF v_debuff = 'fog' THEN
    UPDATE public.challenge_participants SET pending_fog = true WHERE match_id = p_id AND user_id = p_target;
  ELSIF v_debuff = 'vowel_block' THEN
    UPDATE public.challenge_participants SET vowel_block_left = 3 WHERE match_id = p_id AND user_id = p_target;
  ELSIF v_debuff = 'tax' THEN
    UPDATE public.challenge_participants SET tax_left = 3,
      debuff_by = COALESCE(debuff_by, '{}'::jsonb) || jsonb_build_object('tax', v_uid::text)
    WHERE match_id = p_id AND user_id = p_target;
  ELSE
    UPDATE public.challenge_participants SET
      debuffs = (SELECT ARRAY(SELECT DISTINCT unnest(COALESCE(debuffs,'{}') || ARRAY[v_debuff]))),
      debuff_by = COALESCE(debuff_by, '{}'::jsonb) || jsonb_build_object(v_debuff, v_uid::text)
    WHERE match_id = p_id AND user_id = p_target;
  END IF;

  PERFORM public._notify(p_target, 'sabotaged', '💥 You got hit!',
    public._display_name(v_uid) || ' hit you with ' || COALESCE(v_name,'a sabotage') ||
    CASE v_debuff WHEN 'tax' THEN ' — your letters cost +50%' WHEN 'fog' THEN ' — your next puzzle starts foggy'
      WHEN 'toll' THEN ' — your next letter costs 3×' WHEN 'vowel_block' THEN ' — your vowels cost 3×'
      WHEN 'lock' THEN COALESCE(' — they wiped your ' || v_lockletter || 's', ' — a revealed letter is gone') ELSE '' END,
    jsonb_build_object('match_id', p_id));
  -- Record the sabotage against this opponent (success paths only). Resets on
  -- the attacker's own advance (Task 1). Placed after all early-returns so a
  -- rejected fog/erase never burns the per-opponent slot.
  UPDATE public.challenge_participants SET sabotaged_targets = array_append(sabotaged_targets, p_target)
    WHERE match_id = p_id AND user_id = v_uid;
  RETURN public._match_board(p_id, v_uid);
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
  IF 'half_off' = ANY(cp.active_powerups) THEN v_cost := CEIL(v_cost * 0.5)::int; END IF;
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
    tax_left = GREATEST(0, cp.tax_left - 1) WHERE match_id = p_id AND user_id = v_uid;
  RETURN public._match_resolve_and_advance(p_id, v_uid);
END; $function$

;

CREATE OR REPLACE FUNCTION public._match_board(p_id uuid, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cp public.challenge_participants; m public.challenge_matches; v_pid UUID; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_clue TEXT; v_board JSONB; v_minfo JSONB; v_budget BIGINT; v_default_budget BIGINT;
  v_standing JSONB := NULL; v_field INT; v_finished INT; v_my_spent BIGINT; v_best_spent BIGINT; v_best_total BIGINT; v_ahead INT; v_state TEXT; v_rank INT;
  v_pay_places INT; v_fin_count INT; v_target BIGINT; v_target_kind TEXT; v_cheapest INT;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  v_default_budget := GREATEST(COALESCE(m.wager,0), 500);
  v_budget := CASE WHEN m.econ_v = 2 THEN public._match_pos_bounty(p_id, cp.position)
                   ELSE COALESCE(cp.start_budget, v_default_budget) END;
  v_cheapest := public._match_cheapest(p_id, p_uid);
  v_field := (SELECT count(*) FROM public.challenge_participants WHERE match_id = p_id);
  v_pay_places := CASE WHEN m.payout = 'podium' AND v_field >= 4 THEN 3
                       WHEN m.payout = 'podium' AND v_field = 3 THEN 2 ELSE 1 END;
  v_fin_count := (SELECT count(*) FROM public.challenge_participants
                  WHERE match_id = p_id AND user_id <> p_uid AND state = 'done');
  IF v_fin_count = 0 THEN
    v_target := NULL; v_target_kind := NULL;
  ELSIF v_fin_count >= v_pay_places THEN
    v_target := (SELECT min(q.ts) FROM (SELECT total_score ts FROM public.challenge_participants
                 WHERE match_id = p_id AND user_id <> p_uid AND state = 'done'
                 ORDER BY total_score DESC LIMIT v_pay_places) q);
    v_target_kind := CASE WHEN v_pay_places = 1 THEN 'win' ELSE 'place' END;
  ELSE
    v_target := (SELECT max(total_score) FROM public.challenge_participants
                 WHERE match_id = p_id AND user_id <> p_uid AND state = 'done');
    v_target_kind := 'win';
  END IF;
  v_minfo := jsonb_build_object('pack_size', m.pack_size, 'mode', m.mode, 'total_score', cp.total_score,
    'last_score', cp.last_score, 'position', cp.position, 'done', cp.state = 'done', 'status', m.status,
    'solved', cp.solved, 'spent', GREATEST(0, v_budget - cp.bankroll), 'budget', v_budget, 'wager', m.wager,
    'pot', (SELECT m.wager * count(*) FROM public.challenge_participants WHERE match_id = p_id AND state <> 'declined'),
    'target', v_target, 'target_kind', v_target_kind,
    'items_allowed', COALESCE(m.items_allowed,false), 'used_powerups', to_jsonb(cp.active_powerups),
    'my_debuffs', to_jsonb(COALESCE(cp.debuffs,'{}') || (CASE WHEN cp.vowel_block_left > 0 THEN ARRAY['vowel_block'] ELSE ARRAY[]::text[] END) || (CASE WHEN cp.tax_left > 0 THEN ARRAY['tax'] ELSE ARRAY[]::text[] END)), 'fog_buys_left', cp.fog_buys_left, 'vowel_block_left', cp.vowel_block_left,
    'must_guess', (cp.state = 'active' AND NOT cp.awaiting_next AND (v_cheapest IS NULL OR v_cheapest > cp.bankroll)),
    'started_at', cp.started_at,
    'awaiting_next', cp.awaiting_next, 'wrong_count', cp.p_wrong_guesses, 'wrong_spent', cp.p_wrong_spent,
    'clock_mode', m.clock_mode, 'clock_seconds', m.clock_seconds, 'time_scores', m.time_scores, 'puzzle_started_at', cp.puzzle_started_at,
    'opponents', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', o.user_id, 'name', public._display_name(o.user_id),
        'position', o.position, 'pack_size', m.pack_size, 'can_fog', o.position < m.pack_size) ORDER BY o.joined_at NULLS LAST), '[]'::jsonb)
      FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state IN ('active','invited')));
  IF cp.state = 'done' THEN RETURN jsonb_build_object('match', v_minfo); END IF;

  IF m.status = 'open' THEN
    SELECT count(*) INTO v_field FROM public.challenge_participants WHERE match_id = p_id;
    SELECT count(*) INTO v_finished FROM public.challenge_participants WHERE match_id = p_id AND user_id <> p_uid AND state = 'done';
    IF m.pack_size = 1 THEN
      v_my_spent := GREATEST(0, v_budget - cp.bankroll);
      SELECT min(GREATEST(0, (CASE WHEN m.econ_v = 2 THEN public._match_pos_bounty(p_id, o.position) ELSE COALESCE(o.start_budget, v_default_budget) END) - o.bankroll)) INTO v_best_spent
        FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state = 'done' AND o.solved >= 1;
      SELECT count(*) INTO v_ahead
        FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state = 'done' AND o.solved >= 1
          AND GREATEST(0, (CASE WHEN m.econ_v = 2 THEN public._match_pos_bounty(p_id, o.position) ELSE COALESCE(o.start_budget, v_default_budget) END) - o.bankroll) < v_my_spent;
      IF v_finished = 0 THEN v_state := 'first_to_play'; v_rank := 1;
      ELSIF v_best_spent IS NULL THEN v_state := 'lead'; v_rank := 1;
      ELSIF v_my_spent < v_best_spent THEN v_state := 'lead'; v_rank := 1;
      ELSIF v_my_spent = v_best_spent THEN v_state := 'tied'; v_rank := v_ahead + 1;
      ELSE v_state := 'behind'; v_rank := v_ahead + 1;
      END IF;
      v_standing := jsonb_build_object('field_size', v_field, 'finished', v_finished, 'rank', v_rank, 'state', v_state);
    ELSE
      SELECT max(o.total_score) INTO v_best_total
        FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state = 'done';
      SELECT count(*) INTO v_ahead
        FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state = 'done' AND o.total_score > cp.total_score;
      IF v_finished = 0 THEN v_state := 'first_to_play'; v_rank := 1;
      ELSIF cp.total_score > v_best_total THEN v_state := 'lead'; v_rank := 1;
      ELSIF cp.total_score = v_best_total THEN v_state := 'tied'; v_rank := v_ahead + 1;
      ELSE v_state := 'behind'; v_rank := v_ahead + 1;
      END IF;
      v_standing := jsonb_build_object('field_size', v_field, 'finished', v_finished, 'rank', v_rank, 'state', v_state, 'provisional', true);
    END IF;
  END IF;

  v_pid := public._match_pid(p_id, cp.position);
  SELECT upper(phrase), category, COALESCE(subcategory,''), clue INTO v_phrase, v_cat, v_sub, v_clue FROM public.daily_puzzles WHERE id = v_pid;
  v_board := public._daily_board(v_phrase, 'active', cp.bankroll, cp.guesses_remaining, cp.revealed_positions, cp.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('match', v_minfo, 'standing', v_standing,
    'clue', CASE WHEN cp.fog_buys_left > 0 THEN NULL ELSE v_clue END);
END; $function$

;

REVOKE EXECUTE ON FUNCTION public._match_board(uuid, uuid) FROM PUBLIC, anon;
