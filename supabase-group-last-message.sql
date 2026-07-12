-- ============================================================================
-- #27: group chat had no unread indicator on the group list — you had to open each group
-- to discover new messages. Expose the group's latest message timestamp so the client can
-- show an unread dot (compared against a per-group last-seen it tracks locally).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_groups()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'join_code', g.join_code,
    'members', (SELECT count(*) FROM public.group_members gm2 WHERE gm2.group_id = g.id),
    'is_owner', g.owner_id = v_uid,
    'last_message_at', (SELECT max(created_at) FROM public.group_messages gmsg WHERE gmsg.group_id = g.id),
    'added_at', (SELECT gm3.joined_at FROM public.group_members gm3
                 WHERE gm3.group_id = g.id AND gm3.user_id = v_uid)) ORDER BY g.created_at), '[]'::jsonb)
  INTO v_rows FROM public.groups g
  WHERE EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = g.id AND gm.user_id = v_uid);
  RETURN v_rows;
END; $function$;

COMMIT;
