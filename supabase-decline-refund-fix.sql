-- ============================================================================
-- Fix: decline_match refunded the puzzle BOUNTY (start_budget), not the STAKE the
-- player actually paid. In econ_v=2, start_budget = _match_pos_bounty (~$1.2–3k) while
-- the host is only debited stake = wager (min $500) — so a decline handed the host the
-- difference for free (colludable exploit). _match_settle already refunds
-- coalesce(stake, …); mirror it here.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.decline_match(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); m public.challenge_matches; me public.challenge_participants; v_active int; r record;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND OR m.status <> 'open' THEN RETURN jsonb_build_object('ok',false,'reason','closed'); END IF;
  SELECT * INTO me FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','not_invited'); END IF;
  IF me.state <> 'invited' THEN RETURN jsonb_build_object('ok',false,'reason','already_in'); END IF;
  UPDATE public.challenge_participants SET state = 'declined' WHERE match_id = p_id AND user_id = v_uid;
  -- If the match can no longer happen (fewer than 2 players left), void it + refund buy-ins.
  SELECT count(*) INTO v_active FROM public.challenge_participants WHERE match_id = p_id AND state IN ('active','invited','done');
  IF v_active < 2 THEN
    -- Refund the actual STAKE paid (not the puzzle bounty). Matches _match_settle.
    FOR r IN SELECT user_id, COALESCE(stake, GREATEST(m.wager,500)) AS refund
             FROM public.challenge_participants WHERE match_id = p_id AND paid LOOP
      PERFORM public._bank_credit(r.user_id, r.refund, 'wager_refund');
    END LOOP;
    UPDATE public.challenge_matches SET status = 'void' WHERE id = p_id;
    PERFORM public._notify(m.host_id, 'challenge_result', '🚫 Challenge declined',
      public._display_name(v_uid) || ' declined your challenge' || CASE WHEN m.wager>0 THEN ' — buy-in refunded' ELSE '' END,
      jsonb_build_object('match_id', p_id));
  END IF;
  RETURN jsonb_build_object('ok', true);
END; $function$;

COMMIT;
