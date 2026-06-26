<script>
  import { SLOTS, PARTS, CANVAS, DEFAULT_KIT } from '$lib/avatarKit.js';
  /** @type {any} */ export let config = null;   // { slot: partId }
  export let size = 200;                         // width in px (height from CANVAS ratio)

  $: sel = { ...DEFAULT_KIT, ...(config || {}) };
  $: ordered = [...SLOTS].sort((a, b) => a.z - b.z);
  /** @param {string} slot */
  function fileFor(slot) {
    const part = (PARTS[slot] || []).find((p) => p.id === sel[slot]);
    return part && part.file ? `/avatar/${slot}/${part.file}` : null;
  }
</script>

<div class="kit" style="--w:{size}px; aspect-ratio:{CANVAS.w} / {CANVAS.h};">
  {#each ordered as s (s.key)}
    {#if fileFor(s.key)}
      <img class="kit-layer" style="z-index:{s.z}" src={fileFor(s.key)} alt="" />
    {/if}
  {/each}
</div>

<style>
  .kit { position: relative; width: var(--w); flex: none; }
  .kit-layer { position: absolute; inset: 0; width: 100%; height: 100%; display: block; pointer-events: none; }
</style>
