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
    user.set(session?.user ?? null);
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
    gap: 1rem;
    margin-top: 2rem;
  }

  h2 {
    text-align: center;
    margin: 0;
    font-size: 2rem;
    color: limegreen;
  }

  .leaderboard-link {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    font-size: 1.5rem;
    background: #333;
    color: white;
    border-radius: 10px;
    text-decoration: none;
    transition: background 0.2s;
  }

  .leaderboard-link:hover {
    background: limegreen;
  }

  .mode-section {
    margin: 2rem 0;
    padding: 1.5rem;
    border-radius: 12px;
    background: rgba(0, 0, 0, 0.05);
  }

  .mode-section h3 {
    margin-top: 0;
    color: #333;
  }

  .mode-section p {
    color: #666;
    margin-bottom: 1rem;
  }

  .status-loading {
    margin: 1rem 0;
    color: #888;
  }

  .daily-status {
    margin: 1rem 0;
  }

  .played-badge {
    font-weight: bold;
    color: #333;
    margin-bottom: 0.25rem;
  }

  .bankroll-badge {
    font-weight: bold;
    color: limegreen;
    margin-bottom: 1rem;
  }

  .arcade-bankroll {
    font-weight: 600;
  }

  .arcade-bankroll strong {
    color: limegreen;
  }

  .daily-btn {
    padding: 1rem 2rem;
    font-size: 1.2rem;
    font-weight: bold;
    background: linear-gradient(135deg, #ff6b35, #f7931e);
    border: none;
    border-radius: 12px;
    color: white;
    cursor: pointer;
    transition: transform 0.2s, box-shadow 0.2s;
  }

  .daily-btn:hover:not(.disabled) {
    transform: scale(1.05);
    box-shadow: 0 4px 12px rgba(255, 107, 53, 0.4);
  }

  .daily-btn.disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .category-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 0.75rem;
    margin-top: 1rem;
  }

  .category-grid button {
    padding: 1rem;
    font-size: 1rem;
    font-weight: bold;
    background-color: limegreen;
    border: none;
    border-radius: 10px;
    color: white;
    cursor: pointer;
    transition: background 0.2s ease;
  }

  .category-grid button:hover {
    background-color: green;
  }
</style>
