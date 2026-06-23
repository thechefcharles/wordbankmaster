-- Phase 2 of OBJECTIVE_HUD_SPEC: live DIRECTIONAL standing for 1v1 / single-puzzle
-- group challenges. Applied to prod via MCP migration `match_board_directional_standing`.
--
-- _match_board now returns a `standing` object alongside `match` while you're playing
-- a single-puzzle (pack_size=1), non-blitz, open match:
--   { field_size, finished, rank, state }
--   state ∈ 'lead' | 'behind' | 'tied' | 'first_to_play'
--
-- Spoiler-safe by design: the server compares your spend-so-far to FINISHED rivals'
-- locked spend and returns only a DIRECTION + rank — never the exact spend-to-beat.
-- Lower spend wins (a finished non-solver isn't a bar; you just need to solve).
-- Verified (rolled back): lead {rank1}, behind {rank2}, tied {rank1}, first_to_play {finished0}.

CREATE OR REPLACE FUNCTION public._match_board(p_id uuid, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE cp public.challenge_participants; m public.challenge_matches; v_pid UUID; v_phrase TEXT; v_cat TEXT; v_sub TEXT; v_clue TEXT; v_board JSONB; v_minfo JSONB; v_budget BIGINT;
  v_standing JSONB := NULL; v_field INT; v_finished INT; v_my_spent BIGINT; v_best_spent BIGINT; v_ahead INT; v_state TEXT; v_rank INT;
BEGIN
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_uid;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  v_budget := GREATEST(COALESCE(m.wager,0), 500);
  v_minfo := jsonb_build_object('pack_size', m.pack_size, 'mode', m.mode, 'total_score', cp.total_score,
    'last_score', cp.last_score, 'position', cp.position, 'done', cp.state = 'done', 'status', m.status,
    'solved', cp.solved, 'spent', GREATEST(0, v_budget - cp.bankroll), 'budget', v_budget, 'wager', m.wager,
    'items_allowed', COALESCE(m.items_allowed,false), 'used_powerups', to_jsonb(cp.active_powerups),
    'my_debuffs', to_jsonb(COALESCE(cp.debuffs,'{}')),
    'opponents', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', o.user_id, 'name', public._display_name(o.user_id)) ORDER BY o.joined_at NULLS LAST), '[]'::jsonb)
      FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state IN ('active','invited')));
  IF m.mode = 'blitz' THEN
    v_minfo := v_minfo || jsonb_build_object('started_at', cp.started_at, 'clock_seconds', m.pack_size * 30, 'combo', cp.combo_x100);
  END IF;
  IF cp.state = 'done' THEN RETURN jsonb_build_object('match', v_minfo); END IF;

  -- Directional standing (single-puzzle, non-blitz): my projected rank vs FINISHED
  -- rivals, computed here so the exact spend-to-beat never reaches the client.
  -- Lower spend wins (ties broken by who solved); show direction, never the number.
  IF m.pack_size = 1 AND m.status = 'open' AND m.mode <> 'blitz' THEN
    v_my_spent := GREATEST(0, v_budget - cp.bankroll);
    SELECT count(*) INTO v_field FROM public.challenge_participants WHERE match_id = p_id;
    SELECT count(*) INTO v_finished FROM public.challenge_participants WHERE match_id = p_id AND user_id <> p_uid AND state = 'done';
    SELECT min(GREATEST(0, v_budget - o.bankroll)) INTO v_best_spent
      FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state = 'done' AND o.solved >= 1;
    SELECT count(*) INTO v_ahead
      FROM public.challenge_participants o WHERE o.match_id = p_id AND o.user_id <> p_uid AND o.state = 'done' AND o.solved >= 1
        AND GREATEST(0, v_budget - o.bankroll) < v_my_spent;
    IF v_finished = 0 THEN v_state := 'first_to_play'; v_rank := 1;
    ELSIF v_best_spent IS NULL THEN v_state := 'lead'; v_rank := 1;
    ELSIF v_my_spent < v_best_spent THEN v_state := 'lead'; v_rank := 1;
    ELSIF v_my_spent = v_best_spent THEN v_state := 'tied'; v_rank := v_ahead + 1;
    ELSE v_state := 'behind'; v_rank := v_ahead + 1;
    END IF;
    v_standing := jsonb_build_object('field_size', v_field, 'finished', v_finished, 'rank', v_rank, 'state', v_state);
  END IF;

  v_pid := public._match_pid(p_id, cp.position);
  SELECT upper(phrase), category, COALESCE(subcategory,''), clue INTO v_phrase, v_cat, v_sub, v_clue FROM public.daily_puzzles WHERE id = v_pid;
  v_board := public._daily_board(v_phrase, 'active', cp.bankroll, cp.guesses_remaining, cp.revealed_positions, cp.incorrect_letters, v_cat, v_sub);
  RETURN v_board || jsonb_build_object('match', v_minfo, 'standing', v_standing,
    'clue', CASE WHEN 'fog' = ANY(COALESCE(cp.debuffs,'{}')) THEN NULL ELSE v_clue END);
END; $function$;
