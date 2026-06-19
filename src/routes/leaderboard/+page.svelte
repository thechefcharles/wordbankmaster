<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import {
    fetchDailyLeaderboard,
    fetchArcadeLeaderboard
  } from '$lib/stores/statsStore.js';

  /** @typedef {{ rank?: number, display_name?: string, score?: number, bankroll_left?: number, current_streak?: number, highest_streak?: number, total_played?: number, win_rate?: number }} DailyRow */
  /** @typedef {{ rank?: number, display_name?: string, current_bankroll?: number, highest_bankroll?: number, current_streak?: number, highest_streak?: number, total_played?: number, win_rate?: number }} ArcadeRow */

  /** @type {'daily' | 'arcade'} */
  let mode = $state('daily');
  let dailyPeriod = $state('daily');
  /** @type {'score' | 'bankroll' | 'streak' | 'highest_streak' | 'puzzles' | 'win_pct'} */
  let dailyOrderBy = $state('score');

  /** Medal from ending bankroll. @param {number} br @param {number} played */
  function medal(br, played) {
    if (!played) return '';
    if (br >= 700) return '🥇';
    if (br >= 400) return '🥈';
    if (br >= 100) return '🥉';
    return ''; // busted / negligible bankroll
  }
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
      <button class="sort-btn" class:active={dailyOrderBy === 'score'} onclick={() => { dailyOrderBy = 'score'; }}>Score</button>
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
              <th>Score</th>
              <th>Bankroll</th>
              <th>Streak</th>
              <th>Best</th>
              <th>Plays</th>
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
                <td class="score-cell">{fmt(row.score)}</td>
                <td>${fmt(row.bankroll_left)} {medal(row.bankroll_left ?? 0, row.total_played ?? 0)}</td>
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
    margin: 0 auto;
    padding: 2.5rem 1rem 3rem;
    text-align: center;
  }

  h1 {
    font-family: var(--font-display);
    font-size: 2rem;
    letter-spacing: -0.02em;
    margin-bottom: 1.1rem;
  }

  .mode-tabs {
    display: inline-flex;
    gap: 4px;
    padding: 4px;
    margin-bottom: 1.4rem;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-pill);
  }

  .tab-btn {
    padding: 0.55rem 1.6rem;
    border: none;
    background: transparent;
    color: var(--text-muted);
    border-radius: var(--r-pill);
    cursor: pointer;
    font-family: var(--font-display);
    font-size: 0.95rem;
    font-weight: 600;
    transition: color 0.2s, background 0.2s;
  }
  .tab-btn:hover { color: var(--text); }
  .tab-btn.active {
    background: var(--brand-grad);
    color: #06210f;
    box-shadow: var(--glow-brand);
  }

  .period-label {
    color: var(--text-faint);
    font-size: 0.9rem;
    margin-bottom: 0.9rem;
  }

  .period-filters, .sort-filters {
    display: flex;
    gap: 0.45rem;
    justify-content: center;
    flex-wrap: wrap;
    margin-bottom: 1rem;
  }

  .period-btn, .sort-btn {
    padding: 0.4rem 0.9rem;
    border: 1px solid var(--border);
    background: var(--surface);
    color: var(--text-muted);
    border-radius: var(--r-pill);
    cursor: pointer;
    font-size: 0.85rem;
    font-weight: 500;
    transition: background 0.2s, border-color 0.2s, color 0.2s;
  }
  .period-btn:hover, .sort-btn:hover { background: var(--surface-2); color: var(--text); }
  .period-btn.active, .sort-btn.active {
    background: rgba(163, 230, 53, 0.12);
    color: var(--brand-2);
    border-color: rgba(163, 230, 53, 0.4);
  }

  .sort-label {
    color: var(--text-faint);
    font-size: 0.8rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    margin: 0.5rem 0 0.5rem;
  }

  .back-btn {
    display: inline-block;
    margin-bottom: 2rem;
    padding: 0.6rem 1.2rem;
    background: var(--surface);
    color: var(--text);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    cursor: pointer;
    font-weight: 600;
    font-size: 0.9rem;
    transition: background 0.2s, border-color 0.2s, transform 0.15s;
  }
  .back-btn:hover { background: var(--surface-2); border-color: var(--border-strong); transform: translateY(-1px); }

  .loading, .error, .empty {
    padding: 2.5rem 1rem;
    color: var(--text-muted);
  }
  .error { color: var(--danger); }

  .table-wrap {
    overflow-x: auto;
    border-radius: var(--r-lg);
    border: 1px solid var(--border);
    background: var(--surface);
    backdrop-filter: blur(14px);
  }

  table {
    width: 100%;
    min-width: 550px;
    border-collapse: collapse;
  }

  th, td {
    padding: 0.7rem 0.85rem;
    text-align: left;
    border-bottom: 1px solid var(--border);
    font-variant-numeric: tabular-nums;
  }

  th {
    font-family: var(--font-display);
    font-size: 0.72rem;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    font-weight: 600;
    color: var(--text-faint);
    background: rgba(255, 255, 255, 0.02);
  }
  tbody tr { transition: background 0.15s; animation: wb-fade-up 0.45s var(--ease-out) both; }
  tbody tr:nth-child(1) { animation-delay: 0.03s; }
  tbody tr:nth-child(2) { animation-delay: 0.08s; }
  tbody tr:nth-child(3) { animation-delay: 0.13s; }
  tbody tr:nth-child(4) { animation-delay: 0.18s; }
  tbody tr:nth-child(5) { animation-delay: 0.23s; }
  tbody tr:nth-child(n+6) { animation-delay: 0.28s; }
  tbody tr:hover { background: rgba(255, 255, 255, 0.03); }
  td { color: var(--text); }

  tr.top-three {
    background: linear-gradient(90deg, rgba(251, 191, 36, 0.13), transparent);
    box-shadow: inset 0 0 0 1px rgba(251, 191, 36, 0.12);
  }
  tr.top-three td.name { color: #fde68a; }

  td.score-cell {
    font-family: var(--font-display);
    font-weight: 700;
    color: var(--brand-2);
  }
  td.rank { font-weight: 700; width: 50px; font-family: var(--font-display); }
  tr.top-three td.rank { font-size: 1.1rem; animation: wb-pop-in 0.5s var(--ease-spring) both; display: inline-block; }
  td.name { font-weight: 600; }

  .hint {
    margin-top: 1.6rem;
    font-size: 0.82rem;
    color: var(--text-faint);
  }
</style>
