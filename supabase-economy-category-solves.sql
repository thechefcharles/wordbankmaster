-- ============================================================================
-- Phase 5 — count Cash Game + Challenge solves toward category badges.
-- (Decision #5) Today only daily/arcade/freeplay call _record_category_solve;
-- climb (_climb_resolve) and match (_match_resolve_and_advance) don't. Add the
-- call on each solve. Both functions are re-created from their current (Phase 1/3)
-- bodies with only the new PERFORM added. Additive (a counter INSERT). PITR logged.
-- ============================================================================
BEGIN;

-- Cash Game: record the solved puzzle's category (current body = Phase 3 version).
CREATE OR REPLACE FUNCTION public._climb_resolve(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_won BOOLEAN; v_tier JSONB; v_k NUMERIC; v_stake INT; v_cap INT;
  v_bounty INT; v_keep INT; v_payout INT; v_cat TEXT; v_time INT; v_next UUID;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF cs.state <> 'active' THEN RETURN public._climb_board(p_uid); END IF;
  v_tier := public._cg_tier(cs.tier); v_k := COALESCE((v_tier->>'k')::numeric, 0.85);
  v_cap := COALESCE((v_tier->>'heat_cap')::int, 250); v_stake := COALESCE((v_tier->>'stake')::int, 1);
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(cs.revealed_positions)));
  IF v_won THEN
    v_bounty := public._climb_bounty(cs.puzzle_id, v_k) * v_stake;
    v_keep := GREATEST(0, v_bounty - cs.spent);
    v_payout := round(v_keep * cs.heat_x100 / 100.0)::int;
    v_time := LEAST(GREATEST(EXTRACT(epoch FROM (now() - COALESCE(cs.puzzle_started_at, cs.updated_at))) * 1000, 0), 1800000)::int;
    v_next := public._pick_casual(p_uid, null, cs.puzzle_id, 0);
    UPDATE public.climb_state SET state = 'solved', last_gain = v_payout,
      bankroll = cs.bankroll + v_payout,
      heat_x100 = LEAST(v_cap, cs.heat_x100 + 10),
      run_solves = cs.run_solves + 1, next_puzzle_id = v_next, updated_at = now() WHERE user_id = p_uid;
    PERFORM public._record_category_solve(p_uid, v_cat);           -- NEW: counts toward category badges
    PERFORM public._log_game_result(p_uid,'climb','won', cs.puzzle_id, v_cat, 1, 1, cs.spent::int, v_payout, v_time);
  ELSE
    UPDATE public.climb_state SET state = 'active', updated_at = now() WHERE user_id = p_uid;
  END IF;
  RETURN public._climb_board(p_uid);
END; $function$;

-- Challenge: record the solved puzzle's category (current body = Phase 1 version).
CREATE OR REPLACE FUNCTION public._match_resolve_and_advance(p_id uuid, p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE cp public.challenge_participants; m public.challenge_matches; v_phrase TEXT; v_cat TEXT; v_won BOOLEAN;
  v_score INT; v_combo INT; v_solved INT; v_budget BIGINT; v_next_bounty INT;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF cp.state <> 'active' THEN RETURN public._match_board(p_id, p_uid); END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  v_budget := GREATEST(COALESCE(m.wager,0), 500);
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = public._match_pid(p_id, cp.position);
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(cp.revealed_positions)));
  IF NOT v_won THEN RETURN public._match_board(p_id, p_uid); END IF;
  PERFORM public._record_category_solve(p_uid, v_cat);            -- NEW: counts toward category badges
  v_solved := cp.solved + 1;
  IF m.mode = 'blitz' THEN
    v_score := round(300 * cp.combo_x100 / 100.0)::int; v_combo := LEAST(300, cp.combo_x100 + 25);
    IF cp.position >= m.pack_size THEN
      UPDATE public.challenge_participants SET total_score = total_score + v_score, last_score = v_score,
        combo_x100 = v_combo, solved = v_solved, state = 'done', joined_at = COALESCE(joined_at, now())
      WHERE match_id = p_id AND user_id = p_uid;
      PERFORM public._match_maybe_settle(p_id);
    ELSE
      UPDATE public.challenge_participants SET total_score = total_score + v_score, last_score = v_score, position = position + 1,
        solved = v_solved, bankroll = v_budget, revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
        p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0, combo_x100 = v_combo WHERE match_id = p_id AND user_id = p_uid;
    END IF;
    RETURN public._match_board(p_id, p_uid);
  END IF;

  IF m.econ_v = 2 THEN
    IF cp.position >= m.pack_size THEN
      UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
        total_score = total_score + cp.bankroll, state = 'done', joined_at = COALESCE(joined_at, now())
      WHERE match_id = p_id AND user_id = p_uid;
      PERFORM public._match_maybe_settle(p_id);
    ELSE
      v_next_bounty := public._match_pos_bounty(p_id, cp.position + 1);
      UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
        total_score = total_score + cp.bankroll, position = position + 1,
        bankroll = v_next_bounty, start_budget = COALESCE(start_budget,0) + v_next_bounty,
        revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
        p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
      WHERE match_id = p_id AND user_id = p_uid;
    END IF;
    RETURN public._match_board(p_id, p_uid);
  END IF;

  -- OLD (econ_v NULL): rank by Cash left; single carried budget, total_score = bankroll.
  IF cp.position >= m.pack_size THEN
    UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
      total_score = cp.bankroll, state = 'done', joined_at = COALESCE(joined_at, now())
    WHERE match_id = p_id AND user_id = p_uid;
    PERFORM public._match_maybe_settle(p_id);
  ELSE
    UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
      total_score = cp.bankroll, position = position + 1,
      revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}', p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
    WHERE match_id = p_id AND user_id = p_uid;
  END IF;
  RETURN public._match_board(p_id, p_uid);
END; $function$;

COMMIT;
