<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { supabase } from '$lib/supabaseClient.js';
  import { user } from '$lib/stores/userStore.js';
  import { getDailyStatus } from '$lib/stores/statsStore.js';

  const categories = [
    'Movies & TV 🎬',
    'Pop Culture & Celebrities 🌟',
    'Food & Drink 🍔',
    'Slang & Sayings 🗣️',
    'History & Culture 🏛️',
    'Sports & Games 🏆'
  ];

  let status = $state({ has_played_today: false, last_daily_won: null, daily_bankroll: 0, arcade_bankroll: 1000 });
  let loading = $state(true);

  onMount(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    user.set(session?.user ? /** @type {{ id: string }} */ (session.user) : null);
    if (session?.user?.id) {
      status = await getDailyStatus(session.user.id);
    }
    loading = false;
  });

  function selectDaily() {
    if (status.has_played_today) return;
    localStorage.setItem('gameMode', 'daily');
    localStorage.removeItem('selectedCategory');
    goto('/');
  }

  /** @param {string} category */
  function selectArcade(category) {
    localStorage.setItem('gameMode', 'arcade');
    localStorage.setItem('selectedCategory', category);
    goto('/');
  }
</script>

<div class="header-row">
  <h2>Choose Mode</h2>
  <a href="/leaderboard" class="leaderboard-link" title="Leaderboard">🏆</a>
</div>

<div class="mode-section">
  <h3>📅 Daily Puzzle</h3>
  <p>One puzzle per day. Counts for the daily leaderboard!</p>
  {#if loading}
    <p class="status-loading">Loading...</p>
  {:else if status.has_played_today}
    <div class="daily-status">
      <p class="played-badge">Played today: {status.last_daily_won ? '✅ Won' : '❌ Lost'}</p>
      <p class="bankroll-badge">Bankroll: ${status.daily_bankroll?.toLocaleString() ?? 0}</p>
    </div>
    <button class="daily-btn disabled" disabled>Play Daily</button>
  {:else}
    <button class="daily-btn" onclick={selectDaily}>Play Daily</button>
  {/if}
</div>

<div class="mode-section arcade">
  <h3>🎮 Arcade Mode</h3>
  <p>Unlimited play. Build your cumulative bankroll!</p>
  <p class="arcade-bankroll">Your arcade bankroll: <strong>${status.arcade_bankroll?.toLocaleString() ?? 1000}</strong></p>
  <div class="category-grid">
    {#each categories as cat}
      <button onclick={() => selectArcade(cat)}>{cat}</button>
    {/each}
  </div>
</div>

<style>
  .header-row {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.75rem;
    margin-top: 2.5rem;
  }
  h2 {
    text-align: center;
    margin: 0;
    font-family: var(--font-display);
    font-size: 1.9rem;
    letter-spacing: -0.02em;
  }

  .leaderboard-link {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    font-size: 1.3rem;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    text-decoration: none;
    transition: background 0.2s, border-color 0.2s, transform 0.15s;
  }
  .leaderboard-link:hover { background: var(--surface-2); border-color: var(--border-strong); transform: translateY(-1px); }

  .mode-section {
    width: 100%;
    max-width: 460px;
    margin: 1.5rem auto;
    padding: 1.6rem 1.4rem;
    border-radius: var(--r-xl);
    background: var(--surface);
    border: 1px solid var(--border);
    backdrop-filter: blur(14px);
  }
  .mode-section.arcade { border-color: rgba(163, 230, 53, 0.18); }

  .mode-section h3 {
    margin-top: 0;
    font-family: var(--font-display);
    font-size: 1.25rem;
    color: var(--text);
  }
  .mode-section p {
    color: var(--text-muted);
    margin-bottom: 1rem;
    font-size: 0.92rem;
  }

  .status-loading { margin: 1rem 0; color: var(--text-faint); }
  .daily-status { margin: 1rem 0; }
  .played-badge { font-weight: 600; color: var(--text); margin-bottom: 0.25rem; }
  .bankroll-badge { font-weight: 700; color: #fcd34d; margin-bottom: 1rem; }
  .arcade-bankroll { font-weight: 600; color: var(--text-muted); }
  .arcade-bankroll strong { color: #fcd34d; }

  .daily-btn {
    padding: 0.95rem 2rem;
    font-family: var(--font-display);
    font-size: 1.05rem;
    font-weight: 700;
    background: var(--brand-grad);
    border: none;
    border-radius: var(--r-md);
    color: #06210f;
    cursor: pointer;
    box-shadow: var(--glow-brand);
    transition: transform 0.16s var(--ease-spring), filter 0.2s;
  }
  .daily-btn:hover:not(.disabled) { transform: translateY(-2px); filter: brightness(1.05); }
  .daily-btn.disabled { opacity: 0.45; cursor: not-allowed; background: var(--surface-2); color: var(--text-muted); box-shadow: none; }

  .category-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: 0.65rem;
    margin-top: 1rem;
  }
  .category-grid button {
    padding: 1rem 0.75rem;
    font-family: var(--font-display);
    font-size: 0.95rem;
    font-weight: 600;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    color: var(--text);
    cursor: pointer;
    transition: background 0.2s, border-color 0.2s, transform 0.15s var(--ease-spring);
  }
  .category-grid button:hover {
    transform: translateY(-2px);
    background: linear-gradient(135deg, rgba(52, 211, 153, 0.14), rgba(163, 230, 53, 0.05));
    border-color: rgba(163, 230, 53, 0.4);
  }
</style>
