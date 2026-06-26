-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  get_my_matches: expose opponent + group name (fix "you see your own name")  ║
-- ║  (migration: my_matches_opponent_2026_06 — applied via psql)                ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- The menu's act-now banner titled challenges with the HOST's name, so the host saw
-- their OWN name. Add `opponent` (the other player in a 1v1) and `group_name` so the
-- client can title it with who you're actually playing.

CREATE OR REPLACE FUNCTION public.get_my_matches()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB; r RECORD;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  FOR r IN SELECT m.id FROM public.challenge_matches m
           JOIN public.challenge_participants cp ON cp.match_id = m.id AND cp.user_id = v_uid
           WHERE m.status = 'open' AND m.settles_at < now() LOOP
    PERFORM public._match_settle(r.id);
  END LOOP;
  SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) INTO v_rows FROM (
    SELECT jsonb_build_object('id', m.id, 'mode', m.mode, 'pack_size', m.pack_size,
      'wager', m.wager, 'payout', m.payout, 'status', m.status, 'settles_at', m.settles_at,
      'is_host', m.host_id = v_uid, 'my_state', cp.state,
      'players', (SELECT count(*) FROM public.challenge_participants x WHERE x.match_id = m.id AND x.state <> 'declined'),
      'host', public._display_name(m.host_id),
      'group_name', (SELECT g.name FROM public.groups g WHERE g.id = m.group_id),
      'opponent', (SELECT public._display_name(x.user_id) FROM public.challenge_participants x
                   WHERE x.match_id = m.id AND x.user_id <> v_uid AND x.state <> 'declined'
                   ORDER BY x.joined_at NULLS LAST LIMIT 1)) AS row
    FROM public.challenge_matches m
    JOIN public.challenge_participants cp ON cp.match_id = m.id AND cp.user_id = v_uid
    WHERE m.status <> 'void' AND cp.state <> 'declined' ORDER BY m.created_at DESC LIMIT 40
  ) t;
  RETURN v_rows;
END; $function$;
