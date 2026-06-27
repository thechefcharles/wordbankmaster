-- ╔═══════════════════════════════════════════════════════════════════════╗
-- ║ Free Play redesign: free letters with a reveal budget + guess budget,   ║
-- ║ earn credits on solve (scaled by reveals used), credits = pure cashable  ║
-- ║ wallet (no 2,000 stake).                                                 ║
-- ╚═══════════════════════════════════════════════════════════════════════╝
ALTER TABLE public.freeplay_sessions ADD COLUMN IF NOT EXISTS reveals_remaining int NOT NULL DEFAULT 3;

-- Start / next puzzle: free reveals (3) + guesses (6) per puzzle; bankroll = persistent
-- earned wallet (never reset to a free stake).
CREATE OR REPLACE FUNCTION public.freeplay_start(p_category text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid UUID := auth.uid(); v_pid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'freeplay_start: not authenticated'; END IF;
  v_pid := public._pick_casual(v_uid, p_category, null, 0);
  IF v_pid IS NULL THEN RAISE EXCEPTION 'freeplay_start: no puzzles in category'; END IF;
  INSERT INTO public.freeplay_sessions (user_id, category, puzzle_id, bankroll, reveals_remaining, guesses_remaining, revealed_positions, incorrect_letters, state)
    VALUES (v_uid, p_category, v_pid, 0, 3, 6, '{}', '{}', 'active')
  ON CONFLICT (user_id) DO UPDATE SET category = EXCLUDED.category, puzzle_id = EXCLUDED.puzzle_id,
    reveals_remaining = 3, guesses_remaining = 6, revealed_positions = '{}', incorrect_letters = '{}',
    state = 'active', updated_at = NOW();  -- bankroll preserved (it's the wallet)
  PERFORM public._mark_seen(v_uid, v_pid);
  RETURN public._freeplay_response(v_uid);
END; $function$;

-- Pick a letter — FREE, costs 1 reveal. Wrong picks still cost a reveal.
CREATE OR REPLACE FUNCTION public.freeplay_buy_letter(p_letter text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid UUID := auth.uid(); s public.freeplay_sessions; v_phrase TEXT; v_letter TEXT; v_positions INT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'freeplay_buy_letter: not authenticated'; END IF;
  v_letter := upper(p_letter);
  IF v_letter !~ '^[A-Z]$' THEN RAISE EXCEPTION 'freeplay_buy_letter: invalid letter'; END IF;
  SELECT * INTO s FROM public.freeplay_sessions WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'freeplay_buy_letter: no session'; END IF;
  IF s.state <> 'active' OR s.reveals_remaining <= 0 THEN RETURN public._freeplay_response(v_uid); END IF;
  IF v_letter = ANY(s.incorrect_letters) THEN RETURN public._freeplay_response(v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = s.puzzle_id;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) = v_letter;
  IF v_positions IS NOT NULL AND v_positions <@ s.revealed_positions THEN RETURN public._freeplay_response(v_uid); END IF;
  s.reveals_remaining := s.reveals_remaining - 1;  -- letters are free; the budget is the cost
  IF v_positions IS NULL THEN s.incorrect_letters := array_append(s.incorrect_letters, v_letter);
  ELSE s.revealed_positions := ARRAY(SELECT DISTINCT unnest(s.revealed_positions || v_positions) ORDER BY 1); END IF;
  UPDATE public.freeplay_sessions SET reveals_remaining = s.reveals_remaining, incorrect_letters = s.incorrect_letters,
    revealed_positions = s.revealed_positions, updated_at = NOW() WHERE user_id = v_uid;
  RETURN public._freeplay_resolve(v_uid);
END; $function$;

-- Auto-reveal the most useful letter — FREE, costs 1 reveal.
CREATE OR REPLACE FUNCTION public.freeplay_reveal()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid UUID := auth.uid(); s public.freeplay_sessions; v_phrase TEXT; v_letter TEXT; v_positions INT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'freeplay_reveal: not authenticated'; END IF;
  SELECT * INTO s FROM public.freeplay_sessions WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'freeplay_reveal: no session'; END IF;
  IF s.state <> 'active' OR s.reveals_remaining <= 0 THEN RETURN public._freeplay_response(v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = s.puzzle_id;
  SELECT t.ch INTO v_letter FROM (
    SELECT substr(v_phrase, g.i+1, 1) AS ch, count(*) AS c FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions))
    GROUP BY substr(v_phrase, g.i+1, 1) ORDER BY c DESC, ch LIMIT 1) t;
  IF v_letter IS NULL THEN RETURN public._freeplay_response(v_uid); END IF;
  SELECT array_agg(g.i) INTO v_positions FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) = v_letter;
  s.reveals_remaining := s.reveals_remaining - 1;
  s.revealed_positions := ARRAY(SELECT DISTINCT unnest(s.revealed_positions || v_positions) ORDER BY 1);
  UPDATE public.freeplay_sessions SET reveals_remaining = s.reveals_remaining, revealed_positions = s.revealed_positions, updated_at = NOW()
    WHERE user_id = v_uid;
  RETURN public._freeplay_resolve(v_uid);
END; $function$;

-- Submit a full-phrase guess. Wrong → costs 1 guess.
CREATE OR REPLACE FUNCTION public.freeplay_submit_guess(p_guess jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid UUID := auth.uid(); s public.freeplay_sessions; v_phrase TEXT;
  v_editable INT[]; v_correct INT[] := '{}'; v_all_correct BOOLEAN := true; pos INT; v_guess_char TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'freeplay_submit_guess: not authenticated'; END IF;
  SELECT * INTO s FROM public.freeplay_sessions WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'freeplay_submit_guess: no session'; END IF;
  IF s.state <> 'active' THEN RETURN public._freeplay_response(v_uid); END IF;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = s.puzzle_id;
  SELECT array_agg(g.i ORDER BY g.i) INTO v_editable FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions));
  IF v_editable IS NULL OR (SELECT count(*) FROM jsonb_object_keys(p_guess)) <> array_length(v_editable, 1) THEN
    RETURN public._freeplay_response(v_uid);
  END IF;
  FOREACH pos IN ARRAY v_editable LOOP
    v_guess_char := upper(p_guess ->> pos::text);
    IF v_guess_char IS NULL THEN v_all_correct := false;
    ELSIF v_guess_char = substr(v_phrase, pos+1, 1) THEN v_correct := v_correct || pos;
    ELSE v_all_correct := false; END IF;
  END LOOP;
  IF v_all_correct THEN
    s.revealed_positions := ARRAY(SELECT DISTINCT unnest(s.revealed_positions || v_correct) ORDER BY 1);
    UPDATE public.freeplay_sessions SET revealed_positions = s.revealed_positions, updated_at = NOW() WHERE user_id = v_uid;
  ELSE
    UPDATE public.freeplay_sessions SET guesses_remaining = GREATEST(0, s.guesses_remaining - 1), updated_at = NOW() WHERE user_id = v_uid;
  END IF;
  RETURN public._freeplay_resolve(v_uid);
END; $function$;

-- Resolve: win → earn credits scaled by reveals used; lose → out of guesses.
CREATE OR REPLACE FUNCTION public._freeplay_resolve(p_uid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE s public.freeplay_sessions; v_phrase TEXT; v_won BOOLEAN; v_lost BOOLEAN; v_reward INT := 0; v_used INT;
BEGIN
  SELECT * INTO s FROM public.freeplay_sessions WHERE user_id = p_uid;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = s.puzzle_id;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(s.revealed_positions)));
  v_lost := (s.guesses_remaining <= 0) AND NOT v_won;
  IF v_won AND s.state <> 'won' THEN
    v_used := GREATEST(0, 3 - s.reveals_remaining);             -- 0..3 reveals used
    v_reward := GREATEST(150, 300 - 50 * v_used);               -- 0→300 · 1→250 · 2→200 · 3→150
    UPDATE public.freeplay_sessions SET state='won', bankroll = bankroll + v_reward, updated_at=NOW() WHERE user_id=p_uid;
    PERFORM public._record_category_solve(p_uid, s.category);
  ELSIF v_lost AND s.state = 'active' THEN
    UPDATE public.freeplay_sessions SET state='lost', updated_at=NOW() WHERE user_id=p_uid;
  END IF;
  RETURN public._freeplay_response(p_uid) || jsonb_build_object('freeplay_reward', v_reward);
END; $function$;

-- Response: surface the reveal budget to the client too.
CREATE OR REPLACE FUNCTION public._freeplay_response(p_uid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE s public.freeplay_sessions; v_phrase TEXT; v_cat TEXT; v_sub TEXT;
BEGIN
  SELECT * INTO s FROM public.freeplay_sessions WHERE user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT upper(phrase), category, COALESCE(subcategory,'') INTO v_phrase, v_cat, v_sub
    FROM public.daily_puzzles WHERE id = s.puzzle_id;
  RETURN public._daily_board(v_phrase, s.state, s.bankroll, s.guesses_remaining,
    s.revealed_positions, s.incorrect_letters, v_cat, v_sub)
    || jsonb_build_object('reveals_remaining', s.reveals_remaining);
END; $function$;

-- Cash out: all credits are cashable now (no 2,000 stake), still 40:1 and $50/day.
CREATE OR REPLACE FUNCTION public.freeplay_cashout_status()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid uuid := auth.uid(); v_bank int; v_cashable int; v_today int; v_cap int := 50;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  SELECT COALESCE(bankroll,0) INTO v_bank FROM public.freeplay_sessions WHERE user_id = v_uid;
  v_bank := COALESCE(v_bank, 0);
  v_cashable := GREATEST(0, v_bank);
  SELECT COALESCE(sum(delta),0) INTO v_today FROM public.bank_ledger
    WHERE user_id = v_uid AND reason = 'freeplay_cashout' AND created_at::date = CURRENT_DATE;
  RETURN jsonb_build_object('credits', v_bank, 'cashable_credits', v_cashable, 'max_cash', v_cashable / 40,
    'rate', 40, 'floor', 0, 'daily_cap', v_cap, 'cap_remaining', GREATEST(0, v_cap - v_today));
END; $function$;

-- Also applied: freeplay_cashout cashable = full bankroll (GREATEST(0, v_bank), was v_bank-2000).
