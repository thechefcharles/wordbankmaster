-- Add an Efficiency score to the daily board: (base_bounty − spent)/base_bounty ×100.
-- base_bounty = _daily_reward(today's puzzle) — SAME for every player → pure spend-less skill,
-- no streak/boost influence. Shown only for solved dailies.
CREATE OR REPLACE FUNCTION public.get_daily_board(p_scope text DEFAULT 'everyone'::text, p_group uuid DEFAULT NULL::uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
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
      (CASE WHEN g.won AND v_base > 0 THEN GREATEST(0, round((v_base - g.spent)::numeric / v_base * 100))::int ELSE NULL END) AS efficiency,
      pr.equipped_title, pr.equipped_color
    FROM circle c
    JOIN public.profiles pr ON pr.id = c.id
    LEFT JOIN LATERAL (
      SELECT gr.score, gr.spent, gr.won FROM public.game_results gr
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
END; $function$;
