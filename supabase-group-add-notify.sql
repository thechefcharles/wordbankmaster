-- "Added to a group" notification (migration: group_add_notify).
-- add_group_member now _notify()s the newly-added member ("Added to a group")
-- when user A adds friend B to a group. Fires ONLY on a genuinely-new insert
-- (guarded by IF FOUND after ON CONFLICT DO NOTHING): never on a self-add (the
-- 'self' guard above already returns), never on a re-add of an existing member
-- (the 'already_member' guard + the FOUND check). Carries data.group_id (+ the
-- group_join convention: group_name/from_id/from_name) so the client can render
-- and deep-link to the group. Delivered live via the notifications realtime sub.
-- Everything else in the RPC is byte-identical to the live body.
BEGIN;
CREATE OR REPLACE FUNCTION public.add_group_member(p_group_id uuid, p_username text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_uid uuid := auth.uid(); v_target uuid; v_gname text;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'reason','auth'); end if;
  if not exists (select 1 from public.group_members where group_id = p_group_id and user_id = v_uid) then
    return jsonb_build_object('ok',false,'reason','not_member');
  end if;
  select id into v_target from public.profiles where lower(username) = lower(trim(coalesce(p_username,'')));
  if v_target is null then return jsonb_build_object('ok',false,'reason','not_found'); end if;
  if v_target = v_uid then return jsonb_build_object('ok',false,'reason','self'); end if;
  if not exists (select 1 from public.friendships where user_id = v_uid and friend_id = v_target) then
    return jsonb_build_object('ok',false,'reason','not_friend');
  end if;
  if exists (select 1 from public.group_members where group_id = p_group_id and user_id = v_target) then
    return jsonb_build_object('ok',false,'reason','already_member');
  end if;
  insert into public.group_members(group_id, user_id) values (p_group_id, v_target) on conflict do nothing;
  -- Notify the newly-added member — only a genuinely-new insert (never self, never a re-add).
  if found then
    select name into v_gname from public.groups where id = p_group_id;
    perform public._notify(v_target, 'group_added', 'Added to a group',
      public._display_name(v_uid) || ' added you to ' || coalesce(v_gname, 'a group'),
      jsonb_build_object('group_id', p_group_id, 'group_name', v_gname,
        'from_id', v_uid, 'from_name', public._display_name(v_uid), 'route', 'group'));
  end if;
  return jsonb_build_object('ok',true,'group',public.get_group(p_group_id));
end; $function$;
COMMIT;
