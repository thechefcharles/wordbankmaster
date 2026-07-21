-- ============================================================================
-- Remove "Reveal Word" power-up. On a one-word phrase (~40% of all puzzles) it
-- reveals the ENTIRE answer for $250 — effectively a paid auto-solve — and it
-- overlaps the existing reveals (Letter Reveal / First Letters / Vowel Vision).
-- Same cut pattern as the earlier roster rebalance: deactivate + clear inventory.
-- (The effect_key logic in climb_use_powerup/match_use_powerup is left dormant.)
-- Applied to prod.
-- ============================================================================
BEGIN;

UPDATE public.powerups SET active = false WHERE id = 'reveal_word';
DELETE FROM public.user_powerups_v2 WHERE powerup_id = 'reveal_word';

COMMIT;
