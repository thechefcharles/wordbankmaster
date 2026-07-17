-- Retention engine (2026-07-17).
--
-- Runs hourly. Reuses the existing funnel: this only INSERTs into `notifications`, and the
-- trg_push_on_notify trigger does policy + prefs + pg_net + APNs. So retention needs zero
-- new delivery code and automatically inherits per-category prefs.
--
-- DESIGN NOTES
--  * Hourly, not per-minute: every send targets a specific LOCAL hour, so we only need to
--    catch each user's clock once per hour.
--  * Timezone is REQUIRED. A user with no timezone gets nothing rather than a 3am push —
--    profiles.timezone backfills as people open the app (see set_timezone).
--  * Quiet hours 22:00-08:00 local, enforced once at the top for every kind.
--  * Device token REQUIRED: retention exists to pull people BACK. Without a token these
--    would be invisible in-app rows that just clutter the inbox.
--  * push_log dedupes per (user, kind, LOCAL day) — without it an hourly cron re-sends
--    every hour the condition holds.
--  * Exception-guarded per user: one bad row must never abort the whole tick.

CREATE OR REPLACE FUNCTION public._retention_tick()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  r          record;
  v_local    timestamp;
  v_hour     int;
  v_day      date;
  v_rows     int;
  n_streak   int := 0;
  n_daily    int := 0;
  n_expiring int := 0;
BEGIN
  ------------------------------------------------------------------
  -- 1. Streak at risk + 2. Daily reminder
  ------------------------------------------------------------------
  FOR r IN
    SELECT p.id, p.timezone, p.push_prefs, p.streak_freezes,
           COALESCE(p.current_daily_play_streak, 0) AS streak,
           p.last_daily_play_date
      FROM public.profiles p
     WHERE p.timezone IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.device_tokens d WHERE d.user_id = p.id)
  LOOP
    BEGIN
      v_local := now() AT TIME ZONE r.timezone;
      v_hour  := extract(hour from v_local)::int;
      v_day   := v_local::date;

      -- Quiet hours — never wake anyone up.
      CONTINUE WHEN v_hour >= 22 OR v_hour < 8;
      -- Already played today: nothing to nudge about.
      CONTINUE WHEN r.last_daily_play_date IS NOT NULL AND r.last_daily_play_date >= v_day;

      -- 1. STREAK AT RISK — ~3h before local midnight. Loss aversion; the strongest hook.
      IF r.streak >= 2 AND v_hour = 21 THEN
        IF COALESCE((r.push_prefs ->> 'streak')::boolean, true) THEN
          INSERT INTO public.push_log (user_id, kind, local_day)
          VALUES (r.id, 'streak_at_risk', v_day) ON CONFLICT DO NOTHING;
          GET DIAGNOSTICS v_rows = ROW_COUNT;
          IF v_rows > 0 THEN
            INSERT INTO public.notifications (user_id, type, title, body, data)
            VALUES (
              r.id, 'streak_at_risk',
              r.streak || ' day streak on the line',
              CASE WHEN COALESCE(r.streak_freezes, 0) > 0
                   THEN 'Play today to keep it — or spend a streak freeze.'
                   ELSE 'Play today''s puzzle before midnight to keep it alive.' END,
              jsonb_build_object('route', 'daily')
            );
            n_streak := n_streak + 1;
          END IF;
        END IF;

      -- 2. DAILY REMINDER — 18:00 local, only for people the streak hook doesn't cover.
      ELSIF r.streak < 2 AND v_hour = 18 THEN
        IF COALESCE((r.push_prefs ->> 'daily')::boolean, true) THEN
          INSERT INTO public.push_log (user_id, kind, local_day)
          VALUES (r.id, 'daily_reminder', v_day) ON CONFLICT DO NOTHING;
          GET DIAGNOSTICS v_rows = ROW_COUNT;
          IF v_rows > 0 THEN
            INSERT INTO public.notifications (user_id, type, title, body, data)
            VALUES (
              r.id, 'daily_reminder',
              'Today''s puzzle is waiting',
              'A fresh Daily is up. Solve it before midnight.',
              jsonb_build_object('route', 'daily')
            );
            n_daily := n_daily + 1;
          END IF;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      CONTINUE; -- one bad profile must not kill the tick
    END;
  END LOOP;

  ------------------------------------------------------------------
  -- 3. Challenge expiring — play or forfeit.
  ------------------------------------------------------------------
  FOR r IN
    SELECT cp.user_id, m.id AS match_id, m.settles_at, p.timezone, p.push_prefs
      FROM public.challenge_matches m
      JOIN public.challenge_participants cp ON cp.match_id = m.id
      JOIN public.profiles p                ON p.id = cp.user_id
     WHERE m.status = 'open'
       AND m.settles_at > now()
       AND m.settles_at <= now() + interval '2 hours'
       AND cp.finished_at IS NULL
       AND p.timezone IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.device_tokens d WHERE d.user_id = cp.user_id)
  LOOP
    BEGIN
      v_local := now() AT TIME ZONE r.timezone;
      v_hour  := extract(hour from v_local)::int;
      v_day   := v_local::date;
      CONTINUE WHEN v_hour >= 22 OR v_hour < 8;
      CONTINUE WHEN NOT COALESCE((r.push_prefs ->> 'challenges')::boolean, true);

      -- Dedupe per match (not per day) — two matches can expire on the same day.
      INSERT INTO public.push_log (user_id, kind, local_day)
      VALUES (r.user_id, 'challenge_expiring:' || r.match_id, v_day) ON CONFLICT DO NOTHING;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows > 0 THEN
        INSERT INTO public.notifications (user_id, type, title, body, data)
        VALUES (
          r.user_id, 'challenge_expiring',
          'Your challenge is about to expire',
          'Finish your puzzles now or you''ll forfeit.',
          jsonb_build_object('match_id', r.match_id)
        );
        n_expiring := n_expiring + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      CONTINUE;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'streak_at_risk', n_streak, 'daily_reminder', n_daily, 'challenge_expiring', n_expiring
  );
END; $$;

-- Internal only — cron calls it as the job owner. No client role should reach it.
REVOKE EXECUTE ON FUNCTION public._retention_tick() FROM PUBLIC, anon, authenticated;

-- Hourly, on the hour. Each send targets a specific local hour, so hourly is enough.
SELECT cron.unschedule('retention-tick')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'retention-tick');
SELECT cron.schedule('retention-tick', '0 * * * *', 'SELECT public._retention_tick();');

-- Keep the dedupe log from growing forever; 60 days is well past any decision value.
SELECT cron.unschedule('push-log-prune')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'push-log-prune');
SELECT cron.schedule('push-log-prune', '17 4 * * *',
  $c$DELETE FROM public.push_log WHERE sent_at < now() - interval '60 days'$c$);
