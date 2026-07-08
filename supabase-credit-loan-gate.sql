-- Credit Score Phase 2b — take_loan honors the credit-effective cap + rate + Bad
-- lockout, and both take/repay recompute the score. PITR point logged before apply.
BEGIN;

CREATE OR REPLACE FUNCTION public.take_loan(p_amount bigint)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v_loan bigint; v_cap bigint; v_rate int; v_score int;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  IF p_amount IS NULL OR p_amount < 50 THEN RETURN jsonb_build_object('ok',false,'reason','bad_amount'); END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT COALESCE(loan,0), COALESCE(credit_score,650) INTO v_loan, v_score
    FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_loan > 0 THEN RETURN jsonb_build_object('ok',false,'reason','active_loan'); END IF;
  v_cap := public._credit_effective_cap(v_uid);
  IF v_cap <= 0 THEN RETURN jsonb_build_object('ok',false,'reason','credit_locked'); END IF;
  IF p_amount > v_cap THEN RETURN jsonb_build_object('ok',false,'reason','over_cap','cap',v_cap); END IF;
  v_rate := GREATEST(200, LEAST(2500,
    public._loan_daily_rate_bp(p_amount, v_cap) + public._credit_rate_adjust(v_score)));
  UPDATE public.profiles
    SET loan = p_amount, loan_principal = p_amount, loan_rate_bp = v_rate,
        loan_taken_at = now(), loan_accrued_at = now()
    WHERE id = v_uid;
  PERFORM public._bank_credit(v_uid, p_amount, 'loan_take');   -- principal to Cash (skim-exempt)
  PERFORM public._recompute_credit(v_uid, 'take_loan', 0);     -- utilization/restraint moved
  RETURN jsonb_build_object('ok',true,'borrowed',p_amount,'owed',p_amount,'rate_bp',v_rate,'cap',v_cap);
END; $function$;

CREATE OR REPLACE FUNCTION public.repay_loan(p_amount bigint DEFAULT NULL::bigint)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v_loan bigint; v_bank bigint; v_pay bigint;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  PERFORM public._ensure_bank(v_uid);
  PERFORM public._accrue_loan(v_uid);
  SELECT COALESCE(loan,0), COALESCE(bank,0) INTO v_loan, v_bank FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_loan <= 0 THEN RETURN jsonb_build_object('ok',false,'reason','no_loan'); END IF;
  v_pay := LEAST(COALESCE(p_amount, v_loan), v_loan, v_bank);
  IF v_pay <= 0 THEN RETURN jsonb_build_object('ok',false,'reason','insufficient'); END IF;
  UPDATE public.profiles
    SET loan = v_loan - v_pay,
        loan_accrued_at  = CASE WHEN v_loan - v_pay <= 0 THEN NULL ELSE loan_accrued_at END,
        loan_principal   = CASE WHEN v_loan - v_pay <= 0 THEN NULL ELSE loan_principal  END,
        loan_rate_bp     = CASE WHEN v_loan - v_pay <= 0 THEN NULL ELSE loan_rate_bp    END,
        loan_taken_at    = CASE WHEN v_loan - v_pay <= 0 THEN NULL ELSE loan_taken_at   END
    WHERE id = v_uid;
  PERFORM public._bank_credit(v_uid, -v_pay, 'loan_repay');
  IF v_loan - v_pay <= 0 THEN PERFORM public._award_badge(v_uid, 'paid_in_full'); END IF;
  PERFORM public._recompute_credit(v_uid, 'repay_loan', 0);    -- utilization/repayment moved
  RETURN jsonb_build_object('ok',true,'paid',v_pay,'remaining',v_loan - v_pay,'cleared',(v_loan - v_pay) <= 0);
END; $function$;

COMMIT;
