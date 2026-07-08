-- 🦈 Loans v3 — progressive daily interest (replaces the flat 25% origination fee).
-- Borrow amount is a slider up to your cap; the daily rate scales with how much you
-- take (relative to cap) and is LOCKED at borrow time. Interest COMPOUNDS daily,
-- accrued lazily on read, capped at 2.5× principal so a forgotten loan can't run away.
-- PITR checkpoint logged before apply.

BEGIN;

-- New per-loan state
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS loan_principal bigint;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS loan_rate_bp integer; -- daily rate, basis points
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS loan_taken_at timestamptz;

-- Progressive daily rate (basis points) by loan size relative to cap.
CREATE OR REPLACE FUNCTION public._loan_daily_rate_bp(p_amount bigint, p_cap bigint)
  RETURNS integer LANGUAGE sql IMMUTABLE
AS $fn$
  SELECT CASE
    WHEN p_cap <= 0 THEN 800
    WHEN p_amount::numeric / p_cap <= 0.25 THEN 200   -- 2%/day
    WHEN p_amount::numeric / p_cap <= 0.50 THEN 400   -- 4%/day
    WHEN p_amount::numeric / p_cap <= 0.75 THEN 600   -- 6%/day
    ELSE 800                                          -- 8%/day
  END;
$fn$;

-- Lazy daily compounding: apply whole elapsed days, advance the clock by that many
-- days (remainder carries), cap owed at 2.5× principal. No-op if <1 day or no loan.
CREATE OR REPLACE FUNCTION public._accrue_loan(p_uid uuid)
  RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE p public.profiles; v_days int; v_rate numeric; v_new bigint; v_cap bigint;
BEGIN
  SELECT * INTO p FROM public.profiles WHERE id = p_uid FOR UPDATE;
  IF NOT FOUND OR COALESCE(p.loan,0) <= 0 OR p.loan_accrued_at IS NULL OR COALESCE(p.loan_rate_bp,0) = 0 THEN
    RETURN;
  END IF;
  v_days := floor(extract(epoch FROM now() - p.loan_accrued_at) / 86400)::int;
  IF v_days < 1 THEN RETURN; END IF;
  v_rate := p.loan_rate_bp / 10000.0;
  v_new := round(p.loan * power(1 + v_rate, v_days))::bigint;
  v_cap := round(COALESCE(p.loan_principal, p.loan) * 2.5)::bigint;   -- runaway guard
  v_new := LEAST(v_new, v_cap);
  UPDATE public.profiles
    SET loan = v_new,
        loan_accrued_at = p.loan_accrued_at + (v_days || ' days')::interval
    WHERE id = p_uid;
END;
$fn$;

-- Take a loan: pick amount (≤ cap), rate locked from size, owed starts = principal
-- (no upfront fee — interest accrues daily from now).
CREATE OR REPLACE FUNCTION public.take_loan(p_amount bigint)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v_loan bigint; v_cap bigint; v_rate int;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  IF p_amount IS NULL OR p_amount < 50 THEN RETURN jsonb_build_object('ok',false,'reason','bad_amount'); END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT COALESCE(loan,0) INTO v_loan FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_loan > 0 THEN RETURN jsonb_build_object('ok',false,'reason','active_loan'); END IF;
  v_cap := public._loan_cap(v_uid);
  IF p_amount > v_cap THEN RETURN jsonb_build_object('ok',false,'reason','over_cap','cap',v_cap); END IF;
  v_rate := public._loan_daily_rate_bp(p_amount, v_cap);
  UPDATE public.profiles
    SET loan = p_amount, loan_principal = p_amount, loan_rate_bp = v_rate,
        loan_taken_at = now(), loan_accrued_at = now()
    WHERE id = v_uid;
  PERFORM public._bank_credit(v_uid, p_amount, 'loan_take');   -- principal to Cash (skim-exempt)
  RETURN jsonb_build_object('ok',true,'borrowed',p_amount,'owed',p_amount,'rate_bp',v_rate,'cap',v_cap);
END; $function$;

-- Repay: accrue first, then pay down from Cash (capped).
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
  RETURN jsonb_build_object('ok',true,'paid',v_pay,'remaining',v_loan - v_pay,'cleared',(v_loan - v_pay) <= 0);
END; $function$;

-- Payout auto-skim: accrue before skimming, and reset loan state when a skim clears it.
CREATE OR REPLACE FUNCTION public._bank_credit(p_uid uuid, p_delta bigint, p_reason text)
  RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_new bigint; v_loan bigint; v_skim bigint;
BEGIN
  PERFORM public._ensure_bank(p_uid);
  INSERT INTO public.networth_snapshots(user_id, week_start, net_worth)
    SELECT p_uid, date_trunc('week', CURRENT_DATE)::date, COALESCE(bank,0)
    FROM public.profiles WHERE id = p_uid
    ON CONFLICT DO NOTHING;
  UPDATE public.profiles SET bank = GREATEST(0, COALESCE(bank,0) + p_delta) WHERE id = p_uid RETURNING bank INTO v_new;
  INSERT INTO public.bank_ledger(user_id, delta, reason, balance_after) VALUES (p_uid, p_delta, p_reason, v_new);
  IF p_delta > 0 AND p_reason NOT IN ('loan_take','loan_repay','loan_skim') THEN
    PERFORM public._accrue_loan(p_uid);
    SELECT COALESCE(loan,0) INTO v_loan FROM public.profiles WHERE id = p_uid;
    IF v_loan > 0 THEN
      v_skim := LEAST(v_loan, floor(p_delta * 0.5)::bigint);
      IF v_skim > 0 THEN
        UPDATE public.profiles SET bank = GREATEST(0, COALESCE(bank,0) - v_skim),
          loan = v_loan - v_skim,
          loan_accrued_at = CASE WHEN v_loan - v_skim <= 0 THEN NULL ELSE loan_accrued_at END,
          loan_principal  = CASE WHEN v_loan - v_skim <= 0 THEN NULL ELSE loan_principal  END,
          loan_rate_bp    = CASE WHEN v_loan - v_skim <= 0 THEN NULL ELSE loan_rate_bp    END,
          loan_taken_at   = CASE WHEN v_loan - v_skim <= 0 THEN NULL ELSE loan_taken_at   END
          WHERE id = p_uid RETURNING bank INTO v_new;
        INSERT INTO public.bank_ledger(user_id, delta, reason, balance_after) VALUES (p_uid, -v_skim, 'loan_skim', v_new);
      END IF;
    END IF;
  END IF;
  RETURN v_new;
END; $function$;

-- get_bank: accrue first, expose loan detail (principal, rate, days out, projected).
CREATE OR REPLACE FUNCTION public.get_bank(p_limit integer DEFAULT 12)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); p public.profiles; v_led jsonb; v_rate numeric; v_tomorrow bigint; v_days int;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  PERFORM public._accrue_loan(v_uid);
  SELECT * INTO p FROM public.profiles WHERE id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('delta',delta,'reason',reason,'balance_after',balance_after,'at',created_at) ORDER BY created_at DESC), '[]'::jsonb)
    INTO v_led FROM (SELECT * FROM public.bank_ledger WHERE user_id = v_uid ORDER BY created_at DESC LIMIT GREATEST(p_limit, 1)) t;
  v_rate := COALESCE(p.loan_rate_bp,0) / 10000.0;
  v_tomorrow := CASE WHEN COALESCE(p.loan,0) > 0
    THEN LEAST(round(p.loan * (1 + v_rate))::bigint, round(COALESCE(p.loan_principal, p.loan) * 2.5)::bigint)
    ELSE 0 END;
  v_days := CASE WHEN p.loan_taken_at IS NOT NULL THEN floor(extract(epoch FROM now() - p.loan_taken_at)/86400)::int ELSE 0 END;
  RETURN jsonb_build_object(
    'bank', COALESCE(p.bank,0), 'net_worth', COALESCE(p.bank,0) - COALESCE(p.loan,0),
    'loan', COALESCE(p.loan,0), 'auto_repay', COALESCE(p.loan,0) > 0, 'in_the_red', COALESCE(p.loan,0) > 0,
    'loan_cap', public._loan_cap(v_uid), 'ledger', v_led,
    'loan_principal', COALESCE(p.loan_principal,0), 'loan_rate_bp', COALESCE(p.loan_rate_bp,0),
    'loan_taken_at', p.loan_taken_at, 'loan_days', v_days, 'loan_owed_tomorrow', v_tomorrow);
END; $function$;

COMMIT;
