-- ============================================================
-- First-party product analytics (applied to prod).
-- Clients call log_event() (SECURITY DEFINER) which stamps user_id from
-- auth.uid() server-side so it can't be spoofed. The events table is RLS-locked
-- (no client SELECT/INSERT policies); read it via the service role / dashboard.
-- Client helper: src/lib/analytics.js  →  track(name, props)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  session_id TEXT,
  platform TEXT,          -- web | pwa | ios
  name TEXT NOT NULL,
  props JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS idx_events_name_time ON public.events (name, created_at);
CREATE INDEX IF NOT EXISTS idx_events_user_time ON public.events (user_id, created_at);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.log_event(
  p_name TEXT, p_props JSONB DEFAULT '{}', p_session TEXT DEFAULT NULL, p_platform TEXT DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF p_name IS NULL OR length(p_name) = 0 OR length(p_name) > 64 THEN RETURN; END IF;
  INSERT INTO public.events (user_id, session_id, platform, name, props)
  VALUES (auth.uid(), left(p_session, 64), left(p_platform, 16), p_name,
          COALESCE(p_props, '{}'::jsonb));
END; $$;
GRANT EXECUTE ON FUNCTION public.log_event(TEXT, JSONB, TEXT, TEXT) TO anon, authenticated;

-- ---- Handy KPI queries (run via service role) ------------------------------
-- Events emitted by the client: app_open, signup, login, daily_start,
-- daily_result {won,bankroll}, arcade_start, arcade_solve {position,payout,earned},
-- arcade_over {peak,solved}, freeplay_start {category}.
--
-- Daily active users (by day):
--   SELECT created_at::date d, count(DISTINCT user_id) dau
--   FROM public.events WHERE user_id IS NOT NULL GROUP BY 1 ORDER BY 1;
--
-- Signups per day:
--   SELECT created_at::date d, count(*) FROM public.events
--   WHERE name='signup' GROUP BY 1 ORDER BY 1;
--
-- Daily completion (started vs finished, last 7 days):
--   SELECT count(*) FILTER (WHERE name='daily_start')  AS starts,
--          count(*) FILTER (WHERE name='daily_result') AS finishes,
--          count(*) FILTER (WHERE name='daily_result' AND (props->>'won')::bool) AS wins
--   FROM public.events WHERE created_at > now() - interval '7 days';
--
-- D1 retention (signed up on a day, came back the next):
--   WITH s AS (SELECT user_id, min(created_at)::date d0 FROM public.events
--              WHERE name='signup' GROUP BY 1)
--   SELECT s.d0, count(*) signups,
--     count(*) FILTER (WHERE EXISTS (
--       SELECT 1 FROM public.events e WHERE e.user_id=s.user_id
--       AND e.created_at::date = s.d0 + 1)) AS returned_d1
--   FROM s GROUP BY s.d0 ORDER BY s.d0;
