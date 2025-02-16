<!-- Keyboard.svelte -->
<script>
    /**
     * Keyboard.svelte
     *
     * This component renders the on‑screen keyboard with all letters and their purchase prices.
     * When a letter is clicked, it performs one of two actions:
     * - In "guess_mode": calls inputGuessLetter(letter) to fill the next guess slot.
     * - In purchase mode: calls selectLetter(letter) to select a letter for purchase.
     *
     * The button styling changes based on the game store’s state:
     * - "pending": when a letter is selected for purchase.
     * - "purchased": when a letter has been successfully purchased.
     * - "incorrect": when a letter was purchased but is not in the phrase.
     */
  
    import { gameStore, selectLetter, inputGuessLetter } from '$lib/stores/GameStore.js';
  
    // Define the letter cost table.
    const letterCosts = {
      Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
      A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
      Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
    };
  
    /**
     * handleLetterClick(letter)
     * - In guess mode: calls inputGuessLetter(letter) so that the letter fills the next available slot.
     * - Otherwise: calls selectLetter(letter) to select it for purchase.
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
  
  <!-- Render the keyboard buttons -->
  <div class="keyboard">
    {#each Object.keys(letterCosts) as letter}
      <button
        on:click={() => handleLetterClick(letter)}
        class="{ 
          // If a letter is pending purchase in purchase mode...
          ($gameStore.selectedPurchase && 
           $gameStore.selectedPurchase.type === 'letter' && 
           $gameStore.selectedPurchase.value === letter && 
           $gameStore.gameState === 'purchase_pending')
             ? 'pending'
             // Otherwise, if the letter has been purchased, mark it as purchased.
             : $gameStore.purchasedLetters.includes(letter)
               ? 'purchased'
               // Otherwise, if it is marked as incorrect, show as incorrect.
               : $gameStore.incorrectLetters.includes(letter)
                 ? 'incorrect'
                 : ''
        }"
      >
        {letter} (${letterCosts[letter]})
      </button>
    {/each}
  </div>
  
  <style>
    .keyboard {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      justify-content: center;
      margin: 20px 0;
    }
    button {
      width: 50px;
      height: 50px;
      font-size: 18px;
      font-weight: bold;
      border: 2px solid black;
      background-color: white;
      cursor: pointer;
    }
    /* Purchased letters: green background */
    button.purchased {
      background-color: green;
      color: white;
      cursor: default;
    }
    /* Pending purchase: blue background */
    button.pending {
      background-color: blue !important;
      color: white !important;
    }
    /* Incorrect letters: red background */
    button.incorrect {
      background-color: red;
      color: white;
      cursor: default;
    }
    /* Hover effect for unstyled buttons */
    button:hover:not(.purchased, .pending, .incorrect) {
      background-color: lightgray;
    }
  </style>
  