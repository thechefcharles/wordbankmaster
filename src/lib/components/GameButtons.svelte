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
  
    // Reactive block to compute if the guess is complete.
    $: guessComplete = (() => {
      if ($gameStore.gameState !== 'guess_mode') return false;
      // Build an array of editable indices: non-space and not locked by purchased letters.
      const editableIndices = [];
      for (let i = 0; i < $gameStore.currentPhrase.length; i++) {
        if ($gameStore.currentPhrase[i] === ' ') continue;
        if ($gameStore.purchasedLetters.includes($gameStore.currentPhrase[i])) continue;
        editableIndices.push(i);
      }
      // Check each editable index: if any are empty, the guess is not complete.
      for (const idx of editableIndices) {
        if ($gameStore.guessInput[idx] === '') return false;
      }
      return true;
    })();
  </script>
  
  <div class="game-buttons">
    <div class="primary-buttons">
      <button 
        on:click={() => {
          if ($gameStore.gameState === 'guess_mode') {
            if (guessComplete) {
              submitGuess();
            } else {
              console.log("Not all guess slots are filled.");
            }
          } else {
            confirmPurchase();
          }
        }}
        class="{ $gameStore.gameState === 'guess_mode' && guessComplete ? 'submit-ready' : '' }"
      >
        Enter { $gameStore.gameState === 'guess_mode' ? "(Submit Guess)" : "(Confirm Purchase)" }
      </button>
      <button on:click={() => {
        // Toggling guess mode: if already in guess mode, exit; otherwise, enter guess mode.
        enterGuessMode();
      }}>
        Guess (Enter Guess Mode)
      </button>
      <button 
        on:click={selectHint}
        class="{$gameStore.selectedPurchase && $gameStore.selectedPurchase.type === 'hint' && $gameStore.gameState === 'purchase_pending' ? 'pending' : ''}"
      >
        Hint ($150)
      </button>
      <button 
        on:click={selectExtraGuess}
        class="{$gameStore.selectedPurchase && $gameStore.selectedPurchase.type === 'extra_guess' && $gameStore.gameState === 'purchase_pending' ? 'pending' : ''}"
      >
        Extra Guess ($150)
      </button>
      <button on:click={() => {
        if ($gameStore.gameState === 'guess_mode') {
          deleteGuessLetter();
        }
      }}>
        Delete
      </button>
    </div>
    <div class="state-buttons">
      <button>Reset Game (New Game)</button>
      <button>Back (Exit Guess Mode)</button>
    </div>
    <div class="utility-buttons">
      <button>Rules/How to Play</button>
      <button>Settings</button>
    </div>
  </div>
  
  <style>
    .game-buttons {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 1em;
      margin: 20px 0;
    }
    .primary-buttons,
    .state-buttons,
    .utility-buttons {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
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
    /* When in guess mode and all slots are filled, the Enter button turns green */
    .submit-ready {
      background-color: green !important;
      color: white !important;
    }
    /* Existing styles for pending, etc. remain here */
    button.pending {
      background-color: blue !important;
      color: white !important;
    }
  </style>
  