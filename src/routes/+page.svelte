<script>
  import { onMount, tick } from 'svelte';
  import { browser } from '$app/environment';
  import { supabase } from '$lib/supabaseClient';
  import { gameStore, fetchRandomGame } from '$lib/stores/GameStore.js';
  import { user, userProfile, fetchUserProfile, saveUserProfile } from '$lib/stores/userStore.js';
  import { saveGameToLocalStorage, loadGameFromLocalStorage, clearSavedGame } from '$lib/stores/localGameUtils.js';
  import { gameWasRestored } from '$lib/stores/GameStateFlags.js';
  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import FlipDigit from '$lib/components/FlipDigit.svelte';
  import Auth from '$lib/components/Auth.svelte';
  import { get } from 'svelte/store';

  export let data;

  let showHowToPlay = false;
  let darkMode = false;
  let wagerUIVisible = false;
  let sliderWagerAmount = 0;
  let sliderLocked = false;
  let showResultModal = false;
  let hasTriggeredModal = false;
  let hasInitialized = false;

  async function loadUserProfile(userId) {
    try {
      const { data: profile, error } = await fetchUserProfile(userId);
      if (error) {
        console.error("❌ Error fetching profile:", error.message);
        return null;
      }

      if (!profile) {
        console.warn(`⚠️ No profile found for user ID: ${userId}`);
        return null;
      }

      userProfile.set(profile);
      gameStore.update(state => ({
        ...state,
        bankroll: profile.current_bankroll ?? 1000
      }));

      console.log("✅ User profile loaded and bankroll initialized");
      return profile;

    } catch (err) {
      console.error("❌ Error loading user profile:", err.message);
      return null;
    }
  }

  onMount(async () => {
    try {
      const { data: { session }, error } = await supabase.auth.getSession();

      if (!session || error) {
        console.log("⛔ No user session found");
        return;
      }

      user.set(session.user);

      const profile = await loadUserProfile(session.user.id);

      if (profile?.current_bankroll !== undefined) {
        const currentBankroll = get(gameStore).bankroll;
        if (profile.current_bankroll !== currentBankroll) {
          await saveUserProfile({ ...profile, current_bankroll: currentBankroll });
          console.log("🔄 Synced bankroll to Supabase on refresh:", currentBankroll);
        }
      }

      const restored = loadGameFromLocalStorage();
      if (restored) {
        gameWasRestored.set(true);
        console.log("✅ Game restored from localStorage");
      } else {
        await fetchRandomGame();
        console.log("📦 Loaded new puzzle (no saved game)");
      }

      await tick(); // wait for reactivity to settle
      hasInitialized = true;

    } catch (err) {
      console.error("❌ Error during session/profile fetch:", err.message);
    }
  });

  $: if (data?.user) {
    user.set(data.user);
    loadUserProfile(data.user.id);
  }

  $: loggedIn = !!$user?.id;
  $: bankroll = $gameStore.bankroll || 0;
  $: digits = String(bankroll).split('');
  $: nextPuzzleAvailable = $gameStore.gameState === 'won' || $gameStore.gameState === 'lost';
  $: sliderLocked = $gameStore.gameState === 'guess_mode';

  // ✅ Reactive fetch only if not restored AND after init is done
  $: if (
    hasInitialized &&
    loggedIn &&
    $gameStore.currentPhrase === '' &&
    !$gameWasRestored
  ) {
    console.log("🧨 Reactive block fetching new puzzle");
    fetchRandomGame();
  }

  const applyDarkMode = () => {
    document.body.classList.toggle('dark-mode', darkMode);
  };

  const toggleDarkMode = () => {
    darkMode = !darkMode;
    localStorage.setItem('darkMode', darkMode);
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

  const removeButtonFocus = (event) => {
    if (event.target.tagName === 'BUTTON') event.target.blur();
  };

  const handleLogout = async () => {
    saveGameToLocalStorage();
    gameWasRestored.set(false);
    await supabase.auth.signOut();
    user.set(null);
    location.reload();
  };

  const handlePlayAgain = async () => {
    showResultModal = false;
    hasTriggeredModal = false;

    const newBankroll = 1000;
    const currentUser = get(user);

    if (!currentUser?.id) {
      console.warn("⚠️ No user found during Play Again.");
      return;
    }

    try {
      await saveUserProfile({ id: currentUser.id, current_bankroll: newBankroll });
      clearSavedGame();
      gameWasRestored.set(false);

      gameStore.set({
        bankroll: newBankroll,
        wagerAmount: 1,
        category: '',
        currentPhrase: '',
        gameState: 'default',
        purchasedLetters: [],
        guessedLetters: {},
        lockedLetters: {},
        incorrectLetters: [],
        selectedPurchase: null,
        shakenLetters: [],
        message: ''
      });

      await fetchRandomGame();
      console.log("🔁 Game successfully reset after loss.");
    } catch (err) {
      console.error("❌ Failed to reset game or update bankroll:", err.message);
    }
  };

  const handleNextPuzzle = async () => {
    showResultModal = false;
    hasTriggeredModal = false;

    const currentUser = get(user);
    const currentBankroll = get(gameStore).bankroll;

    if (currentUser?.id) {
      try {
        await saveUserProfile({ id: currentUser.id, current_bankroll: currentBankroll });
        clearSavedGame();
        gameWasRestored.set(false);

        gameStore.set({
          bankroll: currentBankroll,
          wagerAmount: 1,
          category: '',
          currentPhrase: '',
          gameState: 'default',
          purchasedLetters: [],
          guessedLetters: {},
          lockedLetters: {},
          incorrectLetters: [],
          selectedPurchase: null,
          shakenLetters: [],
          message: ''
        });

        await fetchRandomGame();
        console.log("🎯 Next puzzle loaded");
      } catch (err) {
        console.error("❌ Failed to load next puzzle:", err.message);
      }
    } else {
      console.warn("⚠️ No user found for next puzzle");
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
<!-- 🔹 Top Control Buttons -->
<div class="top-buttons">
  <!-- ❓ How to Play -->
  <button class="icon-button subtle-button" on:click={() => showHowToPlay = true}>
    ❓
  </button>

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
      <p>💰 Start with $1000. Use it wisely to buy letters, get hints, and guess the phrase!</p>

      <h3>🎯 Goal</h3>
      <p>Solve the phrase before running out of money!</p>

      <h3>🕹️ Gameplay</h3>
      <ul>
        <li>🔤 <b>Buy Letters:</b> Click or tap letters to purchase.</li>
        <li>⏎ <b>Confirm:</b> Press Enter to submit purchases or guesses.</li>
        <li>🔄 <b>Guess Mode:</b> Press Spacebar to toggle Guess Mode.</li>
        <li>💡 <b>Hint ($150):</b> Reveals one random letter in the phrase.</li>
        <li>🎟️ <b>Extra Guess ($150):</b> Buy another guess attempt.</li>
      </ul>

      <p><strong>Think smart, spend wisely, and guess like a pro! 🚀</strong></p>
    </div>
  </div>
{/if}

<main>
  {#if !loggedIn}
    <!-- 🔐 Login Screen -->
    <div class="auth-screen">
      <Auth />
    </div>
  {:else}
    <!-- ✅ GAME UI (Visible only when logged in) -->

    <!-- 🧠 Game Logo -->
    <div class="logo-container">
      <img src="/1.png" alt="WordBank Logo" class="wordbank-logo" />
    </div>

    <!-- 🌍 Category Display -->
    <p class="category">{$gameStore.category} 🌍</p>

    <!-- 🔤 Phrase Display -->
    <section class="phrase-section">
      <PhraseDisplay on:revealComplete={onPhraseRevealComplete} />
    </section>

    <!-- 💰 Bankroll Display -->
    <section class="stats-section">
      <div class="bankroll-container">
        <div class="bankroll-box">
          <span class="currency">$</span>
          {#each digits as d}
            <FlipDigit digit={+d} />
          {/each}
        </div>
      </div>
    </section>

    <!-- 🎚️ Wager UI -->
    {#if wagerUIVisible}
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
        disabled={$gameStore.gameState === 'won' || $gameStore.gameState === 'lost'}
        on:setWagerUIVisible={(e) => wagerUIVisible = e.detail}
        on:setSliderWagerAmount={(e) => sliderWagerAmount = e.detail}
      />
    </section>

    <!-- ⌨️ Keyboard Section -->
    <section class="keyboard-section">
      <Keyboard
        disabled={$gameStore.gameState === 'won' || $gameStore.gameState === 'lost'}
        on:letterSelected={() => {
          if ($gameStore.gameState !== 'guess_mode') {
            wagerUIVisible = false;
          }
        }}
              />
    </section>

    <!-- 🏆 Game Outcome Banner -->
    {#if $gameStore.gameState === "won"}
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
    font-family: 'Orbitron', sans-serif;
    padding: 8px;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .category {
    font-size: .8rem;
    margin-top: -140px;
    margin-bottom: -20px;
    font-weight: bold;
  }

  .phrase-section,
  .stats-section,
  .keyboard-section,
  .buttons-section {
    width: 100%;
    padding: 0px;
  }

  .reset-button.hidden {
    display: none;
  }

  .bankroll-container {
  position: fixed;
  bottom: 320px; /* adjust this as needed to sit above the Solve button */
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 1000;
}


.bankroll-box {
  padding: 3px 40px;
  font-size: 0.4rem;
  font-family: 'Orbitron', sans-serif;
  color: #fff;
  background: linear-gradient(180deg, #d1cdcd, #858484);
  border: 3px solid rgba(255, 255, 255, 0.4);
  border-radius: 12px;
  text-align: center;
  box-shadow:
    inset 2px 2px 6px rgba(255, 255, 255, 0.2),
    3px 3px 8px rgba(0, 0, 0, 0.742),
    5px 5px 12px rgba(0, 0, 0, 0.5),
    0 0 8px rgba(245, 246, 245, 0.5);
  display: inline-flex;
  justify-content: center;
  align-items: center;
  letter-spacing: 1.5px;
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
  font-size: 1.0rem;
  margin-right: 6px;
  font-weight: bold;
  color: rgba(255, 255, 255, 0.8);
  text-shadow: 0 0 5px rgba(255, 255, 255, 0.5);
}

@keyframes bankrollGlow {
  0%   { box-shadow: 0 0 8px rgba(245, 246, 245, 0.5); }
  50%  { box-shadow: 0 0 12px rgba(242, 243, 242, 0.7); }
  100% { box-shadow: 0 0 8px rgba(239, 241, 239, 0.5); }
}

  .wordbank-logo {
    width: 380px;
    height: auto;
    display: block;
    margin: -50px auto -60px;
    padding-bottom: 0;
    align-self: center;
  }

  .logo-container {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-top: -30px;
    margin-bottom: 0;
  }

  .bankroll-game-buttons-container {
    position: fixed;
    bottom: 160px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 12px 18px;
    border-radius: 10px;
    z-index: 1000;
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

  .banner.win {
    font-size: 2rem;
    font-weight: 600;
    color: limegreen;
    text-transform: uppercase;
    background: linear-gradient(45deg, green, limegreen);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    text-align: center;
    padding: 20px;
    border: 5px solid limegreen;
    border-radius: 10px;
    animation: winPulse 1.5s infinite, winFlash 0.5s infinite;
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
    font-size: 2rem;
    font-weight: 600;
    color: red;
    text-transform: uppercase;
    background: linear-gradient(45deg, red, black);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    text-align: center;
    padding: 20px;
    border: 5px solid red;
    border-radius: 10px;
    animation: gameOverPulse 1.5s infinite, gameOverFlash 0.5s infinite;
  }

  :global(body.dark-mode) {
    background: #222;
    color: white;
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
    left: 12px;
    right: 12px;
    display: flex;
    justify-content: space-between;
    z-index: 1000;
  }

  .icon-button {
    background: transparent;
    border: none;
    font-size: 20px;
    cursor: pointer;
    color: rgba(255, 255, 255, 0.75);
    transition: color 0.3s ease, transform 0.2s ease, opacity 0.3s ease;
  }

  .subtle-button {
    opacity: 0.5;
  }

  .subtle-button:hover {
    opacity: 1;
    transform: scale(1.15);
  }

  .modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background: rgba(0, 0, 0, 0.3); /* 🌘 Semi-transparent black */
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 9999;
  /* Removed blur so puzzle stays sharp */
}

  .modal-content {
    background: white;
    padding: 20px;
    border-radius: 10px;
    width: 90%;
    max-width: 400px;
    text-align: center;
    box-shadow: 0 4px 10px rgba(0, 0, 0, 0.2);
    animation: slideIn 0.3s ease-out;
    border: 3px solid #007bff;
    color: black;
    position: relative;
  }

  :global(body.dark-mode) .modal-content {
    background: linear-gradient(135deg, #222, #333);
    border: 3px solid limegreen;
    color: white;
    box-shadow: 0 4px 10px rgba(0, 255, 0, 0.3);
  }

  .close-btn:hover {
    background: darkred;
  }

  .modal-title {
    font-size: 24px;
    font-weight: bold;
    color: #007bff;
    text-transform: uppercase;
    text-shadow: 0 0 5px rgba(0, 0, 0, 0.2);
  }

  .intro-text {
    font-size: 16px;
    color: #333;
    margin-bottom: 10px;
  }

  .modal-list {
    list-style-type: none;
    padding: 0;
    text-align: left;
  }

  .modal-list li {
    font-size: 16px;
    background: rgba(0, 0, 0, 0.05);
    padding: 8px;
    margin-bottom: 5px;
    border-radius: 5px;
    text-shadow: none;
  }

  :global(body.dark-mode) .modal-list li {
    background: rgba(255, 255, 255, 0.1);
  }

  .modal-footer {
    font-size: 14px;
    font-weight: bold;
    color: black;
    padding: 10px;
    text-shadow: none;
  }

  :global(body.dark-mode) .modal-footer {
    color: white;
    text-shadow: 0 0 5px rgba(255, 255, 255, 0.4);
  }

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
    background-color: limegreen;
    color: white;
    font-weight: bold;
    border: none;
    padding: 12px 24px;
    border-radius: 8px;
    font-size: 1rem;
    cursor: pointer;
    animation: pulse 1s infinite alternate;
  }

  @keyframes pulse {
    0% { transform: scale(1); }
    100% { transform: scale(1.08); }
  }

  .next-puzzle-button:hover {
    background-color: green;
  }

  .wager-ui {
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  position: fixed;
  bottom: 245px;
  left: 50%;
  transform: translateX(-50%);
  width: 100%;
  max-width: 360px;
  padding: 6px 10px;
  border-radius: 10px;

  /* 🔧 NEW: Light mode border and shadow */
  background: rgba(255, 255, 255, 0.9);
  border: 2px solid #ccc;
  box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);

  gap: 8px;
  z-index: 999;
}

.wager-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  width: 100%;
}

.wager-label {
  font-family: 'Orbitron', sans-serif;
  font-size: 0.8rem;
  color: #222;
  text-align: center;
  width: 70px;
}

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



</style>