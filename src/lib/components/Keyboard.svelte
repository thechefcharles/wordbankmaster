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

  // Define letter costs
  const letterCosts = {
    Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
    A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
    Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
  };

  // Rows for QWERTY layout
  const row1 = ['Q','W','E','R','T','Y','U','I','O','P'];
  const row2 = ['A','S','D','F','G','H','J','K','L'];
  const row3 = ['Z','X','C','V','B','N','M'];

  // Decide if we place a letter in guess mode or buy a letter in default mode
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
      // skip spaces & locked letters
      if (phrase[i] === ' ' || $gameStore.purchasedLetters[i] === phrase[i]) continue;
      // if a slot isn't filled, we're not complete
      if (!$gameStore.guessedLetters[i]) return false;
    }
    return true;
  })();

  // Listen to keyboard events (Enter, Backspace, Space, A–Z)
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
    // remove focus from any clicked element
    document.activeElement.blur();
  }

  // Hook up the keyboard events on mount
  onMount(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  });
</script>

<!-- Keyboard Layout -->
<div class="keyboard-container">
  <!-- Row 1: Q–P + Del -->
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

  <!-- Row 2: A–L -->
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

  <!-- Row 3: "Guess" + Z–M + "Enter" -->
  <div class="keyboard-row">

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

    <!-- Enter Button -->
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
  /* Keyboard Container */
  .keyboard-container {
    position: absolute;
    bottom: 20px;
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

  /* Each Row (QWERTY layout) */
  .keyboard-row {
    display: flex;
    flex-wrap: nowrap;
    gap: 2px;
    justify-content: center;
  }

  /* Key Styles */
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

  
  .enter-button {
  width: 140px;  /* Assuming other keys are 70px wide */
  display: flex;
  align-items: center;
  justify-content: center;
  text-align: center;
}

  .letter {
    line-height: 1;
  }
  .price {
    line-height: 1;
    font-size: 10px;
  }

  /* Button States */
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

  /* Media Query for small screens */
  @media (max-width: 480px) {
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

  /* ============================= */
  /* =========== DARK MODE ======= */
  /* ============================= */

  /* Make sure these are global: 
     so they apply when <body> has .dark-mode */
  :global(body.dark-mode) .keyboard-container {
    background-color: #333;
  }

  :global(body.dark-mode) .key {
    background-color: #444;
    color: white;
    border-color: #777;
  }

  :global(body.dark-mode) .key.delete {
    background-color: #cc6666; /* slightly darker red */
  }

  :global(body.dark-mode) .guess-button,
  :global(body.dark-mode) .enter-button {
    background-color: #555;
  }

  :global(body.dark-mode) .letter {
    color: white;
  }

  :global(body.dark-mode) .price {
    color: #ccc;
  }

  :global(body.dark-mode) button.purchased {
    background-color: #228B22; /* or a darker green */
  }

  :global(body.dark-mode) button.incorrect {
    background-color: #990000;
  }

  :global(body.dark-mode) button.pending {
    background-color: #5555aa !important; /* or a darker blue */
  }

  :global(body.dark-mode) button:hover:not(.purchased, .pending, .incorrect) {
    background-color: #666;
  }

  /* If your Enter button should remain green (or its default color), override its focus state */
.enter-button:focus {
  background-color: green !important;  /* Replace 'green' with your actual Enter button color if different */
  color: white !important;
}

/* For any letter buttons using the .key class, force their default background on focus */
.key:focus {
  background-color: white !important;  /* Change if your default isn't white */
  color: inherit !important;
}
</style>
