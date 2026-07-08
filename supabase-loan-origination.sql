-- Loans: charge an upfront origination the moment you borrow so a same-day take+repay
-- is never free. You owe principal + GREATEST(one day's interest, 10% of principal).
-- The bank still receives the full principal. PITR point logged before apply.
BEGIN;

CREATE OR REPLACE FUNCTION public.take_loan(p_amount bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v_loan bigint; v_cap bigint; v_rate int; v_score int;
        v_upfront bigint; v_owed bigint;
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
  -- Upfront charge: the greater of one day's interest or a 10% floor. Baked into what's
  -- owed at borrow time (bank still receives the full principal).
  v_upfront := GREATEST(round(p_amount * v_rate / 10000.0)::bigint, round(p_amount * 0.10)::bigint);
  v_owed := p_amount + v_upfront;
  UPDATE public.profiles
    SET loan = v_owed, loan_principal = p_amount, loan_rate_bp = v_rate,
        loan_taken_at = now(), loan_accrued_at = now()
    WHERE id = v_uid;
  PERFORM public._bank_credit(v_uid, p_amount, 'loan_take');   -- principal to Cash (skim-exempt)
  PERFORM public._recompute_credit(v_uid, 'take_loan', 0);     -- utilization/restraint moved
  RETURN jsonb_build_object('ok',true,'borrowed',p_amount,'owed',v_owed,
                            'upfront',v_upfront,'rate_bp',v_rate,'cap',v_cap);
END; $function$;

COMMIT;
