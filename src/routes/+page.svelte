<script>
  import { onMount, tick } from 'svelte';
  import { browser } from '$app/environment';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';

  import { gameStore, fetchRandomGame, fetchDailyGame } from '$lib/stores/GameStore.js';
  import { user, userProfile, fetchUserProfile, ensureProfileExists } from '$lib/stores/userStore.js';
  import { hasPlayedDailyToday, saveArcadeBankroll } from '$lib/stores/statsStore.js';
  import {
    saveGameToLocalStorage,
    loadGameFromLocalStorage,
    clearSavedGame,
    getSavedGameInfo
  } from '$lib/stores/localGameUtils.js';
  import { gameWasRestored } from '$lib/stores/GameStateFlags.js';
  import { goto } from '$app/navigation';

  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import FlipDigit from '$lib/components/FlipDigit.svelte';
  import Auth from '$lib/components/Auth.svelte';

  export let data;

  // UI state
  let showHowToPlay = false;
  let darkMode = false;
  /** @type {boolean} */
  let wagerUIVisible = false;
  /** @type {number} */
  let sliderWagerAmount = 0;
  let sliderLocked = false;
  let showResultModal = false;
  let hasTriggeredModal = false;
  let hasInitialized = false;
  /** @type {string | null} */
  let initError = null; // 🔍 Diagnostic: what failed during init
  /** Show main menu (Daily / Arcade / Leaderboard / My account) when true; game when false */
  let showMainMenu = false;
  /** When showing menu: can we show "Resume daily" / "Resume arcade"? */
  let savedGameInfo = /** @type {{ gameMode: string, gameState: string } | null} */ (null);
  /** When showing menu: has user already played daily today? */
  let menuDailyPlayed = false;

  // ✅ Load Supabase user profile and sync bankroll (creates profile if missing)
  /** @param {string} userId */
  async function loadUserProfile(userId) {
    try {
      const { data: profile, error } = await fetchUserProfile(userId);
      if (error || !profile) {
        console.warn("⚠️ Failed to load profile:", error?.message ?? error);
        // Auto-create profile for new users (no profile row yet)
        const createError = await ensureProfileExists(userId);
        if (createError) {
          console.error("❌ Failed to create profile:", createError);
          return null;
        }
        const { data: newProfile } = await fetchUserProfile(userId);
        if (!newProfile) return null;
        userProfile.set(newProfile);
        gameStore.update(state => ({ ...state, bankroll: 1000 }));
        console.log("✅ Profile created. Bankroll: 1000");
        return newProfile;
      }

      userProfile.set(profile);
      gameStore.update(state => ({
        ...state,
        bankroll: profile.arcade_bankroll ?? 1000
      }));

      console.log("✅ Profile loaded. Bankroll:", profile.current_bankroll ?? profile.arcade_bankroll);
      return profile;
    } catch (err) {
      console.error("❌ Profile load error:", err instanceof Error ? err.message : String(err));
      return null;
    }
  }

  // ✅ Main logic on initial mount
  onMount(async () => {
    initError = null;
    try {
      const { data: { session }, error } = await supabase.auth.getSession();
      if (!session || error) {
        initError = "No session (session: " + (session ? "yes" : "no") + ", error: " + (error?.message || "none") + ")";
        console.warn("⛔", initError);
        return;
      }

      user.set(/** @type {{ id: string }} */ (session.user));
      const profile = await loadUserProfile(session.user.id);
      if (!profile) {
        initError = "Profile failed to load or create. Check Supabase profiles table and RLS policies.";
        console.warn("⛔", initError);
        return;
      }

      const peek = getSavedGameInfo(session.user.id);
      // Daily is now server-resumed (daily_start); only arcade resumes from localStorage.
      const arcadeSave = peek && peek.gameMode === 'arcade' ? peek : null;
      const inProgress = arcadeSave && arcadeSave.gameState !== 'won' && arcadeSave.gameState !== 'lost';

      if (inProgress) {
        const restored = loadGameFromLocalStorage();
        if (restored) {
          gameWasRestored.set(true);
          showMainMenu = false;
          console.log("🔁 Game restored from localStorage");
        } else {
          showMainMenu = true;
          savedGameInfo = arcadeSave;
          menuDailyPlayed = await hasPlayedDailyToday(session.user.id);
        }
      } else {
        showMainMenu = true;
        savedGameInfo = arcadeSave;
        menuDailyPlayed = await hasPlayedDailyToday(session.user.id);
        // If they just came from /select with a category, start arcade instead of showing menu
        const mode = localStorage.getItem('gameMode');
        const category = localStorage.getItem('selectedCategory');
        if (mode === 'arcade' && category) {
          const ok = await fetchRandomGame(category);
          if (ok) {
            showMainMenu = false;
            hasInitialized = true;
          }
        }
      }

      await tick();
      hasInitialized = true;

    } catch (err) {
      initError = "Init error: " + (err instanceof Error ? err.message : String(err));
      console.error("❌", initError);
    }
  });

  // ✅ Reactive puzzle loader if puzzle is missing (skip when showing main menu)
  $: if (
    hasInitialized &&
    loggedIn &&
    !showMainMenu &&
    $gameStore.currentPhrase === '' &&
    !$gameWasRestored
  ) {
    const gameMode = localStorage.getItem('gameMode') || 'daily';
    if (gameMode === 'daily') {
      fetchDailyGame().then((ok) => {
        if (!ok) initError = "Daily puzzle failed to load.";
      });
    } else {
      const category = localStorage.getItem('selectedCategory');
      if (category) {
        fetchRandomGame(category).then((ok) => {
          if (!ok) initError = "Arcade puzzle failed to load.";
        });
      } else {
        window.location.href = '/select/arcade';
      }
    }
  }

  // ✅ Set user from SSR if present (profile load happens once in onMount)
  $: if (data?.user) {
    user.set(/** @type {{ id: string }} */ (data.user));
  }

  // Reactive state values
  $: loggedIn = !!$user?.id;
  $: bankroll = $gameStore.bankroll || 0;
  $: digits = String(bankroll).split('');
  $: sliderLocked = $gameStore.gameState === 'guess_mode';

  // ✨ Bankroll change reaction (pulse + floating delta)
  let bankrollPulse = '';
  let bankrollDelta = 0;
  /** @type {number | null} */
  let _prevBankroll = null;
  $: {
    const b = $gameStore.bankroll;
    if (_prevBankroll !== null && typeof b === 'number' && b !== _prevBankroll) {
      bankrollDelta = b - _prevBankroll;
      bankrollPulse = bankrollDelta > 0 ? 'up' : 'down';
      const token = bankrollDelta;
      setTimeout(() => { if (bankrollDelta === token) bankrollPulse = ''; }, 950);
    }
    if (typeof b === 'number') _prevBankroll = b;
  }

  // ✅ Auto-save whenever state is valid
  $: if (
    loggedIn &&
    $gameStore.currentPhrase &&
    $gameStore.category &&
    $gameStore.purchasedLetters.length > 0
  ) {
    saveGameToLocalStorage();
  }

  // ✅ Dark mode init
  const applyDarkMode = () => {
    document.body.classList.toggle('dark-mode', darkMode);
  };

  const toggleDarkMode = () => {
    darkMode = !darkMode;
    localStorage.setItem('darkMode', String(darkMode));
    applyDarkMode();
  };

  onMount(() => {
    if (browser) {
      darkMode = localStorage.getItem('darkMode') === 'true';
      applyDarkMode();
    }
    ['click', 'mousedown', 'touchstart'].forEach(event =>
      document.addEventListener(event, removeButtonFocus, true)
    );
  });

  /** @param {Event} e */
  const removeButtonFocus = (e) => {
    if (e.target && /** @type {HTMLElement} */ (e.target).tagName === 'BUTTON') /** @type {HTMLButtonElement} */ (e.target).blur();
  };

  // ✅ Log out: clear saved game so next login always shows main menu
  const handleLogout = async () => {
    clearSavedGame();
    gameWasRestored.set(false);
    await supabase.auth.signOut();
    user.set(null);
    location.reload();
  };

  /** Start daily: resume if in progress, else show "already played" or fetch new daily */
  async function handleMenuDaily() {
    const currentUser = get(user);
    if (!currentUser?.id) return;
    // Finished today's daily already -> show streak message (server enforces one/day).
    if (menuDailyPlayed) {
      showStreakMessage = true;
      return;
    }
    // daily_start resumes an in-progress session or begins a fresh one, server-side.
    localStorage.setItem('gameMode', 'daily');
    const ok = await fetchDailyGame();
    if (ok) {
      hasInitialized = true;
      showMainMenu = false;
    } else {
      initError = "Daily puzzle failed to load.";
    }
  }

  /** Start or resume arcade: resume from save or go to arcade category select */
  function handleMenuArcade() {
    if (savedGameInfo?.gameMode === 'arcade' && savedGameInfo?.gameState !== 'won' && savedGameInfo?.gameState !== 'lost') {
      loadGameFromLocalStorage();
      gameWasRestored.set(true);
      showMainMenu = false;
      return;
    }
    goto('/select/arcade');
  }

  function handleMenuLeaderboard() {
    goto('/leaderboard');
  }

  /** Return to main menu from game (saves and refreshes menu state) */
  function goToMainMenu() {
    const currentUser = get(user);
    if (!currentUser?.id) return;
    saveGameToLocalStorage();
    savedGameInfo = getSavedGameInfo(currentUser.id);
    showMainMenu = true;
  }

  let showMyAccount = false;
  let showStreakMessage = false;
  function handleMenuMyAccount() {
    showMyAccount = true;
  }
  /** @param {KeyboardEvent} e */
  function handleEscape(e) {
    if (e.key !== 'Escape') return;
    if (showMyAccount) showMyAccount = false;
    if (showStreakMessage) showStreakMessage = false;
  }

  const handlePlayAgain = async () => {
    showResultModal = false;
    hasTriggeredModal = false;

    const currentUser = get(user);
    if (!currentUser?.id) return;

    const store = get(gameStore);
    if (store.gameMode === 'arcade') {
      await saveArcadeBankroll(1000);
    }
    clearSavedGame();
    gameWasRestored.set(false);
    localStorage.removeItem('selectedCategory');
    if (store.gameMode === 'arcade') {
      goto('/select/arcade');
    } else {
      goto('/leaderboard?mode=daily');
    }
  };

  const handleNextPuzzle = async () => {
    showResultModal = false;
    hasTriggeredModal = false;

    const currentUser = get(user);
    if (!currentUser?.id) return;

    const store = get(gameStore);
    if (store.gameMode === 'arcade') {
      await saveArcadeBankroll(store.bankroll);
    }

    clearSavedGame();
    gameWasRestored.set(false);
    localStorage.removeItem('selectedCategory');
    if (store.gameMode === 'arcade') {
      goto('/select/arcade');
    } else {
      goto('/leaderboard?mode=daily');
    }
  };

  const onPhraseRevealComplete = () => {
    if (!hasTriggeredModal && ['won', 'lost'].includes($gameStore.gameState)) {
      hasTriggeredModal = true;
      setTimeout(() => {
        showResultModal = true;
      }, 1000);
    }
  };
</script>
<svelte:window on:keydown={handleEscape} />
<!-- 🔹 Top Control Buttons -->
<div class="top-buttons">
  <!-- ❓ How to Play -->
  <button class="icon-button subtle-button" on:click={() => showHowToPlay = true}>
    ❓
  </button>

  <!-- ☰ Main menu (only when in a puzzle) -->
  {#if loggedIn && !showMainMenu}
    <button class="icon-button subtle-button" title="Main menu" on:click={goToMainMenu}>
      ☰
    </button>
  {/if}

  <!-- 🏆 Leaderboard -->
  {#if loggedIn}
    <a href="/leaderboard" class="icon-button subtle-button" title="Weekly Leaderboard">🏆</a>
  {/if}

  <!-- 🌙 Dark Mode Toggle -->
  <button class="icon-button subtle-button" on:click={toggleDarkMode}>
    {darkMode ? '☀️' : '🌙'}
  </button>

  <!-- 🚪 Logout -->
  {#if loggedIn}
    <button class="icon-button subtle-button" on:click={handleLogout}>
      🚪
    </button>
  {/if}
</div>

<!-- 📜 How to Play Modal -->
{#if showHowToPlay}
  <div class="modal-overlay">
    <div class="modal-content">
      <button class="close-btn" on:click={() => showHowToPlay = false}>❌</button>

      <h2>📜 How to Play</h2>
      <p>💰 Start with $1000. Spend it on information, then solve the phrase. Whatever's left is your score.</p>

      <h3>📅 Daily vs Arcade</h3>
      <p><b>Daily:</b> One puzzle per day. Counts for the daily leaderboard!<br />
      <b>Arcade:</b> Unlimited play. Build your cumulative bankroll!</p>

      <h3>🎯 Goal</h3>
      <p>Solve the phrase before you run out of money.</p>

      <h3>🕹️ Gameplay</h3>
      <ul>
        <li>🔤 <b>Buy Letters:</b> Tap a letter to buy it. In the phrase → all copies revealed. Not in it → you lose the money.</li>
        <li>🔍 <b>Reveal ($150):</b> Reveals every copy of the most useful unrevealed letter — guaranteed, never random.</li>
        <li>✏️ <b>Solve:</b> Fill the blanks and submit. You get <b>3 free tries</b> — a wrong guess just costs a try, no money.</li>
        <li>🏁 <b>Out of tries?</b> You can still win by buying letters until the whole phrase is revealed.</li>
        <li>💀 <b>You only lose</b> if you go broke before solving.</li>
      </ul>

      <p><strong>Spend smart, solve cheap, bank the rest. 🚀</strong></p>
    </div>
  </div>
{/if}

<main>
  {#if !loggedIn}
    <!-- 🔐 Login Screen -->
    <div class="auth-screen">
      <Auth />
    </div>
  {:else if !hasInitialized}
    <!-- ⏳ Loading (prevents flash of game UI / diagnostic before we know menu vs game) -->
    <div class="init-loading">Loading…</div>
  {:else if showMainMenu}
    <!-- 🏠 Main Menu (after sign-in) -->
    <div class="main-menu fade-up">
      <div class="menu-hero">
        <div class="menu-mark float">WB</div>
        <h1 class="menu-wordmark"><span class="brand-text">Word</span>Bank</h1>
        <p class="menu-tagline">Crack the phrase. Bank the win.</p>
      </div>
      <div class="main-menu-buttons stagger">
        <button
          class="menu-card primary sheen"
          style="--i: 0"
          class:disabled={menuDailyPlayed && !(savedGameInfo?.gameMode === 'daily' && savedGameInfo?.gameState !== 'won' && savedGameInfo?.gameState !== 'lost')}
          on:click={handleMenuDaily}
        >
          <span class="mc-icon">🎯</span>
          <span class="mc-body">
            <span class="mc-title">{#if savedGameInfo?.gameMode === 'daily' && savedGameInfo?.gameState !== 'won' && savedGameInfo?.gameState !== 'lost'}Resume Daily{:else}Daily Puzzle{/if}</span>
            <span class="mc-sub">One puzzle a day · ranked</span>
          </span>
          <span class="mc-arrow">→</span>
        </button>
        <button class="menu-card" style="--i: 1" on:click={handleMenuArcade}>
          <span class="mc-icon">🕹️</span>
          <span class="mc-body">
            <span class="mc-title">{#if savedGameInfo?.gameMode === 'arcade' && savedGameInfo?.gameState !== 'won' && savedGameInfo?.gameState !== 'lost'}Resume Arcade{:else}Arcade Mode{/if}</span>
            <span class="mc-sub">Unlimited · build your bankroll</span>
          </span>
          <span class="mc-arrow">→</span>
        </button>
        <button class="menu-card" style="--i: 2" on:click={handleMenuLeaderboard}>
          <span class="mc-icon">🏆</span>
          <span class="mc-body">
            <span class="mc-title">Leaderboard</span>
            <span class="mc-sub">See who's on top</span>
          </span>
          <span class="mc-arrow">→</span>
        </button>
        <button class="menu-card" style="--i: 3" on:click={handleMenuMyAccount}>
          <span class="mc-icon">👤</span>
          <span class="mc-body">
            <span class="mc-title">My Account</span>
            <span class="mc-sub">Profile &amp; sign out</span>
          </span>
          <span class="mc-arrow">→</span>
        </button>
      </div>
    </div>
    <!-- Streak message (when Daily is disabled and user taps it) -->
    {#if showStreakMessage}
      <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="Come back tomorrow">
        <button type="button" class="modal-backdrop" aria-label="Close" on:click={() => showStreakMessage = false}></button>
        <div class="modal-content main-menu-modal">
          <button class="close-btn" on:click={() => showStreakMessage = false}>❌</button>
          <h2>Come Back Tomorrow</h2>
          <p class="streak-message">Come back tomorrow to continue your streak!</p>
          <button class="main-menu-btn" on:click={() => showStreakMessage = false}>OK</button>
        </div>
      </div>
    {/if}
    <!-- My Account modal -->
    {#if showMyAccount}
      <div class="modal-overlay" role="dialog" aria-modal="true" aria-label="My Account">
        <button type="button" class="modal-backdrop" aria-label="Close" on:click={() => showMyAccount = false}></button>
        <div class="modal-content main-menu-modal">
          <button class="close-btn" on:click={() => showMyAccount = false}>❌</button>
          <h2>My Account</h2>
          {#if $user?.email}
            <p class="account-email">{$user.email}</p>
          {/if}
          <button class="main-menu-btn" on:click={() => { showMyAccount = false; handleLogout(); }}>Log Out</button>
        </div>
      </div>
    {/if}
  {:else}
    <!-- ✅ GAME UI (Visible only when logged in) -->

    <!-- 🧠 Game Logo -->
    <div class="game-logo"><span class="brand-text">Word</span>Bank</div>

    <!-- 🔍 Diagnostic banner (shows when init failed) -->
    {#if initError}
      <div class="diagnostic-banner">
        <strong>⚠️ Diagnostic:</strong> {initError}
        <br />
        <small>Open DevTools (F12) → Console for details.</small>
        <button class="diagnostic-retry" on:click={() => { initError = null; location.reload(); }}>
          Retry
        </button>
      </div>
    {:else if loggedIn && hasInitialized && !$gameStore.currentPhrase && !$gameWasRestored}
      <div class="diagnostic-banner info">
        Loading puzzle… If this persists, check Console (F12).
      </div>
    {/if}

    <!-- 🌍 Category Display -->
    <div class="puzzle-meta">
      {#if $gameStore.category}<span class="category-chip">{$gameStore.category}</span>{/if}
      {#if $gameStore.subcategory}<span class="subcat-chip">{$gameStore.subcategory}</span>{/if}
    </div>


    <!-- 🔤 Phrase Display -->
    <section class="phrase-section">
      <PhraseDisplay on:revealComplete={onPhraseRevealComplete} />
    </section>

    <!-- 💰 Bankroll Display -->
    <section class="stats-section">
      <div class="bankroll-container">
        <div class="bankroll-box" class:pulse-up={bankrollPulse === 'up'} class:pulse-down={bankrollPulse === 'down'}>
          {#if bankrollPulse}
            <span class="bankroll-delta {bankrollPulse}">{bankrollDelta > 0 ? '+' : '−'}${Math.abs(bankrollDelta)}</span>
          {/if}
          <span class="bankroll-label">Balance</span>
          <span class="bankroll-amount">
            <span class="currency">$</span>
            {#each digits as d}
              <FlipDigit digit={+d} />
            {/each}
          </span>
        </div>
      </div>
    </section>

    <!-- 🎚️ Wager UI (arcade only) -->
    {#if $gameStore.gameMode === 'arcade' && wagerUIVisible}
      <div class="wager-ui">
        <div class="wager-row">
          <div class="wager-label">
            Wager<br /><span class="wager-amount">${sliderWagerAmount}</span>
          </div>

          <input
            type="range"
            min="0"
            max={$gameStore.bankroll}
            step="1"
            bind:value={sliderWagerAmount}
            class="wager-slider"
            disabled={sliderLocked || $gameStore.gameState === 'won' || $gameStore.gameState === 'lost'}
            />

          <div class="wager-label">
            To Win<br /><span class="wager-amount">${sliderWagerAmount * 2}</span>
          </div>
        </div>
      </div>
    {/if}

    <!-- 🎮 Solve / Cancel Buttons -->
    <section class="buttons-section">
      <GameButtons
        bind:wagerUIVisible
        bind:sliderWagerAmount
        on:setWagerUIVisible={(e) => wagerUIVisible = e.detail}
        on:setSliderWagerAmount={(e) => sliderWagerAmount = e.detail}
      />
    </section>

    <!-- ⌨️ Keyboard Section (keyboard disables itself via gameStore state) -->
    <section class="keyboard-section">
      <Keyboard
        on:letterSelected={() => {
          if ($gameStore.gameState !== 'guess_mode') {
            wagerUIVisible = false;
          }
        }}
      />
    </section>

    <!-- 🏆 Game Outcome Banner -->
    {#if $gameStore.gameState === "won"}
      <div class="win-burst" aria-hidden="true"></div>
      <div class="banner win">Winner!</div>
    {:else if $gameStore.gameState === "lost"}
      <div class="banner lose">Bankrupt!</div>
    {/if}

    <!-- 🎯 Result Modal -->
    {#if showResultModal && ['won', 'lost'].includes($gameStore.gameState)}
      <div class="modal-overlay">
        <div class="modal-content">
          <h2>{$gameStore.gameState === 'won' ? '🎉 You Win!' : '💀 Game Over'}</h2>
          <p>
            {$gameStore.gameState === 'won'
              ? 'Great job! Want to try the next one?'
              : 'You ran out of cash. Want to try again?'}
          </p>

          <div style="margin-top: 16px;">
<!-- ✅ Fixed version -->
<button
  class="next-puzzle-button"
  on:click={$gameStore.gameState === 'won' ? handleNextPuzzle : handlePlayAgain}
  disabled={!['won', 'lost'].includes($gameStore.gameState)}
>
  {$gameStore.gameState === 'won' ? 'Next Puzzle' : 'Play Again'}
</button>
          </div>
        </div>
      </div>
    {/if}
  {/if}
</main>

<style>
  @import url('https://fonts.googleapis.com/css2?family=VT323&display=swap');
  @import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@500;700&display=swap');
  @import url('https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;700&display=swap');
  @import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700&display=swap');

  main {
    max-width: 600px;
    margin: 0 auto;
    text-align: center;
    font-family: var(--font-ui);
    padding: 16px 12px 248px; /* space so content stays above fixed Solve + keyboard */
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
  }

  .puzzle-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    justify-content: center;
    margin: 0 0 22px;
  }
  .category-chip {
    font-family: var(--font-display);
    font-weight: 600;
    font-size: 0.8rem;
    color: var(--brand-2);
    background: rgba(163, 230, 53, 0.10);
    border: 1px solid rgba(163, 230, 53, 0.28);
    padding: 6px 13px;
    border-radius: var(--r-pill);
  }
  .subcat-chip {
    font-size: 0.8rem;
    color: var(--text-muted);
    background: var(--surface);
    border: 1px solid var(--border);
    padding: 6px 13px;
    border-radius: var(--r-pill);
  }

  .phrase-section {
    width: 100%;
    padding: 0;
    margin-bottom: 0;
    padding-bottom: min(1rem, 3vw);
    min-height: 0;
  }

  .stats-section {
    width: 100%;
    padding: 0;
    margin-top: 0.6rem;
    margin-bottom: 0.4rem;
    flex-shrink: 0;
  }

  @media (max-width: 600px) {
    .phrase-section {
      padding-bottom: 0.75rem;
    }
    .stats-section {
      margin-top: 0.75rem;
    }
  }

  .keyboard-section,
  .buttons-section {
    width: 100%;
    padding: 0;
  }

  .diagnostic-banner {
    background: #ffebee;
    border: 2px solid #c62828;
    border-radius: 8px;
    padding: 12px 16px;
    margin: 12px 0;
    text-align: left;
    font-size: 0.9rem;
    color: #b71c1c;
    max-width: 100%;
  }
  .diagnostic-banner.info {
    background: #e3f2fd;
    border-color: #1976d2;
    color: #0d47a1;
  }
  .diagnostic-retry {
    margin-top: 8px;
    padding: 6px 12px;
    background: #c62828;
    color: white;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-weight: bold;
  }
  .diagnostic-retry:hover {
    background: #b71c1c;
  }

  .init-loading {
    min-height: 200px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1rem;
    color: #666;
  }

  /* Main menu (after sign-in) — premium dark */
  .main-menu {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 3.5rem 1.1rem 2rem;
    gap: 2rem;
  }
  .menu-hero {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
  }
  .menu-mark {
    width: 60px;
    height: 60px;
    display: grid;
    place-items: center;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1.35rem;
    color: #06210f;
    background: var(--brand-grad);
    border-radius: 18px;
    box-shadow: var(--glow-brand);
    margin-bottom: 16px;
  }
  .menu-wordmark {
    font-family: var(--font-display);
    font-size: 2.4rem;
    letter-spacing: -0.03em;
    margin: 0;
  }
  .menu-tagline {
    margin: 8px 0 0;
    color: var(--text-muted);
    font-size: 0.95rem;
  }
  .main-menu-buttons {
    display: flex;
    flex-direction: column;
    gap: 0.85rem;
    width: 100%;
    max-width: 360px;
  }
  .menu-card {
    display: flex;
    align-items: center;
    gap: 14px;
    text-align: left;
    padding: 16px 18px;
    border-radius: var(--r-lg);
    background: var(--surface);
    border: 1px solid var(--border);
    color: var(--text);
    cursor: pointer;
    backdrop-filter: blur(14px) saturate(140%);
    -webkit-backdrop-filter: blur(14px) saturate(140%);
    transition: transform 0.16s var(--ease-spring), background 0.2s, border-color 0.2s, box-shadow 0.2s;
  }
  .menu-card:hover:not(.disabled) {
    transform: translateY(-2px);
    background: var(--surface-2);
    border-color: var(--border-strong);
    box-shadow: var(--shadow-md);
  }
  .menu-card:active:not(.disabled) { transform: scale(0.99); }
  .menu-card.primary {
    border-color: rgba(163, 230, 53, 0.4);
    background: linear-gradient(135deg, rgba(52, 211, 153, 0.16), rgba(163, 230, 53, 0.06));
    box-shadow: var(--glow-brand);
  }
  .menu-card.disabled { opacity: 0.45; cursor: not-allowed; }
  .mc-icon {
    width: 46px;
    height: 46px;
    flex-shrink: 0;
    display: grid;
    place-items: center;
    font-size: 1.4rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border);
    border-radius: 13px;
  }
  .menu-card.primary .mc-icon {
    background: var(--brand-grad);
    border: none;
  }
  .mc-body { display: flex; flex-direction: column; gap: 2px; flex: 1; }
  .mc-title { font-family: var(--font-display); font-weight: 600; font-size: 1.06rem; }
  .mc-sub { font-size: 0.8rem; color: var(--text-muted); }
  .mc-arrow { color: var(--text-faint); font-size: 1.1rem; transition: transform 0.2s, color 0.2s; }
  .menu-card:hover:not(.disabled) .mc-arrow { transform: translateX(3px); color: var(--brand-2); }

  /* Modal action button (reused brand button) */
  .main-menu-btn {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1rem;
    padding: 13px 20px;
    border-radius: var(--r-md);
    border: none;
    background: var(--brand-grad);
    color: #06210f;
    cursor: pointer;
    box-shadow: var(--glow-brand);
    transition: transform 0.15s var(--ease-spring), filter 0.2s;
  }
  .main-menu-btn:hover { transform: translateY(-2px); filter: brightness(1.05); }
  .main-menu-modal { text-align: center; }
  .main-menu-modal .main-menu-btn { margin-top: 1rem; }
  .streak-message {
    margin: 1rem 0 0 0;
    font-size: 1.05rem;
    color: var(--text-muted);
  }
  .account-email {
    font-size: 0.95rem;
    color: var(--text-muted);
    margin: 0.5rem 0 0 0;
  }

  :global(body.dark-mode) .diagnostic-banner {
    background: rgba(255, 80, 80, 0.2);
    border-color: #ef5350;
    color: #ffcdd2;
  }
  :global(body.dark-mode) .diagnostic-banner.info {
    background: rgba(33, 150, 243, 0.2);
    border-color: #42a5f5;
    color: #90caf9;
  }

  .bankroll-container {
    display: flex;
    justify-content: center;
    align-items: center;
    width: 100%;
    margin: 0 auto;
  }

  .bankroll-box {
    position: relative;
    display: inline-flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    padding: 12px 30px;
    background: var(--surface-strong);
    border: 1px solid var(--border);
    border-radius: var(--r-lg);
    box-shadow: var(--shadow-md), inset 0 1px 0 rgba(255, 255, 255, 0.06);
    backdrop-filter: blur(14px);
    -webkit-backdrop-filter: blur(14px);
  }
  .bankroll-box.pulse-up { animation: bankPulseUp 0.7s var(--ease-spring); }
  .bankroll-box.pulse-down { animation: bankPulseDown 0.6s var(--ease-spring); }
  @keyframes bankPulseUp {
    0%, 100% { transform: scale(1); box-shadow: var(--shadow-md), inset 0 1px 0 rgba(255,255,255,0.06); }
    40% { transform: scale(1.07); box-shadow: var(--shadow-md), 0 0 30px rgba(163,230,53,0.55); }
  }
  @keyframes bankPulseDown {
    0%, 100% { transform: scale(1); }
    35% { transform: scale(0.96); }
  }
  .bankroll-delta {
    position: absolute;
    top: 2px;
    right: 12px;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 0.95rem;
    font-variant-numeric: tabular-nums;
    pointer-events: none;
    text-shadow: 0 0 12px currentColor;
  }
  .bankroll-delta.up { color: var(--brand-2); animation: deltaFloatUp 0.95s var(--ease-out) forwards; }
  .bankroll-delta.down { color: #fb7185; animation: deltaFloatDown 0.95s var(--ease-out) forwards; }
  @keyframes deltaFloatUp {
    0% { opacity: 0; transform: translateY(8px); }
    25% { opacity: 1; }
    100% { opacity: 0; transform: translateY(-28px); }
  }
  @keyframes deltaFloatDown {
    0% { opacity: 0; transform: translateY(-8px); }
    25% { opacity: 1; }
    100% { opacity: 0; transform: translateY(24px); }
  }

  .bankroll-label {
    font-family: var(--font-ui);
    font-size: 0.62rem;
    font-weight: 600;
    letter-spacing: 0.2em;
    text-transform: uppercase;
    color: var(--text-faint);
  }

  .bankroll-amount {
    display: inline-flex;
    align-items: center;
  }

  .currency {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1.55rem;
    margin-right: 3px;
    color: #fcd34d;
    text-shadow: 0 0 14px rgba(251, 191, 36, 0.45);
  }

  .game-logo {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1.5rem;
    letter-spacing: -0.02em;
    text-align: center;
    margin: 4px 0 14px;
  }

  .logo-container {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-top: -20px;
    margin-bottom: 0;
  }

  :global(html, body) {
    overflow-x: hidden;
    touch-action: manipulation;
  }

  @keyframes winPulse {
    0%, 100% { transform: scale(1) rotate(0deg); text-shadow: 0px 0px 10px green; }
    25% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px limegreen; }
    50% { transform: scale(1.5) rotate(-3deg); text-shadow: 0px 0px 30px limegreen; }
    75% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px green; }
  }

  @keyframes winFlash {
    0% { opacity: 1; }
    50% { opacity: 0.2; }
    100% { opacity: 1; }
  }

  .win-burst {
    position: fixed;
    inset: 0;
    z-index: 998;
    pointer-events: none;
    background: radial-gradient(circle at 50% 45%, rgba(163, 230, 53, 0.35), rgba(52, 211, 153, 0.18) 35%, transparent 60%);
    animation: winBurst 1s var(--ease-out) forwards;
  }
  @keyframes winBurst {
    0% { opacity: 0; transform: scale(0.4); }
    30% { opacity: 1; }
    100% { opacity: 0; transform: scale(1.6); }
  }

  .banner.win {
    font-family: var(--font-display);
    font-size: 1.6rem;
    font-weight: 700;
    letter-spacing: 0.02em;
    color: #06210f;
    text-transform: uppercase;
    background: var(--brand-grad);
    text-align: center;
    padding: 14px 28px;
    border-radius: var(--r-pill);
    box-shadow: var(--glow-brand);
    animation: bannerPop 0.5s var(--ease-spring) both;
  }
  @keyframes bannerPop {
    from { transform: scale(0.8); opacity: 0; }
    to { transform: scale(1); opacity: 1; }
  }

  @keyframes gameOverPulse {
    0%, 100% { transform: scale(1) rotate(0deg); text-shadow: 0px 0px 10px red; }
    25% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px red; }
    50% { transform: scale(1.5) rotate(-3deg); text-shadow: 0px 0px 30px red; }
    75% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px red; }
  }

  @keyframes gameOverFlash {
    0% { opacity: 1; }
    50% { opacity: 0.2; }
    100% { opacity: 1; }
  }

  .banner.lose {
    font-family: var(--font-display);
    font-size: 1.6rem;
    font-weight: 700;
    letter-spacing: 0.02em;
    color: #fff;
    text-transform: uppercase;
    background: linear-gradient(135deg, #fb5a5a, #c81e1e);
    text-align: center;
    padding: 14px 28px;
    border-radius: var(--r-pill);
    box-shadow: 0 8px 28px rgba(200, 30, 30, 0.4);
    animation: bannerPop 0.5s var(--ease-spring) both;
  }

  button:focus,
  button:active {
    outline: none !important;
    box-shadow: none !important;
    background: inherit !important;
  }

  button:focus-visible {
    outline: none !important;
  }

  .top-buttons {
    position: fixed;
    top: 12px;
    left: 50%;
    transform: translateX(-50%);
    width: calc(100% - 24px);
    max-width: 600px;
    display: flex;
    justify-content: space-between;
    z-index: 1000;
  }

  .icon-button, a.icon-button {
    width: 40px;
    height: 40px;
    display: grid;
    place-items: center;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-pill);
    text-decoration: none;
    font-size: 18px;
    line-height: 1;
    cursor: pointer;
    color: var(--text);
    backdrop-filter: blur(10px);
    -webkit-backdrop-filter: blur(10px);
    transition: transform 0.18s var(--ease-spring), background 0.2s, border-color 0.2s;
  }

  .icon-button:hover, a.icon-button:hover {
    background: var(--surface-2);
    border-color: var(--border-strong);
    transform: translateY(-1px) scale(1.05);
  }

  .subtle-button { opacity: 0.95; }

  .modal-overlay {
    position: fixed;
    inset: 0;
    background: rgba(4, 7, 12, 0.66);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    display: flex;
    justify-content: center;
    align-items: center;
    z-index: 9999;
    animation: fadeIn 0.25s ease-out;
  }
  .modal-backdrop {
    position: absolute;
    inset: 0;
    background: transparent;
    border: none;
    cursor: pointer;
  }

  .modal-content {
    background: var(--surface-strong);
    padding: 28px 24px;
    border-radius: var(--r-xl);
    width: 90%;
    max-width: 400px;
    text-align: center;
    box-shadow: var(--shadow-lg);
    animation: slideIn 0.35s var(--ease-out);
    border: 1px solid var(--border-strong);
    color: var(--text);
    backdrop-filter: blur(20px) saturate(140%);
    -webkit-backdrop-filter: blur(20px) saturate(140%);
    position: relative;
    z-index: 1;
  }
  .modal-content :global(h2) { font-family: var(--font-display); }

  .close-btn {
    position: absolute;
    top: 12px;
    right: 12px;
    width: 32px;
    height: 32px;
    display: grid;
    place-items: center;
    font-size: 13px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-pill);
    cursor: pointer;
    transition: background 0.2s, border-color 0.2s;
  }
  .close-btn:hover { background: rgba(251, 90, 90, 0.16); border-color: rgba(251, 90, 90, 0.4); }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes slideIn {
    from { transform: translateY(-20px); }
    to { transform: translateY(0); }
  }

  .next-puzzle-button {
    margin-top: 12px;
    background: var(--brand-grad);
    color: #06210f;
    font-family: var(--font-display);
    font-weight: 700;
    border: none;
    padding: 13px 28px;
    border-radius: var(--r-md);
    font-size: 1rem;
    cursor: pointer;
    box-shadow: var(--glow-brand);
    transition: transform 0.16s var(--ease-spring), filter 0.2s;
  }
  .next-puzzle-button:hover { transform: translateY(-2px); filter: brightness(1.05); }
  .next-puzzle-button:active { transform: scale(0.97); }

  .wager-ui {
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  position: fixed;
  bottom: 230px; /* sits above the action buttons (which clear the keyboard) */
  left: 50%;
  transform: translateX(-50%);
  width: calc(100% - 24px);
  max-width: 360px;
  padding: 10px 14px;
  border-radius: var(--r-lg);

  background: var(--surface-strong);
  border: 1px solid var(--border-strong);
  box-shadow: var(--shadow-lg);
  backdrop-filter: blur(14px);

  gap: 8px;
  z-index: 1003; /* always in front */
}

.wager-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  width: 100%;
}

.wager-label {
  font-family: var(--font-ui);
  font-size: 0.62rem;
  font-weight: 600;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--text-faint);
  text-align: center;
  width: 70px;
}
.wager-amount { color: #fcd34d; }

.wager-amount {
  font-size: 1rem;
  font-weight: bold;
  display: block;
}

.wager-slider {
  flex: 1;
  max-width: 260px; /* ✅ Long enough for precision */
  height: 10px;
  background: linear-gradient(90deg, limegreen 0%, #a8e063 100%);
  border-radius: 6px;
  outline: none;
  cursor: pointer;
  -webkit-appearance: none;
  appearance: none;
  touch-action: pan-y;
  -webkit-tap-highlight-color: transparent;
}

/* ✅ Precision Thumb Styling */
.wager-slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  width: 22px;
  height: 22px;
  background-color: limegreen;
  border: 2px solid white;
  border-radius: 50%;
  box-shadow: 0 0 6px rgba(0, 255, 0, 0.8);
  transition: transform 0.1s ease;
}
.wager-slider::-webkit-slider-thumb:hover {
  transform: scale(1.1);
}

.wager-slider::-moz-range-thumb {
  width: 22px;
  height: 22px;
  background-color: limegreen;
  border: 2px solid white;
  border-radius: 50%;
  box-shadow: 0 0 6px rgba(0, 255, 0, 0.8);
  cursor: pointer;
  transition: transform 0.1s ease;
}
.wager-slider::-moz-range-thumb:hover {
  transform: scale(1.1);
}
.wager-slider:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

:global(body.dark-mode) .wager-label {
  color: white;
}

:global(body.dark-mode) .wager-ui {
  background: rgba(255, 255, 255, 0.1);
  border: 2px solid rgba(255, 255, 255, 0.3);
  box-shadow: 0 4px 12px rgba(0, 255, 0, 0.2);
}

.subcategory-hint {
  font-size: 1rem;
  font-style: italic;
  color: #999;
  margin-bottom: 12px;
}




</style>