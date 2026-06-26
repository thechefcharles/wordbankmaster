-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Multiple live games: server-truth "open games" for menu resume             ║
-- ║  (migration: get_open_games_2026_06 — applied via psql)                     ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- The server already keeps independent per-mode sessions (daily_sessions,
-- climb_state, freeplay_sessions), so several solo games can be live at once.
-- The client used to infer "in progress" from a single shared localStorage slot,
-- which any mode's goToMainMenu() overwrote (the "Daily shows lost" bug).
--
-- get_open_games() returns the caller's currently-resumable SOLO games, newest
-- first, so the menu can: (a) label each mode's card from server truth, and
-- (b) offer a top-level "Resume" shortcut to the most-recently-played one.

CREATE OR REPLACE FUNCTION public.get_open_games()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.updated_at DESC), '[]'::jsonb) INTO v
  FROM (
    SELECT 'daily'::text AS mode, ds.updated_at
      FROM public.daily_sessions ds
      WHERE ds.user_id = v_uid AND ds.puzzle_date = CURRENT_DATE AND ds.state = 'active'
    UNION ALL
    SELECT 'climb', cs.updated_at
      FROM public.climb_state cs
      WHERE cs.user_id = v_uid AND cs.state IN ('active','stuck')
    UNION ALL
    SELECT 'freeplay', fs.updated_at
      FROM public.freeplay_sessions fs
      WHERE fs.user_id = v_uid AND fs.state = 'active'
  ) t;
  RETURN v;
END; $function$;
