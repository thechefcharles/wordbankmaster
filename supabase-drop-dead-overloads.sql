-- ============================================================================
-- Tier 5 dead-code drops:
--  #24 accept_match(uuid) — dead 1-arg overload. The client always calls the 2-arg form
--      accept_match(uuid, boolean); the 1-arg version is unreferenced AND ambiguous with
--      the 2-arg default, and it skips _mark_seen_many.
--  #25 join_group(text) — dead join-by-code path. No client caller (joinGroup wrapper
--      removed), no DB caller; codes were generated but never shown. (The vestigial
--      groups.join_code column is left in place — harmless data, not code.)
-- ============================================================================
BEGIN;

DROP FUNCTION IF EXISTS public.accept_match(uuid);
DROP FUNCTION IF EXISTS public.join_group(text);

COMMIT;
