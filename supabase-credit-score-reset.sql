-- One-time reset: the initial credit launch had a NULL-loan bug that deflated scores
-- (LEAST(NULL/cap,1)=1 → utilization 0) and skipped new-player grace. Now fixed. The
-- feature is <1 day old, so wipe the buggy stored scores back to the neutral 650 baseline
-- and let the corrected lazy recompute rebuild them. PITR point logged before apply.
BEGIN;
UPDATE public.profiles
   SET credit_score = 650, credit_updated_at = NULL, credit_derog_until = NULL;
-- Clear any credit badges auto-awarded off buggy scores; they re-award correctly on recompute.
DELETE FROM public.user_badges WHERE badge IN ('credit_700','credit_800','credit_850');
COMMIT;
