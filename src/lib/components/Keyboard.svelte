<script>
    import { gameStore, selectLetter, inputGuessLetter } from '$lib/stores/GameStore.js';
    
    const letterCosts = {
      Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
      A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
      Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
    };
  
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
  
  <p>✅ Keyboard is rendering...</p>
  
  <div class="keyboard">
    {#each Object.keys(letterCosts) as letter}
      <button 
        class="{($gameStore.selectedPurchase && $gameStore.selectedPurchase.type === 'letter' && $gameStore.selectedPurchase.value === letter && $gameStore.gameState === 'purchase_pending')
                 ? 'pending'
                 : $gameStore.purchasedLetters.includes(letter)
                    ? 'purchased'
                    : $gameStore.incorrectLetters.includes(letter)
                       ? 'incorrect'
                       : ''}"
        on:click={() => handleLetterClick(letter)}
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
    button.purchased {
      background-color: green;
      color: white;
      cursor: default;
    }
    button.pending {
      background-color: blue !important;
      color: white !important;
    }
    button.incorrect {
      background-color: red;
      color: white;
      cursor: default;
    }
    button:hover:not(.purchased, .pending, .incorrect) {
      background-color: lightgray;
    }
  </style>
  