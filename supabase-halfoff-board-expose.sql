-- Expose half_off_left on both boards so the client shows the discount only for the 3 buys.
CREATE OR REPLACE FUNCTION public._climb_board(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_state TEXT; v_board JSONB; v_tier JSONB;
  v_k NUMERIC; v_stake INT; v_cap INT; v_bounty INT; v_budget_left INT; v_cheapest INT; v_balance INT;
  v_solve_reward INT; v_next_cat TEXT; v_next_bounty INT;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_tier := public._cg_tier(cs.tier);
  v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_stake := COALESCE((v_tier->>'stake')::int, 1);
  v_cap := COALESCE((v_tier->>'heat_cap')::int, 250);
  SELECT upper(phrase), category, COALESCE(subcategory,'') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_state := CASE cs.state WHEN 'solved' THEN 'won' WHEN 'busted' THEN 'lost' ELSE 'active' END;
  v_bounty := round(public._climb_bounty(cs.puzzle_id, v_k) * v_stake * cs.heat_x100 / 100.0)::int;
  v_budget_left := CASE WHEN cs.state = 'active' THEN GREATEST(0, v_bounty - cs.spent) ELSE 0 END;
  v_cheapest := public._cg_cheapest(cs);
  v_balance := cs.bankroll + v_budget_left;
  v_solve_reward := v_budget_left;
  IF cs.state = 'solved' AND cs.next_puzzle_id IS NOT NULL THEN
    SELECT category INTO v_next_cat FROM public.daily_puzzles WHERE id = cs.next_puzzle_id;
    v_next_bounty := round(public._climb_bounty(cs.next_puzzle_id, v_k) * v_stake * LEAST(v_cap, cs.heat_x100 + 10) / 100.0)::int;
  END IF;
  v_board := public._daily_board(v_phrase, v_state, cs.bankroll::int, 99, cs.revealed_positions, cs.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('climb', jsonb_build_object(
    'wallet', cs.bankroll, 'bankroll', cs.bankroll, 'balance', v_balance,
    'bounty', v_bounty, 'budget_left', v_budget_left, 'solve_reward', v_solve_reward, 'spent', cs.spent,
    'heat', cs.heat_x100, 'heat_cap', v_cap, 'tier', cs.tier, 'buy_in', cs.buy_in,
    'tier_label', v_tier->>'label', 'stake', v_stake, 'cheapest', v_cheapest,
    'must_guess', (cs.state = 'active' AND (v_cheapest IS NULL OR v_balance < v_cheapest)),
    'position', cs.position, 'last_gain', cs.last_gain, 'state', cs.state,
    'pups_locked', cs.pups_locked, 'equipped', to_jsonb(cs.active_powerups), 'half_off_left', cs.half_off_left,
    'run_solves', cs.run_solves, 'run_profit', cs.bankroll - cs.buy_in,
    'run_interest', cs.run_interest, 'run_spent', cs.run_spent,
    'wrong_count', cs.wrong_count, 'wrong_spent', cs.wrong_spent,
    'last_interest', cs.last_interest,                              -- ← this puzzle's interest $
    'next_bounty', v_next_bounty, 'next_category', v_next_cat));
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
    'items_allowed', COALESCE(m.items_allowed,false), 'used_powerups', to_jsonb(cp.active_powerups), 'half_off_left', cp.half_off_left,
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

REVOKE EXECUTE ON FUNCTION public._climb_board(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._match_board(uuid, uuid) FROM PUBLIC, anon;
