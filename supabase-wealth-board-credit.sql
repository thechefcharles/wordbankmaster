-- ============================================================================
-- Wealth leaderboard: also return each player's credit score, so the Wealth tab
-- can show Cash + Credit together (moved off the Daily board). Display-only add —
-- ranking (by net-worth metric) is unchanged.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_wealth_leaderboard(p_scope text DEFAULT 'friends'::text, p_period text DEFAULT 'week'::text, p_group uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB; v_ws DATE := date_trunc('week', CURRENT_DATE)::date;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  WITH pool AS (
    SELECT p.id, COALESCE(p.bank,0) AS nw, COALESCE(p.bank,0) AS cash,
           COALESCE(p.credit_score, 650) AS credit,
           ct.value AS title, cc.value AS color,
           COALESCE((SELECT net_worth FROM public.networth_snapshots s WHERE s.user_id = p.id AND s.week_start = v_ws), COALESCE(p.bank,0)) AS ws_nw
    FROM public.profiles p
    LEFT JOIN public.cosmetics ct ON ct.id = p.equipped_title
    LEFT JOIN public.cosmetics cc ON cc.id = p.equipped_color
    WHERE p.bank IS NOT NULL AND (
      p_scope = 'global' OR p.id = v_uid
      OR (p_scope = 'friends' AND p.id IN (SELECT friend_id FROM public.friendships WHERE user_id = v_uid))
      OR (p_scope = 'group' AND p.id IN (SELECT user_id FROM public.group_members WHERE group_id = p_group)))
  ),
  metric AS (SELECT *, CASE WHEN p_period = 'week' THEN nw - ws_nw ELSE nw END AS m FROM pool),
  ranked AS (SELECT *, row_number() OVER (ORDER BY m DESC, cash DESC) AS rank FROM metric ORDER BY m DESC, cash DESC LIMIT 50)
  SELECT jsonb_agg(jsonb_build_object('rank', rank, 'name', public._display_name(id), 'metric', m,
    'net_worth', nw, 'cash', cash, 'credit', credit, 'title', title, 'color', color, 'is_me', id = v_uid) ORDER BY rank)
  INTO v_rows FROM ranked;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $function$;

COMMIT;
