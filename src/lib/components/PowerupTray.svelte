<script>
  // Arcade-only: the run's earned power-ups, tappable to spend. The armed effect
  // (Double Payout) shows as ON and can't be re-armed.
  import { gameStore, useArcadePowerup } from '$lib/stores/GameStore.js';
  import { powerupInfo } from '$lib/powerups.js';
  import { fx } from '$lib/sound.js';

  $: run = $gameStore.arcadeRun;
  $: inv = (run && run.inventory) || {};
  $: active = (run && run.active) || [];
  // Show spendable chips (inventory > 0) AND effects armed on this puzzle (already
  // spent from inventory, so they'd otherwise vanish) — the armed ones render "ON".
  $: ids = [...new Set([...active, ...Object.keys(inv).filter((k) => (inv[k] ?? 0) > 0)])];
  $: playable = $gameStore.gameMode === 'arcade'
    && $gameStore.gameState !== 'won'
    && $gameStore.gameState !== 'lost';

  /** @param {string} id */
  function use(id) {
    if (active.includes(id)) return; // already armed on this puzzle
    fx('tap');
    useArcadePowerup(id);
  }
</script>

{#if playable && ids.length}
  <div class="pu-tray" role="toolbar" aria-label="Power-ups">
    {#each ids as id (id)}
      {@const info = powerupInfo(id)}
      {@const isArmed = active.includes(id)}
      <button
        class="pu-chip {isArmed ? 'armed' : ''}"
        on:click={() => use(id)}
        disabled={isArmed}
        title={`${info.name} — ${info.desc}`}
        aria-label={`Use ${info.name}`}
      >
        <span class="pu-emoji">{info.emoji}</span>
        {#if !isArmed}<span class="pu-count">{inv[id]}</span>{/if}
      </button>
    {/each}
  </div>
{/if}

<style>
  .pu-tray {
    display: flex;
    gap: 8px;
    justify-content: center;
    flex-wrap: wrap;
    margin: -8px auto 16px;
    max-width: 360px;
  }
  .pu-chip {
    position: relative;
    width: 46px;
    height: 44px;
    border-radius: 12px;
    background: var(--surface, rgba(255, 255, 255, 0.05));
    border: 1px solid var(--border, rgba(255, 255, 255, 0.12));
    display: grid;
    place-items: center;
    cursor: pointer;
    transition: transform 0.15s var(--ease-spring, ease), border-color 0.2s, box-shadow 0.2s;
  }
  .pu-chip:hover { transform: translateY(-2px); border-color: var(--border-strong, rgba(255, 255, 255, 0.25)); }
  .pu-chip:active { transform: scale(0.94); }
  .pu-emoji { font-size: 1.3rem; line-height: 1; }
  .pu-count {
    position: absolute;
    top: -5px;
    right: -5px;
    min-width: 16px;
    height: 16px;
    padding: 0 4px;
    display: grid;
    place-items: center;
    font-family: var(--font-display, sans-serif);
    font-size: 10px;
    font-weight: 700;
    color: #06210f;
    background: var(--brand-grad, linear-gradient(135deg, #34d399, #a3e635));
    border-radius: 999px;
  }
  .pu-chip.armed {
    border-color: rgba(251, 191, 36, 0.55);
    box-shadow: 0 0 14px rgba(251, 191, 36, 0.28);
    cursor: default;
  }
  .pu-chip.armed::after {
    content: 'ON';
    position: absolute;
    bottom: -6px;
    left: 50%;
    transform: translateX(-50%);
    font-family: var(--font-display, sans-serif);
    font-size: 7px;
    font-weight: 700;
    letter-spacing: 0.08em;
    color: #fcd34d;
    background: rgba(251, 191, 36, 0.16);
    border-radius: 999px;
    padding: 1px 5px;
  }
</style>
