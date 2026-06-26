-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  delete_my_account() — in-app account deletion (App Store 5.1.1(v))     ║
-- ╚══════════════════════════════════════════════════════════════════════╝
-- Deletes the caller's auth row; nearly everything cascades (profiles,
-- game_results, sessions, badges, friendships, challenge_participants, …).
-- Two tables carry a user_id with NO cascading FK (group_messages,
-- match_messages) so we clear those explicitly first.
-- postgres has DELETE on auth.users, and this runs SECURITY DEFINER as the
-- owner — so the auth row (and its cascade) is removed in one call.

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  -- user_id columns with no cascading FK → delete the caller's rows by hand
  DELETE FROM public.group_messages WHERE user_id = v_uid;
  DELETE FROM public.match_messages WHERE user_id = v_uid;

  -- everything else cascades off the auth row
  DELETE FROM auth.users WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_account() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
