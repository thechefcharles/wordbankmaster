-- #7: multi-puzzle spent was start_budget - bankroll, double-counting banked winnings
-- (start_budget accumulates every puzzle bounty; bankroll is only the current puzzle).
-- Correct: budget - total_score - (current bankroll unless done). Single-puzzle unchanged.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_match(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); m public.challenge_matches; me public.challenge_participants; v_reveal BOOLEAN; v_parts JSONB; v_default_budget BIGINT;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO me FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_reveal := (me.state = 'done' OR m.status = 'settled');
  v_default_budget := GREATEST(COALESCE(m.wager,0), 500);
  SELECT jsonb_agg(jsonb_build_object('name', public._display_name(cp.user_id), 'state', cp.state,
    'is_me', cp.user_id = v_uid,
    'score', CASE WHEN v_reveal OR cp.user_id = v_uid THEN cp.total_score ELSE NULL END,
    'solved', CASE WHEN v_reveal OR cp.user_id = v_uid THEN cp.solved ELSE NULL END,
    'spent', CASE WHEN v_reveal OR cp.user_id = v_uid THEN GREATEST(0, COALESCE(cp.start_budget, v_default_budget) - cp.total_score - CASE WHEN cp.state = 'done' THEN 0 ELSE cp.bankroll END) ELSE NULL END
  ) ORDER BY (CASE WHEN v_reveal THEN cp.total_score ELSE 0 END) DESC, cp.joined_at NULLS LAST)
  INTO v_parts FROM public.challenge_participants cp WHERE cp.match_id = p_id;
  RETURN jsonb_build_object('id', m.id, 'mode', m.mode, 'categories', m.categories, 'pack_size', m.pack_size,
    'wager', m.wager, 'payout', m.payout, 'status', m.status, 'settles_at', m.settles_at,
    'budget', COALESCE(me.start_budget, v_default_budget),
    'items_allowed', COALESCE(m.items_allowed,false),
    'is_host', m.host_id = v_uid, 'my_state', me.state, 'my_score', me.total_score, 'revealed', v_reveal,
    'participants', COALESCE(v_parts, '[]'::jsonb));
END; $function$;

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
        'state', t.state, 'rank', t.rnk
      ) ORDER BY t.total_score DESC)
      FROM (SELECT cp.user_id, cp.solved, cp.total_score, cp.bankroll, cp.start_budget, cp.state,
                   rank() OVER (ORDER BY cp.total_score DESC) AS rnk,
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

COMMIT;
