<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { getProfileDetail } from '$lib/stores/statsStore.js';
  import HistoryList from '$lib/components/HistoryList.svelte';
  import BadgesPanel from '$lib/components/BadgesPanel.svelte';
  import { track } from '$lib/analytics.js';

  /** @type {'stats'|'history'|'badges'} */
  let tab = $state('stats');
  /** @type {any|null} */
  let d = $state(null);
  let loading = $state(true);

  onMount(async () => {
    track('profile_view');
    const t = $page.url.searchParams.get('tab');
    if (t === 'history' || t === 'badges') tab = t;
    try { d = await getProfileDetail(); } finally { loading = false; }
  });

  const fmt = (/** @type {any} */ n) => '$' + Math.round(Number(n ?? 0)).toLocaleString();
  const mult = (/** @type {any} */ x) => x ? (Number(x) / 100).toFixed(1) + '×' : '—';
  const time = (/** @type {any} */ ms) => !ms ? '—' : Number(ms) < 60000 ? Math.round(Number(ms) / 1000) + 's' : (Number(ms) / 60000).toFixed(1) + 'm';
  const pct = (/** @type {number} */ w, /** @type {number} */ n) => n > 0 ? Math.round((w / n) * 100) + '%' : '—';
</script>

<svelte:head><title>WordBank — Profile</title></svelte:head>

{#snippet chip(value, label)}
  <div class="stat"><span class="sv">{value}</span><span class="sc">{label}</span></div>
{/snippet}

<main class="you-page">
  <div class="topbar">
    <button class="back-btn" onclick={() => goto('/')}>← Menu</button>
    <h1 class="page-title">Profile</h1>
    <button class="gear" onclick={() => goto('/?account=1')} title="Settings" aria-label="Settings">⚙️</button>
  </div>

  {#if loading}
    <p class="muted">Loading…</p>
  {:else if d}
    <header class="head">
      <div class="coin" style={d.color ? `--c:${d.color}` : ''}>{(d.username || '?').slice(0, 1).toUpperCase()}</div>
      <div class="uname">{d.username ? '@' + d.username : 'You'}</div>
      <div class="nw">{fmt(d.net_worth)}</div>
      <span class="nw-sub">Cash</span>
    </header>

    <div class="tabs">
      <button class="tab" class:active={tab === 'stats'} onclick={() => tab = 'stats'}>Stats</button>
      <button class="tab" class:active={tab === 'history'} onclick={() => tab = 'history'}>History</button>
      <button class="tab" class:active={tab === 'badges'} onclick={() => tab = 'badges'}>Badges</button>
    </div>

    {#if tab === 'stats'}
      <div class="sec-title">📊 Overall</div>
      <div class="grid">
        {@render chip((d.overall.puzzles_solved ?? 0).toLocaleString(), 'Puzzles solved')}
        {@render chip(d.overall.games_played ?? 0, 'Games played')}
        {@render chip(d.overall.clean_solves ?? 0, 'Clean solves')}
        {@render chip(mult(d.overall.avg_multiple), 'Avg multiple')}
        {@render chip(mult(d.overall.best_multiple), 'Best multiple')}
        {@render chip(fmt(d.overall.earned), 'Earned')}
      </div>
      <p class="spent-line">Lifetime spent: <b>{fmt(d.overall.spent)}</b></p>

      <div class="sec-title">📅 Daily</div>
      <div class="grid">
        {@render chip('🔥 ' + (d.daily.current_streak ?? 0), 'Streak')}
        {@render chip(d.daily.best_streak ?? 0, 'Best streak')}
        {@render chip(pct(d.daily.won ?? 0, d.daily.played ?? 0), 'Win rate')}
        {@render chip(d.daily.won ?? 0, 'Dailies won')}
        {@render chip(mult(d.daily.best_multiple), 'Best ×')}
        {@render chip(time(d.daily.fastest_ms), 'Fastest')}
      </div>

      <div class="sec-title">🎰 Cash Game</div>
      <div class="grid">
        {@render chip('#' + (d.cash_game.position ?? 0), 'Furthest')}
        {@render chip(d.cash_game.solved ?? 0, 'Solved')}
        {@render chip(fmt(d.cash_game.earned), 'Earned')}
        {@render chip(mult(d.cash_game.best_multiple), 'Best ×')}
        {@render chip(time(d.cash_game.fastest_ms), 'Fastest')}
      </div>

      <div class="sec-title">⚔️ Challenges</div>
      <div class="grid">
        {@render chip(`${d.challenges.wins ?? 0}-${d.challenges.losses ?? 0}-${d.challenges.ties ?? 0}`, 'W-L-T')}
        {@render chip(pct(d.challenges.wins ?? 0, d.challenges.played ?? 0), 'Win rate')}
        {@render chip(fmt(d.challenges.biggest_pot), 'Biggest pot')}
      </div>

      <div class="sec-title">🎲 Arcade</div>
      <div class="grid">
        {@render chip(fmt(d.arcade.best_bankroll), 'Best run')}
        {@render chip(d.arcade.best_streak ?? 0, 'Best streak')}
      </div>

      {#if (d.categories ?? []).length}
        <div class="sec-title">🗂️ Categories</div>
        <div class="cats">
          {#each d.categories as c}
            <div class="cat-row">
              <span class="cat-name">{c.category}</span>
              <span class="cat-meta">{c.solves} solved{#if c.best_multiple} · best {mult(c.best_multiple)}{/if}</span>
            </div>
          {/each}
        </div>
      {/if}
    {:else if tab === 'history'}
      <HistoryList />
    {:else}
      <BadgesPanel />
    {/if}
  {/if}
</main>

<style>
  .you-page { max-width: 520px; margin: 0 auto; padding: 16px 14px 60px; }
  .topbar { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  .back-btn { background: none; border: none; color: var(--text-muted); font-size: 0.92rem; cursor: pointer; padding: 6px 0; }
  .page-title { font-family: var(--font-display); font-size: 1.2rem; margin: 0; }
  .gear { background: none; border: none; font-size: 1.1rem; cursor: pointer; padding: 6px; opacity: 0.85; }
  .gear:hover { opacity: 1; }
  .muted { color: var(--text-muted); text-align: center; padding: 2rem 0; }

  .head { text-align: center; margin: 8px 0 18px; }
  .coin { width: 64px; height: 64px; margin: 0 auto 8px; border-radius: 50%; display: grid; place-items: center;
    font-family: var(--font-display); font-weight: 800; font-size: 1.6rem; color: #3a2a00;
    background: linear-gradient(135deg, var(--c, #fde047), #f59e0b); box-shadow: 0 0 24px rgba(251,191,36,0.4); }
  .uname { font-family: var(--font-display); font-weight: 700; font-size: 1.3rem; }
  .nw { font-family: 'Orbitron', var(--font-display); font-weight: 800; font-size: 2.1rem; color: #fde047;
    margin-top: 10px; text-shadow: 0 0 18px rgba(251,191,36,0.5); }
  .nw-sub { font-size: 0.72rem; color: var(--text-faint); text-transform: uppercase; letter-spacing: 0.1em; }

  .tabs { display: flex; gap: 8px; margin: 0 0 16px; }
  .tab { flex: 1; padding: 9px 0; border-radius: 12px; border: 1px solid var(--border); background: var(--surface);
    color: var(--text-muted); font-weight: 700; font-size: 0.88rem; cursor: pointer; }
  .tab.active { background: linear-gradient(135deg, #fde047, #f59e0b); color: #3a2a00; border-color: transparent; }

  .sec-title { font-family: var(--font-display); font-size: 0.78rem; font-weight: 700; letter-spacing: 0.06em;
    text-transform: uppercase; color: var(--gold); text-align: left; margin: 18px 2px 8px; }
  .grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px; }
  .stat { display: flex; flex-direction: column; gap: 3px; padding: 0.85rem 0.4rem; background: var(--surface); border: 1px solid var(--border); border-radius: 14px; text-align: center; }
  .sv { font-family: var(--font-display); font-weight: 800; font-size: 1.02rem; color: var(--text); }
  .sc { font-size: 0.58rem; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-faint); }
  .spent-line { text-align: center; color: var(--text-muted); font-size: 0.82rem; margin: 10px 0 0; }
  .spent-line b { color: var(--text); }

  .cats { display: flex; flex-direction: column; gap: 6px; }
  .cat-row { display: flex; justify-content: space-between; align-items: center; gap: 10px; padding: 9px 11px;
    background: var(--surface); border: 1px solid var(--border); border-radius: 10px; }
  .cat-name { font-weight: 600; color: var(--text); font-size: 0.86rem; }
  .cat-meta { color: var(--text-faint); font-size: 0.74rem; }
</style>
