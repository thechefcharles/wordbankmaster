-- Buy Free Play credits with Cash (always 40 credits = $1). Opens a Free Play session
-- if none exists (default category). Validates before charging so cash is never lost.
CREATE OR REPLACE FUNCTION public.buy_credits(p_dollars integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid uuid := auth.uid(); v_cash bigint; v_credits int := p_dollars * 40;
        v_has boolean := false; v_pid uuid; v_cat text := 'Pop Culture & Celebrities 🌟';
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  IF p_dollars IS NULL OR p_dollars < 1 THEN RETURN jsonb_build_object('ok',false,'reason','amount'); END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT bank INTO v_cash FROM public.profiles WHERE id = v_uid;
  IF v_cash < p_dollars THEN RETURN jsonb_build_object('ok',false,'reason','insufficient'); END IF;
  SELECT true INTO v_has FROM public.freeplay_sessions WHERE user_id = v_uid;
  IF NOT COALESCE(v_has,false) THEN
    v_pid := public._pick_casual(v_uid, v_cat, NULL, 0);
    IF v_pid IS NULL THEN v_pid := public._pick_casual(v_uid, NULL, NULL, 0); END IF;
    IF v_pid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','no_puzzle'); END IF;
  END IF;
  PERFORM public._bank_credit(v_uid, -p_dollars::bigint, 'buy_credits');
  IF COALESCE(v_has,false) THEN
    UPDATE public.freeplay_sessions SET bankroll = bankroll + v_credits, updated_at = NOW() WHERE user_id = v_uid;
  ELSE
    INSERT INTO public.freeplay_sessions(user_id, category, puzzle_id, bankroll) VALUES (v_uid, v_cat, v_pid, v_credits);
  END IF;
  RETURN jsonb_build_object('ok',true, 'credits_added', v_credits, 'dollars_spent', p_dollars);
END; $$;
REVOKE ALL ON FUNCTION public.buy_credits(integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.buy_credits(integer) TO authenticated;
