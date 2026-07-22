-- Challenge (1v1 + group) wrong-solve aligned with Cash Game: escalating bounty-based
-- penalty (miss1 20%, miss2 50%, miss3/over-budget = FOLD instead of bust). Reuses
-- _cg_wrong_pen. _match_board exposes fold_on_wrong / wrong_next_cost / wrong_guess_num /
-- wrong_pen1,2 for the shared Solve UI (ⓘ + warning).
BEGIN;

CREATE OR REPLACE FUNCTION public.match_submit_guess(p_id uuid, p_guess jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cp public.challenge_participants; m public.challenge_matches; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}'; v_all BOOLEAN := true; pos INT; v_ch TEXT; v_pen INT; v_budget BIGINT; v_n INT;
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
    -- Escalating, budget-based penalty tied to this puzzle's bounty (same curve as Cash Game):
    -- miss 1 = 20%, miss 2 = 50%, miss 3 (or a penalty the budget can't cover) = FOLD (lose the puzzle).
    SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
    v_budget := CASE WHEN m.econ_v = 2 THEN public._match_pos_bounty(p_id, cp.position)
                     ELSE COALESCE(cp.start_budget, GREATEST(COALESCE(m.wager,0), 500)) END;
    v_n := cp.p_wrong_guesses + 1;
    v_pen := public._cg_wrong_pen(v_budget::int, v_n);
    IF v_pen IS NULL OR v_pen > cp.bankroll THEN
      RETURN public._match_do_fold(p_id, v_uid);          -- fold (lose this puzzle), not a bust
    END IF;
    cp.bankroll := cp.bankroll - v_pen;
    cp.p_wrong_guesses := cp.p_wrong_guesses + 1;
    cp.p_wrong_spent := cp.p_wrong_spent + v_pen;
    UPDATE public.challenge_participants SET bankroll = cp.bankroll, p_wrong_guesses = cp.p_wrong_guesses, p_wrong_spent = cp.p_wrong_spent
      WHERE match_id = p_id AND user_id = v_uid;
  END IF;
  RETURN public._match_resolve_and_advance(p_id, v_uid);
END; $function$;

CREATE OR REPLACE FUNCTION public._match_board(p_id uuid, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cp public.challenge_participants; m public.challenge_matches; v_pid UUID; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_clue TEXT; v_board JSONB; v_minfo JSONB; v_budget BIGINT; v_default_budget BIGINT;
  v_standing JSONB := NULL; v_field INT; v_finished INT; v_my_spent BIGINT; v_best_spent BIGINT; v_best_total BIGINT; v_ahead INT; v_state TEXT; v_rank INT;
  v_pay_places INT; v_fin_count INT; v_target BIGINT; v_target_kind TEXT; v_cheapest INT; v_wrong_next INT;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  v_default_budget := GREATEST(COALESCE(m.wager,0), 500);
  v_budget := CASE WHEN m.econ_v = 2 THEN public._match_pos_bounty(p_id, cp.position)
                   ELSE COALESCE(cp.start_budget, v_default_budget) END;
  v_cheapest := public._match_cheapest(p_id, p_uid);
  v_wrong_next := public._cg_wrong_pen(v_budget::int, cp.p_wrong_guesses + 1);
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
    'items_allowed', COALESCE(m.items_allowed,false), 'used_powerups', to_jsonb(cp.active_powerups), 'half_off_left', cp.half_off_left,
    'my_debuffs', to_jsonb(COALESCE(cp.debuffs,'{}') || (CASE WHEN cp.vowel_block_left > 0 THEN ARRAY['vowel_block'] ELSE ARRAY[]::text[] END) || (CASE WHEN cp.tax_left > 0 THEN ARRAY['tax'] ELSE ARRAY[]::text[] END)), 'fog_buys_left', cp.fog_buys_left, 'vowel_block_left', cp.vowel_block_left,
    'must_guess', (cp.state = 'active' AND NOT cp.awaiting_next AND (v_cheapest IS NULL OR v_cheapest > cp.bankroll)),
    -- Wrong-solve UI (same curve as Cash Game; terminal state is FOLD, not bust):
    'fold_on_wrong', (cp.state = 'active' AND NOT cp.awaiting_next AND (v_wrong_next IS NULL OR v_wrong_next > cp.bankroll)),
    'wrong_next_cost', v_wrong_next, 'wrong_guess_num', cp.p_wrong_guesses + 1,
    'wrong_pen1', public._cg_wrong_pen(v_budget::int, 1), 'wrong_pen2', public._cg_wrong_pen(v_budget::int, 2),
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

COMMIT;
