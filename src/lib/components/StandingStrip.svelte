<script>
  // Live challenge HUD. Frames your buy-in as one budget being consumed:
  //   Spent (filled) + Left to spend (rest) = your buy-in.
  // 💰 Cash is shown separately as your account. Tap any value for a plain
  // explanation. Rank vs FINISHED rivals is directional only (never the exact
  // spend to beat); the lead-flip is the reward moment.
  import { fx } from '$lib/sound.js';

  /** @type {{ field_size:number, finished:number, rank:number, state:'lead'|'behind'|'tied'|'first_to_play', provisional?:boolean } | null} */
  export let standing = null;
  /** @type {number} */ export let spent = 0;
  /** @type {number} in-game budget you have left to spend this match */ export let bankroll = 0;
  /** @type {number|null} your total Cash account (separate from the match budget) */ export let netWorth = null;

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
  const money = (/** @type {number|null} */ n) => n == null ? '—' : '$' + Math.round(n).toLocaleString();

  $: ranked = !!standing && standing.state !== 'first_to_play';
  $: budget = Math.max(0, (spent ?? 0) + (bankroll ?? 0)); // spent + left = your buy-in
  $: spentPct = budget > 0 ? Math.min(100, Math.max(0, (spent / budget) * 100)) : 0;
  $: lead = standing && standing.state === 'lead';

  // Tap a value → explain it. Tapping the same one (or the note) closes it.
  let info = /** @type {null | 'spent' | 'left' | 'budget' | 'cash'} */ (null);
  function toggle(/** @type {any} */ k) { fx('tap'); info = info === k ? null : k; }
  const EXPLAIN = {
    spent: 'What you’ve spent on letters this match. The lowest spend to solve wins the whole pot — so keep it small.',
    left: 'Your budget that’s still unspent. Anything you don’t use is refunded to your Cash at the end.',
    budget: 'Your buy-in — the most you can spend this match (Spent + Left). Unspent money comes back to you.',
    cash: 'Your account balance, outside this match. Your buy-in already moved out of here into the match budget — that’s why it can be less than your budget.'
  };
</script>

{#if standing || budget > 0}
  <div class="standing {standing?.state ?? 'first_to_play'}" class:lead>
    {#if ranked && standing}
      <div class="rank-row">
        <span class="rank">{medal(standing.rank)} {ord(standing.rank)} of {standing.field_size}{#if standing.provisional}<span class="sofar">so far</span>{/if}</span>
        {#if lead}<span class="lead-badge">✓ In the lead</span>{/if}
      </div>
    {/if}

    <div class="bud-labels">
      <button class="chip" class:on={info === 'spent'} on:click={() => toggle('spent')}>Spent <b>{money(spent)}</b></button>
      <button class="chip right" class:on={info === 'left'} on:click={() => toggle('left')}><b>{money(bankroll)}</b> left to spend</button>
    </div>
    <button class="bar" class:on={info === 'budget'} on:click={() => toggle('budget')} aria-label="Your buy-in budget">
      <span class="bar-fill" style="width:{spentPct}%"></span>
    </button>
    <div class="bud-foot">
      <button class="foot" class:on={info === 'budget'} on:click={() => toggle('budget')}>{money(budget)} buy-in</button>
      <button class="foot cash" class:on={info === 'cash'} on:click={() => toggle('cash')}>💰 Cash {money(netWorth)}</button>
    </div>

    {#if info}
      <button class="explain" on:click={() => (info = null)}>
        <span class="ex-ic">ⓘ</span><span class="ex-tx">{EXPLAIN[info]}</span>
      </button>
    {:else}
      <div class="hint">Tap any value to see what it means</div>
    {/if}
  </div>
{/if}

<style>
  .standing {
    max-width: 360px; margin: 0 auto 6px; padding: 9px 13px 8px;
    border-radius: 13px;
    border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
    background: var(--surface, rgba(255, 255, 255, 0.05));
    animation: stPop 0.32s cubic-bezier(0.34, 1.56, 0.64, 1);
  }
  @keyframes stPop { from { transform: scale(0.96); opacity: 0.4; } to { transform: scale(1); opacity: 1; } }

  .rank-row { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin-bottom: 7px;
    font-family: var(--font-display, sans-serif); font-weight: 700; font-size: 0.92rem; color: var(--text, #fff); }
  .sofar { margin-left: 6px; font-family: var(--font-ui, sans-serif); font-weight: 600; font-size: 0.62rem;
    text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-faint, #8090a0); }
  .lead-badge { font-size: 0.78rem; font-weight: 700; color: #7ee0a8; }

  /* tappable values */
  button { font-family: inherit; cursor: pointer; background: none; border: none; color: inherit; padding: 0; }
  .bud-labels { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; }
  .chip { font-size: 0.82rem; color: var(--text-muted, #c2cbd8); border-bottom: 1px dotted var(--text-faint, #6b7686); line-height: 1.5; }
  .chip.right { text-align: right; }
  .chip b { color: var(--text, #fff); font-variant-numeric: tabular-nums; }
  .chip.on { color: var(--brand-2, #fde047); border-bottom-color: var(--brand-2, #fde047); }

  .bar { display: block; width: 100%; height: 9px; margin: 5px 0 6px; border-radius: 999px;
    background: rgba(255, 255, 255, 0.10); overflow: hidden; }
  .bar-fill { display: block; height: 100%; border-radius: 999px;
    background: linear-gradient(90deg, #fbbf24, #fde047); transition: width 0.35s ease; }
  .bar.on { box-shadow: 0 0 0 2px rgba(253, 224, 71, 0.4); }

  .bud-foot { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
  .foot { font-size: 0.72rem; color: var(--text-faint, #8090a0); border-bottom: 1px dotted transparent; }
  .foot.cash { color: var(--text-muted, #c2cbd8); border-bottom-color: var(--text-faint, #6b7686); }
  .foot.on { color: var(--brand-2, #fde047); border-bottom-color: var(--brand-2, #fde047); }

  .hint { margin-top: 6px; font-size: 0.63rem; color: var(--text-faint, #6b7686); text-align: center; }
  .explain { display: flex; gap: 6px; align-items: flex-start; text-align: left; width: 100%;
    margin-top: 7px; padding: 7px 9px; border-radius: 9px;
    background: rgba(125, 188, 255, 0.10); border: 1px solid rgba(125, 188, 255, 0.28); }
  .ex-ic { color: #93c5fd; font-size: 0.8rem; line-height: 1.35; }
  .ex-tx { font-size: 0.74rem; line-height: 1.35; color: var(--text, #fff); }

  .standing.lead { border-color: rgba(126, 224, 168, 0.5);
    background: linear-gradient(135deg, rgba(126, 224, 168, 0.13), rgba(126, 224, 168, 0.04));
    box-shadow: 0 0 16px rgba(126, 224, 168, 0.22); }
  .standing.behind { border-color: rgba(251, 191, 36, 0.45); }
  .standing.first_to_play { border-color: rgba(125, 188, 255, 0.4); }
</style>
