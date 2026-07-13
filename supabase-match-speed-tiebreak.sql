-- Prototype: fastest-solve tiebreaker for challenge matches.
-- Adds per-player finished_at, stamps started_at on match_start, and breaks
-- score ties in _match_settle by elapsed play time (finished_at - started_at).

alter table public.challenge_participants add column if not exists finished_at timestamptz;

-- Elapsed play seconds, with safe fallbacks for pre-migration / null data.
create or replace function public._match_elapsed(p_started timestamptz, p_finished timestamptz, p_joined timestamptz)
returns numeric language sql stable as $$
  select extract(epoch from (coalesce(p_finished, now()) - coalesce(p_started, p_joined, now())))::numeric;
$$;

CREATE OR REPLACE FUNCTION public.match_start(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cp public.challenge_participants; m public.challenge_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'match_start: not authenticated'; END IF;
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'match_start: not a participant'; END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  UPDATE public.challenge_participants SET started_at = COALESCE(started_at, now()) WHERE match_id = p_id AND user_id = v_uid;
  RETURN public._match_board(p_id, v_uid);
END; $function$

;

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
  PERFORM public._record_category_solve(p_uid, v_cat);            -- NEW: counts toward category badges
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
END; $function$

;

CREATE OR REPLACE FUNCTION public.match_fold(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_uid uuid := auth.uid(); cp public.challenge_participants; m public.challenge_matches;
  v_phrase text; v_charge bigint; v_left bigint; v_next_bounty int;
begin
  if v_uid is null then raise exception 'match_fold: not authenticated'; end if;
  if public._match_tick(p_id, v_uid) then return public._match_board(p_id, v_uid); end if;
  select * into cp from public.challenge_participants where match_id = p_id and user_id = v_uid for update;
  if not found or cp.state <> 'active' then return public._match_board(p_id, v_uid); end if;
  select * into m from public.challenge_matches where id = p_id;
  -- full price of every still-unrevealed distinct letter (base cost), capped at remaining ante
  select upper(phrase) into v_phrase from public.daily_puzzles where id = public._match_pid(p_id, cp.position);
  select coalesce(sum(public.letter_cost(t.ch)), 0) into v_charge from (
    select distinct substr(v_phrase, g.i+1, 1) as ch from generate_series(0, length(v_phrase)-1) g(i)
    where substr(v_phrase, g.i+1, 1) ~ '[A-Z]' and not (g.i = any(cp.revealed_positions))
  ) t;
  v_charge := least(v_charge, cp.bankroll);
  v_left := greatest(0, cp.bankroll - v_charge);

  if m.econ_v = 2 then
    -- Accumulate this puzzle's leftover; advance with a fresh bounty (mirrors the solve path).
    if cp.position >= m.pack_size then
      update public.challenge_participants
        set state = 'done', bankroll = v_left, last_score = 0, total_score = total_score + v_left,
            finished_at = now(), finished_at = now(), joined_at = coalesce(joined_at, now())
        where match_id = p_id and user_id = v_uid;
      perform public._match_maybe_settle(p_id);
      perform public._match_notify_opponent_played(p_id, v_uid);
    else
      v_next_bounty := public._match_pos_bounty(p_id, cp.position + 1);
      update public.challenge_participants
        set position = position + 1, bankroll = v_next_bounty,
            start_budget = coalesce(start_budget, 0) + v_next_bounty,
            last_score = 0, total_score = total_score + v_left,
            revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
            p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
        where match_id = p_id and user_id = v_uid;
    end if;
    return public._match_board(p_id, v_uid);
  end if;

  -- OLD (econ_v NULL): rank by Cash left; single carried budget, total_score = leftover.
  if cp.position >= m.pack_size then
    update public.challenge_participants
      set state = 'done', bankroll = v_left, last_score = 0, total_score = v_left,
          finished_at = now(), finished_at = now(), joined_at = coalesce(joined_at, now())
      where match_id = p_id and user_id = v_uid;
    perform public._match_maybe_settle(p_id);
  else
    update public.challenge_participants
      set position = position + 1, bankroll = v_left, last_score = 0, total_score = v_left,
          revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
          p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
      where match_id = p_id and user_id = v_uid;
  end if;
  return public._match_board(p_id, v_uid);
end; $function$

;

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
        perform public._award_badge(r.user_id, 'first_blood');
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
    perform public._log_game_result(
      r.user_id, 'challenge',
      case when v_refunded then 'tie'
           when r.rk = 1 and r.tied > 1 then 'tie'
           when r.rk = 1 then 'won'
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
      perform public._log_game_result(r.user_id, 'challenge', 'tie',
        null, null, coalesce(r.solved,0)::int, m.pack_size::int, null, null, null, null,null,null,null,
        p_id, v_opponent, m.group_id, null, v_done::int, null, m.wager);
    else
      v_spent := case when m.econ_v = 2 then coalesce(r.stake, m.wager)::int else r.budget::int end;
      perform public._notify(r.user_id, 'challenge_result', 'Challenge settled',
        'You did not finish in time' || (case when m.wager>0 then ' — lost your $' || v_spent::text || ' buy-in' else '' end) || '.',
        jsonb_build_object('match_id', p_id, 'route','challenge'));
      perform public._log_game_result(r.user_id, 'challenge', 'lost',
        null, null, coalesce(r.solved,0)::int, m.pack_size::int, v_spent, 0, null, null,null,null,null,
        p_id, v_opponent, m.group_id, null, v_done::int,
        (case when m.wager > 0 then v_pot else null end), m.wager);
    end if;
  end loop;
end; $function$

;

CREATE OR REPLACE FUNCTION public.get_match_detail(p_match_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v_status text; v_settled boolean; v_budget bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.challenge_participants WHERE match_id = p_match_id AND user_id = v_uid) THEN
    RETURN NULL;
  END IF;
  SELECT status, GREATEST(COALESCE(wager,0), 500) INTO v_status, v_budget
  FROM public.challenge_matches WHERE id = p_match_id;
  v_settled := (v_status = 'settled');
  RETURN jsonb_build_object(
    'match', (SELECT jsonb_build_object('id', m.id, 'mode', m.mode, 'pack_size', m.pack_size,
                'wager', m.wager, 'budget', v_budget, 'payout', m.payout, 'status', m.status, 'group_id', m.group_id)
              FROM public.challenge_matches m WHERE m.id = p_match_id),
    'group_name', (SELECT g.name FROM public.groups g
                   JOIN public.challenge_matches cm ON cm.group_id = g.id WHERE cm.id = p_match_id),
    'participants', (SELECT jsonb_agg(jsonb_build_object(
        'user_id', t.user_id, 'name', public._display_name(t.user_id), 'is_me', (t.user_id = v_uid),
        'solved', t.solved, 'score', t.total_score, 'spent', GREATEST(0, COALESCE(t.start_budget, v_budget) - t.total_score - CASE WHEN t.state = 'done' THEN 0 ELSE t.bankroll END),
        'net', t.net, 'earned', t.earned, 'multiple_x100', t.multiple_x100,
        'state', t.state, 'rank', t.rnk, 'elapsed_seconds', public._match_elapsed(t.started_at, t.finished_at, t.joined_at)
      ) ORDER BY t.total_score DESC)
      FROM (SELECT cp.user_id, cp.solved, cp.total_score, cp.bankroll, cp.start_budget, cp.state, cp.started_at, cp.finished_at, cp.joined_at,
                   rank() OVER (ORDER BY cp.total_score DESC, public._match_elapsed(cp.started_at, cp.finished_at, cp.joined_at) ASC) AS rnk,
                   gr.net, gr.earned, gr.multiple_x100
            FROM public.challenge_participants cp
            LEFT JOIN public.game_results gr ON gr.match_id = p_match_id AND gr.user_id = cp.user_id
            WHERE cp.match_id = p_match_id) t),
    'pack', (SELECT jsonb_agg(jsonb_build_object(
        'position', pk.position, 'category', dp.category,
        'phrase', CASE WHEN v_settled THEN dp.phrase ELSE NULL END
      ) ORDER BY pk.position)
      FROM public.challenge_pack pk JOIN public.daily_puzzles dp ON dp.id = pk.puzzle_id
      WHERE pk.match_id = p_match_id)
  );
END; $function$

;

CREATE OR REPLACE FUNCTION public.get_profile_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); p public.profiles; v_climb INT; v_cwins INT; v_closs INT; v_cties INT;
  v_badges JSONB; v_avg INT; v_best INT; v_solved INT; v_earned BIGINT; v_spent BIGINT; v_dplayed INT; v_dwon INT; v_solve_avg INT; v_solve_best INT;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT * INTO p FROM public.profiles WHERE id = v_uid;
  SELECT position INTO v_climb FROM public.climb_state WHERE user_id = v_uid;
  SELECT
    count(*) FILTER (WHERE game_mode='challenge' AND outcome='won'),
    count(*) FILTER (WHERE game_mode='challenge' AND outcome='lost'),
    count(*) FILTER (WHERE game_mode='challenge' AND outcome='tie'),
    round(avg(multiple_x100) FILTER (WHERE multiple_x100 IS NOT NULL))::int,
    max(multiple_x100),
    COALESCE(sum(COALESCE(solved_count, CASE WHEN outcome='won' THEN 1 ELSE 0 END)),0),
    COALESCE(sum(earned),0), COALESCE(sum(spent),0),
    count(*) FILTER (WHERE game_mode='daily'),
    count(*) FILTER (WHERE game_mode='daily' AND outcome='won')
  INTO v_cwins, v_closs, v_cties, v_avg, v_best, v_solved, v_earned, v_spent, v_dplayed, v_dwon
  FROM public.game_results WHERE user_id = v_uid;
  SELECT round(avg(secs))::int, round(min(secs))::int INTO v_solve_avg, v_solve_best
  FROM (SELECT extract(epoch from (finished_at - started_at)) / greatest(solved,1) AS secs
        FROM public.challenge_participants
        WHERE user_id = v_uid AND state = 'done' AND solved > 0
          AND started_at IS NOT NULL AND finished_at IS NOT NULL) q;
  SELECT COALESCE(jsonb_agg(badge), '[]'::jsonb) INTO v_badges FROM public.user_badges WHERE user_id = v_uid;
  RETURN jsonb_build_object(
    'username', p.username,
    'net_worth', COALESCE(p.bank,0), 'cash', COALESCE(p.bank,0),
    'current_streak', COALESCE(p.current_daily_play_streak,0), 'longest_streak', COALESCE(p.best_daily_play_streak,0),
    'games_played', v_dplayed, 'games_won', v_dwon,
    'puzzles_solved', v_solved, 'climb_position', COALESCE(v_climb,0),
    'challenge_wins', COALESCE(v_cwins,0), 'challenge_losses', COALESCE(v_closs,0), 'challenge_ties', COALESCE(v_cties,0),
    'avg_multiple_x100', v_avg, 'best_multiple_x100', v_best,
    'total_earned', v_earned, 'total_spent', v_spent,
    'avg_solve_seconds', v_solve_avg, 'best_solve_seconds', v_solve_best,
    'badges', v_badges);
END; $function$

;
