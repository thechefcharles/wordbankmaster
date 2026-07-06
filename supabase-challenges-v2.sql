-- V2 Phase 4: Challenges V2 — alignment with the V2 grammar.
--
-- Challenges already run the budget model (ante staked → pot; bankroll = ante spent down;
-- score = ante − spent; winner takes the pot). Two gaps vs the V2 spec, fixed here:
--   1. Wrong guesses now DRAIN the budget (universal rule) — they were stat-only.
--   2. Payout is now a field-size PODIUM: Duel(2) winner-take-all (tie 50/50);
--      Group(3) 70/30; Group(4+) 60/30/10. Ties split their combined rank shares.
--      No-contest (<2 paid, or nobody solved) → full ante refund.
-- Tier antes (Bronze $500 / Silver $2000 / Gold $10000) are frontend-driven (create_match
-- already takes the wager). Loans fund antes via the existing Loan Shark.
-- Spec: Notion "Challenges V2". PITR point logged before apply.

BEGIN;

-- 1) Wrong guess drains the budget: remaining −= GREATEST($10, round(0.2×remaining/10)×10).
CREATE OR REPLACE FUNCTION public.match_submit_guess(p_id uuid, p_guess jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cp public.challenge_participants; v_phrase TEXT; v_editable INT[]; v_correct INT[] := '{}'; v_all BOOLEAN := true; pos INT; v_ch TEXT; v_pen INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'match_submit_guess: not authenticated'; END IF;
  IF public._match_tick(p_id, v_uid) THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cp.state <> 'active' THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = public._match_pid(p_id, cp.position);
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1,1) <> ' ' AND NOT (g.i = ANY(cp.revealed_positions));
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable,1) THEN RETURN public._match_board(p_id, v_uid); END IF;
  FOREACH pos IN ARRAY v_editable LOOP
    v_ch := upper(p_guess ->> pos::text);
    IF v_ch IS NULL THEN v_all := false;
    ELSIF v_ch = substr(v_phrase, pos+1, 1) THEN v_correct := v_correct || pos;
    ELSE v_all := false; END IF;
  END LOOP;
  IF v_all THEN
    cp.revealed_positions := ARRAY(SELECT DISTINCT unnest(cp.revealed_positions || v_correct) ORDER BY 1);
    UPDATE public.challenge_participants SET revealed_positions = cp.revealed_positions
      WHERE match_id = p_id AND user_id = v_uid;
  ELSE
    -- Wrong guess wastes budget (universal WordBank rule), lowering your score.
    v_pen := GREATEST(10, (round(0.2 * cp.bankroll / 10.0) * 10)::int);
    cp.bankroll := GREATEST(0, cp.bankroll - v_pen);
    cp.p_wrong_guesses := cp.p_wrong_guesses + 1;
    UPDATE public.challenge_participants SET bankroll = cp.bankroll, p_wrong_guesses = cp.p_wrong_guesses
      WHERE match_id = p_id AND user_id = v_uid;
  END IF;
  RETURN public._match_resolve_and_advance(p_id, v_uid);
END; $function$;

-- 2) Field-size podium payout + ties-split-combined-shares + no-contest refund.
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
      -- no real contest → full refund of each player's own ante
      v_refunded := true;
      for r in select user_id, coalesce(start_budget, v_budget) as refund
               from public.challenge_participants where match_id = p_id and paid loop
        perform public._bank_credit(r.user_id, r.refund, 'wager_refund'); end loop;
    else
      select coalesce(sum(coalesce(start_budget, v_budget)), 0) into v_pot
        from public.challenge_participants where match_id = p_id and paid;
      -- payout structure by FIELD SIZE (players who anted)
      v_shares := case when v_paid <= 2 then array[1.0]::numeric[]
                       when v_paid = 3  then array[0.7, 0.3]::numeric[]
                       else                  array[0.6, 0.3, 0.1]::numeric[] end;
      -- each finisher's share = (Σ shares over the positions their tie-group occupies) ÷ group size
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
