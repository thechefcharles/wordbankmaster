-- Challenge Batch 2 · Task 2 — Payout creator toggle (Winner-take-all vs Top-finishers-split)
--
-- Goal: let a GROUP creator choose the payout and make settle RESPECT the stored
-- `challenge_matches.payout` instead of deriving winner-vs-split purely by field size.
--   * create_match: store the incoming p_payout ('winner' | 'podium'); when null/absent,
--     default by field size for back-compat (1v1 -> winner, group -> podium).
--   * _match_settle: when m.payout = 'winner' pay the single top scorer the whole pot
--     (even for 3+); otherwise ('podium' or legacy null) fall back to the existing
--     count-based split (2 -> winner, 3 -> 70/30, 4+ -> 60/30/10). 1v1 is winner-take-all
--     regardless. ALL other money math (pot, shares loop, _bank_credit, _log_game_result,
--     notifies, refunds, tie handling) is byte-identical to the live body.
--
-- Dumped live 2026-07-16 via pg_get_functiondef and transformed surgically.

-- ─────────────────────────────────────────────────────────────────────────────
-- create_match — resolve v_payout AFTER the field is known so a null defaults by count
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_match(p_opponent text, p_group_id uuid, p_categories text[], p_pack_size integer, p_wager bigint, p_mode text, p_payout text, p_window_seconds integer, p_items_allowed boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_uid uuid := auth.uid(); v_id uuid; v_opp uuid; v_size int; v_wager bigint; v_mode text; v_payout text;
  v_n int; v_budget bigint; v_cash bigint; v_uids uuid[]; r record;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'reason','auth'); end if;
  v_size := least(greatest(coalesce(p_pack_size,1),1),10);
  v_wager := greatest(coalesce(p_wager,0),0);
  if v_wager > 0 and v_wager < 500 then return jsonb_build_object('ok',false,'reason','min_wager'); end if;
  v_mode := 'standard';  -- Blitz retired; all matches are standard
  if p_group_id is not null then
    if not exists (select 1 from public.group_members where group_id = p_group_id and user_id = v_uid) then
      return jsonb_build_object('ok',false,'reason','not_member'); end if;
    select array_agg(user_id) into v_uids from public.group_members where group_id = p_group_id;
  else
    select id into v_opp from public.profiles where lower(username) = lower(trim(coalesce(p_opponent,'')));
    if v_opp is null then return jsonb_build_object('ok',false,'reason','no_opponent'); end if;
    if v_opp = v_uid then return jsonb_build_object('ok',false,'reason','self'); end if;
    v_uids := array[v_uid, v_opp];
  end if;
  -- Payout: honor an explicit creator choice; else default by field size for back-compat
  -- (1v1 -> winner-take-all, group -> top-finishers split). Settle respects this value.
  v_payout := case when p_payout in ('winner','podium') then p_payout
                   when coalesce(array_length(v_uids,1),0) <= 2 then 'winner'
                   else 'podium' end;
  if v_wager > 0 then
    perform public._ensure_bank(v_uid);
    select bank into v_cash from public.profiles where id = v_uid;
    if v_cash < v_wager then return jsonb_build_object('ok',false,'reason','insufficient'); end if;
    perform public._bank_credit(v_uid, -v_wager, 'wager_stake');
  end if;
  insert into public.challenge_matches(host_id, group_id, mode, categories, pack_size, wager, payout, settles_at, items_allowed, econ_v)
  values (v_uid, p_group_id, v_mode, coalesce(p_categories,'{}'), v_size, v_wager, v_payout, now() + (least(greatest(coalesce(p_window_seconds,172800),3600),604800) || ' seconds')::interval, coalesce(p_items_allowed,false), 2)
  returning id into v_id;
  insert into public.challenge_pack(match_id, position, puzzle_id)
  select v_id, row_number() over (), pid
  from public._pick_casual_pack(v_uids, coalesce(p_categories,'{}'), v_size, 8) pid;
  select count(*) into v_n from public.challenge_pack where match_id = v_id;
  if v_n = 0 then return jsonb_build_object('ok',false,'reason','no_puzzles'); end if;
  -- NEW: budget = puzzle-1 bounty (standardized), not GREATEST(wager,500).
  v_budget := public._match_pos_bounty(v_id, 1);
  insert into public.challenge_participants(match_id, user_id, paid, state, joined_at, bankroll, start_budget, stake)
  values (v_id, v_uid, v_wager > 0, 'active', now(), v_budget, v_budget, v_wager);
  perform public._mark_seen_many(v_uid, (select array_agg(puzzle_id) from public.challenge_pack where match_id = v_id));
  if p_group_id is not null then
    for r in select user_id from public.group_members where group_id = p_group_id and user_id <> v_uid loop
      insert into public.challenge_participants(match_id, user_id) values (v_id, r.user_id) on conflict do nothing;
      perform public._notify(r.user_id, 'challenge_incoming', 'Group challenge',
        public._display_name(v_uid) || ' challenged your group' || case when v_wager>0 then ' — $' || v_wager else '' end,
        jsonb_build_object('match_id', v_id));
    end loop;
  else
    insert into public.challenge_participants(match_id, user_id) values (v_id, v_opp);
    perform public._notify(v_opp, 'challenge_incoming', 'New challenge',
      public._display_name(v_uid) || ' challenged you — ' || v_n || ' puzzle' || case when v_n=1 then '' else 's' end ||
      case when v_wager>0 then ' · $' || v_wager else '' end, jsonb_build_object('match_id', v_id, 'route','challenge'));
  end if;
  return jsonb_build_object('ok',true, 'match', public.get_match(v_id));
end; $function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- _match_settle — the ONLY change is the v_shares decision: honor m.payout='winner'
-- (whole pot to the single top scorer even for 3+); 'podium'/legacy-null falls back to
-- the existing count-based split. Everything else is byte-identical to the live body.
-- ─────────────────────────────────────────────────────────────────────────────
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
      -- (even for 3+ players). Otherwise ('podium' or legacy null) fall back to the field-size
      -- rule: 1v1 winner-take-all, 3 -> 70/30, 4+ -> 60/30/10. A 1v1 is winner-take-all either way.
      v_shares := case when m.payout = 'winner' then array[1.0]::numeric[]
                       when v_paid <= 2 then array[1.0]::numeric[]
                       when v_paid = 3  then array[0.7, 0.3]::numeric[]
                       else                  array[0.6, 0.3, 0.1]::numeric[] end;
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
