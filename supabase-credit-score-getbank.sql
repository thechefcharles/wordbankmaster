-- Credit Score Phase 1 — surface credit in get_bank (lazy daily recompute) and add
-- get_credit_detail() for the gauge breakdown. PITR point logged before apply.
BEGIN;

CREATE OR REPLACE FUNCTION public._credit_read(p_uid UUID)
  RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE v_score INT; v_upd TIMESTAMPTZ; v_prev INT;
BEGIN
  SELECT credit_score, credit_updated_at INTO v_score, v_upd
    FROM public.profiles WHERE id = p_uid;
  IF v_upd IS NULL OR v_upd::date < current_date THEN
    SELECT score INTO v_prev FROM public.credit_history
      WHERE user_id = p_uid ORDER BY at DESC LIMIT 1;
    v_score := public._recompute_credit(p_uid);
    RETURN jsonb_build_object('credit_score', v_score,
      'credit_tier', public._credit_tier(v_score),
      'credit_delta', v_score - COALESCE(v_prev, v_score));
  END IF;
  RETURN jsonb_build_object('credit_score', COALESCE(v_score,650),
    'credit_tier', public._credit_tier(COALESCE(v_score,650)),
    'credit_delta', 0);
END; $fn$;

CREATE OR REPLACE FUNCTION public.get_bank(p_limit INT DEFAULT 12)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_bank BIGINT; v_loan BIGINT; v_led JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT bank, loan INTO v_bank, v_loan FROM public.profiles WHERE id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('delta',delta,'reason',reason,
           'balance_after',balance_after,'at',created_at) ORDER BY created_at DESC),'[]'::jsonb)
    INTO v_led FROM (SELECT * FROM public.bank_ledger WHERE user_id = v_uid
                      ORDER BY created_at DESC LIMIT p_limit) t;
  RETURN jsonb_build_object('bank', COALESCE(v_bank,0), 'loan', COALESCE(v_loan,0),
           'net_worth', COALESCE(v_bank,0) - COALESCE(v_loan,0), 'ledger', v_led)
         || public._credit_read(v_uid);
END; $$;
GRANT EXECUTE ON FUNCTION public.get_bank(INT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_credit_detail()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_score INT; v_target INT; v_comp JSONB; v_hist JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._credit_read(v_uid);
  SELECT score, target, components INTO v_score, v_target, v_comp
    FROM public.credit_history WHERE user_id = v_uid ORDER BY at DESC LIMIT 1;
  v_score := COALESCE(v_score, 650);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('at', at, 'score', score) ORDER BY at), '[]')
    INTO v_hist FROM (SELECT at, score FROM public.credit_history
                       WHERE user_id = v_uid ORDER BY at DESC LIMIT 30) h;
  RETURN jsonb_build_object(
    'score', v_score, 'target', COALESCE(v_target, v_score),
    'tier', public._credit_tier(v_score), 'history', v_hist,
    'components', jsonb_build_object(
      'utilization', jsonb_build_object('value', COALESCE((v_comp->>'U')::numeric,1),
        'label','Utilization','hint','Repay loans and keep debt low.'),
      'solvency', jsonb_build_object('value', COALESCE((v_comp->>'S')::numeric,1),
        'label','Solvency','hint','Stay out of the red.'),
      'repayment', jsonb_build_object('value', COALESCE((v_comp->>'R')::numeric,1),
        'label','Repayment','hint','Repay loans yourself before they auto-collect.'),
      'restraint', jsonb_build_object('value', COALESCE((v_comp->>'B')::numeric,1),
        'label','Restraint','hint','Avoid frequent borrowing.'),
      'consistency', jsonb_build_object('value', COALESCE((v_comp->>'C')::numeric,1),
        'label','Consistency','hint','Play daily to build history.')));
END; $$;
GRANT EXECUTE ON FUNCTION public.get_credit_detail() TO authenticated;
COMMIT;
