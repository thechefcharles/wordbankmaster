-- ── Group join-requests (owner approval) + public-profile friends/groups ──
CREATE TABLE IF NOT EXISTS public.group_join_requests (
  group_id     uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  requester_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, requester_id)
);
ALTER TABLE public.group_join_requests ENABLE ROW LEVEL SECURITY;

-- Ask to join a group → notify the owner.
CREATE OR REPLACE FUNCTION public.request_join_group(p_group uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid uuid := auth.uid(); v_owner uuid; v_name text; v_gname text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT owner_id, name INTO v_owner, v_gname FROM public.groups WHERE id = p_group;
  IF v_owner IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','no_group'); END IF;
  IF EXISTS (SELECT 1 FROM public.group_members WHERE group_id=p_group AND user_id=v_uid) THEN
    RETURN jsonb_build_object('ok',false,'reason','already_member'); END IF;
  INSERT INTO public.group_join_requests(group_id, requester_id) VALUES (p_group, v_uid) ON CONFLICT DO NOTHING;
  v_name := public._display_name(v_uid);
  PERFORM public._notify(v_owner, 'group_join', 'Join request',
    v_name || ' wants to join ' || v_gname,
    jsonb_build_object('group_id', p_group, 'group_name', v_gname, 'from_id', v_uid, 'from_name', v_name));
  RETURN jsonb_build_object('ok',true,'status','requested');
END; $$;

-- Owner approves/declines a join request.
CREATE OR REPLACE FUNCTION public.respond_join_request(p_group uuid, p_user uuid, p_accept boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid uuid := auth.uid(); v_owner uuid; v_gname text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT owner_id, name INTO v_owner, v_gname FROM public.groups WHERE id = p_group;
  IF v_owner IS DISTINCT FROM v_uid THEN RETURN jsonb_build_object('ok',false,'reason','not_owner'); END IF;
  DELETE FROM public.group_join_requests WHERE group_id=p_group AND requester_id=p_user;
  IF p_accept THEN
    INSERT INTO public.group_members(group_id, user_id) VALUES (p_group, p_user) ON CONFLICT DO NOTHING;
    PERFORM public._notify(p_user, 'group_join_ok', 'Request approved',
      'You''re now in ' || v_gname, jsonb_build_object('group_id', p_group, 'group_name', v_gname));
  END IF;
  RETURN jsonb_build_object('ok',true);
END; $$;

REVOKE ALL ON FUNCTION public.request_join_group(uuid), public.respond_join_request(uuid,uuid,boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.request_join_group(uuid), public.respond_join_request(uuid,uuid,boolean) TO authenticated;

-- Also applied: get_public_profile now returns the target's 'friends' (username/name)
-- and 'groups' (id/name/my_status: member|requested|none), so others can see them.
