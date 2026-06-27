-- Credits become a standalone wallet: a freeplay_sessions row can exist as a pure
-- balance (state='idle', no puzzle) — buying credits no longer opens a puzzle.
ALTER TABLE public.freeplay_sessions ALTER COLUMN category DROP NOT NULL;
ALTER TABLE public.freeplay_sessions ALTER COLUMN puzzle_id DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.buy_credits(p_dollars integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid uuid := auth.uid(); v_cash bigint; v_credits int := p_dollars * 40;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  IF p_dollars IS NULL OR p_dollars < 1 THEN RETURN jsonb_build_object('ok',false,'reason','amount'); END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT bank INTO v_cash FROM public.profiles WHERE id = v_uid;
  IF v_cash < p_dollars THEN RETURN jsonb_build_object('ok',false,'reason','insufficient'); END IF;
  PERFORM public._bank_credit(v_uid, -p_dollars::bigint, 'buy_credits');
  -- pure wallet top-up: no puzzle, state 'idle' for a new row (won't show as resumable)
  INSERT INTO public.freeplay_sessions(user_id, bankroll, state)
    VALUES (v_uid, v_credits, 'idle')
    ON CONFLICT (user_id) DO UPDATE SET bankroll = public.freeplay_sessions.bankroll + v_credits, updated_at = NOW();
  RETURN jsonb_build_object('ok',true, 'credits_added', v_credits, 'dollars_spent', p_dollars);
END; $$;
REVOKE ALL ON FUNCTION public.buy_credits(integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.buy_credits(integer) TO authenticated;
