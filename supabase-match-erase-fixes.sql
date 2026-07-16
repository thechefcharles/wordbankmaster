-- Task 3 follow-up: three review gaps in the Erase feature (all reachable in normal play).
-- Fix 1: match_reveal ("Buy hint") must record the revealed letter in reveal_order.
-- Fix 2: match_fold must reset the new per-puzzle columns on advance (Task 1 gap).
-- Fix 3: match_sabotage Erase on empty reveal_order -> no charge, no false notify.
-- DB-only: dumped live bodies, transformed, keeping everything else byte-identical.

-- ── Fix 1 ── match_reveal: append the hint-revealed letter to reveal_order (dedup),
--    mirroring match_buy_letter, so hint-revealed letters are erasable and Erase targets
--    the truly most-recent reveal.
CREATE OR REPLACE FUNCTION public.match_reveal(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cp public.challenge_participants; v_phrase TEXT; v_letter TEXT; v_positions INT[]; v_cost INT := 150;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'match_reveal: not authenticated'; END IF;
  IF public._match_tick(p_id, v_uid) THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cp.state <> 'active' THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = public._match_pid(p_id, cp.position);
  SELECT t.ch INTO v_letter FROM (
    SELECT substr(v_phrase, g.i+1,1) AS ch, count(*) AS c FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1,1) ~ '[A-Z]' AND NOT (g.i = ANY(cp.revealed_positions))
    GROUP BY substr(v_phrase, g.i+1,1) ORDER BY c DESC, ch LIMIT 1) t;
  IF cp.bankroll < v_cost OR v_letter IS NULL THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1,1) = v_letter;
  UPDATE public.challenge_participants SET bankroll = cp.bankroll - v_cost, p_reveals = cp.p_reveals + 1,
    revealed_positions = ARRAY(SELECT DISTINCT unnest(cp.revealed_positions || v_positions) ORDER BY 1),
    reveal_order = CASE WHEN v_letter = ANY(cp.reveal_order) THEN cp.reveal_order ELSE array_append(cp.reveal_order, v_letter) END
  WHERE match_id = p_id AND user_id = v_uid;
  RETURN public._match_resolve_and_advance(p_id, v_uid);
END; $function$;

-- ── Fix 2 ── match_fold: reset the new per-puzzle columns on advance, matching
--    _match_resolve_and_advance. Non-final branches (both econ) seed fog + clear
--    reveal_order/sabotaged_targets; final (state='done') branches clear reveal_order only
--    (a done player can't be Erase-targeted, and there is no next puzzle to seed fog on).
CREATE OR REPLACE FUNCTION public.match_fold(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_uid uuid := auth.uid(); cp public.challenge_participants; m public.challenge_matches;
  v_phrase text; v_charge bigint; v_left bigint; v_next_bounty int;
begin
  if v_uid is null then raise exception 'match_fold: not authenticated'; end if;
  if public._match_tick(p_id, v_uid) then return public._match_board(p_id, v_uid); end if;
  select * into cp from public.challenge_participants where match_id = p_id and user_id = v_uid for update;
  if not found or cp.state <> 'active' then return public._match_board(p_id, v_uid); end if;
  select * into m from public.challenge_matches where id = p_id;
  -- full price of every still-unrevealed distinct letter (base cost), capped at remaining ante
  select upper(phrase) into v_phrase from public.daily_puzzles where id = public._match_pid(p_id, cp.position);
  select coalesce(sum(public.letter_cost(t.ch)), 0) into v_charge from (
    select distinct substr(v_phrase, g.i+1, 1) as ch from generate_series(0, length(v_phrase)-1) g(i)
    where substr(v_phrase, g.i+1, 1) ~ '[A-Z]' and not (g.i = any(cp.revealed_positions))
  ) t;
  v_charge := least(v_charge, cp.bankroll);
  v_left := greatest(0, cp.bankroll - v_charge);

  if m.econ_v = 2 then
    -- Accumulate this puzzle's leftover; advance with a fresh bounty (mirrors the solve path).
    if cp.position >= m.pack_size then
      update public.challenge_participants
        set state = 'done', bankroll = v_left, last_score = 0, total_score = total_score + v_left,
            reveal_order = '{}',
            finished_at = now(), finished_at = now(), joined_at = coalesce(joined_at, now())
        where match_id = p_id and user_id = v_uid;
      perform public._match_maybe_settle(p_id);
      perform public._match_notify_opponent_played(p_id, v_uid);
    else
      v_next_bounty := public._match_pos_bounty(p_id, cp.position + 1);
      update public.challenge_participants
        set position = position + 1, bankroll = v_next_bounty,
            start_budget = coalesce(start_budget, 0) + v_next_bounty,
            last_score = 0, total_score = total_score + v_left,
            revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
            reveal_order = '{}', sabotaged_targets = '{}',
            fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false,
            p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
        where match_id = p_id and user_id = v_uid;
    end if;
    return public._match_board(p_id, v_uid);
  end if;

  -- OLD (econ_v NULL): rank by Cash left; single carried budget, total_score = leftover.
  if cp.position >= m.pack_size then
    update public.challenge_participants
      set state = 'done', bankroll = v_left, last_score = 0, total_score = v_left,
          reveal_order = '{}',
          finished_at = now(), finished_at = now(), joined_at = coalesce(joined_at, now())
      where match_id = p_id and user_id = v_uid;
    perform public._match_maybe_settle(p_id);
  else
    update public.challenge_participants
      set position = position + 1, bankroll = v_left, last_score = 0, total_score = v_left,
          revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
          reveal_order = '{}', sabotaged_targets = '{}',
          fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false,
          p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
      where match_id = p_id and user_id = v_uid;
  end if;
  return public._match_board(p_id, v_uid);
end; $function$;

-- ── Fix 3 ── match_sabotage: Erase on an empty reveal_order is now pre-validated BEFORE the
--    inventory decrement (no charge) and returns sabotage_reason='nothing_to_erase'. With this
--    guard the lock branch always removes a real letter, so the "they wiped your {letter}s"
--    notify only fires on a genuine erase. Everything else byte-identical.
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
  RETURN public._match_board(p_id, v_uid);
END; $function$;
