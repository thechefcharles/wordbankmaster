-- ============================================================================
-- #11: get_challenge_leaderboard returned the raw cosmetic IDS (p.equipped_color /
-- p.equipped_title) instead of their values — so the board rendered the player's title as
-- a UUID string and applied an invalid CSS color. Every sibling board (get_wealth_leaderboard,
-- get_group) resolves them via public.cosmetics; mirror that here.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_challenge_leaderboard(p_scope text DEFAULT 'friends'::text, p_group uuid DEFAULT NULL::uuid, p_period text DEFAULT 'week'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  WITH pool AS (
    SELECT gr.user_id AS id,
      count(*) FILTER (WHERE gr.outcome = 'won') AS wins,
      count(*) AS played,
      COALESCE(sum(gr.net) FILTER (WHERE gr.outcome = 'won'), 0) AS pot_won
    FROM public.game_results gr
    WHERE gr.game_mode = 'challenge'
      AND (p_period <> 'week' OR gr.played_at >= date_trunc('week', now()))
      AND (p_scope = 'global' OR gr.user_id = v_uid
        OR (p_scope = 'friends' AND gr.user_id IN (SELECT friend_id FROM public.friendships WHERE user_id = v_uid))
        OR (p_scope = 'group' AND gr.user_id IN (SELECT user_id FROM public.group_members WHERE group_id = p_group)))
    GROUP BY gr.user_id
  ),
  ranked AS (SELECT *, row_number() OVER (ORDER BY wins DESC, pot_won DESC) AS rank
             FROM pool WHERE played > 0 ORDER BY wins DESC, pot_won DESC LIMIT 50)
  SELECT jsonb_agg(jsonb_build_object('rank', r.rank, 'name', public._display_name(r.id),
    'metric', r.wins, 'played', r.played, 'pot_won', r.pot_won, 'is_me', r.id = v_uid,
    'color', cc.value, 'title', ct.value) ORDER BY r.rank)
  INTO v_rows FROM ranked r
    LEFT JOIN public.profiles p ON p.id = r.id
    LEFT JOIN public.cosmetics ct ON ct.id = p.equipped_title
    LEFT JOIN public.cosmetics cc ON cc.id = p.equipped_color;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $function$;

COMMIT;
