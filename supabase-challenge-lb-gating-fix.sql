-- ============================================================================
-- #22: get_challenge_leaderboard group scope wasn't membership-gated, and the
-- `OR gr.user_id = v_uid` self-include applied to ALL scopes — so you always appeared on
-- a group's board even if you weren't in it. Now: group scope requires membership (else
-- empty), and self-include is scoped to 'friends' only (group members already include you).
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
  -- Group board is members-only.
  IF p_scope = 'group' AND (p_group IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.group_members WHERE group_id = p_group AND user_id = v_uid)) THEN
    RETURN '[]'::jsonb;
  END IF;
  WITH pool AS (
    SELECT gr.user_id AS id,
      count(*) FILTER (WHERE gr.outcome = 'won') AS wins,
      count(*) AS played,
      COALESCE(sum(gr.net) FILTER (WHERE gr.outcome = 'won'), 0) AS pot_won
    FROM public.game_results gr
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
    'metric', r.wins, 'played', r.played, 'pot_won', r.pot_won, 'is_me', r.id = v_uid,
    'color', cc.value, 'title', ct.value) ORDER BY r.rank)
  INTO v_rows FROM ranked r
    LEFT JOIN public.profiles p ON p.id = r.id
    LEFT JOIN public.cosmetics ct ON ct.id = p.equipped_title
    LEFT JOIN public.cosmetics cc ON cc.id = p.equipped_color;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $function$;

COMMIT;
