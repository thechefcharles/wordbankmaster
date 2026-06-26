// ── Full-body avatar "kit" — layered SVG paper-doll ────────────────────────────
// This is the integration scaffold for a modular art kit (e.g. Humaaans/Blush).
// HOW IT WORKS: each slot stacks one transparent SVG, all exported on the SAME
// canvas (see CANVAS), so they auto-align. To add art: drop the file in
// static/avatar/<slot>/<file>.svg and add an entry to PARTS below. Items with a
// `price` are paid cosmetics (wired into the existing store when KIT_READY).
//
// The placeholder SVGs shipped here are throwaway — replace them with real exports.

/** Export every part on this canvas (px). Aspect ratio drives the on-screen box. */
export const CANVAS = { w: 360, h: 540 };

/** Flip to true once real art has replaced the placeholders — then the builder +
 *  store switch from the DiceBear bust to this full-body kit. */
export const KIT_READY = false;

/** Slots in paint order (low z first). `solid` slots always render something. */
export const SLOTS = [
  { key: 'body', label: 'Body', z: 0 },
  { key: 'bottom', label: 'Bottoms', z: 1 },
  { key: 'top', label: 'Tops', z: 2 },
  { key: 'shoes', label: 'Shoes', z: 3 },
  { key: 'hair', label: 'Hair', z: 5 },
  { key: 'accessory', label: 'Accessories', z: 6 }
];

/** Parts per slot. file → static/avatar/<slot>/<file> (null = nothing drawn).
 *  Add `price` to make a part a paid cosmetic; `cosmeticId` ties it to the catalog. */
export const PARTS = /** @type {Record<string, any[]>} */ ({
  body: [
    { id: 'default', label: 'Default', file: 'default.svg' }
  ],
  hair: [
    { id: 'none', label: 'Bald', file: null },
    { id: 'short', label: 'Short', file: 'short.svg' },
    { id: 'long', label: 'Long', file: 'long.svg', price: 300, cosmeticId: 'kit_hair_long' }
  ],
  top: [
    { id: 'tee', label: 'Tee', file: 'tee.svg' },
    { id: 'hoodie', label: 'Hoodie', file: 'hoodie.svg', price: 400, cosmeticId: 'kit_top_hoodie' }
  ],
  bottom: [
    { id: 'jeans', label: 'Jeans', file: 'jeans.svg' },
    { id: 'shorts', label: 'Shorts', file: 'shorts.svg' }
  ],
  shoes: [
    { id: 'sneakers', label: 'Sneakers', file: 'sneakers.svg' },
    { id: 'boots', label: 'Boots', file: 'boots.svg', price: 500, cosmeticId: 'kit_shoes_boots' }
  ],
  accessory: [
    { id: 'none', label: 'None', file: null },
    { id: 'glasses', label: 'Glasses', file: 'glasses.svg', price: 300, cosmeticId: 'kit_acc_glasses' }
  ]
});

/** A sensible starter look. */
export const DEFAULT_KIT = { body: 'default', hair: 'short', top: 'tee', bottom: 'jeans', shoes: 'sneakers', accessory: 'none' };

/** Resolve the SVG url for a slot's selected part (null if nothing). @param {string} slot @param {string} id */
export function partFile(slot, id) {
  const part = (PARTS[slot] || []).find((p) => p.id === id);
  return part && part.file ? `/avatar/${slot}/${part.file}` : null;
}
