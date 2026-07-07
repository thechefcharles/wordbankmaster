-- Loan cap scales to the highest UNLOCKED Cash Game tier's buy-in (was a flat $500 —
-- too big for a $250 Micro ante, useless for a $2,500 Silver / $5,000 Gold run). A loan's
-- job is funding a buy-in you can't quite afford, so the cap should always cover the tier
-- you've earned access to: Bronze $1,000 (default) → Silver $2,500 → Gold $5,000.
-- PITR point logged before apply.

BEGIN;

CREATE OR REPLACE FUNCTION public._loan_cap(p_uid uuid)
 RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER
AS $function$
  SELECT (public._cg_tier(
    CASE
      WHEN public._cg_unlocked(p_uid, 'gold')   THEN 'gold'
      WHEN public._cg_unlocked(p_uid, 'silver') THEN 'silver'
      ELSE 'bronze'
    END
  )->>'buy_in')::bigint;
$function$;

COMMIT;
