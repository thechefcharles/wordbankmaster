-- Voluntary give-up for Cash Game: a clean bust so a stuck player doesn't have to
-- type wrong guesses. Same outcome as a wrong guess (_cg_bust: wipes the pot,
-- reveals the answer, ends the run). Gated on an active run. PITR logged.
BEGIN;
CREATE OR REPLACE FUNCTION public.climb_forfeit()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid uuid := auth.uid(); cs public.climb_state;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_forfeit: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state <> 'active' THEN RETURN public._climb_board(v_uid); END IF;
  RETURN public._cg_bust(v_uid);
END; $function$;
COMMIT;
