<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { supabase } from '$lib/supabaseClient.js';
  import { user } from '$lib/stores/userStore.js';
  import { getDailyStatus } from '$lib/stores/statsStore.js';
  import FlipDigit from '$lib/components/FlipDigit.svelte';

  const categories = [
    'Movies & TV 🎬',
    'Pop Culture & Celebrities 🌟',
    'Food & Drink 🍔',
    'Slang & Sayings 🗣️',
    'History & Culture 🏛️',
    'Sports & Games 🏆'
  ];

  let status = $state({ arcade_bankroll: 1000 });

  onMount(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    user.set(session?.user ? /** @type {{ id: string }} */ (session.user) : null);
    if (session?.user?.id) {
      const s = await getDailyStatus(session.user.id);
      status = { arcade_bankroll: s.arcade_bankroll ?? 1000 };
    }
  });

  /** @param {string} category */
  function selectArcade(category) {
    localStorage.setItem('gameMode', 'arcade');
    localStorage.setItem('selectedCategory', category);
    goto('/');
  }

  function goToMainMenu() {
    goto('/');
  }

  const bankroll = $derived(status.arcade_bankroll ?? 1000);
  const digits = $derived(String(Math.max(0, Math.floor(bankroll))).split(''));
</script>

<div class="header-row">
  <h2>🎮 Arcade Mode</h2>
</div>

<div class="main-menu-link-wrap">
  <button type="button" class="main-menu-btn" onclick={goToMainMenu}>← Return to main menu</button>
</div>

<div class="mode-section arcade">
  <h3 class="select-category-heading">Select Category</h3>
  <p class="current-bankroll-label">Current Bankroll</p>
  <div class="bankroll-container">
    <div class="bankroll-box">
      <span class="currency">$</span>
      {#each digits as d}
        <FlipDigit digit={+d} />
      {/each}
    </div>
  </div>
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
    margin-top: 2.5rem;
  }
  h2 {
    text-align: center;
    margin: 0;
    font-family: var(--font-display);
    font-size: 1.9rem;
    letter-spacing: -0.02em;
  }

  .main-menu-link-wrap {
    text-align: center;
    margin: 1rem 0 1.5rem 0;
  }
  .main-menu-btn {
    font-family: var(--font-ui);
    font-weight: 600;
    font-size: 0.9rem;
    padding: 0.6rem 1.1rem;
    border-radius: var(--r-md);
    border: 1px solid var(--border);
    background: var(--surface);
    color: var(--text);
    cursor: pointer;
    transition: background 0.2s, border-color 0.2s, transform 0.15s;
  }
  .main-menu-btn:hover {
    transform: translateY(-1px);
    background: var(--surface-2);
    border-color: var(--border-strong);
  }

  .mode-section {
    width: 100%;
    max-width: 440px;
    margin: 0 auto 2rem;
    padding: 1.6rem 1.4rem;
    border-radius: var(--r-xl);
    background: var(--surface);
    border: 1px solid var(--border);
    backdrop-filter: blur(14px);
  }

  .select-category-heading {
    margin: 0 0 0.25rem 0;
    font-family: var(--font-display);
    font-size: 1.5rem;
    font-weight: 700;
    text-align: center;
  }

  .current-bankroll-label {
    margin: 1rem 0 0.5rem 0;
    font-size: 0.65rem;
    letter-spacing: 0.2em;
    text-transform: uppercase;
    color: var(--text-faint);
    text-align: center;
    font-weight: 600;
  }

  .bankroll-container {
    display: flex;
    justify-content: center;
    align-items: center;
    width: 100%;
    margin: 0.5rem auto 1.5rem;
  }
  .bankroll-box {
    display: inline-flex;
    align-items: center;
    padding: 12px 26px;
    background: var(--surface-strong);
    border: 1px solid var(--border);
    border-radius: var(--r-lg);
    box-shadow: var(--shadow-md);
    backdrop-filter: blur(14px);
  }
  .currency {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1.45rem;
    margin-right: 3px;
    color: #fcd34d;
    text-shadow: 0 0 14px rgba(251, 191, 36, 0.45);
  }

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
