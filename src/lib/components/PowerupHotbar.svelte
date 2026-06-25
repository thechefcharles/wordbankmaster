<script>
  // ⚡ Power-up hotbar: 2 slots each side of the (fixed) Solve button.
  // Pages through your mode-eligible inventory with ◀ ▶ arrows; duplicates show
  // a count bubble. Filtering to "power-ups allowed in this game type" happens in
  // the parent — this component just renders whatever `items` it's given.
  import { createEventDispatcher } from 'svelte';
  const dispatch = createEventDispatcher();

  /** @type {{ id: string, emoji: string, name: string, blurb?: string, count?: number }[]} */
  export let items = [];
  export let busy = false;
  /** Optional helper line under the bar (e.g. the Daily "keep it for ×1.5" nudge). */
  export let hint = '';

  const PAGE = 4; // 2 left + 2 right
  let page = 0;
  // Clamp the page whenever the inventory shrinks/grows.
  $: totalPages = Math.max(1, Math.ceil(items.length / PAGE));
  $: if (page > totalPages - 1) page = totalPages - 1;
  $: pageItems = items.slice(page * PAGE, page * PAGE + PAGE);

  // Fill inner slots first so a few power-ups cluster symmetrically around Solve:
  // [leftInner, rightInner, leftOuter, rightOuter].
  $: leftCells = [pageItems[2] ?? null, pageItems[0] ?? null]; // [outer, inner]
  $: rightCells = [pageItems[1] ?? null, pageItems[3] ?? null]; // [inner, outer]

  /** @param {any} cell */
  function use(cell) {
    if (!cell || busy) return;
    dispatch('use', cell);
  }
  /** @param {number} d */
  function flip(d) {
    page = Math.min(totalPages - 1, Math.max(0, page + d));
  }
</script>

{#if items.length}
  <div class="ph-wrap">
    {#if totalPages > 1}
      <div class="ph-pager">
        <button class="ph-arrow" on:click={() => flip(-1)} disabled={page === 0} aria-label="Previous power-ups">◀</button>
        <span class="ph-dots">{page + 1}/{totalPages}</span>
        <button class="ph-arrow" on:click={() => flip(1)} disabled={page === totalPages - 1} aria-label="More power-ups">▶</button>
      </div>
    {/if}
    <div class="ph-bar">
      <div class="ph-group">
        {#each leftCells as cell}
          {#if cell}
            <button class="ph-slot filled" disabled={busy} on:click={() => use(cell)} title={cell.name + (cell.blurb ? ' — ' + cell.blurb : '')} aria-label={cell.name}>
              <span class="ph-emoji">{cell.emoji}</span>
              {#if (cell.count ?? 1) > 1}<span class="ph-count">{cell.count}</span>{/if}
            </button>
          {:else}
            <span class="ph-slot empty" aria-hidden="true"></span>
          {/if}
        {/each}
      </div>
      <div class="ph-spacer" aria-hidden="true"></div>
      <div class="ph-group">
        {#each rightCells as cell}
          {#if cell}
            <button class="ph-slot filled" disabled={busy} on:click={() => use(cell)} title={cell.name + (cell.blurb ? ' — ' + cell.blurb : '')} aria-label={cell.name}>
              <span class="ph-emoji">{cell.emoji}</span>
              {#if (cell.count ?? 1) > 1}<span class="ph-count">{cell.count}</span>{/if}
            </button>
          {:else}
            <span class="ph-slot empty" aria-hidden="true"></span>
          {/if}
        {/each}
      </div>
    </div>
  </div>
  {#if hint}<div class="ph-hint">{@html hint}</div>{/if}
{/if}

<style>
  .ph-wrap { position: fixed; left: 50%; transform: translateX(-50%); z-index: 998; pointer-events: none;
    bottom: calc(env(safe-area-inset-bottom, 0px) + 188px); display: flex; flex-direction: column; align-items: center; gap: 5px; }
  .ph-pager { display: flex; align-items: center; gap: 10px; pointer-events: auto; }
  .ph-arrow { width: 30px; height: 24px; border-radius: 8px; display: grid; place-items: center;
    border: 1px solid var(--border-strong, rgba(255,255,255,0.18)); background: var(--surface-2, rgba(255,255,255,0.06));
    color: var(--text); font-size: 0.72rem; cursor: pointer; }
  .ph-arrow:disabled { opacity: 0.3; cursor: default; }
  .ph-arrow:active:not(:disabled) { transform: scale(0.92); }
  .ph-dots { font-size: 0.66rem; color: var(--text-faint); font-variant-numeric: tabular-nums; min-width: 26px; text-align: center; }
  .ph-bar { display: flex; align-items: center; gap: 8px; }
  .ph-group { display: flex; gap: 5px; pointer-events: auto; }
  .ph-spacer { width: 200px; height: 46px; flex: none; } /* the Solve button overlays this */
  .ph-slot { position: relative; width: 36px; height: 46px; border-radius: 11px; display: grid; place-items: center; box-sizing: border-box; }
  .ph-slot.filled { cursor: pointer;
    border: 1px solid rgba(253, 224, 71, 0.6); background: linear-gradient(135deg, rgba(251, 191, 36, 0.22), rgba(251, 191, 36, 0.05));
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4), inset 0 1px 0 rgba(255, 255, 255, 0.2); animation: phPulse 1.8s ease-in-out infinite; }
  .ph-slot.filled:active { transform: scale(0.93); }
  .ph-slot.filled:disabled { opacity: 0.5; cursor: default; animation: none; }
  .ph-slot.empty { border: 1.5px solid rgba(255, 255, 255, 0.2); background: rgba(255, 255, 255, 0.05); box-shadow: inset 0 2px 7px rgba(0, 0, 0, 0.55); }
  @keyframes phPulse { 0%,100% { box-shadow: 0 2px 8px rgba(0,0,0,0.4), 0 0 0 0 rgba(251,191,36,0.5); } 50% { box-shadow: 0 2px 8px rgba(0,0,0,0.4), 0 0 0 5px rgba(251,191,36,0); } }
  .ph-emoji { font-size: 1.3rem; line-height: 1; }
  .ph-count { position: absolute; top: -5px; right: -5px; min-width: 16px; height: 16px; padding: 0 4px; border-radius: 999px;
    background: #1f2937; border: 1px solid rgba(253,224,71,0.7); color: #fde047; font-family: var(--font-display); font-weight: 800;
    font-size: 0.62rem; display: grid; place-items: center; }
  .ph-hint { position: fixed; left: 50%; transform: translateX(-50%); z-index: 998; text-align: center; pointer-events: none;
    bottom: calc(env(safe-area-inset-bottom, 0px) + 158px); font-size: 0.7rem; color: var(--text-muted); max-width: 320px; }
  .ph-hint :global(b) { color: #6ee7b7; }
</style>
