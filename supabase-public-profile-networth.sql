-- Public profile: net_worth = bank - loan (was just bank; loans made it gameable).
CREATE OR REPLACE FUNCTION public.get_public_profile(p_username text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_tid uuid; p public.profiles;
  v_climb int; v_cwins int; v_badges jsonb; v_avg int; v_best int; v_solved int; v_dplayed int; v_dwon int;
  v_is_friend boolean; v_req_out boolean; v_req_in boolean; v_h2h jsonb;
BEGIN
  SELECT id INTO v_tid FROM public.profiles WHERE lower(username) = lower(p_username);
  IF v_tid IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO p FROM public.profiles WHERE id = v_tid;
  SELECT position INTO v_climb FROM public.climb_state WHERE user_id = v_tid;
  SELECT count(*) INTO v_cwins FROM public.challenge_matches m
    JOIN public.challenge_participants cp ON cp.match_id = m.id AND cp.user_id = v_tid
    WHERE m.status = 'settled'
      AND cp.total_score = (SELECT max(total_score) FROM public.challenge_participants x WHERE x.match_id = m.id);
  SELECT COALESCE(jsonb_agg(badge), '[]'::jsonb) INTO v_badges FROM public.user_badges WHERE user_id = v_tid;
  SELECT round(avg(multiple_x100))::int, max(multiple_x100),
         COALESCE(sum(COALESCE(solved_count, CASE WHEN outcome='won' THEN 1 ELSE 0 END)),0),
         count(*) FILTER (WHERE game_mode='daily'),
         count(*) FILTER (WHERE game_mode='daily' AND outcome='won')
    INTO v_avg, v_best, v_solved, v_dplayed, v_dwon
    FROM public.game_results WHERE user_id = v_tid;
  v_is_friend := EXISTS (SELECT 1 FROM public.friendships WHERE user_id = v_uid AND friend_id = v_tid);
  v_req_out := EXISTS (SELECT 1 FROM public.friend_requests WHERE requester = v_uid AND addressee = v_tid);
  v_req_in  := EXISTS (SELECT 1 FROM public.friend_requests WHERE requester = v_tid AND addressee = v_uid);
  IF v_uid IS DISTINCT FROM v_tid THEN v_h2h := public.get_head_to_head(v_tid); END IF;
  RETURN jsonb_build_object(
    'id', v_tid, 'username', p.username, 'avatar', p.avatar, 'name', public._display_name(v_tid),
    'title', p.equipped_title, 'color', p.equipped_color,
    'net_worth', (COALESCE(p.bank,0) - COALESCE(p.loan,0)), 'cash', COALESCE(p.bank,0),
    'credit_score', COALESCE(p.credit_score, 650), 'credit_tier', public._credit_tier(COALESCE(p.credit_score,650)),
    'current_streak', COALESCE(p.current_daily_play_streak,0), 'longest_streak', COALESCE(p.best_daily_play_streak,0),
    'games_played', v_dplayed, 'games_won', v_dwon,
    'puzzles_solved', v_solved, 'climb_position', COALESCE(v_climb,0),
    'challenge_wins', COALESCE(v_cwins,0), 'avg_multiple_x100', v_avg, 'best_multiple_x100', v_best,
    'badges', v_badges,
    'friends', (SELECT COALESCE(jsonb_agg(jsonb_build_object('username', p2.username, 'name', public._display_name(p2.id), 'is_self', (p2.id = v_uid), 'status', CASE WHEN p2.id = v_uid THEN 'self' WHEN EXISTS(SELECT 1 FROM public.friendships fx WHERE fx.user_id = v_uid AND fx.friend_id = p2.id) THEN 'friends' WHEN EXISTS(SELECT 1 FROM public.friend_requests rq WHERE rq.requester = v_uid AND rq.addressee = p2.id) THEN 'pending_out' WHEN EXISTS(SELECT 1 FROM public.friend_requests rq WHERE rq.requester = p2.id AND rq.addressee = v_uid) THEN 'pending_in' ELSE 'none' END) ORDER BY p2.username), '[]'::jsonb) FROM public.friendships f JOIN public.profiles p2 ON p2.id = f.friend_id WHERE f.user_id = v_tid AND p2.username IS NOT NULL),
    'groups', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'my_status', CASE WHEN g.owner_id = v_uid OR EXISTS(SELECT 1 FROM public.group_members gm2 WHERE gm2.group_id=g.id AND gm2.user_id=v_uid) THEN 'member' WHEN EXISTS(SELECT 1 FROM public.group_join_requests jr WHERE jr.group_id=g.id AND jr.requester_id=v_uid) THEN 'requested' ELSE 'none' END) ORDER BY g.name), '[]'::jsonb) FROM public.group_members gm JOIN public.groups g ON g.id = gm.group_id WHERE gm.user_id = v_tid), 'is_self', (v_uid IS NOT DISTINCT FROM v_tid), 'is_friend', v_is_friend,
    'request_outgoing', v_req_out, 'request_incoming', v_req_in, 'head_to_head', v_h2h
  );
END; $function$

;
