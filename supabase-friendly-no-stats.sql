-- Challenges: friendly (wager = 0) matches award no stats/badges/leaderboard/category
--
-- Friendly ≡ challenge_matches.wager = 0. A settled/advanced friendly match must:
--   * write NO game_results row (this alone keeps it out of the challenge leaderboard,
--     best-bounty, wealth board, and play-log — those all read
--     game_results WHERE game_mode='challenge'),
--   * award NO badges (first_blood, hustler),
--   * record NO category-solve credit.
-- Money matches (wager > 0) behave EXACTLY as before — every gate below is purely additive
-- (an `if m.wager > 0 then <existing statement> end if` wrapper), never altering the
-- existing statements' arguments.
--
-- NOTE on get_challenge_leaderboard / best-bounty (deliberately NOT changed):
--   get_challenge_leaderboard reads `WHERE gr.game_mode='challenge'` with NO join to
--   challenge_matches, so a `wager > 0` filter cannot be added there safely — and isn't
--   needed. The write-side gate here (no friendly game_results row is ever written) already
--   excludes friendlies from the leaderboard, best-bounty, wealth board, and play-log.
--   The write-side gate is the single source of exclusion; no read-side change is required.

-- ============================================================================
-- Function 1: _match_settle — gate the three _log_game_result calls + badges
-- ============================================================================
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
      v_shares := case when v_paid <= 2 then array[1.0]::numeric[]
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

-- ============================================================================
-- Function 2: _match_resolve_and_advance — gate the category-solve credit
-- ============================================================================
CREATE OR REPLACE FUNCTION public._match_resolve_and_advance(p_id uuid, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cp public.challenge_participants; m public.challenge_matches; v_phrase TEXT; v_cat TEXT; v_won BOOLEAN;
  v_score INT; v_combo INT; v_solved INT; v_budget BIGINT; v_next_bounty INT;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF cp.state <> 'active' THEN RETURN public._match_board(p_id, p_uid); END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  v_budget := GREATEST(COALESCE(m.wager,0), 500);
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = public._match_pid(p_id, cp.position);
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(cp.revealed_positions)));
  IF NOT v_won THEN RETURN public._match_board(p_id, p_uid); END IF;
  IF COALESCE(m.wager,0) > 0 THEN PERFORM public._record_category_solve(p_uid, v_cat); END IF;  -- friendly (wager 0) earns no category credit
  v_solved := cp.solved + 1;
  IF m.econ_v = 2 THEN
    IF cp.position >= m.pack_size THEN
      UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
        total_score = total_score + cp.bankroll, state = 'done', finished_at = now(), joined_at = COALESCE(joined_at, now())
      WHERE match_id = p_id AND user_id = p_uid;
      PERFORM public._match_maybe_settle(p_id); PERFORM public._match_notify_opponent_played(p_id, p_uid);
    ELSE
      v_next_bounty := public._match_pos_bounty(p_id, cp.position + 1);
      UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
        total_score = total_score + cp.bankroll, position = position + 1,
        bankroll = v_next_bounty, start_budget = COALESCE(start_budget,0) + v_next_bounty,
        revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
        p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
      WHERE match_id = p_id AND user_id = p_uid;
    END IF;
    RETURN public._match_board(p_id, p_uid);
  END IF;

  -- OLD (econ_v NULL): rank by Cash left; single carried budget, total_score = bankroll.
  IF cp.position >= m.pack_size THEN
    UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
      total_score = cp.bankroll, state = 'done', finished_at = now(), joined_at = COALESCE(joined_at, now())
    WHERE match_id = p_id AND user_id = p_uid;
    PERFORM public._match_maybe_settle(p_id); PERFORM public._match_notify_opponent_played(p_id, p_uid);
  ELSE
    UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
      total_score = cp.bankroll, position = position + 1,
      revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}', p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
    WHERE match_id = p_id AND user_id = p_uid;
  END IF;
  RETURN public._match_board(p_id, p_uid);
END; $function$;
