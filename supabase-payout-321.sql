-- ============================================================================
-- Payout rework: the group "podium" option becomes a true 3-2-1 split.
--   • 'winner'  -> whole pot to the top scorer (unchanged; 1v1 always this).
--   • 'podium'  -> 3-2-1 placement split:
--        3 players  -> top 2 paid, 3:2  = 60/40
--        4+ players -> top 3 paid, 3:2:1 = 50 / 33.3 / 16.7
--      (was 3 -> 70/30, 4+ -> 60/30/10). 1v1 / 2 paid stays winner-take-all.
-- Only the v_shares expression changes; the rest of _match_settle is byte-identical to
-- the live definition. _match_board's pay-places logic (podium & 4+ -> 3, podium & 3 -> 2,
-- else 1) already matches this, so it needs no change. The internal payout value stays
-- 'podium' (no data/enum migration); only the split math and user-facing labels change.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public._match_settle(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare m public.challenge_matches; v_paid int; v_done int; v_solved_max int;
  v_budget bigint; v_pot bigint := 0; v_refunded boolean := false; v_opponent uuid; v_winnings jsonb := '{}'::jsonb;
  v_shares numeric[]; v_spent int; v_earned int; v_wins int; v_pay bigint; v_stake bigint; r record;
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
      for r in select user_id, coalesce(stake, v_budget) as refund
               from public.challenge_participants where match_id = p_id and paid loop
        perform public._bank_credit(r.user_id, r.refund, 'wager_refund'); end loop;
    else
      -- pot = sum of the ACTUAL stakes (v2: per-player stake; old: start_budget = wager).
      if m.econ_v = 2 then
        select coalesce(sum(coalesce(stake,0)), 0) into v_pot
          from public.challenge_participants where match_id = p_id and paid;
      else
        select coalesce(sum(coalesce(start_budget, v_budget)), 0) into v_pot
          from public.challenge_participants where match_id = p_id and paid;
      end if;
      -- Payout shape: creator's choice wins. 'winner' -> whole pot to the single top scorer
      -- (even for 3+ players). Otherwise ('podium' or legacy null) it's a 3-2-1 placement split:
      -- 3 paid -> top 2 at 3:2 (60/40); 4+ paid -> top 3 at 3:2:1 (50 / 33.3 / 16.7).
      -- 1v1 / 2 paid is winner-take-all either way.
      v_shares := case when m.payout = 'winner' then array[1.0]::numeric[]
                       when v_paid <= 2 then array[1.0]::numeric[]
                       when v_paid = 3  then array[3.0/5.0, 2.0/5.0]::numeric[]
                       else                  array[3.0/6.0, 2.0/6.0, 1.0/6.0]::numeric[] end;
      for r in
        with done as (
          select user_id, total_score,
                 rank()  over (order by total_score desc, public._match_elapsed(started_at, finished_at, joined_at) asc) as rk,
                 count(*) over (partition by total_score, public._match_elapsed(started_at, finished_at, joined_at))  as grp
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

  for r in select cp.user_id, cp.solved, cp.bankroll, cp.total_score, cp.stake, coalesce(cp.start_budget, v_budget) as budget,
                  rank() over (order by cp.total_score desc, public._match_elapsed(cp.started_at, cp.finished_at, cp.joined_at) asc) as rk,
                  count(*) filter (where true) over (partition by cp.total_score, public._match_elapsed(cp.started_at, cp.finished_at, cp.joined_at)) as tied
           from public.challenge_participants cp where cp.match_id = p_id and cp.state = 'done' loop
    if v_refunded then
      perform public._notify(r.user_id, 'challenge_result', 'Challenge tied',
        'No one solved it — ' || (case when m.wager>0 then 'ante refunded.' else 'no winner.' end),
        jsonb_build_object('match_id', p_id, 'tie', true, 'route','challenge'));
    elsif coalesce((v_winnings->>r.user_id::text)::bigint,0) > 0 or (r.rk = 1 and r.tied = 1) then
      perform public._notify(r.user_id, 'challenge_result',
        case when r.rk = 1 then 'You won the challenge!' else 'You placed — took a share' end,
        'Solved ' || r.solved || '/' || m.pack_size || (case when m.wager>0 then ' — +$' || coalesce((v_winnings->>r.user_id::text),'0') else '' end),
        jsonb_build_object('match_id', p_id, 'rank', r.rk, 'route','challenge'));
      if r.rk = 1 then
        if m.wager > 0 then perform public._award_badge(r.user_id, 'first_blood'); end if;
        if m.wager >= 10000 then perform public._award_badge(r.user_id, 'gold_duelist'); end if;
      end if;
    else
      perform public._notify(r.user_id, 'challenge_result', 'Challenge settled',
        'Solved ' || r.solved || '/' || m.pack_size || ' · rank #' || r.rk,
        jsonb_build_object('match_id', p_id, 'rank', r.rk, 'route','challenge'));
    end if;

    v_opponent := case when m.group_id is null
      then (select cp2.user_id from public.challenge_participants cp2 where cp2.match_id = p_id and cp2.user_id <> r.user_id limit 1) else null end;
    if m.wager > 0 and not v_refunded then
      -- game_results.spent = the actual STAKE so net (earned−spent) is true money P&L.
      -- (The "letters spent" skill number lives in the match-detail view, not here.)
      v_spent := case when m.econ_v = 2 then coalesce(r.stake, m.wager)::int else r.budget::int end;
      v_earned := coalesce((v_winnings->>r.user_id::text)::int, 0);
    else
      v_spent := null; v_earned := null;
    end if;
    if m.wager > 0 then
      perform public._log_game_result(
        r.user_id, 'challenge',
        case when v_refunded then 'tie'
             when r.rk = 1 and r.tied > 1 then 'tie'
             when r.rk = 1 then 'won'
             else 'lost' end,
        null, null, r.solved::int, m.pack_size::int, v_spent, v_earned, null, null,null,null,null,
        p_id, v_opponent, m.group_id, r.rk::int, v_done::int,
        (case when m.wager > 0 and not v_refunded then v_pot else null end), m.wager);
    end if;

    if r.rk = 1 and not v_refunded and r.tied = 1 then
      select count(*) into v_wins from public.challenge_matches mm
        join public.challenge_participants cpp on cpp.match_id = mm.id and cpp.user_id = r.user_id
        where mm.status = 'settled' and cpp.total_score = (select max(total_score) from public.challenge_participants x where x.match_id = mm.id);
      if m.wager > 0 and v_wins >= 10 then perform public._award_badge(r.user_id, 'hustler'); end if;
    end if;
  end loop;
  -- Paid players who never finished (state<>'done' at settle) — the done-loop above skipped
  -- them, so their money loss (stake swept into the pot) or refund was invisible: no result
  -- row, no notification. Record it here.
  for r in select cp.user_id, cp.solved, cp.stake, coalesce(cp.start_budget, v_budget) as budget
           from public.challenge_participants cp
           where cp.match_id = p_id and cp.paid and cp.state <> 'done' loop
    v_opponent := case when m.group_id is null
      then (select cp2.user_id from public.challenge_participants cp2 where cp2.match_id = p_id and cp2.user_id <> r.user_id limit 1) else null end;
    if v_refunded then
      perform public._notify(r.user_id, 'challenge_result', 'Challenge refunded',
        'No one solved it — your buy-in was refunded.',
        jsonb_build_object('match_id', p_id, 'tie', true, 'route','challenge'));
      if m.wager > 0 then
        perform public._log_game_result(r.user_id, 'challenge', 'tie',
          null, null, coalesce(r.solved,0)::int, m.pack_size::int, null, null, null, null,null,null,null,
          p_id, v_opponent, m.group_id, null, v_done::int, null, m.wager);
      end if;
    else
      v_spent := case when m.econ_v = 2 then coalesce(r.stake, m.wager)::int else r.budget::int end;
      perform public._notify(r.user_id, 'challenge_result', 'Challenge settled',
        'You did not finish in time' || (case when m.wager>0 then ' — lost your $' || v_spent::text || ' buy-in' else '' end) || '.',
        jsonb_build_object('match_id', p_id, 'route','challenge'));
      if m.wager > 0 then
        perform public._log_game_result(r.user_id, 'challenge', 'lost',
          null, null, coalesce(r.solved,0)::int, m.pack_size::int, v_spent, 0, null, null,null,null,null,
          p_id, v_opponent, m.group_id, null, v_done::int,
          (case when m.wager > 0 then v_pot else null end), m.wager);
      end if;
    end if;
  end loop;
end; $function$;

COMMIT;
