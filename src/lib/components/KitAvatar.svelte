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

<svg class="kit" viewBox="0 0 {CANVAS.w} {CANVAS.h}" style="width:{size}px;" xmlns="http://www.w3.org/2000/svg">
  {#each ordered as s (s.key)}
    {#if fileFor(s.key)}
      <image href={fileFor(s.key)} x={s.place.x} y={s.place.y} width={s.place.w} height={s.place.h} />
    {/if}
  {/each}
</svg>

<style>
  .kit { display: block; height: auto; flex: none; overflow: visible; }
</style>
