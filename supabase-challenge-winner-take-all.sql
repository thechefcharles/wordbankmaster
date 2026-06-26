-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Challenge: winner-take-all — full buy-ins at stake, no unspent refund       ║
-- ║  (migration: challenge_winner_take_all_2026_06 — applied via psql)          ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- Per the user: you don't get your money back. Your whole buy-in is staked. The pot
-- is the sum of everyone's full buy-in; the winner (most Cash left = spent least)
-- takes it; losers lose their entire stake. Spending less just decides who wins —
-- not how much you lose. Ties at the top still split the pot evenly.
--
-- Safety unchanged: if it wasn't a real contest (fewer than 2 paid, nobody finished,
-- or nobody solved a single puzzle) every buy-in is fully refunded.
--
-- History now logs the STAKE as `spent` (the whole buy-in leaves your wallet at
-- accept) and the pot share as `earned`, so net P&L is right: winner +pot−stake,
-- loser −stake.

CREATE OR REPLACE FUNCTION public._match_settle(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare m public.challenge_matches; v_paid int; v_done int; v_solved_max int;
  v_budget bigint; v_pot bigint := 0; v_max int; v_winners int; v_share bigint;
  v_third bigint; v_second bigint; v_first bigint; v_remaining bigint;
  v_refunded boolean := false; v_opponent uuid; v_winnings jsonb := '{}'::jsonb;
  v_spent int; v_earned int; v_wins int; r record;
begin
  select * into m from public.challenge_matches where id = p_id for update;
  if m.status <> 'open' then return; end if;
  v_budget := greatest(m.wager, 500);  -- fallback when a participant has no start_budget
  select count(*) into v_paid from public.challenge_participants where match_id = p_id and paid;
  select count(*) into v_done from public.challenge_participants where match_id = p_id and paid and state = 'done';
  select coalesce(max(solved),0) into v_solved_max from public.challenge_participants where match_id = p_id and state = 'done';

  if m.wager > 0 then
    if v_paid < 2 or v_done = 0 or v_solved_max = 0 then
      -- no real contest → full refund of each player's own buy-in
      v_refunded := true;
      for r in select user_id, coalesce(start_budget, v_budget) as refund
               from public.challenge_participants where match_id = p_id and paid loop
        perform public._bank_credit(r.user_id, r.refund, 'wager_refund'); end loop;
    else
      -- 🏆 winner-take-all: pot = sum of FULL buy-ins, no unspent refund
      select coalesce(sum(coalesce(start_budget, v_budget)), 0) into v_pot
        from public.challenge_participants where match_id = p_id and paid;
      if m.payout = 'podium' and v_done >= 3 then
        v_third := round(v_pot * 0.2); v_remaining := v_pot - v_third;
        v_first := round(v_remaining * 0.6); v_second := v_remaining - v_first;
        for r in select user_id, row_number() over (order by total_score desc, joined_at) as rk
                 from public.challenge_participants where match_id = p_id and paid and state = 'done' loop
          v_share := case r.rk when 1 then v_first when 2 then v_second when 3 then v_third else 0 end;
          if v_share > 0 then
            perform public._bank_credit(r.user_id, v_share, 'wager_win');
            v_winnings := v_winnings || jsonb_build_object(r.user_id::text, v_share);
          end if;
        end loop;
      else
        -- most Cash left wins; everyone tied for the top splits the pot evenly
        select max(total_score) into v_max from public.challenge_participants where match_id = p_id and paid and state = 'done';
        select count(*) into v_winners from public.challenge_participants where match_id = p_id and paid and state = 'done' and total_score = v_max;
        v_share := v_pot / greatest(v_winners, 1);
        for r in select user_id from public.challenge_participants where match_id = p_id and paid and state = 'done' and total_score = v_max loop
          perform public._bank_credit(r.user_id, v_share, 'wager_win');
          v_winnings := v_winnings || jsonb_build_object(r.user_id::text, v_share);
        end loop;
      end if;
    end if;
  end if;

  update public.challenge_matches set status = 'settled' where id = p_id;

  for r in select cp.user_id, cp.solved, cp.bankroll, coalesce(cp.start_budget, v_budget) as budget,
                  rank() over (order by cp.total_score desc) as rk,
                  count(*) filter (where true) over (partition by cp.total_score) as tied
           from public.challenge_participants cp where cp.match_id = p_id and cp.state = 'done' loop
    if v_refunded then
      perform public._notify(r.user_id, 'challenge_result', '🤝 Challenge tied',
        'No one solved it — ' || (case when m.wager>0 then 'buy-in refunded.' else 'no winner.' end),
        jsonb_build_object('match_id', p_id, 'tie', true, 'route','challenge'));
    elsif r.rk = 1 and r.tied > 1 then
      perform public._notify(r.user_id, 'challenge_result', '🤝 Tied for the win',
        'Solved ' || r.solved || '/' || m.pack_size || (case when m.wager>0 then ' — pot split +$' || coalesce((v_winnings->>r.user_id::text),'0') else '' end),
        jsonb_build_object('match_id', p_id, 'rank', 1, 'tie', true, 'route','challenge'));
    elsif r.rk = 1 then
      perform public._notify(r.user_id, 'challenge_result', '🏆 You won the challenge!',
        'Solved ' || r.solved || '/' || m.pack_size || (case when m.wager>0 then ' — took the pot +$' || coalesce((v_winnings->>r.user_id::text),'0') else '' end),
        jsonb_build_object('match_id', p_id, 'rank', 1, 'route','challenge'));
    else
      perform public._notify(r.user_id, 'challenge_result', '⚔️ Challenge settled',
        'Solved ' || r.solved || '/' || m.pack_size || ' · rank #' || r.rk,
        jsonb_build_object('match_id', p_id, 'rank', r.rk, 'route','challenge'));
    end if;

    v_opponent := case when m.group_id is null
      then (select cp2.user_id from public.challenge_participants cp2 where cp2.match_id = p_id and cp2.user_id <> r.user_id limit 1) else null end;
    if m.wager > 0 and not v_refunded then
      v_spent := r.budget::int;  -- the whole stake is at risk now (no refund)
      v_earned := coalesce((v_winnings->>r.user_id::text)::int, 0);
    else
      v_spent := null; v_earned := null;
    end if;
    perform public._log_game_result(
      r.user_id, 'challenge',
      case when v_refunded then 'tie' when r.rk = 1 and r.tied > 1 then 'tie' when r.rk = 1 then 'won' else 'lost' end,
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
