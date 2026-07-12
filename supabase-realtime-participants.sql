-- ============================================================================
-- #13 live sabotage/standing refresh: add challenge_participants to the Supabase realtime
-- publication so the client's postgres_changes UPDATE subscription fires. match_sabotage
-- writes the debuff onto the VICTIM's own row, which RLS (cp_self: user_id = auth.uid())
-- lets the victim receive live → the debuff banner shows instantly (before they overpay).
-- PK includes match_id, so REPLICA IDENTITY DEFAULT is sufficient for the match_id filter.
-- ============================================================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.challenge_participants;
