-- ============================================================
-- Daily Quests (applied to prod). 3 quests/day, SAME for everyone (deterministic
-- by date, like the daily modifier). Progress is computed from the events table
-- (server-stamped user_id) so there are NO game-engine changes. Finishing all 3
-- lets the player claim a streak freeze (capped at 3, earned-through-play =
-- sweepstakes-safe). Client: src/lib/stores/statsStore.js getDailyQuests/claim,
-- src/routes/quests/+page.svelte, menu card in +page.svelte.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.quest_claims (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  day DATE NOT NULL,
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, day)
);
ALTER TABLE public.quest_claims ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.get_daily_quests()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_quests JSONB; v_all BOOL; v_claimed BOOL;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  WITH pool(id, emoji, label, metric, target) AS (VALUES
    ('daily_win','🎯','Win today''s Daily','daily_win',1),
    ('arcade_3','🕹️','Solve 3 Arcade puzzles','arcade_solve',3),
    ('arcade_5','🕹️','Solve 5 Arcade puzzles','arcade_solve',5),
    ('arcade_powerup','⚡','Earn a power-up in Arcade','arcade_powerup',1),
    ('freeplay','🎲','Play a Free Play puzzle','freeplay_play',1),
    ('arcade_run','🏦','Start an Arcade run','arcade_start',1)
  ),
  ranked AS (
    SELECT *, md5(CURRENT_DATE::text || id) AS h,
      row_number() OVER (PARTITION BY metric ORDER BY md5(CURRENT_DATE::text || id)) AS rn
    FROM pool
  ),
  chosen AS (SELECT * FROM ranked WHERE rn = 1 ORDER BY h LIMIT 3),
  prog AS (
    SELECT c.*, CASE c.metric
      WHEN 'daily_win' THEN (SELECT count(*) FROM public.events e WHERE e.user_id=v_uid AND e.name='daily_result' AND (e.props->>'won')::bool IS TRUE AND e.created_at::date=CURRENT_DATE)
      WHEN 'arcade_solve' THEN (SELECT count(*) FROM public.events e WHERE e.user_id=v_uid AND e.name='arcade_solve' AND e.created_at::date=CURRENT_DATE)
      WHEN 'arcade_powerup' THEN (SELECT count(*) FROM public.events e WHERE e.user_id=v_uid AND e.name='arcade_solve' AND COALESCE(e.props->>'earned','') NOT IN ('','null') AND e.created_at::date=CURRENT_DATE)
      WHEN 'freeplay_play' THEN (SELECT count(*) FROM public.events e WHERE e.user_id=v_uid AND e.name='freeplay_start' AND e.created_at::date=CURRENT_DATE)
      WHEN 'arcade_start' THEN (SELECT count(*) FROM public.events e WHERE e.user_id=v_uid AND e.name='arcade_start' AND e.created_at::date=CURRENT_DATE)
      ELSE 0 END AS progress
    FROM chosen c
  )
  SELECT jsonb_agg(jsonb_build_object('id',id,'emoji',emoji,'label',label,'target',target,
           'progress', LEAST(progress, target), 'done', progress >= target) ORDER BY h)
  INTO v_quests FROM prog;

  SELECT bool_and((q->>'done')::bool) FROM jsonb_array_elements(COALESCE(v_quests,'[]'::jsonb)) q INTO v_all;
  v_claimed := EXISTS (SELECT 1 FROM public.quest_claims WHERE user_id=v_uid AND day=CURRENT_DATE);

  RETURN jsonb_build_object(
    'quests', COALESCE(v_quests,'[]'::jsonb),
    'all_done', COALESCE(v_all,false),
    'reward_claimed', v_claimed,
    'resets_in_seconds', GREATEST(0, extract(epoch FROM (date_trunc('day', now() AT TIME ZONE 'utc') + interval '1 day' - (now() AT TIME ZONE 'utc')))::int)
  );
END; $$;
GRANT EXECUTE ON FUNCTION public.get_daily_quests() TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_quest_reward()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_status JSONB; v_fz INT;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  v_status := public.get_daily_quests();
  IF v_status IS NULL OR NOT (v_status->>'all_done')::bool THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_done');
  END IF;
  INSERT INTO public.quest_claims(user_id, day) VALUES (v_uid, CURRENT_DATE) ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'claimed'); END IF;
  UPDATE public.profiles SET streak_freezes = LEAST(COALESCE(streak_freezes,0) + 1, 3)
    WHERE id = v_uid RETURNING streak_freezes INTO v_fz;
  RETURN jsonb_build_object('ok', true, 'reward', 'streak_freeze', 'freezes', COALESCE(v_fz,0));
END; $$;
GRANT EXECUTE ON FUNCTION public.claim_quest_reward() TO authenticated;
