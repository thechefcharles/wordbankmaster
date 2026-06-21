-- ============================================================
-- Streak overview RPC for the /streak screen (applied to prod).
-- Returns current/longest streak + freezes + last ~10 weeks of daily outcomes
-- (for the calendar heatmap). Keyed on auth.uid().
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_streak_overview()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_cur INT; v_high INT; v_fz INT; v_days JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  SELECT COALESCE(current_win_streak,0), COALESCE(highest_win_streak,0), COALESCE(streak_freezes,0)
    INTO v_cur, v_high, v_fz FROM public.profiles WHERE id = v_uid;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('d', d, 'won', won) ORDER BY d), '[]'::jsonb)
    INTO v_days
  FROM (
    SELECT gr.played_at::date AS d, bool_or(gr.won) AS won
    FROM public.game_results gr
    WHERE gr.user_id = v_uid AND gr.game_mode = 'daily'
      AND gr.played_at >= (CURRENT_DATE - INTERVAL '70 days')
    GROUP BY gr.played_at::date
  ) t;
  RETURN jsonb_build_object(
    'current_streak', COALESCE(v_cur,0), 'highest_streak', COALESCE(v_high,0),
    'freezes', COALESCE(v_fz,0), 'days', COALESCE(v_days, '[]'::jsonb)
  );
END; $$;
GRANT EXECUTE ON FUNCTION public.get_streak_overview() TO authenticated;
