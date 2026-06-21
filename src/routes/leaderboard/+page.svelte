<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import {
    fetchDailyLeaderboard,
    fetchArcadeLeaderboard,
    getMyUsername,
    setUsername,
    searchUsers,
    addFriend,
    getFriendsDailyLeaderboard,
    getNetworthLeaderboard
  } from '$lib/stores/statsStore.js';
  import { track } from '$lib/analytics.js';

  /** @typedef {{ rank?: number, display_name?: string, score?: number, bankroll_left?: number, current_streak?: number, highest_streak?: number, total_played?: number, win_rate?: number }} DailyRow */
  /** @typedef {{ rank?: number, display_name?: string, banked?: number, furthest?: number, total?: number }} ArcadeRow */

  /** @type {'daily' | 'arcade' | 'friends' | 'networth'} */
  let mode = $state('daily');

  // ---- Username + Friends ----
  let myUsername = $state('');
  let usernameInput = $state('');
  let usernameMsg = $state('');
  let editingUsername = $state(false);
  let usernameCopied = $state(false);
  /** @type {any[]} */
  let friendsData = $state([]);
  let addQuery = $state('');
  let addMsg = $state('');
  /** @type {{username:string,is_friend:boolean}[]} */
  let searchResults = $state([]);
  /** @type {ReturnType<typeof setTimeout>|undefined} */
  let searchTimer;
  // ---- Net Worth ----
  /** @type {'friends'|'global'} */
  let networthScope = $state('friends');
  /** @type {any[]} */
  let networthData = $state([]);

  async function loadFriends() {
    try {
      if (!myUsername) myUsername = (await getMyUsername()) ?? '';
      friendsData = await getFriendsDailyLeaderboard();
    } catch (e) {
      error = (e instanceof Error ? e.message : String(e)) || 'Failed to load';
    }
  }
  async function loadNetworth() {
    try {
      if (!myUsername) myUsername = (await getMyUsername()) ?? '';
      networthData = await getNetworthLeaderboard(networthScope);
    } catch (e) {
      error = (e instanceof Error ? e.message : String(e)) || 'Failed to load';
    }
  }
  async function submitUsername() {
    const name = usernameInput.trim();
    if (!name) return;
    usernameMsg = 'Saving…';
    const res = await setUsername(name);
    if (res.ok) {
      myUsername = res.username ?? name;
      usernameMsg = '';
      editingUsername = false;
      track('username_set');
    } else {
      usernameMsg = res.reason === 'taken' ? 'That username is taken.'
        : res.reason === 'reserved' ? 'That username is reserved.'
        : res.reason === 'invalid' ? '3–15 letters, numbers or _ only.'
        : 'Could not save username.';
    }
  }
  function onAddInput() {
    addMsg = '';
    clearTimeout(searchTimer);
    const q = addQuery.trim();
    if (q.length < 2) { searchResults = []; return; }
    searchTimer = setTimeout(async () => { searchResults = await searchUsers(q); }, 220);
  }
  /** @param {string} username */
  async function addByUsername(username) {
    addMsg = 'Adding…';
    const res = await addFriend(username);
    if (res.ok) {
      addMsg = `✓ Added ${res.friend_name || username}!`;
      addQuery = ''; searchResults = [];
      track('friend_add');
      await loadFriends();
    } else {
      addMsg = res.reason === 'not_found' ? 'No player with that username.'
        : res.reason === 'self' ? "That's you 🙂"
        : 'Could not add friend.';
    }
  }
  function shareUsername() {
    if (!myUsername) return;
    const origin = typeof window !== 'undefined' ? window.location.origin : 'https://wordbanksvelte.vercel.app';
    const text = `Add me on WordBank — I'm @${myUsername}. Play today's puzzle: ${origin}/?add=${myUsername}`;
    if (typeof navigator !== 'undefined' && navigator.share) { navigator.share({ text }).catch(() => {}); return; }
    navigator.clipboard?.writeText(text).then(() => { usernameCopied = true; setTimeout(() => usernameCopied = false, 1800); }, () => {});
  }
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
  let arcadePeriod = $state('daily');
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
      arcadeData = await fetchArcadeLeaderboard(arcadePeriod);
    } catch (e) {
      error = (e instanceof Error ? e.message : String(e)) || 'Failed to load';
    }
  }

  $effect(() => {
    loading = true;
    error = '';
    if (mode === 'daily') {
      loadDaily().finally(() => { loading = false; });
    } else if (mode === 'arcade') {
      loadArcade().finally(() => { loading = false; });
    } else if (mode === 'networth') {
      loadNetworth().finally(() => { loading = false; });
    } else {
      loadFriends().finally(() => { loading = false; });
    }
  });

  $effect(() => {
    if (mode === 'daily' && (dailyPeriod || dailyOrderBy)) {
      loadDaily();
    }
    if (mode === 'arcade' && arcadePeriod) {
      loadArcade();
    }
    if (mode === 'networth' && networthScope) {
      loadNetworth();
    }
  });

  // Open in daily tab when coming from daily finish (?mode=daily)
  onMount(() => {
    const modeParam = typeof window !== 'undefined' && $page.url.searchParams.get('mode');
    if (modeParam === 'daily') mode = 'daily';
    else if (modeParam === 'arcade') mode = 'arcade';
    else if (modeParam === 'friends') mode = 'friends';
    else if (modeParam === 'networth') mode = 'networth';
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
    <button
      class="tab-btn"
      class:active={mode === 'friends'}
      onclick={() => { mode = 'friends'; }}
    >
      Friends
    </button>
    <button
      class="tab-btn"
      class:active={mode === 'networth'}
      onclick={() => { mode = 'networth'; }}
    >
      💰 Net Worth
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
  {:else if mode === 'arcade'}
    <p class="period-label">{periodLabels[arcadePeriod] ?? 'Today'} · peak bankroll</p>
    <div class="period-filters">
      {#each ['daily', 'weekly', 'monthly', 'all'] as p}
        <button class="period-btn" class:active={arcadePeriod === p} onclick={() => { arcadePeriod = p; }}>
          {periodLabels[p] ?? p}
        </button>
      {/each}
    </div>
  {:else if mode === 'networth'}
    <p class="period-label">Richest players · Bank − Loan</p>
    <div class="period-filters">
      <button class="period-btn" class:active={networthScope === 'friends'} onclick={() => { networthScope = 'friends'; }}>Friends</button>
      <button class="period-btn" class:active={networthScope === 'global'} onclick={() => { networthScope = 'global'; }}>Global</button>
    </div>
  {:else}
    <p class="period-label">Today's Daily · you vs your friends</p>
    <div class="friend-panel">
      <div class="my-code">
        <span class="mc-label">Your username</span>
        {#if myUsername && !editingUsername}
          <button class="code-pill" onclick={shareUsername} title="Share your username">
            @{myUsername} <span class="share-ico">{usernameCopied ? '✓' : '↗'}</span>
          </button>
          <button class="edit-uname" onclick={() => { editingUsername = true; usernameInput = myUsername; usernameMsg = ''; }}>edit</button>
        {:else}
          <div class="add-row">
            <input class="code-input" placeholder="pick a username" bind:value={usernameInput} maxlength="15"
              onkeydown={(e) => { if (e.key === 'Enter') submitUsername(); }} />
            <button class="add-btn" onclick={submitUsername}>Save</button>
          </div>
          {#if usernameMsg}<p class="add-msg">{usernameMsg}</p>{/if}
        {/if}
      </div>

      {#if myUsername}
        <div class="add-row search-row">
          <input class="code-input" placeholder="Find friends by username" bind:value={addQuery}
            oninput={onAddInput} autocomplete="off" />
        </div>
        {#if searchResults.length}
          <div class="search-results">
            {#each searchResults as r}
              <div class="search-item">
                <span class="si-name">@{r.username}</span>
                {#if r.is_friend}
                  <span class="si-added">✓ Friend</span>
                {:else}
                  <button class="si-add" onclick={() => addByUsername(r.username)}>+ Add</button>
                {/if}
              </div>
            {/each}
          </div>
        {/if}
        {#if addMsg}<p class="add-msg">{addMsg}</p>{/if}
      {:else}
        <p class="add-msg">Pick a username first — that's how friends find you.</p>
      {/if}
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
                <td class="name">{row.display_name || 'Player'}{#if (row.current_streak ?? 0) >= 7} 🔥{/if}</td>
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
  {:else if mode === 'arcade'}
    {#if arcadeData.length === 0}
      <p class="empty">No arcade runs yet. Climb today's gauntlet to appear!</p>
    {:else}
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>#</th>
              <th>Player</th>
              <th>Peak $</th>
              <th>Solved</th>
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
                <td class="score-cell">${fmt(row.banked)}</td>
                <td>{fmt(row.furthest)}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {:else if mode === 'networth'}
    <!-- Net Worth: richest by Bank − Loan -->
    {#if networthData.length === 0}
      <p class="empty">{networthScope === 'friends' ? 'Add friends to see who’s richest!' : 'No players yet.'}</p>
    {:else}
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th>#</th><th>Player</th><th>Net Worth</th><th>Bank</th></tr>
          </thead>
          <tbody>
            {#each networthData as row}
              <tr class={row.is_me ? 'me-row' : ((row.rank ?? 0) <= 3 ? 'top-three' : '')}>
                <td class="rank">
                  {#if row.rank === 1}🥇{:else if row.rank === 2}🥈{:else if row.rank === 3}🥉{:else}{row.rank}{/if}
                </td>
                <td class="name">
                  <span style={row.color ? `color:${row.color}` : ''}>{row.is_me ? 'You' : (row.name || 'Player')}</span>
                  {#if row.title}<span class="nw-title">{row.title}</span>{/if}
                </td>
                <td class="score-cell" class:negative={(row.net_worth ?? 0) < 0}>${fmt(row.net_worth)}</td>
                <td>${fmt(row.bank)}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {:else}
    <!-- Friends: you + friends ranked by today's Daily score -->
    {#if friendsData.length <= 1}
      <p class="empty">Find friends by username above, then race them on today's Daily!</p>
    {/if}
    {#if friendsData.length > 0}
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th>#</th><th>Player</th><th>Today's Score</th></tr>
          </thead>
          <tbody>
            {#each friendsData as row}
              <tr class={row.is_me ? 'me-row' : ((row.rank ?? 0) <= 3 ? 'top-three' : '')}>
                <td class="rank">
                  {#if row.rank === 1}🥇{:else if row.rank === 2}🥈{:else if row.rank === 3}🥉{:else}{row.rank}{/if}
                </td>
                <td class="name">{row.is_me ? 'You' : (row.name || 'Player')}{#if (row.streak ?? 0) >= 7} 🔥{/if}</td>
                <td class="score-cell">{row.played ? fmt(row.score) : '—'}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {/if}

  <p class="hint">
    {#if mode === 'daily'}
      Daily: Score = bankroll × streak multiplier. Medals 🥇$700 / 🥈$400 / 🥉$100. 🔥 = 7+ day streak.
    {:else if mode === 'arcade'}
      Arcade: ranked by peak bankroll in a survival run, and how many puzzles you solved before going broke.
    {:else if mode === 'networth'}
      Net Worth = Bank − Loan. Pay off your loan and bank your winnings to climb. Titles & colors come from the Shop.
    {:else}
      Friends: pick a username, then search to add friends — everyone plays the same Daily, so it's head-to-head. "—" = hasn't played today.
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

  /* ---- Friends ---- */
  .friend-panel { max-width: 420px; margin: 0 auto 0.5rem; display: flex; flex-direction: column; gap: 0.7rem; }
  .my-code { display: flex; align-items: center; justify-content: center; gap: 0.6rem; }
  .mc-label { color: var(--text-faint); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.05em; }
  .code-pill {
    font-family: var(--font-display); font-weight: 800; font-size: 1.1rem; letter-spacing: 0.12em;
    padding: 0.5rem 1rem; border-radius: 999px; cursor: pointer; color: var(--brand-2);
    background: rgba(163,230,53,0.1); border: 1px solid rgba(163,230,53,0.4);
    display: inline-flex; align-items: center; gap: 0.5rem;
  }
  .share-ico { font-size: 0.85rem; opacity: 0.8; }
  .add-row { display: flex; gap: 0.5rem; }
  .code-input {
    flex: 1; padding: 0.6rem 0.9rem; border-radius: 12px; border: 1px solid var(--border);
    background: var(--surface); color: var(--text); font-size: 0.95rem;
  }
  .add-btn {
    padding: 0.6rem 1.2rem; border: none; border-radius: 12px; cursor: pointer; font-weight: 700;
    color: #06210f; background: var(--brand-grad, linear-gradient(135deg,#34d399,#a3e635));
  }
  .add-msg { text-align: center; font-size: 0.85rem; color: var(--text-muted); margin: 0; }
  .edit-uname { background: none; border: none; color: var(--text-faint); font-size: 0.8rem; cursor: pointer; text-decoration: underline; }
  .search-row { max-width: 420px; }
  .search-results {
    max-width: 420px; margin: 0 auto; display: flex; flex-direction: column; gap: 0.35rem;
    border: 1px solid var(--border); border-radius: 12px; padding: 0.4rem; background: var(--surface);
  }
  .search-item { display: flex; align-items: center; justify-content: space-between; padding: 0.35rem 0.5rem; }
  .si-name { font-weight: 600; }
  .si-added { color: var(--brand-2); font-size: 0.8rem; font-weight: 700; }
  .si-add {
    padding: 0.3rem 0.8rem; border: none; border-radius: 999px; cursor: pointer; font-weight: 700; font-size: 0.82rem;
    color: #06210f; background: var(--brand-grad, linear-gradient(135deg,#34d399,#a3e635));
  }
  .nw-title { font-size: 0.72rem; color: var(--text-faint); margin-left: 0.4rem; white-space: nowrap; }
  td.score-cell.negative { color: #f87171; }
  tr.me-row { background: rgba(56, 189, 248, 0.12); box-shadow: inset 0 0 0 1px rgba(56,189,248,0.25); }
  tr.me-row td.name { color: #7dd3fc; font-weight: 700; }

  /* ---- Mobile: fit the table without horizontal scroll ---- */
  @media (max-width: 560px) {
    .leaderboard-page { padding: 1.6rem 0.5rem 2.5rem; }
    h1 { font-size: 1.5rem; }
    .tab-btn { padding: 0.5rem 1.15rem; font-size: 0.9rem; }
    .back-btn { margin-bottom: 1.2rem; }
    .table-wrap { backdrop-filter: none; }
    table { min-width: 0; }
    th, td { padding: 0.55rem 0.45rem; font-size: 0.82rem; }
    th { font-size: 0.6rem; }
    td.rank { width: 30px; }
    /* The daily table has 8 columns — too wide for a phone. Keep the essentials
       (#, Player, Score, Bankroll) and hide Streak/Best/Plays/Win%. The Arcade
       table only has 4 columns, so these selectors are a no-op there. */
    th:nth-child(n+5), td:nth-child(n+5) { display: none; }
  }
</style>
