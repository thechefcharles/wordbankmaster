-- Credit Score Phase 1 — core recompute. Derives 5 discipline components from a
-- 14-day bank_ledger window, eases the stored score toward a target (bounded per
-- day), applies new-player grace + derogatory cap + event jolts, logs history.
-- PITR point logged before apply.
BEGIN;

CREATE OR REPLACE FUNCTION public._recompute_credit(
  p_uid UUID,
  p_event TEXT DEFAULT NULL,
  p_event_delta INT DEFAULT 0
) RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  DROP_CAP CONSTANT INT := 120;
  RISE_CAP CONSTANT INT := 40;
  v_bank BIGINT; v_loan BIGINT; v_created TIMESTAMPTZ;
  v_prev INT; v_updated TIMESTAMPTZ; v_derog TIMESTAMPTZ; v_streak INT;
  v_cap BIGINT;
  u NUMERIC; s NUMERIC; r NUMERIC; b NUMERIC; c NUMERIC;
  v_neg_days INT; v_repay INT; v_skim INT; v_take INT; v_active_days INT;
  v_target INT; v_new INT; v_days_elapsed INT; i INT;
  v_had_loan BOOLEAN;
BEGIN
  PERFORM public._ensure_bank(p_uid);
  -- COALESCE loan/bank to 0: a player who never borrowed has loan = NULL, and NULL
  -- would (a) make `v_loan > 0` NULL so grace is skipped and (b) make LEAST(NULL/cap,1)
  -- collapse to 1 → utilization 0, wrongly deflating a debt-free newcomer.
  SELECT COALESCE(p.bank, 0), COALESCE(p.loan, 0), p.credit_score, p.credit_updated_at,
         p.credit_derog_until, COALESCE(p.current_daily_play_streak, 0)
    INTO v_bank, v_loan, v_prev, v_updated, v_derog, v_streak
    FROM public.profiles p WHERE p.id = p_uid;
  SELECT u.created_at INTO v_created FROM auth.users u WHERE u.id = p_uid;
  v_prev := COALESCE(v_prev, 650);

  SELECT (v_loan > 0) OR EXISTS(
    SELECT 1 FROM public.bank_ledger WHERE user_id = p_uid AND reason = 'loan_take'
  ) INTO v_had_loan;

  IF v_created IS NOT NULL AND v_created > now() - INTERVAL '7 days' AND NOT v_had_loan THEN
    UPDATE public.profiles
       SET credit_score = 650, credit_updated_at = now() WHERE id = p_uid;
    INSERT INTO public.credit_history(user_id, score, target, tier, components)
      VALUES (p_uid, 650, 650, 'Good', jsonb_build_object('grace', true));
    RETURN 650;
  END IF;

  v_cap := GREATEST(public._loan_cap(p_uid), 1);

  u := 1 - LEAST(v_loan::numeric / v_cap, 1);

  SELECT COUNT(DISTINCT date(created_at)) INTO v_neg_days
    FROM public.bank_ledger
   WHERE user_id = p_uid AND created_at > now() - INTERVAL '14 days'
     AND balance_after < 0;
  s := 1 - LEAST(v_neg_days::numeric / 14, 1);
  IF (v_bank - v_loan) < 0 THEN s := LEAST(s, 0.5); END IF;

  SELECT COUNT(*) FILTER (WHERE reason = 'loan_repay'),
         COUNT(*) FILTER (WHERE reason = 'loan_skim'),
         COUNT(*) FILTER (WHERE reason = 'loan_take')
    INTO v_repay, v_skim, v_take
    FROM public.bank_ledger
   WHERE user_id = p_uid AND created_at > now() - INTERVAL '14 days';
  r := CASE WHEN (v_repay + v_skim) = 0 THEN 1
            ELSE v_repay::numeric / (v_repay + v_skim) END;
  IF v_derog IS NOT NULL AND v_derog > now() THEN r := LEAST(r, 0.3); END IF;

  b := 1 - LEAST(v_take::numeric / 6, 1);

  IF v_streak > 0 THEN
    c := LEAST(v_streak::numeric / 14, 1);
  ELSE
    SELECT COUNT(DISTINCT date(created_at)) INTO v_active_days
      FROM public.bank_ledger
     WHERE user_id = p_uid AND created_at > now() - INTERVAL '14 days';
    c := LEAST(v_active_days::numeric / 14, 1);
  END IF;

  v_target := round(300 + 550 * (0.35*u + 0.25*s + 0.20*r + 0.10*b + 0.10*c));
  v_target := GREATEST(300, LEAST(850, v_target));

  v_days_elapsed := GREATEST(1, LEAST(7,
    COALESCE(date_part('day', now() - v_updated)::int, 1)));
  v_new := v_prev;
  FOR i IN 1..v_days_elapsed LOOP
    v_new := v_new + GREATEST(LEAST(v_target - v_new, RISE_CAP), -DROP_CAP);
  END LOOP;

  v_new := GREATEST(300, LEAST(850, v_new + COALESCE(p_event_delta, 0)));

  UPDATE public.profiles
     SET credit_score = v_new, credit_updated_at = now() WHERE id = p_uid;
  INSERT INTO public.credit_history(user_id, score, target, tier, components)
    VALUES (p_uid, v_new, v_target, public._credit_tier(v_new),
      jsonb_build_object('U',round(u,3),'S',round(s,3),'R',round(r,3),
                         'B',round(b,3),'C',round(c,3),'event',p_event));
  -- Credit-tier badge milestones (700 / 800 / perfect 850).
  IF v_new >= 700 THEN PERFORM public._award_badge(p_uid, 'credit_700'); END IF;
  IF v_new >= 800 THEN PERFORM public._award_badge(p_uid, 'credit_800'); END IF;
  IF v_new >= 850 THEN PERFORM public._award_badge(p_uid, 'credit_850'); END IF;
  RETURN v_new;
END; $fn$;

-- SECURITY: internal-only. Clients must NOT call this directly — it accepts an
-- arbitrary p_uid and p_event_delta, so a GRANT to authenticated would allow score
-- tampering/IDOR. It is invoked solely by SECURITY DEFINER wrappers (get_bank,
-- get_credit_detail, and — in later phases — loan lifecycle functions) which run as
-- the owner and derive the uid from auth.uid(). Revoke from all client roles.
REVOKE ALL ON FUNCTION public._recompute_credit(UUID, TEXT, INT) FROM PUBLIC, anon, authenticated;
COMMIT;
