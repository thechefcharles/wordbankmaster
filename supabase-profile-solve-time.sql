-- Add per-puzzle avg/best solve time to get_profile_detail.challenges_1v1.
CREATE OR REPLACE FUNCTION public.get_profile_detail()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); p public.profiles; v_climb int;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT * INTO p FROM public.profiles WHERE id = v_uid;
  SELECT position INTO v_climb FROM public.climb_state WHERE user_id = v_uid;
  RETURN jsonb_build_object(
    'username', p.username, 'color', p.equipped_color, 'title', p.equipped_title,
    'account_number', p.account_number, 'member_no', p.member_no,
    'net_worth', COALESCE(p.bank,0), 'cash', COALESCE(p.bank,0),
    'overall', (SELECT jsonb_build_object(
        'puzzles_solved', COALESCE(sum(COALESCE(solved_count, CASE WHEN outcome='won' THEN 1 ELSE 0 END)),0),
        'games_played', count(*), 'earned', COALESCE(sum(earned),0), 'spent', COALESCE(sum(spent),0),
        'avg_multiple', round(avg(multiple_x100) FILTER (WHERE multiple_x100 IS NOT NULL))::int,
        'best_multiple', max(multiple_x100), 'clean_solves', count(*) FILTER (WHERE clean))
      FROM public.game_results WHERE user_id = v_uid),
    -- Daily includes make-ups (a make-up IS a daily, just played late).
    'daily', (SELECT jsonb_build_object(
        'current_streak', COALESCE(p.current_daily_play_streak,0), 'best_streak', COALESCE(p.best_daily_play_streak,0), 'win_streak', (CASE WHEN p.last_daily_solve_date >= CURRENT_DATE - 1 THEN COALESCE(p.current_daily_solve_streak,0) ELSE 0 END), 'best_win_streak', COALESCE(p.best_daily_solve_streak,0),
        'played', count(*), 'won', count(*) FILTER (WHERE outcome='won'),
        'best_multiple', max(multiple_x100), 'fastest_ms', min(time_ms) FILTER (WHERE outcome='won'), 'best_bounty', COALESCE(max(net) FILTER (WHERE outcome='won'),0))
      FROM public.game_results WHERE user_id = v_uid AND game_mode IN ('daily','makeup')),
    'cash_game', jsonb_build_object('position', COALESCE(v_climb,0)) ||
      (SELECT jsonb_build_object('solved', count(*) FILTER (WHERE outcome='won'),
        'earned', COALESCE(sum(earned) FILTER (WHERE outcome='won'),0),
        'best_multiple', max(multiple_x100), 'fastest_ms', min(time_ms) FILTER (WHERE outcome='won'))
       FROM public.game_results WHERE user_id = v_uid AND game_mode='climb') || jsonb_build_object('net', COALESCE(p.cg_lifetime_net,0)),
    -- 1v1 = challenge rows with no group; record vs people
    'challenges_1v1', (SELECT jsonb_build_object(
        'wins', count(*) FILTER (WHERE outcome='won'), 'losses', count(*) FILTER (WHERE outcome='lost'),
        'ties', count(*) FILTER (WHERE outcome='tie'), 'played', count(*),
        'biggest_pot', COALESCE(max(earned) FILTER (WHERE outcome='won'),0),
        'avg_solve_seconds', (SELECT round(avg(extract(epoch from (cp.finished_at - cp.started_at))/greatest(cp.solved,1)))::int FROM public.challenge_participants cp JOIN public.challenge_matches cm ON cm.id=cp.match_id WHERE cp.user_id=v_uid AND cm.group_id IS NULL AND cp.state='done' AND cp.solved>0 AND cp.started_at IS NOT NULL AND cp.finished_at IS NOT NULL),
        'best_solve_seconds', (SELECT round(min(extract(epoch from (cp.finished_at - cp.started_at))/greatest(cp.solved,1)))::int FROM public.challenge_participants cp JOIN public.challenge_matches cm ON cm.id=cp.match_id WHERE cp.user_id=v_uid AND cm.group_id IS NULL AND cp.state='done' AND cp.solved>0 AND cp.started_at IS NOT NULL AND cp.finished_at IS NOT NULL))
      FROM public.game_results WHERE user_id = v_uid AND game_mode='challenge' AND group_id IS NULL),
    -- group challenges = your placement in the pack
    'challenges_group', (SELECT jsonb_build_object(
        'played', count(*), 'wins', count(*) FILTER (WHERE rank = 1),
        'podiums', count(*) FILTER (WHERE rank <= 3),
        'biggest_pot', COALESCE(max(earned) FILTER (WHERE outcome='won'),0))
      FROM public.game_results WHERE user_id = v_uid AND game_mode='challenge' AND group_id IS NOT NULL),
    'categories', (SELECT COALESCE(jsonb_agg(jsonb_build_object('category', category, 'solves', solves, 'best_multiple', bm) ORDER BY solves DESC), '[]'::jsonb)
      FROM (SELECT category, sum(COALESCE(solved_count, CASE WHEN outcome='won' THEN 1 ELSE 0 END)) AS solves, max(multiple_x100) AS bm
            FROM public.game_results WHERE user_id = v_uid AND category IS NOT NULL
            GROUP BY category HAVING sum(COALESCE(solved_count, CASE WHEN outcome='won' THEN 1 ELSE 0 END)) > 0) c),
    -- Rivals: your head-to-head record vs each 1v1 opponent
    'rivals', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'name', public._display_name(opponent_id), 'wins', wins, 'losses', losses, 'ties', ties) ORDER BY played DESC, wins DESC), '[]'::jsonb)
      FROM (SELECT opponent_id, count(*) AS played,
              count(*) FILTER (WHERE outcome='won') AS wins,
              count(*) FILTER (WHERE outcome='lost') AS losses,
              count(*) FILTER (WHERE outcome='tie') AS ties
            FROM public.game_results
            WHERE user_id = v_uid AND game_mode='challenge' AND opponent_id IS NOT NULL
            GROUP BY opponent_id ORDER BY played DESC LIMIT 8) r)
  );
END; $function$

;
