-- Task 4: Usage caps for 1v1 matches (gameMode:'match') --------------------
-- One power-up total per puzzle; one sabotage per opponent per puzzle.
-- Bodies dumped live from prod (include Tasks 1-3 changes), transformed, and
-- kept byte-identical elsewhere.

-- 1) match_use_powerup: one power-up TOTAL per puzzle (was one-of-each).
--    Gate returns a reason and runs BEFORE the inventory decrement so a
--    rejected power-up does not consume the item.
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
  UPDATE public.challenge_participants SET active_powerups = array_append(active_powerups, v_eff) WHERE match_id = p_id AND user_id = v_uid;
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
END; $function$;

-- 2) match_sabotage: one sabotage per opponent per puzzle.
--    already_sabotaged check runs after target validation but before the
--    inventory decrement / effect branches (so a repeat never charges).
--    The array_append(sabotaged_targets) runs ONLY at the end — after the
--    decrement and effect applied — so it never fires on the no_next_puzzle
--    or nothing_to_erase early-returns, and records exactly once per success.
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
END; $function$;
