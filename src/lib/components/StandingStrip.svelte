<script>
  // Live directional standing for a challenge (Phase 2 of OBJECTIVE_HUD_SPEC).
  // Shows rank + ahead/behind vs FINISHED rivals — never the exact spend to beat
  // (the server only sends a direction). The lead-flip is the reward moment.
  import { fx } from '$lib/sound.js';

  /** @type {{ field_size:number, finished:number, rank:number, state:'lead'|'behind'|'tied'|'first_to_play' } | null} */
  export let standing = null;
  /** @type {number} */ export let spent = 0;

  // Chime when you flip INTO the lead. prevState lives outside the reactive
  // dependency graph (read/written inside a fn) so it can't self-invalidate.
  let prevState;
  function onStanding(/** @type {any} */ s) {
    if (s && s.state === 'lead' && prevState && prevState !== 'lead') fx('lead');
    prevState = s?.state;
  }
  $: onStanding(standing);

  const ord = (/** @type {number} */ n) => { const s = ['th','st','nd','rd'], v = n % 100; return n + (s[(v - 20) % 10] || s[v] || s[0]); };
  const medal = (/** @type {number} */ r) => r === 1 ? '🥇' : r === 2 ? '🥈' : r === 3 ? '🥉' : '#' + r;
  $: msg = !standing ? '' :
    standing.state === 'lead' ? "✓ You're in the lead" :
    standing.state === 'behind' ? '▲ Spend less to take the lead' :
    standing.state === 'tied' ? 'Dead even — spend less to pull ahead' :
    '🚩 Set the bar — spend as little as you can';
</script>

{#if standing}
  {#key standing.state}
    <div class="standing {standing.state}">
      <div class="top">
        {#if standing.state === 'first_to_play'}
          <span class="rank">🚩 First to play</span>
        {:else}
          <span class="rank">{medal(standing.rank)} {ord(standing.rank)} of {standing.field_size}</span>
        {/if}
        <span class="spent">Spent <b>${spent.toLocaleString()}</b></span>
      </div>
      <div class="msg">{msg}</div>
    </div>
  {/key}
{/if}

<style>
  .standing {
    max-width: 360px;
    margin: 0 auto 6px;
    padding: 9px 14px;
    border-radius: 13px;
    border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
    background: var(--surface, rgba(255, 255, 255, 0.05));
    animation: stPop 0.32s cubic-bezier(0.34, 1.56, 0.64, 1);
  }
  @keyframes stPop {
    from { transform: scale(0.96); opacity: 0.4; }
    to { transform: scale(1); opacity: 1; }
  }
  .top {
    display: flex; align-items: center; justify-content: space-between; gap: 10px;
    font-family: var(--font-display, sans-serif); font-weight: 700; font-size: 0.92rem;
    color: var(--text, #fff);
  }
  .spent { font-weight: 600; color: var(--text-muted, #c2cbd8); font-size: 0.84rem; }
  .spent b { color: var(--text, #fff); font-variant-numeric: tabular-nums; }
  .msg {
    margin-top: 3px; text-align: left;
    font-family: var(--font-ui, sans-serif); font-size: 0.76rem; font-weight: 600;
  }

  .standing.lead {
    border-color: rgba(126, 224, 168, 0.55);
    background: linear-gradient(135deg, rgba(126, 224, 168, 0.16), rgba(126, 224, 168, 0.05));
    box-shadow: 0 0 18px rgba(126, 224, 168, 0.25);
  }
  .standing.lead .msg { color: #7ee0a8; }

  .standing.behind {
    border-color: rgba(251, 191, 36, 0.5);
    background: linear-gradient(135deg, rgba(251, 191, 36, 0.13), rgba(251, 191, 36, 0.04));
  }
  .standing.behind .msg { color: #fbbf24; }

  .standing.tied { border-color: var(--border-strong, rgba(255, 255, 255, 0.18)); }
  .standing.tied .msg { color: var(--text-muted, #c2cbd8); }

  .standing.first_to_play {
    border-color: rgba(125, 188, 255, 0.5);
    background: linear-gradient(135deg, rgba(125, 188, 255, 0.12), rgba(125, 188, 255, 0.04));
  }
  .standing.first_to_play .msg { color: #93c5fd; }
</style>
