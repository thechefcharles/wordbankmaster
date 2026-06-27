-- Dismiss (delete) a single notification for the caller.
CREATE OR REPLACE FUNCTION public.dismiss_notification(p_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
  DELETE FROM public.notifications WHERE id = p_id AND user_id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.dismiss_notification(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.dismiss_notification(uuid) TO authenticated;
