-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Challenge: efficiency-first scoring — most Cash left wins; skip pays full   ║
-- ║  (migration: challenge_cash_left_scoring_2026_06 — applied via psql)         ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- New 1v1 / group model (decided with the user):
--   • One shared ante budget across the whole pack; spend it on letters.
--   • WINNER = most Cash left at the end (i.e. spent the least). total_score is now
--     just the remaining bankroll (was solved×1e6 + bankroll). Solving is implicitly
--     required: a skip costs the FULL reveal price, which is always ≥ what solving the
--     same puzzle costs, so skippers always rank below solvers.
--   • SKIP / fold / out-of-Cash timeout = charged the full price of every still-
--     UNREVEALED letter in that puzzle (base letter_cost, capped at your remaining
--     ante). So a skipped puzzle always totals the full price — you can't reveal-then-
--     skip to dodge it, and you can't skip to "save" Cash.
--   • TIES at the top split the pot evenly — already handled by _match_settle's
--     winner branch (pot / count(top total_score)); now that total_score = cash-left,
--     everyone tied for least-spent shares equally.
--
-- The "Left to Spend" bounty hero is now literally the scoreboard: highest wins.

-- ── scoring: total_score = cash left (rank by least spent) ──
CREATE OR REPLACE FUNCTION public._match_resolve_and_advance(p_id uuid, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cp public.challenge_participants; m public.challenge_matches; v_phrase TEXT; v_won BOOLEAN; v_score INT; v_combo INT; v_solved INT; v_budget BIGINT;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF cp.state <> 'active' THEN RETURN public._match_board(p_id, p_uid); END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  v_budget := GREATEST(COALESCE(m.wager,0), 500);
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = public._match_pid(p_id, cp.position);
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(cp.revealed_positions)));
  IF NOT v_won THEN RETURN public._match_board(p_id, p_uid); END IF;
  v_solved := cp.solved + 1;
  IF m.mode = 'blitz' THEN
    v_score := round(300 * cp.combo_x100 / 100.0)::int; v_combo := LEAST(300, cp.combo_x100 + 25);
    IF cp.position >= m.pack_size THEN
      UPDATE public.challenge_participants SET total_score = total_score + v_score, last_score = v_score,
        combo_x100 = v_combo, solved = v_solved, state = 'done', joined_at = COALESCE(joined_at, now())
      WHERE match_id = p_id AND user_id = p_uid;
      PERFORM public._match_maybe_settle(p_id);
    ELSE
      UPDATE public.challenge_participants SET total_score = total_score + v_score, last_score = v_score, position = position + 1,
        solved = v_solved, bankroll = v_budget, revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
        p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0, combo_x100 = v_combo WHERE match_id = p_id AND user_id = p_uid;
    END IF;
    RETURN public._match_board(p_id, p_uid);
  END IF;
  -- Standard: rank by Cash left (total_score = bankroll). Solve cost is partial, so a
  -- solved puzzle always leaves more Cash than a skipped one (full price).
  IF cp.position >= m.pack_size THEN
    UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
      total_score = cp.bankroll, state = 'done', joined_at = COALESCE(joined_at, now())
    WHERE match_id = p_id AND user_id = p_uid;
    PERFORM public._match_maybe_settle(p_id);
  ELSE
    UPDATE public.challenge_participants SET solved = v_solved, last_score = cp.bankroll,
      total_score = cp.bankroll, position = position + 1,
      revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}', p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
    WHERE match_id = p_id AND user_id = p_uid;
  END IF;
  RETURN public._match_board(p_id, p_uid);
END; $function$;

-- ── skip / fold / timeout: charge the full price of the rest of the puzzle ──
CREATE OR REPLACE FUNCTION public.match_fold(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_uid uuid := auth.uid(); cp public.challenge_participants; m public.challenge_matches;
  v_phrase text; v_charge bigint; v_left bigint;
begin
  if v_uid is null then raise exception 'match_fold: not authenticated'; end if;
  if public._match_tick(p_id, v_uid) then return public._match_board(p_id, v_uid); end if;
  select * into cp from public.challenge_participants where match_id = p_id and user_id = v_uid for update;
  if not found or cp.state <> 'active' then return public._match_board(p_id, v_uid); end if;
  select * into m from public.challenge_matches where id = p_id;
  -- full price of every still-unrevealed distinct letter (base cost), capped at remaining ante
  select upper(phrase) into v_phrase from public.daily_puzzles where id = public._match_pid(p_id, cp.position);
  select coalesce(sum(public.letter_cost(t.ch)), 0) into v_charge from (
    select distinct substr(v_phrase, g.i+1, 1) as ch from generate_series(0, length(v_phrase)-1) g(i)
    where substr(v_phrase, g.i+1, 1) ~ '[A-Z]' and not (g.i = any(cp.revealed_positions))
  ) t;
  v_charge := least(v_charge, cp.bankroll);
  v_left := greatest(0, cp.bankroll - v_charge);
  if cp.position >= m.pack_size then
    update public.challenge_participants
      set state = 'done', bankroll = v_left, last_score = 0, total_score = v_left,
          joined_at = coalesce(joined_at, now())
      where match_id = p_id and user_id = v_uid;
    perform public._match_maybe_settle(p_id);
  else
    update public.challenge_participants
      set position = position + 1, bankroll = v_left, last_score = 0, total_score = v_left,
          revealed_positions = '{}', incorrect_letters = '{}', active_powerups = '{}', debuffs = '{}',
          p_vowels = 0, p_reveals = 0, p_wrong_guesses = 0
      where match_id = p_id and user_id = v_uid;
  end if;
  return public._match_board(p_id, v_uid);
end; $function$;
