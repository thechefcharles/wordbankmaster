-- V2 Phase 2: the Loan Shark — borrow / repay + 50% auto-skim + debt lockout.
--
-- Builds the loan system now so the tiered risk modes (Cash Game V2, Challenges V2)
-- have their "can't afford" answer. Loans live ONLY in the risk tiers — never gate the Daily.
--   • profiles.loan = total OWED (principal + 25% fee); loan_accrued_at = when taken.
--   • take_loan: 25% flat fee, credit-limit check, ONE active loan at a time.
--   • repay_loan: pay manually (partial/full) from Cash.
--   • _bank_credit auto-skims 50% of every positive payout toward an active loan (Daily,
--     cash-outs, challenge wins, attendance) — the debt digs itself out; loan_take/repay/skim exempt.
--   • Debt lockout: money-out (Store: buy_cosmetic/buy_powerup) blocked while loan > 0.
--   • Negative net worth: get_bank + the Daily board show bank − loan (you look broke, rank drops).
-- Credit limit is a flat $500 for now (Bronze default); _loan_cap scales with tier in Phase 3.
-- Spec: Notion "Cash Game V2 → Loans". PITR point logged before apply.

BEGIN;

-- Credit limit (Phase 2: flat; Phase 3: scale with highest unlocked Cash Game tier).
CREATE OR REPLACE FUNCTION public._loan_cap(p_uid uuid)
 RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER
AS $function$ SELECT 500::bigint; $function$;

-- _bank_credit + 50% auto-skim toward an active loan (transparent: full payout line, then a skim line).
CREATE OR REPLACE FUNCTION public._bank_credit(p_uid uuid, p_delta bigint, p_reason text)
 RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_new BIGINT; v_loan BIGINT; v_skim BIGINT;
BEGIN
  PERFORM public._ensure_bank(p_uid);
  INSERT INTO public.networth_snapshots(user_id, week_start, net_worth)
    SELECT p_uid, date_trunc('week', CURRENT_DATE)::date, COALESCE(bank,0)
    FROM public.profiles WHERE id = p_uid
    ON CONFLICT DO NOTHING;
  UPDATE public.profiles SET bank = GREATEST(0, COALESCE(bank,0) + p_delta) WHERE id = p_uid RETURNING bank INTO v_new;
  INSERT INTO public.bank_ledger(user_id, delta, reason, balance_after) VALUES (p_uid, p_delta, p_reason, v_new);
  -- Auto-skim 50% of positive payouts toward an outstanding loan (not the loan flows themselves).
  IF p_delta > 0 AND p_reason NOT IN ('loan_take','loan_repay','loan_skim') THEN
    SELECT COALESCE(loan,0) INTO v_loan FROM public.profiles WHERE id = p_uid;
    IF v_loan > 0 THEN
      v_skim := LEAST(v_loan, floor(p_delta * 0.5)::bigint);
      IF v_skim > 0 THEN
        UPDATE public.profiles SET bank = GREATEST(0, COALESCE(bank,0) - v_skim),
          loan = v_loan - v_skim,
          loan_accrued_at = CASE WHEN v_loan - v_skim <= 0 THEN NULL ELSE loan_accrued_at END
          WHERE id = p_uid RETURNING bank INTO v_new;
        INSERT INTO public.bank_ledger(user_id, delta, reason, balance_after) VALUES (p_uid, -v_skim, 'loan_skim', v_new);
      END IF;
    END IF;
  END IF;
  RETURN v_new;
END; $function$;

-- Borrow: 25% flat fee, one active loan, capped by _loan_cap.
CREATE OR REPLACE FUNCTION public.take_loan(p_amount bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_loan BIGINT; v_cap BIGINT; v_owed BIGINT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RETURN jsonb_build_object('ok',false,'reason','bad_amount'); END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT COALESCE(loan,0) INTO v_loan FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_loan > 0 THEN RETURN jsonb_build_object('ok',false,'reason','active_loan'); END IF;
  v_cap := public._loan_cap(v_uid);
  IF p_amount > v_cap THEN RETURN jsonb_build_object('ok',false,'reason','over_cap','cap',v_cap); END IF;
  v_owed := p_amount + round(p_amount * 0.25)::bigint;             -- 25% origination fee
  UPDATE public.profiles SET loan = v_owed, loan_accrued_at = now() WHERE id = v_uid;
  PERFORM public._bank_credit(v_uid, p_amount, 'loan_take');       -- principal to Cash (skim-exempt)
  RETURN jsonb_build_object('ok',true,'borrowed',p_amount,'owed',v_owed,'fee',v_owed - p_amount);
END; $function$;

-- Repay: pay down the loan from Cash (partial or, with NULL, the max you can afford).
CREATE OR REPLACE FUNCTION public.repay_loan(p_amount bigint DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_loan BIGINT; v_bank BIGINT; v_pay BIGINT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT COALESCE(loan,0), COALESCE(bank,0) INTO v_loan, v_bank FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_loan <= 0 THEN RETURN jsonb_build_object('ok',false,'reason','no_loan'); END IF;
  v_pay := LEAST(COALESCE(p_amount, v_loan), v_loan, v_bank);
  IF v_pay <= 0 THEN RETURN jsonb_build_object('ok',false,'reason','insufficient'); END IF;
  UPDATE public.profiles SET loan = v_loan - v_pay,
    loan_accrued_at = CASE WHEN v_loan - v_pay <= 0 THEN NULL ELSE loan_accrued_at END WHERE id = v_uid;
  PERFORM public._bank_credit(v_uid, -v_pay, 'loan_repay');        -- debit Cash (skim-exempt)
  RETURN jsonb_build_object('ok',true,'paid',v_pay,'remaining',v_loan - v_pay,'cleared',(v_loan - v_pay) <= 0);
END; $function$;

-- Debt lockout: no money-out (Store) while a loan is outstanding.
CREATE OR REPLACE FUNCTION public.buy_cosmetic(p_id text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_price BIGINT; v_kind TEXT; v_bank BIGINT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  IF COALESCE((SELECT loan FROM public.profiles WHERE id = v_uid),0) > 0 THEN RETURN jsonb_build_object('ok',false,'reason','in_debt'); END IF;
  SELECT price, kind INTO v_price, v_kind FROM public.cosmetics WHERE id = p_id;
  IF v_price IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','no_item'); END IF;
  IF EXISTS (SELECT 1 FROM public.user_cosmetics WHERE user_id = v_uid AND cosmetic_id = p_id) THEN
    RETURN jsonb_build_object('ok',false,'reason','owned'); END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT bank INTO v_bank FROM public.profiles WHERE id = v_uid;
  IF v_bank < v_price THEN RETURN jsonb_build_object('ok',false,'reason','insufficient'); END IF;
  PERFORM public._bank_credit(v_uid, -v_price, 'cosmetic_buy');
  INSERT INTO public.user_cosmetics(user_id, cosmetic_id) VALUES (v_uid, p_id) ON CONFLICT DO NOTHING;
  IF v_kind = 'title' THEN UPDATE public.profiles SET equipped_title = p_id WHERE id = v_uid;
  ELSIF v_kind = 'color' THEN UPDATE public.profiles SET equipped_color = p_id WHERE id = v_uid;
  END IF;
  RETURN jsonb_build_object('ok',true);
END; $function$;

CREATE OR REPLACE FUNCTION public.buy_powerup(p_id text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_price BIGINT; v_cash BIGINT; v_owned INT; v_kind TEXT; v_cap INT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  IF COALESCE((SELECT loan FROM public.profiles WHERE id = v_uid),0) > 0 THEN RETURN jsonb_build_object('ok',false,'reason','in_debt'); END IF;
  SELECT price, kind INTO v_price, v_kind FROM public.powerups WHERE id = p_id AND active;
  IF v_price IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','no_item'); END IF;
  v_cap := CASE WHEN v_kind = 'daily' THEN 5 ELSE 1 END;
  SELECT COALESCE(qty,0) INTO v_owned FROM public.user_powerups_v2 WHERE user_id=v_uid AND powerup_id=p_id AND pool='cash';
  IF COALESCE(v_owned,0) >= v_cap THEN RETURN jsonb_build_object('ok',false,'reason','owned'); END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT bank INTO v_cash FROM public.profiles WHERE id = v_uid;
  IF v_cash < v_price THEN RETURN jsonb_build_object('ok',false,'reason','insufficient'); END IF;
  PERFORM public._bank_credit(v_uid, -v_price, 'powerup_buy');
  PERFORM public._award_powerup(v_uid, p_id, 'cash');
  RETURN jsonb_build_object('ok',true);
END; $function$;

-- get_bank: expose the real loan, capacity, and net worth (bank − loan).
CREATE OR REPLACE FUNCTION public.get_bank(p_limit integer DEFAULT 12)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_bank BIGINT; v_loan BIGINT; v_led JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT COALESCE(bank,0), COALESCE(loan,0) INTO v_bank, v_loan FROM public.profiles WHERE id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('delta',delta,'reason',reason,'balance_after',balance_after,'at',created_at) ORDER BY created_at DESC), '[]'::jsonb)
    INTO v_led FROM (SELECT * FROM public.bank_ledger WHERE user_id = v_uid ORDER BY created_at DESC LIMIT GREATEST(p_limit, 1)) t;
  RETURN jsonb_build_object('bank', v_bank, 'net_worth', v_bank - v_loan,
    'loan', v_loan, 'auto_repay', v_loan > 0, 'in_the_red', v_loan > 0,
    'loan_cap', public._loan_cap(v_uid), 'ledger', v_led);
END; $function$;

-- Daily board: Cash (net worth) reflects debt = bank − loan (a debtor looks broke / ranks lower).
CREATE OR REPLACE FUNCTION public.get_daily_board(p_scope text DEFAULT 'everyone'::text, p_group uuid DEFAULT NULL::uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB; v_base int;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  v_base := public._daily_reward(public._todays_puzzle_id());
  WITH circle AS (
    SELECT v_uid AS id
    UNION SELECT friend_id FROM public.friendships WHERE user_id = v_uid AND p_scope = 'friends'
    UNION SELECT user_id FROM public.group_members WHERE group_id = p_group AND p_scope = 'group'
    UNION SELECT id FROM public.profiles WHERE p_scope IN ('global','everyone')
  ),
  d AS (
    SELECT c.id,
      (COALESCE(pr.bank, 0) - COALESCE(pr.loan, 0))::bigint AS net_worth,
      (CASE WHEN pr.last_daily_play_date >= CURRENT_DATE - 1 THEN COALESCE(pr.current_daily_play_streak,0) ELSE 0 END) AS play_streak,
      (CASE WHEN pr.last_daily_solve_date >= CURRENT_DATE - 1 THEN COALESCE(pr.current_daily_solve_streak,0) ELSE 0 END) AS win_streak,
      g.score AS score,
      (CASE WHEN g.won AND v_base > 0 THEN GREATEST(0, LEAST(100, round(COALESCE(g.kept,0)::numeric / v_base * 100)::int)) ELSE NULL END) AS efficiency,
      pr.equipped_title, pr.equipped_color
    FROM circle c
    JOIN public.profiles pr ON pr.id = c.id
    LEFT JOIN LATERAL (
      SELECT gr.score, gr.kept, gr.won FROM public.game_results gr
      WHERE gr.user_id = c.id AND gr.game_mode = 'daily' AND gr.played_at::date = CURRENT_DATE
      ORDER BY gr.played_at DESC LIMIT 1
    ) g ON true
    WHERE c.id IS NOT NULL
  ),
  ranked AS (
    SELECT *, row_number() OVER (ORDER BY (score IS NULL), score DESC NULLS LAST, net_worth DESC) AS rank
    FROM d ORDER BY (score IS NULL), score DESC NULLS LAST, net_worth DESC LIMIT 100
  )
  SELECT jsonb_agg(jsonb_build_object(
    'rank', rank, 'name', public._display_name(id), 'net_worth', net_worth, 'score', score,
    'efficiency', efficiency,
    'play_streak', play_streak, 'win_streak', win_streak, 'played', score IS NOT NULL,
    'is_me', id = v_uid, 'title', equipped_title, 'color', equipped_color) ORDER BY rank) INTO v_rows FROM ranked;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $function$;

COMMIT;
