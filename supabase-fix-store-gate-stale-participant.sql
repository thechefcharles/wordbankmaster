-- Fix: Store buy blocked by a "game in progress" that isn't (2026-07-17).
--
-- Root cause: buy_powerup's active-game gate blocked when the user had ANY
-- challenge_participants row with state='active' — WITHOUT checking the match is still
-- open. _match_settle sets challenge_matches.status='settled' but never clears the
-- participant state, so a non-finisher stays 'active' forever. Those stale rows then
-- falsely trip the buy gate (the client menu was already correct — it checks status='open').
--
-- Fix: the gate now only blocks on active participants whose MATCH is still open. This is
-- the correct semantics (a settled match is not an active game) and is robust to any stale
-- rows, present or future. Also one-time-cleans the existing stale rows.

CREATE OR REPLACE FUNCTION public.buy_powerup(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
 DECLARE v_uid UUID := auth.uid(); v_price BIGINT; v_cash BIGINT; v_owned INT; v_kind TEXT; v_cap INT;
 BEGIN
   IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
   IF COALESCE((SELECT loan FROM public.profiles WHERE id = v_uid),0) > 0 THEN RETURN jsonb_build_object('ok',false,'reason','in_debt'); END IF;
   SELECT price, kind INTO v_price, v_kind FROM public.powerups WHERE id = p_id AND active;
   IF v_price IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','no_item'); END IF;
   -- Active-game gate: gameplay items only; never blocks cosmetics.
   -- The challenge check joins challenge_matches so a SETTLED match (whose participant
   -- state was never cleared) can't falsely block — only genuinely OPEN matches count.
   IF v_kind IN ('climb','daily','sabotage') AND (
        EXISTS (SELECT 1 FROM public.climb_state WHERE user_id = v_uid AND state = 'active')
     OR EXISTS (SELECT 1 FROM public.challenge_participants cp
                  JOIN public.challenge_matches m2 ON m2.id = cp.match_id
                 WHERE cp.user_id = v_uid AND cp.state = 'active' AND m2.status = 'open')
     OR EXISTS (SELECT 1 FROM public.daily_sessions WHERE user_id = v_uid AND puzzle_date = CURRENT_DATE AND state = 'active')
   ) THEN
     RETURN jsonb_build_object('ok',false,'reason','in_game');
   END IF;
   v_cap := CASE WHEN v_kind = 'daily' THEN 5 ELSE 1 END;
   SELECT COALESCE(qty,0) INTO v_owned FROM public.user_powerups_v2 WHERE user_id=v_uid AND powerup_id=p_id AND pool='cash';
   IF COALESCE(v_owned,0) >= v_cap THEN RETURN jsonb_build_object('ok',false,'reason','owned'); END IF;
   PERFORM public._ensure_bank(v_uid);
   SELECT bank INTO v_cash FROM public.profiles WHERE id = v_uid;
   IF v_cash < v_price THEN RETURN jsonb_build_object('ok',false,'reason','insufficient'); END IF;
   PERFORM public._bank_credit(v_uid, -v_price, 'powerup_buy');
   PERFORM public._award_powerup(v_uid, p_id, 'cash');
   RETURN jsonb_build_object('ok',true);
 END; $function$;

-- Keep the grant hygiene from the launch audit (never PUBLIC).
REVOKE EXECUTE ON FUNCTION public.buy_powerup(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buy_powerup(text) TO authenticated;

-- One-time cleanup of the existing stale rows (active participant on an already-settled
-- match → terminal 'done'; the match is settled, so this has no scoring effect).
UPDATE public.challenge_participants cp
   SET state = 'done'
  FROM public.challenge_matches m
 WHERE m.id = cp.match_id AND cp.state = 'active' AND m.status = 'settled';
