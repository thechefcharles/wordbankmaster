<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getBank, repayLoan, takeLoan, setAutoRepay } from '$lib/stores/statsStore.js';
  import { track } from '$lib/analytics.js';
  import { fx } from '$lib/sound.js';

  /** @type {{ bank:number, loan:number, net_worth:number, auto_repay:boolean, in_the_red:boolean, loan_cap:number, ledger:any[] }|null} */
  let b = null;
  let loading = true;
  let repayAmt = '';
  let borrowAmt = '';
  let busy = false;
  $: loanRoom = b ? Math.max(0, (b.loan_cap ?? 10000) - b.loan) : 0;

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
      loan_payment: 'Loan payment',
      loan_taken: 'Loan taken',
      loan_interest: 'Loan interest',
      arcade_cashout: 'Cash Game cash-out',
      cosmetic_buy: 'Shop purchase',
      wager_win: 'Won a wager',
      wager_stake: 'Wager staked',
      wager_refund: 'Wager refunded',
      interest: 'Loan interest'
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

  async function borrow(/** @type {number} */ amt) {
    if (busy || !b) return;
    const take = Math.min(amt, loanRoom);
    if (take <= 0) return;
    busy = true;
    const res = await takeLoan(take);
    busy = false;
    if (res && res.ok !== false) { b = res; borrowAmt = ''; fx('select'); track('loan_taken', { amount: take }); }
  }

  async function toggleAutoRepay() {
    if (busy || !b) return;
    busy = true;
    const res = await setAutoRepay(!b.auto_repay);
    busy = false;
    if (res) b = res;
  }
</script>

<svelte:head><title>WordBank — Cash & Net Worth</title></svelte:head>

<main class="bank-page">
  <button class="back-btn" on:click={() => goto('/')}>← Menu</button>

  {#if loading}
    <p class="loading">Loading…</p>
  {:else if b}
    <p class="nw-label">Net Worth</p>
    <div class="net-worth" class:neg={b.net_worth < 0}>{fmt(b.net_worth)}</div>
    <p class="nw-sub">Cash on hand minus what you owe</p>
    {#if b.in_the_red}<div class="red-badge">🔴 In the Red — you owe more than you hold</div>{/if}

    <div class="stat-row">
      <div class="stat"><span class="sv">{fmt(b.bank)}</span><span class="sc">Cash on hand</span></div>
      <div class="stat loan"><span class="sv">{fmt(b.loan)}</span><span class="sc">Loan owed</span></div>
    </div>

    <!-- Borrow -->
    <div class="loan-box">
      <p class="loan-copy">
        <strong>The House</strong> will front you Cash anytime — <strong>5%/day interest</strong>, up to {fmt(b.loan_cap)} total debt.
        {#if loanRoom > 0}You can borrow up to <strong>{fmt(loanRoom)}</strong> more.{:else}You're at the borrowing cap.{/if}
      </p>
      <div class="pay-row">
        <input class="amt" type="number" min="1" max={loanRoom} placeholder="Amount" bind:value={borrowAmt} disabled={loanRoom <= 0} />
        <button class="pay-btn borrow" disabled={busy || loanRoom <= 0} on:click={() => borrow(Math.floor(Number(borrowAmt) || 0))}>Borrow</button>
      </div>
    </div>

    {#if b.loan > 0}
      <div class="loan-box">
        <p class="loan-copy">You owe <strong>{fmt(b.loan)}</strong>. Interest accrues daily until it's paid — clear it to go debt-free and grow your Net Worth.</p>
        <div class="pay-row">
          <input class="amt" type="number" min="1" placeholder="Amount" bind:value={repayAmt} />
          <button class="pay-btn" disabled={busy} on:click={() => payLoan(Math.floor(Number(repayAmt) || 0))}>Pay</button>
          <button class="pay-btn ghost" disabled={busy} on:click={() => payLoan(b?.loan ?? 0)}>Pay all</button>
        </div>
        <button class="auto-row" disabled={busy} on:click={toggleAutoRepay}>
          <span class="auto-box" class:on={b.auto_repay}>{b.auto_repay ? '✓' : ''}</span>
          Auto-repay — skim 10% of winnings toward this loan
        </button>
      </div>
    {:else}
      <div class="debt-free">🎉 Debt-free! Your Cash is all yours.</div>
    {/if}

    <h2 class="hist-title">Recent activity</h2>
    {#if b.ledger.length === 0}
      <p class="empty">No transactions yet. Win the Daily, finish quests, or cash out a Cash Game run to grow your Cash.</p>
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

    <p class="hint">Cash is in-game money — earn it by playing, risk it in the Cash Game, wager friends, and spend it on power-ups &amp; cosmetics. It can't be bought with real money or cashed out.</p>
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
  .net-worth.neg { color: #fb7185; }
  .nw-sub { color: var(--text-faint); font-size: 0.78rem; margin: 0.2rem 0 0; }

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
  .pay-btn.borrow { color: #06210f; background: linear-gradient(135deg,#fbbf24,#f59e0b); }
  .pay-btn:disabled { opacity: 0.5; }
  .red-badge {
    display: inline-block; margin: 0.6rem auto 0; padding: 0.4rem 0.9rem; border-radius: 999px;
    font-size: 0.8rem; font-weight: 700; color: #fb7185;
    background: rgba(251,113,133,0.12); border: 1px solid rgba(251,113,133,0.35);
  }
  .auto-row {
    display: flex; align-items: center; gap: 0.5rem; width: 100%; margin-top: 0.7rem; padding: 0;
    background: none; border: none; cursor: pointer; color: var(--text-muted); font-size: 0.82rem; text-align: left;
  }
  .auto-box {
    width: 18px; height: 18px; flex-shrink: 0; border-radius: 5px; display: grid; place-items: center;
    border: 1px solid var(--border); background: var(--surface-2, rgba(255,255,255,0.04)); color: #06210f; font-size: 0.7rem; font-weight: 800;
  }
  .auto-box.on { background: var(--brand-grad, linear-gradient(135deg,#34d399,#a3e635)); border-color: transparent; }
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
