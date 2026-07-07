-- Cash Game V3c: rebalance the tier buy-in ladder.
--
-- Old: Micro $100 / Bronze $500 / Silver $2,000 / Gold $10,000 (100× spread; $100 too
-- little, $10k too much). New: $250 / $1,000 / $2,500 / $5,000 (20× spread). Micro becomes
-- a real entry stake (still swingy — a solve ~3× it), Gold stays aspirational but reachable.
-- Only the buy-in numbers change; k, heat caps, labels, mastery gates, and order are kept.
-- Spec: chat decision 2026-07-07. PITR point logged before apply.

BEGIN;

CREATE OR REPLACE FUNCTION public._cg_tier(p_tier text)
 RETURNS jsonb LANGUAGE sql IMMUTABLE
AS $function$
  SELECT CASE lower(p_tier)
    WHEN 'micro'  THEN jsonb_build_object('buy_in', 250,   'k', 0.90, 'heat_cap', 200, 'label', '🪙 Micro',  'order', 1)
    WHEN 'bronze' THEN jsonb_build_object('buy_in', 1000,  'k', 0.85, 'heat_cap', 250, 'label', '🥉 Bronze', 'order', 2)
    WHEN 'silver' THEN jsonb_build_object('buy_in', 2500,  'k', 0.70, 'heat_cap', 275, 'label', '🥈 Silver', 'order', 3)
    WHEN 'gold'   THEN jsonb_build_object('buy_in', 5000,  'k', 0.55, 'heat_cap', 300, 'label', '🥇 Gold',   'order', 4)
    ELSE NULL END;
$function$;

COMMIT;
