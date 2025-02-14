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

  <!-- ✅ Display Bankroll -->
  <p class="bankroll">Bankroll: <strong>{$gameStore.bankroll}</strong></p>

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
</style>
