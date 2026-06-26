-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Avatars — DiceBear avataaars dress-up, built on the cosmetics system    ║
-- ╚══════════════════════════════════════════════════════════════════════╝
-- Avatar cosmetics reuse the existing `cosmetics` + `user_cosmetics` tables
-- (kind = 'av_<category>', value = the avataaars option). The equipped look is
-- a composite, stored as profiles.avatar (jsonb). Free options (colors, basic
-- hair/clothes) live client-side; only the items below cost Cash.

BEGIN;

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar jsonb;

-- widen the kind check to allow avatar cosmetic kinds (av_*)
ALTER TABLE public.cosmetics DROP CONSTRAINT IF EXISTS cosmetics_kind_check;
ALTER TABLE public.cosmetics ADD CONSTRAINT cosmetics_kind_check
  CHECK (kind = ANY (ARRAY['title'::text, 'color'::text]) OR kind LIKE 'av\_%');

-- ── Paid catalog (kind av_top / av_clothing / av_accessories / av_facialHair) ──
INSERT INTO public.cosmetics (id, kind, label, value, price, sort) VALUES
  ('av_top_hat',          'av_top',        'Fedora',            'hat',            600, 100),
  ('av_top_beanie',       'av_top',        'Beanie',            'winterHat1',     400, 101),
  ('av_top_bobble',       'av_top',        'Bobble Hat',        'winterHat03',    500, 102),
  ('av_top_bighair',      'av_top',        'Big Hair',          'bigHair',        500, 110),
  ('av_top_fro',          'av_top',        'Afro',              'fro',            400, 111),
  ('av_top_dreads',       'av_top',        'Dreads',            'dreads',         500, 112),
  ('av_top_curly',        'av_top',        'Curly',             'curly',          300, 113),
  ('av_top_miawallace',   'av_top',        'Long Bob',          'miaWallace',     400, 114),
  ('av_top_frida',        'av_top',        'Frida',             'frida',          600, 115),
  ('av_cloth_hoodie',     'av_clothing',   'Hoodie',            'hoodie',         400, 200),
  ('av_cloth_blazer',     'av_clothing',   'Blazer',            'blazerAndShirt', 800, 201),
  ('av_cloth_blazersw',   'av_clothing',   'Blazer & Sweater',  'blazerAndSweater',900,202),
  ('av_cloth_collar',     'av_clothing',   'Collar & Sweater',  'collarAndSweater',600,203),
  ('av_cloth_overall',    'av_clothing',   'Overalls',          'overall',        500, 204),
  ('av_cloth_graphic',    'av_clothing',   'Graphic Tee',       'graphicShirt',   300, 205),
  ('av_acc_round',        'av_accessories','Round Glasses',     'round',          300, 300),
  ('av_acc_sunglasses',   'av_accessories','Sunglasses',        'sunglasses',     500, 301),
  ('av_acc_wayfarers',    'av_accessories','Wayfarers',         'wayfarers',      500, 302),
  ('av_acc_specs',        'av_accessories','Specs',             'prescription01', 300, 303),
  ('av_acc_kurt',         'av_accessories','Kurt Glasses',      'kurt',           400, 304),
  ('av_acc_eyepatch',     'av_accessories','Eyepatch',          'eyepatch',       700, 305),
  ('av_beard_light',      'av_facialHair', 'Light Beard',       'beardLight',     300, 400),
  ('av_beard_medium',     'av_facialHair', 'Beard',             'beardMedium',    400, 401),
  ('av_beard_majestic',   'av_facialHair', 'Majestic Beard',    'beardMajestic',  700, 402),
  ('av_must_fancy',       'av_facialHair', 'Fancy Moustache',   'moustacheFancy', 400, 403),
  ('av_must_magnum',      'av_facialHair', 'Magnum Moustache',  'moustacheMagnum',400, 404)
ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label, value=EXCLUDED.value, price=EXCLUDED.price, sort=EXCLUDED.sort;

-- ── buy_cosmetic: don't let avatar kinds mis-equip into equipped_color ──
CREATE OR REPLACE FUNCTION public.buy_cosmetic(p_id text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid UUID := auth.uid(); v_price BIGINT; v_kind TEXT; v_bank BIGINT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  SELECT price, kind INTO v_price, v_kind FROM public.cosmetics WHERE id = p_id;
  IF v_price IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','no_item'); END IF;
  IF EXISTS (SELECT 1 FROM public.user_cosmetics WHERE user_id = v_uid AND cosmetic_id = p_id) THEN
    RETURN jsonb_build_object('ok',false,'reason','owned'); END IF;
  PERFORM public._ensure_bank(v_uid);
  SELECT bank INTO v_bank FROM public.profiles WHERE id = v_uid;
  IF v_bank < v_price THEN RETURN jsonb_build_object('ok',false,'reason','insufficient'); END IF;
  PERFORM public._bank_credit(v_uid, -v_price, 'cosmetic_buy');
  INSERT INTO public.user_cosmetics(user_id, cosmetic_id) VALUES (v_uid, p_id) ON CONFLICT DO NOTHING;
  -- auto-equip only the single-slot kinds; avatar items are equipped via set_avatar
  IF v_kind = 'title' THEN UPDATE public.profiles SET equipped_title = p_id WHERE id = v_uid;
  ELSIF v_kind = 'color' THEN UPDATE public.profiles SET equipped_color = p_id WHERE id = v_uid;
  END IF;
  RETURN jsonb_build_object('ok',true);
END; $function$;

-- ── set_avatar: save the composite look, rejecting any unowned paid item ──
CREATE OR REPLACE FUNCTION public.set_avatar(p_config jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','auth'); END IF;
  IF jsonb_typeof(p_config) <> 'object' THEN RETURN jsonb_build_object('ok',false,'reason','bad'); END IF;
  -- any paid avatar cosmetic whose value the config equips, that the user doesn't own → reject
  IF EXISTS (
    SELECT 1 FROM public.cosmetics c
    WHERE c.kind LIKE 'av\_%'
      AND c.value = (p_config ->> substring(c.kind from 4))
      AND NOT EXISTS (SELECT 1 FROM public.user_cosmetics uc WHERE uc.user_id = v_uid AND uc.cosmetic_id = c.id)
  ) THEN
    RETURN jsonb_build_object('ok',false,'reason','locked');
  END IF;
  UPDATE public.profiles SET avatar = p_config WHERE id = v_uid;
  RETURN jsonb_build_object('ok',true);
END; $function$;

-- ── get_my_avatar: my equipped config + the avatar cosmetic ids I own ──
CREATE OR REPLACE FUNCTION public.get_my_avatar()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('config', NULL, 'owned', '[]'::jsonb); END IF;
  RETURN jsonb_build_object(
    'config', (SELECT avatar FROM public.profiles WHERE id = v_uid),
    'owned', COALESCE((SELECT jsonb_agg(uc.cosmetic_id)
                       FROM public.user_cosmetics uc JOIN public.cosmetics c ON c.id = uc.cosmetic_id
                       WHERE uc.user_id = v_uid AND c.kind LIKE 'av\_%'), '[]'::jsonb)
  );
END; $function$;

REVOKE ALL ON FUNCTION public.set_avatar(jsonb), public.get_my_avatar() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.set_avatar(jsonb), public.get_my_avatar() TO authenticated;

COMMIT;

-- Also applied separately: get_public_profile now returns 'avatar' (p.avatar) so
-- other players' avatars render on their public profile. (Injected the
-- 'avatar', p.avatar pair after the existing 'username', p.username pair.)
