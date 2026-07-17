-- Realtime social layer: friend-request live flips + self-clearing notifications.
-- Adds friend_requests (and confirms notifications) to the supabase_realtime
-- publication, and ensures each has an RLS SELECT policy so a user can read
-- their own rows — Realtime only delivers rows a user is allowed to SELECT.
-- Idempotent: safe to re-run.

-- 1) friend_requests: user must be able to SELECT rows where they are the
--    requester (to see their outgoing "Pending" flip/disappear on accept) or
--    the addressee (to see incoming requests appear live). RLS is enabled on
--    the table but had no policies, so add a self-scoped SELECT policy.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'friend_requests'
      and policyname = 'friend_requests_self'
  ) then
    create policy "friend_requests_self" on public.friend_requests
      for select using (requester = auth.uid() or addressee = auth.uid());
  end if;
end $$;

-- Full replica identity so DELETE events carry the old row (requester/addressee)
-- for the RLS check + client re-derive when a request is accepted/declined.
alter table public.friend_requests replica identity full;

-- 2) Add friend_requests to the realtime publication (guard so re-running is safe).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'friend_requests'
  ) then
    alter publication supabase_realtime add table public.friend_requests;
  end if;
end $$;

-- 3) notifications: already in the publication with a self SELECT policy
--    ("notifications_self" USING user_id = auth.uid()). Guard-add both in case
--    this runs against an environment where they're missing.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'notifications'
      and policyname = 'notifications_self'
  ) then
    create policy "notifications_self" on public.notifications
      for select using (user_id = auth.uid());
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
