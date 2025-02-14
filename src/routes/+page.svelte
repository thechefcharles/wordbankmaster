<script>
  import Keyboard from '../components/Keyboard.svelte';
  import PhraseDisplay from '../components/PhraseDisplay.svelte';
  import { gameStore, actions } from '../stores/gameStore';
  import { get } from 'svelte/store';
  console.log("Current Phrase:", get(gameStore).currentPhrase);
  console.log("Correct Positions:", get(gameStore).correctPositions);


$: console.log("Pending Purchase:", get(gameStore).pendingPurchase);

</script>

<main>
  <h1>WordBankMaster</h1>

<!-- ✅ Display Bankroll as Whole Dollars -->
<p class="bankroll">Bankroll: <strong>
  {new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 0, maximumFractionDigits: 0 }).format($gameStore.bankroll)}
</strong></p>

  <!-- ✅ Display Phrase -->
  <PhraseDisplay />

  <!-- ✅ Display Guesses Remaining -->
  <p class="guesses">Guesses Remaining: <strong>{$gameStore.guesses}</strong></p>

  <!-- ✅ Show Win/Loss Messages -->
  {#if $gameStore.winState}
    <p class="win-message">🎉 You Won! 🎉</p>
    <button class="reset-btn" on:click={actions.resetGame}>Restart Game</button>
  {:else if $gameStore.lossState}
    <p class="loss-message">😞 You Lost! Try Again!</p>
    <button class="reset-btn" on:click={actions.resetGame}>Restart Game</button>
  {/if}

  <!-- ✅ Disable Keyboard if the Player Wins -->
  {#if !$gameStore.winState && !$gameStore.lossState}
    <Keyboard />
  {/if}
  {#if $gameStore.lossState}
  <div class="game-over-banner">
    <h2>Game Over</h2>
    <p>You're out of guesses and don't have enough bankroll to continue!</p>
    <button on:click={restartGame}>Try Again</button>
  </div>
{/if}

</main>

<!-- ✅ Styles -->
<style>
  main {
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 15px;
    margin-top: 20px;
  }

  .bankroll, .guesses {
    font-size: 1.2em;
    font-weight: bold;
  }

  .win-message {
    color: green;
    font-size: 22px;
    font-weight: bold;
  }

  .loss-message {
    color: red;
    font-size: 22px;
    font-weight: bold;
  }

  /* ✅ Reset Button */
  .reset-btn {
    background-color: darkblue;
    color: white;
    padding: 12px 20px;
    border: none;
    border-radius: 5px;
    cursor: pointer;
    font-size: 20px;
    margin-top: 20px;
    font-weight: bold;
  }

  .reset-btn:hover {
    background-color: navy;
  }

  .game-over-banner {
    position: fixed;
    top: 30%;
    left: 50%;
    transform: translate(-50%, -50%);
    background: red;
    color: white;
    padding: 20px;
    text-align: center;
    border-radius: 10px;
}

.game-over-banner button {
    background: white;
    color: red;
    border: none;
    padding: 10px 15px;
    font-size: 18px;
    cursor: pointer;
    margin-top: 10px;
    border-radius: 5px;
}

.game-over-banner button:hover {
    background: darkred;
    color: white;
}

</style>
