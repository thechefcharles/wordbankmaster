-- Decision #8 extra: 'your opponent played — you're up' notification.
-- Fires only on the FIRST completion of a still-open match (no group spam).
-- PITR logged.
BEGIN;
CREATE OR REPLACE FUNCTION public._match_notify_opponent_played(p_id uuid, p_finisher uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE m public.challenge_matches; v_done int; v_name text; r record;
BEGIN
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND OR m.status <> 'open' THEN RETURN; END IF;
  SELECT count(*) INTO v_done FROM public.challenge_participants WHERE match_id = p_id AND state = 'done';
  IF v_done <> 1 THEN RETURN; END IF;          -- only the FIRST finisher pings the waiters
  v_name := public._display_name(p_finisher);
  FOR r IN SELECT user_id FROM public.challenge_participants
           WHERE match_id = p_id AND user_id <> p_finisher AND state IN ('active','invited') LOOP
    PERFORM public._notify(r.user_id, 'challenge_your_turn',
      v_name || ' played your challenge',
      'You''re up — beat their score to take the pot!',
      jsonb_build_object('match_id', p_id, 'route', 'challenge'));
  END LOOP;
END; $fn$;
CREATE OR REPLACE FUNCTION public._match_resolve_and_advance(p_id uuid, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
      PERFORM public._match_maybe_settle(p_id); PERFORM public._match_notify_opponent_played(p_id, p_uid);
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
      PERFORM public._match_maybe_settle(p_id); PERFORM public._match_notify_opponent_played(p_id, p_uid);
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
    PERFORM public._match_maybe_settle(p_id); PERFORM public._match_notify_opponent_played(p_id, p_uid);
  ELSE
    UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
      total_score = cp.bankroll, position = position + 1,
      revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}', p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
    WHERE match_id = p_id AND user_id = p_uid;
  END IF;
  RETURN public._match_board(p_id, p_uid);
END; $function$

;
COMMIT;
