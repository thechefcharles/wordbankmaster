-- ============================================================================
-- Retire the legacy challenge_* / _challenge_* engine. Superseded entirely by the
-- match_* engine (challenge_matches + challenge_participants, econ_v=2). Verified: no
-- live function references these, the client wrappers/GameStore functions are removed,
-- and the challenges + challenge_plays tables are empty in prod.
-- ============================================================================
BEGIN;

DROP FUNCTION IF EXISTS public.create_challenge(text,text,bigint,text);
DROP FUNCTION IF EXISTS public.accept_challenge(uuid);
DROP FUNCTION IF EXISTS public.get_challenge(uuid);
DROP FUNCTION IF EXISTS public.get_my_challenges();
DROP FUNCTION IF EXISTS public.challenge_buy_letter(uuid,text);
DROP FUNCTION IF EXISTS public.challenge_submit_guess(uuid,jsonb);
DROP FUNCTION IF EXISTS public.challenge_reveal(uuid);
DROP FUNCTION IF EXISTS public.challenge_check(uuid);
DROP FUNCTION IF EXISTS public._challenge_board(uuid,uuid);
DROP FUNCTION IF EXISTS public._challenge_resolve(uuid,uuid);
DROP FUNCTION IF EXISTS public._challenge_record_score(uuid,uuid,integer);
DROP FUNCTION IF EXISTS public._challenge_settle(uuid);

COMMIT;
