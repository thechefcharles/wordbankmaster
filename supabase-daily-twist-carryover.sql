-- 🎟️ Daily Twist cross-mode carry-over  (applied via MCP migration `daily_twist_carryover`)
--
-- Solving the Daily WITHOUT using the Twist already pays a ×1.5 bounty. Now it also
-- BANKS the Twist as a usable power-up in Cash Game & Challenges.
--
-- Design (low-risk): map each Daily Twist (the weekday modifier from _daily_modifier())
-- to an existing ACTIVE cross-mode power-up id, then grant it into the v2 'cash' pool
-- via _award_powerup(uid, id, 'cash'). The client already surfaces 'cash'-pool power-ups
-- in Cash Game (ownedClimb) and Challenges (ownedSelf) through get_powerups(), so no
-- money-handling RPCs change and the grant is usable immediately.
--
-- Grant fires only on WIN + Twist-not-used (ties it to the same reward as ×1.5, and
-- avoids fold-farming). Hooked inside _finalize_daily's p_won branch, reusing the
-- v_used (daily_sessions.twist_used) it already reads for _daily_reward_eff.
--
-- Twist → power-up map:
--   free_vowel     -> free_vowel     (exact)
--   vowel_vision   -> vowel_vision   (exact)
--   discount       -> half_off
--   consonant_sale -> half_off
--   flat_rate      -> extra_hint
--   head_start     -> free_reveal
--   insured        -> last_letters
--
-- See the migration for the full _finalize_daily body; the mapping helper:
CREATE OR REPLACE FUNCTION public._twist_powerup(p_mod text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_mod
    WHEN 'free_vowel'     THEN 'free_vowel'
    WHEN 'vowel_vision'   THEN 'vowel_vision'
    WHEN 'discount'       THEN 'half_off'
    WHEN 'consonant_sale' THEN 'half_off'
    WHEN 'flat_rate'      THEN 'extra_hint'
    WHEN 'head_start'     THEN 'free_reveal'
    WHEN 'insured'        THEN 'last_letters'
    ELSE NULL
  END;
$$;
REVOKE EXECUTE ON FUNCTION public._twist_powerup(text) FROM anon, authenticated, PUBLIC;

-- Inside _finalize_daily, in the `IF p_won THEN` branch (after the flawless badge):
--   IF NOT COALESCE(v_used, false) THEN
--     v_grant := public._twist_powerup(public._daily_modifier());
--     IF v_grant IS NOT NULL THEN PERFORM public._award_powerup(p_uid, v_grant, 'cash'); END IF;
--   END IF;
