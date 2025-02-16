<script>
    /**
     * Keyboard.svelte
     *
     * Renders all letters with their costs. Clicking a letter:
     *  - In guess mode: inputs the letter into the guess.
     *  - Otherwise: selects the letter for purchase.
     */
    import { gameStore, selectLetter, inputGuessLetter } from '$lib/stores/GameStore.js';
  
    // Letter cost table
    const letterCosts = {
      Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
      A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
      Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
    };
  
    /**
     * handleLetterClick(letter):
     * - If in guess mode, calls inputGuessLetter.
     * - Otherwise, calls selectLetter to purchase.
     */
    function handleLetterClick(letter) {
      if ($gameStore.gameState === 'guess_mode') {
        console.log(`Guess mode: input letter ${letter}`);
        inputGuessLetter(letter);
      } else {
        console.log(`Purchase mode: select letter ${letter}`);
        selectLetter(letter);
      }
    }
  </script>
  
  <!-- Keyboard Heading (for debugging) -->
  <p>✅ Keyboard is rendering...</p>
  
  <div class="keyboard-container">
    <div class="keyboard">
      {#each Object.keys(letterCosts) as letter}
        <button
          on:click={() => handleLetterClick(letter)}
          class="{
            ($gameStore.selectedPurchase &&
             $gameStore.selectedPurchase.type === 'letter' &&
             $gameStore.selectedPurchase.value === letter &&
             $gameStore.gameState === 'purchase_pending')
              ? 'pending'
              : $gameStore.purchasedLetters.includes(letter)
                ? 'purchased'
                : $gameStore.incorrectLetters.includes(letter)
                  ? 'incorrect'
                  : ''
          }"
        >
          {letter} (${letterCosts[letter]})
        </button>
      {/each}
    </div>
  </div>
  
  <style>
    .keyboard-container {
      background-color: #f9f9f9;
      padding: 10px;
      border-radius: 4px;
      margin-bottom: 20px;
    }
  
    .keyboard {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: center;
    }
  
    /* Base button styling */
    button {
      width: 50px;
      height: 50px;
      font-size: 18px;
      font-weight: bold;
      border: 2px solid black;
      background-color: white;
      cursor: pointer;
    }
    /* Purchased letters: green */
    button.purchased {
      background-color: green;
      color: white;
      cursor: default;
    }
    /* Pending purchase: blue */
    button.pending {
      background-color: blue !important;
      color: white !important;
    }
    /* Incorrect letters: red */
    button.incorrect {
      background-color: red;
      color: white;
      cursor: default;
    }
    /* Hover effect for unstyled letters */
    button:hover:not(.purchased, .pending, .incorrect) {
      background-color: lightgray;
    }
  </style>
  