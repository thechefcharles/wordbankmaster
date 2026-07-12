-- ============================================================================
-- #21: join-request approval was only reachable via a transient notification
-- (respond_join_request called only from NotificationsPanel). If the owner missed/cleared
-- it, the request in group_join_requests was orphaned with no UI to act on. get_group now
-- returns the pending requests (owner view only) so GroupsPanel can render them.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_group(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_uid uuid := auth.uid(); g public.groups; v_members jsonb; v_requests jsonb;
begin
  if v_uid is null then return null; end if;
  select * into g from public.groups where id = p_id;
  if not found or not exists (select 1 from public.group_members where group_id = p_id and user_id = v_uid) then return null; end if;
  with m as (
    select gm.user_id as id, pr.username as username, coalesce(pr.bank,0) as net_worth, coalesce(pr.bank,0) as cash,
           ct.value as title, cc.value as color, (pr.id = g.owner_id) as is_owner
    from public.group_members gm
    join public.profiles pr on pr.id = gm.user_id
    left join public.cosmetics ct on ct.id = pr.equipped_title
    left join public.cosmetics cc on cc.id = pr.equipped_color
    where gm.group_id = p_id
  ),
  ranked as (select *, row_number() over (order by net_worth desc, cash desc) as rank from m)
  select jsonb_agg(jsonb_build_object('rank', rank, 'name', public._display_name(id), 'username', username,
    'net_worth', net_worth, 'cash', cash, 'title', title, 'color', color, 'is_me', id = v_uid, 'is_owner', is_owner) order by rank)
  into v_members from ranked;

  -- Pending join requests — owner view only.
  if g.owner_id = v_uid then
    select jsonb_agg(jsonb_build_object('requester_id', r.requester_id,
             'name', public._display_name(r.requester_id), 'username', pr.username) order by r.created_at)
    into v_requests
    from public.group_join_requests r join public.profiles pr on pr.id = r.requester_id
    where r.group_id = p_id;
  end if;

  return jsonb_build_object('id', g.id, 'name', g.name, 'is_owner', g.owner_id = v_uid,
    'members', coalesce(v_members,'[]'::jsonb), 'requests', coalesce(v_requests, '[]'::jsonb));
end; $function$;

COMMIT;
