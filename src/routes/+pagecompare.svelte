<!-- +page.svelte -->
<svelte:head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
</svelte:head>

<script>
  import { onMount } from 'svelte';
  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import { gameStore, fetchRandomGame, enterGuessMode } from '$lib/stores/GameStore.js';
  import confetti from 'canvas-confetti';

  // Reactive: Watch for game win state
  $: if ($gameStore.gameState === "won") {
    launchConfetti();
  }
  function launchConfetti() {
    confetti({
      particleCount: 300,
      spread: 300,
      startVelocity: 200,
      scalar: 1.4,
      decay: 0.2,
      origin: { y: 0.6 }
    });
  }

  // Local reactive variable for the game state
  $: currentGame = $gameStore;

  onMount(() => {
    fetchRandomGame();
  });
</script>

<main>
  <!-- Logo and Category -->
  <div class="logo-container">
    <img src="/WordBank.png" alt="WordBank Logo" class="wordbank-logo" />
  </div>
  <p class="category">{currentGame.category} 🌍</p>

  <!-- Phrase Display -->
  <section class="phrase-section">
    <PhraseDisplay />
  </section>

  <!-- Resource Stats -->
  <section class="stats-section">
    <div class="bankroll-container">
      <p class="bankroll-box">$ {Math.floor(currentGame.bankroll)}</p>
    </div>
    <!-- Removed the extra "Guesses Remaining" text -->
  </section>

  <!-- Game Buttons Section (Buy Guess & Hint) -->
  <section class="buttons-section">
    <GameButtons />
  </section>

  <!-- New Guess Phrase Container (moved below the GameButtons and above the Keyboard) -->
  <div class="guess-phrase-container">
    <button class="guess-phrase-button" on:click={enterGuessMode}>
      Guess Phrase
    </button>
    <div class="guesses-box">
      {currentGame.guessesRemaining}
    </div>
  </div>

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

  <button class="reset-button hidden" on:click={fetchRandomGame}>
    Reset Game
  </button>
</main>

<style>
  /* Logo */
  .logo-container {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-bottom: -50px;
    margin-top: -30px;
  }
  .wordbank-logo {
    width: 380px;
    height: auto;
    display: block;
    margin: 0 auto;
    padding-bottom: 0;
  }

  /* Category */
  .category {
    font-size: 1.4rem;
    margin-top: -130px;
    margin-bottom: 0;
    font-weight: bold;
  }

  /* Resource Stats */
  .stats-section {
    margin-top: 10px;
    margin-bottom: 5px;
    font-size: 1.2rem;
    font-weight: bold;
  }
  .bankroll-container {
    display: flex;
    justify-content: center;
    align-items: center;
    width: 100%;
    margin: 0 auto;
    padding-top: 5px;
  }
  .bankroll-box {
    padding: 10px 20px;
    font-size: 2rem;
    font-weight: bold;
    color: white;
    background-color: green;
    border-radius: 8px;
    text-align: center;
    display: inline-block;
    width: fit-content;
    margin: 0 auto;
  }

  /* New Guess Phrase Container */
  .guess-phrase-container {
    display: flex;
    flex-direction: column;
    align-items: center;
    margin-bottom: 20px;
  }
  .guess-phrase-button {
    background-color: orange;  /* Orange button */
    color: white;
    padding: 8px 12px;
    border: none;
    border-radius: 5px;
    cursor: pointer;
    font-size: 14px;
    transition: background-color 0.3s;
  }
  .guess-phrase-button:hover {
    background-color: darkorange;
  }
  .guesses-box {
    background-color: orange;
    color: white;
    padding: 8px 12px;
    border-radius: 5px;
    font-size: 16px;
    margin-top: 10px;
    min-width: 40px;
    text-align: center;
  }

  /* Keyboard Section */
  .keyboard-section {
    width: 100%;
    padding: 5px;
  }

  /* Other existing styles remain unchanged... */
</style>
