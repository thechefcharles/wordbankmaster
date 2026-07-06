<script>
  import { onMount } from 'svelte';
  import PageNav from "$lib/components/PageNav.svelte";
  import { getBank, takeLoan, repayLoan } from '$lib/stores/statsStore.js';
  import InventoryList from '$lib/components/InventoryList.svelte';
  import { requirePin } from '$lib/pinConfirm.js';
  import { track } from '$lib/analytics.js';
  import { fx } from '$lib/sound.js';

  /** @type {{ bank:number, net_worth:number, loan:number, loan_cap:number, in_the_red:boolean, ledger:any[] }|null} */
  let b = null;
  let loading = true;
  /** @type {{title:string, desc:string}|null} */
  let info = null;

  // 💸 Loan Shark
  let borrowAmt = 100;      // $ to borrow (dial)
  let repayAmt = 0;         // $ to repay (dial)
  let loanBusy = '';
  let loanMsg = '';
  $: loanCap = b?.loan_cap ?? 0;
  $: owed = b?.loan ?? 0;
  $: feeOnBorrow = Math.round(borrowAmt * 0.25);
  $: if (borrowAmt > loanCap) borrowAmt = loanCap;
  $: if (borrowAmt < 10 && loanCap >= 10) borrowAmt = 10;
  $: maxRepay = Math.max(0, Math.min(owed, b?.bank ?? 0));
  $: if (repayAmt > maxRepay) repayAmt = maxRepay;

  async function load() {
    b = await getBank(500);
    repayAmt = Math.max(0, Math.min(b?.loan ?? 0, b?.bank ?? 0));
  }
  onMount(async () => {
    track('bank_view');
    try { await load(); } finally { loading = false; }
  });

  async function borrow() {
    if (loanBusy || borrowAmt < 10) return;
    const total = borrowAmt + Math.round(borrowAmt * 0.25);
    try { await requirePin(`Borrow $${borrowAmt.toLocaleString()} — you'll owe $${total.toLocaleString()}`, [
      { label: 'You receive', value: '$' + borrowAmt.toLocaleString() },
      { label: 'Fee (25%)', value: '$' + Math.round(borrowAmt * 0.25).toLocaleString() },
      { label: 'You owe', value: '$' + total.toLocaleString() }
    ]); } catch { return; }
    loanBusy = 'borrow'; loanMsg = '';
    const res = await takeLoan(borrowAmt);
    loanBusy = '';
    if (res?.ok) { fx('win'); track('take_loan', { amount: borrowAmt, owed: res.owed }); await load(); }
    else { loanMsg = res?.reason === 'active_loan' ? 'Pay off your current loan first.' : res?.reason === 'over_cap' ? `Over your $${(res.cap ?? loanCap).toLocaleString()} limit.` : 'Could not borrow right now.'; }
  }
  async function repay(/** @type {number|null} */ amt) {
    if (loanBusy) return;
    const pay = amt ?? maxRepay;
    if (pay <= 0) return;
    loanBusy = 'repay'; loanMsg = '';
    const res = await repayLoan(amt);
    loanBusy = '';
    if (res?.ok) { fx('tap'); track('repay_loan', { amount: res.paid, cleared: res.cleared }); await load(); }
    else { loanMsg = res?.reason === 'insufficient' ? 'Not enough Cash to repay.' : 'Could not repay right now.'; }
  }

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
      daily_win: 'Daily reward', daily_reward: 'Daily reward',
      attendance: 'Attendance reward', arcade_cashout: 'Cash Game cash-out', climb_bounty: 'Cash Game bounty',
      freeplay_reward: 'Free Play reward', freeplay_cashout: 'Exchanged credits → Cash',
      cosmetic_buy: 'Store purchase', powerup_buy: 'Power-up purchase',
      loan_take: 'Loan received', loan_repay: 'Loan repayment', loan_skim: 'Loan auto-payment',
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

    <!-- 💸 Loan Shark -->
    {#if b.in_the_red}
      <!-- In debt: repay panel + the teeth -->
      <div class="loan-card debt">
        <div class="loan-head">
          <span class="loan-title">🦈 You owe the Shark</span>
          <span class="loan-owed">{fmt(owed)}</span>
        </div>
        <p class="loan-note">Store is locked and half of every payout auto-pays your debt until it's clear. Your net worth is <b class="neg">{fmt(b.net_worth)}</b>.</p>
        {#if maxRepay > 0}
          <div class="loan-dial">
            <button class="loan-step" onclick={() => repayAmt = Math.max(0, repayAmt - 50)} aria-label="Less" disabled={repayAmt <= 0}>−</button>
            <div class="loan-amt"><span class="loan-usd">{fmt(repayAmt)}</span><span class="loan-sub">of {fmt(owed)} owed</span></div>
            <button class="loan-step" onclick={() => repayAmt = Math.min(maxRepay, repayAmt + 50)} aria-label="More" disabled={repayAmt >= maxRepay}>+</button>
          </div>
          <input class="loan-slider" type="range" min="0" max={maxRepay} step="10" bind:value={repayAmt} />
          <div class="loan-actions">
            <button class="loan-btn ghost" disabled={!!loanBusy || repayAmt <= 0} onclick={() => repay(repayAmt)}>Repay {fmt(repayAmt)}</button>
            <button class="loan-btn pay" disabled={!!loanBusy} onclick={() => repay(null)}>Pay max ({fmt(maxRepay)})</button>
          </div>
        {:else}
          <p class="loan-note">Earn some Cash (play the Daily) then come back to repay.</p>
        {/if}
        {#if loanMsg}<p class="msg">{loanMsg}</p>{/if}
      </div>
    {:else if loanCap > 0}
      <!-- No debt: borrow panel -->
      <details class="loan-card">
        <summary class="loan-summary">🦈 Need Cash? Borrow up to {fmt(loanCap)} <span class="loan-cv">▾</span></summary>
        <p class="loan-note">A 25% fee, one loan at a time. While you owe, the Store locks and half of every payout auto-pays it down.</p>
        <div class="loan-dial">
          <button class="loan-step" onclick={() => borrowAmt = Math.max(10, borrowAmt - 50)} aria-label="Less" disabled={borrowAmt <= 10}>−</button>
          <div class="loan-amt"><span class="loan-usd">{fmt(borrowAmt)}</span><span class="loan-sub">you'll owe {fmt(borrowAmt + feeOnBorrow)}</span></div>
          <button class="loan-step" onclick={() => borrowAmt = Math.min(loanCap, borrowAmt + 50)} aria-label="More" disabled={borrowAmt >= loanCap}>+</button>
        </div>
        <input class="loan-slider" type="range" min="10" max={loanCap} step="10" bind:value={borrowAmt} />
        <button class="loan-btn borrow" disabled={!!loanBusy || borrowAmt < 10} onclick={borrow}>🦈 Borrow {fmt(borrowAmt)} (fee {fmt(feeOnBorrow)})</button>
        {#if loanMsg}<p class="msg">{loanMsg}</p>{/if}
      </details>
    {/if}

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

  /* 💸 Loan Shark */
  .loan-card { border-radius: 16px; padding: 14px 16px; margin: 0 0 14px; border: 1px solid var(--border); background: var(--surface); }
  .loan-card.debt { border-color: rgba(248,113,113,0.5); background: linear-gradient(135deg, rgba(248,113,113,0.12), rgba(248,113,113,0.03)); }
  .loan-head { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; }
  .loan-title { font-family: var(--font-display); font-weight: 800; font-size: 1rem; }
  .loan-owed { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 1.5rem; color: #fb7185; }
  .loan-summary { cursor: pointer; font-family: var(--font-display); font-weight: 700; font-size: 0.95rem; list-style: none; display: flex; align-items: center; justify-content: space-between; }
  .loan-summary::-webkit-details-marker { display: none; }
  .loan-cv { color: var(--text-faint); font-size: 0.8rem; }
  .loan-note { font-size: 0.78rem; color: var(--text-muted); margin: 8px 0; line-height: 1.4; }
  .loan-note .neg { color: #fb7185; }
  .loan-dial { display: flex; align-items: center; justify-content: center; gap: 12px; width: 100%; max-width: 320px; margin: 4px auto 0; }
  .loan-step { width: 44px; height: 44px; flex: none; border-radius: 12px; cursor: pointer; font-size: 1.5rem; font-weight: 800; background: var(--surface); border: 1px solid var(--border); color: var(--text); display: grid; place-items: center; }
  .loan-step:disabled { opacity: 0.3; cursor: default; }
  .loan-amt { flex: 1; display: flex; flex-direction: column; align-items: center; gap: 1px; }
  .loan-usd { font-family: 'Orbitron', var(--font-display); font-weight: 800; color: var(--brand-2); font-size: 1.6rem; line-height: 1; }
  .loan-sub { font-size: 0.68rem; color: var(--text-faint); }
  .loan-slider { width: 100%; max-width: 320px; display: block; margin: 12px auto; accent-color: #fb7185; }
  .loan-actions { display: flex; gap: 8px; }
  .loan-btn { flex: 1; padding: 0.8rem; border: none; border-radius: 12px; cursor: pointer; font-weight: 800; font-size: 0.92rem; }
  .loan-btn.borrow { width: 100%; color: #2a1005; background: linear-gradient(135deg, #fbbf24, #f59e0b); }
  .loan-btn.pay { color: #06281d; background: linear-gradient(135deg, #6ee7b7, #34d399); }
  .loan-btn.ghost { background: var(--surface); border: 1px solid var(--border); color: var(--text); }
  .loan-btn:disabled { opacity: 0.45; cursor: default; }

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
