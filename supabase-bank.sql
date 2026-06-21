-- ============================================================
-- Bank economy — Phase A (applied to prod). Persistent, earned-only, virtual
-- Bank + a $5,000 starting loan; Net Worth = bank - loan. Bank is NEVER
-- purchasable or cashable. Ledger for auditability. Quest reward pays Bank.
-- Client: statsStore getBank/repayLoan, /bank screen, Net Worth chip on the menu.
-- See BANK_ECONOMY.md for the full design + roadmap.
-- ============================================================
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bank BIGINT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS loan BIGINT;

CREATE TABLE IF NOT EXISTS public.bank_ledger (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  delta BIGINT NOT NULL,
  reason TEXT NOT NULL,
  balance_after BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_bank_ledger_user_time ON public.bank_ledger(user_id, created_at DESC);
ALTER TABLE public.bank_ledger ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._ensure_bank(p_uid UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.profiles SET bank = 5000, loan = 5000 WHERE id = p_uid AND bank IS NULL;
END; $$;

CREATE OR REPLACE FUNCTION public._bank_credit(p_uid UUID, p_delta BIGINT, p_reason TEXT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_new BIGINT;
BEGIN
  PERFORM public._ensure_bank(p_uid);
  UPDATE public.profiles SET bank = GREATEST(0, COALESCE(bank,0) + p_delta) WHERE id = p_uid RETURNING bank INTO v_new;
  INSERT INTO public.bank_ledger(user_id, delta, reason, balance_after) VALUES (p_uid, p_delta, p_reason, v_new);
  RETURN v_new;
END; $$;

CREATE OR REPLACE FUNCTION public.get_bank()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_bank BIGINT; v_loan BIGINT; v_led JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT bank, loan INTO v_bank, v_loan FROM public.profiles WHERE id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('delta',delta,'reason',reason,'balance_after',balance_after,'at',created_at) ORDER BY created_at DESC), '[]'::jsonb)
    INTO v_led FROM (SELECT * FROM public.bank_ledger WHERE user_id = v_uid ORDER BY created_at DESC LIMIT 12) t;
  RETURN jsonb_build_object('bank', COALESCE(v_bank,0), 'loan', COALESCE(v_loan,0),
                            'net_worth', COALESCE(v_bank,0) - COALESCE(v_loan,0), 'ledger', v_led);
END; $$;
GRANT EXECUTE ON FUNCTION public.get_bank() TO authenticated;

CREATE OR REPLACE FUNCTION public.repay_loan(p_amount BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_bank BIGINT; v_loan BIGINT; v_pay BIGINT;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT bank, loan INTO v_bank, v_loan FROM public.profiles WHERE id = v_uid FOR UPDATE;
  v_pay := LEAST(GREATEST(COALESCE(p_amount,0),0), COALESCE(v_loan,0), COALESCE(v_bank,0));
  IF v_pay > 0 THEN
    UPDATE public.profiles SET bank = bank - v_pay, loan = loan - v_pay WHERE id = v_uid;
    INSERT INTO public.bank_ledger(user_id, delta, reason, balance_after) VALUES (v_uid, -v_pay, 'loan_payment', v_bank - v_pay);
  END IF;
  RETURN public.get_bank();
END; $$;
GRANT EXECUTE ON FUNCTION public.repay_loan(BIGINT) TO authenticated;

-- Quest reward now pays Bank (was a streak freeze).
CREATE OR REPLACE FUNCTION public.claim_quest_reward()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_status JSONB; v_bank BIGINT;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  v_status := public.get_daily_quests();
  IF v_status IS NULL OR NOT (v_status->>'all_done')::bool THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_done');
  END IF;
  INSERT INTO public.quest_claims(user_id, day) VALUES (v_uid, CURRENT_DATE) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'claimed'); END IF;
  v_bank := public._bank_credit(v_uid, 1000, 'quest_reward');
  RETURN jsonb_build_object('ok', true, 'reward', 'bank', 'amount', 1000, 'bank', v_bank);
END; $$;
GRANT EXECUTE ON FUNCTION public.claim_quest_reward() TO authenticated;
