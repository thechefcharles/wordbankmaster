-- Wrong-guess penalty: each wrong phrase guess drops the bounty multiplier by 0.2 (floor 1.0)
-- and docks 5 off the Efficiency score (floor 0). Uses daily_sessions.p_wrong_guesses.
BEGIN;
ALTER TABLE public.game_results ADD COLUMN IF NOT EXISTS wrong_guesses int NOT NULL DEFAULT 0;
CREATE OR REPLACE FUNCTION public._daily_bounty_mult(p_uid uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER AS $fn$
  SELECT GREATEST(1.0, LEAST(3.0,
    1.0
    + LEAST(0.1 * GREATEST(0, COALESCE(
        (SELECT CASE WHEN last_daily_solve_date >= CURRENT_DATE - 1 THEN current_daily_solve_streak ELSE 0 END
         FROM public.profiles WHERE id = p_uid), 0)), 0.5)
    + COALESCE((SELECT bounty_boost FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE), 0)
  ) - 0.2 * COALESCE((SELECT p_wrong_guesses FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE), 0));
$fn$;
CREATE OR REPLACE FUNCTION public._finalize_daily(p_uid uuid, p_won boolean, p_spent integer, p_incorrect_count integer DEFAULT 0)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_week_start DATE; v_pid UUID; v_reward INT; v_net INT; v_streak INT; v_cat TEXT; v_spent INT; v_started TIMESTAMPTZ; v_time INT; v_used BOOLEAN; v_earned INT; v_wrong INT;
  v_ss INT; v_bss INT; v_lss DATE; v_grant TEXT;
BEGIN
  v_week_start := date_trunc('week', CURRENT_DATE)::DATE + 1;
  SELECT puzzle_id, created_at, twist_used, COALESCE(p_wrong_guesses,0) INTO v_pid, v_started, v_used, v_wrong FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;
  SELECT category INTO v_cat FROM public.daily_puzzles WHERE id = v_pid;
  v_reward := public._daily_reward_final(p_uid, v_pid);
  v_spent  := GREATEST(0, COALESCE(p_spent,0));
  v_time := LEAST(GREATEST(EXTRACT(epoch FROM (now() - v_started)) * 1000, 0), 1800000)::int;
  IF p_won THEN v_earned := v_reward; v_net := v_reward - v_spent; ELSE v_earned := 0; v_net := -v_spent; END IF;
  SELECT COALESCE(current_daily_play_streak,0) INTO v_streak FROM public.profiles WHERE id = p_uid;
  INSERT INTO public.game_results (
    user_id, played_at, won, bankroll_left, game_mode, score, outcome, puzzle_id, category,
    solved_count, puzzle_count, spent, earned, net, multiple_x100, time_ms, clean, wrong_guesses)
  VALUES (
    p_uid, NOW(), p_won, v_spent, 'daily', v_net, CASE WHEN p_won THEN 'won' ELSE 'lost' END, v_pid, v_cat,
    CASE WHEN p_won THEN 1 ELSE 0 END, 1, v_spent, v_earned, v_net,
    CASE WHEN p_won AND v_spent > 0 THEN round(v_reward * 100.0 / v_spent)::int ELSE NULL END,
    CASE WHEN p_won THEN v_time ELSE NULL END,
    (p_won AND COALESCE(p_incorrect_count,0) = 0), COALESCE(v_wrong,0));
  INSERT INTO public.user_weekly_stats (user_id, week_start, puzzles_completed, bankroll_earned, highest_bankroll, total_wins, total_played, win_streak)
  VALUES (p_uid, v_week_start, CASE WHEN p_won THEN 1 ELSE 0 END, v_net, GREATEST(v_net,0), CASE WHEN p_won THEN 1 ELSE 0 END, 1, v_streak)
  ON CONFLICT (user_id, week_start) DO UPDATE SET
    total_played = user_weekly_stats.total_played + 1,
    total_wins = user_weekly_stats.total_wins + CASE WHEN p_won THEN 1 ELSE 0 END,
    puzzles_completed = user_weekly_stats.puzzles_completed + CASE WHEN p_won THEN 1 ELSE 0 END,
    bankroll_earned = user_weekly_stats.bankroll_earned + v_net,
    highest_bankroll = GREATEST(user_weekly_stats.highest_bankroll, v_net),
    win_streak = GREATEST(user_weekly_stats.win_streak, v_streak);
  SELECT COALESCE(current_daily_solve_streak,0), COALESCE(best_daily_solve_streak,0), last_daily_solve_date INTO v_ss, v_bss, v_lss
    FROM public.profiles WHERE id = p_uid;
  IF p_won THEN
    IF v_lss = CURRENT_DATE THEN v_ss := v_ss;
    ELSIF v_lss = CURRENT_DATE - 1 THEN v_ss := v_ss + 1;
    ELSE v_ss := 1; END IF;
    v_bss := GREATEST(v_bss, v_ss);
    UPDATE public.profiles SET current_daily_solve_streak = v_ss, best_daily_solve_streak = v_bss, last_daily_solve_date = CURRENT_DATE WHERE id = p_uid;
    PERFORM public._bank_credit(p_uid, v_reward, 'daily_reward');
    IF COALESCE(p_incorrect_count,0) = 0 THEN PERFORM public._award_badge(p_uid, 'flawless'); END IF;
    IF NOT COALESCE(v_used, false) THEN
      v_grant := public._twist_powerup(public._daily_modifier());
      IF v_grant IS NOT NULL THEN PERFORM public._award_powerup(p_uid, v_grant, 'cash'); END IF;
    END IF;
  ELSE
    UPDATE public.profiles SET current_daily_solve_streak = 0 WHERE id = p_uid;
  END IF;
  PERFORM public._check_calendar_badges(p_uid, CURRENT_DATE);
END; $function$

;
CREATE OR REPLACE FUNCTION public.get_daily_board(p_scope text DEFAULT 'everyone'::text, p_group uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB; v_base int;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  v_base := public._daily_reward(public._todays_puzzle_id());
  WITH circle AS (
    SELECT v_uid AS id
    UNION SELECT friend_id FROM public.friendships WHERE user_id = v_uid AND p_scope = 'friends'
    UNION SELECT user_id FROM public.group_members WHERE group_id = p_group AND p_scope = 'group'
    UNION SELECT id FROM public.profiles WHERE p_scope IN ('global','everyone')
  ),
  d AS (
    SELECT c.id,
      COALESCE(pr.bank, 0)::bigint AS net_worth,
      (CASE WHEN pr.last_daily_play_date >= CURRENT_DATE - 1 THEN COALESCE(pr.current_daily_play_streak,0) ELSE 0 END) AS play_streak,
      (CASE WHEN pr.last_daily_solve_date >= CURRENT_DATE - 1 THEN COALESCE(pr.current_daily_solve_streak,0) ELSE 0 END) AS win_streak,
      g.score AS score,
      (CASE WHEN g.won AND v_base > 0 THEN GREATEST(0, round((v_base - g.spent)::numeric / v_base * 100)::int - 5 * COALESCE(g.wrong_guesses,0)) ELSE NULL END) AS efficiency,
      pr.equipped_title, pr.equipped_color
    FROM circle c
    JOIN public.profiles pr ON pr.id = c.id
    LEFT JOIN LATERAL (
      SELECT gr.score, gr.spent, gr.won, gr.wrong_guesses FROM public.game_results gr
      WHERE gr.user_id = c.id AND gr.game_mode = 'daily' AND gr.played_at::date = CURRENT_DATE
      ORDER BY gr.played_at DESC LIMIT 1
    ) g ON true
    WHERE c.id IS NOT NULL
  ),
  ranked AS (
    SELECT *, row_number() OVER (ORDER BY (score IS NULL), score DESC NULLS LAST, net_worth DESC) AS rank
    FROM d ORDER BY (score IS NULL), score DESC NULLS LAST, net_worth DESC LIMIT 100
  )
  SELECT jsonb_agg(jsonb_build_object(
    'rank', rank, 'name', public._display_name(id), 'net_worth', net_worth, 'score', score,
    'efficiency', efficiency,
    'play_streak', play_streak, 'win_streak', win_streak, 'played', score IS NOT NULL,
    'is_me', id = v_uid, 'title', equipped_title, 'color', equipped_color) ORDER BY rank) INTO v_rows FROM ranked;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $function$

;
COMMIT;
