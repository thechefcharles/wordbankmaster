<!-- +page.svelte -->
<svelte:head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
  <link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@700&display=swap" rel="stylesheet" />
</svelte:head>

<script>
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';
  import { supabase } from '$lib/supabaseClient';
  import { gameStore, fetchRandomGame } from '$lib/stores/GameStore.js';
  import { user } from '$lib/stores/userStore.js';

  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import FlipDigit from '$lib/components/FlipDigit.svelte';
  import Auth from '$lib/components/Auth.svelte';

  export let data;

  let showHowToPlay = false;
  let darkMode = false;
  let wagerUIVisible = false;
  let sliderWagerAmount = 0;
  let showResultModal = false;

  let hasTriggeredModal = false;

  $: if (data?.user) user.set(data.user);
  $: loggedIn = !!$user?.id;
  $: bankroll = $gameStore.bankroll || 0;
  $: digits = String(bankroll).split('');
  $: nextPuzzleAvailable = $gameStore.gameState === 'won' || $gameStore.gameState === 'lost';

  function applyDarkMode() {
    document.body.classList.toggle('dark-mode', darkMode);
  }

  function toggleDarkMode() {
    darkMode = !darkMode;
    localStorage.setItem('darkMode', darkMode);
    applyDarkMode();
  }

  onMount(() => {
    if (browser) {
      darkMode = localStorage.getItem('darkMode') === 'true';
      applyDarkMode();
    }
    if (loggedIn) fetchRandomGame();
    ['click', 'mousedown', 'touchstart'].forEach(event =>
      document.addEventListener(event, removeButtonFocus, true)
    );
  });

  function removeButtonFocus(event) {
    if (event.target.tagName === 'BUTTON') event.target.blur();
  }

  async function handleLogout() {
    await supabase.auth.signOut();
    user.set(null);
    location.reload();
  }

  function handlePlayAgain() {
    showResultModal = false;
    hasTriggeredModal = false;
    gameStore.update(state => ({ ...state, gameState: null }));
    fetchRandomGame();
  }

  function onPhraseRevealComplete() {
    if (!hasTriggeredModal && ['won', 'lost'].includes($gameStore.gameState)) {
      showResultModal = true;
      hasTriggeredModal = true;
    }
  }
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

    <!-- 🌍 Category Tag -->
    <p class="category">{$gameStore.category} 🌍</p>

<!-- 🔤 Phrase Display -->
<section class="phrase-section">
  <PhraseDisplay on:revealComplete={onPhraseRevealComplete} />
</section>
    <!-- 💰 Bankroll + 🎮 Game Buttons Container -->
    <div class="bankroll-game-buttons-container">
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

      <!-- 🎚️ Wager Slider -->
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
              bind:value={sliderWagerAmount}
              class="wager-slider"
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
          disabled={nextPuzzleAvailable}
          on:setWagerUIVisible={(e) => wagerUIVisible = e.detail}
          on:setSliderWagerAmount={(e) => sliderWagerAmount = e.detail}
        />
      </section>
    </div>

    <!-- ⌨️ Keyboard Section -->
    <section class="keyboard-section">
      <Keyboard
        disabled={nextPuzzleAvailable}
        on:letterSelected={() => wagerUIVisible = false}
      />
    </section>

    <!-- 🏆 Game Outcome Banner -->
    {#if $gameStore.gameState === "won"}
          <div class="banner win">Winner!</div>
      {#if !showResultModal}
        {@html ''} <!-- Modal will be triggered below -->
      {/if}
      {:else if $gameStore.gameState === "lost"}
            <div class="banner lose">Bankrupt!</div>
      {#if !showResultModal}
        {@html ''} <!-- Modal will be triggered below -->
      {/if}
    {/if}

    <!-- 🎯 Result Modal -->
    {#if showResultModal && ['won', 'lost'].includes($gameStore.gameState)}
    <div class="modal-overlay">
      <div class="modal-content">
        <h2>{$gameStore.gameState === 'won' ? '🎉 You Win!' : '💀 Game Over'}</h2>
        <p>{$gameStore.gameState === 'won'
          ? 'Great job! Want to try the next one?'
          : 'You ran out of cash. Want to try again?'}</p>
  
        <div style="margin-top: 16px;">
          <button class="next-puzzle-button" on:click={handlePlayAgain}>
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
    margin-top: -120px;
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

  .bankroll-box {
    padding: 10px 15px;
    font-size: 1.8rem;
    font-family: 'Orbitron', sans-serif;
    color: #fff;
    background: linear-gradient(180deg, #d1cdcd, #858484);
    border: 3px solid rgba(255, 255, 255, 0.4);
    border-radius: 12px;
    text-align: center;
    box-shadow: inset 2px 2px 6px rgba(255, 255, 255, 0.2), 3px 3px 8px rgba(0, 0, 0, 0.742), 5px 5px 12px rgba(0, 0, 0, 0.5);
    display: inline-flex;
    justify-content: center;
    align-items: center;
    letter-spacing: 1.5px;
    backdrop-filter: blur(5px);
    transition: transform 0.3s ease-in-out, box-shadow 0.3s ease-in-out;
    position: relative;
    top: 30px;
  }

  .bankroll-box:hover {
    transform: scale(1.05);
    box-shadow: 0 0 25px rgba(251, 251, 251, 0.8), 0 0 10px rgba(158, 158, 158, 0.7) inset;
  }

  .bankroll-box::before {
    content: "";
    position: absolute;
    width: 100%;
    height: 100%;
    top: 0;
    left: 0;
    border-radius: 12px;
    box-shadow: 0 0 12px rgba(251, 251, 251, 0.5) inset;
    opacity: 0.5;
    transition: opacity 0.3s ease-in-out;
  }

  @keyframes bankrollGlow {
    0% { box-shadow: 0 0 8px rgba(245, 246, 245, 0.5); }
    50% { box-shadow: 0 0 12px rgba(242, 243, 242, 0.7); }
    100% { box-shadow: 0 0 8px rgba(239, 241, 239, 0.5); }
  }

  .bankroll-box {
    animation: bankrollGlow 2.5s infinite alternate ease-in-out;
  }

  .currency {
    font-size: 1.5rem;
    margin-right: 6px;
    font-weight: bold;
    color: rgba(255, 255, 255, 0.8);
    text-shadow: 0 0 5px rgba(255, 255, 255, 0.5);
  }

  .bankroll-container {
    position: absolute;
    bottom: 170px;
    left: 50%;
    transform: translateX(-50%);
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
    margin-top: -10px;
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
    justify-content: center;
    align-items: center;
    width: 100%;
    max-width: 300px;
    padding: 8px 12px;
    border-radius: 10px;
    background: rgba(255, 255, 255, 0.1);
    flex-direction: column;
    gap: 6px;
    margin-bottom: 60px;
  }

  .wager-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
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
    display: block;
    font-size: 1rem;
    font-weight: bold;
  }

  .wager-slider {
    flex: 1;
    height: 8px;
    -webkit-appearance: none;
    appearance: none;
    background: #ccc;
    border-radius: 4px;
    outline: none;
  }

  .wager-slider::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 20px;
    height: 20px;
    background: limegreen;
    border-radius: 50%;
    cursor: pointer;
    box-shadow: 0 0 5px lime;
  }

  .wager-slider::-moz-range-thumb {
    width: 20px;
    height: 20px;
    background: limegreen;
    border-radius: 50%;
    cursor: pointer;
  }
</style>