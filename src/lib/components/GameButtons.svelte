<script>
  import {
    confirmPurchase,
    selectHint,
    selectExtraGuess,
    enterGuessMode,
    submitGuess,
    deleteGuessLetter
  } from '$lib/stores/GameStore.js';
  import { gameStore } from '$lib/stores/GameStore.js';

  // Helper: returns an array of editable indices in guess mode.
  // An index is editable if:
  //  - The character is not a space.
  //  - It is not already locked in purchasedLetters.
  function getEditableIndices(state) {
    const indices = [];
    const phrase = state.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if (state.purchasedLetters[i] === phrase[i]) continue;
      indices.push(i);
    }
    return indices;
  }

  // Reactive: Determine if every editable slot is filled with a guess.
  $: guessComplete = $gameStore.gameState === 'guess_mode' && (() => {
    const phrase = $gameStore.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      // Skip spaces and indices already locked in purchasedLetters.
      if (phrase[i] === ' ') continue;
      if ($gameStore.purchasedLetters[i] === phrase[i]) continue;
      // Immediately return false if an editable slot is missing a guess.
      if (!$gameStore.guessedLetters[i]) return false;
    }
    return true;
  })();
</script>

<div class="game-buttons">
  <!-- Primary Actions -->
  <div class="primary-buttons">
    <!-- Enter Button: Confirm purchase or submit guess -->
    <button
      on:click={(e) => {
        if ($gameStore.gameState === 'guess_mode') {
          if (guessComplete) {
            submitGuess();
          } else {
            console.log("Not all guess slots are filled.");
          }
        } else {
          confirmPurchase();
        }
        e.currentTarget.blur();
      }}
      class="{ ($gameStore.gameState === 'guess_mode' && guessComplete) || $gameStore.gameState === 'purchase_pending' ? 'submit-ready' : '' }"
    >
      Enter { $gameStore.gameState === 'guess_mode' ? "(Submit Guess)" : "(Confirm Purchase)" }
    </button>
    
    <!-- Guess Mode Toggle -->
    <button 
      on:click={(e) => { enterGuessMode(); e.currentTarget.blur(); }}
      class:active-guess={$gameStore.gameState === 'guess_mode'}
    >
      Guess (Enter Guess Mode)
    </button>
        
    <!-- Hint Purchase -->
    <button
      on:click={(e) => { selectHint(); e.currentTarget.blur(); }}
      class="{$gameStore.selectedPurchase?.type === 'hint' && $gameStore.gameState === 'purchase_pending' ? 'pending' : ''}"
    >
      Hint ($150)
    </button>
    
    <!-- Extra Guess Purchase -->
    <button
      on:click={(e) => { selectExtraGuess(); e.currentTarget.blur(); }}
      class="{$gameStore.selectedPurchase?.type === 'extra_guess' && $gameStore.gameState === 'purchase_pending' ? 'pending' : ''}"
    >
      Extra Guess ($150)
    </button>
    
    <!-- Delete (only in guess mode) -->
    <button
      on:click={(e) => { if ($gameStore.gameState === 'guess_mode') { deleteGuessLetter(); } e.currentTarget.blur(); }}
    >
      Delete
    </button>
  </div>
    
  <!-- Utility Buttons -->
  <div class="utility-buttons">
    <button on:click={(e) => e.currentTarget.blur()}>How to Play</button>
    <button on:click={(e) => e.currentTarget.blur()}>Settings</button>
  </div>
</div>
    
<style>
  button:focus {
    outline: none;
  }
    
  .game-buttons {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1em;
  }
    
  .primary-buttons,
  .secondary-buttons,
  .utility-buttons {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
    justify-content: center;
  }
    
  button {
    padding: 10px 15px;
    font-size: 16px;
    border: 1px solid #333;
    background-color: #f0f0f0;
    cursor: pointer;
  }
    
  button:hover {
    background-color: #ddd;
  }
    
  .submit-ready {
    background-color: green !important;
    color: white !important;
  }
    
  button.pending {
    background-color: blue !important;
    color: white !important;
  }
  
  button.active-guess {
    background-color: orange !important;
    color: white !important;
  }
</style>
