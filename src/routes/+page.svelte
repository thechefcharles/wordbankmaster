<!-- page.svelte -->
<svelte:head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
</svelte:head>

<script>
  import { onMount } from 'svelte';
  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import { gameStore, fetchRandomGame } from '$lib/stores/GameStore.js';

  // Create a local reactive variable for the game state
  $: currentGame = $gameStore;

  // When component mounts, fetch a random puzzle from Supabase
  onMount(() => {
    fetchRandomGame();
  });
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
    <div class="banner lose">Game Over</div>
  {/if}

  <!-- Game Buttons Section -->
  <section class="buttons-section">
    <GameButtons />
  </section>

  <!-- Hidden Reset Button (if you still want it) -->
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

  /* Remove default focus outlines for buttons */
  .buy-guess-button:focus,
  .hint-button:focus,
  .guess-phrase-button:focus,
  .enter-button:focus,
  .key:focus {
    outline: none;
    box-shadow: none;
  }

  /* Force certain button colors on focus */
  .buy-guess-button:focus,
  .hint-button:focus {
    background-color: #007bff !important;
    color: white !important;
  }
  .guess-phrase-button:focus {
    background-color: orange !important;
    color: white !important;
  }

  :global(html, body) {
    overflow-x: hidden;
    touch-action: manipulation;
  }
</style>
