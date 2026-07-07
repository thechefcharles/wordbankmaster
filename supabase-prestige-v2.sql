-- V2 Phase 6: Prestige & cosmetics — the earned-status layer.
--
-- Wires the V2 badge set across every mode + the marquee EARNED title (🦈 Gold Shark).
--   • cosmetics.earned flag → earned items are granted, never shown in the Store.
--   • _grant_title grants an earned title (auto-equips if you have none).
--   • Badges awarded at the moments they're earned: Cash Game cash-out, Blitz settle,
--     Challenge settle, loan payoff. (_award_badge is idempotent — ON CONFLICT DO NOTHING.)
-- Spec: Notion mode specs' Badges sections + V2 Roadmap Phase 6. PITR logged before apply.

BEGIN;

-- Earned (not-for-sale) cosmetics.
ALTER TABLE public.cosmetics ADD COLUMN IF NOT EXISTS earned boolean DEFAULT false;
INSERT INTO public.cosmetics (id, kind, label, value, price, sort, earned)
VALUES ('title_gold_shark', 'title', '🦈 Gold Shark', 'Gold Shark', 0, 100, true)
ON CONFLICT (id) DO UPDATE SET label = EXCLUDED.label, value = EXCLUDED.value, earned = true;

-- Store lists only for-sale cosmetics (earned ones live in your vault once granted).
CREATE OR REPLACE FUNCTION public.get_shop()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_bank BIGINT; v_items JSONB; v_t TEXT; v_c TEXT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('bank',0,'items','[]'::jsonb); END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT bank, equipped_title, equipped_color INTO v_bank, v_t, v_c FROM public.profiles WHERE id = v_uid;
  SELECT jsonb_agg(jsonb_build_object(
    'id', c.id, 'kind', c.kind, 'label', c.label, 'value', c.value, 'price', c.price,
    'owned', EXISTS (SELECT 1 FROM public.user_cosmetics uc WHERE uc.user_id = v_uid AND uc.cosmetic_id = c.id),
    'equipped', (c.id = v_t OR c.id = v_c)
  ) ORDER BY c.sort) INTO v_items FROM public.cosmetics c WHERE NOT COALESCE(c.earned, false);
  RETURN jsonb_build_object('bank', COALESCE(v_bank,0), 'items', COALESCE(v_items,'[]'::jsonb));
END; $function$;

-- Grant an earned title (auto-equip if you're not wearing one yet).
CREATE OR REPLACE FUNCTION public._grant_title(p_uid uuid, p_id text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO public.user_cosmetics(user_id, cosmetic_id) VALUES (p_uid, p_id) ON CONFLICT DO NOTHING;
  UPDATE public.profiles SET equipped_title = p_id WHERE id = p_uid AND equipped_title IS NULL;
END; $function$;

-- ══ Cash Game cash-out: tier reach · run streak · big multiple · max heat · high roller · 🦈 Gold Shark ══
CREATE OR REPLACE FUNCTION public.cashgame_cashout()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_profit BIGINT; v_mult INT; v_wins jsonb; v_streak INT; v_bestrs INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'cashgame_cashout: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state NOT IN ('active','stuck','solved') THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_run'); END IF;
  v_profit := cs.bankroll - cs.buy_in;
  v_mult := CASE WHEN cs.buy_in > 0 THEN round(cs.bankroll * 100.0 / cs.buy_in)::int ELSE 0 END;
  IF cs.bankroll > 0 THEN PERFORM public._bank_credit(v_uid, cs.bankroll, 'cashgame_cashout'); END IF;
  SELECT COALESCE(cg_wins,'{}'::jsonb), COALESCE(cg_run_streak,0), COALESCE(cg_best_run_streak,0)
    INTO v_wins, v_streak, v_bestrs FROM public.profiles WHERE id = v_uid;
  IF v_profit > 0 THEN
    v_wins := jsonb_set(v_wins, ARRAY[cs.tier], to_jsonb(COALESCE((v_wins->>cs.tier)::int,0) + 1), true);
    v_streak := v_streak + 1;
  ELSE
    v_streak := 0;
  END IF;
  UPDATE public.profiles SET
    cg_wins = v_wins, cg_run_streak = v_streak, cg_best_run_streak = GREATEST(v_bestrs, v_streak),
    cg_best_run = GREATEST(COALESCE(cg_best_run,0), cs.bankroll),
    cg_best_multiple_x100 = GREATEST(COALESCE(cg_best_multiple_x100,0), v_mult),
    cg_best_heat_x100 = GREATEST(COALESCE(cg_best_heat_x100,100), cs.heat_x100),
    cg_lifetime_net = COALESCE(cg_lifetime_net,0) + v_profit
    WHERE id = v_uid;
  -- 🏅 prestige
  PERFORM public._award_badge(v_uid, 'cg_' || cs.tier);
  IF v_streak >= 5 THEN PERFORM public._award_badge(v_uid, 'cg_run_5'); END IF;
  IF v_mult >= 1000 THEN PERFORM public._award_badge(v_uid, 'cg_multiple_10'); END IF;
  IF cs.heat_x100 >= COALESCE((public._cg_tier(cs.tier)->>'heat_cap')::int, 250) THEN PERFORM public._award_badge(v_uid, 'cg_heat_max'); END IF;
  IF cs.bankroll >= 25000 THEN PERFORM public._award_badge(v_uid, 'cg_high_roller'); END IF;
  IF cs.tier = 'gold' AND v_profit > 0 THEN
    PERFORM public._grant_title(v_uid, 'title_gold_shark');
    PERFORM public._award_badge(v_uid, 'gold_shark');
  END IF;
  DELETE FROM public.climb_state WHERE user_id = v_uid;
  RETURN jsonb_build_object('ok', true, 'banked', cs.bankroll, 'buy_in', cs.buy_in, 'profit', v_profit,
    'multiple_x100', v_mult, 'solves', cs.run_solves, 'tier', cs.tier, 'heat', cs.heat_x100);
END; $function$;

-- ══ Blitz settle: tier reach · Speed Demon · combo milestones · high roller ══
CREATE OR REPLACE FUNCTION public._blitz_settle(p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE r public.blitz_runs; v_net bigint; v_tier_order int; v_cur_order int;
BEGIN
  SELECT * INTO r FROM public.blitz_runs WHERE user_id = p_uid FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('blitz', jsonb_build_object('state','ended','ok',false)); END IF;
  v_net := r.winnings - r.buy_in;
  IF r.winnings > 0 THEN PERFORM public._bank_credit(p_uid, r.winnings, 'blitz_payout'); END IF;
  v_tier_order := COALESCE((public._blitz_tier(r.tier)->>'order')::int, 0);
  v_cur_order  := COALESCE((public._blitz_tier((SELECT bz_highest_tier FROM public.profiles WHERE id = p_uid))->>'order')::int, 0);
  UPDATE public.profiles SET
    bz_best_run = GREATEST(COALESCE(bz_best_run,0), r.solved),
    bz_best_combo_x100 = GREATEST(COALESCE(bz_best_combo_x100,100), r.combo_x100),
    bz_best_payout = GREATEST(COALESCE(bz_best_payout,0), r.winnings),
    bz_lifetime_net = COALESCE(bz_lifetime_net,0) + v_net,
    bz_runs = COALESCE(bz_runs,0) + 1,
    bz_highest_tier = CASE WHEN v_tier_order > v_cur_order THEN r.tier ELSE bz_highest_tier END
    WHERE id = p_uid;
  -- 🏅 prestige
  PERFORM public._award_badge(p_uid, 'bz_' || r.tier);
  IF r.solved >= 10 THEN PERFORM public._award_badge(p_uid, 'bz_speed_demon'); END IF;
  IF r.combo_x100 >= 500 THEN PERFORM public._award_badge(p_uid, 'bz_combo_5');
  ELSIF r.combo_x100 >= 300 THEN PERFORM public._award_badge(p_uid, 'bz_combo_3'); END IF;
  IF r.winnings >= 5000 THEN PERFORM public._award_badge(p_uid, 'bz_high_roller'); END IF;
  DELETE FROM public.blitz_runs WHERE user_id = p_uid;
  RETURN jsonb_build_object('blitz', jsonb_build_object('state','ended','ok',true,
    'solved', r.solved, 'winnings', r.winnings, 'buy_in', r.buy_in, 'net', v_net,
    'best_combo', r.combo_x100, 'tier', r.tier));
END; $function$;

-- ══ Loan payoff: Paid in Full ══
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
  PERFORM public._bank_credit(v_uid, -v_pay, 'loan_repay');
  IF v_loan - v_pay <= 0 THEN PERFORM public._award_badge(v_uid, 'paid_in_full'); END IF;
  RETURN jsonb_build_object('ok',true,'paid',v_pay,'remaining',v_loan - v_pay,'cleared',(v_loan - v_pay) <= 0);
END; $function$;

-- ══ Challenge win: First Blood · Gold Duelist (added inside the settle notify/log loop) ══
-- (Re-defining _match_settle to add the two award lines where a paid winner is finalized.)
CREATE OR REPLACE FUNCTION public._match_settle(p_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER
AS $function$
declare m public.challenge_matches; v_paid int; v_done int; v_solved_max int;
  v_budget bigint; v_pot bigint := 0; v_refunded boolean := false; v_opponent uuid; v_winnings jsonb := '{}'::jsonb;
  v_shares numeric[]; v_spent int; v_earned int; v_wins int; v_pay bigint; r record;
begin
  select * into m from public.challenge_matches where id = p_id for update;
  if m.status <> 'open' then return; end if;
  v_budget := greatest(m.wager, 500);
  select count(*) into v_paid from public.challenge_participants where match_id = p_id and paid;
  select count(*) into v_done from public.challenge_participants where match_id = p_id and paid and state = 'done';
  select coalesce(max(solved),0) into v_solved_max from public.challenge_participants where match_id = p_id and state = 'done';

  if m.wager > 0 then
    if v_paid < 2 or v_done = 0 or v_solved_max = 0 then
      v_refunded := true;
      for r in select user_id, coalesce(start_budget, v_budget) as refund
               from public.challenge_participants where match_id = p_id and paid loop
        perform public._bank_credit(r.user_id, r.refund, 'wager_refund'); end loop;
    else
      select coalesce(sum(coalesce(start_budget, v_budget)), 0) into v_pot
        from public.challenge_participants where match_id = p_id and paid;
      v_shares := case when v_paid <= 2 then array[1.0]::numeric[]
                       when v_paid = 3  then array[0.7, 0.3]::numeric[]
                       else                  array[0.6, 0.3, 0.1]::numeric[] end;
      for r in
        with done as (
          select user_id, total_score,
                 rank()  over (order by total_score desc) as rk,
                 count(*) over (partition by total_score)  as grp
          from public.challenge_participants where match_id = p_id and paid and state = 'done'
        )
        select d.user_id,
          ( (select coalesce(sum(case when p <= array_length(v_shares,1) then v_shares[p] else 0 end), 0)
               from generate_series(d.rk, d.rk + d.grp - 1) p) / d.grp ) as frac
        from done d
      loop
        v_pay := round(v_pot * r.frac)::bigint;
        if v_pay > 0 then
          perform public._bank_credit(r.user_id, v_pay, 'wager_win');
          v_winnings := v_winnings || jsonb_build_object(r.user_id::text, v_pay);
        end if;
      end loop;
    end if;
  end if;

  update public.challenge_matches set status = 'settled' where id = p_id;

  for r in select cp.user_id, cp.solved, cp.bankroll, coalesce(cp.start_budget, v_budget) as budget,
                  rank() over (order by cp.total_score desc) as rk,
                  count(*) filter (where true) over (partition by cp.total_score) as tied
           from public.challenge_participants cp where cp.match_id = p_id and cp.state = 'done' loop
    if v_refunded then
      perform public._notify(r.user_id, 'challenge_result', '🤝 Challenge tied',
        'No one solved it — ' || (case when m.wager>0 then 'ante refunded.' else 'no winner.' end),
        jsonb_build_object('match_id', p_id, 'tie', true, 'route','challenge'));
    elsif coalesce((v_winnings->>r.user_id::text)::bigint,0) > 0 then
      perform public._notify(r.user_id, 'challenge_result',
        case when r.rk = 1 then '🏆 You won the challenge!' else '🥈 You placed — took a share' end,
        'Solved ' || r.solved || '/' || m.pack_size || (case when m.wager>0 then ' — +$' || coalesce((v_winnings->>r.user_id::text),'0') else '' end),
        jsonb_build_object('match_id', p_id, 'rank', r.rk, 'route','challenge'));
      -- 🏅 prestige: a paid winner
      if r.rk = 1 then
        perform public._award_badge(r.user_id, 'first_blood');
        if m.wager >= 10000 then perform public._award_badge(r.user_id, 'gold_duelist'); end if;
      end if;
    else
      perform public._notify(r.user_id, 'challenge_result', '⚔️ Challenge settled',
        'Solved ' || r.solved || '/' || m.pack_size || ' · rank #' || r.rk,
        jsonb_build_object('match_id', p_id, 'rank', r.rk, 'route','challenge'));
    end if;

    v_opponent := case when m.group_id is null
      then (select cp2.user_id from public.challenge_participants cp2 where cp2.match_id = p_id and cp2.user_id <> r.user_id limit 1) else null end;
    if m.wager > 0 and not v_refunded then
      v_spent := r.budget::int; v_earned := coalesce((v_winnings->>r.user_id::text)::int, 0);
    else
      v_spent := null; v_earned := null;
    end if;
    perform public._log_game_result(
      r.user_id, 'challenge',
      case when v_refunded then 'tie'
           when coalesce((v_winnings->>r.user_id::text)::bigint,0) > 0 and r.rk = 1 and r.tied > 1 then 'tie'
           when coalesce((v_winnings->>r.user_id::text)::bigint,0) > 0 and r.rk = 1 then 'won'
           else 'lost' end,
      null, null, r.solved::int, m.pack_size::int, v_spent, v_earned, null, null,null,null,null,
      p_id, v_opponent, m.group_id, r.rk::int, v_done::int,
      (case when m.wager > 0 and not v_refunded then v_pot else null end), m.wager);

    if r.rk = 1 and not v_refunded and r.tied = 1 then
      select count(*) into v_wins from public.challenge_matches mm
        join public.challenge_participants cpp on cpp.match_id = mm.id and cpp.user_id = r.user_id
        where mm.status = 'settled' and cpp.total_score = (select max(total_score) from public.challenge_participants x where x.match_id = mm.id);
      if v_wins >= 10 then perform public._award_badge(r.user_id, 'hustler'); end if;
    end if;
  end loop;
end; $function$;

COMMIT;
