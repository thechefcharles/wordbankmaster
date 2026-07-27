BEGIN;
-- ============================================================================
-- UGC moderation (App Store Guideline 1.2): report + block + profanity filter
-- Idempotent. Applies to production only.
-- ============================================================================

-- ---- Tables -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.blocked_users (
  blocker_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id)
);
ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.content_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reported_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  context text NOT NULL,        -- 'match_message' | 'group_message' | 'user' | 'username'
  ref_id uuid,                  -- message id, or reported profile id
  reason text,
  snapshot text,                -- message body / username captured at report time
  status text NOT NULL DEFAULT 'open',   -- 'open' | 'actioned' | 'dismissed'
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.content_reports ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_content_reports_open ON public.content_reports (status, created_at DESC);

-- RLS on, zero policies: only SECURITY DEFINER functions below may touch these.
REVOKE ALL ON public.blocked_users   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.content_reports FROM PUBLIC, anon, authenticated;

-- ---- Profanity filter (targeted; avoids the Scunthorpe problem) -------------
-- Slurs: matched as substrings on the de-punctuated text (evasion-resistant) because
-- they virtually never occur inside innocent English words.
-- Profanity: whole-word in chat (so "class"/"assassin"/"Scunthorpe"/"Pakistan" pass),
-- but substring inside usernames (single tokens) when p_strict is true.
CREATE OR REPLACE FUNCTION public._is_profane(p_text text, p_strict boolean DEFAULT false)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE
AS $function$
DECLARE
  v_low text; v_squish text; w text;
  -- Slurs + hard profanity that virtually never occur inside innocent words:
  -- matched as substrings on de-punctuated text (catches f.u.c.k / n i g g e r evasion) in BOTH modes.
  hard text[] := ARRAY[
    'nigger','nigga','faggot','chink','kike','wetback','tranny','beaner','shemale',
    'fuck','shit','bitch','asshole','pussy','motherfucker','bastard','bollocks','wank'
  ];
  -- False-positive-prone (cockpit, Pakistan, raccoon, Scunthorpe, despicable, who're...):
  -- whole-word only in chat; substring inside usernames (single tokens) when strict.
  soft text[] := ARRAY[
    'cock','fag','spic','paki','coon','gook','dick','dyke','cunt','slut','whore',
    'goddamn','retard','retarded'
  ];
BEGIN
  v_low := lower(coalesce(p_text,''));
  v_squish := regexp_replace(v_low, '[^a-z]', '', 'g');
  IF v_squish = '' THEN RETURN false; END IF;
  FOREACH w IN ARRAY hard LOOP
    IF v_squish LIKE '%'||w||'%' THEN RETURN true; END IF;
  END LOOP;
  IF p_strict THEN
    FOREACH w IN ARRAY soft LOOP
      IF v_squish LIKE '%'||w||'%' THEN RETURN true; END IF;
    END LOOP;
  ELSE
    FOREACH w IN ARRAY soft LOOP
      IF v_low ~ ('(^|[^a-z])'||w||'([^a-z]|$)') THEN RETURN true; END IF;
    END LOOP;
  END IF;
  RETURN false;
END; $function$;

-- ---- Block / unblock / list -------------------------------------------------
CREATE OR REPLACE FUNCTION public.block_user(p_username text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid uuid := auth.uid(); v_target uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT id INTO v_target FROM public.profiles WHERE lower(username)=lower(trim(coalesce(p_username,'')));
  IF v_target IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_found'); END IF;
  IF v_target = v_uid THEN RETURN jsonb_build_object('ok',false,'reason','self'); END IF;
  INSERT INTO public.blocked_users(blocker_id, blocked_id) VALUES (v_uid, v_target) ON CONFLICT DO NOTHING;
  -- Full no-contact: sever friendship + pending requests both ways.
  DELETE FROM public.friendships     WHERE (user_id=v_uid AND friend_id=v_target) OR (user_id=v_target AND friend_id=v_uid);
  DELETE FROM public.friend_requests WHERE (requester=v_uid AND addressee=v_target) OR (requester=v_target AND addressee=v_uid);
  DELETE FROM public.notifications   WHERE user_id=v_uid AND type='friend_request' AND (data->>'from_id')=v_target::text;
  RETURN jsonb_build_object('ok',true);
END; $function$;

CREATE OR REPLACE FUNCTION public.unblock_user(p_username text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid uuid := auth.uid(); v_target uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT id INTO v_target FROM public.profiles WHERE lower(username)=lower(trim(coalesce(p_username,'')));
  IF v_target IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_found'); END IF;
  DELETE FROM public.blocked_users WHERE blocker_id=v_uid AND blocked_id=v_target;
  RETURN jsonb_build_object('ok',true);
END; $function$;

CREATE OR REPLACE FUNCTION public.list_blocked()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid uuid := auth.uid(); v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'username', p.username,
           'name', public._display_name(b.blocked_id),
           'at', b.created_at) ORDER BY b.created_at DESC), '[]'::jsonb)
  INTO v_rows
  FROM public.blocked_users b JOIN public.profiles p ON p.id = b.blocked_id
  WHERE b.blocker_id = v_uid;
  RETURN v_rows;
END; $function$;

CREATE OR REPLACE FUNCTION public.is_blocking(p_username text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $function$
  SELECT EXISTS(
    SELECT 1 FROM public.blocked_users b JOIN public.profiles p ON p.id=b.blocked_id
    WHERE b.blocker_id = auth.uid()
      AND lower(p.username) = lower(trim(coalesce(p_username,''))));
$function$;

-- ---- Report -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.report_content(p_context text, p_ref_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_owner constant uuid := '8f41d897-1097-4a70-b857-30f91af42570';  -- Chefcharles (owner inbox)
  v_reported uuid; v_snap text; v_ctx text; v_reason text; v_nil constant uuid := '00000000-0000-0000-0000-000000000000';
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  v_ctx := lower(coalesce(p_context,''));
  IF v_ctx NOT IN ('match_message','group_message','user','username') THEN
    RETURN jsonb_build_object('ok',false,'reason','bad_context'); END IF;
  v_reason := left(trim(coalesce(p_reason,'')), 300);
  IF v_ctx = 'match_message' THEN
    SELECT user_id, body INTO v_reported, v_snap FROM public.match_messages WHERE id = p_ref_id;
  ELSIF v_ctx = 'group_message' THEN
    SELECT user_id, body INTO v_reported, v_snap FROM public.group_messages WHERE id = p_ref_id;
  ELSE
    SELECT id, username INTO v_reported, v_snap FROM public.profiles WHERE id = p_ref_id;
  END IF;
  IF v_reported IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_found'); END IF;
  IF v_reported = v_uid THEN RETURN jsonb_build_object('ok',false,'reason','self'); END IF;
  IF EXISTS (SELECT 1 FROM public.content_reports
             WHERE reporter_id=v_uid AND reported_user_id=v_reported AND status='open'
               AND coalesce(ref_id,v_nil) = coalesce(p_ref_id,v_nil)) THEN
    RETURN jsonb_build_object('ok',true,'dup',true);
  END IF;
  INSERT INTO public.content_reports(reporter_id, reported_user_id, context, ref_id, reason, snapshot)
  VALUES (v_uid, v_reported, v_ctx, p_ref_id, v_reason, left(coalesce(v_snap,''),500));
  PERFORM public._notify(v_owner, 'report', 'Content reported',
    public._display_name(v_uid) || ' reported ' || coalesce(public._display_name(v_reported),'a user') ||
      case when v_reason <> '' then ' — ' || v_reason else '' end,
    jsonb_build_object('context', v_ctx, 'ref_id', p_ref_id, 'reported_id', v_reported::text));
  RETURN jsonb_build_object('ok',true);
END; $function$;


-- ---- Patched existing RPCs (guards injected; bodies otherwise unchanged) ----
CREATE OR REPLACE FUNCTION public.set_username(p_username text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_name TEXT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  v_name := trim(COALESCE(p_username,''));
  IF v_name !~ '^[A-Za-z0-9_]{3,15}$' THEN RETURN jsonb_build_object('ok',false,'reason','invalid'); END IF;
  IF lower(v_name) IN ('player','admin','wordbank','me','you','null','undefined') THEN
    RETURN jsonb_build_object('ok',false,'reason','reserved'); END IF;
  IF public._is_profane(v_name, true) THEN
    RETURN jsonb_build_object('ok',false,'reason','inappropriate'); END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = lower(v_name) AND id <> v_uid) THEN
    RETURN jsonb_build_object('ok',false,'reason','taken'); END IF;
  INSERT INTO public.profiles(id) VALUES (v_uid) ON CONFLICT (id) DO NOTHING;
  UPDATE public.profiles SET username = v_name WHERE id = v_uid;
  RETURN jsonb_build_object('ok',true,'username',v_name);
END; $function$;

CREATE OR REPLACE FUNCTION public.send_group_message(p_group_id uuid, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_body TEXT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.group_members WHERE group_id = p_group_id AND user_id = v_uid) THEN
    RETURN jsonb_build_object('ok',false,'reason','not_member'); END IF;
  v_body := left(trim(COALESCE(p_body,'')), 500);
  IF v_body = '' THEN RETURN jsonb_build_object('ok',false,'reason','empty'); END IF;
  IF public._is_profane(v_body, false) THEN RETURN jsonb_build_object('ok',false,'reason','inappropriate'); END IF;
  INSERT INTO public.group_messages(group_id, user_id, body) VALUES (p_group_id, v_uid, v_body);
  RETURN jsonb_build_object('ok',true);
END; $function$;

CREATE OR REPLACE FUNCTION public.send_match_message(p_match_id uuid, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_body TEXT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.challenge_participants WHERE match_id = p_match_id AND user_id = v_uid) THEN
    RETURN jsonb_build_object('ok',false,'reason','not_participant'); END IF;
  v_body := left(trim(COALESCE(p_body,'')), 500);
  IF v_body = '' THEN RETURN jsonb_build_object('ok',false,'reason','empty'); END IF;
  IF public._is_profane(v_body, false) THEN RETURN jsonb_build_object('ok',false,'reason','inappropriate'); END IF;
  INSERT INTO public.match_messages(match_id, user_id, body) VALUES (p_match_id, v_uid, v_body);
  RETURN jsonb_build_object('ok',true);
END; $function$;

CREATE OR REPLACE FUNCTION public.get_group_messages(p_group_id uuid, p_limit integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.group_members WHERE group_id = p_group_id AND user_id = v_uid) THEN
    RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.nm, 'username', t.uname, 'is_me', t.me, 'body', t.body, 'at', t.created_at) ORDER BY t.created_at), '[]'::jsonb)
  INTO v_rows FROM (
    SELECT gm.id, public._display_name(gm.user_id) AS nm, (SELECT username FROM public.profiles WHERE id = gm.user_id) AS uname, (gm.user_id = v_uid) AS me, gm.body, gm.created_at
    FROM public.group_messages gm WHERE gm.group_id = p_group_id
      AND gm.user_id NOT IN (SELECT blocked_id FROM public.blocked_users WHERE blocker_id = v_uid)
    ORDER BY gm.created_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,60),1),100)
  ) t;
  RETURN v_rows;
END; $function$;

CREATE OR REPLACE FUNCTION public.get_match_messages(p_match_id uuid, p_limit integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.challenge_participants WHERE match_id = p_match_id AND user_id = v_uid) THEN
    RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.nm, 'username', t.uname, 'is_me', t.me, 'body', t.body, 'at', t.created_at) ORDER BY t.created_at), '[]'::jsonb)
  INTO v_rows FROM (
    SELECT mm.id, public._display_name(mm.user_id) AS nm, (SELECT username FROM public.profiles WHERE id = mm.user_id) AS uname, (mm.user_id = v_uid) AS me, mm.body, mm.created_at
    FROM public.match_messages mm WHERE mm.match_id = p_match_id
      AND mm.user_id NOT IN (SELECT blocked_id FROM public.blocked_users WHERE blocker_id = v_uid)
    ORDER BY mm.created_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,60),1),100)
  ) t;
  RETURN v_rows;
END; $function$;

CREATE OR REPLACE FUNCTION public.add_friend(p_username text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_uid uuid := auth.uid(); v_friend uuid; v_myname text; v_myuname text;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'reason','auth'); end if;
  select username into v_myuname from public.profiles where id = v_uid;
  if v_myuname is null then return jsonb_build_object('ok',false,'reason','need_username'); end if;
  if trim(coalesce(p_username,'')) = '' then return jsonb_build_object('ok',false,'reason','empty'); end if;
  select id into v_friend from public.profiles where lower(username)=lower(trim(p_username));
  if v_friend is null then return jsonb_build_object('ok',false,'reason','not_found'); end if;
  if v_friend = v_uid then return jsonb_build_object('ok',false,'reason','self'); end if;
  if exists(select 1 from public.blocked_users where (blocker_id=v_uid and blocked_id=v_friend) or (blocker_id=v_friend and blocked_id=v_uid)) then
    return jsonb_build_object('ok',false,'reason','blocked'); end if;
  if exists(select 1 from public.friendships where user_id=v_uid and friend_id=v_friend) then
    return jsonb_build_object('ok',false,'reason','already_friends');
  end if;
  v_myname := public._display_name(v_uid);
  if exists(select 1 from public.friend_requests where requester=v_friend and addressee=v_uid) then
    delete from public.friend_requests where (requester=v_friend and addressee=v_uid) or (requester=v_uid and addressee=v_friend);
    delete from public.notifications where user_id = v_uid and type='friend_request' and (data->>'from_id') = v_friend::text;
    insert into public.friendships(user_id,friend_id) values (v_uid,v_friend),(v_friend,v_uid) on conflict do nothing;
    perform public._notify(v_friend, 'friend_accepted', '🤝 Friend request accepted',
      v_myname || ' accepted your friend request', jsonb_build_object('route','friends'));
    return jsonb_build_object('ok',true,'status','friends','friend_name',public._display_name(v_friend));
  end if;
  if exists(select 1 from public.friend_requests where requester=v_uid and addressee=v_friend) then
    return jsonb_build_object('ok',true,'status','requested','friend_name',public._display_name(v_friend));
  end if;
  insert into public.friend_requests(requester,addressee) values (v_uid,v_friend);
  perform public._notify(v_friend, 'friend_request', '👋 New friend request',
    v_myname || ' wants to be friends',
    jsonb_build_object('route','friends','friend_request',true,'from_id',v_uid::text,'from_username',v_myuname));
  return jsonb_build_object('ok',true,'status','requested','friend_name',public._display_name(v_friend));
end; $function$;

CREATE OR REPLACE FUNCTION public.request_join_group(p_group uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); v_owner uuid; v_name text; v_gname text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT owner_id, name INTO v_owner, v_gname FROM public.groups WHERE id = p_group;
  IF v_owner IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','no_group'); END IF;
  IF EXISTS (SELECT 1 FROM public.group_members WHERE group_id=p_group AND user_id=v_uid) THEN
    RETURN jsonb_build_object('ok',false,'reason','already_member'); END IF;
  IF EXISTS (SELECT 1 FROM public.blocked_users WHERE (blocker_id=v_uid AND blocked_id=v_owner) OR (blocker_id=v_owner AND blocked_id=v_uid)) THEN
    RETURN jsonb_build_object('ok',false,'reason','blocked'); END IF;
  INSERT INTO public.group_join_requests(group_id, requester_id) VALUES (p_group, v_uid) ON CONFLICT DO NOTHING;
  v_name := public._display_name(v_uid);
  PERFORM public._notify(v_owner, 'group_join', 'Join request',
    v_name || ' wants to join ' || v_gname,
    jsonb_build_object('group_id', p_group, 'group_name', v_gname, 'from_id', v_uid, 'from_name', v_name));
  RETURN jsonb_build_object('ok',true,'status','requested');
END; $function$;

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
    if exists(select 1 from public.blocked_users where (blocker_id=v_uid and blocked_id=v_opp) or (blocker_id=v_opp and blocked_id=v_uid)) then
      return jsonb_build_object('ok',false,'reason','blocked'); end if;
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

-- ---- Grants (new functions): keep off PUBLIC/anon, allow authenticated ------
REVOKE ALL ON FUNCTION public._is_profane(text, boolean)      FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.block_user(text)                FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unblock_user(text)              FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_blocked()                  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_blocking(text)               FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_content(text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._is_profane(text, boolean)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_user(text)                TO authenticated;
GRANT EXECUTE ON FUNCTION public.unblock_user(text)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_blocked()                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_blocking(text)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_content(text, uuid, text) TO authenticated;

COMMIT;
