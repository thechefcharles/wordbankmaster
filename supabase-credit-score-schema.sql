-- Credit Score Phase 1 — storage + tier helper. Read-only; no loan effects yet.
-- PITR point logged before apply.
BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS credit_score       INT         NOT NULL DEFAULT 650,
  ADD COLUMN IF NOT EXISTS credit_updated_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS credit_derog_until TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.credit_history (
  id         BIGSERIAL PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  score      INT  NOT NULL,
  target     INT  NOT NULL,
  tier       TEXT NOT NULL,
  components JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_credit_history_user_time
  ON public.credit_history(user_id, at DESC);

CREATE OR REPLACE FUNCTION public._credit_tier(p_score INT)
  RETURNS TEXT LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE
    WHEN p_score >= 780 THEN 'Excellent'
    WHEN p_score >= 650 THEN 'Good'      -- neutral start (650) lands in Good, not Fair
    WHEN p_score >= 560 THEN 'Fair'
    WHEN p_score >= 400 THEN 'Poor'
    ELSE 'Bad'
  END;
$fn$;

COMMIT;
