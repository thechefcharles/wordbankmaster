-- Store active-game gate: block buying GAMEPLAY items during an active real game.
-- Gameplay items (kind IN 'climb','daily','sabotage') can no longer be bought while
-- the buyer has an active Cash Game run, an active challenge, or an in-progress Daily
-- for today. Cosmetics are NOT sold via buy_powerup and are never affected.
-- Everything else in buy_powerup is byte-identical to the live definition.

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
   IF v_kind IN ('climb','daily','sabotage') AND (
        EXISTS (SELECT 1 FROM public.climb_state WHERE user_id = v_uid AND state = 'active')
     OR EXISTS (SELECT 1 FROM public.challenge_participants WHERE user_id = v_uid AND state = 'active')
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
