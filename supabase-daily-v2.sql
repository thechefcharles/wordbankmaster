-- V2 Phase 1: Daily V2 — the Prize-Budget redesign.
--
-- Reframes the Daily from "spend your real Cash (k=1.2, can't lose)" to "spend a
-- per-puzzle PRIZE budget and keep the remainder (k=1.0); Cash only goes up."
--   • daily_sessions.bankroll = the remaining PRIZE budget (was 0; buying debited profiles.bank).
--   • Buying letters spends the budget, not Cash.
--   • Wrong guess drains the budget: GREATEST($10, round(0.2×remaining/10)×10).
--   • Final guess when remaining < cheapest buyable letter; wrong there → fail (bank $0).
--   • kept = remaining at solve; winnings = kept × mult; multiplier is on WINNINGS (not budget).
--   • score/earned/net = winnings (≥ 0 always). Efficiency = kept/base×100 (−5 dock retired).
-- Spec: Notion "Daily V2 — the Prize-Budget redesign". PITR point logged before apply.

BEGIN;

-- 0) game_results: kept = remaining budget at finish (path-dependent; needed for Efficiency).
ALTER TABLE public.game_results ADD COLUMN IF NOT EXISTS kept integer;

-- 1) Prize (budget) = cost to reveal every distinct letter at k = 1.0.
CREATE OR REPLACE FUNCTION public._daily_reward(p_pid uuid)
 RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER
AS $function$
  SELECT GREATEST(100, (round(1.0 * COALESCE(SUM(public.letter_cost(t.ch)), 0) / 10.0) * 10)::int)
  FROM (
    SELECT DISTINCT substr(upper(dp.phrase), g.i + 1, 1) AS ch
    FROM public.daily_puzzles dp, generate_series(0, length(dp.phrase) - 1) g(i)
    WHERE dp.id = p_pid AND substr(upper(dp.phrase), g.i + 1, 1) ~ '[A-Z]'
  ) t;
$function$;

-- 2) Multiplier = streak + boosts only (wrong guesses now drain the BUDGET, not the mult).
CREATE OR REPLACE FUNCTION public._daily_bounty_mult(p_uid uuid)
 RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER
AS $function$
  SELECT GREATEST(1.0, LEAST(3.0,
    1.0
    + LEAST(0.1 * GREATEST(0, COALESCE(
        (SELECT CASE WHEN last_daily_solve_date >= CURRENT_DATE - 1 THEN current_daily_solve_streak ELSE 0 END
         FROM public.profiles WHERE id = p_uid), 0)), 0.5)
    + COALESCE((SELECT bounty_boost FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE), 0)
  ));
$function$;

-- 3a) Effective letter price under the session's active Twist (extracted from daily_buy_letter).
CREATE OR REPLACE FUNCTION public._daily_eff_cost(s public.daily_sessions, p_letter text)
 RETURNS integer LANGUAGE plpgsql IMMUTABLE
AS $function$
DECLARE v_cost int; v_vowel boolean; v_letter text;
BEGIN
  v_letter := upper(p_letter);
  v_cost := public.letter_cost(v_letter);
  IF v_cost IS NULL THEN RETURN NULL; END IF;
  v_vowel := v_letter IN ('A','E','I','O','U');
  IF s.twist_used THEN
    IF 'flat_rate' = ANY(s.active_powerups) THEN v_cost := 50;
    ELSIF 'discount' = ANY(s.active_powerups) THEN v_cost := CEIL(v_cost * 0.75)::int;
    ELSIF 'vowel_vision' = ANY(s.active_powerups) AND v_vowel THEN v_cost := CEIL(v_cost * 0.5)::int;
    ELSIF 'consonant_sale' = ANY(s.active_powerups) AND NOT v_vowel THEN v_cost := CEIL(v_cost * 0.75)::int;
    END IF;
  END IF;
  RETURN v_cost;
END; $function$;

-- 3b) Cheapest still-buyable (unrevealed) letter — the final-guess wall.
CREATE OR REPLACE FUNCTION public._daily_cheapest_buyable(s public.daily_sessions, p_phrase text)
 RETURNS integer LANGUAGE sql STABLE
AS $function$
  SELECT MIN(public._daily_eff_cost(s, t.ch))
  FROM (
    SELECT DISTINCT substr(p_phrase, g.i + 1, 1) AS ch
    FROM generate_series(0, length(p_phrase) - 1) g(i)
    WHERE substr(p_phrase, g.i + 1, 1) <> ' '
      AND NOT (g.i = ANY(s.revealed_positions))
  ) t;
$function$;

-- 4) Live HUD numbers: remaining prize, multiplier, and what you'd bank if you solved now.
CREATE OR REPLACE FUNCTION public._daily_live(p_remaining integer, p_mult numeric)
 RETURNS jsonb LANGUAGE sql IMMUTABLE
AS $function$
  SELECT jsonb_build_object(
    'remaining', COALESCE(p_remaining,0),
    'mult', COALESCE(p_mult,1.0),
    'winnings', (round(COALESCE(p_remaining,0) * COALESCE(p_mult,1.0) / 10.0) * 10)::int,
    -- back-compat aliases so the pre-V2 client's HUD still shows sane numbers in the deploy window
    'spent', 0,
    'reward', (round(COALESCE(p_remaining,0) * COALESCE(p_mult,1.0) / 10.0) * 10)::int,
    'net', (round(COALESCE(p_remaining,0) * COALESCE(p_mult,1.0) / 10.0) * 10)::int);
$function$;

-- 5) daily_start: seed the session budget = the prize; board shows remaining budget.
CREATE OR REPLACE FUNCTION public.daily_start(p_powerups text[] DEFAULT '{}'::text[], p_use_twist boolean DEFAULT true)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_pid UUID; v_phrase TEXT; v_cat TEXT; v_sub TEXT; s public.daily_sessions; v_mod TEXT;
  v_streak INT; v_high INT; v_last DATE; v_freezes INT; v_day INT; v_att INT := 0; v_new BOOLEAN := false;
  v_fv TEXT; v_reveal INT[] := '{}'; i INT; v_base INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_start: not authenticated'; END IF;
  PERFORM public._ensure_bank(v_uid);
  v_pid := public._todays_puzzle_id();
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
  IF NOT FOUND THEN
    IF v_pid IS NULL THEN RAISE EXCEPTION 'daily_start: no puzzle available'; END IF;
    v_mod := public._daily_modifier();
    v_base := public._daily_reward(v_pid);   -- the Prize (k = 1.0)
    INSERT INTO public.daily_sessions (user_id, puzzle_date, puzzle_id, bankroll, guesses_remaining, active_powerups, spent, twist_used)
    VALUES (v_uid, CURRENT_DATE, v_pid, v_base, 999, ARRAY[v_mod], 0, true) RETURNING * INTO s;
    v_new := true;
    -- auto-apply: reveal letters for the reveal-type Twists (free)
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
    -- attendance + play streak (unchanged)
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
  RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, v_cat, v_sub)
    || jsonb_build_object('live', public._daily_live(s.bankroll, public._daily_bounty_mult(v_uid)),
         'base', public._daily_reward(s.puzzle_id),
         'modifier', s.active_powerups[1], 'twist_used', s.twist_used, 'bounty_mult', public._daily_bounty_mult(v_uid),
         'wrong_guesses', COALESCE(s.p_wrong_guesses,0))
    || CASE WHEN v_new THEN jsonb_build_object('attendance', v_att, 'attendance_day', v_day) ELSE '{}'::jsonb END;
END; $function$;

-- 6) daily_buy_letter: spend from the session BUDGET (not profiles.bank).
CREATE OR REPLACE FUNCTION public.daily_buy_letter(p_letter text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); s public.daily_sessions; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_letter TEXT; v_cost INT; v_positions INT[]; v_vowel BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_buy_letter: not authenticated'; END IF;
  v_letter := upper(p_letter);
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'daily_buy_letter: no active session (call daily_start)'; END IF;
  v_cost := public._daily_eff_cost(s, v_letter);
  IF v_cost IS NULL THEN RAISE EXCEPTION 'daily_buy_letter: invalid letter'; END IF;
  v_vowel := v_letter IN ('A','E','I','O','U');
  SELECT upper(phrase), category, COALESCE(subcategory, '') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1, 1) = v_letter;
  -- Insured Twist: first wrong letter is free
  IF s.twist_used AND 'insured' = ANY(s.active_powerups) AND v_positions IS NULL AND COALESCE(array_length(s.incorrect_letters,1),0) = 0 THEN
    v_cost := 0;
  END IF;
  -- Can't buy: game over, already-wrong letter, or budget can't cover it.
  IF s.state <> 'active' OR v_letter = ANY(s.incorrect_letters) OR s.bankroll < v_cost THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;
  IF v_positions IS NOT NULL AND v_positions <@ s.revealed_positions THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;
  s.bankroll := s.bankroll - v_cost;           -- spend the PRIZE budget, not Cash
  s.spent := s.spent + v_cost;
  IF v_vowel THEN s.p_vowels := s.p_vowels + 1; END IF;
  IF v_positions IS NULL THEN s.incorrect_letters := array_append(s.incorrect_letters, v_letter);
  ELSE s.revealed_positions := ARRAY(SELECT DISTINCT unnest(s.revealed_positions || v_positions) ORDER BY 1); END IF;
  UPDATE public.daily_sessions SET bankroll = s.bankroll, spent = s.spent, incorrect_letters = s.incorrect_letters,
    revealed_positions = s.revealed_positions, p_vowels = s.p_vowels, updated_at = NOW()
  WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
  RETURN public._daily_resolve_and_return(v_uid, v_phrase, v_cat, v_sub);
END; $function$;

-- 7) daily_submit_guess: wrong guess drains the budget; final-guess wall → fail.
CREATE OR REPLACE FUNCTION public.daily_submit_guess(p_guess jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); s public.daily_sessions; v_phrase TEXT; v_cat TEXT; v_sub TEXT;
  v_editable INT[]; v_correct INT[] := '{}'; v_all_correct BOOLEAN := true; pos INT; v_guess_char TEXT;
  v_cheapest INT; v_pen INT; v_all INT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'daily_submit_guess: not authenticated'; END IF;
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'daily_submit_guess: no active session'; END IF;
  SELECT upper(phrase), category, COALESCE(subcategory, '') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = s.puzzle_id;
  IF s.state <> 'active' THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions));
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable, 1) THEN
    RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  END IF;
  FOREACH pos IN ARRAY v_editable LOOP
    v_guess_char := upper(p_guess ->> pos::text);
    IF v_guess_char IS NULL THEN v_all_correct := false;
    ELSIF v_guess_char = substr(v_phrase, pos+1, 1) THEN v_correct := v_correct || pos;
    ELSE v_all_correct := false; END IF;
  END LOOP;
  IF v_all_correct THEN
    s.revealed_positions := ARRAY(SELECT DISTINCT unnest(s.revealed_positions || v_correct) ORDER BY 1);
    UPDATE public.daily_sessions SET revealed_positions = s.revealed_positions, updated_at = NOW()
      WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
    RETURN public._daily_resolve_and_return(v_uid, v_phrase, v_cat, v_sub);
  END IF;
  -- Wrong guess.
  s.p_wrong_guesses := s.p_wrong_guesses + 1;
  v_cheapest := public._daily_cheapest_buyable(s, v_phrase);
  IF v_cheapest IS NOT NULL AND s.bankroll < v_cheapest THEN
    -- Final-guess wall: can't afford any letter and guessed wrong → fail (bank $0).
    SELECT array_agg(g.i) INTO v_all FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1, 1) <> ' ';
    UPDATE public.daily_sessions SET state = 'lost', finished_at = NOW(),
      revealed_positions = COALESCE(v_all, '{}'), p_wrong_guesses = s.p_wrong_guesses, updated_at = NOW()
      WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
    PERFORM public._finalize_daily(v_uid, false, s.spent, 0, COALESCE(array_length(s.incorrect_letters,1),0));
    RETURN public._daily_board(v_phrase, 'lost', s.bankroll, s.guesses_remaining, COALESCE(v_all,'{}'), s.incorrect_letters, v_cat, v_sub)
      || jsonb_build_object('live', public._daily_live(s.bankroll, public._daily_bounty_mult(v_uid)),
           'base', public._daily_reward(s.puzzle_id), 'modifier', s.active_powerups[1], 'twist_used', s.twist_used,
           'bounty_mult', public._daily_bounty_mult(v_uid), 'wrong_guesses', s.p_wrong_guesses,
           'daily_result', jsonb_build_object('won', false, 'base', public._daily_reward(s.puzzle_id),
             'spent', s.spent, 'kept', 0, 'mult', public._daily_bounty_mult(v_uid), 'winnings', 0, 'banked', 0, 'score', 0,
             'reward', 0, 'net', 0));
  END IF;
  -- Otherwise: drain the budget (20% of remaining, snapped to $10, min $10).
  v_pen := GREATEST(10, (round(0.2 * s.bankroll / 10.0) * 10)::int);
  s.bankroll := GREATEST(0, s.bankroll - v_pen);
  UPDATE public.daily_sessions SET bankroll = s.bankroll, p_wrong_guesses = s.p_wrong_guesses, updated_at = NOW()
    WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE;
  RETURN public._daily_resolve_and_return(v_uid, v_phrase, v_cat, v_sub);
END; $function$;

-- 8) Resolve: kept = remaining budget; winnings = kept × mult; bank winnings on solve.
CREATE OR REPLACE FUNCTION public._daily_resolve_and_return(p_uid uuid, p_phrase text, p_cat text, p_sub text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE s public.daily_sessions; v_won BOOLEAN; v_board JSONB; v_base INT; v_kept INT; v_mult NUMERIC; v_winnings INT;
BEGIN
  SELECT * INTO s FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;
  v_base := public._daily_reward(s.puzzle_id);
  v_kept := GREATEST(0, s.bankroll);
  v_mult := public._daily_bounty_mult(p_uid);                 -- pre-finalize → incoming streak
  v_winnings := (round(v_kept * v_mult / 10.0) * 10)::int;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(p_phrase)-1) g(i)
    WHERE substr(p_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions)));
  IF v_won AND s.state = 'active' THEN
    UPDATE public.daily_sessions SET state = 'won', updated_at = NOW(), finished_at = COALESCE(finished_at, NOW())
      WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;
    s.state := 'won';
    PERFORM public._finalize_daily(p_uid, true, s.spent, v_kept, COALESCE(array_length(s.incorrect_letters,1),0));
    PERFORM public._record_category_solve(p_uid, p_cat);
  END IF;
  v_board := public._daily_board(p_phrase, s.state, s.bankroll, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, p_cat, p_sub)
    || jsonb_build_object('live', public._daily_live(s.bankroll, v_mult), 'base', v_base,
         'modifier', s.active_powerups[1], 'twist_used', s.twist_used, 'bounty_mult', v_mult,
         'wrong_guesses', COALESCE(s.p_wrong_guesses,0));
  IF s.state = 'won' THEN
    v_board := v_board || jsonb_build_object('daily_result', jsonb_build_object(
      'won', true, 'base', v_base, 'spent', s.spent, 'kept', v_kept, 'mult', v_mult,
      'winnings', v_winnings, 'banked', v_winnings, 'score', v_winnings, 'twist_used', s.twist_used,
      'reward', v_winnings, 'net', v_winnings));   -- reward/net = back-compat aliases
  END IF;
  RETURN v_board;
END; $function$;

-- 9) Finalize: bank winnings (kept × mult); store kept; score = winnings (≥ 0).
CREATE OR REPLACE FUNCTION public._finalize_daily(p_uid uuid, p_won boolean, p_spent integer, p_kept integer DEFAULT 0, p_incorrect_count integer DEFAULT 0)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_week_start DATE; v_pid UUID; v_base INT; v_kept INT; v_mult NUMERIC; v_winnings INT; v_streak INT; v_cat TEXT; v_spent INT;
  v_started TIMESTAMPTZ; v_time INT; v_used BOOLEAN; v_wrong INT; v_ss INT; v_bss INT; v_lss DATE; v_grant TEXT;
BEGIN
  v_week_start := date_trunc('week', CURRENT_DATE)::DATE + 1;
  SELECT puzzle_id, created_at, twist_used, COALESCE(p_wrong_guesses,0) INTO v_pid, v_started, v_used, v_wrong
    FROM public.daily_sessions WHERE user_id = p_uid AND puzzle_date = CURRENT_DATE;
  SELECT category INTO v_cat FROM public.daily_puzzles WHERE id = v_pid;
  v_base    := public._daily_reward(v_pid);
  v_kept    := GREATEST(0, COALESCE(p_kept, 0));
  v_mult    := public._daily_bounty_mult(p_uid);              -- incoming streak (before the bump below)
  v_spent   := GREATEST(0, COALESCE(p_spent,0));
  v_winnings := CASE WHEN p_won THEN (round(v_kept * v_mult / 10.0) * 10)::int ELSE 0 END;
  v_time := LEAST(GREATEST(EXTRACT(epoch FROM (now() - v_started)) * 1000, 0), 1800000)::int;
  SELECT COALESCE(current_daily_play_streak,0) INTO v_streak FROM public.profiles WHERE id = p_uid;
  INSERT INTO public.game_results (
    user_id, played_at, won, bankroll_left, kept, game_mode, score, outcome, puzzle_id, category,
    solved_count, puzzle_count, spent, earned, net, multiple_x100, time_ms, clean, wrong_guesses)
  VALUES (
    p_uid, NOW(), p_won, v_kept, v_kept, 'daily', v_winnings, CASE WHEN p_won THEN 'won' ELSE 'lost' END, v_pid, v_cat,
    CASE WHEN p_won THEN 1 ELSE 0 END, 1, v_spent, v_winnings, v_winnings,
    CASE WHEN p_won AND v_base > 0 THEN round(v_winnings * 100.0 / v_base)::int ELSE NULL END,
    CASE WHEN p_won THEN v_time ELSE NULL END,
    (p_won AND COALESCE(p_incorrect_count,0) = 0), COALESCE(v_wrong,0));
  INSERT INTO public.user_weekly_stats (user_id, week_start, puzzles_completed, bankroll_earned, highest_bankroll, total_wins, total_played, win_streak)
  VALUES (p_uid, v_week_start, CASE WHEN p_won THEN 1 ELSE 0 END, v_winnings, GREATEST(v_winnings,0), CASE WHEN p_won THEN 1 ELSE 0 END, 1, v_streak)
  ON CONFLICT (user_id, week_start) DO UPDATE SET
    total_played = user_weekly_stats.total_played + 1,
    total_wins = user_weekly_stats.total_wins + CASE WHEN p_won THEN 1 ELSE 0 END,
    puzzles_completed = user_weekly_stats.puzzles_completed + CASE WHEN p_won THEN 1 ELSE 0 END,
    bankroll_earned = user_weekly_stats.bankroll_earned + v_winnings,
    highest_bankroll = GREATEST(user_weekly_stats.highest_bankroll, v_winnings),
    win_streak = GREATEST(user_weekly_stats.win_streak, v_streak);
  SELECT COALESCE(current_daily_solve_streak,0), COALESCE(best_daily_solve_streak,0), last_daily_solve_date INTO v_ss, v_bss, v_lss
    FROM public.profiles WHERE id = p_uid;
  IF p_won THEN
    IF v_lss = CURRENT_DATE THEN v_ss := v_ss;
    ELSIF v_lss = CURRENT_DATE - 1 THEN v_ss := v_ss + 1;
    ELSE v_ss := 1; END IF;
    v_bss := GREATEST(v_bss, v_ss);
    UPDATE public.profiles SET current_daily_solve_streak = v_ss, best_daily_solve_streak = v_bss, last_daily_solve_date = CURRENT_DATE WHERE id = p_uid;
    PERFORM public._bank_credit(p_uid, v_winnings, 'daily_reward');
    IF COALESCE(p_incorrect_count,0) = 0 THEN PERFORM public._award_badge(p_uid, 'flawless'); END IF;
    IF NOT COALESCE(v_used, false) THEN
      v_grant := public._twist_powerup(public._daily_modifier());
      IF v_grant IS NOT NULL THEN PERFORM public._award_powerup(p_uid, v_grant, 'cash'); END IF;
    END IF;
  ELSE
    UPDATE public.profiles SET current_daily_solve_streak = 0 WHERE id = p_uid;
  END IF;
  PERFORM public._check_calendar_badges(p_uid, CURRENT_DATE);
END; $function$;

-- 10) daily_fold: give up → lost, bank $0 (pass kept=0).
CREATE OR REPLACE FUNCTION public.daily_fold()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
declare v_uid uuid := auth.uid(); s public.daily_sessions; v_phrase text; v_cat text; v_sub text; v_all int[];
begin
  if v_uid is null then raise exception 'daily_fold: not authenticated'; end if;
  select * into s from public.daily_sessions where user_id = v_uid and puzzle_date = current_date for update;
  if not found then raise exception 'daily_fold: no active session'; end if;
  select upper(phrase), category, coalesce(subcategory,'') into v_phrase, v_cat, v_sub from public.daily_puzzles where id = s.puzzle_id;
  if s.state <> 'active' then
    return public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining, s.revealed_positions, s.incorrect_letters, v_cat, v_sub);
  end if;
  select array_agg(g.i) into v_all from generate_series(0, length(v_phrase)-1) g(i) where substr(v_phrase, g.i+1, 1) <> ' ';
  update public.daily_sessions set state = 'lost', finished_at = now(), revealed_positions = coalesce(v_all, '{}'), updated_at = now()
    where user_id = v_uid and puzzle_date = current_date;
  perform public._finalize_daily(v_uid, false, s.spent, 0, coalesce(array_length(s.incorrect_letters,1),0));
  return public._daily_board(v_phrase, 'lost', s.bankroll, s.guesses_remaining, coalesce(v_all, '{}'), s.incorrect_letters, v_cat, v_sub);
end; $function$;

-- 11) expire_stale_dailies: a missed day → loss, score 0 (no negative net anymore).
CREATE OR REPLACE FUNCTION public.expire_stale_dailies()
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); r public.daily_sessions; v_phrase text; v_cat text; v_all int[]; v_n int := 0;
BEGIN
  IF v_uid IS NULL THEN RETURN 0; END IF;
  FOR r IN SELECT * FROM public.daily_sessions
           WHERE user_id = v_uid AND state = 'active' AND puzzle_date < CURRENT_DATE
           FOR UPDATE LOOP
    SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = r.puzzle_id;
    SELECT array_agg(g.i) INTO v_all FROM generate_series(0, length(v_phrase)-1) g(i) WHERE substr(v_phrase, g.i+1, 1) <> ' ';
    UPDATE public.daily_sessions
      SET state = 'lost', finished_at = (r.puzzle_date + 1)::timestamptz,
          revealed_positions = COALESCE(v_all, '{}'), updated_at = now()
      WHERE user_id = v_uid AND puzzle_date = r.puzzle_date;
    INSERT INTO public.game_results
      (user_id, played_at, won, bankroll_left, kept, game_mode, score, outcome, puzzle_id, category,
       solved_count, puzzle_count, spent, earned, net)
    VALUES
      (v_uid, (r.puzzle_date + 1)::timestamptz, false, 0, 0, 'daily', 0, 'lost', r.puzzle_id, v_cat,
       0, 1, r.spent, 0, 0);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END; $function$;

-- 12) Leaderboard: Bounty Earned = winnings (≥0), Efficiency = kept/base×100 (−5 dock retired).
CREATE OR REPLACE FUNCTION public.get_daily_board(p_scope text DEFAULT 'everyone'::text, p_group uuid DEFAULT NULL::uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB; v_base int;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  v_base := public._daily_reward(public._todays_puzzle_id());
  WITH circle AS (
    SELECT v_uid AS id
    UNION SELECT friend_id FROM public.friendships WHERE user_id = v_uid AND p_scope = 'friends'
    UNION SELECT user_id FROM public.group_members WHERE group_id = p_group AND p_scope = 'group'
    UNION SELECT id FROM public.profiles WHERE p_scope IN ('global','everyone')
  ),
  d AS (
    SELECT c.id,
      COALESCE(pr.bank, 0)::bigint AS net_worth,
      (CASE WHEN pr.last_daily_play_date >= CURRENT_DATE - 1 THEN COALESCE(pr.current_daily_play_streak,0) ELSE 0 END) AS play_streak,
      (CASE WHEN pr.last_daily_solve_date >= CURRENT_DATE - 1 THEN COALESCE(pr.current_daily_solve_streak,0) ELSE 0 END) AS win_streak,
      g.score AS score,
      (CASE WHEN g.won AND v_base > 0 THEN GREATEST(0, LEAST(100, round(COALESCE(g.kept,0)::numeric / v_base * 100)::int)) ELSE NULL END) AS efficiency,
      pr.equipped_title, pr.equipped_color
    FROM circle c
    JOIN public.profiles pr ON pr.id = c.id
    LEFT JOIN LATERAL (
      SELECT gr.score, gr.kept, gr.won FROM public.game_results gr
      WHERE gr.user_id = c.id AND gr.game_mode = 'daily' AND gr.played_at::date = CURRENT_DATE
      ORDER BY gr.played_at DESC LIMIT 1
    ) g ON true
    WHERE c.id IS NOT NULL
  ),
  ranked AS (
    SELECT *, row_number() OVER (ORDER BY (score IS NULL), score DESC NULLS LAST, net_worth DESC) AS rank
    FROM d ORDER BY (score IS NULL), score DESC NULLS LAST, net_worth DESC LIMIT 100
  )
  SELECT jsonb_agg(jsonb_build_object(
    'rank', rank, 'name', public._display_name(id), 'net_worth', net_worth, 'score', score,
    'efficiency', efficiency,
    'play_streak', play_streak, 'win_streak', win_streak, 'played', score IS NOT NULL,
    'is_me', id = v_uid, 'title', equipped_title, 'color', equipped_color) ORDER BY rank) INTO v_rows FROM ranked;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $function$;

COMMIT;
