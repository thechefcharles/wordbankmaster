# Full-body avatar kit — drop your art here

This folder is the integration point for a modular art kit (Humaaans, Blush, a bought
asset pack, or commissioned art). The plumbing is already built — you just add SVGs and
list them in the manifest.

## How the pieces fit
- **`src/lib/avatarKit.js`** — the manifest. Lists every part, its slot, label, and price.
- **`src/lib/components/KitAvatar.svelte`** — stacks the chosen parts into a figure.
- **`src/routes/avatar/kit`** — a live preview page to see it + flip parts.
- The placeholder `.svg` files in here are **throwaway** — replace them with real art.

## Slots (paint order, back → front)
`body → bottom → top → shoes → hair → accessory`

## Exporting parts (the only rule that matters)
**Every part must be exported on the SAME canvas** so they line up when stacked:
- Canvas: **360 × 540** (portrait, the value in `CANVAS` in avatarKit.js — change it there
  if your art uses a different size, but keep ALL parts identical).
- **Transparent background.**
- Each part draws **only its own piece** in its correct position on that canvas
  (e.g. `top/hoodie.svg` draws just the hoodie where the torso is — nothing else).
- Format: **SVG** (preferred) or transparent PNG.

## Adding a part
1. Export it onto the 360×540 canvas, transparent.
2. Save it as `static/avatar/<slot>/<name>.svg` (e.g. `static/avatar/top/varsity.svg`).
3. Add a line to `PARTS` in `src/lib/avatarKit.js`:
   ```js
   top: [
     { id: 'tee', label: 'Tee', file: 'tee.svg' },
     { id: 'varsity', label: 'Varsity Jacket', file: 'varsity.svg', price: 600, cosmeticId: 'kit_top_varsity' },
   ]
   ```
   - No `price` = free. With `price` = a paid cosmetic (wired into the store when ready).

## Humaaans / Blush workflow
1. Duplicate the **Humaaans** Figma community file (or use the Blush editor).
2. Pick **one standing pose** as the base.
3. For that pose, export each swappable layer (head/hair/top/bottom/shoes/accessory) as
   its own SVG on a shared 360×540 frame, transparent.
4. Drop them in the matching slot folder + list them in the manifest.

## Going live
When the real art is in and looks good, set **`KIT_READY = true`** in `avatarKit.js` and
tell me — I'll switch the builder + store + profile from the DiceBear bust to this
full-body kit (and seed the paid parts into the cosmetics catalog).
