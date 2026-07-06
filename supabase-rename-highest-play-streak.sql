-- Rename profiles.highest_win_streak -> highest_play_streak (it's the highest ATTENDANCE/play streak, a misnomer).
BEGIN;
ALTER TABLE public.profiles RENAME COLUMN highest_win_streak TO highest_play_streak;
DROP FUNCTION IF EXISTS public.get_all_users_leaderboard();
DROP FUNCTION IF EXISTS public.get_leaderboard_by_period(p_period text);
CREATE OR REPLACE FUNCTION public.daily_start(p_powerups text[] DEFAULT '{}'::text[], p_use_twist boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_pid UUID; v_phrase TEXT; v_cat TEXT; v_sub TEXT; s public.daily_sessions; v_mod TEXT;
  v_bank BIGINT; v_streak INT; v_high INT; v_last DATE; v_freezes INT; v_day INT; v_att INT := 0; v_new BOOLEAN := false;
  v_fv TEXT; v_reveal INT[] := '{}'; i INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_start: not authenticated'; END IF;
  PERFORM public._ensure_bank(v_uid);
  v_pid := public._todays_puzzle_id();
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
  IF NOT FOUND THEN
    IF v_pid IS NULL THEN RAISE EXCEPTION 'daily_start: no puzzle available'; END IF;
    v_mod := public._daily_modifier();
    INSERT INTO public.daily_sessions (user_id, puzzle_date, puzzle_id, bankroll, guesses_remaining, active_powerups, spent, twist_used)
    VALUES (v_uid, CURRENT_DATE, v_pid, 0, 999, ARRAY[v_mod], 0, true) RETURNING * INTO s;
    v_new := true;
    -- 🎁 auto-apply: reveal letters for the reveal-type Twists
    SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = v_pid;
    IF v_mod = 'free_vowel' THEN
      SELECT substr(v_phrase, g.i+1, 1) INTO v_fv FROM generate_series(0, length(v_phrase)-1) g(i)
        WHERE substr(v_phrase, g.i+1, 1) IN ('A','E','I','O','U') ORDER BY g.i LIMIT 1;
      IF v_fv IS NOT NULL THEN
        SELECT array_agg(g.i) INTO v_reveal FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1, 1) = v_fv;
      END IF;
    ELSIF v_mod = 'head_start' THEN
      FOR i IN 0 .. length(v_phrase)-1 LOOP
        IF substr(v_phrase, i+1, 1) <> ' ' AND (i = 0 OR substr(v_phrase, i, 1) = ' ') THEN v_reveal := v_reveal || i; END IF;
      END LOOP;
    END IF;
    IF array_length(v_reveal, 1) > 0 THEN
      UPDATE public.daily_sessions SET revealed_positions = ARRAY(SELECT DISTINCT unnest(revealed_positions || v_reveal) ORDER BY 1)
        WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE RETURNING * INTO s;
    END IF;
    -- attendance + streak
    SELECT play_streak, highest_play_streak, last_daily_play_date, COALESCE(streak_freezes,0)
      INTO v_streak, v_high, v_last, v_freezes FROM public.profiles WHERE id = v_uid;
    IF v_last = CURRENT_DATE THEN v_day := COALESCE(v_streak,0);
    ELSIF v_last = CURRENT_DATE - 1 THEN v_day := COALESCE(v_streak,0) + 1;
    ELSIF v_last = CURRENT_DATE - 2 AND v_freezes > 0 AND COALESCE(v_streak,0) > 0 THEN v_freezes := v_freezes - 1; v_day := COALESCE(v_streak,0) + 1;
    ELSE v_day := 1; END IF;
    IF v_day > 0 AND v_day % 7 = 0 THEN v_freezes := LEAST(v_freezes + 1, 3); END IF;
    v_high := GREATEST(COALESCE(v_high,0), v_day);
    UPDATE public.profiles SET play_streak = v_day, highest_play_streak = v_high,
      last_daily_play_date = CURRENT_DATE, streak_freezes = v_freezes WHERE id = v_uid;
    v_att := 50 + CASE WHEN v_day % 30 = 0 THEN 1500 WHEN v_day % 14 = 0 THEN 500
                       WHEN v_day % 7 = 0 THEN 250 WHEN v_day = 3 THEN 100 ELSE 0 END;
    PERFORM public._bank_credit(v_uid, v_att, 'attendance');
    IF v_day >= 7 THEN PERFORM public._award_badge(v_uid, 'streak_7'); END IF;
    IF v_day >= 30 THEN PERFORM public._award_badge(v_uid, 'streak_30'); END IF;
  END IF;
  SELECT upper(phrase), category, COALESCE(subcategory, '') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;
  SELECT bank INTO v_bank FROM public.profiles WHERE id = v_uid;
  RETURN public._daily_board(v_phrase, s.state, v_bank::int, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, v_cat, v_sub)
    || jsonb_build_object('live', public._daily_live(s.spent, public._daily_reward_final(v_uid, s.puzzle_id)),
         'modifier', s.active_powerups[1], 'twist_used', s.twist_used, 'bounty_mult', public._daily_bounty_mult(v_uid))
    || CASE WHEN v_new THEN jsonb_build_object('attendance', v_att, 'attendance_day', v_day) ELSE '{}'::jsonb END;
END; $function$

;
CREATE OR REPLACE FUNCTION public.get_all_users_leaderboard()
 RETURNS TABLE(rank bigint, user_id uuid, display_name text, current_bankroll integer, play_streak integer, highest_play_streak integer, puzzles_completed integer, bankroll_earned integer, highest_bankroll integer, win_streak integer, total_wins integer, total_played integer, win_rate numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_week_start DATE;
BEGIN
  v_week_start := date_trunc('week', CURRENT_DATE)::DATE + 1;

  RETURN QUERY
  SELECT
    ROW_NUMBER() OVER (ORDER BY COALESCE(s.puzzles_completed, 0) DESC, COALESCE(s.bankroll_earned, 0) DESC)::BIGINT AS rank,
    prof.id AS user_id,
    COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email', '@', 1), 'Player')::TEXT AS display_name,
    COALESCE(prof.current_bankroll, 1000)::INT AS current_bankroll,
    COALESCE(prof.play_streak, 0)::INT AS play_streak,
    COALESCE(prof.highest_play_streak, 0)::INT AS highest_play_streak,
    COALESCE(s.puzzles_completed, 0)::INT AS puzzles_completed,
    COALESCE(s.bankroll_earned, 0)::INT AS bankroll_earned,
    COALESCE(s.highest_bankroll, 0)::INT AS highest_bankroll,
    COALESCE(s.win_streak, 0)::INT AS win_streak,
    COALESCE(s.total_wins, 0)::INT AS total_wins,
    COALESCE(s.total_played, 0)::INT AS total_played,
    CASE WHEN COALESCE(s.total_played, 0) > 0 THEN ROUND((COALESCE(s.total_wins, 0)::NUMERIC / s.total_played) * 100, 1) ELSE 0 END AS win_rate
  FROM public.profiles prof
  LEFT JOIN auth.users au ON au.id = prof.id
  LEFT JOIN public.user_weekly_stats s ON s.user_id = prof.id AND s.week_start = v_week_start
  ORDER BY COALESCE(s.puzzles_completed, 0) DESC, COALESCE(s.bankroll_earned, 0) DESC;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.get_daily_leaderboard(p_period text DEFAULT 'daily'::text, p_order_by text DEFAULT 'score'::text)
 RETURNS TABLE(rank bigint, user_id uuid, display_name text, score integer, bankroll_left integer, current_streak integer, highest_streak integer, total_played integer, total_wins integer, win_rate numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_start TIMESTAMPTZ; v_end TIMESTAMPTZ;
BEGIN
  CASE p_period
    WHEN 'weekly' THEN v_start := ((date_trunc('week', CURRENT_DATE)::DATE + 1)::TIMESTAMP) AT TIME ZONE 'UTC'; v_end := v_start + INTERVAL '7 days';
    WHEN 'monthly' THEN v_start := date_trunc('month', CURRENT_DATE) AT TIME ZONE 'UTC'; v_end := v_start + INTERVAL '1 month';
    WHEN 'yearly' THEN v_start := date_trunc('year', CURRENT_DATE) AT TIME ZONE 'UTC'; v_end := v_start + INTERVAL '1 year';
    ELSE v_start := date_trunc('day', CURRENT_DATE) AT TIME ZONE 'UTC'; v_end := v_start + INTERVAL '1 day';
  END CASE;
  RETURN QUERY
  WITH agg AS (
    SELECT gr.user_id, MAX(gr.score)::INT AS score, MAX(gr.bankroll_left)::INT AS bankroll_left,
      COUNT(*)::INT AS total_played, COUNT(*) FILTER (WHERE gr.won)::INT AS total_wins
    FROM public.game_results gr
    WHERE gr.played_at >= v_start AND gr.played_at < v_end AND (gr.game_mode = 'daily' OR gr.game_mode IS NULL)
    GROUP BY gr.user_id
  ),
  base AS (
    SELECT prof.id AS user_id,
      COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email', '@', 1), 'Player')::TEXT AS display_name,
      agg.score, agg.bankroll_left,
      COALESCE(prof.play_streak, 0)::INT AS current_streak,
      COALESCE(prof.highest_play_streak, 0)::INT AS highest_streak,
      agg.total_played, agg.total_wins,
      (CASE WHEN agg.total_played > 0 THEN ROUND((agg.total_wins::NUMERIC / agg.total_played) * 100, 1) ELSE 0 END)::NUMERIC AS win_rate
    FROM agg JOIN public.profiles prof ON prof.id = agg.user_id LEFT JOIN auth.users au ON au.id = prof.id
  )
  SELECT ROW_NUMBER() OVER (ORDER BY
      CASE WHEN p_order_by = 'bankroll' THEN base.bankroll_left END DESC NULLS LAST,
      CASE WHEN p_order_by = 'streak' THEN base.current_streak END DESC NULLS LAST,
      CASE WHEN p_order_by = 'highest_streak' THEN base.highest_streak END DESC NULLS LAST,
      CASE WHEN p_order_by = 'puzzles' THEN base.total_played END DESC NULLS LAST,
      CASE WHEN p_order_by = 'win_pct' THEN base.win_rate END DESC NULLS LAST,
      CASE WHEN p_order_by = 'score' THEN base.score END DESC NULLS LAST,
      base.score DESC NULLS LAST)::BIGINT AS rank,
    base.user_id, base.display_name, base.score, base.bankroll_left,
    base.current_streak, base.highest_streak, base.total_played, base.total_wins, base.win_rate
  FROM base
  ORDER BY
    CASE WHEN p_order_by = 'bankroll' THEN base.bankroll_left END DESC NULLS LAST,
    CASE WHEN p_order_by = 'streak' THEN base.current_streak END DESC NULLS LAST,
    CASE WHEN p_order_by = 'highest_streak' THEN base.highest_streak END DESC NULLS LAST,
    CASE WHEN p_order_by = 'puzzles' THEN base.total_played END DESC NULLS LAST,
    CASE WHEN p_order_by = 'win_pct' THEN base.win_rate END DESC NULLS LAST,
    CASE WHEN p_order_by = 'score' THEN base.score END DESC NULLS LAST,
    base.score DESC NULLS LAST;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.get_leaderboard_by_period(p_period text DEFAULT 'weekly'::text)
 RETURNS TABLE(rank bigint, user_id uuid, display_name text, current_bankroll integer, play_streak integer, highest_play_streak integer, puzzles_completed integer, bankroll_earned integer, highest_bankroll integer, win_streak integer, total_wins integer, total_played integer, win_rate numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_start TIMESTAMPTZ;
  v_end TIMESTAMPTZ;
BEGIN
  CASE p_period
    WHEN 'daily' THEN
      v_start := date_trunc('day', CURRENT_DATE) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '1 day';
    WHEN 'weekly' THEN
      v_start := ((date_trunc('week', CURRENT_DATE)::DATE + 1)::TIMESTAMP) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '7 days';
    WHEN 'monthly' THEN
      v_start := date_trunc('month', CURRENT_DATE) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '1 month';
    WHEN 'yearly' THEN
      v_start := date_trunc('year', CURRENT_DATE) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '1 year';
    ELSE
      v_start := ((date_trunc('week', CURRENT_DATE)::DATE + 1)::TIMESTAMP) AT TIME ZONE 'UTC';
      v_end := v_start + INTERVAL '7 days';
  END CASE;

  RETURN QUERY
  WITH period_agg AS (
    SELECT
      gr.user_id,
      COUNT(*) FILTER (WHERE gr.won)::INT AS puzzles_completed,
      COALESCE(SUM(gr.bankroll_left) FILTER (WHERE gr.won), 0)::INT AS bankroll_earned,
      COALESCE(MAX(gr.bankroll_left), 0)::INT AS highest_bankroll,
      COUNT(*)::INT AS total_played,
      COUNT(*) FILTER (WHERE gr.won)::INT AS total_wins
    FROM public.game_results gr
    WHERE gr.played_at >= v_start AND gr.played_at < v_end
    GROUP BY gr.user_id
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY COALESCE(prof.current_bankroll, 1000) DESC)::BIGINT AS rank,
    prof.id AS user_id,
    COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email', '@', 1), 'Player')::TEXT AS display_name,
    COALESCE(prof.current_bankroll, 1000)::INT AS current_bankroll,
    COALESCE(prof.play_streak, 0)::INT AS play_streak,
    COALESCE(prof.highest_play_streak, 0)::INT AS highest_play_streak,
    COALESCE(pa.puzzles_completed, 0)::INT AS puzzles_completed,
    COALESCE(pa.bankroll_earned, 0)::INT AS bankroll_earned,
    COALESCE(pa.highest_bankroll, 0)::INT AS highest_bankroll,
    COALESCE(pa.puzzles_completed, 0)::INT AS win_streak,
    COALESCE(pa.total_wins, 0)::INT AS total_wins,
    COALESCE(pa.total_played, 0)::INT AS total_played,
    CASE WHEN COALESCE(pa.total_played, 0) > 0 THEN ROUND((COALESCE(pa.total_wins, 0)::NUMERIC / pa.total_played) * 100, 1) ELSE 0 END AS win_rate
  FROM public.profiles prof
  LEFT JOIN auth.users au ON au.id = prof.id
  LEFT JOIN period_agg pa ON pa.user_id = prof.id
  ORDER BY COALESCE(prof.current_bankroll, 1000) DESC;
END;
$function$

;
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
    'net_worth', COALESCE(p.bank,0), 'cash', COALESCE(p.bank,0),
    'overall', (SELECT jsonb_build_object(
        'puzzles_solved', COALESCE(sum(COALESCE(solved_count, CASE WHEN outcome='won' THEN 1 ELSE 0 END)),0),
        'games_played', count(*), 'earned', COALESCE(sum(earned),0), 'spent', COALESCE(sum(spent),0),
        'avg_multiple', round(avg(multiple_x100) FILTER (WHERE multiple_x100 IS NOT NULL))::int,
        'best_multiple', max(multiple_x100), 'clean_solves', count(*) FILTER (WHERE clean))
      FROM public.game_results WHERE user_id = v_uid),
    -- Daily includes make-ups (a make-up IS a daily, just played late).
    'daily', (SELECT jsonb_build_object(
        'current_streak', COALESCE(p.play_streak,0), 'best_streak', COALESCE(p.highest_play_streak,0), 'win_streak', (CASE WHEN p.last_daily_solve_date >= CURRENT_DATE - 1 THEN COALESCE(p.current_solve_streak,0) ELSE 0 END), 'best_win_streak', COALESCE(p.best_solve_streak,0),
        'played', count(*), 'won', count(*) FILTER (WHERE outcome='won'),
        'best_multiple', max(multiple_x100), 'fastest_ms', min(time_ms) FILTER (WHERE outcome='won'))
      FROM public.game_results WHERE user_id = v_uid AND game_mode IN ('daily','makeup')),
    'cash_game', jsonb_build_object('position', COALESCE(v_climb,0)) ||
      (SELECT jsonb_build_object('solved', count(*) FILTER (WHERE outcome='won'),
        'earned', COALESCE(sum(earned) FILTER (WHERE outcome='won'),0),
        'best_multiple', max(multiple_x100), 'fastest_ms', min(time_ms) FILTER (WHERE outcome='won'))
       FROM public.game_results WHERE user_id = v_uid AND game_mode='climb'),
    -- 1v1 = challenge rows with no group; record vs people
    'challenges_1v1', (SELECT jsonb_build_object(
        'wins', count(*) FILTER (WHERE outcome='won'), 'losses', count(*) FILTER (WHERE outcome='lost'),
        'ties', count(*) FILTER (WHERE outcome='tie'), 'played', count(*),
        'biggest_pot', COALESCE(max(earned) FILTER (WHERE outcome='won'),0))
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
CREATE OR REPLACE FUNCTION public.get_profile_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); p public.profiles; v_climb INT; v_cwins INT; v_closs INT; v_cties INT;
  v_badges JSONB; v_avg INT; v_best INT; v_solved INT; v_earned BIGINT; v_spent BIGINT; v_dplayed INT; v_dwon INT;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT * INTO p FROM public.profiles WHERE id = v_uid;
  SELECT position INTO v_climb FROM public.climb_state WHERE user_id = v_uid;
  SELECT
    count(*) FILTER (WHERE game_mode='challenge' AND outcome='won'),
    count(*) FILTER (WHERE game_mode='challenge' AND outcome='lost'),
    count(*) FILTER (WHERE game_mode='challenge' AND outcome='tie'),
    round(avg(multiple_x100) FILTER (WHERE multiple_x100 IS NOT NULL))::int,
    max(multiple_x100),
    COALESCE(sum(COALESCE(solved_count, CASE WHEN outcome='won' THEN 1 ELSE 0 END)),0),
    COALESCE(sum(earned),0), COALESCE(sum(spent),0),
    count(*) FILTER (WHERE game_mode='daily'),
    count(*) FILTER (WHERE game_mode='daily' AND outcome='won')
  INTO v_cwins, v_closs, v_cties, v_avg, v_best, v_solved, v_earned, v_spent, v_dplayed, v_dwon
  FROM public.game_results WHERE user_id = v_uid;
  SELECT COALESCE(jsonb_agg(badge), '[]'::jsonb) INTO v_badges FROM public.user_badges WHERE user_id = v_uid;
  RETURN jsonb_build_object(
    'username', p.username,
    'net_worth', COALESCE(p.bank,0), 'cash', COALESCE(p.bank,0),
    'current_streak', COALESCE(p.play_streak,0), 'longest_streak', COALESCE(p.highest_play_streak,0),
    'games_played', v_dplayed, 'games_won', v_dwon,
    'puzzles_solved', v_solved, 'climb_position', COALESCE(v_climb,0),
    'challenge_wins', COALESCE(v_cwins,0), 'challenge_losses', COALESCE(v_closs,0), 'challenge_ties', COALESCE(v_cties,0),
    'avg_multiple_x100', v_avg, 'best_multiple_x100', v_best,
    'total_earned', v_earned, 'total_spent', v_spent,
    'badges', v_badges);
END; $function$

;
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
    'net_worth', COALESCE(p.bank,0), 'cash', COALESCE(p.bank,0),
    'current_streak', COALESCE(p.play_streak,0), 'longest_streak', COALESCE(p.highest_play_streak,0),
    'games_played', v_dplayed, 'games_won', v_dwon,
    'puzzles_solved', v_solved, 'climb_position', COALESCE(v_climb,0),
    'challenge_wins', COALESCE(v_cwins,0), 'avg_multiple_x100', v_avg, 'best_multiple_x100', v_best,
    'badges', v_badges,
    'friends', (SELECT COALESCE(jsonb_agg(jsonb_build_object('username', p2.username, 'name', public._display_name(p2.id)) ORDER BY p2.username), '[]'::jsonb) FROM public.friendships f JOIN public.profiles p2 ON p2.id = f.friend_id WHERE f.user_id = v_tid AND p2.username IS NOT NULL),
    'groups', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'my_status', CASE WHEN g.owner_id = v_uid OR EXISTS(SELECT 1 FROM public.group_members gm2 WHERE gm2.group_id=g.id AND gm2.user_id=v_uid) THEN 'member' WHEN EXISTS(SELECT 1 FROM public.group_join_requests jr WHERE jr.group_id=g.id AND jr.requester_id=v_uid) THEN 'requested' ELSE 'none' END) ORDER BY g.name), '[]'::jsonb) FROM public.group_members gm JOIN public.groups g ON g.id = gm.group_id WHERE gm.user_id = v_tid), 'is_self', (v_uid IS NOT DISTINCT FROM v_tid), 'is_friend', v_is_friend,
    'request_outgoing', v_req_out, 'request_incoming', v_req_in, 'head_to_head', v_h2h
  );
END; $function$

;
CREATE OR REPLACE FUNCTION public.get_streak_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_cur INT; v_high INT; v_fz INT; v_days JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  SELECT COALESCE(play_streak,0), COALESCE(highest_play_streak,0), COALESCE(streak_freezes,0)
    INTO v_cur, v_high, v_fz FROM public.profiles WHERE id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('d', puzzle_date, 'won', state = 'won') ORDER BY puzzle_date), '[]'::jsonb)
    INTO v_days
  FROM public.daily_sessions
  WHERE user_id = v_uid AND state <> 'active' AND puzzle_date >= (CURRENT_DATE - INTERVAL '70 days');
  RETURN jsonb_build_object('current_streak', COALESCE(v_cur,0), 'highest_streak', COALESCE(v_high,0),
    'freezes', COALESCE(v_fz,0), 'days', COALESCE(v_days, '[]'::jsonb));
END; $function$

;
CREATE OR REPLACE FUNCTION public.record_daily_result(p_user_id uuid, p_won boolean, p_bankroll_left integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_week_start DATE;
  v_current_streak INT;
  v_highest_streak INT;
  v_last_win DATE;
  v_last_play DATE;
  v_bankroll INT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'record_daily_result: not authenticated';
  END IF;

  v_bankroll := LEAST(GREATEST(COALESCE(p_bankroll_left, 0), 0), 1000);

  v_week_start := date_trunc('week', CURRENT_DATE)::DATE + 1; -- Tuesday-keyed league week

  SELECT play_streak, highest_play_streak, last_daily_win_date, last_daily_play_date
  INTO v_current_streak, v_highest_streak, v_last_win, v_last_play
  FROM public.profiles WHERE id = v_uid;

  -- Enforce one daily result per day, server-side.
  IF v_last_play = CURRENT_DATE THEN
    RETURN;
  END IF;

  IF p_won THEN
    IF v_last_win = CURRENT_DATE - 1 THEN
      v_current_streak := COALESCE(v_current_streak, 0) + 1;
    ELSIF v_last_win IS DISTINCT FROM CURRENT_DATE THEN
      v_current_streak := 1;
    END IF;
    v_highest_streak := GREATEST(COALESCE(v_highest_streak, 0), v_current_streak);
    UPDATE public.profiles SET
      play_streak = v_current_streak,
      highest_play_streak = v_highest_streak,
      last_daily_win_date = CURRENT_DATE,
      last_daily_play_date = CURRENT_DATE,
      daily_bankroll = v_bankroll,
      last_daily_won = true
    WHERE id = v_uid;
  ELSE
    v_current_streak := 0;
    UPDATE public.profiles SET
      play_streak = 0,
      last_daily_play_date = CURRENT_DATE,
      daily_bankroll = v_bankroll,
      last_daily_won = false
    WHERE id = v_uid;
  END IF;

  INSERT INTO public.game_results (user_id, played_at, won, bankroll_left, game_mode)
  VALUES (v_uid, NOW(), p_won, v_bankroll, 'daily');

  INSERT INTO public.user_weekly_stats (user_id, week_start, puzzles_completed, bankroll_earned, highest_bankroll, total_wins, total_played, win_streak)
  VALUES (
    v_uid, v_week_start,
    CASE WHEN p_won THEN 1 ELSE 0 END,
    CASE WHEN p_won THEN v_bankroll ELSE 0 END,
    v_bankroll,
    CASE WHEN p_won THEN 1 ELSE 0 END,
    1,
    COALESCE(v_current_streak, 0)
  )
  ON CONFLICT (user_id, week_start) DO UPDATE SET
    total_played = user_weekly_stats.total_played + 1,
    total_wins = user_weekly_stats.total_wins + CASE WHEN p_won THEN 1 ELSE 0 END,
    puzzles_completed = user_weekly_stats.puzzles_completed + CASE WHEN p_won THEN 1 ELSE 0 END,
    bankroll_earned = user_weekly_stats.bankroll_earned + CASE WHEN p_won THEN v_bankroll ELSE 0 END,
    highest_bankroll = GREATEST(user_weekly_stats.highest_bankroll, v_bankroll),
    win_streak = GREATEST(user_weekly_stats.win_streak, v_current_streak);
END;
$function$

;
COMMIT;
