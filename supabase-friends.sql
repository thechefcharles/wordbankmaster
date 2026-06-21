-- ============================================================
-- Friends + friends Daily leaderboard (applied to prod).
-- Shareable 6-char friend code on profiles; symmetric friendships; a friends-only
-- Daily leaderboard (everyone plays the same Daily → rank friends by today's score).
-- Writes only via SECURITY DEFINER RPCs (tables RLS-locked).
-- Client: statsStore getMyFriendCode/addFriend/getFriendsDailyLeaderboard,
-- Friends tab in src/routes/leaderboard/+page.svelte, ?add=CODE invite link in +page.svelte.
-- ============================================================
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS friend_code TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_friend_code ON public.profiles(friend_code) WHERE friend_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.friendships (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  friend_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, friend_id)
);
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.get_my_friend_code()
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_code TEXT; v_alpha TEXT := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; i INT;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  SELECT friend_code INTO v_code FROM public.profiles WHERE id = v_uid;
  IF v_code IS NOT NULL THEN RETURN v_code; END IF;
  LOOP
    v_code := '';
    FOR i IN 1..6 LOOP v_code := v_code || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1); END LOOP;
    BEGIN
      UPDATE public.profiles SET friend_code = v_code WHERE id = v_uid;
      RETURN v_code;
    EXCEPTION WHEN unique_violation THEN /* retry */ END;
  END LOOP;
END; $$;
GRANT EXECUTE ON FUNCTION public.get_my_friend_code() TO authenticated;

CREATE OR REPLACE FUNCTION public.add_friend(p_code TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_friend UUID; v_name TEXT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'auth'); END IF;
  p_code := upper(trim(COALESCE(p_code, '')));
  IF p_code = '' THEN RETURN jsonb_build_object('ok', false, 'reason', 'empty'); END IF;
  SELECT id INTO v_friend FROM public.profiles WHERE friend_code = p_code;
  IF v_friend IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_found'); END IF;
  IF v_friend = v_uid THEN RETURN jsonb_build_object('ok', false, 'reason', 'self'); END IF;
  INSERT INTO public.friendships(user_id, friend_id) VALUES (v_uid, v_friend), (v_friend, v_uid) ON CONFLICT DO NOTHING;
  SELECT COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email','@',1), 'Player')
    INTO v_name FROM auth.users au WHERE au.id = v_friend;
  RETURN jsonb_build_object('ok', true, 'friend_name', v_name);
END; $$;
GRANT EXECUTE ON FUNCTION public.add_friend(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_friends_daily_leaderboard()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  WITH circle AS (
    SELECT v_uid AS id UNION SELECT friend_id FROM public.friendships WHERE user_id = v_uid
  ),
  scored AS (
    SELECT c.id,
      COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.raw_user_meta_data->>'email','@',1), 'Player') AS name,
      (SELECT gr.score FROM public.game_results gr
        WHERE gr.user_id = c.id AND gr.game_mode = 'daily' AND gr.played_at::date = CURRENT_DATE
        ORDER BY gr.played_at DESC LIMIT 1) AS score,
      COALESCE(p.current_win_streak, 0) AS streak
    FROM circle c JOIN auth.users au ON au.id = c.id LEFT JOIN public.profiles p ON p.id = c.id
  ),
  ranked AS (
    SELECT *, row_number() OVER (ORDER BY (score IS NULL), score DESC NULLS LAST, name) AS rank FROM scored
  )
  SELECT jsonb_agg(jsonb_build_object('rank', rank, 'name', name, 'score', score, 'streak', streak,
    'is_me', id = v_uid, 'played', score IS NOT NULL) ORDER BY rank)
  INTO v_rows FROM ranked;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $$;
GRANT EXECUTE ON FUNCTION public.get_friends_daily_leaderboard() TO authenticated;
