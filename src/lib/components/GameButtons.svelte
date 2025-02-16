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
     * Utility Buttons:
     *  - How to Play
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
      // If any editable slot is empty, guess is incomplete.
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
        class="{$gameStore.selectedPurchase && $gameStore.selectedPurchase.type === 'hint' && $gameStore.gameState === 'purchase_pending' ? 'pending' : ''}"
      >
        Hint ($150)
      </button>
    
      <!-- Extra Guess Purchase -->
      <button
        on:click={(e) => { selectExtraGuess(); e.currentTarget.blur(); }}
        class="{$gameStore.selectedPurchase && $gameStore.selectedPurchase.type === 'extra_guess' && $gameStore.gameState === 'purchase_pending' ? 'pending' : ''}"
      >
        Extra Guess ($150)
      </button>
    
      <!-- Delete (only relevant in guess mode) -->
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
    /* Remove focus outlines from all buttons */
    button:focus {
      outline: none;
    }
    
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
  
    /* When in guess mode, the Guess button turns orange */
    button.active-guess {
      background-color: orange !important;
      color: white !important;
    }
  </style>
  