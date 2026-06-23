-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Economy v3.2 — bigger bounties + cheaper letters (so money carries weight) ║
-- ║  (migration: economy_v3_2_bounty_and_price_rebalance — applied via MCP)     ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- Goal (owner): a solve should clearly pay; "spend less" should bite. The lever is
-- the BOUNTY MULTIPLIER (k), not the price cut — under a derived bounty, halving
-- letters shrinks bounty AND spend equally (same ratio). So we BUMP k and apply a
-- light price trim for bankroll stretch / fewer broke-timers.
--
--   net = (k − f) × full_reveal      (f = fraction of letters skill made you buy)
--
-- Changes:
--   • letter_cost(): −25%, rounded to clean $10s. Cheapest letter $30 → $20.
--       Q20 W40 E100 R90 T90 Y50 U60 I80 O70 P60 A100 S90 D60 F50 G50 H50
--       J20 K40 L60 Z30 X30 C60 V40 B50 N80 M50
--   • _daily_reward(): k 0.70 → 1.20. Daily is the forgiving paycheck — bounty >
--       full-reveal, so a solve ALWAYS nets positive (you still lose by NOT solving).
--   • _climb_bounty(): k 0.65 → 0.85. Climb is the wealth engine — bounty <
--       full-reveal, so brute-forcing a full reveal LOSES; efficiency is the skill.
--       (Climb still multiplies by heat on top.)
--   • Broke floor 30 → 20 in the two resolvers that hardcoded it
--       (_freeplay_resolve, _makeup_resolve_and_return) — cheapest letter is now $20.
--   • NOT touched (already dynamic via letter_cost / client isBroke, so auto-adapt):
--       main Daily loss (client broke-timer → daily_fold), _arcade_resolve,
--       arcade_buy_letter, climb broke check. Reveal stays a flat $150 premium.
--       Arcade/Free Play start bankrolls unchanged → cheaper letters = the intended
--       "bankroll stretches further" effect.
--
-- Client mirror (must stay in sync with letter_cost): LETTER_COSTS in
--   src/lib/stores/GameStore.js, src/routes/+page.svelte, and letterCosts in
--   src/lib/components/Keyboard.svelte.
--
-- Verified (live, new prices): "Let the Cat Out of the Bag" full-reveal $740 →
--   Daily bounty $890 (>740: buy everything, still +$150) ·
--   Climb bounty $630 (<740: full reveal loses −$110). Modes now feel distinct.

CREATE OR REPLACE FUNCTION public.letter_cost(p_letter TEXT)
RETURNS INT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE upper(p_letter)
    WHEN 'Q' THEN 20  WHEN 'W' THEN 40  WHEN 'E' THEN 100 WHEN 'R' THEN 90
    WHEN 'T' THEN 90  WHEN 'Y' THEN 50  WHEN 'U' THEN 60  WHEN 'I' THEN 80
    WHEN 'O' THEN 70  WHEN 'P' THEN 60  WHEN 'A' THEN 100 WHEN 'S' THEN 90
    WHEN 'D' THEN 60  WHEN 'F' THEN 50  WHEN 'G' THEN 50  WHEN 'H' THEN 50
    WHEN 'J' THEN 20  WHEN 'K' THEN 40  WHEN 'L' THEN 60  WHEN 'Z' THEN 30
    WHEN 'X' THEN 30  WHEN 'C' THEN 60  WHEN 'V' THEN 40  WHEN 'B' THEN 50
    WHEN 'N' THEN 80  WHEN 'M' THEN 50  ELSE NULL END;
$$;

CREATE OR REPLACE FUNCTION public._daily_reward(p_pid uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER AS $function$
  SELECT GREATEST(100, (round(1.20 * COALESCE(SUM(public.letter_cost(t.ch)), 0) / 10.0) * 10)::int)
  FROM (
    SELECT DISTINCT substr(upper(dp.phrase), g.i + 1, 1) AS ch
    FROM public.daily_puzzles dp, generate_series(0, length(dp.phrase) - 1) g(i)
    WHERE dp.id = p_pid AND substr(upper(dp.phrase), g.i + 1, 1) ~ '[A-Z]'
  ) t;
$function$;

CREATE OR REPLACE FUNCTION public._climb_bounty(p_pid uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER AS $function$
  SELECT (round(0.85 * COALESCE(SUM(public.letter_cost(t.ch)), 0) / 10.0) * 10)::int
  FROM (
    SELECT DISTINCT substr(upper(dp.phrase), g.i + 1, 1) AS ch
    FROM public.daily_puzzles dp, generate_series(0, length(dp.phrase) - 1) g(i)
    WHERE dp.id = p_pid AND substr(upper(dp.phrase), g.i + 1, 1) ~ '[A-Z]'
  ) t;
$function$;

-- _freeplay_resolve / _makeup_resolve_and_return: broke floor 30 → 20 (bodies otherwise
-- unchanged from their prior definitions; see git history for the full functions).
