<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { getProfileStats } from '$lib/stores/statsStore.js';
  import { badgeInfo } from '$lib/badges.js';
  import HistoryList from '$lib/components/HistoryList.svelte';
  import BadgesPanel from '$lib/components/BadgesPanel.svelte';
  import { track } from '$lib/analytics.js';

  /** @type {'stats'|'history'|'badges'} */
  let tab = $state('stats');
  /** @type {any|null} */
  let s = $state(null);
  let loading = $state(true);

  onMount(async () => {
    track('profile_view');
    const t = $page.url.searchParams.get('tab');
    if (t === 'history' || t === 'badges') tab = t;
    try { s = await getProfileStats(); } finally { loading = false; }
  });

  const fmt = (/** @type {any} */ n) => '$' + Math.round(Number(n ?? 0)).toLocaleString();
  const mult = (/** @type {any} */ x) => x ? (Number(x) / 100).toFixed(1) + '×' : '—';
  let winPct = $derived(s && s.games_played > 0 ? Math.round((s.games_won / s.games_played) * 100) : 0);
  let record = $derived(s ? `${s.challenge_wins ?? 0}-${s.challenge_losses ?? 0}-${s.challenge_ties ?? 0}` : '—');
</script>

<svelte:head><title>WordBank — You</title></svelte:head>

<main class="you-page">
  <button class="back-btn" onclick={() => goto('/')}>← Menu</button>

  {#if loading}
    <p class="muted">Loading…</p>
  {:else if s}
    <header class="head">
      <div class="coin" style={s.color ? `--c:${s.color}` : ''}>{(s.username || '?').slice(0, 1).toUpperCase()}</div>
      <h1>{s.username ? '@' + s.username : 'You'}</h1>
      <div class="nw" class:neg={Number(s.net_worth) < 0}>{fmt(s.net_worth)}</div>
      <span class="nw-sub">Net Worth</span>
    </header>

    <div class="tabs">
      <button class="tab" class:active={tab === 'stats'} onclick={() => tab = 'stats'}>Stats</button>
      <button class="tab" class:active={tab === 'history'} onclick={() => tab = 'history'}>History</button>
      <button class="tab" class:active={tab === 'badges'} onclick={() => tab = 'badges'}>Badges</button>
    </div>

    {#if tab === 'stats'}
      <div class="grid">
        <div class="stat"><span class="sv">🔥 {s.current_streak}</span><span class="sc">Day streak</span></div>
        <div class="stat"><span class="sv">{s.longest_streak}</span><span class="sc">Best streak</span></div>
        <div class="stat"><span class="sv">{winPct}%</span><span class="sc">Daily win rate</span></div>
        <div class="stat"><span class="sv">{(s.puzzles_solved ?? 0).toLocaleString()}</span><span class="sc">Puzzles solved</span></div>
        <div class="stat"><span class="sv">#{s.climb_position}</span><span class="sc">Climb position</span></div>
        <div class="stat"><span class="sv">{record}</span><span class="sc">Challenge W-L-T</span></div>
        <div class="stat"><span class="sv">{mult(s.avg_multiple_x100)}</span><span class="sc">Avg multiple</span></div>
        <div class="stat"><span class="sv">{mult(s.best_multiple_x100)}</span><span class="sc">Best multiple</span></div>
        <div class="stat"><span class="sv">{fmt(s.total_earned)}</span><span class="sc">Lifetime earned</span></div>
      </div>
      <p class="spent-line">Lifetime spent: <b>{fmt(s.total_spent)}</b></p>
    {:else if tab === 'history'}
      <HistoryList />
    {:else}
      <BadgesPanel />
    {/if}
  {/if}
</main>

<style>
  .you-page { max-width: 520px; margin: 0 auto; padding: 16px 14px 60px; }
  .back-btn { background: none; border: none; color: var(--text-muted); font-size: 0.92rem; cursor: pointer; padding: 6px 0; }
  .muted { color: var(--text-muted); text-align: center; padding: 2rem 0; }

  .head { text-align: center; margin: 8px 0 18px; }
  .coin { width: 64px; height: 64px; margin: 0 auto 8px; border-radius: 50%; display: grid; place-items: center;
    font-family: var(--font-display); font-weight: 800; font-size: 1.6rem; color: #3a2a00;
    background: linear-gradient(135deg, var(--c, #fde047), #f59e0b); box-shadow: 0 0 24px rgba(251,191,36,0.4); }
  h1 { font-family: var(--font-display); font-size: 1.4rem; margin: 0; }
  .nw { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 2.1rem; color: #fde047;
    margin-top: 10px; text-shadow: 0 0 18px rgba(251,191,36,0.5); }
  .nw.neg { color: #fb7185; text-shadow: none; }
  .nw-sub { font-size: 0.72rem; color: var(--text-faint); text-transform: uppercase; letter-spacing: 0.1em; }

  .tabs { display: flex; gap: 8px; margin: 0 0 16px; }
  .tab { flex: 1; padding: 9px 0; border-radius: 12px; border: 1px solid var(--border); background: var(--surface);
    color: var(--text-muted); font-weight: 700; font-size: 0.88rem; cursor: pointer; }
  .tab.active { background: linear-gradient(135deg, #fde047, #f59e0b); color: #3a2a00; border-color: transparent; }

  .grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px; }
  .stat { display: flex; flex-direction: column; gap: 3px; padding: 0.9rem 0.4rem; background: var(--surface); border: 1px solid var(--border); border-radius: 14px; text-align: center; }
  .sv { font-family: var(--font-display); font-weight: 800; font-size: 1.05rem; color: var(--text); }
  .sc { font-size: 0.6rem; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-faint); }
  .spent-line { text-align: center; color: var(--text-muted); font-size: 0.84rem; margin: 14px 0 0; }
  .spent-line b { color: var(--text); }
</style>
