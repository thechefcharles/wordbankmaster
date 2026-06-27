<script>
  import { onMount } from 'svelte';
  import PageNav from "$lib/components/PageNav.svelte";
  import { getBank, getFreeplayCashoutStatus, freeplayCashout } from '$lib/stores/statsStore.js';
  import { requirePin } from '$lib/pinConfirm.js';
  import { track } from '$lib/analytics.js';
  import { fx } from '$lib/sound.js';

  /** @type {{ bank:number, net_worth:number, ledger:any[] }|null} */
  let b = null;
  /** @type {any|null} */
  let cashout = null;
  let loading = true;
  let busy = '';
  let msg = '';

  async function load() {
    const [bank, co] = await Promise.all([getBank(500), getFreeplayCashoutStatus()]);
    b = bank; cashout = co;
  }
  onMount(async () => {
    track('bank_view');
    try { await load(); } finally { loading = false; }
  });

  async function doCashout() {
    if (busy || !cashout) return;
    const amt = Math.min(cashout.max_cash, cashout.cap_remaining);
    if (amt <= 0) return;
    try { await requirePin(`Exchange ${(amt * 40).toLocaleString()} credits → $${amt}`, [
      { label: 'Credits', value: (amt * 40).toLocaleString() },
      { label: 'You receive', value: '$' + amt }
    ]); } catch { return; }
    busy = 'cashout'; msg = '';
    const res = await freeplayCashout(amt);
    busy = '';
    if (res?.ok) { fx('win'); track('freeplay_cashout', { cash: res.cashed }); await load(); }
    else { msg = res?.reason === 'daily_cap' ? "You've hit today's $50 exchange cap — come back tomorrow." : 'Could not exchange right now.'; }
  }

  const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();
  const when = (/** @type {string} */ at) => {
    if (!at) return '';
    const d = new Date(at), now = new Date();
    const day = d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    return d.toDateString() === now.toDateString() ? d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' }) : day;
  };

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
      <div class="bal cash">
        <span class="bal-label">💰 Cash</span>
        <span class="bal-value">{fmt(b.bank)}</span>
        <span class="bal-sub">Your score — can't be bought</span>
      </div>
      {#if cashout}
        <div class="bal credits">
          <span class="bal-label">🎟️ Credits</span>
          <span class="bal-value cr">{(cashout.credits ?? 0).toLocaleString()}</span>
          <span class="bal-sub">From Free Play</span>
        </div>
      {/if}
    </div>

    <!-- Exchange -->
    {#if cashout && cashout.credits > 0}
      <div class="exchange">
        <div class="ex-head"><span class="ex-title">💱 Exchange</span><span class="ex-rate">40 credits = $1 · up to $50/day</span></div>
        {#if cashout.max_cash > 0 && cashout.cap_remaining > 0}
          <button class="ex-btn" disabled={busy === 'cashout'} onclick={doCashout}>
            Exchange {(Math.min(cashout.max_cash, cashout.cap_remaining) * 40).toLocaleString()} credits → ${Math.min(cashout.max_cash, cashout.cap_remaining)}
          </button>
        {:else if cashout.cap_remaining <= 0}
          <p class="ex-pending">Daily $50 exchange cap reached — come back tomorrow.</p>
        {:else}
          <p class="ex-pending">Your first 2,000 credits are your stake. Earn {(2040 - cashout.credits).toLocaleString()} more to exchange.</p>
        {/if}
      </div>
    {/if}
    {#if msg}<p class="msg">{msg}</p>{/if}

    <!-- Ledger -->
    <h2 class="hist-title">📒 Ledger</h2>
    {#if b.ledger.length === 0}
      <p class="empty">No transactions yet. Win the Daily, show up for attendance, or climb the Cash Game to grow your Cash.</p>
    {:else}
      <div class="ledger">
        {#each b.ledger as e}
          <div class="led-row">
            <span class="led-main"><span class="led-reason">{reasonLabel(e.reason)}</span>{#if e.at}<span class="led-when">{when(e.at)}</span>{/if}</span>
            <span class="led-right">
              <span class="led-delta" class:pos={e.delta > 0} class:neg={e.delta < 0}>{e.delta > 0 ? '+' : '−'}{fmt(Math.abs(e.delta))}</span>
              {#if e.balance_after != null}<span class="led-bal">{fmt(e.balance_after)}</span>{/if}
            </span>
          </div>
        {/each}
      </div>
    {/if}
  {/if}
</main>

<style>
  .bank-page { max-width: 480px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }
  .bank-title { font-family: var(--font-display); font-size: 1.5rem; margin: 4px 0 16px; text-align: center; }
  .loading { color: var(--text-muted); padding: 2rem; text-align: center; }

  .balances { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 14px; }
  .bal { display: flex; flex-direction: column; gap: 2px; padding: 14px; border-radius: 16px; background: var(--surface); border: 1px solid var(--border); }
  .bal-label { font-size: 0.78rem; color: var(--text-muted); font-weight: 700; }
  .bal-value { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 1.7rem; color: var(--brand-2); }
  .bal-value.cr { color: #6ee7b7; }
  .bal-sub { font-size: 0.68rem; color: var(--text-faint); }

  .exchange { padding: 14px; border-radius: 16px; margin-bottom: 14px;
    background: linear-gradient(135deg, rgba(110,231,183,0.08), rgba(110,231,183,0.02)); border: 1px solid rgba(110,231,183,0.3); }
  .ex-head { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; margin-bottom: 10px; }
  .ex-title { font-family: var(--font-display); font-weight: 800; font-size: 0.95rem; }
  .ex-rate { font-size: 0.68rem; color: var(--text-faint); text-align: right; }
  .ex-btn { width: 100%; padding: 0.8rem; border: none; border-radius: 12px; cursor: pointer; font-weight: 800; color: #06281d;
    background: linear-gradient(135deg, #6ee7b7, #34d399); }
  .ex-btn:disabled { opacity: 0.6; }
  .ex-pending { font-size: 0.82rem; color: var(--text-muted); margin: 0; text-align: center; }
  .msg { text-align: center; color: #fb7185; font-size: 0.85rem; margin: 0.4rem 0 0; }

  .hist-title { font-family: var(--font-display); font-size: 1rem; margin: 1.4rem 0 0.6rem; }
  .empty { color: var(--text-muted); font-size: 0.9rem; text-align: center; padding: 1rem 0; }
  .ledger { display: flex; flex-direction: column; gap: 1px; background: var(--border); border-radius: 12px; overflow: hidden; }
  .led-row { display: flex; justify-content: space-between; align-items: center; gap: 10px; padding: 0.7rem 0.9rem; background: var(--surface); }
  .led-main { display: flex; flex-direction: column; gap: 1px; min-width: 0; }
  .led-reason { color: var(--text); font-size: 0.9rem; }
  .led-when { color: var(--text-faint); font-size: 0.72rem; }
  .led-right { display: flex; flex-direction: column; align-items: flex-end; gap: 1px; flex: none; }
  .led-delta { font-family: var(--font-display); font-weight: 700; font-size: 0.92rem; }
  .led-delta.pos { color: var(--brand-2); }
  .led-delta.neg { color: #fb7185; }
  .led-bal { font-size: 0.68rem; color: var(--text-faint); }
</style>
