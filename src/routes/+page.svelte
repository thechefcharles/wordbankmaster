<script>
    /**
     * +page.svelte
     *
     * Main page for BankWord.
     * Displays the header, category, phrase, keyboard, stats, win/loss banner,
     * game buttons, and a reset button.
     */
    import { gameStore, resetGame } from '$lib/stores/GameStore.js';
    import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
    import Keyboard from '$lib/components/Keyboard.svelte';
    import GameButtons from '$lib/components/GameButtons.svelte';
  
    // Format the bankroll as US dollars without cents
    $: formattedBankroll = new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format($gameStore.bankroll);
  </script>
  
  <main>
    <h1>WordBank</h1>
    
    <!-- Display category above the phrase -->
    <p class="category">Category: {$gameStore.category}</p>
  
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
      <p>Bankroll: {formattedBankroll}</p>
      <p>Guesses Remaining: {$gameStore.guessesRemaining}</p>
      <p>Game State: {$gameStore.gameState}</p>
    </section>
  
    <!-- Win/Loss Banner -->
    {#if $gameStore.gameState === "won"}
      <div class="banner win">Congratulations! You won!</div>
    {:else if $gameStore.gameState === "lost"}
      <div class="banner lose">Game Over</div>
    {/if}
  
    <!-- Game Buttons Section -->
    <section class="buttons-section">
      <GameButtons />
    </section>
  
    <!-- Reset Button (turns green when game is over or won) -->
    <button
      on:click={resetGame}
      class:reset-green={$gameStore.gameState === "won" || $gameStore.gameState === "lost"}
    >
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
    
    /* Category displayed right under header */
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
    
    button.reset-green {
      background-color: green !important;
      color: white !important;
      margin-top: 20px;
      padding: 10px 20px;
      font-size: 16px;
    }
  </style>
  