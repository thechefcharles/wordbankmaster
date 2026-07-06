-- Drop the broken + redundant signup trigger. handle_user_signup inserts into columns that
-- don't exist on profiles (bankroll/games_played/games_won/games_lost/highest_streak) and only
-- never errors because handle_new_user (on_auth_user_created) shadows it by creating the profile
-- first. Removing this latent landmine; handle_new_user remains the sole profile-creator
-- (to be updated in V2 Phase 0 for the $2,000 start + arcade-column removal).
BEGIN;
DROP TRIGGER IF EXISTS trigger_user_signup ON auth.users;
DROP FUNCTION IF EXISTS public.handle_user_signup();
COMMIT;
