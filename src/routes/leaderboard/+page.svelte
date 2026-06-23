<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { getWealthLeaderboard, getDailyBoard, getClimbLeaderboard, getMyGroups } from '$lib/stores/statsStore.js';
  import { track } from '$lib/analytics.js';

  /** @type {'wealth'|'daily'|'climb'} */
  let board = $state('wealth');
  /** scope: 'global' | 'friends' | a group id */
  let scope = $state('friends');
  /** @type {'week'|'all'} */
  let period = $state('week');
  /** @type {any[]} */
  let rows = $state([]);
  /** @type {any[]} */
  let groups = $state([]);
  let loading = $state(true);
  let error = $state('');

  const fmt = (/** @type {any} */ n) => '$' + Math.round(Number(n ?? 0)).toLocaleString();

  async function load() {
    loading = true; error = '';
    try {
      const isGroup = scope !== 'global' && scope !== 'friends';
      const sc = isGroup ? 'group' : scope;
      const grp = isGroup ? scope : null;
      if (board === 'wealth') rows = await getWealthLeaderboard(sc, period, grp);
      else if (board === 'daily') rows = await getDailyBoard(sc, grp);
      else rows = await getClimbLeaderboard(sc, grp);
    } catch (e) {
      error = (e instanceof Error ? e.message : String(e)) || 'Failed to load';
    } finally { loading = false; }
  }

  onMount(async () => {
    track('leaderboard_view');
    groups = await getMyGroups();
    const b = $page.url.searchParams.get('board');
    if (b === 'daily' || b === 'climb' || b === 'wealth') board = b;
    await load();
  });

  // reload whenever the board / scope / period changes
  $effect(() => { board; scope; period; load(); });

  /** @param {number} rank */
  const medal = (rank) => rank === 1 ? '🥇' : rank === 2 ? '🥈' : rank === 3 ? '🥉' : String(rank);
</script>

<svelte:head><title>WordBank — Leaderboard</title></svelte:head>

<main class="lb-page">
  <button class="back-btn" onclick={() => goto('/')}>← Menu</button>
  <h1>🏆 Leaderboard</h1>

  <!-- Board selector -->
  <div class="tabs">
    <button class="tab" class:active={board === 'wealth'} onclick={() => board = 'wealth'}>💰 Wealth</button>
    <button class="tab" class:active={board === 'daily'} onclick={() => board = 'daily'}>📅 Daily</button>
    <button class="tab" class:active={board === 'climb'} onclick={() => board = 'climb'}>⚡ Climb</button>
  </div>

  <!-- Scope + (wealth) period -->
  <div class="filters">
    <select class="filter-select" bind:value={scope}>
      <option value="friends">Friends</option>
      <option value="global">Global</option>
      {#each groups as g}<option value={g.id}>👥 {g.name}</option>{/each}
    </select>
    {#if board === 'wealth'}
      <div class="seg">
        <button class="seg-btn" class:on={period === 'week'} onclick={() => period = 'week'}>This Week</button>
        <button class="seg-btn" class:on={period === 'all'} onclick={() => period = 'all'}>All-Time</button>
      </div>
    {/if}
  </div>

  <p class="caption">
    {#if board === 'wealth'}{period === 'week' ? 'Net Worth gained this week' : 'Net Worth — Cash minus Loans'}
    {:else if board === 'daily'}Today's Daily Score
    {:else}Furthest puzzle in the Cash Game{/if}
  </p>

  {#if loading}
    <p class="muted">Loading…</p>
  {:else if error}
    <p class="error">{error}</p>
  {:else if rows.length === 0}
    <p class="muted">{board === 'climb' ? 'No one’s started the Cash Game here yet.' : 'Nobody here yet — add friends or play!'}</p>
  {:else}
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>#</th><th>Player</th>
            {#if board === 'wealth'}<th>{period === 'week' ? 'Gained' : 'Net Worth'}</th><th>Cash</th>
            {:else if board === 'daily'}<th>Score</th>
            {:else}<th>Climb</th>{/if}
          </tr>
        </thead>
        <tbody>
          {#each rows as r}
            <tr class={r.is_me ? 'me' : (r.rank <= 3 ? 'top' : '')}>
              <td class="rank">{medal(r.rank)}</td>
              <td class="name">
                <span style={r.color ? `color:${r.color}` : ''}>{r.is_me ? 'You' : (r.name || 'Player')}</span>
                {#if r.title}<span class="title">{r.title}</span>{/if}
                {#if board === 'wealth' && (r.net_worth ?? 0) < 0}<span class="red-flag">🔴</span>{/if}
              </td>
              {#if board === 'wealth'}
                <td class="metric" class:neg={(period === 'week' ? r.metric : r.net_worth) < 0}>
                  {period === 'week' ? (r.metric >= 0 ? '+' : '') + fmt(r.metric) : fmt(r.net_worth)}
                </td>
                <td class="dim">{fmt(r.cash)}</td>
              {:else if board === 'daily'}
                <td class="metric">{r.played ? Number(r.score).toLocaleString() : '—'}</td>
              {:else}
                <td class="metric">#{r.position}</td>
              {/if}
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}

  <p class="hint">
    {#if board === 'wealth'}Net Worth = Cash − Loans. 🔴 = in the red. Weekly resets Monday — fair for newcomers.
    {:else if board === 'daily'}Same puzzle for everyone today. Spend less, score more.
    {:else}How far you've climbed the Cash Game ladder. Everyone faces the same puzzles, in order.{/if}
  </p>
</main>

<style>
  .lb-page { max-width: 640px; margin: 0 auto; padding: 2rem 1rem 3rem; text-align: center; }
  .back-btn { display: inline-block; margin-bottom: 1rem; padding: 0.55rem 1.1rem; background: var(--surface); color: var(--text); border: 1px solid var(--border); border-radius: 12px; cursor: pointer; font-weight: 600; font-size: 0.9rem; }
  h1 { font-family: var(--font-display); font-size: 1.9rem; margin: 0 0 1rem; }
  .tabs { display: flex; gap: 0.4rem; justify-content: center; margin-bottom: 0.8rem; }
  .tab { flex: 1; max-width: 150px; padding: 0.55rem 0.5rem; border-radius: 12px; cursor: pointer; font-weight: 700; font-size: 0.9rem; border: 1px solid var(--border); background: var(--surface); color: var(--text-muted); }
  .tab.active { color: #3a2a00; background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); border-color: transparent; }
  .filters { display: flex; gap: 0.5rem; justify-content: center; align-items: center; flex-wrap: wrap; margin-bottom: 0.5rem; }
  .filter-select { padding: 0.5rem 0.8rem; border-radius: 10px; border: 1px solid var(--border); background: var(--surface); color: var(--text); font-size: 0.9rem; }
  .seg { display: inline-flex; border: 1px solid var(--border); border-radius: 999px; overflow: hidden; }
  .seg-btn { padding: 0.45rem 0.9rem; cursor: pointer; font-size: 0.82rem; font-weight: 600; background: transparent; color: var(--text-muted); border: none; }
  .seg-btn.on { background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); color: #3a2a00; }
  .caption { color: var(--text-faint); font-size: 0.8rem; margin: 0.2rem 0 1rem; }
  .muted { color: var(--text-muted); padding: 2rem 0; }
  .error { color: #fb7185; }
  .table-wrap { overflow-x: auto; border: 1px solid var(--border); border-radius: 14px; }
  table { width: 100%; border-collapse: collapse; }
  th { font-size: 0.62rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-faint); padding: 0.7rem 0.6rem; text-align: left; border-bottom: 1px solid var(--border); }
  td { padding: 0.7rem 0.6rem; border-bottom: 1px solid var(--border); font-size: 0.9rem; text-align: left; }
  tr:last-child td { border-bottom: none; }
  td.rank { width: 34px; }
  td.name { font-weight: 600; }
  td.metric { font-family: var(--font-display); font-weight: 700; color: var(--brand-2); text-align: right; }
  td.metric.neg { color: #fb7185; }
  td.dim { color: var(--text-faint); text-align: right; }
  th:last-child { text-align: right; }
  tr.me { background: rgba(56,189,248,0.1); }
  tr.me td.name { color: #7dd3fc; }
  .title { font-size: 0.68rem; color: var(--text-faint); margin-left: 0.35rem; white-space: nowrap; }
  .red-flag { margin-left: 0.3rem; font-size: 0.7rem; }
  .hint { margin-top: 1.2rem; font-size: 0.76rem; color: var(--text-faint); line-height: 1.5; }
</style>
