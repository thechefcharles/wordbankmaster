-- Credit Score Phase 2a — loan effects on READ + restore the rich get_bank that
-- Phase 1 accidentally slimmed (it had dropped _accrue_loan + loan detail fields).
-- Adds credit-tier cap factor + rate-adjust helpers and merges credit into get_bank.
-- PITR point logged before apply.
BEGIN;

-- Effective loan cap = base (Cash-Game-tier) cap scaled by credit tier.
--   Excellent ×1.25 · Good ×1.0 · Fair ×0.5 · Poor floor $250 · Bad locked (0).
CREATE OR REPLACE FUNCTION public._credit_effective_cap(p_uid uuid)
  RETURNS bigint LANGUAGE plpgsql STABLE SECURITY DEFINER AS $fn$
DECLARE v_base bigint; v_score int;
BEGIN
  v_base := public._loan_cap(p_uid);
  SELECT COALESCE(credit_score, 650) INTO v_score FROM public.profiles WHERE id = p_uid;
  RETURN CASE public._credit_tier(v_score)
    WHEN 'Excellent' THEN round(v_base * 1.25)::bigint
    WHEN 'Good'      THEN v_base
    WHEN 'Fair'      THEN round(v_base * 0.5)::bigint
    WHEN 'Poor'      THEN LEAST(v_base, 250)
    ELSE 0
  END;
END; $fn$;

-- Daily-rate adjustment (basis points) added to the base curve at borrow time.
CREATE OR REPLACE FUNCTION public._credit_rate_adjust(p_score int)
  RETURNS int LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE public._credit_tier(p_score)
    WHEN 'Excellent' THEN -300
    WHEN 'Good'      THEN 0
    WHEN 'Fair'      THEN 300
    WHEN 'Poor'      THEN 600
    ELSE 0
  END;
$fn$;

-- get_bank: rich loan detail (accrue + principal/rate/days/projected) + credit fields,
-- with loan_cap now the credit-effective cap.
CREATE OR REPLACE FUNCTION public.get_bank(p_limit integer DEFAULT 12)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); p public.profiles; v_led jsonb; v_rate numeric;
        v_tomorrow bigint; v_days int; v_credit jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  PERFORM public._accrue_loan(v_uid);
  v_credit := public._credit_read(v_uid);         -- recompute (≤1/day) BEFORE effective cap
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
    'loan_cap', public._credit_effective_cap(v_uid), 'ledger', v_led,
    'loan_principal', COALESCE(p.loan_principal,0), 'loan_rate_bp', COALESCE(p.loan_rate_bp,0),
    'loan_taken_at', p.loan_taken_at, 'loan_days', v_days, 'loan_owed_tomorrow', v_tomorrow)
    || v_credit;
END; $function$;
GRANT EXECUTE ON FUNCTION public.get_bank(integer) TO authenticated;

COMMIT;
