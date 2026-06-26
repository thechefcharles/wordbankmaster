-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Challenge: attribute sabotage debuffs (who hit you) for the on-screen tap   ║
-- ║  (migration: match_debuff_by_2026_06 — applied via psql)                    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- The debuff banner is now tappable and explains each active debuff + who applied
-- it. challenge_participants.debuffs only stored effect keys, so we add a debuff_by
-- map {effect -> applier_uid}. (No reset needed: it's only ever read for effects
-- that are currently in `debuffs`, and a re-application overwrites the entry.)

ALTER TABLE public.challenge_participants ADD COLUMN IF NOT EXISTS debuff_by jsonb NOT NULL DEFAULT '{}'::jsonb;

-- record who applied each persistent debuff
CREATE OR REPLACE FUNCTION public.match_sabotage(p_id uuid, p_target uuid, p_powerup text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid UUID := auth.uid(); m public.challenge_matches; v_debuff TEXT; v_name TEXT; v_qty INT; v_tstate TEXT;
  tcp public.challenge_participants; v_phrase TEXT; v_lockletter TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'match_sabotage: not authenticated'; END IF;
  SELECT * INTO m FROM public.challenge_matches WHERE id = p_id;
  IF NOT FOUND OR NOT COALESCE(m.items_allowed,false) THEN RETURN public._match_board(p_id, v_uid); END IF;
  IF p_target = v_uid THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT effect_key, name INTO v_debuff, v_name FROM public.powerups WHERE id = p_powerup AND kind = 'sabotage' AND active;
  IF v_debuff IS NULL THEN RETURN public._match_board(p_id, v_uid); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid AND state = 'active') THEN
    RETURN public._match_board(p_id, v_uid); END IF;
  SELECT * INTO tcp FROM public.challenge_participants WHERE match_id = p_id AND user_id = p_target;
  IF tcp.user_id IS NULL OR tcp.state NOT IN ('active','invited') THEN RETURN public._match_board(p_id, v_uid); END IF;
  SELECT qty INTO v_qty FROM public.user_powerups_v2 WHERE user_id = v_uid AND powerup_id = p_powerup AND pool = 'cash';
  IF COALESCE(v_qty,0) <= 0 THEN RETURN public._match_board(p_id, v_uid); END IF;
  UPDATE public.user_powerups_v2 SET qty = qty - 1 WHERE user_id = v_uid AND powerup_id = p_powerup AND pool = 'cash';

  IF v_debuff = 'lock' THEN
    SELECT upper(phrase) INTO v_phrase FROM public.daily_puzzles WHERE id = public._match_pid(p_id, tcp.position);
    SELECT substr(v_phrase, p+1, 1) INTO v_lockletter FROM unnest(tcp.revealed_positions) p
      WHERE substr(v_phrase, p+1, 1) ~ '[A-Z]' ORDER BY random() LIMIT 1;
    IF v_lockletter IS NOT NULL THEN
      UPDATE public.challenge_participants SET revealed_positions =
        ARRAY(SELECT DISTINCT p FROM unnest(revealed_positions) p WHERE substr(v_phrase, p+1, 1) <> v_lockletter ORDER BY 1)
      WHERE match_id = p_id AND user_id = p_target;
    END IF;
  ELSE
    UPDATE public.challenge_participants SET
      debuffs = (SELECT ARRAY(SELECT DISTINCT unnest(COALESCE(debuffs,'{}') || ARRAY[v_debuff]))),
      debuff_by = COALESCE(debuff_by, '{}'::jsonb) || jsonb_build_object(v_debuff, v_uid::text)
    WHERE match_id = p_id AND user_id = p_target;
  END IF;

  PERFORM public._notify(p_target, 'sabotaged', '💥 You got hit!',
    public._display_name(v_uid) || ' hit you with ' || COALESCE(v_name,'a sabotage') ||
    CASE v_debuff WHEN 'tax' THEN ' — your letters cost +50%' WHEN 'fog' THEN ' — your clue is hidden'
      WHEN 'toll' THEN ' — your next letter costs 3×' WHEN 'vowel_block' THEN ' — your vowels cost 3×'
      WHEN 'lock' THEN COALESCE(' — they wiped your ' || v_lockletter || 's', ' — a revealed letter is gone') ELSE '' END,
    jsonb_build_object('match_id', p_id));
  RETURN public._match_board(p_id, v_uid);
END; $function$;

-- the caller's active debuffs, each with WHO applied it (for the tappable banner)
CREATE OR REPLACE FUNCTION public.get_match_debuffs(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_uid uuid := auth.uid(); cp public.challenge_participants; v jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  SELECT * INTO cp FROM public.challenge_participants WHERE match_id = p_id AND user_id = v_uid;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'effect', d,
    'by', CASE WHEN cp.debuff_by ? d THEN public._display_name((cp.debuff_by->>d)::uuid) ELSE NULL END
  )), '[]'::jsonb) INTO v
  FROM unnest(COALESCE(cp.debuffs, '{}'::text[])) d;
  RETURN v;
END; $function$;
