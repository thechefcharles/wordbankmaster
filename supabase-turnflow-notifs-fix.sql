-- ============================================================================
-- Tier 3 turn-flow notifications:
--  #16 _match_notify_opponent_played only pinged waiters on the FIRST finish
--      (IF v_done <> 1 THEN RETURN), so in a group the 2nd+ finishers never re-nudged
--      the stragglers. Now every finish nudges the still-waiting players, deduped so each
--      waiter has at most one unread "your turn" per match (no pile-up).
--  #18 decline_match only told the host when a decline VOIDED the match. In a group where
--      the match survives, the host was never told anyone bowed out. Now notify the host.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public._match_notify_opponent_played(p_id uuid, p_finisher uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE m public.challenge_matches; v_name text; r record;
BEGIN
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND OR m.status <> 'open' THEN RETURN; END IF;
  v_name := public._display_name(p_finisher);
  FOR r IN SELECT user_id FROM public.challenge_participants
           WHERE match_id = p_id AND user_id <> p_finisher AND state IN ('active','invited') LOOP
    -- Replace any stale unread "your turn" for this match so a waiter sees one fresh nudge.
    DELETE FROM public.notifications
      WHERE user_id = r.user_id AND type = 'challenge_your_turn'
        AND read_at IS NULL AND data->>'match_id' = p_id::text;
    PERFORM public._notify(r.user_id, 'challenge_your_turn',
      v_name || ' played your challenge',
      'You''re up — beat their score to take the pot!',
      jsonb_build_object('match_id', p_id, 'route', 'challenge'));
  END LOOP;
END; $function$;

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
  ELSIF m.host_id IS NOT NULL AND m.host_id <> v_uid THEN
    -- Match still on (group) — let the host know someone bowed out.
    PERFORM public._notify(m.host_id, 'challenge_result', 'Challenge declined',
      public._display_name(v_uid) || ' declined — the challenge is still on.',
      jsonb_build_object('match_id', p_id, 'route', 'challenge'));
  END IF;
  RETURN jsonb_build_object('ok', true);
END; $function$;

COMMIT;
