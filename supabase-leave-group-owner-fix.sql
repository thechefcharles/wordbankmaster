-- ============================================================================
-- Fix: leave_group deleted the caller's membership (and the group if now empty) but never
-- reassigned groups.owner_id. When the OWNER left a group that still had members, owner_id
-- kept pointing at the departed non-member, and every management RPC (rename_group,
-- remove_group_member, respond_join_request) gates on owner_id = uid — so the remaining
-- members were permanently locked out of admin. Now: on owner-leave with members
-- remaining, hand ownership to the oldest remaining member.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.leave_group(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_owner UUID; v_new_owner UUID;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT owner_id INTO v_owner FROM public.groups WHERE id = p_id;
  DELETE FROM public.group_members WHERE group_id = p_id AND user_id = v_uid;
  -- If the group is now empty, remove it entirely.
  DELETE FROM public.groups g WHERE g.id = p_id AND NOT EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = g.id);
  -- If the owner left but members remain, hand ownership to the oldest remaining member.
  IF v_owner = v_uid THEN
    SELECT user_id INTO v_new_owner FROM public.group_members
      WHERE group_id = p_id ORDER BY joined_at ASC, user_id ASC LIMIT 1;
    IF v_new_owner IS NOT NULL THEN
      UPDATE public.groups SET owner_id = v_new_owner WHERE id = p_id;
    END IF;
  END IF;
  RETURN jsonb_build_object('ok',true);
END; $function$;

COMMIT;
