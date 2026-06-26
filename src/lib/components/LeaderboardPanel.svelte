<script>
  // Leaderboard content (Cash · Daily). Reused by the /leaderboard route and the
  // Community ▸ Leaderboard tab. The page/hub provides its own title + back.
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getWealthLeaderboard, getDailyBoard, getClimbRunLeaderboard, getMyGroups } from '$lib/stores/statsStore.js';

  /** @type {'cash'|'daily'|'cash_game'} */
  let board = $state('cash');
  const TABS = [
    { k: 'cash', label: '💰 Cash' },
    { k: 'daily', label: '📅 Daily' },
    { k: 'cash_game', label: '🎰 Cash Game' }
  ];
  const PERIOD_BOARDS = ['cash'];
  /** scope: 'global' (Everyone) | 'friends' | a group id */
  let scope = $state('global');
  /** @type {'week'|'all'} */
  let period = $state('all');
  /** @type {any[]} */
  let rows = $state([]);
  /** @type {any[]} */
  let groups = $state([]);
  let loading = $state(true);
  let error = $state('');

  // Sortable daily columns (client-side). Default: today's score, high → low.
  /** @type {'name'|'net_worth'|'score'|'play_streak'|'win_streak'} */
  let sortKey = $state('score');
  /** @type {'asc'|'desc'} */
  let sortDir = $state('desc');
  /** @param {typeof sortKey} k */
  function setSort(k) {
    if (sortKey === k) sortDir = sortDir === 'asc' ? 'desc' : 'asc';
    else { sortKey = k; sortDir = k === 'name' ? 'asc' : 'desc'; }
  }
  /** @param {typeof sortKey} k */
  const arrow = (k) => sortKey === k ? (sortDir === 'asc' ? ' ▲' : ' ▼') : '';
  let sortedRows = $derived.by(() => {
    if (board !== 'daily') return rows;
    const dir = sortDir === 'asc' ? 1 : -1;
    return [...rows].sort((a, b) => {
      if (sortKey === 'name') return dir * String(a.name || '').localeCompare(String(b.name || ''), undefined, { sensitivity: 'base' });
      const av = sortKey === 'score' ? (a.score ?? -Infinity) : Number(a[sortKey] ?? 0);
      const bv = sortKey === 'score' ? (b.score ?? -Infinity) : Number(b[sortKey] ?? 0);
      return dir * (av - bv) || String(a.name || '').localeCompare(String(b.name || ''));
    });
  });

  const fmt = (/** @type {any} */ n) => '$' + Math.round(Number(n ?? 0)).toLocaleString();

  async function load() {
    loading = true; error = '';
    try {
      const isGroup = scope !== 'global' && scope !== 'friends';
      const sc = isGroup ? 'group' : scope;
      const grp = isGroup ? scope : null;
      if (board === 'cash') rows = await getWealthLeaderboard(sc, period, grp);
      else if (board === 'cash_game') rows = await getClimbRunLeaderboard(sc, grp);
      else rows = await getDailyBoard(sc, grp);
    } catch (e) {
      error = (e instanceof Error ? e.message : String(e)) || 'Failed to load';
    } finally { loading = false; }
  }

  onMount(async () => { groups = await getMyGroups(); await load(); });

  // reload whenever the board / scope / period changes
  $effect(() => { board; scope; period; load(); });

  /** @param {number} rank */
  const medal = (rank) => rank === 1 ? '🥇' : rank === 2 ? '🥈' : rank === 3 ? '🥉' : String(rank);
</script>

<!-- Board selector -->
<div class="tabs">
  {#each TABS as t}
    <button class="tab" class:active={board === t.k} onclick={() => board = /** @type {any} */ (t.k)}>{t.label}</button>
  {/each}
</div>

<!-- Scope: Everyone · Friends · each of your groups -->
<div class="scope-row">
  <button class="scope-pill" class:on={scope === 'global'} onclick={() => scope = 'global'}>🌍 Everyone</button>
  <button class="scope-pill" class:on={scope === 'friends'} onclick={() => scope = 'friends'}>👋 Friends</button>
  {#each groups as g}
    <button class="scope-pill" class:on={scope === g.id} onclick={() => scope = g.id}>👥 {g.name}</button>
  {/each}
</div>

{#if PERIOD_BOARDS.includes(board)}
  <div class="filters">
    <div class="seg">
      <button class="seg-btn" class:on={period === 'week'} onclick={() => period = 'week'}>This Week</button>
      <button class="seg-btn" class:on={period === 'all'} onclick={() => period = 'all'}>All-Time</button>
    </div>
  </div>
{/if}

<p class="caption">
  {#if board === 'cash'}{period === 'week' ? 'Cash gained this week' : 'Richest players — total Cash'}
  {:else if board === 'cash_game'}Biggest Cash Game run — most profit banked in one heat streak
  {:else}Ranked by today's Daily score · {scope === 'global' ? 'everyone' : scope === 'friends' ? 'your friends' : 'this group'}{/if}
</p>

{#if loading}
  <p class="muted">Loading…</p>
{:else if error}
  <p class="error">{error}</p>
{:else if rows.length === 0}
  <p class="muted">Nobody here yet — add friends or play!</p>
{:else}
  <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th>#</th>
          {#if board === 'cash'}<th>Player</th><th>{period === 'week' ? 'Gained' : 'Cash'}</th>
          {:else if board === 'cash_game'}<th>Player</th><th class="num">Best run</th><th class="num">Streak</th>
          {:else}
            <th><button class="sort" class:on={sortKey === 'name'} onclick={() => setSort('name')}>Player{arrow('name')}</button></th>
            <th class="num"><button class="sort" class:on={sortKey === 'net_worth'} onclick={() => setSort('net_worth')}>💰 Cash{arrow('net_worth')}</button></th>
            <th class="num"><button class="sort" class:on={sortKey === 'score'} onclick={() => setSort('score')}>Score{arrow('score')}</button></th>
            <th class="num"><button class="sort" class:on={sortKey === 'play_streak'} onclick={() => setSort('play_streak')}>🔥{arrow('play_streak')}</button></th>
            <th class="num"><button class="sort" class:on={sortKey === 'win_streak'} onclick={() => setSort('win_streak')}>🏆{arrow('win_streak')}</button></th>
          {/if}
        </tr>
      </thead>
      <tbody>
        {#each sortedRows as r, i}
          {@const pos = board === 'daily' ? i + 1 : r.rank}
          <tr class={r.is_me ? 'me' : (pos <= 3 ? 'top' : '')}>
            <td class="rank">{medal(pos)}</td>
            <td class="name">
              {#if r.is_me}
                <button class="name-link" onclick={() => goto('/profile')} style={r.color ? `color:${r.color}` : ''}>You</button>
              {:else}
                <button class="name-link" onclick={() => goto('/u/' + encodeURIComponent(r.name || ''))} style={r.color ? `color:${r.color}` : ''}>{r.name || 'Player'}</button>
              {/if}
              {#if r.title}<span class="title">{r.title}</span>{/if}
            </td>
            {#if board === 'cash'}
              <td class="metric" class:neg={period === 'week' && Number(r.metric) < 0}>
                {period === 'week' ? (r.metric >= 0 ? '+' : '') + fmt(r.metric) : fmt(r.net_worth)}
              </td>
            {:else if board === 'cash_game'}
              <td class="metric gold">{fmt(r.best_run_profit)}</td>
              <td class="metric small">{r.best_run_solves > 0 ? '🔥' + r.best_run_solves : '—'}</td>
            {:else}
              <td class="metric">{fmt(r.net_worth)}</td>
              <td class="metric gold">{r.played ? Number(r.score).toLocaleString() : '—'}</td>
              <td class="metric small">{r.play_streak > 0 ? '🔥' + r.play_streak : '—'}</td>
              <td class="metric small">{r.win_streak > 0 ? '🏆' + r.win_streak : '—'}</td>
            {/if}
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<p class="hint">
  {#if board === 'cash'}Your total Cash, earned across every mode. The weekly view resets Monday — fair for newcomers.
  {:else if board === 'cash_game'}Your best single run — profit banked before your heat reset. Build a streak, push your luck with Double or Nothing.
  {:else}Same puzzle for everyone today. Spend less, score more.{/if}
</p>

<style>
  .tabs { display: flex; gap: 0.4rem; margin-bottom: 0.8rem; overflow-x: auto; padding-bottom: 4px; -webkit-overflow-scrolling: touch; justify-content: center; }
  .tabs::-webkit-scrollbar { display: none; }
  .tab { flex: 0 0 auto; padding: 0.5rem 0.8rem; border-radius: 999px; cursor: pointer; font-weight: 700; font-size: 0.82rem; white-space: nowrap; border: 1px solid var(--border); background: var(--surface); color: var(--text-muted); }
  .tab.active { color: #3a2a00; background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); border-color: transparent; }
  .filters { display: flex; gap: 0.5rem; justify-content: center; align-items: center; flex-wrap: wrap; margin-bottom: 0.5rem; }
  .scope-row { display: flex; gap: 0.4rem; margin-bottom: 0.6rem; overflow-x: auto; padding-bottom: 4px; -webkit-overflow-scrolling: touch; }
  .scope-row::-webkit-scrollbar { display: none; }
  .scope-pill { flex: 0 0 auto; padding: 0.42rem 0.8rem; border-radius: 999px; cursor: pointer; font-weight: 700; font-size: 0.8rem; white-space: nowrap;
    border: 1px solid var(--border); background: var(--surface); color: var(--text-muted); }
  .scope-pill.on { color: var(--text); background: var(--surface-2, rgba(56,189,248,0.16)); border-color: var(--brand-2); box-shadow: inset 0 0 0 1px var(--brand-2); }
  .seg { display: inline-flex; border: 1px solid var(--border); border-radius: 999px; overflow: hidden; }
  .seg-btn { padding: 0.45rem 0.9rem; cursor: pointer; font-size: 0.82rem; font-weight: 600; background: transparent; color: var(--text-muted); border: none; }
  .seg-btn.on { background: var(--brand-grad, linear-gradient(135deg,#fbbf24,#fde047)); color: #3a2a00; }
  .caption { color: var(--text-faint); font-size: 0.8rem; margin: 0.2rem 0 1rem; text-align: center; }
  .muted { color: var(--text-muted); padding: 2rem 0; text-align: center; }
  .error { color: #fb7185; text-align: center; }
  .table-wrap { overflow-x: auto; border: 1px solid var(--border); border-radius: 14px; }
  table { width: 100%; border-collapse: collapse; }
  th { font-size: 0.62rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-faint); padding: 0.7rem 0.6rem; text-align: left; border-bottom: 1px solid var(--border); }
  td { padding: 0.7rem 0.6rem; border-bottom: 1px solid var(--border); font-size: 0.9rem; text-align: left; }
  tr:last-child td { border-bottom: none; }
  td.rank { width: 34px; }
  td.name { font-weight: 600; }
  .name-link { background: none; border: none; padding: 0; font: inherit; color: inherit; cursor: pointer; text-decoration: underline; text-decoration-color: rgba(255,255,255,0.2); text-underline-offset: 2px; }
  .name-link:hover { text-decoration-color: var(--gold); }
  td.metric { font-family: var(--font-display); font-weight: 700; color: var(--text); text-align: right; white-space: nowrap; }
  td.metric.gold { color: var(--brand-2); }
  td.metric.small { font-weight: 700; font-size: 0.82rem; color: var(--text-muted); }
  td.metric.neg { color: #fb7185; }
  th.num { text-align: right; }
  th:last-child { text-align: right; }
  th button.sort { background: none; border: none; padding: 0; margin: 0; cursor: pointer; font: inherit;
    color: inherit; text-transform: inherit; letter-spacing: inherit; white-space: nowrap; }
  th button.sort:hover { color: var(--text-muted); }
  th button.sort.on { color: var(--brand-2); }
  /* tighter cells when the Daily board shows 6 columns */
  th, td { padding: 0.6rem 0.45rem; }
  td.rank { width: 30px; padding-left: 0.5rem; }
  tr.me { background: rgba(56,189,248,0.1); }
  tr.me td.name { color: #7dd3fc; }
  .title { font-size: 0.68rem; color: var(--text-faint); margin-left: 0.35rem; white-space: nowrap; }
  .hint { margin-top: 1.2rem; font-size: 0.76rem; color: var(--text-faint); line-height: 1.5; text-align: center; }
</style>
