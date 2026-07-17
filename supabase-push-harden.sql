-- Harden push function grants (2026-07-17).
--
-- WHY: REVOKE ... FROM PUBLIC is NOT sufficient on this project. Supabase ships
--   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
-- so every newly created function also gets a DIRECT grant to anon. Revoking PUBLIC leaves
-- that direct grant intact — which is why all six push functions were anon-executable despite
-- the REVOKEs in supabase-push-wiring.sql. Same root cause as the 2026-07-16 Tier 0 audit.
--
-- No live exploit: all of these key on auth.uid(), which is NULL for anon, so they no-op.
-- This is defense in depth — the auth.uid() guard should not be the ONLY thing standing
-- between anon and these functions.
--
-- RULE FOR FUTURE FUNCTIONS: always REVOKE FROM PUBLIC, anon (and authenticated for
-- internal helpers), then GRANT back only what the client genuinely calls.

-- ── Client-callable RPCs: authenticated only, never anon.
REVOKE EXECUTE ON FUNCTION public.register_device_token(text, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.unregister_device_token(text)           FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_push_prefs(jsonb)                   FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_timezone(text)                      FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.register_device_token(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_device_token(text)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_push_prefs(jsonb)                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_timezone(text)                      TO authenticated;

-- ── Internal helpers: no client role should reach these at all.
REVOKE EXECUTE ON FUNCTION public.push_policy(text)   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._push_on_notify()   FROM PUBLIC, anon, authenticated;
