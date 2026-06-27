<script>
  import { onMount } from 'svelte';
  import PageNav from "$lib/components/PageNav.svelte";
  import { getBank, getFreeplayCashoutStatus, freeplayCashout } from '$lib/stores/statsStore.js';
  import InventoryList from '$lib/components/InventoryList.svelte';
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
  /** @type {{title:string, desc:string}|null} */
  let info = null;

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
      <button class="bal cash" onclick={() => info = { title: '💰 Cash', desc: 'Your main currency — and your score. Earn it by solving puzzles in the Daily, Cash Game, and challenges. Spend it on letters mid-game and on power-ups & cosmetics in the Store. It can’t be bought with real money.' }}>
        <span class="bal-label">💰 Cash <span class="bal-i">ⓘ</span></span>
        <span class="bal-value">{fmt(b.bank)}</span>
      </button>
      {#if cashout}
        <button class="bal credits" onclick={() => info = { title: '🎟️ Credits', desc: 'Earned in Free Play — a practice stack you can build up. Exchange them for Cash right here in the Bank (40 credits = $1, up to $50 a day).' }}>
          <span class="bal-label">🎟️ Credits <span class="bal-i">ⓘ</span></span>
          <span class="bal-value cr">{(cashout.credits ?? 0).toLocaleString()}</span>
        </button>
      {/if}
    </div>

    <!-- Items (your vault) -->
    <h2 class="hist-title">🎒 Your Items</h2>
    <InventoryList addHref="/shop?from=bank" />

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

  .balances { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 14px; }
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
