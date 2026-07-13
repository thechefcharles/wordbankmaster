-- Challenge leaderboard: split wins into 1v1 vs group by participant count
-- (<=2 players = head-to-head, 3+ = group). Still ranked by total wins, pot_won tiebreak.
CREATE OR REPLACE FUNCTION public.get_challenge_leaderboard(p_scope text DEFAULT 'friends'::text, p_group uuid DEFAULT NULL::uuid, p_period text DEFAULT 'week'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  -- Group board is members-only.
  IF p_scope = 'group' AND (p_group IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.group_members WHERE group_id = p_group AND user_id = v_uid)) THEN
    RETURN '[]'::jsonb;
  END IF;
  WITH mp AS (  -- participant count per match: the 1v1-vs-group discriminator
    SELECT match_id, count(*) AS n FROM public.challenge_participants GROUP BY match_id
  ),
  pool AS (
    SELECT gr.user_id AS id,
      count(*) FILTER (WHERE gr.outcome = 'won') AS wins,
      count(*) FILTER (WHERE gr.outcome = 'won' AND COALESCE(mp.n, 2) <= 2) AS wins_1v1,
      count(*) FILTER (WHERE gr.outcome = 'won' AND COALESCE(mp.n, 2) >= 3) AS wins_group,
      count(*) AS played,
      COALESCE(sum(gr.net) FILTER (WHERE gr.outcome = 'won'), 0) AS pot_won
    FROM public.game_results gr
    LEFT JOIN mp ON mp.match_id = gr.match_id
    WHERE gr.game_mode = 'challenge'
      AND (p_period <> 'week' OR gr.played_at >= date_trunc('week', now()))
      AND (p_scope = 'global'
        OR (p_scope = 'friends' AND (gr.user_id = v_uid
              OR gr.user_id IN (SELECT friend_id FROM public.friendships WHERE user_id = v_uid)))
        OR (p_scope = 'group' AND gr.user_id IN (SELECT user_id FROM public.group_members WHERE group_id = p_group)))
    GROUP BY gr.user_id
  ),
  ranked AS (SELECT *, row_number() OVER (ORDER BY wins DESC, pot_won DESC) AS rank
             FROM pool WHERE played > 0 ORDER BY wins DESC, pot_won DESC LIMIT 50)
  SELECT jsonb_agg(jsonb_build_object('rank', r.rank, 'name', public._display_name(r.id),
    'metric', r.wins, 'wins_1v1', r.wins_1v1, 'wins_group', r.wins_group,
    'played', r.played, 'pot_won', r.pot_won, 'is_me', r.id = v_uid,
    'color', cc.value, 'title', ct.value) ORDER BY r.rank)
  INTO v_rows FROM ranked r
    LEFT JOIN public.profiles p ON p.id = r.id
    LEFT JOIN public.cosmetics ct ON ct.id = p.equipped_title
    LEFT JOIN public.cosmetics cc ON cc.id = p.equipped_color;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $function$;
