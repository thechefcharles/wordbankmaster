-- Phase 4 of OBJECTIVE_HUD_SPEC: solo "beat your best" goal line.
-- Applied to prod via MCP migration `get_personal_bests`.
--
-- Returns the current user's lowest WINNING spend per mode, e.g. { "daily": 20, "climb": 60 }.
-- Derived from the Play Log (game_results). The client shows it as a goal line on the
-- solo spend HUD ("🎯 Beat your best: $X" / "🔥 Under your best") for daily / makeup / climb.
-- Modes with no prior win are simply absent → no goal line shown.

CREATE OR REPLACE FUNCTION public.get_personal_bests()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT COALESCE(jsonb_object_agg(game_mode, min_spent), '{}'::jsonb)
  FROM (
    SELECT game_mode, MIN(spent)::int AS min_spent
    FROM public.game_results
    WHERE user_id = auth.uid() AND outcome = 'won' AND spent IS NOT NULL
    GROUP BY game_mode
  ) t;
$function$;
