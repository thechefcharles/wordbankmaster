-- Push notifications wiring (2026-07-17).
-- Hooks the EXISTING _notify() funnel to APNs: every notification type (current + future)
-- gets push for free, with a per-type policy + per-user category prefs. No feature code touched.
--
-- SECURITY NOTE: Postgres grants EXECUTE to PUBLIC by default (see the 2026-07-16 audit —
-- that's how internal helpers got exposed). So every function below is explicitly REVOKEd
-- from PUBLIC and granted only where needed; `_`-prefixed helpers stay un-granted.

-- ── 1. Locked-down config store (hook secret + function URL). No RLS policy = no API access;
--       only SECURITY DEFINER functions can read it.
CREATE TABLE IF NOT EXISTS public.app_secrets (
  key   text PRIMARY KEY,
  value text NOT NULL
);
ALTER TABLE public.app_secrets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_secrets FROM PUBLIC, anon, authenticated;

-- ── 2. Per-user push preferences + timezone (for quiet hours / local-time retention sends).
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS push_prefs jsonb NOT NULL
    DEFAULT '{"challenges":true,"social":true,"daily":true,"streak":true}'::jsonb,
  ADD COLUMN IF NOT EXISTS timezone text;

-- ── 3. Push policy: which _notify types actually push, and under which category.
--       NULL = in-app only (never push). Default-deny: unknown types don't push.
CREATE OR REPLACE FUNCTION public.push_policy(p_type text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_type
    -- Tier 1 — the async game is broken without these
    WHEN 'challenge_incoming'  THEN 'challenges'
    WHEN 'challenge_your_turn' THEN 'challenges'
    WHEN 'challenge_result'    THEN 'challenges'
    WHEN 'challenge_expiring'  THEN 'challenges'
    -- Tier 2 — social / fun
    WHEN 'sabotaged'           THEN 'challenges'
    WHEN 'friend_request'      THEN 'social'
    WHEN 'friend_accepted'     THEN 'social'
    WHEN 'group_added'         THEN 'social'
    WHEN 'group_join'          THEN 'social'
    -- Retention (cron-sent, still respects prefs)
    WHEN 'daily_reminder'      THEN 'daily'
    WHEN 'streak_at_risk'      THEN 'streak'
    -- Tier 3 / unknown -> NULL = in-app only (powerup_used, decline_match, ownership, ...)
    ELSE NULL
  END;
$$;
REVOKE EXECUTE ON FUNCTION public.push_policy(text) FROM PUBLIC;

-- ── 4. Register / unregister a device token (writes are revoked on the table, so this
--       SECURITY DEFINER RPC is the only path; it keys strictly on auth.uid()).
CREATE OR REPLACE FUNCTION public.register_device_token(
  p_token text, p_platform text DEFAULT 'ios', p_env text DEFAULT 'sandbox'
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'auth'); END IF;
  IF p_token IS NULL OR length(p_token) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'bad_token');
  END IF;
  INSERT INTO public.device_tokens (user_id, token, platform, env, updated_at)
  VALUES (v_uid, p_token, COALESCE(p_platform, 'ios'), COALESCE(p_env, 'sandbox'), now())
  ON CONFLICT (user_id, token)
    DO UPDATE SET updated_at = now(), platform = EXCLUDED.platform, env = EXCLUDED.env;
  RETURN jsonb_build_object('ok', true);
END; $$;
REVOKE EXECUTE ON FUNCTION public.register_device_token(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_device_token(text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.unregister_device_token(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'auth'); END IF;
  DELETE FROM public.device_tokens WHERE user_id = v_uid AND token = p_token;
  RETURN jsonb_build_object('ok', true);
END; $$;
REVOKE EXECUTE ON FUNCTION public.unregister_device_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.unregister_device_token(text) TO authenticated;

-- ── 5. Let a user set their own push category prefs.
CREATE OR REPLACE FUNCTION public.set_push_prefs(p_prefs jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'auth'); END IF;
  UPDATE public.profiles
     SET push_prefs = COALESCE(push_prefs, '{}'::jsonb) || COALESCE(p_prefs, '{}'::jsonb)
   WHERE id = v_uid;
  RETURN jsonb_build_object('ok', true);
END; $$;
REVOKE EXECUTE ON FUNCTION public.set_push_prefs(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_push_prefs(jsonb) TO authenticated;

-- ── 6. The hook: every notifications INSERT -> (policy + prefs) -> async push.
--       CRITICAL: this must never break the inserting transaction (that would break gameplay),
--       so the whole body is exception-guarded and pg_net is async by design.
CREATE OR REPLACE FUNCTION public._push_on_notify()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_cat text; v_prefs jsonb; v_url text; v_secret text; v_badge int;
BEGIN
  v_cat := public.push_policy(NEW.type);
  IF v_cat IS NULL THEN RETURN NEW; END IF;                    -- in-app only

  SELECT COALESCE(push_prefs, '{}'::jsonb) INTO v_prefs FROM public.profiles WHERE id = NEW.user_id;
  IF COALESCE((v_prefs ->> v_cat)::boolean, true) IS NOT TRUE THEN RETURN NEW; END IF;  -- muted

  SELECT value INTO v_url    FROM public.app_secrets WHERE key = 'push_fn_url';
  SELECT value INTO v_secret FROM public.app_secrets WHERE key = 'push_hook_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN RETURN NEW; END IF;

  SELECT count(*) INTO v_badge
    FROM public.notifications WHERE user_id = NEW.user_id AND read_at IS NULL;

  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object('content-type', 'application/json', 'x-push-secret', v_secret),
    body    := jsonb_build_object(
                 'user_id', NEW.user_id,
                 'title',   NEW.title,
                 'body',    NEW.body,
                 'data',    COALESCE(NEW.data, '{}'::jsonb),
                 'badge',   v_badge
               )
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Push is best-effort: never let it fail a game action.
  RETURN NEW;
END; $$;
REVOKE EXECUTE ON FUNCTION public._push_on_notify() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_push_on_notify ON public.notifications;
CREATE TRIGGER trg_push_on_notify
  AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public._push_on_notify();
