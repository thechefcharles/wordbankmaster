-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Challenge: opponent status for the in-bag sabotage target picker            ║
-- ║  (migration: get_match_opponents_2026_06 — applied via psql)                ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- Sabotage now lives in the bag. In group play you tap a sabotage item, then pick a
-- target — and the picker shows which puzzle each opponent is on and how much of
-- their ante they have left. This RPC feeds that picker.

CREATE OR REPLACE FUNCTION public.get_match_opponents(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  -- IDOR guard: only an actual participant of this match may enumerate its opponents.
  IF NOT EXISTS (
    SELECT 1 FROM public.challenge_participants
    WHERE match_id = p_id AND user_id = v_uid AND state IN ('active','invited','done')
  ) THEN RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', o.user_id,
    'name', public._display_name(o.user_id),
    'position', o.position,
    'ante_left', GREATEST(0, o.bankroll),
    'done', o.state = 'done'
  ) ORDER BY o.joined_at NULLS LAST, o.position), '[]'::jsonb) INTO v
  FROM public.challenge_participants o
  WHERE o.match_id = p_id AND o.user_id <> v_uid AND o.state IN ('active','invited','done');
  RETURN v;
END; $function$;
