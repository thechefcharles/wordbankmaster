-- Challenge between-puzzle receipt: gate the auto-advance so each solve prints a
-- per-puzzle scorecard with a "Next puzzle" tap (2026-07-18).
--
-- Today _match_resolve_and_advance credits your score AND loads the next puzzle in one
-- step. To show a Cash-Game-style per-puzzle receipt, we split that: on a non-final solve
-- we credit the score (unchanged) and enter an `awaiting_next` state, then a new match_next()
-- RPC does the advance when the player taps Next.
--
-- Scope: gated for clock_mode 'none' (default) and 'puzzle' (its clock only starts on Next,
-- so the receipt naturally pauses it). MATCH-wide clock keeps auto-advancing — a per-player
-- pause on a single shared countdown either burns your clock or becomes a stall exploit.
-- Legacy econ_v-NULL matches keep auto-advancing too (only new econ_v=2 matches gate).
--
-- Also tracks p_wrong_spent (wrong-guess $ this puzzle) so the slip can show
-- Bounty − Letters − Wrong = Kept exactly.

ALTER TABLE public.challenge_participants
  ADD COLUMN IF NOT EXISTS awaiting_next boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS p_wrong_spent int NOT NULL DEFAULT 0;

-- ── Track wrong-guess $ per puzzle; no-op guard handled by _match_tick ──────
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
  IF cp.awaiting_next THEN RETURN public._match_board(p_id, v_uid); END IF;  -- between puzzles: ignore
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
    v_pen := LEAST(v_pen, cp.bankroll::int);                     -- never drain below 0
    cp.bankroll := cp.bankroll - v_pen;
    cp.p_wrong_guesses := cp.p_wrong_guesses + 1;
    cp.p_wrong_spent := cp.p_wrong_spent + v_pen;               -- ← wrong-guess $ this puzzle
    UPDATE public.challenge_participants SET bankroll = cp.bankroll, p_wrong_guesses = cp.p_wrong_guesses, p_wrong_spent = cp.p_wrong_spent
      WHERE match_id = p_id AND user_id = v_uid;
  END IF;
  RETURN public._match_resolve_and_advance(p_id, v_uid);
END; $function$;

-- ── Don't enforce the clock while sitting on a between-puzzle receipt ───────
CREATE OR REPLACE FUNCTION public._match_tick(p_id uuid, p_uid uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cp public.challenge_participants; m public.challenge_matches; v_state text; v_i int;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF cp.state <> 'active' THEN RETURN true; END IF;
  IF cp.awaiting_next THEN RETURN false; END IF;   -- between puzzles: the next clock hasn't started
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF current_setting('wordbank.match_tick_busy', true) = '1' THEN RETURN false; END IF;
  IF m.clock_mode = 'puzzle' AND cp.puzzle_started_at IS NOT NULL
     AND EXTRACT(EPOCH FROM now() - cp.puzzle_started_at) > m.clock_seconds THEN
    PERFORM set_config('wordbank.match_tick_busy', '1', true);
    PERFORM public._match_do_fold(p_id, p_uid);
    PERFORM set_config('wordbank.match_tick_busy', '0', true);
    RETURN true;
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

-- ── Resolve: credit the solve, then either advance (final / match-clock) or wait ──
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
  IF COALESCE(m.wager,0) > 0 THEN PERFORM public._record_category_solve(p_uid, v_cat); END IF;
  v_solved := cp.solved + 1;
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
    ELSIF m.clock_mode = 'match' THEN
      -- Match-wide clock: keep auto-advancing (can't pause a shared countdown per player).
      v_next_bounty := public._match_pos_bounty(p_id, cp.position + 1);
      UPDATE public.challenge_participants SET solved = v_solved, solved_positions = array_append(solved_positions, cp.position), last_score = cp.bankroll,
        total_score = total_score + cp.bankroll + v_bonus, position = position + 1,
        bankroll = v_next_bounty, start_budget = COALESCE(start_budget,0) + v_next_bounty,
        revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
        reveal_order = '{}', sabotaged_targets = '{}',
        fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false, vowel_block_left = 0,
        p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0, p_wrong_spent = 0, puzzle_started_at = now()
      WHERE match_id = p_id AND user_id = p_uid;
    ELSE
      -- None / per-puzzle clock: credit the solve, then WAIT for match_next (the receipt).
      UPDATE public.challenge_participants SET solved = v_solved, solved_positions = array_append(solved_positions, cp.position),
        last_score = cp.bankroll, total_score = total_score + cp.bankroll + v_bonus,
        awaiting_next = true, joined_at = COALESCE(joined_at, now())
      WHERE match_id = p_id AND user_id = p_uid;
    END IF;
    RETURN public._match_board(p_id, p_uid);
  END IF;

  -- OLD (econ_v NULL): rank by Cash left; single carried budget, total_score = bankroll. Unchanged.
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
      p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0, p_wrong_spent = 0, puzzle_started_at = now()
    WHERE match_id = p_id AND user_id = p_uid;
  END IF;
  RETURN public._match_board(p_id, p_uid);
END; $function$;

-- ── New client RPC: advance from the between-puzzle receipt ─────────────────
CREATE OR REPLACE FUNCTION public.match_next(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cp public.challenge_participants; v_next_bounty INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'match_next: not authenticated'; END IF;
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cp.state <> 'active' OR NOT cp.awaiting_next THEN RETURN public._match_board(p_id, v_uid); END IF;
  v_next_bounty := public._match_pos_bounty(p_id, cp.position + 1);
  UPDATE public.challenge_participants SET position = cp.position + 1,
    bankroll = v_next_bounty, start_budget = COALESCE(start_budget,0) + v_next_bounty,
    revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
    reveal_order = '{}', sabotaged_targets = '{}',
    fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false, vowel_block_left = 0,
    p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0, p_wrong_spent = 0,
    awaiting_next = false, puzzle_started_at = now()
  WHERE match_id = p_id AND user_id = v_uid;
  RETURN public._match_board(p_id, v_uid);
END; $function$;

REVOKE EXECUTE ON FUNCTION public.match_next(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.match_next(uuid) TO authenticated;

-- ── Expose awaiting_next + per-puzzle wrong data on the board ───────────────
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
    'my_debuffs', to_jsonb(CASE WHEN cp.vowel_block_left > 0 THEN array_append(COALESCE(cp.debuffs,'{}'), 'vowel_block') ELSE COALESCE(cp.debuffs,'{}') END), 'fog_buys_left', cp.fog_buys_left, 'vowel_block_left', cp.vowel_block_left,
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
END; $function$;

REVOKE EXECUTE ON FUNCTION public._match_board(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._match_tick(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public._match_resolve_and_advance(uuid, uuid) FROM PUBLIC, anon;
