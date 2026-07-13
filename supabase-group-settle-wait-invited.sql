-- Fix: group/async matches early-settled while members were still 'invited'
-- (not yet accepted), locking them out. Only early-settle when nobody is still
-- playing (active) AND nobody is still pending an invite. Stragglers who never
-- accept are force-settled at settles_at by the settle_expired_matches cron.
create or replace function public._match_maybe_settle(p_id uuid)
returns void
language plpgsql
security definer
as $function$
begin
  if not exists (
       select 1 from public.challenge_participants
       where match_id = p_id and state in ('active', 'invited')
     )
     and (
       select count(*) from public.challenge_participants
       where match_id = p_id and state = 'done'
     ) >= 2
  then
    perform public._match_settle(p_id);
  end if;
end;
$function$;
