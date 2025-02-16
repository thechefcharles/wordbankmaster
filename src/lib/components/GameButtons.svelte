<!-- GameButtons.svelte -->
<script>
    /**
     * GameButtons.svelte
     *
     * This component renders the primary, state, and utility buttons for the game.
     * It supports the following actions:
     * - Confirming a purchase or submitting a guess (via the "Enter" button)
     * - Toggling guess mode (via the "Guess" button)
     * - Purchasing a hint or an extra guess
     * - Deleting a letter (only in guess mode)
     *
     * The "Enter" button turns green (via the "submit-ready" class) when either:
     * - In guess mode and all editable slots are filled, or
     * - When a purchase is pending.
     */
  
    // Import functions and reactive store from GameStore
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
     * Reactive block to determine if the current guess is complete.
     * This only applies when the game is in "guess_mode".
     *
     * It builds an array of "editable" indices (positions that are not spaces
     * and not locked by already purchased letters) and then checks that each of these
     * positions in the guessInput array is filled.
     */
    $: guessComplete = (() => {
      if ($gameStore.gameState !== 'guess_mode') return false;
      const editableIndices = [];
      for (let i = 0; i < $gameStore.currentPhrase.length; i++) {
        if ($gameStore.currentPhrase[i] === ' ') continue;
        if ($gameStore.purchasedLetters.includes($gameStore.currentPhrase[i])) continue;
        editableIndices.push(i);
      }
      for (const idx of editableIndices) {
        if ($gameStore.guessInput[idx] === '') return false;
      }
      return true;
    })();
  </script>
  
  <div class="game-buttons">
    <!-- Primary Action Buttons -->
    <div class="primary-buttons">
      <!-- Enter Button: Confirms purchase or submits guess -->
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
  
      <!-- Toggle Guess Mode Button -->
      <button on:click={enterGuessMode}>
        Guess (Enter Guess Mode)
      </button>
  
      <!-- Hint Purchase Button -->
      <button
        on:click={selectHint}
        class="{$gameStore.selectedPurchase && $gameStore.selectedPurchase.type === 'hint' && $gameStore.gameState === 'purchase_pending' ? 'pending' : ''}"
      >
        Hint ($150)
      </button>
  
      <!-- Extra Guess Purchase Button -->
      <button
        on:click={selectExtraGuess}
        class="{$gameStore.selectedPurchase && $gameStore.selectedPurchase.type === 'extra_guess' && $gameStore.gameState === 'purchase_pending' ? 'pending' : ''}"
      >
        Extra Guess ($150)
      </button>
  
      <!-- Delete Button (active only in guess mode) -->
      <button on:click={() => {
        if ($gameStore.gameState === 'guess_mode') deleteGuessLetter();
      }}>
        Delete
      </button>
    </div>
  
    <!-- State Buttons Section -->
    <div class="state-buttons">
      <!-- Back Button: Exits guess mode -->
      <button>Back (Exit Guess Mode)</button>
    </div>
  
    <!-- Utility Buttons Section -->
    <div class="utility-buttons">
      <button>Rules/How to Play</button>
      <button>Settings</button>
    </div>
  </div>
  
  <style>
    /* Container styling for all game buttons */
    .game-buttons {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 1em;
      margin: 20px 0;
    }
    /* Styling for grouped button sections */
    .primary-buttons,
    .state-buttons,
    .utility-buttons {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
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
    /* When ready to submit (either guess is complete or purchase pending), button turns green */
    .submit-ready {
      background-color: green !important;
      color: white !important;
    }
    /* When a purchase option is selected (pending state), style it with a blue background */
    button.pending {
      background-color: blue !important;
      color: white !important;
    }
  </style>
  