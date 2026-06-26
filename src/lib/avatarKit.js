// ── Full-body avatar kit — Humaaans (3-piece: Bottom + Body + Head) ────────────
// Humaaans composes a figure from three pieces, each on its OWN canvas, placed at
// fixed offsets (derived from the library's composed characters). Because every
// piece of a type shares its canvas, these offsets work for ANY head+body+bottom
// combo. Art lives in static/avatar/<slot>/*.svg.
//
// To add a part: drop the SVG in the slot folder + add a line to PARTS.

/** Master compose canvas (px). */
export const CANVAS = { w: 300, h: 460 };

/** Flip true once the look is dialed in — then the builder/store/profile switch
 *  from the DiceBear bust to this full-body kit. */
export const KIT_READY = false;

/** Slots in paint order, each with its placement {x,y,w,h} inside CANVAS. */
export const SLOTS = [
  { key: 'bottom', label: 'Bottoms', z: 0, place: { x: 0, y: 215, w: 300, h: 239 } },
  { key: 'body', label: 'Outfit', z: 1, place: { x: 23, y: 105, w: 256, h: 187 } },
  { key: 'head', label: 'Hair', z: 2, place: { x: 97, y: 17, w: 136, h: 104 } }
];

/** Parts per slot. `price` = paid cosmetic (wired to the store when KIT_READY). */
export const PARTS = /** @type {Record<string, any[]>} */ ({
  head: [
    { id: 'short-1', label: 'Short', file: 'short-1.svg' },
    { id: 'short-2', label: 'Short 2', file: 'short-2.svg' },
    { id: 'no-hair', label: 'Bald', file: 'no-hair.svg' },
    { id: 'caesar', label: 'Caesar', file: 'caesar.svg' },
    { id: 'wavy', label: 'Wavy', file: 'wavy.svg' },
    { id: 'airy', label: 'Airy', file: 'airy.svg' },
    { id: 'pony', label: 'Ponytail', file: 'pony.svg' },
    { id: 'chongo', label: 'Bun', file: 'chongo.svg' },
    { id: 'hijab-1', label: 'Hijab', file: 'hijab-1.svg' },
    { id: 'turban-1', label: 'Turban', file: 'turban-1.svg' },
    { id: 'curly', label: 'Curly', file: 'curly.svg', price: 300, cosmeticId: 'kit_head_curly' },
    { id: 'afro', label: 'Afro', file: 'afro.svg', price: 400, cosmeticId: 'kit_head_afro' },
    { id: 'long', label: 'Long', file: 'long.svg', price: 400, cosmeticId: 'kit_head_long' },
    { id: 'rad', label: 'Rad', file: 'rad.svg', price: 400, cosmeticId: 'kit_head_rad' },
    { id: 'top', label: 'Topknot', file: 'top.svg', price: 300, cosmeticId: 'kit_head_top' },
    { id: 'short-beard', label: 'Beard', file: 'short-beard.svg', price: 500, cosmeticId: 'kit_head_beard' }
  ],
  body: [
    { id: 'long-sleeve', label: 'Long Sleeve', file: 'long-sleeve.svg' },
    { id: 'turtle-neck', label: 'Turtleneck', file: 'turtle-neck.svg' },
    { id: 'hoodie', label: 'Hoodie', file: 'hoodie.svg', price: 400, cosmeticId: 'kit_body_hoodie' },
    { id: 'jacket', label: 'Jacket', file: 'jacket.svg', price: 600, cosmeticId: 'kit_body_jacket' },
    { id: 'jacket-2', label: 'Bomber', file: 'jacket-2.svg', price: 600, cosmeticId: 'kit_body_jacket2' },
    { id: 'lab-coat', label: 'Lab Coat', file: 'lab-coat.svg', price: 700, cosmeticId: 'kit_body_labcoat' },
    { id: 'trench-coat', label: 'Trench Coat', file: 'trench-coat.svg', price: 800, cosmeticId: 'kit_body_trench' }
  ],
  bottom: [
    { id: 'skinny-jeans', label: 'Jeans', file: 'skinny-jeans.svg' },
    { id: 'sweatpants', label: 'Sweatpants', file: 'sweatpants.svg' },
    { id: 'shorts', label: 'Shorts', file: 'shorts.svg' },
    { id: 'baggy-pants', label: 'Baggy Pants', file: 'baggy-pants.svg', price: 400, cosmeticId: 'kit_btm_baggy' },
    { id: 'jogging', label: 'Joggers', file: 'jogging.svg', price: 400, cosmeticId: 'kit_btm_jogging' },
    { id: 'skirt', label: 'Skirt', file: 'skirt.svg', price: 500, cosmeticId: 'kit_btm_skirt' }
  ]
});

/** A sensible starter look. */
export const DEFAULT_KIT = { head: 'short-1', body: 'long-sleeve', bottom: 'skinny-jeans' };

/** Resolve the SVG url for a slot's selected part. @param {string} slot @param {string} id */
export function partFile(slot, id) {
  const part = (PARTS[slot] || []).find((p) => p.id === id);
  return part && part.file ? `/avatar/${slot}/${part.file}` : null;
}
