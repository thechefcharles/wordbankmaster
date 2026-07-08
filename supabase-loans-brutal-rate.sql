-- 🦈 Loans: crank the daily rate curve to "brutal" (was 2/4/6/8%/day).
-- Only the rate table changes; accrual/cap/flow are unchanged. Existing loans keep
-- their locked rate; new loans use the steeper curve.
CREATE OR REPLACE FUNCTION public._loan_daily_rate_bp(p_amount bigint, p_cap bigint)
  RETURNS integer LANGUAGE sql IMMUTABLE
AS $fn$
  SELECT CASE
    WHEN p_cap <= 0 THEN 1500
    WHEN p_amount::numeric / p_cap <= 0.25 THEN 500    -- 5%/day
    WHEN p_amount::numeric / p_cap <= 0.50 THEN 800    -- 8%/day
    WHEN p_amount::numeric / p_cap <= 0.75 THEN 1200   -- 12%/day
    ELSE 1500                                          -- 15%/day
  END;
$fn$;
