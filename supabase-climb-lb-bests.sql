-- Cash Game leaderboard: replace the transient "furthest rung" (current-run
-- climb_state.position, which resets each run) with persistent personal bests.
-- Ranks by best single-run profit; returns best run, best run streak, best heat.
create or replace function public.get_climb_leaderboard(p_scope text default 'friends', p_group uuid default null)
returns jsonb
language plpgsql
security definer
as $function$
declare v_uid uuid := auth.uid(); v_rows jsonb;
begin
  if v_uid is null then return '[]'::jsonb; end if;
  with pool as (
    select p.id as id,
           coalesce(p.cg_best_run, 0)            as best_run,
           coalesce(p.cg_best_run_streak, 0)     as best_streak,
           coalesce(p.cg_best_multiple_x100, 0)  as best_heat
    from public.profiles p
    where coalesce(p.cg_best_run, 0) > 0
      and (p_scope = 'global' or p.id = v_uid
        or (p_scope = 'friends' and p.id in (select friend_id from public.friendships where user_id = v_uid))
        or (p_scope = 'group' and p.id in (select user_id from public.group_members where group_id = p_group)))
  ),
  ranked as (
    select *, row_number() over (order by best_run desc, best_streak desc) as rank
    from pool order by best_run desc, best_streak desc limit 50
  )
  select jsonb_agg(jsonb_build_object(
    'rank', rank, 'name', public._display_name(id),
    'best_run', best_run, 'best_streak', best_streak, 'best_heat', best_heat,
    'is_me', id = v_uid) order by rank) into v_rows from ranked;
  return coalesce(v_rows, '[]'::jsonb);
end;
$function$;
