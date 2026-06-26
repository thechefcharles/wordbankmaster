-- Avatar v2 cosmetics: shirt designs (clothingGraphic) + premium FX (holo shirt,
-- frames, headpieces, auras). Reuses the cosmetics/user_cosmetics system; set_avatar
-- validates ownership via kind→config-key matching (substring(kind from 4)).
INSERT INTO public.cosmetics (id, kind, label, value, price, sort) VALUES
  ('av_gfx_skull',    'av_clothingGraphic','Skull Tee','skull',        200, 500),
  ('av_gfx_skullo',   'av_clothingGraphic','Skull Outline','skullOutline',200,501),
  ('av_gfx_bat',      'av_clothingGraphic','Bat Tee','bat',            200, 502),
  ('av_gfx_deer',     'av_clothingGraphic','Deer Tee','deer',          200, 503),
  ('av_gfx_pizza',    'av_clothingGraphic','Pizza Tee','pizza',        300, 504),
  ('av_gfx_hola',     'av_clothingGraphic','Hola Tee','hola',          200, 505),
  ('av_gfx_cumbia',   'av_clothingGraphic','Cumbia Tee','cumbia',      200, 506),
  ('av_gfx_resist',   'av_clothingGraphic','Resist Tee','resist',      300, 507),
  ('av_fxshirt_holo', 'av_fxShirt',  'Holographic Shirt','holo',      1500, 600),
  ('av_frame_neon',   'av_frame',    'Neon Frame','neon',             1000, 610),
  ('av_frame_gold',   'av_frame',    'Gold Frame','gold',             1200, 611),
  ('av_frame_gem',    'av_frame',    'Gem Frame','gem',               2000, 612),
  ('av_overlay_crown','av_overlay',  'Crown','crown',                 1500, 620),
  ('av_overlay_halo', 'av_overlay',  'Halo','halo',                   1000, 621),
  ('av_overlay_horns','av_overlay',  'Horns','horns',                  800, 622),
  ('av_aura_neon',    'av_aura',     'Neon Glow','neon',               800, 630),
  ('av_aura_gold',    'av_aura',     'Gold Glow','gold',              1000, 631)
ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label, value=EXCLUDED.value, price=EXCLUDED.price, kind=EXCLUDED.kind, sort=EXCLUDED.sort;

-- graphicShirt made FREE: removed its paid catalog row so shirt designs (the paid
-- items) are usable on the free Graphic Tee.
DELETE FROM public.cosmetics WHERE id = 'av_cloth_graphic';
