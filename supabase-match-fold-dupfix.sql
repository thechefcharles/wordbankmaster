-- Critical fix: match_fold crashed on a final-puzzle fold.
-- Both state='done' branches had a duplicate column assignment
-- `finished_at = now(), finished_at = now()`, which Postgres rejects at execute time with
-- ERROR: multiple assignments to same column "finished_at" — so folding on the LAST puzzle of a
-- match errored in production. Predates our work (from the match-timing PR) but lives in the
-- function Task 3 edited and Task 5's broke-fold will reuse this path. Dumped the live body and
-- removed the SECOND `finished_at = now(),` in both done branches; everything else (incl. the
-- Task-3 reveal_order='{}' additions) is byte-identical.
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
            reveal_order = '{}',
            finished_at = now(), joined_at = coalesce(joined_at, now())
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
            reveal_order = '{}', sabotaged_targets = '{}',
            fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false,
            p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
        where match_id = p_id and user_id = v_uid;
    end if;
    return public._match_board(p_id, v_uid);
  end if;

  -- OLD (econ_v NULL): rank by Cash left; single carried budget, total_score = leftover.
  if cp.position >= m.pack_size then
    update public.challenge_participants
      set state = 'done', bankroll = v_left, last_score = 0, total_score = v_left,
          reveal_order = '{}',
          finished_at = now(), joined_at = coalesce(joined_at, now())
      where match_id = p_id and user_id = v_uid;
    perform public._match_maybe_settle(p_id);
  else
    update public.challenge_participants
      set position = position + 1, bankroll = v_left, last_score = 0, total_score = v_left,
          revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
          reveal_order = '{}', sabotaged_targets = '{}',
          fog_buys_left = CASE WHEN pending_fog THEN 3 ELSE 0 END, pending_fog = false,
          p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
      where match_id = p_id and user_id = v_uid;
  end if;
  return public._match_board(p_id, v_uid);
end; $function$;
