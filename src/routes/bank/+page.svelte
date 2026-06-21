<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getBank, repayLoan } from '$lib/stores/statsStore.js';
  import { track } from '$lib/analytics.js';
  import { fx } from '$lib/sound.js';

  /** @type {{ bank:number, loan:number, net_worth:number, ledger:any[] }|null} */
  let b = null;
  let loading = true;
  let repayAmt = '';
  let busy = false;

  onMount(async () => {
    track('bank_view');
    try { b = await getBank(); } finally { loading = false; }
  });

  const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();

  /** @param {string} reason */
  function reasonLabel(reason) {
    return ({
      quest_reward: 'Daily quests reward',
      daily_win: 'Daily win bonus',
      loan_payment: 'Loan payment',
      arcade_cashout: 'Arcade cash-out',
      wager_win: 'Won a wager',
      wager_stake: 'Wager staked',
      interest: 'Bank interest'
    })[reason] || reason;
  }

  async function payLoan(/** @type {number} */ amt) {
    if (busy || !b || b.loan <= 0) return;
    const pay = Math.min(amt, b.loan, b.bank);
    if (pay <= 0) return;
    busy = true;
    const res = await repayLoan(pay);
    busy = false;
    if (res) { b = res; repayAmt = ''; fx('tap'); track('loan_repay', { amount: pay }); }
  }
</script>

<svelte:head><title>WordBank — Your Bank</title></svelte:head>

<main class="bank-page">
  <button class="back-btn" on:click={() => goto('/')}>← Menu</button>

  {#if loading}
    <p class="loading">Loading…</p>
  {:else if b}
    <p class="nw-label">Net Worth</p>
    <div class="net-worth" class:neg={b.net_worth < 0}>{fmt(b.net_worth)}</div>

    <div class="stat-row">
      <div class="stat"><span class="sv">{fmt(b.bank)}</span><span class="sc">Bank</span></div>
      <div class="stat loan"><span class="sv">{fmt(b.loan)}</span><span class="sc">Loan owed</span></div>
    </div>

    {#if b.loan > 0}
      <div class="loan-box">
        <p class="loan-copy">The House fronted you <strong>$5,000</strong> to get started. Pay it back to go debt-free — everything after is pure profit.</p>
        <div class="pay-row">
          <input class="amt" type="number" min="1" placeholder="Amount" bind:value={repayAmt} />
          <button class="pay-btn" disabled={busy} on:click={() => payLoan(Math.floor(Number(repayAmt) || 0))}>Pay</button>
          <button class="pay-btn ghost" disabled={busy} on:click={() => payLoan(b?.loan ?? 0)}>Pay all</button>
        </div>
      </div>
    {:else}
      <div class="debt-free">🎉 Debt-free! Your Bank is all yours.</div>
    {/if}

    <h2 class="hist-title">Recent activity</h2>
    {#if b.ledger.length === 0}
      <p class="empty">No transactions yet. Win the Daily, finish quests, or cash out an Arcade run to grow your Bank.</p>
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

    <p class="hint">Your Bank is in-game money — earn it by playing, spend it on wagers and (soon) power-ups &amp; cosmetics. It can't be bought or cashed out.</p>
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
  .net-worth.neg { color: var(--text-muted); }

  .stat-row { display: flex; justify-content: center; gap: 0.6rem; margin: 1.2rem 0 0; }
  .stat { flex: 1; max-width: 160px; display: flex; flex-direction: column; gap: 3px; padding: 0.8rem 0.5rem;
    background: var(--surface); border: 1px solid var(--border); border-radius: 14px; }
  .stat.loan { border-color: rgba(251,113,133,0.3); }
  .sv { font-family: var(--font-display); font-weight: 700; font-size: 1.25rem; color: var(--text); }
  .stat.loan .sv { color: #fb7185; }
  .sc { font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--text-faint); }

  .loan-box { margin-top: 1.4rem; padding: 1rem; background: var(--surface); border: 1px solid var(--border); border-radius: 16px; text-align: left; }
  .loan-copy { margin: 0 0 0.8rem; color: var(--text-muted); font-size: 0.9rem; }
  .pay-row { display: flex; gap: 0.5rem; }
  .amt { flex: 1; min-width: 0; padding: 0.6rem 0.8rem; border-radius: 10px; border: 1px solid var(--border); background: var(--surface-2, rgba(255,255,255,0.04)); color: var(--text); }
  .pay-btn { padding: 0.6rem 1rem; border: none; border-radius: 10px; cursor: pointer; font-weight: 700; color: #06210f; background: var(--brand-grad, linear-gradient(135deg,#34d399,#a3e635)); }
  .pay-btn.ghost { background: transparent; color: var(--brand-2); border: 1px solid rgba(163,230,53,0.4); }
  .pay-btn:disabled { opacity: 0.5; }
  .debt-free { margin-top: 1.4rem; padding: 0.9rem; border-radius: 14px; background: linear-gradient(135deg, rgba(52,211,153,0.12), rgba(163,230,53,0.05)); border: 1px solid rgba(163,230,53,0.4); font-weight: 700; }

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
