-- ============================================================================
-- #17: _match_maybe_settle only settled when NO participant was 'active' OR 'invited',
-- so a group invitee who never accepted blocked early settlement — finishers waited out
-- the whole window for payout. New rule: settle once everyone who accepted has finished
-- (no 'active' left) AND at least 2 players actually completed ('done'). This passes over
-- invitees who never accepted, while still protecting 1:1 — if the opponent never accepts,
-- only 1 player is 'done' (< 2), so it waits for the window/cron instead of settling early.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public._match_maybe_settle(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.challenge_participants WHERE match_id = p_id AND state = 'active')
     AND (SELECT count(*) FROM public.challenge_participants WHERE match_id = p_id AND state = 'done') >= 2 THEN
    PERFORM public._match_settle(p_id);
  END IF;
END; $function$;

COMMIT;
