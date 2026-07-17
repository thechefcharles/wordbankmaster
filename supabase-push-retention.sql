-- Push retention groundwork (2026-07-17).
--
-- Every retention send is local-time based (streak-at-risk ~21:00 local, daily reminder
-- 18:00 local, quiet hours 22:00-08:00 local), but profiles.timezone is NULL for all 165
-- users because nothing ever set it. This adds the capture RPC + the dedupe log, so the
-- timezone backfills naturally as people open the app and the engine has data when it lands.
--
-- SECURITY NOTE: Postgres grants EXECUTE to PUBLIC by default (see the 2026-07-16 audit).
-- Every function here is explicitly REVOKEd from PUBLIC and granted only to authenticated.

-- ── 1. Let a signed-in client record its IANA timezone (keyed on auth.uid()).
--       Validated by casting to timezone-aware time — a bad string raises, so we reject
--       rather than store junk that would later mis-time every send for that user.
CREATE OR REPLACE FUNCTION public.set_timezone(p_tz text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'auth'); END IF;
  IF p_tz IS NULL OR length(p_tz) < 3 OR length(p_tz) > 64 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'bad_tz');
  END IF;
  -- Reject anything Postgres doesn't recognise as a real zone.
  BEGIN
    PERFORM now() AT TIME ZONE p_tz;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_tz');
  END;
  UPDATE public.profiles SET timezone = p_tz WHERE id = v_uid;
  RETURN jsonb_build_object('ok', true);
END; $$;
REVOKE EXECUTE ON FUNCTION public.set_timezone(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_timezone(text) TO authenticated;

-- ── 2. Dedupe log for retention sends: at most one of each kind per user per LOCAL day.
--       Without this a cron that runs hourly would re-send every hour the condition holds.
CREATE TABLE IF NOT EXISTS public.push_log (
  user_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind      text NOT NULL,
  local_day date NOT NULL,
  sent_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, kind, local_day)
);
ALTER TABLE public.push_log ENABLE ROW LEVEL SECURITY;
-- No policies: unreachable via the API. Only SECURITY DEFINER functions touch it.
REVOKE ALL ON public.push_log FROM PUBLIC, anon, authenticated;

-- Keep it small; retention history older than 60 days has no decision value.
CREATE INDEX IF NOT EXISTS push_log_sent_at_idx ON public.push_log (sent_at);
