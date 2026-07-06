-- surface wrong_guesses in the daily board response (for the multiplier explainer)
BEGIN;
CREATE OR REPLACE FUNCTION public._daily_resolve_and_return(p_uid uuid, p_phrase text, p_cat text, p_sub text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE s public.daily_sessions; v_won BOOLEAN; v_board JSONB; v_bank BIGINT; v_reward INT; v_base INT; v_mult NUMERIC;
BEGIN
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;
  v_base := public._daily_reward(s.puzzle_id);
  v_mult := public._daily_bounty_mult(p_uid);                 -- pre-finalize → matches the credited reward
  v_reward := (round(v_base * v_mult / 10.0) * 10)::int;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(p_phrase)-1) g(i)
    WHERE substr(p_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions)));
  IF v_won AND s.state = 'active' THEN
    UPDATE public.daily_sessions SET state = 'won', updated_at = NOW(), finished_at = COALESCE(finished_at, NOW())
      WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;
    s.state := 'won';
    PERFORM public._finalize_daily(p_uid, true, s.spent, COALESCE(array_length(s.incorrect_letters,1),0));
    PERFORM public._record_category_solve(p_uid, p_cat);
  END IF;
  SELECT bank INTO v_bank FROM public.profiles WHERE id = p_uid;
  v_board := public._daily_board(p_phrase, s.state, v_bank::int, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, p_cat, p_sub)
    || jsonb_build_object('live', public._daily_live(s.spent, v_reward),
         'modifier', s.active_powerups[1], 'twist_used', s.twist_used, 'bounty_mult', public._daily_bounty_mult(p_uid), 'wrong_guesses', COALESCE((SELECT p_wrong_guesses FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE),0));
  IF s.state = 'won' THEN
    v_board := v_board || jsonb_build_object('daily_result', jsonb_build_object(
      'reward', v_reward, 'base', v_base, 'mult', v_mult, 'spent', s.spent,
      'net', v_reward - s.spent, 'score', v_reward - s.spent, 'twist_used', s.twist_used));
  END IF;
  RETURN v_board;
END; $function$

;
CREATE OR REPLACE FUNCTION public.daily_start(p_powerups text[] DEFAULT '{}'::text[], p_use_twist boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_pid UUID; v_phrase TEXT; v_cat TEXT; v_sub TEXT; s public.daily_sessions; v_mod TEXT;
  v_bank BIGINT; v_streak INT; v_high INT; v_last DATE; v_freezes INT; v_day INT; v_att INT := 0; v_new BOOLEAN := false;
  v_fv TEXT; v_reveal INT[] := '{}'; i INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_start: not authenticated'; END IF;
  PERFORM public._ensure_bank(v_uid);
  v_pid := public._todays_puzzle_id();
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
  IF NOT FOUND THEN
    IF v_pid IS NULL THEN RAISE EXCEPTION 'daily_start: no puzzle available'; END IF;
    v_mod := public._daily_modifier();
    INSERT INTO public.daily_sessions (user_id, puzzle_date, puzzle_id, bankroll, guesses_remaining, active_powerups, spent, twist_used)
    VALUES (v_uid, CURRENT_DATE, v_pid, 0, 999, ARRAY[v_mod], 0, true) RETURNING * INTO s;
    v_new := true;
    -- 🎁 auto-apply: reveal letters for the reveal-type Twists
    SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = v_pid;
    IF v_mod = 'free_vowel' THEN
      SELECT substr(v_phrase, g.i+1, 1) INTO v_fv FROM generate_series(0, length(v_phrase)-1) g(i)
        WHERE substr(v_phrase, g.i+1, 1) IN ('A','E','I','O','U') ORDER BY g.i LIMIT 1;
      IF v_fv IS NOT NULL THEN
        SELECT array_agg(g.i) INTO v_reveal FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1, 1) = v_fv;
      END IF;
    ELSIF v_mod = 'head_start' THEN
      FOR i IN 0 .. length(v_phrase)-1 LOOP
        IF substr(v_phrase, i+1, 1) <> ' ' AND (i = 0 OR substr(v_phrase, i, 1) = ' ') THEN v_reveal := v_reveal || i; END IF;
      END LOOP;
    END IF;
    IF array_length(v_reveal, 1) > 0 THEN
      UPDATE public.daily_sessions SET revealed_positions = ARRAY(SELECT DISTINCT unnest(revealed_positions || v_reveal) ORDER BY 1)
        WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE RETURNING * INTO s;
    END IF;
    -- attendance + streak
    SELECT current_daily_play_streak, best_daily_play_streak, last_daily_play_date, COALESCE(streak_freezes,0)
      INTO v_streak, v_high, v_last, v_freezes FROM public.profiles WHERE id = v_uid;
    IF v_last = CURRENT_DATE THEN v_day := COALESCE(v_streak,0);
    ELSIF v_last = CURRENT_DATE - 1 THEN v_day := COALESCE(v_streak,0) + 1;
    ELSIF v_last = CURRENT_DATE - 2 AND v_freezes > 0 AND COALESCE(v_streak,0) > 0 THEN v_freezes := v_freezes - 1; v_day := COALESCE(v_streak,0) + 1;
    ELSE v_day := 1; END IF;
    IF v_day > 0 AND v_day % 7 = 0 THEN v_freezes := LEAST(v_freezes + 1, 3); END IF;
    v_high := GREATEST(COALESCE(v_high,0), v_day);
    UPDATE public.profiles SET current_daily_play_streak = v_day, best_daily_play_streak = v_high,
      last_daily_play_date = CURRENT_DATE, streak_freezes = v_freezes WHERE id = v_uid;
    v_att := 50 + CASE WHEN v_day % 30 = 0 THEN 1500 WHEN v_day % 14 = 0 THEN 500
                       WHEN v_day % 7 = 0 THEN 250 WHEN v_day = 3 THEN 100 ELSE 0 END;
    PERFORM public._bank_credit(v_uid, v_att, 'attendance');
    IF v_day >= 7 THEN PERFORM public._award_badge(v_uid, 'streak_7'); END IF;
    IF v_day >= 30 THEN PERFORM public._award_badge(v_uid, 'streak_30'); END IF;
  END IF;
  SELECT upper(phrase), category, COALESCE(subcategory, '') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;
  SELECT bank INTO v_bank FROM public.profiles WHERE id = v_uid;
  RETURN public._daily_board(v_phrase, s.state, v_bank::int, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, v_cat, v_sub)
    || jsonb_build_object('live', public._daily_live(s.spent, public._daily_reward_final(v_uid, s.puzzle_id)),
         'modifier', s.active_powerups[1], 'twist_used', s.twist_used, 'bounty_mult', public._daily_bounty_mult(v_uid), 'wrong_guesses', COALESCE((SELECT p_wrong_guesses FROM public.daily_sessions WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE),0))
    || CASE WHEN v_new THEN jsonb_build_object('attendance', v_att, 'attendance_day', v_day) ELSE '{}'::jsonb END;
END; $function$

;
COMMIT;
