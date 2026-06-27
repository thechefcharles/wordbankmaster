<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import PageNav from "$lib/components/PageNav.svelte";
  import { getBank } from '$lib/stores/statsStore.js';
  import { track } from '$lib/analytics.js';

  /** @type {{ bank:number, net_worth:number, ledger:any[] }|null} */
  let b = null;
  let loading = true;

  onMount(async () => {
    track('bank_view');
    try { b = await getBank(); } finally { loading = false; }
  });

  const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();

  /** @param {string} reason */
  function reasonLabel(reason) {
    return ({
      quest_reward: 'Daily quests reward',
      daily_win: 'Daily reward',
      attendance: 'Daily attendance reward',
      arcade_cashout: 'Cash Game cash-out',
      climb_bounty: 'Climb bounty',
      freeplay_reward: 'Free Play reward',
      cosmetic_buy: 'Shop purchase',
      powerup_buy: 'Power-up purchase',
      wager_win: 'Won a wager',
      wager_stake: 'Wager staked',
      wager_refund: 'Wager refunded'
    })[reason] || reason;
  }
</script>

<svelte:head><title>WordBank — Cash & Net Worth</title></svelte:head>

<main class="bank-page">
  <PageNav back="/" />

  {#if loading}
    <p class="loading">Loading…</p>
  {:else if b}
    <p class="nw-label">Net Worth</p>
    <div class="net-worth">{fmt(b.bank)}</div>
    <p class="nw-sub">Your Cash — this is your score</p>

    <h2 class="hist-title">Recent activity</h2>
    {#if b.ledger.length === 0}
      <p class="empty">No transactions yet. Win the Daily, show up for attendance rewards, or climb the Cash Game to grow your Cash.</p>
    {:else}
      <div class="ledger">
        {#each b.ledger as e}
          <div class="led-row">
            <span class="led-reason">{reasonLabel(e.reason)}</span>
            <span class="led-delta" class:pos={e.delta > 0} class:neg={e.delta < 0}>{e.delta > 0 ? '+' : '−'}{fmt(Math.abs(e.delta))}</span>
          </div>
        {/each}
      </div>
    {/if}

    <p class="hint">In-game Cash — can't be bought or cashed out.</p>
  {/if}
</main>

<style>
  .bank-page { max-width: 460px; margin: 0 auto; padding: 1.5rem 1rem 3rem; text-align: center; }
  .back-btn {
    display: inline-block; margin-bottom: 1rem; padding: 0.55rem 1.1rem;
    background: var(--surface); color: var(--text); border: 1px solid var(--border);
    border-radius: 12px; cursor: pointer; font-weight: 600; font-size: 0.9rem;
  }
  .loading { color: var(--text-muted); padding: 2rem; }
  .nw-label { color: var(--text-faint); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.08em; margin: 0.5rem 0 0; }
  .net-worth { font-family: var(--font-display); font-weight: 800; font-size: 3rem; line-height: 1.1; color: var(--brand-2); }
  .nw-sub { color: var(--text-faint); font-size: 0.78rem; margin: 0.2rem 0 0; }

  .hist-title { font-family: var(--font-display); font-size: 1rem; margin: 1.8rem 0 0.6rem; text-align: left; }
  .empty { color: var(--text-muted); font-size: 0.9rem; }
  .ledger { display: flex; flex-direction: column; gap: 1px; background: var(--border); border-radius: 12px; overflow: hidden; }
  .led-row { display: flex; justify-content: space-between; padding: 0.7rem 0.9rem; background: var(--surface); }
  .led-reason { color: var(--text-muted); font-size: 0.9rem; }
  .led-delta { font-family: var(--font-display); font-weight: 700; font-size: 0.9rem; }
  .led-delta.pos { color: var(--brand-2); }
  .led-delta.neg { color: #fb7185; }
  .hint { margin-top: 1.6rem; font-size: 0.78rem; color: var(--text-faint); }
</style>
