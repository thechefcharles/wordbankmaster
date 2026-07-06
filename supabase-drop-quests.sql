-- V2 Phase 0 (DB): drop the retired Quests feature.
--
-- Quests never shipped a UI (get_daily_quests/claim_quest_reward had no client callers).
-- Verified before writing:
--   • No other DB function references quest_claims / claim_quest_reward / get_daily_quests.
--   • No frontend references (only historical ledger LABEL 'quest_reward', removed in code).
--   • 0 rows in quest_claims; 0 bank_ledger rows with reason='quest_reward' → no data lost.
-- PITR rollback point logged before apply: see below.

BEGIN;

DROP FUNCTION IF EXISTS public.claim_quest_reward();
DROP FUNCTION IF EXISTS public.get_daily_quests();
DROP TABLE IF EXISTS public.quest_claims;

COMMIT;
