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
  let loading = $state(true);

  onMount(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    user.set(session?.user ? /** @type {{ id: string }} */ (session.user) : null);
    if (session?.user?.id) {
      const s = await getDailyStatus(session.user.id);
      status = { arcade_bankroll: s.arcade_bankroll ?? 1000 };
    }
    loading = false;
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
    gap: 1rem;
    margin-top: 2rem;
  }

  h2 {
    text-align: center;
    margin: 0;
    font-size: 2rem;
    color: #0055bb;
  }

  .main-menu-link-wrap {
    text-align: center;
    margin: 1rem 0 1.5rem 0;
  }

  .main-menu-btn {
    font-family: 'Orbitron', sans-serif;
    font-size: 1rem;
    padding: 0.6rem 1rem;
    border-radius: 10px;
    border: 2px solid #2e9417;
    background: linear-gradient(180deg, #46a230, #318020);
    color: #fff;
    cursor: pointer;
    box-shadow: inset 1px 1px 4px rgba(255, 255, 255, 0.3), 2px 2px 6px rgba(0, 0, 0, 0.6);
  }

  .main-menu-btn:hover {
    transform: translateY(-2px);
    background: linear-gradient(180deg, #4cb038, #368828);
  }

  .mode-section {
    margin: 2rem 0;
    padding: 1.5rem;
    border-radius: 12px;
    background: rgba(0, 85, 187, 0.08);
    border: 2px solid rgba(0, 85, 187, 0.35);
  }

  .select-category-heading {
    margin: 0 0 0.5rem 0;
    font-size: 2rem;
    font-weight: 700;
    color: #0055bb;
    text-align: center;
    text-shadow: 0 0 8px rgba(68, 136, 255, 0.4);
  }

  .current-bankroll-label {
    margin: 1rem 0 0.5rem 0;
    font-size: 1rem;
    color: #0055bb;
    text-align: center;
    font-weight: 600;
  }

  .mode-section p {
    color: #0055bb;
    margin-bottom: 1rem;
  }

  /* Same bankroll graphic as in-game */
  .bankroll-container {
    display: flex;
    justify-content: center;
    align-items: center;
    width: 100%;
    margin: 1rem auto;
  }

  .bankroll-box {
    padding: 2px 28px;
    font-size: 0.4rem;
    font-family: 'Orbitron', sans-serif;
    color: #fff;
    background: linear-gradient(180deg, #d1cdcd, #858484);
    border: 2px solid rgba(255, 255, 255, 0.4);
    border-radius: 8px;
    text-align: center;
    box-shadow:
      inset 1px 1px 4px rgba(255, 255, 255, 0.2),
      2px 2px 6px rgba(0, 0, 0, 0.742),
      3px 3px 8px rgba(0, 0, 0, 0.5),
      0 0 6px rgba(245, 246, 245, 0.5);
    display: inline-flex;
    justify-content: center;
    align-items: center;
    letter-spacing: 1px;
    backdrop-filter: blur(5px);
    transition: transform 0.3s ease-in-out, box-shadow 0.3s ease-in-out;
    animation: bankrollGlow 2.5s infinite alternate ease-in-out;
  }

  .bankroll-box:hover {
    transform: scale(1.05);
    box-shadow:
      0 0 25px rgba(251, 251, 251, 0.8),
      0 0 10px rgba(158, 158, 158, 0.7) inset;
  }

  .currency {
    font-size: 0.85rem;
    margin-right: 4px;
    font-weight: bold;
    color: rgba(255, 255, 255, 0.8);
    text-shadow: 0 0 5px rgba(255, 255, 255, 0.5);
  }

  @keyframes bankrollGlow {
    0%   { box-shadow: 0 0 8px rgba(245, 246, 245, 0.5); }
    50%  { box-shadow: 0 0 12px rgba(242, 243, 242, 0.7); }
    100% { box-shadow: 0 0 8px rgba(239, 241, 239, 0.5); }
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
