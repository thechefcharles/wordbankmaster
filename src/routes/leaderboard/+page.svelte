<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import {
    fetchDailyLeaderboard,
    fetchArcadeLeaderboard
  } from '$lib/stores/statsStore.js';

  /** @typedef {{ rank?: number, display_name?: string, bankroll_left?: number, current_streak?: number, highest_streak?: number, total_played?: number, win_rate?: number }} DailyRow */
  /** @typedef {{ rank?: number, display_name?: string, current_bankroll?: number, highest_bankroll?: number, current_streak?: number, highest_streak?: number, total_played?: number, win_rate?: number }} ArcadeRow */

  /** @type {'daily' | 'arcade'} */
  let mode = $state('daily');
  let dailyPeriod = $state('daily');
  /** @type {'bankroll' | 'streak' | 'highest_streak' | 'puzzles' | 'win_pct'} */
  let dailyOrderBy = $state('bankroll');
  /** @type {DailyRow[]} */
  let dailyData = $state([]);
  let arcadePeriod = $state('all');
  /** @type {'bankroll' | 'highest_bankroll' | 'streak' | 'highest_streak' | 'puzzles' | 'win_pct'} */
  let arcadeOrderBy = $state('bankroll');
  /** @type {ArcadeRow[]} */
  let arcadeData = $state([]);
  let loading = $state(true);
  let error = $state('');

  const periodLabels = /** @type {Record<string, string>} */ ({
    all: 'All Time',
    daily: 'Today',
    weekly: 'This Week',
    monthly: 'This Month',
    yearly: 'This Year'
  });

  async function loadDaily() {
    try {
      dailyData = await fetchDailyLeaderboard(dailyPeriod, dailyOrderBy);
    } catch (e) {
      error = (e instanceof Error ? e.message : String(e)) || 'Failed to load';
    }
  }

  async function loadArcade() {
    try {
      arcadeData = await fetchArcadeLeaderboard(arcadePeriod, arcadeOrderBy);
    } catch (e) {
      error = (e instanceof Error ? e.message : String(e)) || 'Failed to load';
    }
  }

  $effect(() => {
    loading = true;
    error = '';
    if (mode === 'daily') {
      loadDaily().finally(() => { loading = false; });
    } else {
      loadArcade().finally(() => { loading = false; });
    }
  });

  $effect(() => {
    if (mode === 'daily' && (dailyPeriod || dailyOrderBy)) {
      loadDaily();
    }
    if (mode === 'arcade' && (arcadePeriod || arcadeOrderBy)) {
      loadArcade();
    }
  });

  // Open in daily tab when coming from daily finish (?mode=daily)
  onMount(() => {
    const modeParam = typeof window !== 'undefined' && $page.url.searchParams.get('mode');
    if (modeParam === 'daily') mode = 'daily';
    else if (modeParam === 'arcade') mode = 'arcade';
  });

  /** @param {unknown} n */
  function fmt(n) {
    return n != null ? Number(n).toLocaleString() : '0';
  }
</script>

<main class="leaderboard-page">
  <h1>🏆 Leaderboard</h1>

  <div class="mode-tabs">
    <button
      class="tab-btn"
      class:active={mode === 'daily'}
      onclick={() => { mode = 'daily'; }}
    >
      Daily
    </button>
    <button
      class="tab-btn"
      class:active={mode === 'arcade'}
      onclick={() => { mode = 'arcade'; }}
    >
      Arcade
    </button>
  </div>

  {#if mode === 'daily'}
    <p class="period-label">{periodLabels[dailyPeriod] ?? 'Today'}</p>
    <div class="period-filters">
      {#each ['daily', 'weekly', 'monthly', 'yearly'] as p}
        <button
          class="period-btn"
          class:active={dailyPeriod === p}
          onclick={() => { dailyPeriod = p; }}
        >
          {periodLabels[p] ?? p}
        </button>
      {/each}
    </div>
    <p class="sort-label">Sort by:</p>
    <div class="sort-filters">
      <button class="sort-btn" class:active={dailyOrderBy === 'bankroll'} onclick={() => { dailyOrderBy = 'bankroll'; }}>Bankroll</button>
      <button class="sort-btn" class:active={dailyOrderBy === 'streak'} onclick={() => { dailyOrderBy = 'streak'; }}>Current Streak</button>
      <button class="sort-btn" class:active={dailyOrderBy === 'highest_streak'} onclick={() => { dailyOrderBy = 'highest_streak'; }}>Highest Streak</button>
      <button class="sort-btn" class:active={dailyOrderBy === 'puzzles'} onclick={() => { dailyOrderBy = 'puzzles'; }}>Puzzles</button>
      <button class="sort-btn" class:active={dailyOrderBy === 'win_pct'} onclick={() => { dailyOrderBy = 'win_pct'; }}>Win %</button>
    </div>
  {:else}
    <p class="period-label">{periodLabels[arcadePeriod] ?? 'All Time'}</p>
    <div class="period-filters">
      {#each ['all', 'daily', 'weekly', 'monthly', 'yearly'] as p}
        <button class="period-btn" class:active={arcadePeriod === p} onclick={() => { arcadePeriod = p; }}>
          {periodLabels[p] ?? p}
        </button>
      {/each}
    </div>
    <p class="sort-label">Sort by:</p>
    <div class="sort-filters">
      <button class="sort-btn" class:active={arcadeOrderBy === 'bankroll'} onclick={() => { arcadeOrderBy = 'bankroll'; }}>Bankroll</button>
      <button class="sort-btn" class:active={arcadeOrderBy === 'highest_bankroll'} onclick={() => { arcadeOrderBy = 'highest_bankroll'; }}>Highest Bankroll</button>
      <button class="sort-btn" class:active={arcadeOrderBy === 'streak'} onclick={() => { arcadeOrderBy = 'streak'; }}>Current Streak</button>
      <button class="sort-btn" class:active={arcadeOrderBy === 'highest_streak'} onclick={() => { arcadeOrderBy = 'highest_streak'; }}>Highest Streak</button>
      <button class="sort-btn" class:active={arcadeOrderBy === 'puzzles'} onclick={() => { arcadeOrderBy = 'puzzles'; }}>Puzzles</button>
      <button class="sort-btn" class:active={arcadeOrderBy === 'win_pct'} onclick={() => { arcadeOrderBy = 'win_pct'; }}>Win %</button>
    </div>
  {/if}

  <button class="back-btn" onclick={() => goto('/')}>← Return to main menu</button>

  {#if loading}
    <p class="loading">Loading...</p>
  {:else if error}
    <p class="error">{error}</p>
  {:else if mode === 'daily'}
    {#if dailyData.length === 0}
      <p class="empty">No daily results yet. Play the daily puzzle to appear!</p>
    {:else}
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>#</th>
              <th>Player</th>
              <th>Bankroll Left</th>
              <th>Current Streak</th>
              <th>Highest Streak</th>
              <th>Puzzles</th>
              <th>Win %</th>
            </tr>
          </thead>
          <tbody>
            {#each dailyData as row}
              <tr class={(row.rank ?? 0) <= 3 ? 'top-three' : ''}>
                <td class="rank">
                  {#if row.rank === 1}🥇
                  {:else if row.rank === 2}🥈
                  {:else if row.rank === 3}🥉
                  {:else}{row.rank}{/if}
                </td>
                <td class="name">{row.display_name || 'Player'}</td>
                <td>${fmt(row.bankroll_left)}</td>
                <td>{fmt(row.current_streak)}</td>
                <td>{fmt(row.highest_streak)}</td>
                <td>{fmt(row.total_played)}</td>
                <td>{fmt(row.win_rate)}%</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {:else}
    {#if arcadeData.length === 0}
      <p class="empty">No arcade results yet. Play arcade mode to build your bankroll!</p>
    {:else}
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>#</th>
              <th>Player</th>
              <th>Bankroll</th>
              <th>Highest Bankroll</th>
              <th>Current Streak</th>
              <th>Highest Streak</th>
              <th>Puzzles</th>
              <th>Win %</th>
            </tr>
          </thead>
          <tbody>
            {#each arcadeData as row}
              <tr class={(row.rank ?? 0) <= 3 ? 'top-three' : ''}>
                <td class="rank">
                  {#if row.rank === 1}🥇
                  {:else if row.rank === 2}🥈
                  {:else if row.rank === 3}🥉
                  {:else}{row.rank}{/if}
                </td>
                <td class="name">{row.display_name || 'Player'}</td>
                <td>${fmt(row.current_bankroll)}</td>
                <td>${fmt(row.highest_bankroll)}</td>
                <td>{fmt(row.current_streak)}</td>
                <td>{fmt(row.highest_streak)}</td>
                <td>{fmt(row.total_played)}</td>
                <td>{fmt(row.win_rate)}%</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {/if}

  <p class="hint">
    {#if mode === 'daily'}
      Daily: Bankroll left, current streak (consecutive days won), highest streak, puzzles, win %.
    {:else}
      Arcade: Current bankroll, highest bankroll, streaks, puzzles played, win %.
    {/if}
  </p>
</main>

<style>
  .leaderboard-page {
    max-width: 700px;
    margin: 2rem auto;
    padding: 1rem;
    text-align: center;
  }

  h1 {
    color: limegreen;
    font-size: 2rem;
    margin-bottom: 0.25rem;
  }

  .mode-tabs {
    display: flex;
    gap: 0.5rem;
    justify-content: center;
    margin-bottom: 1rem;
  }

  .tab-btn {
    padding: 0.6rem 1.5rem;
    border: 2px solid #ccc;
    background: #fff;
    color: #333;
    border-radius: 8px;
    cursor: pointer;
    font-size: 1rem;
    font-weight: bold;
  }

  .tab-btn:hover {
    background: #f5f5f5;
  }

  .tab-btn.active {
    background: limegreen;
    color: white;
    border-color: limegreen;
  }

  .period-label {
    color: #888;
    font-size: 0.95rem;
    margin-bottom: 1rem;
  }

  .period-filters {
    display: flex;
    gap: 0.5rem;
    justify-content: center;
    flex-wrap: wrap;
    margin-bottom: 1rem;
  }

  .period-btn {
    padding: 0.4rem 0.9rem;
    border: 1px solid #ccc;
    background: #fff;
    color: #333;
    border-radius: 8px;
    cursor: pointer;
    font-size: 0.9rem;
  }

  .period-btn:hover {
    background: #f5f5f5;
  }

  .period-btn.active {
    background: limegreen;
    color: white;
    border-color: limegreen;
  }

  .sort-label {
    color: #888;
    font-size: 0.85rem;
    margin: 0.5rem 0 0.25rem;
  }

  .sort-filters {
    display: flex;
    gap: 0.4rem;
    justify-content: center;
    flex-wrap: wrap;
    margin-bottom: 1rem;
  }

  .sort-btn {
    padding: 0.35rem 0.75rem;
    border: 1px solid #ccc;
    background: #fff;
    color: #333;
    border-radius: 6px;
    cursor: pointer;
    font-size: 0.85rem;
  }

  .sort-btn:hover {
    background: #f5f5f5;
  }

  .sort-btn.active {
    background: limegreen;
    color: white;
    border-color: limegreen;
  }

  .back-btn {
    display: inline-block;
    margin-bottom: 2rem;
    padding: 0.5rem 1rem;
    background: #333;
    color: white;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    font-size: 0.95rem;
  }

  .back-btn:hover {
    background: #555;
  }

  .loading, .error, .empty {
    padding: 2rem;
    color: #666;
  }

  .error {
    color: #c62828;
  }

  .table-wrap {
    overflow-x: auto;
    border-radius: 12px;
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.1);
    margin: 0 -1rem;
  }

  table {
    width: 100%;
    min-width: 550px;
    border-collapse: collapse;
    background: white;
  }

  th, td {
    padding: 0.5rem 0.75rem;
    text-align: left;
    border-bottom: 1px solid #eee;
  }

  th {
    background: #f5f5f5;
    font-weight: 700;
    color: #333;
  }

  tr.top-three {
    background: linear-gradient(90deg, rgba(76, 175, 80, 0.08), transparent);
  }

  td.rank {
    font-weight: bold;
    width: 50px;
  }

  td.name {
    font-weight: 600;
  }

  .hint {
    margin-top: 2rem;
    font-size: 0.85rem;
    color: #999;
  }

  :global(body.dark-mode) .leaderboard-page table {
    background: #333;
  }

  :global(body.dark-mode) th, :global(body.dark-mode) td {
    border-color: #555;
    color: #eee;
  }

  :global(body.dark-mode) th {
    background: #444;
  }

  :global(body.dark-mode) .tab-btn, :global(body.dark-mode) .period-btn {
    background: #333;
    color: #eee;
    border-color: #555;
  }

  :global(body.dark-mode) .tab-btn.active, :global(body.dark-mode) .period-btn.active, :global(body.dark-mode) .sort-btn.active {
    background: limegreen;
    color: white;
    border-color: limegreen;
  }

  :global(body.dark-mode) .sort-btn {
    background: #333;
    color: #eee;
    border-color: #555;
  }
</style>
