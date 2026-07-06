<script>
  import { onMount } from 'svelte';
  import PageNav from "$lib/components/PageNav.svelte";
  import { getBank } from '$lib/stores/statsStore.js';
  import InventoryList from '$lib/components/InventoryList.svelte';
  import { track } from '$lib/analytics.js';

  /** @type {{ bank:number, net_worth:number, ledger:any[] }|null} */
  let b = null;
  let loading = true;
  /** @type {{title:string, desc:string}|null} */
  let info = null;

  async function load() {
    b = await getBank(500);
  }
  onMount(async () => {
    track('bank_view');
    try { await load(); } finally { loading = false; }
  });

  const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();
  const dateOnly = (/** @type {string} */ at) => at ? new Date(at).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : '';

  // Ledger filters: by type, and sort by date/amount. Custom dropdowns so the menu
  // opens downward over the ledger.
  let typeFilter = 'all';
  let sortBy = 'newest';
  /** @type {null|'type'|'sort'} */
  let openMenu = null;
  const SORTS = [{ k: 'newest', label: 'Newest' }, { k: 'oldest', label: 'Oldest' }, { k: 'largest', label: 'Largest' }, { k: 'smallest', label: 'Smallest' }];
  $: sortLabel = SORTS.find((s) => s.k === sortBy)?.label ?? 'Newest';
  $: ledgerTypes = b ? [...new Set(b.ledger.map((/** @type {any} */ e) => e.reason))] : [];
  $: shownLedger = (b ? [...b.ledger] : [])
    .filter((/** @type {any} */ e) => typeFilter === 'all' || e.reason === typeFilter)
    .sort((/** @type {any} */ x, /** @type {any} */ y) => {
      if (sortBy === 'oldest') return new Date(x.at).getTime() - new Date(y.at).getTime();
      if (sortBy === 'largest') return Math.abs(y.delta) - Math.abs(x.delta);
      if (sortBy === 'smallest') return Math.abs(x.delta) - Math.abs(y.delta);
      return new Date(y.at).getTime() - new Date(x.at).getTime();
    });

  /** @param {string} reason */
  function reasonLabel(reason) {
    return ({
      quest_reward: 'Daily quests reward', daily_win: 'Daily reward', daily_reward: 'Daily reward',
      attendance: 'Attendance reward', arcade_cashout: 'Cash Game cash-out', climb_bounty: 'Cash Game bounty',
      freeplay_reward: 'Free Play reward', freeplay_cashout: 'Exchanged credits → Cash',
      cosmetic_buy: 'Store purchase', powerup_buy: 'Power-up purchase',
      wager_win: 'Won a wager', wager_stake: 'Wager staked', wager_refund: 'Wager refunded',
      makeup_reward: 'Make-up Daily', challenge_payout: 'Challenge payout'
    })[reason] || reason.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  }
</script>

<svelte:head><title>WordBank — Bank</title></svelte:head>

<main class="bank-page">
  <PageNav back="/" />
  <h1 class="bank-title">🏦 Bank</h1>

  {#if loading}
    <p class="loading">Loading…</p>
  {:else if b}
    <!-- Balances -->
    <div class="balances">
      <button class="bal cash" onclick={() => info = { title: '💰 Cash', desc: 'Your main currency — and your score. Earn it by solving puzzles in the Daily, Cash Game, and challenges. Spend it on letters mid-game and on power-ups & cosmetics in the Store. It can’t be bought with real money.' }}>
        <span class="bal-label">💰 Cash <span class="bal-i">ⓘ</span></span>
        <span class="bal-value">{fmt(b.bank)}</span>
      </button>
    </div>

    <!-- Items (your vault) -->
    <h2 class="hist-title">🎒 Your Items</h2>
    <InventoryList addHref="/shop?from=bank" />

    <!-- Ledger -->
    <div class="led-head">
      <h2 class="hist-title">📒 Ledger</h2>
      {#if b.ledger.length}
        <div class="led-filters">
          <div class="led-dd">
            <button class="led-sel" onclick={() => openMenu = openMenu === 'type' ? null : 'type'}>{typeFilter === 'all' ? 'All types' : reasonLabel(typeFilter)} <span class="dd-cv">▾</span></button>
            {#if openMenu === 'type'}
              <div class="led-menu">
                <button class:on={typeFilter === 'all'} onclick={() => { typeFilter = 'all'; openMenu = null; }}>All types</button>
                {#each ledgerTypes as t}<button class:on={typeFilter === t} onclick={() => { typeFilter = t; openMenu = null; }}>{reasonLabel(t)}</button>{/each}
              </div>
            {/if}
          </div>
          <div class="led-dd">
            <button class="led-sel" onclick={() => openMenu = openMenu === 'sort' ? null : 'sort'}>{sortLabel} <span class="dd-cv">▾</span></button>
            {#if openMenu === 'sort'}
              <div class="led-menu">
                {#each SORTS as s}<button class:on={sortBy === s.k} onclick={() => { sortBy = s.k; openMenu = null; }}>{s.label}</button>{/each}
              </div>
            {/if}
          </div>
        </div>
      {/if}
    </div>
    {#if openMenu}<button class="led-backdrop" onclick={() => openMenu = null} aria-label="Close" tabindex="-1"></button>{/if}
    {#if b.ledger.length === 0}
      <p class="empty">No transactions yet. Win the Daily, show up for attendance, or climb the Cash Game to grow your Cash.</p>
    {:else}
      <div class="ledger scroll">
        {#each shownLedger as e}
          <div class="led-row">
            <span class="led-date">{dateOnly(e.at)}</span>
            <span class="led-reason">{reasonLabel(e.reason)}</span>
            <span class="led-delta" class:pos={e.delta > 0} class:neg={e.delta < 0}>{e.delta > 0 ? '+' : '−'}{fmt(Math.abs(e.delta))}</span>
          </div>
        {/each}
      </div>
    {/if}
  {/if}

  {#if info}
    <div class="si-overlay" role="button" tabindex="0" onclick={() => info = null}
      onkeydown={(e) => { if (e.key === 'Escape' || e.key === 'Enter') info = null; }}>
      <div class="si-card" role="document" onclick={(e) => e.stopPropagation()}>
        <h3 class="si-title">{info.title}</h3>
        <p class="si-desc">{info.desc}</p>
        <button class="si-close" onclick={() => info = null}>Got it</button>
      </div>
    </div>
  {/if}
</main>

<style>
  .bank-page { max-width: 480px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }
  .bank-title { font-family: var(--font-display); font-size: 1.5rem; margin: 4px 0 16px; text-align: center; }
  .loading { color: var(--text-muted); padding: 2rem; text-align: center; }

  .balances { display: grid; grid-template-columns: 1fr; gap: 10px; margin-bottom: 14px; }
  .bal { display: flex; flex-direction: column; gap: 2px; padding: 14px; border-radius: 16px; background: var(--surface); border: 1px solid var(--border);
    text-align: left; cursor: pointer; font: inherit; color: inherit; }
  .bal:hover { border-color: var(--brand-2); }
  .bal:active { transform: scale(0.98); }
  .bal-label { font-size: 0.78rem; color: var(--text-muted); font-weight: 700; }
  .bal-i { color: var(--text-faint); font-size: 0.72rem; }

  /* balance explanation popup */
  .si-overlay { position: fixed; inset: 0; z-index: 4000; display: grid; place-items: center; padding: 24px;
    background: rgba(4,8,14,0.72); backdrop-filter: blur(6px); border: none; }
  .si-card { width: 100%; max-width: 320px; padding: 22px; border-radius: 18px; text-align: center;
    background: var(--surface-strong, rgba(20,26,38,0.96)); border: 1px solid var(--border-strong, rgba(255,255,255,0.16));
    box-shadow: 0 20px 50px rgba(0,0,0,0.5); display: flex; flex-direction: column; gap: 10px; }
  .si-title { font-family: var(--font-display); font-size: 1.15rem; margin: 0; }
  .si-desc { font-size: 0.92rem; line-height: 1.5; color: var(--text-muted); margin: 0; }
  .si-close { margin-top: 4px; height: 44px; border-radius: 12px; border: none; cursor: pointer; font-weight: 800; color: #3a2a00;
    background: linear-gradient(135deg, #fde047, #f59e0b); }
  .bal-value { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 1.7rem; color: var(--brand-2); }

  .led-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin: 1.4rem 0 0.6rem; flex-wrap: wrap; }
  .hist-title { font-family: var(--font-display); font-size: 1rem; margin: 0; }
  .led-filters { display: flex; gap: 6px; }
  .led-dd { position: relative; }
  .led-sel { display: flex; align-items: center; gap: 5px; padding: 6px 10px; border-radius: 9px; border: 1px solid var(--border);
    background: var(--surface); color: var(--text); font-size: 0.74rem; font-weight: 600; cursor: pointer; white-space: nowrap; }
  .led-sel:hover { border-color: var(--brand-2); }
  .dd-cv { color: var(--text-faint); font-size: 0.7rem; }
  .led-backdrop { position: fixed; inset: 0; z-index: 25; background: transparent; border: none; cursor: default; }
  .led-menu { position: absolute; top: calc(100% + 4px); right: 0; z-index: 30; min-width: 150px; max-height: 260px; overflow-y: auto;
    display: flex; flex-direction: column; padding: 5px; border-radius: 12px;
    background: var(--surface-strong, rgba(20,26,38,0.98)); border: 1px solid var(--border-strong, rgba(255,255,255,0.16)); box-shadow: 0 16px 40px rgba(0,0,0,0.55); }
  .led-menu button { text-align: left; padding: 8px 10px; border-radius: 8px; border: none; background: none; color: var(--text); cursor: pointer; font-size: 0.82rem; white-space: nowrap; }
  .led-menu button:hover { background: rgba(255,255,255,0.06); }
  .led-menu button.on { color: var(--brand-2); font-weight: 700; }
  .empty { color: var(--text-muted); font-size: 0.9rem; text-align: center; padding: 1rem 0; }
  .ledger { display: flex; flex-direction: column; gap: 1px; background: var(--border); border-radius: 12px; overflow: hidden; }
  .ledger.scroll { max-height: 300px; overflow-y: auto; }
  .led-row { display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: 10px; padding: 0.5rem 0.8rem; background: var(--surface); }
  .led-date { font-size: 0.72rem; color: var(--text-faint); font-variant-numeric: tabular-nums; white-space: nowrap; }
  .led-reason { color: var(--text); font-size: 0.86rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .led-delta { font-family: var(--font-display); font-weight: 700; font-size: 0.88rem; white-space: nowrap; }
  .led-delta.pos { color: var(--brand-2); }
  .led-delta.neg { color: #fb7185; }
</style>
