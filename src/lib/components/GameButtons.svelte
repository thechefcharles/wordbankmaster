<script>
    /**
     * GameButtons.svelte
     *
     * Renders the primary, secondary, and utility buttons for BankWord.
     *
     * Primary Buttons:
     *  - Enter (Confirm Purchase or Submit Guess)
     *  - Guess (Toggle Guess Mode)
     *  - Hint
     *  - Extra Guess
     *  - Delete
     *
     * Secondary Buttons:
     *  - Back (Exit Guess Mode)
     *
     * Utility Buttons:
     *  - Rules/How to Play
     *  - Settings
     */
  
    import {
      confirmPurchase,
      selectHint,
      selectExtraGuess,
      enterGuessMode,
      submitGuess,
      deleteGuessLetter
    } from '$lib/stores/GameStore.js';
    import { gameStore } from '$lib/stores/GameStore.js';
  
    /**
     * guessComplete:
     * Determines if all editable slots in guess mode are filled.
     */
    $: guessComplete = (() => {
      if ($gameStore.gameState !== 'guess_mode') return false;
      const editableIndices = [];
      for (let i = 0; i < $gameStore.currentPhrase.length; i++) {
        const char = $gameStore.currentPhrase[i];
        if (char === ' ') continue;
        if ($gameStore.purchasedLetters.includes(char)) continue;
        editableIndices.push(i);
      }
      // If any editable slot is empty, guess is incomplete
      for (const idx of editableIndices) {
        if ($gameStore.guessInput[idx] === '') return false;
      }
      return true;
    })();
  </script>
  
  <div class="game-buttons">
    <!-- Primary Actions -->
    <div class="primary-buttons">
      <!-- Enter Button: Confirm purchase or submit guess -->
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
        class="{ ($gameStore.gameState === 'guess_mode' && guessComplete) || $gameStore.gameState === 'purchase_pending' ? 'submit-ready' : '' }"
      >
        Enter { $gameStore.gameState === 'guess_mode' ? "(Submit Guess)" : "(Confirm Purchase)" }
      </button>
  
      <!-- Guess Mode Toggle -->
      <button on:click={enterGuessMode}>
        Guess (Enter Guess Mode)
      </button>
  
      <!-- Hint Purchase -->
      <button
        on:click={selectHint}
        class="{$gameStore.selectedPurchase && $gameStore.selectedPurchase.type === 'hint' && $gameStore.gameState === 'purchase_pending' ? 'pending' : ''}"
      >
        Hint ($150)
      </button>
  
      <!-- Extra Guess Purchase -->
      <button
        on:click={selectExtraGuess}
        class="{$gameStore.selectedPurchase && $gameStore.selectedPurchase.type === 'extra_guess' && $gameStore.gameState === 'purchase_pending' ? 'pending' : ''}"
      >
        Extra Guess ($150)
      </button>
  
      <!-- Delete (only relevant in guess mode) -->
      <button
        on:click={() => {
          if ($gameStore.gameState === 'guess_mode') {
            deleteGuessLetter();
          }
        }}
      >
        Delete
      </button>
    </div>
  
    <!-- Secondary Buttons -->
    <div class="secondary-buttons">
      <button>Back (Exit Guess Mode)</button>
    </div>
  
    <!-- Utility Buttons -->
    <div class="utility-buttons">
      <button>Rules/How to Play</button>
      <button>Settings</button>
    </div>
  </div>
  
  <style>
    /* Container for all game buttons */
    .game-buttons {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 1em;
    }
  
    /* Grouping for different button sets */
    .primary-buttons,
    .secondary-buttons,
    .utility-buttons {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      justify-content: center;
    }
  
    /* Base button styling */
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
  
    /* When guess is complete or a purchase is pending, turn the Enter button green */
    .submit-ready {
      background-color: green !important;
      color: white !important;
    }
  
    /* When a purchase option is selected (pending), turn it blue */
    button.pending {
      background-color: blue !important;
      color: white !important;
    }
  </style>
  