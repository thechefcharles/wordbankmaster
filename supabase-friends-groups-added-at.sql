-- Expose when a friend/group was added so the client can offer an "A–Z / Recently added" sort.
-- list_friends → added_at = friendships.created_at; get_my_groups → added_at = my joined_at.

CREATE OR REPLACE FUNCTION public.list_friends()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
declare v_uid uuid := auth.uid(); v_rows jsonb;
begin
  if v_uid is null then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', pr.id, 'username', pr.username, 'name', public._display_name(pr.id),
           'added_at', f.created_at)
           order by lower(public._display_name(pr.id))), '[]'::jsonb) into v_rows
  from public.friendships f join public.profiles pr on pr.id = f.friend_id
  where f.user_id = v_uid;
  return v_rows;
end; $function$;

CREATE OR REPLACE FUNCTION public.get_my_groups()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'join_code', g.join_code,
    'members', (SELECT count(*) FROM public.group_members gm2 WHERE gm2.group_id = g.id),
    'is_owner', g.owner_id = v_uid,
    'added_at', (SELECT gm3.joined_at FROM public.group_members gm3
                 WHERE gm3.group_id = g.id AND gm3.user_id = v_uid)) ORDER BY g.created_at), '[]'::jsonb)
  INTO v_rows FROM public.groups g
  WHERE EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = g.id AND gm.user_id = v_uid);
  RETURN v_rows;
END; $function$;
