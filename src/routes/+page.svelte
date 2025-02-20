<!-- +page.svelte -->
<svelte:head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
  <link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@700&display=swap" rel="stylesheet">
</svelte:head>

<script>
  import { onMount } from 'svelte';
  import { browser } from '$app/environment'; // For browser-only document access
  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import { gameStore, fetchRandomGame } from '$lib/stores/GameStore.js';
  import FlipDigit from '$lib/components/FlipDigit.svelte';

  onMount(() => {
    document.body.classList.add('dark-mode');
  });

  

  // Reactive bankroll value from your store
  $: bankroll = $gameStore.bankroll || 0;
  // Split the bankroll into individual digits
  $: digits = String(bankroll).split('');
  // Keep a reactive local reference to the game store
  $: currentGame = $gameStore;

  // On mount, fetch a random puzzle
  onMount(() => {
    fetchRandomGame();
  });

  // Toggle the "guess-mode" class on the document body based on game state
  $: if (browser) {
    if (currentGame.gameState === 'guess_mode') {
      document.body.classList.add('guess-mode');
    } else {
      document.body.classList.remove('guess-mode');
    }
  }
</script>

<main>
  <!-- Logo -->
  <div class="logo-container">
    <img src="/WordBank.png" alt="WordBank Logo" class="wordbank-logo" />
  </div>

  <!-- Category Display -->
  <p class="category">{currentGame.category} 🌍</p>

  <!-- Phrase Display Section -->
  <section class="phrase-section">
    <PhraseDisplay />
  </section>

  <!-- Resource Stats (Bankroll) -->
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

  <!-- Keyboard Section -->
  <section class="keyboard-section">
    <Keyboard />
  </section>

  <!-- Win/Loss Banner -->
  {#if currentGame.gameState === "won"}
    <div class="banner win">Winner!</div>
  {:else if currentGame.gameState === "lost"}
    <div class="banner lose">Bankrupt!</div>
  {/if}

  <!-- Game Buttons Section -->
  <section class="buttons-section">
    <GameButtons />
  </section>

  <!-- Optional Reset Button (Hidden) -->
  <button class="reset-button hidden" on:click={fetchRandomGame}>
    Reset Game
  </button>
</main>

<style>
  /* Main container styling */
  main {
    max-width: 600px;
    margin: 0 auto;
    text-align: center;
    font-family: sans-serif;
    padding: 10px;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  /* Category text styling */
  .category {
    font-size: 1.2rem;
    margin-top: -150px;
    margin-bottom: 0;
    font-weight: bold;
  }

  /* Keyboard section styling */
  .keyboard-section {
    width: 100%;
    padding: 5px;
  }

  /* Hide reset button */
  .reset-button.hidden {
    display: none;
  }

  /* Bankroll container and box styling */
  .bankroll-container {
    display: flex;
    justify-content: center;
    align-items: center;
    width: 100%;
    margin: 10px auto 0;
  }
  
  .bankroll-box {
    padding: 5px 10px;             /* Reduced padding */
    font-size: 1.5rem;             /* Smaller font size */
    font-family: 'Orbitron', sans-serif; /* Bold digital font */
    color: #fff;
    background: linear-gradient(45deg, #2e7d32, #66bb6a);
    border: 3px solid #1b5e20;
    border-radius: 8px;
    text-align: center;
    box-shadow: inset 0 0 10px rgba(0, 0, 0, 0.5);
    display: inline-flex;
    justify-content: center;
    align-items: center;
  }
  
  .currency {
    margin-right: 4px;
  }

  /* Logo styling */
  .wordbank-logo {
    width: 380px;
    height: auto;
    display: block;
    margin-bottom: -60px;
    margin-top: -50px;
    padding-bottom: 0;
  }
  
  .logo-container {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-top: -50px;
    margin-bottom: 0;
  }

  /* Global overrides for touch and overflow */
  :global(html, body) {
    overflow-x: hidden;
    touch-action: manipulation;
  }

  /* Win Banner Animations */
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
    font-size: 3rem;
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

  /* Game Over Banner Animations */
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
    font-size: 3rem;
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

</style>
