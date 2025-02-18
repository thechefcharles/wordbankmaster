<script>
  import { onMount } from 'svelte';
  import { 
    gameStore, 
    selectLetter, 
    inputGuessLetter, 
    confirmPurchase, 
    submitGuess, 
    deleteGuessLetter, 
    enterGuessMode 
  } from '$lib/stores/GameStore.js';

  // Define letter costs.
  const letterCosts = {
    Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
    A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
    Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
  };

  // QWERTY rows (no reordering).
  const row1 = ['Q','W','E','R','T','Y','U','I','O','P'];
  const row2 = ['A','S','D','F','G','H','J','K','L'];
  const row3 = ['Z','X','C','V','B','N','M'];

  function handleLetterClick(letter) {
    if ($gameStore.gameState === 'guess_mode') {
      inputGuessLetter(letter);
    } else {
      selectLetter(letter);
    }
  }

  // Reactive: check if all guess slots are filled
  $: guessComplete = $gameStore.gameState === 'guess_mode' && (() => {
    const phrase = $gameStore.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ' || $gameStore.purchasedLetters[i] === phrase[i]) continue;
      if (!$gameStore.guessedLetters[i]) return false;
    }
    return true;
  })();

  function handleKeyDown(event) {
    if (event.key === 'Enter') {
      event.preventDefault();
      if ($gameStore.gameState === 'guess_mode') {
        if (guessComplete) submitGuess();
        else console.log("Not all guess slots are filled.");
      } else {
        confirmPurchase();
      }
    } else if (event.key === 'Delete' || event.key === 'Backspace') {
      event.preventDefault();
      if ($gameStore.gameState === 'guess_mode') deleteGuessLetter();
    } else if (event.key === ' ' || event.code === 'Space') {
      event.preventDefault();
      enterGuessMode();
    } else {
      const key = event.key.toUpperCase();
      if (/^[A-Z]$/.test(key)) {
        event.preventDefault();
        handleLetterClick(key);
      }
    }
    // Remove focus from button or input elements
    document.activeElement.blur();
  }

  onMount(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  });
</script>

<!-- Keyboard Layout -->
<div class="keyboard-container">
  <!-- Row 1: Q-W-E-R-T-Y-U-I-O-P + Del -->
  <div class="keyboard-row">
    {#each row1 as letter}
      <button
        class="key {
          $gameStore.selectedPurchase?.type === 'letter' &&
          $gameStore.selectedPurchase.value === letter &&
          $gameStore.gameState === 'purchase_pending'
            ? 'pending'
            : $gameStore.lockedLetters?.[letter]
              ? 'purchased'
              : $gameStore.incorrectLetters.includes(letter)
                ? 'incorrect'
                : ''
        }"
        on:click={() => handleLetterClick(letter)}
      >
        <div class="letter">{letter}</div>
        <div class="price">${letterCosts[letter]}</div>
      </button>
    {/each}
    <button class="key delete" on:click={() => deleteGuessLetter()}>
      <div class="letter">Del</div>
    </button>
  </div>

  <!-- Row 2: A-S-D-F-G-H-J-K-L -->
  <div class="keyboard-row">
    {#each row2 as letter}
      <button
        class="key {
          $gameStore.selectedPurchase?.type === 'letter' &&
          $gameStore.selectedPurchase.value === letter &&
          $gameStore.gameState === 'purchase_pending'
            ? 'pending'
            : $gameStore.lockedLetters?.[letter]
              ? 'purchased'
              : $gameStore.incorrectLetters.includes(letter)
                ? 'incorrect'
                : ''
        }"
        on:click={() => handleLetterClick(letter)}
      >
        <div class="letter">{letter}</div>
        <div class="price">${letterCosts[letter]}</div>
      </button>
    {/each}
  </div>

  <!-- Row 3: "Guess" + Z-X-C-V-B-N-M + "Enter" -->
  <div class="keyboard-row">
    <button
      class="key guess-button { $gameStore.gameState === 'guess_mode' ? 'active-guess' : '' }"
      on:click={() => enterGuessMode()}
    >
      <div class="letter">Guess</div>
    </button>

    {#each row3 as letter}
      <button
        class="key {
          $gameStore.selectedPurchase?.type === 'letter' &&
          $gameStore.selectedPurchase.value === letter &&
          $gameStore.gameState === 'purchase_pending'
            ? 'pending'
            : $gameStore.lockedLetters?.[letter]
              ? 'purchased'
              : $gameStore.incorrectLetters.includes(letter)
                ? 'incorrect'
                : ''
        }"
        on:click={() => handleLetterClick(letter)}
      >
        <div class="letter">{letter}</div>
        <div class="price">${letterCosts[letter]}</div>
      </button>
    {/each}

    <button
      class="key enter-button {
        ($gameStore.gameState === 'guess_mode' && guessComplete) || 
        $gameStore.gameState === 'purchase_pending'
          ? 'submit-ready'
          : ''
      }"
      on:click={() => {
        if ($gameStore.gameState === 'guess_mode') {
          if (guessComplete) submitGuess();
          else console.log("Not all guess slots are filled.");
        } else {
          confirmPurchase();
        }
      }}
    >
      <div class="letter">Enter</div>
    </button>
  </div>
</div>

<style>
  /* Container for entire keyboard */
  .keyboard-container {
  position: absolute;
  bottom: 0;
  left: 50%;
  transform: translateX(-50%);
  width: 100%;
  background-color: #f9f9f9;
  padding: 10px;
  border-radius: 4px;
  display: flex;
  flex-direction: column;
  gap: 5px;
  justify-content: center;
  z-index: 1000;
}

  /* Each row: no wrap => QWERTY stays in same order */
  .keyboard-row {
    display: flex;
    flex-wrap: nowrap; /* so layout never changes order on narrow screens */
    gap: 2px;
    justify-content: center;
  }

  /* Common styling for each key */
  .key {
    width: 70px;
    height: 70px;
    font-size: 14px;
    font-weight: bold;
    border: 2px solid black;
    background-color: white;
    cursor: pointer;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 2px;
    box-sizing: border-box;
  }
  .key.delete {
    background-color: #ff6666;
    color: white;
  }

  .guess-button, .enter-button {
    background-color: #ddd;
    min-width: 60px;
  }

  .letter {
    line-height: 1;
  }
  .price {
    line-height: 1;
    font-size: 10px;
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
  .active-guess {
    background-color: orange !important;
    color: white !important;
  }
  .submit-ready {
    background-color: green !important;
    color: white !important;
  }

  /* Shrink keys for smaller screens (so entire row fits) */
  @media (max-width: 480px) {
    /* Decrease each key's width/height and font so row doesn't overflow */
    .key {
      width: 40px;
      height: 40px;
      font-size: 12px;
    }
    .guess-button,
    .enter-button {
      min-width: 50px; 
    }
  }
</style>
