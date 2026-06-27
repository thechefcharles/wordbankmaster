-- Auto-friend: accepting a challenge makes you friends with the host.
BEGIN;
CREATE OR REPLACE FUNCTION public.accept_match(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); m public.challenge_matches; me public.challenge_participants; v_cash BIGINT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND OR m.status <> 'open' THEN RETURN jsonb_build_object('ok',false,'reason','closed'); END IF;
  SELECT * INTO me FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','not_invited'); END IF;
  IF me.state <> 'invited' THEN RETURN jsonb_build_object('ok',true, 'match', public.get_match(p_id)); END IF;
  IF m.wager > 0 THEN
    PERFORM public._ensure_bank(v_uid);
    SELECT bank INTO v_cash FROM public.profiles WHERE id = v_uid;
    IF v_cash < m.wager THEN RETURN jsonb_build_object('ok',false,'reason','insufficient'); END IF;
    PERFORM public._bank_credit(v_uid, -m.wager, 'wager_stake');
  END IF;
  UPDATE public.challenge_participants SET paid = (m.wager > 0), state = 'active', joined_at = now(),
    bankroll = GREATEST(m.wager, 500)
  WHERE match_id = p_id AND user_id = v_uid;
  IF m.host_id IS NOT NULL AND m.host_id <> v_uid THEN
    INSERT INTO public.friendships(user_id, friend_id) VALUES (v_uid, m.host_id), (m.host_id, v_uid) ON CONFLICT DO NOTHING;
  END IF;
  RETURN jsonb_build_object('ok',true, 'match', public.get_match(p_id));
END; $function$

;
CREATE OR REPLACE FUNCTION public.accept_match(p_id uuid, p_reduced boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); m public.challenge_matches; me public.challenge_participants;
  v_cash BIGINT; v_stake BIGINT; v_budget BIGINT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND OR m.status <> 'open' THEN RETURN jsonb_build_object('ok',false,'reason','closed'); END IF;
  SELECT * INTO me FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','not_invited'); END IF;
  IF me.state <> 'invited' THEN RETURN jsonb_build_object('ok',true, 'match', public.get_match(p_id)); END IF;
  v_budget := GREATEST(m.wager, 500);
  IF m.wager > 0 THEN
    PERFORM public._ensure_bank(v_uid);
    SELECT bank INTO v_cash FROM public.profiles WHERE id = v_uid;
    IF v_cash >= m.wager THEN
      v_stake := m.wager;
    ELSIF p_reduced AND v_cash > 0 THEN
      v_stake := v_cash;
    ELSE
      RETURN jsonb_build_object('ok',false,'reason','insufficient','cash',COALESCE(v_cash,0),'wager',m.wager);
    END IF;
    PERFORM public._bank_credit(v_uid, -v_stake, 'wager_stake');
    v_budget := v_stake;
  END IF;
  UPDATE public.challenge_participants SET paid = (m.wager > 0), state = 'active', joined_at = now(),
    bankroll = v_budget, start_budget = v_budget
  WHERE match_id = p_id AND user_id = v_uid;
  PERFORM public._mark_seen_many(v_uid, (select array_agg(puzzle_id) from public.challenge_pack where match_id = p_id));
  IF m.host_id IS NOT NULL AND m.host_id <> v_uid THEN
    INSERT INTO public.friendships(user_id, friend_id) VALUES (v_uid, m.host_id), (m.host_id, v_uid) ON CONFLICT DO NOTHING;
  END IF;
  RETURN jsonb_build_object('ok',true, 'match', public.get_match(p_id));
END; $function$

;
COMMIT;
