<!-- page.svelte -->
<svelte:head>
  <meta
    name="viewport"
    content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"
  />
</svelte:head>

<script>
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';  // ensures we only access 'document' in the browser
  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import { gameStore, fetchRandomGame } from '$lib/stores/GameStore.js';

  // Reactive variable for the store
  $: currentGame = $gameStore;

  // Fetch a random puzzle on mount
  onMount(() => {
    fetchRandomGame();
  });

  // Toggle .guess-mode on <body> if in the browser
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

  <!-- Phrase Display -->
  <section class="phrase-section">
    <PhraseDisplay />
  </section>

  <!-- Resource Stats (Bankroll, etc.) -->
  <section class="stats-section">
    <div class="bankroll-container">
      <p class="bankroll-box">$ {Math.floor(currentGame.bankroll)}</p>
    </div>
  </section>

  <!-- Keyboard Section -->
  <section class="keyboard-section">
    <Keyboard />
  </section>

  <!-- Win/Loss Banner -->
  {#if currentGame.gameState === "won"}
    <div class="banner win">Congratulations! You won!</div>
  {:else if currentGame.gameState === "lost"}
    <div class="banner lose">Bankrupt!</div>
  {/if}

  <!-- Game Buttons -->
  <section class="buttons-section">
    <GameButtons />
  </section>

  <!-- Hidden Reset Button (optional) -->
  <button class="reset-button hidden" on:click={fetchRandomGame}>
    Reset Game
  </button>
</main>

<style>
  /* Overall container */
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

  /* Category display */
  .category {
    font-size: 1.4rem;
    margin-top: -140px;
    margin-bottom: 0px;
    font-weight: bold;
  }

  /* Keyboard section wrapper */
  .keyboard-section {
    width: 100%;
    padding: 5px;
  }

  /* Hide Reset Game Button */
  .reset-button.hidden {
    display: none;
  }

  /* Bankroll styling */
  .bankroll-container {
    display: flex;
    justify-content: center;
    align-items: center;
    width: 100%;
    margin: 0 auto;
    margin-top: 30px;
  }
  .bankroll-box {
    padding: 10px 20px;
    font-size: 1.7rem;
    font-weight: bold;
    color: white;
    background-color: rgb(103, 208, 103);
    border-radius: 1px;
    text-align: center;
    display: inline-block;
    width: fit-content;
    margin: 0 auto;
  }

  /* Logo styling */
  .wordbank-logo {
    width: 380px;
    height: auto;
    display: block;
    margin-bottom: -50px;
    margin-top: -30px;
    padding-bottom: 0px;
  }
  .logo-container {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-top: -50px;
    margin-bottom: 0px;
  }

  :global(html, body) {
    overflow-x: hidden;
    touch-action: manipulation;
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
  font-size: 3rem; /* Make it massive */
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

</style>
