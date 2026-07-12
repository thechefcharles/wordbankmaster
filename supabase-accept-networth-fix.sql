-- ============================================================================
-- Fix: accept_match gated affordability and the reduced-stake cap on gross `bank`, but
-- the whole app (incl. the accept sheet's "Available Balance" + the client's decision to
-- offer "play with what you have") uses net worth = bank − loan. A loan-holder with
-- bank ≥ wager but net worth < wager was shown a capped buy-in yet charged the full
-- wager, spending into negative net worth. Gate + cap on net worth (charge still debits
-- bank, which is the same money). No change for players without a loan (net worth = bank).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.accept_match(p_id uuid, p_reduced boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); m public.challenge_matches; me public.challenge_participants;
  v_cash BIGINT; v_stake BIGINT; v_seed BIGINT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND OR m.status <> 'open' THEN RETURN jsonb_build_object('ok',false,'reason','closed'); END IF;
  SELECT * INTO me FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','not_invited'); END IF;
  IF me.state <> 'invited' THEN RETURN jsonb_build_object('ok',true, 'match', public.get_match(p_id)); END IF;
  v_stake := 0;
  IF m.wager > 0 THEN
    PERFORM public._ensure_bank(v_uid);
    PERFORM public._accrue_loan(v_uid);                          -- so net worth reflects the current loan
    -- Available balance = net worth (bank − loan), matching the accept sheet + the client's cap.
    SELECT COALESCE(bank,0) - COALESCE(loan,0) INTO v_cash FROM public.profiles WHERE id = v_uid;
    IF v_cash >= m.wager THEN v_stake := m.wager;
    ELSIF p_reduced AND v_cash > 0 THEN v_stake := v_cash;
    ELSE RETURN jsonb_build_object('ok',false,'reason','insufficient','cash',COALESCE(v_cash,0),'wager',m.wager); END IF;
    PERFORM public._bank_credit(v_uid, -v_stake, 'wager_stake');
  END IF;
  -- NEW (econ_v=2): spend budget from puzzle bounty; OLD: the staked amount.
  v_seed := CASE WHEN m.econ_v = 2 THEN public._match_pos_bounty(p_id, COALESCE(me.position,1))
                 ELSE GREATEST(v_stake, CASE WHEN m.wager > 0 THEN 500 ELSE 0 END) END;
  UPDATE public.challenge_participants SET paid = (m.wager > 0), state = 'active', joined_at = now(),
    bankroll = v_seed, start_budget = v_seed, stake = v_stake
  WHERE match_id = p_id AND user_id = v_uid;
  PERFORM public._mark_seen_many(v_uid, (select array_agg(puzzle_id) from public.challenge_pack where match_id = p_id));
  IF m.host_id IS NOT NULL AND m.host_id <> v_uid THEN
    INSERT INTO public.friendships(user_id, friend_id) VALUES (v_uid, m.host_id), (m.host_id, v_uid) ON CONFLICT DO NOTHING;
  END IF;
  RETURN jsonb_build_object('ok',true, 'match', public.get_match(p_id));
END; $function$;

COMMIT;
