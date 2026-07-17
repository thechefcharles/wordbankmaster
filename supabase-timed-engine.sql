-- Timed challenges — clock enforcement + speed bonus (server engine)
-- Task 8 of challenge batch 2. See docs/superpowers/specs/2026-07-17-timed-challenges.md
--
-- Touches four live functions; everything else is byte-identical to the dumped bodies:
--   _match_tick                — authoritative clock enforcement (was a near no-op)
--   _match_do_fold             — re-stamp puzzle_started_at on every advance
--   _match_resolve_and_advance — re-stamp on advance + speed bonus in the WIN path
--   _match_board               — expose clock config + anchors for the client countdown
--
-- Speed-bonus RATE = 3 points per leftover second (single tunable constant; see below).

-- ---------------------------------------------------------------------------
-- 1) _match_tick: enforce the clock.
--    Re-entrancy note: _match_do_fold() calls _match_tick() at its top, so when
--    WE invoke _match_do_fold() from here that nested tick must be a no-op (else
--    it would re-detect the same expiry and recurse forever). A transaction-local
--    GUC ('wordbank.match_tick_busy') guards that: while we drive the fold(s) the
--    nested tick returns false, letting the real fold body run (which advances the
--    position and re-stamps puzzle_started_at, breaking the recursion).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._match_tick(p_id uuid, p_uid uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cp public.challenge_participants; m public.challenge_matches; v_state text; v_i int;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF cp.state <> 'active' THEN RETURN true; END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  -- Re-entrant call (we are already inside our own fold loop): stand down so the
  -- in-flight _match_do_fold() runs its real body instead of recursing.
  IF current_setting('wordbank.match_tick_busy', true) = '1' THEN RETURN false; END IF;
  -- Per-puzzle clock: the current puzzle's time is up -> force-fold it (advances or ends).
  IF m.clock_mode = 'puzzle' AND cp.puzzle_started_at IS NOT NULL
     AND EXTRACT(EPOCH FROM now() - cp.puzzle_started_at) > m.clock_seconds THEN
    PERFORM set_config('wordbank.match_tick_busy', '1', true);
    PERFORM public._match_do_fold(p_id, p_uid);
    PERFORM set_config('wordbank.match_tick_busy', '0', true);
    RETURN true;
  -- Whole-match clock: the pack's total time is up -> fold every remaining puzzle
  -- until this player is done (capped at pack_size iterations for safety).
  ELSIF m.clock_mode = 'match' AND cp.started_at IS NOT NULL
     AND EXTRACT(EPOCH FROM now() - cp.started_at) > m.clock_seconds THEN
    PERFORM set_config('wordbank.match_tick_busy', '1', true);
    FOR v_i IN 1 .. GREATEST(COALESCE(m.pack_size, 1), 1) LOOP
      PERFORM public._match_do_fold(p_id, p_uid);
      SELECT state INTO v_state FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
      EXIT WHEN v_state = 'done';
    END LOOP;
    PERFORM set_config('wordbank.match_tick_busy', '0', true);
    RETURN true;
  END IF;
  RETURN false;
END; $function$;

-- ---------------------------------------------------------------------------
-- 2) _match_do_fold: re-stamp puzzle_started_at = now() on every advance
--    (both econ branches' non-final paths). 'done' branches don't re-stamp.
-- ---------------------------------------------------------------------------
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
            fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false, vowel_block_left = 0,
            p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0, puzzle_started_at = now()
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
          fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false, vowel_block_left = 0,
          p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0, puzzle_started_at = now()
      where match_id = p_id and user_id = p_uid;
  end if;
  return public._match_board(p_id, p_uid);
end; $function$;

-- ---------------------------------------------------------------------------
-- 3) _match_resolve_and_advance: re-stamp puzzle_started_at on advance +
--    speed bonus (RATE=3 pts/leftover-sec) added onto the banked total_score
--    in the WIN path when m.time_scores is on.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._match_resolve_and_advance(p_id uuid, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cp public.challenge_participants; m public.challenge_matches; v_phrase TEXT; v_cat TEXT; v_won BOOLEAN;
  v_score INT; v_combo INT; v_solved INT; v_budget BIGINT; v_next_bounty INT; v_bonus INT;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF cp.state <> 'active' THEN RETURN public._match_board(p_id, p_uid); END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  v_budget := GREATEST(COALESCE(m.wager,0), 500);
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = public._match_pid(p_id, cp.position);
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(cp.revealed_positions)));
  IF NOT v_won THEN RETURN public._match_board(p_id, p_uid); END IF;
  IF COALESCE(m.wager,0) > 0 THEN PERFORM public._record_category_solve(p_uid, v_cat); END IF;  -- friendly (wager 0) earns no category credit
  v_solved := cp.solved + 1;
  -- Speed bonus: RATE = 3 points per leftover second (single tunable constant;
  -- expect to re-tune after playtest). Only when time_scores is on; anchor is the
  -- per-puzzle clock for 'puzzle', the whole-match clock for 'match' (earlier
  -- solves bank more). Added on TOP of the kept bounty in every WIN UPDATE below.
  v_bonus := 0;
  IF COALESCE(m.time_scores, false) AND m.clock_seconds IS NOT NULL THEN
    IF m.clock_mode = 'puzzle' AND cp.puzzle_started_at IS NOT NULL THEN
      v_bonus := GREATEST(0, m.clock_seconds - EXTRACT(EPOCH FROM now() - cp.puzzle_started_at))::int * 3;
    ELSIF m.clock_mode = 'match' AND cp.started_at IS NOT NULL THEN
      v_bonus := GREATEST(0, m.clock_seconds - EXTRACT(EPOCH FROM now() - cp.started_at))::int * 3;
    END IF;
  END IF;
  IF m.econ_v = 2 THEN
    IF cp.position >= m.pack_size THEN
      UPDATE public.challenge_participants SET solved = v_solved, solved_positions = array_append(solved_positions, cp.position), last_score = cp.bankroll,
        total_score = total_score + cp.bankroll + v_bonus, state = 'done', finished_at = now(), joined_at = COALESCE(joined_at, now())
      WHERE match_id = p_id AND user_id = p_uid;
      PERFORM public._match_maybe_settle(p_id); PERFORM public._match_notify_opponent_played(p_id, p_uid);
    ELSE
      v_next_bounty := public._match_pos_bounty(p_id, cp.position + 1);
      UPDATE public.challenge_participants SET solved = v_solved, solved_positions = array_append(solved_positions, cp.position), last_score = cp.bankroll,
        total_score = total_score + cp.bankroll + v_bonus, position = position + 1,
        bankroll = v_next_bounty, start_budget = COALESCE(start_budget,0) + v_next_bounty,
        revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
        reveal_order = '{}', sabotaged_targets = '{}',
        fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false, vowel_block_left = 0,
        p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0, puzzle_started_at = now()
      WHERE match_id = p_id AND user_id = p_uid;
    END IF;
    RETURN public._match_board(p_id, p_uid);
  END IF;

  -- OLD (econ_v NULL): rank by Cash left; single carried budget, total_score = bankroll.
  IF cp.position >= m.pack_size THEN
    UPDATE public.challenge_participants SET solved = v_solved, solved_positions = array_append(solved_positions, cp.position), last_score = cp.bankroll,
      total_score = cp.bankroll + v_bonus, state = 'done', finished_at = now(), joined_at = COALESCE(joined_at, now())
    WHERE match_id = p_id AND user_id = p_uid;
    PERFORM public._match_maybe_settle(p_id); PERFORM public._match_notify_opponent_played(p_id, p_uid);
  ELSE
    UPDATE public.challenge_participants SET solved = v_solved, solved_positions = array_append(solved_positions, cp.position), last_score = cp.bankroll,
      total_score = cp.bankroll + v_bonus, position = position + 1,
      revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
      reveal_order = '{}', sabotaged_targets = '{}',
      fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false, vowel_block_left = 0,
      p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0, puzzle_started_at = now()
    WHERE match_id = p_id AND user_id = p_uid;
  END IF;
  RETURN public._match_board(p_id, p_uid);
END; $function$;

-- ---------------------------------------------------------------------------
-- 4) _match_board: expose clock config + anchors in v_minfo for the client
--    countdown (purely additive: clock_mode, clock_seconds, time_scores,
--    puzzle_started_at; started_at was already exposed).
-- ---------------------------------------------------------------------------
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
    'my_debuffs', to_jsonb(CASE WHEN cp.vowel_block_left > 0 THEN array_append(COALESCE(cp.debuffs,'{}'), 'vowel_block') ELSE COALESCE(cp.debuffs,'{}') END), 'fog_buys_left', cp.fog_buys_left, 'vowel_block_left', cp.vowel_block_left,
    'must_guess', (cp.state = 'active' AND (v_cheapest IS NULL OR v_cheapest > cp.bankroll)),
    'started_at', cp.started_at,
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
END; $function$;
