-- ============================================================================
-- Daily deposit slip: surface the 50% loan auto-repayment (parity with cashout).
-- ============================================================================
-- Solving Daily deposits your winnings via _finalize_daily → _bank_credit,
-- which auto-skims 50% to an outstanding loan. The slip never showed it. We
-- compute the exact skim (mirroring _bank_credit: LEAST(loan, floor(win*0.5))
-- after accrual) and add `loan_repaid` to the daily_result the board returns.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public._daily_resolve_and_return(p_uid uuid, p_phrase text, p_cat text, p_sub text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE s public.daily_sessions; v_won BOOLEAN; v_board JSONB; v_base INT; v_kept INT; v_mult NUMERIC; v_winnings INT;
  v_loan BIGINT; v_loan_repaid BIGINT := 0;
BEGIN
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;
  v_base := public._daily_reward(s.puzzle_id);
  v_kept := GREATEST(0, s.bankroll);
  v_mult := public._daily_bounty_mult(p_uid);                 -- pre-finalize → incoming streak
  v_winnings := (round(v_kept * v_mult / 10.0) * 10)::int;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(p_phrase)-1) g(i)
    WHERE substr(p_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions)));
  IF v_won AND s.state = 'active' THEN
    UPDATE public.daily_sessions SET state = 'won', updated_at = NOW(), finished_at = COALESCE(finished_at, NOW())
      WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;
    s.state := 'won';
    -- Skim preview: accrue first (idempotent same-day) so v_loan is what _bank_credit skims against.
    PERFORM public._accrue_loan(p_uid);
    SELECT COALESCE(loan,0) INTO v_loan FROM public.profiles WHERE id = p_uid;
    v_loan_repaid := LEAST(v_loan, floor(v_winnings * 0.5)::bigint);
    PERFORM public._finalize_daily(p_uid, true, s.spent, v_kept, COALESCE(array_length(s.incorrect_letters,1),0));
    PERFORM public._record_category_solve(p_uid, p_cat);
  END IF;
  v_board := public._daily_board(p_phrase, s.state, s.bankroll, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, p_cat, p_sub)
    || jsonb_build_object('live', public._daily_live(s.bankroll, v_mult), 'base', v_base,
         'modifier', s.active_powerups[1], 'twist_used', s.twist_used, 'bounty_mult', v_mult,
         'wrong_guesses', COALESCE(s.p_wrong_guesses,0));
  IF s.state = 'won' THEN
    v_board := v_board || jsonb_build_object('daily_result', jsonb_build_object(
      'won', true, 'base', v_base, 'spent', s.spent, 'kept', v_kept, 'mult', v_mult,
      'winnings', v_winnings, 'banked', v_winnings, 'score', v_winnings, 'twist_used', s.twist_used,
      'reward', v_winnings, 'net', v_winnings, 'loan_repaid', v_loan_repaid));
  END IF;
  RETURN v_board;
END; $function$;

COMMIT;
