-- Manual ownership transfer (punch-list #20 follow-up).
-- Owner hands the group to an existing member. Owner-only; target must be a
-- current member. Complements the auto-transfer-on-leave in leave_group (#19).
create or replace function public.transfer_group_ownership(p_group_id uuid, p_username text)
returns jsonb
language plpgsql
security definer
as $function$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_target uuid;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'auth');
  end if;

  select owner_id into v_owner from public.groups where id = p_group_id;
  if v_owner is null then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if v_owner <> v_uid then
    return jsonb_build_object('ok', false, 'reason', 'not_owner');
  end if;

  select id into v_target
  from public.profiles
  where lower(username) = lower(trim(coalesce(p_username, '')));
  if v_target is null then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if v_target = v_uid then
    return jsonb_build_object('ok', false, 'reason', 'self');
  end if;
  if not exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = v_target
  ) then
    return jsonb_build_object('ok', false, 'reason', 'not_member');
  end if;

  update public.groups set owner_id = v_target where id = p_group_id;

  -- Let the new owner know they're in charge now.
  perform public._notify(
    v_target,
    'group_join',
    'You''re now the owner',
    'You now own the group "' || coalesce((select name from public.groups where id = p_group_id), 'a group') || '".',
    jsonb_build_object('group_id', p_group_id)
  );

  return jsonb_build_object('ok', true, 'group', public.get_group(p_group_id));
end;
$function$;

grant execute on function public.transfer_group_ownership(uuid, text) to authenticated;
