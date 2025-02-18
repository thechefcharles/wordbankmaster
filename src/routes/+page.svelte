<script>
  import { onMount } from 'svelte';
  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import { gameStore, fetchRandomGame } from '$lib/stores/GameStore.js';

  // Create a local reactive variable for the game state
  $: currentGame = $gameStore;

  onMount(() => {
    fetchRandomGame();
  });
</script>

<main>
  <h1>WordBank</h1>
  
  <!-- Use the local variable instead of $gameStore directly -->
  <p class="category">Category: {currentGame.category}</p>

  <!-- Phrase Display -->
  <section class="phrase-section">
    <PhraseDisplay />
  </section>

  <!-- Keyboard Section -->
  <section class="keyboard-section">
    <Keyboard />
  </section>

  <!-- Resource Stats -->
  <section class="stats-section">
    <p>Bankroll: {currentGame.bankroll}</p>
    <p>Guesses Remaining: {currentGame.guessesRemaining}</p>
    <p>Game State: {currentGame.gameState}</p>
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

  <!-- Reset Button: Reload a new game -->
  <button on:click={fetchRandomGame}>
    Reset Game (New Game)
  </button>
</main>

<style>
  main {
    max-width: 600px;
    margin: 0 auto;
    text-align: center;
    font-family: sans-serif;
    padding: 20px;
  }
  
  h1 {
    margin-bottom: 10px;
  }
  
  .category {
    font-size: 1.2em;
    margin-bottom: 20px;
  }
  
  section {
    margin-bottom: 20px;
  }
  
  .keyboard-section,
  .buttons-section {
    background-color: #f9f9f9;
    padding: 10px;
    border-radius: 4px;
    margin-bottom: 20px;
  }
  
  .banner {
    margin: 10px 0;
    padding: 10px;
    font-size: 1.5em;
  }
  
  .win {
    background-color: green;
    color: white;
  }
  
  .lose {
    background-color: red;
    color: white;
  }
  
  button {
    margin-top: 20px;
    padding: 10px 20px;
    font-size: 16px;
  }
  
  button.reset-green {
    background-color: green !important;
    color: white !important;
  }
</style>
