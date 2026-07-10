-- ============================================================================
-- Phase 1 — Challenge bounty economy (spec: docs/.../2026-07-09-economy-rework-*)
-- Spend the puzzle BOUNTY (standardized), not the ante. The ante is now a pure
-- STAKE → Pot; Score accumulates across the pack (goes UP).
--
-- VERSION-GATED on challenge_matches.econ_v = 2. Existing open matches have
-- econ_v = NULL and keep the OLD behaviour end-to-end (seed/spend/settle), so
-- nothing in flight is mis-paid. Only NEW matches (create_match sets econ_v=2)
-- run the new economy.
--
-- New-model column semantics on challenge_participants:
--   bankroll     = current puzzle's remaining bounty allowance (spend on letters)
--   total_score  = cumulative "cash kept" banked across solved puzzles  (the Score)
--   start_budget = cumulative bounty GRANTED across the pack (for spent = granted−score)
--
-- PITR point logged before apply.
-- ============================================================================
BEGIN;

-- 1) Version marker (existing rows stay NULL = old economy) ------------------
ALTER TABLE public.challenge_matches ADD COLUMN IF NOT EXISTS econ_v int;
-- Actual amount each player ANTED (v2 decouples the stake from the bounty budget,
-- and reduced-stake joins mean stakes can differ per player → pot = sum of stakes).
ALTER TABLE public.challenge_participants ADD COLUMN IF NOT EXISTS stake bigint;

-- 2) Standardized per-puzzle challenge bounty --------------------------------
--    Reuse _climb_bounty (k × cost of all distinct letters). k is a fixed
--    challenge constant (NOT the wager) so every duel plays identically
--    regardless of stake. k=2 leaves comfortable room to "keep" budget.
CREATE OR REPLACE FUNCTION public._match_bounty(p_pid uuid)
  RETURNS int LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT public._climb_bounty(p_pid, 2.0);
$$;

CREATE OR REPLACE FUNCTION public._match_pos_bounty(p_id uuid, p_pos int)
  RETURNS int LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT public._match_bounty(public._match_pid(p_id, GREATEST(COALESCE(p_pos,1),1)));
$$;

-- 3) create_match: stamp econ_v=2, seed host from puzzle-1 bounty ------------
CREATE OR REPLACE FUNCTION public.create_match(p_opponent text, p_group_id uuid, p_categories text[], p_pack_size integer, p_wager bigint, p_mode text, p_payout text, p_window_seconds integer, p_items_allowed boolean)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
declare v_uid uuid := auth.uid(); v_id uuid; v_opp uuid; v_size int; v_wager bigint; v_mode text; v_payout text;
  v_n int; v_budget bigint; v_cash bigint; v_uids uuid[]; r record;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'reason','auth'); end if;
  v_size := least(greatest(coalesce(p_pack_size,1),1),10);
  v_wager := greatest(coalesce(p_wager,0),0);
  if v_wager > 0 and v_wager < 500 then return jsonb_build_object('ok',false,'reason','min_wager'); end if;
  v_mode := case when p_mode = 'blitz' then 'blitz' else 'standard' end;
  v_payout := case when p_payout = 'podium' then 'podium' else 'winner' end;
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

-- 4) accept_match: seed opponent from their current-position bounty (v2) -----
CREATE OR REPLACE FUNCTION public.accept_match(p_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
declare v_uid UUID := auth.uid(); m public.challenge_matches; me public.challenge_participants; v_cash BIGINT; v_seed BIGINT;
begin
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND OR m.status <> 'open' THEN RETURN jsonb_build_object('ok',false,'reason','closed'); END IF;
  SELECT * INTO me FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','not_invited'); END IF;
  IF me.state <> 'invited' THEN RETURN jsonb_build_object('ok',true, 'match', public.get_match(p_id)); END IF;
  IF m.wager > 0 THEN
    PERFORM public._ensure_bank(v_uid);
    SELECT bank INTO v_cash FROM public.profiles WHERE id = v_uid;
    IF v_cash < m.wager THEN RETURN jsonb_build_object('ok',false,'reason','insufficient'); END IF;
    PERFORM public._bank_credit(v_uid, -m.wager, 'wager_stake');
  END IF;
  -- NEW (econ_v=2): seed from puzzle bounty; OLD: GREATEST(wager,500).
  v_seed := CASE WHEN m.econ_v = 2 THEN public._match_pos_bounty(p_id, COALESCE(me.position,1))
                 ELSE GREATEST(m.wager, 500) END;
  UPDATE public.challenge_participants SET paid = (m.wager > 0), state = 'active', joined_at = now(),
    bankroll = v_seed, start_budget = v_seed, stake = m.wager
  WHERE match_id = p_id AND user_id = v_uid;
  IF m.host_id IS NOT NULL AND m.host_id <> v_uid THEN
    INSERT INTO public.friendships(user_id, friend_id) VALUES (v_uid, m.host_id), (m.host_id, v_uid) ON CONFLICT DO NOTHING;
  END IF;
  RETURN jsonb_build_object('ok',true, 'match', public.get_match(p_id));
END; $function$;

-- 4b) accept_match (reduced-stake overload) — same bounty seeding + record stake
CREATE OR REPLACE FUNCTION public.accept_match(p_id uuid, p_reduced boolean DEFAULT false)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid UUID := auth.uid(); m public.challenge_matches; me public.challenge_participants;
  v_cash BIGINT; v_stake BIGINT; v_seed BIGINT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND OR m.status <> 'open' THEN RETURN jsonb_build_object('ok',false,'reason','closed'); END IF;
  SELECT * INTO me FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','not_invited'); END IF;
  IF me.state <> 'invited' THEN RETURN jsonb_build_object('ok',true, 'match', public.get_match(p_id)); END IF;
  v_stake := 0;
  IF m.wager > 0 THEN
    PERFORM public._ensure_bank(v_uid);
    SELECT bank INTO v_cash FROM public.profiles WHERE id = v_uid;
    IF v_cash >= m.wager THEN v_stake := m.wager;
    ELSIF p_reduced AND v_cash > 0 THEN v_stake := v_cash;
    ELSE RETURN jsonb_build_object('ok',false,'reason','insufficient','cash',COALESCE(v_cash,0),'wager',m.wager); END IF;
    PERFORM public._bank_credit(v_uid, -v_stake, 'wager_stake');
  END IF;
  -- NEW (econ_v=2): spend budget from puzzle bounty; OLD: the staked amount.
  v_seed := CASE WHEN m.econ_v = 2 THEN public._match_pos_bounty(p_id, COALESCE(me.position,1))
                 ELSE GREATEST(v_stake, CASE WHEN m.wager > 0 THEN 500 ELSE 0 END) END;
  UPDATE public.challenge_participants SET paid = (m.wager > 0), state = 'active', joined_at = now(),
    bankroll = v_seed, start_budget = v_seed, stake = v_stake
  WHERE match_id = p_id AND user_id = v_uid;
  PERFORM public._mark_seen_many(v_uid, (select array_agg(puzzle_id) from public.challenge_pack where match_id = p_id));
  IF m.host_id IS NOT NULL AND m.host_id <> v_uid THEN
    INSERT INTO public.friendships(user_id, friend_id) VALUES (v_uid, m.host_id), (m.host_id, v_uid) ON CONFLICT DO NOTHING;
  END IF;
  RETURN jsonb_build_object('ok',true, 'match', public.get_match(p_id));
END; $function$;

-- 5) resolve/advance: v2 banks leftover into Score + resets to next bounty ---
CREATE OR REPLACE FUNCTION public._match_resolve_and_advance(p_id uuid, p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE cp public.challenge_participants; m public.challenge_matches; v_phrase TEXT; v_won BOOLEAN;
  v_score INT; v_combo INT; v_solved INT; v_budget BIGINT; v_next_bounty INT;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF cp.state <> 'active' THEN RETURN public._match_board(p_id, p_uid); END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  v_budget := GREATEST(COALESCE(m.wager,0), 500);
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = public._match_pid(p_id, cp.position);
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(cp.revealed_positions)));
  IF NOT v_won THEN RETURN public._match_board(p_id, p_uid); END IF;
  v_solved := cp.solved + 1;
  IF m.mode = 'blitz' THEN
    v_score := round(300 * cp.combo_x100 / 100.0)::int; v_combo := LEAST(300, cp.combo_x100 + 25);
    IF cp.position >= m.pack_size THEN
      UPDATE public.challenge_participants SET total_score = total_score + v_score, last_score = v_score,
        combo_x100 = v_combo, solved = v_solved, state = 'done', joined_at = COALESCE(joined_at, now())
      WHERE match_id = p_id AND user_id = p_uid;
      PERFORM public._match_maybe_settle(p_id);
    ELSE
      UPDATE public.challenge_participants SET total_score = total_score + v_score, last_score = v_score, position = position + 1,
        solved = v_solved, bankroll = v_budget, revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
        p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0, combo_x100 = v_combo WHERE match_id = p_id AND user_id = p_uid;
    END IF;
    RETURN public._match_board(p_id, p_uid);
  END IF;

  IF m.econ_v = 2 THEN
    -- NEW: bank this puzzle's leftover (cp.bankroll) into the accumulating Score,
    -- then reset bankroll to the NEXT puzzle's bounty (start_budget tracks granted).
    IF cp.position >= m.pack_size THEN
      UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
        total_score = total_score + cp.bankroll, state = 'done', joined_at = COALESCE(joined_at, now())
      WHERE match_id = p_id AND user_id = p_uid;
      PERFORM public._match_maybe_settle(p_id);
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
      total_score = cp.bankroll, state = 'done', joined_at = COALESCE(joined_at, now())
    WHERE match_id = p_id AND user_id = p_uid;
    PERFORM public._match_maybe_settle(p_id);
  ELSE
    UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
      total_score = cp.bankroll, position = position + 1,
      revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}', p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
    WHERE match_id = p_id AND user_id = p_uid;
  END IF;
  RETURN public._match_board(p_id, p_uid);
END; $function$;

-- 6) settle: v2 pot from WAGER stakes; spent = granted−score; else unchanged --
CREATE OR REPLACE FUNCTION public._match_settle(p_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $function$
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

  for r in select cp.user_id, cp.solved, cp.bankroll, cp.total_score, cp.stake, coalesce(cp.start_budget, v_budget) as budget,
                  rank() over (order by cp.total_score desc) as rk,
                  count(*) filter (where true) over (partition by cp.total_score) as tied
           from public.challenge_participants cp where cp.match_id = p_id and cp.state = 'done' loop
    if v_refunded then
      perform public._notify(r.user_id, 'challenge_result', 'Challenge tied',
        'No one solved it — ' || (case when m.wager>0 then 'ante refunded.' else 'no winner.' end),
        jsonb_build_object('match_id', p_id, 'tie', true, 'route','challenge'));
    elsif coalesce((v_winnings->>r.user_id::text)::bigint,0) > 0 then
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

-- 7) _match_board: v2 reports the CURRENT puzzle's bounty as the budget, so
--    spent = bounty − bankroll is per-puzzle (not the cumulative granted total).
--    total_score (the accumulating Score) is already in the payload.
CREATE OR REPLACE FUNCTION public._match_board(p_id uuid, p_uid uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE cp public.challenge_participants; m public.challenge_matches; v_pid UUID; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_clue TEXT; v_board JSONB; v_minfo JSONB; v_budget BIGINT; v_default_budget BIGINT;
  v_standing JSONB := NULL; v_field INT; v_finished INT; v_my_spent BIGINT; v_best_spent BIGINT; v_best_total BIGINT; v_ahead INT; v_state TEXT; v_rank INT;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  v_default_budget := GREATEST(COALESCE(m.wager,0), 500);
  v_budget := CASE WHEN m.econ_v = 2 THEN public._match_pos_bounty(p_id, cp.position)
                   ELSE COALESCE(cp.start_budget, v_default_budget) END;  -- MY per-puzzle budget
  v_minfo := jsonb_build_object('pack_size', m.pack_size, 'mode', m.mode, 'total_score', cp.total_score,
    'last_score', cp.last_score, 'position', cp.position, 'done', cp.state = 'done', 'status', m.status,
    'solved', cp.solved, 'spent', GREATEST(0, v_budget - cp.bankroll), 'budget', v_budget, 'wager', m.wager,
    'items_allowed', COALESCE(m.items_allowed,false), 'used_powerups', to_jsonb(cp.active_powerups),
    'my_debuffs', to_jsonb(COALESCE(cp.debuffs,'{}')),
    'opponents', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', o.user_id, 'name', public._display_name(o.user_id)) ORDER BY o.joined_at NULLS LAST), '[]'::jsonb)
      FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state IN ('active','invited')));
  IF m.mode = 'blitz' THEN
    v_minfo := v_minfo || jsonb_build_object('started_at', cp.started_at, 'clock_seconds', m.pack_size * 30, 'combo', cp.combo_x100);
  END IF;
  IF cp.state = 'done' THEN RETURN jsonb_build_object('match', v_minfo); END IF;

  IF m.status = 'open' AND m.mode <> 'blitz' THEN
    SELECT count(*) INTO v_field FROM public.challenge_participants WHERE match_id = p_id;
    SELECT count(*) INTO v_finished FROM public.challenge_participants WHERE match_id = p_id AND user_id <> p_uid AND state = 'done';
    IF m.pack_size = 1 THEN
      v_my_spent := GREATEST(0, v_budget - cp.bankroll);
      SELECT min(GREATEST(0, (CASE WHEN m.econ_v = 2 THEN public._match_pos_bounty(p_id, o.position) ELSE COALESCE(o.start_budget, v_default_budget) END) - o.bankroll)) INTO v_best_spent
        FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state = 'done' AND o.solved >= 1;
      SELECT count(*) INTO v_ahead
        FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state = 'done' AND o.solved >= 1
          AND GREATEST(0, (CASE WHEN m.econ_v = 2 THEN public._match_pos_bounty(p_id, o.position) ELSE COALESCE(o.start_budget, v_default_budget) END) - o.bankroll) < v_my_spent;
      IF v_finished = 0 THEN v_state := 'first_to_play'; v_rank := 1;
      ELSIF v_best_spent IS NULL THEN v_state := 'lead'; v_rank := 1;
      ELSIF v_my_spent < v_best_spent THEN v_state := 'lead'; v_rank := 1;
      ELSIF v_my_spent = v_best_spent THEN v_state := 'tied'; v_rank := v_ahead + 1;
      ELSE v_state := 'behind'; v_rank := v_ahead + 1;
      END IF;
      v_standing := jsonb_build_object('field_size', v_field, 'finished', v_finished, 'rank', v_rank, 'state', v_state);
    ELSE
      SELECT max(o.total_score) INTO v_best_total
        FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state = 'done';
      SELECT count(*) INTO v_ahead
        FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state = 'done' AND o.total_score > cp.total_score;
      IF v_finished = 0 THEN v_state := 'first_to_play'; v_rank := 1;
      ELSIF cp.total_score > v_best_total THEN v_state := 'lead'; v_rank := 1;
      ELSIF cp.total_score = v_best_total THEN v_state := 'tied'; v_rank := v_ahead + 1;
      ELSE v_state := 'behind'; v_rank := v_ahead + 1;
      END IF;
      v_standing := jsonb_build_object('field_size', v_field, 'finished', v_finished, 'rank', v_rank, 'state', v_state, 'provisional', true);
    END IF;
  END IF;

  v_pid := public._match_pid(p_id, cp.position);
  SELECT upper(phrase), category, COALESCE(subcategory,''), clue INTO v_phrase, v_cat, v_sub, v_clue FROM public.daily_puzzles WHERE id = v_pid;
  v_board := public._daily_board(v_phrase, 'active', cp.bankroll, cp.guesses_remaining, cp.revealed_positions, cp.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('match', v_minfo, 'standing', v_standing,
    'clue', CASE WHEN 'fog' = ANY(COALESCE(cp.debuffs,'{}')) THEN NULL ELSE v_clue END);
END; $function$;

COMMIT;
