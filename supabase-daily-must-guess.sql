-- ============================================================================
-- Daily: expose a `must_guess` flag on the board — true when you're out of budget
-- (bankroll < cheapest buyable letter) on an active session. Drives the Daily
-- "out of budget, last guess" danger treatment (mirrors Cash Game's must_guess).
-- Added to _daily_resolve_and_return, which every budget-changing path returns
-- (letter buy + wrong-guess drain).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public._daily_resolve_and_return(p_uid uuid, p_phrase text, p_cat text, p_sub text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE s public.daily_sessions; v_won BOOLEAN; v_board JSONB; v_base INT; v_kept INT; v_mult NUMERIC; v_winnings INT;
  v_loan BIGINT; v_loan_repaid BIGINT := 0; v_attendance BIGINT := 0; v_cheapest INT;
BEGIN
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;
  v_cheapest := public._daily_cheapest_buyable(s, p_phrase);
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
         'wrong_guesses', COALESCE(s.p_wrong_guesses,0),
         'must_guess', (s.state = 'active' AND v_cheapest IS NOT NULL AND s.bankroll < v_cheapest));
  IF s.state = 'won' THEN
    -- Today's show-up reward (credited at daily_start; already in the balance).
    SELECT COALESCE(sum(delta),0) INTO v_attendance FROM public.bank_ledger
      WHERE user_id = p_uid AND reason = 'attendance' AND created_at::date = CURRENT_DATE;
    v_board := v_board || jsonb_build_object('daily_result', jsonb_build_object(
      'won', true, 'base', v_base, 'spent', s.spent, 'kept', v_kept, 'mult', v_mult,
      'winnings', v_winnings, 'banked', v_winnings, 'score', v_winnings, 'twist_used', s.twist_used,
      'reward', v_winnings, 'net', v_winnings, 'loan_repaid', v_loan_repaid, 'attendance', v_attendance));
  END IF;
  RETURN v_board;
END; $function$;

COMMIT;
