-- ============================================================================
-- Tier 2 group-standings fixes:
--  #12 wins counted every co-leader at the top score as a win (topscore>0 AND
--      total_score=topscore). _match_settle logs a tied #1 as a 'tie', so the standings
--      overstated wins. Now a win requires being the UNIQUE top scorer (top_n = 1).
--  #10 "recent matches" winner picked ORDER BY total_score DESC LIMIT 1 — always naming
--      someone even when nobody solved (top = 0) or the top was tied. Now winner is NULL
--      unless there's a single top scorer with score > 0.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_group_standings(p_group_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v_members jsonb; v_recent jsonb; v_total int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.group_members WHERE group_id = p_group_id AND user_id = v_uid) THEN
    RETURN NULL;  -- members only
  END IF;

  SELECT count(*) INTO v_total FROM public.challenge_matches WHERE group_id = p_group_id AND status = 'settled';

  WITH settled AS (
    SELECT m.id,
      (SELECT max(total_score) FROM public.challenge_participants x WHERE x.match_id = m.id) AS topscore,
      (SELECT count(*) FROM public.challenge_participants x WHERE x.match_id = m.id
         AND x.total_score = (SELECT max(total_score) FROM public.challenge_participants y WHERE y.match_id = m.id)) AS top_n
    FROM public.challenge_matches m WHERE m.group_id = p_group_id AND m.status = 'settled'
  ),
  mem AS (
    SELECT gm.user_id, public._display_name(gm.user_id) AS name FROM public.group_members gm WHERE gm.group_id = p_group_id
  ),
  stats AS (
    SELECT mem.user_id, mem.name,
      count(*) FILTER (WHERE s.id IS NOT NULL AND cp.state = 'done') AS played,
      -- A win = sole top scorer (matches _match_settle's tie handling).
      count(*) FILTER (WHERE s.id IS NOT NULL AND s.topscore > 0 AND s.top_n = 1 AND cp.total_score = s.topscore) AS wins
    FROM mem
    LEFT JOIN public.challenge_participants cp ON cp.user_id = mem.user_id
    LEFT JOIN settled s ON s.id = cp.match_id
    GROUP BY mem.user_id, mem.name
  )
  SELECT jsonb_agg(jsonb_build_object(
    'user_id', user_id, 'name', name, 'is_me', (user_id = v_uid),
    'played', played, 'wins', wins,
    'win_pct', CASE WHEN played > 0 THEN round(wins * 100.0 / played) ELSE 0 END
  ) ORDER BY wins DESC, played DESC, lower(name))
  INTO v_members FROM stats;

  SELECT jsonb_agg(jsonb_build_object(
    'match_id', r.id, 'pack_size', r.pack_size, 'wager', r.wager, 'players', r.players, 'winner', r.winner
  ) ORDER BY r.created_at DESC)
  INTO v_recent FROM (
    SELECT m.id, m.pack_size, m.wager, m.created_at,
      (SELECT count(*) FROM public.challenge_participants cp WHERE cp.match_id = m.id) AS players,
      -- Only a genuine sole winner with a positive score; else NULL (tie / no solve).
      (SELECT CASE WHEN mx.top > 0 AND mx.n = 1
                   THEN (SELECT public._display_name(cp.user_id) FROM public.challenge_participants cp
                           WHERE cp.match_id = m.id AND cp.total_score = mx.top LIMIT 1)
                   ELSE NULL END
       FROM (SELECT (SELECT max(total_score) FROM public.challenge_participants x WHERE x.match_id = m.id) AS top,
                    (SELECT count(*) FROM public.challenge_participants x WHERE x.match_id = m.id
                       AND x.total_score = (SELECT max(total_score) FROM public.challenge_participants y WHERE y.match_id = m.id)) AS n
            ) mx) AS winner
    FROM public.challenge_matches m WHERE m.group_id = p_group_id AND m.status = 'settled'
    ORDER BY m.created_at DESC LIMIT 8
  ) r;

  RETURN jsonb_build_object(
    'total_matches', COALESCE(v_total, 0),
    'members', COALESCE(v_members, '[]'::jsonb),
    'recent', COALESCE(v_recent, '[]'::jsonb)
  );
END; $function$;

COMMIT;
