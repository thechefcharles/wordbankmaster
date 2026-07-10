-- ============================================================================
-- cashgame_cashout: return `loan_repaid` so the DEPOSIT SLIP can show the skim.
-- ============================================================================
-- When you bank Earnings while owing, _bank_credit auto-skims 50% of the credit
-- to the loan (capped at what you owe). The slip never surfaced that, so your
-- Available Balance climbed by less than "banked" with no explanation. We now
-- compute the exact skim (mirroring _bank_credit: LEAST(loan, floor(delta*0.5))
-- after accrual) and return it as `loan_repaid`.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.cashgame_cashout()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_profit BIGINT; v_mult INT; v_wins jsonb;
  v_streak INT; v_bestrs INT; v_phrase TEXT; v_loan BIGINT; v_loan_repaid BIGINT := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'cashgame_cashout: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_run'); END IF;
  IF cs.state <> 'solved' THEN RETURN jsonb_build_object('ok', false, 'reason', 'in_puzzle'); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_profit := cs.bankroll - cs.buy_in;
  v_mult := CASE WHEN cs.buy_in > 0 THEN round(cs.bankroll * 100.0 / cs.buy_in)::int ELSE 0 END;
  -- Skim preview: accrue first (idempotent within a day) so v_loan is the post-accrual
  -- balance _bank_credit will skim against; the skim = LEAST(loan, floor(banked*0.5)).
  IF cs.bankroll > 0 THEN
    PERFORM public._accrue_loan(v_uid);
    SELECT COALESCE(loan,0) INTO v_loan FROM public.profiles WHERE id = v_uid;
    v_loan_repaid := LEAST(v_loan, floor(cs.bankroll * 0.5)::bigint);
    PERFORM public._bank_credit(v_uid, cs.bankroll, 'cashgame_cashout');
  END IF;
  SELECT COALESCE(cg_wins,'{}'::jsonb), COALESCE(cg_run_streak,0), COALESCE(cg_best_run_streak,0)
    INTO v_wins, v_streak, v_bestrs FROM public.profiles WHERE id = v_uid;
  IF v_profit > 0 THEN
    v_wins := jsonb_set(v_wins, ARRAY[cs.tier], to_jsonb(COALESCE((v_wins->>cs.tier)::int,0) + 1), true);
    v_streak := v_streak + 1;
  ELSE
    v_streak := 0;
  END IF;
  UPDATE public.profiles SET
    cg_wins = v_wins,
    cg_run_streak = v_streak,
    cg_best_run_streak = GREATEST(v_bestrs, v_streak),
    cg_best_run = GREATEST(COALESCE(cg_best_run,0), cs.bankroll),
    cg_best_multiple_x100 = GREATEST(COALESCE(cg_best_multiple_x100,0), v_mult),
    cg_best_heat_x100 = GREATEST(COALESCE(cg_best_heat_x100,100), cs.heat_x100),
    cg_lifetime_net = COALESCE(cg_lifetime_net,0) + v_profit
    WHERE id = v_uid;
  DELETE FROM public.climb_state WHERE user_id = v_uid;
  RETURN jsonb_build_object('ok', true, 'banked', cs.bankroll, 'buy_in', cs.buy_in, 'profit', v_profit,
    'multiple_x100', v_mult, 'solves', cs.run_solves, 'tier', cs.tier, 'heat', cs.heat_x100,
    'phrase', v_phrase, 'loan_repaid', v_loan_repaid);
END; $function$;

COMMIT;
