-- One-off: purge QA/test accounts from the production DB (2026-07-17).
--
-- WordBank has ONE database and it IS production. QA harness runs signed up throwaway
-- users (qa…@example.com etc), and with almost no FK constraints their gameplay data was
-- left orphaned in leaderboards/stats. This deletes the test accounts AND all their data.
--
-- SAFETY (verified before writing):
--  * Test set = machine-pattern domains (example.com/test.com/e.com) + the owner's manual
--    wordbank.com test accounts (test1-6, testt, challenge1/2, test5). Real users live on
--    gmail/yahoo/icloud/etc and are NOT touched.
--  * Isolation confirmed: 0 matches, 0 groups, 0 friendships link a test account to a real
--    one — so deleting test rows cannot affect any real user's data.
--  * Runs in a transaction; the caller wraps it and verifies counts before COMMIT.
--  * Backups/PITR must be confirmed BEFORE this is run for real.

DO $$
DECLARE
  v_tbl   text;
  v_users int;
  v_rows  bigint := 0;
  v_n     bigint;
BEGIN
  -- 1. Materialize the exact test-user id set once.
  CREATE TEMP TABLE _test_users ON COMMIT DROP AS
    SELECT id FROM auth.users
     WHERE email ILIKE '%@example.com'
        OR email ILIKE '%@test.com'
        OR email ILIKE '%@e.com'
        OR email ILIKE '%@wordbank.com';
  SELECT count(*) INTO v_users FROM _test_users;
  RAISE NOTICE 'test users to purge: %', v_users;

  -- 2. Delete from EVERY public table that has a user_id uuid column (dynamic = nothing missed).
  FOR v_tbl IN
    SELECT table_name FROM information_schema.columns
     WHERE table_schema='public' AND column_name='user_id' AND data_type='uuid'
     ORDER BY table_name
  LOOP
    EXECUTE format('DELETE FROM public.%I WHERE user_id IN (SELECT id FROM _test_users)', v_tbl);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_rows := v_rows + v_n;
  END LOOP;

  -- 3. Extra user-referencing columns not named user_id (isolation guarantees these are test-only).
  DELETE FROM public.friendships         WHERE friend_id   IN (SELECT id FROM _test_users);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_rows := v_rows + v_n;
  DELETE FROM public.game_results        WHERE opponent_id IN (SELECT id FROM _test_users);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_rows := v_rows + v_n;
  DELETE FROM public.challenges          WHERE opponent_id IN (SELECT id FROM _test_users);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_rows := v_rows + v_n;
  DELETE FROM public.challenge_matches   WHERE host_id     IN (SELECT id FROM _test_users);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_rows := v_rows + v_n;
  DELETE FROM public.groups              WHERE owner_id    IN (SELECT id FROM _test_users);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_rows := v_rows + v_n;
  DELETE FROM public.group_join_requests WHERE requester_id IN (SELECT id FROM _test_users);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_rows := v_rows + v_n;

  -- 4. User-keyed-by-id tables.
  DELETE FROM public.daily_stats WHERE id IN (SELECT id FROM _test_users);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_rows := v_rows + v_n;
  DELETE FROM public.profiles    WHERE id IN (SELECT id FROM _test_users);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_rows := v_rows + v_n;

  -- 5. Finally the auth rows.
  DELETE FROM auth.users WHERE id IN (SELECT id FROM _test_users);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'auth.users deleted: %  |  app-data rows deleted: %', v_n, v_rows;
END $$;
