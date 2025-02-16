<!-- +page.svelte -->
<script>
    /**
     * +page.svelte
     *
     * This is the main page for BankWord.
     * It displays the current phrase (via PhraseDisplay), the on‑screen keyboard (Keyboard),
     * and the game action buttons (GameButtons). It also shows resource stats, a win/loss banner,
     * and a reset button that resets the game when clicked.
     */
    import { gameStore, resetGame } from '$lib/stores/GameStore.js';
    import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
    import Keyboard from '$lib/components/Keyboard.svelte';
    import GameButtons from '$lib/components/GameButtons.svelte';
  </script>
  
  <main>
    <h1>WordBank</h1>
    
    
    <!-- Display the current phrase -->
    <PhraseDisplay />
  
    <!-- Display the on-screen keyboard -->
    <Keyboard />
  
    <!-- Resource Stats -->
    <p>
        Bankroll: {new Intl.NumberFormat('en-US', { 
          style: 'currency', 
          currency: 'USD', 
          minimumFractionDigits: 0, 
          maximumFractionDigits: 0 
        }).format($gameStore.bankroll)}
      </p>
          <p>Guesses Remaining: {$gameStore.guessesRemaining}</p>
    <p>Game State: {$gameStore.gameState}</p>
    
    <!-- Win/Loss Banner -->
    {#if $gameStore.gameState === "won"}
      <div class="banner win">Congratulations! You won!</div>
    {:else if $gameStore.gameState === "lost"}
      <div class="banner lose">Game Over</div>
    {/if}
    
    <!-- Game Action Buttons -->
    <GameButtons />
    
    <!-- Reset Button: turns green if game is over (won or lost) -->
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
  