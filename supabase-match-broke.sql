-- Task 5: Broke = must_guess flag + broke-wrong-guess folds (shared _match_do_fold)
-- Scope: gameMode:'match' only. Server-authoritative. Each body below was dumped
-- LIVE from prod (includes Tasks 1-4) and transformed; everything else byte-identical.
--
-- Toll-in-floor choice: _match_cheapest IGNORES the one-shot `toll` debuff when
-- computing the cheapest-buyable floor (documented in the brief). toll is a single-use
-- x3 surcharge removed on the next buy; folding a player over a transient one-shot
-- surcharge would be too punishing, and match_buy_letter would strip toll on that buy
-- anyway. half_off / tax / vowel_block (persistent within the puzzle) ARE applied,
-- in the same stack order as match_buy_letter.

-- 1) Cheapest still-buyable EFFECTIVE cost for a match participant.
--    Mirrors Daily's _daily_cheapest_buyable: MIN over distinct phrase letters at
--    unrevealed positions. Applies the match cost stack (half_off -> tax -> vowel_block),
--    ignoring one-shot toll. Returns NULL when no letter remains buyable.
CREATE OR REPLACE FUNCTION public._match_cheapest(p_id uuid, p_uid uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE cp public.challenge_participants; v_phrase text; v_half boolean; v_tax boolean; v_vblock boolean;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = public._match_pid(p_id, cp.position);
  IF v_phrase IS NULL THEN RETURN NULL; END IF;
  v_half   := 'half_off'    = ANY(COALESCE(cp.active_powerups,'{}'));
  v_tax    := 'tax'         = ANY(COALESCE(cp.debuffs,'{}'));
  v_vblock := 'vowel_block' = ANY(COALESCE(cp.debuffs,'{}'));
  RETURN (
    SELECT MIN(CASE WHEN x.is_vowel AND v_vblock THEN x.c2 * 3 ELSE x.c2 END)
    FROM (
      SELECT (t.ch IN ('A','E','I','O','U')) AS is_vowel,
             CASE WHEN v_tax THEN CEIL(c1.base_half * 1.5)::int ELSE c1.base_half END AS c2
      FROM (
        SELECT DISTINCT substr(v_phrase, g.i+1, 1) AS ch
        FROM generate_series(0, length(v_phrase)-1) g(i)
        WHERE substr(v_phrase, g.i+1, 1) ~ '[A-Z]'
          AND NOT (g.i = ANY(cp.revealed_positions))
      ) t
      CROSS JOIN LATERAL (
        SELECT CASE WHEN v_half THEN CEIL(public.letter_cost(t.ch) * 0.5)::int ELSE public.letter_cost(t.ch) END AS base_half
      ) c1
      WHERE NOT (t.ch = ANY(COALESCE(cp.incorrect_letters,'{}')))
    ) x
  );
END; $function$;

-- 2) _match_board — add 'must_guess' to v_minfo (LIVE body + one field + v_cheapest var).
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
                   ELSE COALESCE(cp.start_budget, v_default_budget) END;  -- MY per-puzzle budget
  v_cheapest := public._match_cheapest(p_id, p_uid);  -- cheapest still-buyable effective cost (NULL if none)
  -- Podium-aware target: the Score to beat to reach a PAYING place (or to win).
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
    'my_debuffs', to_jsonb(COALESCE(cp.debuffs,'{}')), 'fog_buys_left', cp.fog_buys_left,
    'must_guess', (cp.state = 'active' AND (v_cheapest IS NULL OR v_cheapest > cp.bankroll)),
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
END; $function$;

-- 3) _match_do_fold — faithful extraction of the LIVE match_fold body (v_uid -> p_uid).
--    Byte-identical fold semantics: charge unrevealed base cost capped at bankroll, bank
--    leftover, advance (reset per-puzzle cols incl. Task-1/3) or state='done' + settle on
--    the last puzzle, finished_at fix preserved. Self-contained (tick + FOR UPDATE guard)
--    so it is safe to call from both match_fold and the broke-wrong path.
CREATE OR REPLACE FUNCTION public._match_do_fold(p_id uuid, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare cp public.challenge_participants; m public.challenge_matches;
  v_phrase text; v_charge bigint; v_left bigint; v_next_bounty int;
begin
  if p_uid is null then raise exception 'match_fold: not authenticated'; end if;
  if public._match_tick(p_id, p_uid) then return public._match_board(p_id, p_uid); end if;
  select * into cp from public.challenge_participants where match_id = p_id and user_id = p_uid for update;
  if not found or cp.state <> 'active' then return public._match_board(p_id, p_uid); end if;
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
            finished_at = now(), joined_at = coalesce(joined_at, now())
        where match_id = p_id and user_id = p_uid;
      perform public._match_maybe_settle(p_id);
      perform public._match_notify_opponent_played(p_id, p_uid);
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
        where match_id = p_id and user_id = p_uid;
    end if;
    return public._match_board(p_id, p_uid);
  end if;

  -- OLD (econ_v NULL): rank by Cash left; single carried budget, total_score = leftover.
  if cp.position >= m.pack_size then
    update public.challenge_participants
      set state = 'done', bankroll = v_left, last_score = 0, total_score = v_left,
          reveal_order = '{}',
          finished_at = now(), joined_at = coalesce(joined_at, now())
      where match_id = p_id and user_id = p_uid;
    perform public._match_maybe_settle(p_id);
  else
    update public.challenge_participants
      set position = position + 1, bankroll = v_left, last_score = 0, total_score = v_left,
          revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
          reveal_order = '{}', sabotaged_targets = '{}',
          fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false,
          p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
      where match_id = p_id and user_id = p_uid;
  end if;
  return public._match_board(p_id, p_uid);
end; $function$;

-- 4) match_fold — thin wrapper delegating to the shared internal.
CREATE OR REPLACE FUNCTION public.match_fold(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
  SELECT public._match_do_fold(p_id, auth.uid());
$function$;

-- 5) match_submit_guess — LIVE body + broke-wrong-guess folds (shared _match_do_fold).
--    A solvent player's wrong guess keeps the existing v_pen penalty (unchanged).
CREATE OR REPLACE FUNCTION public.match_submit_guess(p_id uuid, p_guess jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cp public.challenge_participants; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}'; v_all BOOLEAN := true; pos INT; v_ch TEXT; v_pen INT; v_cheapest INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'match_submit_guess: not authenticated'; END IF;
  IF public._match_tick(p_id, v_uid) THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cp.state <> 'active' THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = public._match_pid(p_id, cp.position);
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1,1) <> ' ' AND NOT (g.i = ANY(cp.revealed_positions));
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable,1) THEN RETURN public._match_board(p_id, v_uid); END IF;
  FOREACH pos IN ARRAY v_editable LOOP
    v_ch := upper(p_guess ->> pos::text);
    IF v_ch IS NULL THEN v_all := false;
    ELSIF v_ch = substr(v_phrase, pos+1, 1) THEN v_correct := v_correct || pos;
    ELSE v_all := false; END IF;
  END LOOP;
  IF v_all THEN
    cp.revealed_positions := ARRAY(SELECT DISTINCT unnest(cp.revealed_positions || v_correct) ORDER BY 1);
    UPDATE public.challenge_participants SET revealed_positions = cp.revealed_positions
      WHERE match_id = p_id AND user_id = v_uid;
  ELSE
    -- Broke last-stand: if the player can't afford the cheapest still-buyable letter,
    -- a wrong full-length guess ENDS the puzzle (fold) instead of just a penalty.
    v_cheapest := public._match_cheapest(p_id, v_uid);
    IF v_cheapest IS NULL OR v_cheapest > cp.bankroll THEN
      RETURN public._match_do_fold(p_id, v_uid);
    END IF;
    -- Wrong guess wastes budget (universal WordBank rule), lowering your score.
    v_pen := GREATEST(10, (round(0.2 * cp.bankroll / 10.0) * 10)::int);
    cp.bankroll := GREATEST(0, cp.bankroll - v_pen);
    cp.p_wrong_guesses := cp.p_wrong_guesses + 1;
    UPDATE public.challenge_participants SET bankroll = cp.bankroll, p_wrong_guesses = cp.p_wrong_guesses
      WHERE match_id = p_id AND user_id = v_uid;
  END IF;
  RETURN public._match_resolve_and_advance(p_id, v_uid);
END; $function$;
