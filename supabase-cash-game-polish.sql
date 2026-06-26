-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Cash Game polish: cleanup + run-tracking + run leaderboard + anomaly       ║
-- ║  (migration: cash_game_polish_2026_06 — applied via psql)                   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- Bundles the post-Double-or-Nothing pass:
--   B  (cleanup): drop legacy `attempts_remaining` column + orphaned climb_reveal;
--      remove the DEAD inactive-power-up effect code (double_down / insurance /
--      heat_shield) from _climb_resolve. These power-ups are active=false, so they
--      can never enter active_powerups (climb_use_powerup requires active) — the
--      branches were unreachable. Catalog rows are LEFT in place (active=false) to
--      avoid breaking _grant_random_powerup's FK; "cut" = de-fanged, not deleted.
--   C1 (insurance ✕ DoN): resolved for free by the above — with the insurance
--      branch gone, a Double-or-Nothing bust can never be refunded. (If insurance
--      is ever reactivated, re-add its effect so it explicitly does NOT fire while
--      cs.don_armed — the gamble must stay all-or-nothing.)
--   C3 (run leaderboard): persist best_run_solves / best_run_profit on climb_state
--      (all-time hot-streak bests, never reset), update them on each solve, and add
--      get_climb_run_leaderboard(scope, group) ranked by best_run_profit.
--   C4 (anomaly): get_climb_anomaly_summary(days) from game_results (game_mode=climb)
--      — fast/instant solves, volume, profit — Cash Game was uncovered (the Daily
--      anomaly summary only reads daily_sessions).
--
-- Idempotent; safe to re-run. Apply inside one transaction.

BEGIN;

-- ── C3: all-time run bests (never reset; only run_solves/run_profit reset on stuck) ──
ALTER TABLE public.climb_state
  ADD COLUMN IF NOT EXISTS best_run_solves int    NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS best_run_profit bigint NOT NULL DEFAULT 0;

-- Backfill bests from the current live run so existing players aren't zeroed.
UPDATE public.climb_state
   SET best_run_solves = GREATEST(best_run_solves, run_solves),
       best_run_profit = GREATEST(best_run_profit, run_profit);

-- ── B + C1 + C3: resolve logic (removes dead pup branches, tracks run bests) ──
CREATE OR REPLACE FUNCTION public._climb_resolve(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_won BOOLEAN; v_bounty INT; v_payout INT; v_min INT; v_cash BIGINT; v_cat TEXT; v_time INT; v_newprofit BIGINT;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF cs.state IN ('solved','complete') THEN RETURN public._climb_board(p_uid); END IF;
  SELECT upper(phrase), category INTO v_phrase, v_cat FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_won := NOT EXISTS (SELECT 1 FROM generate_series(0, length(v_phrase)-1) g(i)
    WHERE substr(v_phrase, g.i+1, 1) <> ' ' AND NOT (g.i = ANY(cs.revealed_positions)));
  IF v_won THEN
    v_bounty := public._climb_bounty(cs.puzzle_id);
    IF cs.don_armed THEN v_bounty := v_bounty * 2; END IF;  -- Double or Nothing paid off
    v_payout := round(v_bounty * cs.heat_x100 / 100.0)::int;
    v_newprofit := cs.run_profit + (v_payout - cs.spent);
    v_time := LEAST(GREATEST(EXTRACT(epoch FROM (now() - COALESCE(cs.puzzle_started_at, cs.updated_at))) * 1000, 0), 1800000)::int;
    PERFORM public._bank_credit(p_uid, v_payout, 'climb_bounty');
    UPDATE public.climb_state SET state = 'solved', last_gain = v_payout,
      heat_x100 = LEAST(200, cs.heat_x100 + 10),
      run_solves = cs.run_solves + 1, run_profit = v_newprofit,
      best_run_solves = GREATEST(cs.best_run_solves, cs.run_solves + 1),
      best_run_profit = GREATEST(cs.best_run_profit, v_newprofit),
      don_armed = false, updated_at = now() WHERE user_id = p_uid;
    PERFORM public._log_game_result(p_uid,'climb','won', cs.puzzle_id, v_cat, 1, 1, cs.spent::int, v_payout, v_time);
  ELSE
    SELECT min(public.letter_cost(t.ch)) INTO v_min FROM (
      SELECT DISTINCT substr(v_phrase, g.i+1, 1) AS ch FROM generate_series(0, length(v_phrase)-1) g(i)
      WHERE substr(v_phrase, g.i+1, 1) ~ '[A-Z]' AND NOT (g.i = ANY(cs.revealed_positions))) t;
    SELECT bank INTO v_cash FROM public.profiles WHERE id = p_uid;
    IF v_min IS NULL OR v_cash < v_min THEN
      -- Stuck: can't afford the cheapest unrevealed letter. Heat + run wiped.
      -- (A Double-or-Nothing bust lands here → don_armed cleared, $0, nothing refunded.)
      UPDATE public.climb_state SET state = 'stuck',
        heat_x100 = 100, run_solves = 0, run_profit = 0,
        don_armed = false, updated_at = now() WHERE user_id = p_uid;
      PERFORM public._log_game_result(p_uid,'climb','lost', cs.puzzle_id, v_cat, 0, 1, cs.spent::int, 0);
    ELSE
      UPDATE public.climb_state SET state = 'active', updated_at = now() WHERE user_id = p_uid;
    END IF;
  END IF;
  RETURN public._climb_board(p_uid);
END; $function$;

-- ── B: board (drop attempts_remaining; pass unlimited-guess sentinel; expose bests) ──
CREATE OR REPLACE FUNCTION public._climb_board(p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cs public.climb_state; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_cash BIGINT; v_state TEXT; v_board JSONB;
BEGIN
  SELECT * INTO cs FROM public.climb_state WHERE user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF cs.state = 'complete' THEN
    RETURN jsonb_build_object('climb', jsonb_build_object('complete', true, 'position', cs.position, 'heat', cs.heat_x100));
  END IF;
  SELECT upper(phrase), category, COALESCE(subcategory,'') INTO v_phrase, v_cat, v_sub FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  SELECT bank INTO v_cash FROM public.profiles WHERE id = p_uid;
  v_state := CASE cs.state WHEN 'solved' THEN 'won' ELSE 'active' END;
  -- guesses are unlimited in the Cash Game; pass a high sentinel to the shared board.
  v_board := public._daily_board(v_phrase, v_state, v_cash::int, 99, cs.revealed_positions, cs.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('climb', jsonb_build_object(
    'bounty', public._climb_bounty(cs.puzzle_id), 'heat', cs.heat_x100,
    'spent', cs.spent, 'position', cs.position, 'stuck', cs.state = 'stuck', 'last_gain', cs.last_gain,
    'state', cs.state, 'pups_locked', cs.pups_locked, 'equipped', to_jsonb(cs.active_powerups),
    'don_armed', cs.don_armed, 'don_available', (cs.state = 'active' AND cs.heat_x100 >= 150 AND NOT cs.don_armed),
    'run_solves', cs.run_solves, 'run_profit', cs.run_profit,
    'best_run_solves', cs.best_run_solves, 'best_run_profit', cs.best_run_profit));
END; $function$;

-- ── B: advance (drop attempts_remaining=3; run + bests persist across solves) ──
CREATE OR REPLACE FUNCTION public.climb_next()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_pid UUID; v_newpos INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_next: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state <> 'solved' THEN RETURN public._climb_board(v_uid); END IF;
  v_newpos := cs.position + 1;
  v_pid := public._pick_casual(v_uid, null, cs.puzzle_id, 0);
  IF v_pid IS NULL THEN
    UPDATE public.climb_state SET state = 'complete', position = v_newpos, updated_at = now() WHERE user_id = v_uid;
    RETURN public._climb_board(v_uid);
  END IF;
  UPDATE public.climb_state SET position = v_newpos, puzzle_id = v_pid, revealed_positions = '{}',
    incorrect_letters = '{}', spent = 0, last_gain = 0, active_powerups = '{}',
    pups_locked = false, don_armed = false, state = 'active', puzzle_started_at = now(), updated_at = now() WHERE user_id = v_uid;
  PERFORM public._mark_seen(v_uid, v_pid);
  IF v_newpos = 50 THEN PERFORM public._award_badge(v_uid, 'climb_50');
  ELSIF v_newpos = 100 THEN PERFORM public._award_badge(v_uid, 'climb_100');
  ELSIF v_newpos = 500 THEN PERFORM public._award_badge(v_uid, 'climb_500'); END IF;
  RETURN public._climb_board(v_uid);
END; $function$;

-- ── B: skip (drop attempts_remaining=3; still wipes heat + run) ──
CREATE OR REPLACE FUNCTION public.climb_skip()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_pid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_skip: not authenticated'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state NOT IN ('active','stuck') THEN RETURN public._climb_board(v_uid); END IF;
  IF cs.don_armed THEN RETURN public._climb_board(v_uid); END IF;  -- committed; can't skip
  v_pid := public._pick_casual(v_uid, null, cs.puzzle_id, 0);
  IF v_pid IS NULL THEN RETURN public._climb_board(v_uid); END IF;
  UPDATE public.climb_state SET puzzle_id = v_pid, revealed_positions = '{}', incorrect_letters = '{}',
    spent = 0, last_gain = 0, active_powerups = '{}', pups_locked = false,
    heat_x100 = 100, run_solves = 0, run_profit = 0, don_armed = false,
    state = 'active', puzzle_started_at = now(), updated_at = now()
  WHERE user_id = v_uid;
  PERFORM public._mark_seen(v_uid, v_pid);
  RETURN public._climb_board(v_uid);
END; $function$;

-- ── B: drop orphaned reveal RPC (became the Free Reveal power-up) ──
DROP FUNCTION IF EXISTS public.climb_reveal();

-- ── B: drop legacy column now that no function references it ──
ALTER TABLE public.climb_state DROP COLUMN IF EXISTS attempts_remaining;

-- ── C3: profit/run leaderboard (skill-based; complements the position board) ──
CREATE OR REPLACE FUNCTION public.get_climb_run_leaderboard(p_scope text DEFAULT 'friends'::text, p_group uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); v_rows JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  WITH pool AS (
    SELECT cs.user_id AS id, cs.best_run_profit, cs.best_run_solves, cs.position
    FROM public.climb_state cs
    WHERE cs.best_run_profit > 0 AND (
         p_scope = 'global' OR cs.user_id = v_uid
      OR (p_scope = 'friends' AND cs.user_id IN (SELECT friend_id FROM public.friendships WHERE user_id = v_uid))
      OR (p_scope = 'group'   AND cs.user_id IN (SELECT user_id FROM public.group_members WHERE group_id = p_group)))
  ),
  ranked AS (SELECT *, row_number() OVER (ORDER BY best_run_profit DESC, best_run_solves DESC) AS rank
             FROM pool ORDER BY best_run_profit DESC LIMIT 50)
  SELECT jsonb_agg(jsonb_build_object('rank', rank, 'name', public._display_name(id),
    'best_run_profit', best_run_profit, 'best_run_solves', best_run_solves,
    'position', position, 'is_me', id = v_uid) ORDER BY rank) INTO v_rows FROM ranked;
  RETURN COALESCE(v_rows, '[]'::jsonb);
END; $function$;

-- ── C4: Cash Game anomaly summary (anti-AI-solving) ──
CREATE OR REPLACE FUNCTION public.get_climb_anomaly_summary(p_days int DEFAULT 30)
 RETURNS TABLE(user_id uuid, display_name text, solves int, losses int,
               avg_solve_seconds numeric, fast_solves int, instant_solves int,
               total_profit bigint, max_position int)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN QUERY
  WITH g AS (
    SELECT gr.user_id, gr.won,
           GREATEST(0, COALESCE(gr.time_ms, 0)) / 1000.0 AS secs,
           COALESCE(gr.net, 0) AS net
    FROM public.game_results gr
    WHERE gr.game_mode = 'climb'
      AND gr.played_at >= now() - make_interval(days => GREATEST(p_days, 1))
  ),
  agg AS (
    SELECT g.user_id,
      COUNT(*) FILTER (WHERE g.won)::int       AS solves,
      COUNT(*) FILTER (WHERE NOT g.won)::int    AS losses,
      ROUND(AVG(g.secs) FILTER (WHERE g.won), 1) AS avg_secs,
      COUNT(*) FILTER (WHERE g.won AND g.secs < 15)::int AS fast_solves,
      COUNT(*) FILTER (WHERE g.won AND g.secs < 5)::int  AS instant_solves,
      SUM(g.net)::bigint AS total_profit
    FROM g GROUP BY g.user_id
  )
  SELECT a.user_id, public._display_name(a.user_id), a.solves, a.losses, a.avg_secs,
         a.fast_solves, a.instant_solves, a.total_profit, COALESCE(cs.position, 0)
  FROM agg a
  LEFT JOIN public.climb_state cs ON cs.user_id = a.user_id
  ORDER BY a.instant_solves DESC, a.fast_solves DESC, a.solves DESC;
END; $function$;

COMMIT;
