-- ============================================================================
-- Activate the (now-working) Heat Shield power-up so it's actually purchasable.
-- Heat Shield is PASSIVE: owning one auto-saves you from a bust (see _cg_try_shield
-- in supabase-cashgame-interest-rework.sql). So tapping it in the power-up tray must
-- NOT consume it — climb_use_powerup becomes a no-op for heat_shield.
--
-- The other dead Cash Game power-ups (double_down, extra_attempt, insurance) are left
-- inactive on purpose: they're redundant/meaningless (DoN already has its own button;
-- Cash Game guesses are free/unlimited; a bust-save is now Heat Shield's job).
-- ============================================================================
BEGIN;

UPDATE public.powerups SET active = true WHERE id = 'heat_shield';

CREATE OR REPLACE FUNCTION public.climb_use_powerup(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); cs public.climb_state; v_eff TEXT; v_qty INT; v_phrase TEXT; v_positions INT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'climb_use_powerup: not authenticated'; END IF;
  SELECT effect_key INTO v_eff FROM public.powerups WHERE id = p_id AND kind = 'climb' AND active;
  IF v_eff IS NULL THEN RAISE EXCEPTION 'climb_use_powerup: invalid power-up'; END IF;
  SELECT * INTO cs FROM public.climb_state WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR cs.state NOT IN ('active','stuck') THEN RETURN public._climb_board(v_uid); END IF;
  -- Heat Shield is a passive safety net (auto-consumed on a bust). Tapping it does nothing
  -- and must never burn the charge.
  IF v_eff = 'heat_shield' THEN RETURN public._climb_board(v_uid); END IF;
  SELECT qty INTO v_qty FROM public.user_powerups_v2 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
  IF COALESCE(v_qty,0) <= 0 THEN RETURN public._climb_board(v_uid); END IF;
  IF v_eff = ANY(cs.active_powerups) THEN RETURN public._climb_board(v_uid); END IF;
  UPDATE public.user_powerups_v2 SET qty = qty - 1 WHERE user_id = v_uid AND powerup_id = p_id AND pool = 'cash';
  UPDATE public.climb_state SET active_powerups = array_append(active_powerups, v_eff) WHERE user_id = v_uid;
  SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = cs.puzzle_id;
  v_positions := public._powerup_reveal(v_phrase, v_eff, cs.revealed_positions);
  IF v_positions IS NOT NULL THEN
    UPDATE public.climb_state SET revealed_positions = ARRAY(SELECT DISTINCT unnest(revealed_positions || v_positions) ORDER BY 1) WHERE user_id = v_uid;
  END IF;
  RETURN public._climb_resolve(v_uid);
END; $function$;

COMMIT;
