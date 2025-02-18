<!-- page.svelte -->
<svelte:head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
</svelte:head>

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
  <p class="category">{currentGame.category} 🌍</p>

  <!-- Phrase Display -->
  <section class="phrase-section">
    <PhraseDisplay />
  </section>

  <!-- Resource Stats -->
  <section class="stats-section">
    <p class="bankroll">Bankroll: ${Math.floor(currentGame.bankroll)}</p>
    <p>Guesses Remaining: {currentGame.guessesRemaining}</p>
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

  <!-- Reset Button: Reload a new game -->
  <button on:click={fetchRandomGame}>
    Reset Game (New Game)
  </button>
</main>

<style>
/* Center everything better */
main {
  max-width: 600px;
  margin: 0 auto;
  text-align: center;
  font-family: sans-serif;
  padding: 15px; /* Reduced padding */
  display: flex;
  flex-direction: column;
  align-items: center;
}

/* Fix WordBank spacing */
h1 {
  margin-top: 20px; /* Move down slightly */
  margin-bottom: 5px;
  font-size: 2rem;
}

/* Category display */
.category {
  font-size: 1.4rem;
  margin-bottom: 10px;
  font-weight: bold;
}

/* Move Buy Guess & Hint buttons to avoid overlap */
.top-buttons {
  display: flex;
  justify-content: space-between;
  width: 100%;
  padding: 10px 15px;
}

.top-buttons button {
  flex: 1;
  margin: 0 5px;
  font-size: 14px;
}

/* Adjust bankroll and guesses position */
.stats-section {
  margin: 10px 0;
  font-size: 1.2rem;
  font-weight: bold;
}

/* PHRASE BOXES: Bigger & Tighter Spacing */
.phrase-container {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  width: 100%;
  max-width: 100%;
  gap: 2px; /* Minimized space between boxes */
}

/* Adjust letter box size */
.letter-box {
  width: min(60px, 7vw); /* Increased by 10px */
  height: min(60px, 7vw); /* Increased by 10px */
  font-size: min(26px, 4vw); /* Scale text */
}

/* KEYBOARD: Bigger Keys & No Space Between */
.keyboard-section {
  width: 100%;
  padding: 5px;
}

.keyboard-row {
  display: flex;
  justify-content: center;
  gap: 0px; /* No space between keys */
  flex-wrap: nowrap; /* Keep QWERTY layout */
}

/* Make keys larger while removing spacing */
.key {
  width: min(55px, 8vw); /* Slightly larger */
  height: min(55px, 8vw);
  font-size: min(18px, 3.5vw);
  margin: 0; /* Remove any extra margins */
  padding: 2px; /* Minimal padding */
}
</style>
