-- ============================================================
-- Bank economy Phase C: async friend challenges with a Bank wager (applied to
-- prod across two migrations: challenges_phase_c + challenges_phase_c_play).
-- Both players play the SAME puzzle (stored on the challenge); score = bankroll
-- left on solve (0 if unsolved); higher score wins the pot. Stakes escrowed up
-- front; _challenge_settle pays the winner (tie = refund). Play mirrors the daily
-- engine (reuses _daily_board + letter_cost), keyed on (challenge_id, user_id).
-- Client: statsStore create/accept/get/play wrappers; GameStore 'challenge' mode
-- (enterChallenge/startChallenge/acceptAndPlayChallenge/resumeChallenge); a
-- Challenges modal on the menu. See BANK_ECONOMY.md.
--
-- NOTE: this file documents the schema + the settlement/lifecycle functions. The
-- full play RPC bodies (challenge_buy_letter / challenge_reveal /
-- challenge_submit_guess) mirror daily_* and live in the applied migrations.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.challenges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  opponent_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  puzzle_id UUID NOT NULL REFERENCES public.daily_puzzles(id),
  wager BIGINT NOT NULL,
  mode TEXT NOT NULL DEFAULT 'score',
  status TEXT NOT NULL DEFAULT 'open',          -- open | settled | void
  creator_score INT, opponent_score INT, winner_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '48 hours',
  settled_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_ch_opp ON public.challenges(opponent_id, status);
CREATE INDEX IF NOT EXISTS idx_ch_creator ON public.challenges(creator_id, status);
ALTER TABLE public.challenges ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.challenge_plays (
  challenge_id UUID NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  bankroll INT NOT NULL DEFAULT 1000,
  guesses_remaining INT NOT NULL DEFAULT 3,
  revealed_positions INT[] NOT NULL DEFAULT '{}',
  incorrect_letters TEXT[] NOT NULL DEFAULT '{}',
  state TEXT NOT NULL DEFAULT 'active',          -- active | done
  score INT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (challenge_id, user_id)
);
ALTER TABLE public.challenge_plays ENABLE ROW LEVEL SECURITY;

-- Settle once both scores are in: higher score takes the pot (2× wager); tie refunds.
CREATE OR REPLACE FUNCTION public._challenge_settle(p_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE c public.challenges; v_winner UUID;
BEGIN
  SELECT * INTO c FROM public.challenges WHERE id = p_id FOR UPDATE;
  IF c.status <> 'open' OR c.creator_score IS NULL OR c.opponent_score IS NULL THEN RETURN; END IF;
  IF c.creator_score > c.opponent_score THEN v_winner := c.creator_id;
  ELSIF c.opponent_score > c.creator_score THEN v_winner := c.opponent_id;
  ELSE v_winner := NULL; END IF;
  IF v_winner IS NOT NULL THEN
    PERFORM public._bank_credit(v_winner, c.wager * 2, 'wager_win');
  ELSE
    PERFORM public._bank_credit(c.creator_id, c.wager, 'wager_refund');
    PERFORM public._bank_credit(c.opponent_id, c.wager, 'wager_refund');
  END IF;
  UPDATE public.challenges SET status = 'settled', winner_id = v_winner, settled_at = now() WHERE id = p_id;
END; $$;

-- create_challenge(code, category, wager) — escrows the creator, picks a puzzle from
--   the category, opens the challenge, and starts the creator's play.
-- accept_challenge(id) — escrows the opponent + starts their play (idempotent resume).
-- get_challenge(id) — masked board for the caller's play.
-- challenge_buy_letter / challenge_reveal / challenge_submit_guess — mirror daily_*,
--   keyed on (challenge_id, auth.uid()); each calls _challenge_resolve which, on solve,
--   records score (= bankroll) via _challenge_record_score and triggers _challenge_settle.
-- get_my_challenges() — inbox (incoming/awaiting/settled); lazily voids+refunds expired opens.
-- (Full bodies in the applied migrations challenges_phase_c[_play].)
