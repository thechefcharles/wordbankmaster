<script>
    import { gameStore, resetGame } from '$lib/stores/GameStore.js';
    import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
    import Keyboard from '$lib/components/Keyboard.svelte';
    import GameButtons from '$lib/components/GameButtons.svelte';
</script>

<main>
    <h1>BankWord</h1>
    <p>✅ +page.svelte is rendering...</p>
    
    <!-- Display the phrase -->
    <PhraseDisplay />
    
    <!-- Display the keyboard -->
    <Keyboard />
    
    <!-- Display resource stats -->
    <p>Bankroll: {$gameStore.bankroll}</p>
    <p>Guesses Remaining: {$gameStore.guessesRemaining}</p>
    <p>Game State: {$gameStore.gameState}</p>
    
    <!-- Display win/loss banner -->
    {#if $gameStore.gameState === "won"}
      <div class="banner win">Congratulations! You won!</div>
    {:else if $gameStore.gameState === "lost"}
      <div class="banner lose">Game Over</div>
    {/if}
    
    <!-- Game buttons -->
    <GameButtons />
    
    <!-- Reset Button (turns green when game is over or won) -->
    <button 
      on:click={resetGame} 
      class:reset-green={$gameStore.gameState === "won" || $gameStore.gameState === "lost"}
    >
      Reset Game (New Game)
    </button>
  </main>
  
  <style>
    .banner {
      text-align: center;
      font-size: 1.5em;
      margin: 10px 0;
      padding: 10px;
    }
    .win {
      color: white;
      background-color: green;
    }
    .lose {
      color: white;
      background-color: red;
    }
    button.reset-green {
      background-color: green !important;
      color: white !important;
    }
  </style>