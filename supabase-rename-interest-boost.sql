-- ============================================================================
-- Rename the daily 💥 boost power-up: "Bounty Boost" → "Interest Boost".
-- The Daily deposit multiplier is now spoken of as "Interest" (+%) everywhere
-- (the win-streak interest was dropped in PR #517; only these Store-bought boosts
-- multiply the deposit). The id stays `bounty_boost` — display name only.
-- Jackpot keeps its name. get_powerups()/get_shop() surface `name` to the client.
-- ============================================================================
BEGIN;

UPDATE public.powerups SET name = 'Interest Boost' WHERE id = 'bounty_boost';

COMMIT;
