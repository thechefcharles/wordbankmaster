-- ============================================================================
-- Guarantee challenge packs are the requested size (fixes "last puzzle's receipt
-- row is missing" in group challenges).
--
-- Root cause: create_match stores pack_size = the REQUESTED size unconditionally,
-- but the actual pack from _pick_casual_pack can come up short. The shortfall isn't
-- the seen-exclusion (that's only an ORDER BY preference, not a filter) — it's the
-- hard `char_length >= p_min_len` (8) WHERE clause: a narrow category can have fewer
-- than N phrases of length >= 8, so LIMIT N returns fewer rows. Result: challenge_pack
-- has N-1 rows while pack_size = N, so standings show solved/N while the results
-- receipt's per-puzzle strip faithfully lists only the real rows — the final puzzle
-- looks "missing."
--
-- Fix (two parts):
--   1) _pick_casual_pack — demote p_min_len from a hard WHERE filter to a soft ORDER BY
--      preference: still prefer longer phrases (and less-seen, then random), but never
--      exclude short ones, so a category pool of ~34 always fills the pack.
--   2) create_match — set pack_size to the ACTUAL row count as a safety net, so even in a
--      pathological tiny-pool edge case the denominator and the puzzle strip always agree.
-- ============================================================================
BEGIN;

-- 1) Relaxed pack picker: min-length is now a preference, not a filter.
CREATE OR REPLACE FUNCTION public._pick_casual_pack(p_uids uuid[], p_categories text[] DEFAULT '{}'::text[], p_n integer DEFAULT 1, p_min_len integer DEFAULT 0)
 RETURNS SETOF uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select dp.id
  from public.daily_puzzles dp
  left join lateral (
    select count(*) as seen_cnt, max(s.last_seen) as last_seen
    from public.user_seen_puzzles s
    where s.puzzle_id = dp.id and s.user_id = any(p_uids)
  ) agg on true
  where dp.pool = 'casual'
    and (coalesce(array_length(p_categories,1),0) = 0 or dp.category = any(p_categories))
    and dp.id not in (select puzzle_id from public.daily_puzzle_schedule where scheduled_date = current_date)
  order by
    -- Prefer phrases meeting the min length, but DON'T hard-exclude short ones — a narrow
    -- category could otherwise yield fewer than p_n and short the pack.
    (case when p_min_len <= 0 or char_length(replace(dp.phrase,' ','')) >= p_min_len then 0 else 1 end) asc,
    coalesce(agg.seen_cnt,0) asc, agg.last_seen asc nulls first, random()
  limit greatest(p_n,1);
$function$;

-- Internal helper: not a client RPC.
REVOKE EXECUTE ON FUNCTION public._pick_casual_pack(uuid[], text[], integer, integer) FROM PUBLIC, anon;

-- 2) create_match: make the standings denominator authoritative (pack_size = actual rows).
CREATE OR REPLACE FUNCTION public.create_match(p_opponent text, p_group_id uuid, p_categories text[], p_pack_size integer, p_wager bigint, p_mode text, p_payout text, p_window_seconds integer, p_items_allowed boolean, p_clock_mode text DEFAULT 'none'::text, p_clock_seconds integer DEFAULT NULL::integer, p_time_scores boolean DEFAULT false)
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
  -- Safety net: make pack_size match the ACTUAL pack so standings (solved/pack_size) and the
  -- results receipt's per-puzzle strip always agree, even if the pool couldn't fill v_size.
  if v_n <> v_size then update public.challenge_matches set pack_size = v_n where id = v_id; end if;
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

-- Client RPC: authenticated users call this. (CREATE OR REPLACE preserves grants; re-assert.)
REVOKE EXECUTE ON FUNCTION public.create_match(text, uuid, text[], integer, bigint, text, text, integer, boolean, text, integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_match(text, uuid, text[], integer, bigint, text, text, integer, boolean, text, integer, boolean) TO authenticated;

COMMIT;
