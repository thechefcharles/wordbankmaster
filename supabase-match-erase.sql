-- Task 3: Lock -> Erase (wipe opponent's most-recently-revealed letter) + reveal-order tracking
-- Scoped to gameMode:'match'. DB-only migration: dump live, transform, rollback-test, apply.
-- Touches: match_buy_letter, match_use_powerup, match_sabotage, powerups catalog row.
-- Consumes Task 1 column challenge_participants.reveal_order text[] (resets on advance).

-- 1) match_buy_letter: on a correct (revealing) buy, append the letter to reveal_order
--    (dedup, order stable), and persist. Do NOT append on incorrect letters.
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
  IF 'tax' = ANY(v_debuffs) THEN v_cost := CEIL(v_cost * 1.5)::int; END IF;
  IF v_letter IN ('A','E','I','O','U') AND 'vowel_block' = ANY(v_debuffs) THEN v_cost := v_cost * 3; END IF;
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
    fog_buys_left = GREATEST(0, cp.fog_buys_left - 1) WHERE match_id = p_id AND user_id = v_uid;
  RETURN public._match_resolve_and_advance(p_id, v_uid);
END; $function$;

-- 2) match_use_powerup: when a powerup reveals positions, append the distinct revealed
--    letters (from v_phrase at those positions, position order, skip already-present) to
--    reveal_order so powerup-revealed letters are erasable too. Keep order stable.
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
  IF v_eff = ANY(cp.active_powerups) THEN RETURN public._match_board(p_id, v_uid); END IF;
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

-- 3) match_sabotage: 'lock' branch now ERASES the target's most-recently-revealed letter
--    (last element of reveal_order): remove all its revealed positions AND pop it from
--    reveal_order. Graceful no-op when reveal_order is empty. Fog / tax / toll / vowel_block
--    branches unchanged; _notify "they wiped your {letter}s" preserved.
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
  -- Fog lands on the target's NEXT puzzle; reject (WITHOUT consuming the item) if
  -- they have no un-started next puzzle. Validate before decrementing inventory.
  IF v_debuff = 'fog' AND tcp.position >= m.pack_size THEN
    RETURN public._match_board(p_id, v_uid) || jsonb_build_object('sabotage_reason','no_next_puzzle');
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
  RETURN public._match_board(p_id, v_uid);
END; $function$;

-- 4) Catalog rename. NOTE: public.powerups has no `description` column (columns:
--    id,name,kind,effect_key,price,sort,active) — the item copy is hardcoded client-side,
--    so we update `name` only. Client desc updated in src/routes/shop/+page.svelte.
UPDATE public.powerups SET name = 'Erase' WHERE id = 'sabotage_lock';
