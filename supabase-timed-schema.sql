-- Timed challenges (Batch 2, Task 7): clock config columns + create_match/match_start wiring.
-- Per docs/superpowers/specs/2026-07-17-timed-challenges.md
-- Dump-transform-apply. create_match gains 3 trailing params -> DROP+CREATE (new signature).
-- match_start keeps its signature -> CREATE OR REPLACE. Task-2 payout logic preserved byte-for-byte.

BEGIN;

-- 1) Match-level clock config.
ALTER TABLE public.challenge_matches
  ADD COLUMN IF NOT EXISTS clock_mode text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS clock_seconds int,
  ADD COLUMN IF NOT EXISTS time_scores boolean NOT NULL DEFAULT false;

-- 2) Per-participant current-puzzle open time (per-puzzle clock anchor).
ALTER TABLE public.challenge_participants
  ADD COLUMN IF NOT EXISTS puzzle_started_at timestamptz;

-- 3) create_match: add p_clock_mode/p_clock_seconds/p_time_scores (trailing, defaulted),
--    normalize, and store on the inserted match. Everything else byte-identical to live.
DROP FUNCTION IF EXISTS public.create_match(text, uuid, text[], integer, bigint, text, text, integer, boolean);

CREATE OR REPLACE FUNCTION public.create_match(p_opponent text, p_group_id uuid, p_categories text[], p_pack_size integer, p_wager bigint, p_mode text, p_payout text, p_window_seconds integer, p_items_allowed boolean, p_clock_mode text DEFAULT 'none', p_clock_seconds integer DEFAULT NULL, p_time_scores boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_uid uuid := auth.uid(); v_id uuid; v_opp uuid; v_size int; v_wager bigint; v_mode text; v_payout text;
  v_n int; v_budget bigint; v_cash bigint; v_uids uuid[]; r record;
  v_clock_mode text; v_clock_seconds int; v_time_scores boolean;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'reason','auth'); end if;
  v_size := least(greatest(coalesce(p_pack_size,1),1),10);
  v_wager := greatest(coalesce(p_wager,0),0);
  if v_wager > 0 and v_wager < 500 then return jsonb_build_object('ok',false,'reason','min_wager'); end if;
  v_mode := 'standard';  -- Blitz retired; all matches are standard
  -- Clock config: only 'puzzle'|'match' are live clocks; anything else is 'none' (no limit).
  v_clock_mode := case when p_clock_mode in ('puzzle','match') then p_clock_mode else 'none' end;
  v_clock_seconds := case when v_clock_mode = 'none' then null
                          else nullif(greatest(coalesce(p_clock_seconds,0),0),0) end;
  if v_clock_seconds is null then v_clock_mode := 'none'; end if;
  v_time_scores := (v_clock_mode <> 'none') and coalesce(p_time_scores,false);
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
  insert into public.challenge_matches(host_id, group_id, mode, categories, pack_size, wager, payout, settles_at, items_allowed, econ_v, clock_mode, clock_seconds, time_scores)
  values (v_uid, p_group_id, v_mode, coalesce(p_categories,'{}'), v_size, v_wager, v_payout, now() + (least(greatest(coalesce(p_window_seconds,172800),3600),604800) || ' seconds')::interval, coalesce(p_items_allowed,false), 2, v_clock_mode, v_clock_seconds, v_time_scores)
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

-- 4) match_start: stamp puzzle_started_at (per-puzzle clock anchor) alongside started_at.
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
  UPDATE public.challenge_participants SET started_at = COALESCE(started_at, now()), puzzle_started_at = COALESCE(puzzle_started_at, now()) WHERE match_id = p_id AND user_id = v_uid;
  RETURN public._match_board(p_id, v_uid);
END; $function$;

-- Refresh PostgREST schema cache (create_match signature changed).
NOTIFY pgrst, 'reload schema';

COMMIT;
