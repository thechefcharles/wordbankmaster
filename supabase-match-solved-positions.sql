-- Challenges: track solved puzzle positions + expose in match detail
--
-- Adds a MATCH-LEVEL accumulator `solved_positions int[]` on challenge_participants.
-- It is appended on every solve in _match_resolve_and_advance (all four win-branch
-- UPDATEs), and is NEVER added to any per-puzzle reset SET-list (so it survives the
-- pack). Folds go through _match_do_fold, which does NOT append -> folded puzzles
-- correctly stay ✗. get_match_detail exposes it additively for the ✓/✗ strip (Task 4).

-- 1. Column (match-level accumulator; defaults only at row creation).
ALTER TABLE public.challenge_participants
  ADD COLUMN IF NOT EXISTS solved_positions int[] NOT NULL DEFAULT '{}';

-- 2. Append cp.position on solve in all four win-branch UPDATEs.
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
  IF COALESCE(m.wager,0) > 0 THEN PERFORM public._record_category_solve(p_uid, v_cat); END IF;  -- friendly (wager 0) earns no category credit
  v_solved := cp.solved + 1;
  IF m.econ_v = 2 THEN
    IF cp.position >= m.pack_size THEN
      UPDATE public.challenge_participants SET solved = v_solved, solved_positions = array_append(solved_positions, cp.position), last_score = cp.bankroll,
        total_score = total_score + cp.bankroll, state = 'done', finished_at = now(), joined_at = COALESCE(joined_at, now())
      WHERE match_id = p_id AND user_id = p_uid;
      PERFORM public._match_maybe_settle(p_id); PERFORM public._match_notify_opponent_played(p_id, p_uid);
    ELSE
      v_next_bounty := public._match_pos_bounty(p_id, cp.position + 1);
      UPDATE public.challenge_participants SET solved = v_solved, solved_positions = array_append(solved_positions, cp.position), last_score = cp.bankroll,
        total_score = total_score + cp.bankroll, position = position + 1,
        bankroll = v_next_bounty, start_budget = COALESCE(start_budget,0) + v_next_bounty,
        revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
        reveal_order = '{}', sabotaged_targets = '{}',
        fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false,
        p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
      WHERE match_id = p_id AND user_id = p_uid;
    END IF;
    RETURN public._match_board(p_id, p_uid);
  END IF;

  -- OLD (econ_v NULL): rank by Cash left; single carried budget, total_score = bankroll.
  IF cp.position >= m.pack_size THEN
    UPDATE public.challenge_participants SET solved = v_solved, solved_positions = array_append(solved_positions, cp.position), last_score = cp.bankroll,
      total_score = cp.bankroll, state = 'done', finished_at = now(), joined_at = COALESCE(joined_at, now())
    WHERE match_id = p_id AND user_id = p_uid;
    PERFORM public._match_maybe_settle(p_id); PERFORM public._match_notify_opponent_played(p_id, p_uid);
  ELSE
    UPDATE public.challenge_participants SET solved = v_solved, solved_positions = array_append(solved_positions, cp.position), last_score = cp.bankroll,
      total_score = cp.bankroll, position = position + 1,
      revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
      reveal_order = '{}', sabotaged_targets = '{}',
      fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false,
      p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
    WHERE match_id = p_id AND user_id = p_uid;
  END IF;
  RETURN public._match_board(p_id, p_uid);
END; $function$;

-- 3. Expose solved_positions in get_match_detail (purely additive).
CREATE OR REPLACE FUNCTION public.get_match_detail(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v_status text; v_settled boolean; v_budget bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.challenge_participants WHERE match_id = p_match_id AND user_id = v_uid) THEN
    RETURN NULL;
  END IF;
  SELECT status, GREATEST(COALESCE(wager,0), 500) INTO v_status, v_budget
  FROM public.challenge_matches WHERE id = p_match_id;
  v_settled := (v_status = 'settled');
  RETURN jsonb_build_object(
    'match', (SELECT jsonb_build_object('id', m.id, 'mode', m.mode, 'pack_size', m.pack_size,
                'wager', m.wager, 'budget', v_budget, 'payout', m.payout, 'status', m.status, 'group_id', m.group_id)
              FROM public.challenge_matches m WHERE m.id = p_match_id),
    'group_name', (SELECT g.name FROM public.groups g
                   JOIN public.challenge_matches cm ON cm.group_id = g.id WHERE cm.id = p_match_id),
    'participants', (SELECT jsonb_agg(jsonb_build_object(
        'user_id', t.user_id, 'name', public._display_name(t.user_id), 'is_me', (t.user_id = v_uid),
        'solved', t.solved, 'score', t.total_score, 'spent', GREATEST(0, COALESCE(t.start_budget, v_budget) - t.total_score - CASE WHEN t.state = 'done' THEN 0 ELSE t.bankroll END),
        'net', t.net, 'earned', t.earned, 'multiple_x100', t.multiple_x100,
        'state', t.state, 'rank', t.rnk, 'elapsed_seconds', public._match_elapsed(t.started_at, t.finished_at, t.joined_at),
        'solved_positions', t.solved_positions
      ) ORDER BY t.total_score DESC)
      FROM (SELECT cp.user_id, cp.solved, cp.total_score, cp.bankroll, cp.start_budget, cp.state, cp.started_at, cp.finished_at, cp.joined_at, cp.solved_positions,
                   rank() OVER (ORDER BY cp.total_score DESC, public._match_elapsed(cp.started_at, cp.finished_at, cp.joined_at) ASC) AS rnk,
                   gr.net, gr.earned, gr.multiple_x100
            FROM public.challenge_participants cp
            LEFT JOIN public.game_results gr ON gr.match_id = p_match_id AND gr.user_id = cp.user_id
            WHERE cp.match_id = p_match_id) t),
    'pack', (SELECT jsonb_agg(jsonb_build_object(
        'position', pk.position, 'category', dp.category,
        'phrase', CASE WHEN v_settled THEN dp.phrase ELSE NULL END
      ) ORDER BY pk.position)
      FROM public.challenge_pack pk JOIN public.daily_puzzles dp ON dp.id = pk.puzzle_id
      WHERE pk.match_id = p_match_id)
  );
END; $function$;
