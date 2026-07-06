-- Pre-V2 housekeeping: drop verified-orphan functions (no frontend, no internal callers, no triggers).
-- NOT included: the full arcade code-path + columns removal (entangled with get_daily_status,
-- the handle_new_user auth trigger, and GameStore/Keyboard/+page) → folded into V2 Phase 0.
BEGIN;
DROP FUNCTION IF EXISTS public.get_random_phrase();
DROP FUNCTION IF EXISTS public.get_random_puzzle();
DROP FUNCTION IF EXISTS public.get_random_puzzle_by_category(category_text text);
DROP FUNCTION IF EXISTS public.get_my_friend_code();
DROP FUNCTION IF EXISTS public.record_daily_result(p_user_id uuid, p_won boolean, p_bankroll_left integer);
DROP FUNCTION IF EXISTS public.get_arcade_leaderboard(p_period text, p_order_by text);
DROP FUNCTION IF EXISTS public.record_arcade_result(p_user_id uuid, p_won boolean, p_bankroll_left integer);
DROP FUNCTION IF EXISTS public.save_arcade_bankroll(p_bankroll integer);
COMMIT;
