<script>
  // Import necessary Svelte functions and store functions
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

  // Local state for keyboard (if needed)
  let selectedKeys = new Set();

  // Define letter costs (for display purposes)
  const letterCosts = {
    Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
    A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
    Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
  };

  // Define keyboard rows for a QWERTY layout
  const row1 = ['Q','W','E','R','T','Y','U','I','O','P'];
  const row2 = ['A','S','D','F','G','H','J','K','L'];
  const row3 = ['Z','X','C','V','B','N','M'];

  /**
   * handleLetterClick(letter)
   * - In guess mode, inputs the guess letter.
   * - Otherwise, selects the letter for purchase.
   */
  function handleLetterClick(letter) {
    if ($gameStore.gameState === 'guess_mode') {
      inputGuessLetter(letter);
    } else {
      selectLetter(letter);
    }
  }

  /**
   * Reactive check: Determine if all guess slots are filled.
   */
  $: guessComplete = $gameStore.gameState === 'guess_mode' && (() => {
    const phrase = $gameStore.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue; // Skip spaces
      if ($gameStore.purchasedLetters[i] === phrase[i]) continue; // Skip purchased letters
      if (!$gameStore.guessedLetters[i]) return false; // If any box is empty, return false
    }
    return true;
  })();

  /**
   * Global keyboard handler to support Enter, Delete/Backspace, and Space.
   */
   function handleKeyDown(event) {
  event.preventDefault(); // Prevent unintended default browser actions

  const key = event.key.toUpperCase();

  gameStore.update(state => {
    // --- ENTER KEY FUNCTIONALITY ---
    if (event.key === 'Enter') {
      if (state.selectedPurchase) {
        confirmPurchase();
        return { ...state, gameState: "default" }; // Stay in default mode after purchase
      }

      if (state.gameState === "guess_mode") {
        return guessComplete
          ? submitGuess()
          : { ...state, gameState: "default", guessedLetters: {} }; // Exit guess mode if incomplete
      }

      if (!state.selectedPurchase && state.gameState !== "guess_mode") {
        return { ...state, gameState: "guess_mode", guessedLetters: {} };
      }

      return state;
    }

    // --- BACKSPACE / DELETE (Remove last guessed letter) ---
    if (event.key === 'Backspace' || event.key === 'Delete') {
      if (state.gameState === "guess_mode") {
        deleteGuessLetter();
      }
      return state;
    }

    // --- SPACEBAR (Toggles Guess Mode) ---
    if (event.key === ' ' || event.code === 'Space') {
      enterGuessMode();
      return state;
    }

    // --- LETTER SELECTION (Only when not submitting) ---
    if (/^[A-Z]$/.test(key)) {
      if (state.gameState === "guess_mode") {
        inputGuessLetter(key);
      } else {
        selectLetter(key);
      }
      return state;
    }

    return state;
  });

  // Remove focus from active element after key press
  document.activeElement.blur();
}
</script>

<div class="keyboard-container">
  <!-- Row 1: Letters Q - P, plus conditionally the Delete button -->
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
    {#if $gameStore.gameState === 'guess_mode'}
      <button class="key delete" on:click={deleteGuessLetter}>
        <div class="letter">Del</div>
      </button>
    {/if}
  </div>

  <!-- Row 2: Letters A - L -->
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

  <!-- Row 3: Letters Z - M plus the Enter button -->
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
    <!-- Enter Button: Blinks green when guessComplete is true -->
  </div>
</div>

<style>
  /* ---------------------------
     Keyboard Container & Rows
  --------------------------- */
  .keyboard-container {
    position: fixed;
    bottom: 0;
    left: 50%;
    transform: translateX(-50%);
    width: 100%;
    max-width: 600px;
    background-color: #f9f9f9;
    padding: 10px;
    border-top: 2px solid #ccc;
    display: flex;
    flex-direction: column;
    gap: 5px;
    justify-content: center;
    z-index: 1000;
  }

  .keyboard-row {
    display: flex;
    justify-content: center;
    gap: 2px;
    flex-wrap: nowrap;
  }

  body {
    padding-bottom: 200px;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  /* ---------------------------
     Key Styles
  --------------------------- */
  .key {
    width: 70px;
    height: 50px;
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
/* Style for the delete button - red background with white text */
.key.delete {
  background-color: red; /* Changed to a solid red */
  color: white;
  border: 2px solid darkred; /* Optional: add a darker red border */
}

/* Dark mode override for the delete button */
:global(body.dark-mode) .key.delete {
  background-color: red;
  color: white;
  border: 2px solid darkred;
}

  /* ---------------------------
     Enter Button Specifics
  --------------------------- */
  .enter-button {
    width: 70px;
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
    background-color: white !important;
    color: black !important;
    border: 2px solid black;
  }

  /* ---------------------------
     Letter & Price Display
  --------------------------- */
  .letter {
    line-height: 1;
  }
  .price {
    line-height: 1;
    font-size: 10px;
  }

  /* ---------------------------
     Key State Styles
  --------------------------- */
  button.purchased {
    background-color: green;
    color: white;
    cursor: default;
  }
  button.pending {
    background-color: blue !important;
    color: white !important;
    animation: blink 1s infinite;
  }
  button.incorrect {
    background-color: red;
    color: white;
    cursor: default;
  }

  /* ---------------------------
     Enter Button Blinking Effect for Submit Ready State
  --------------------------- */
  .enter-button.submit-ready,
  .enter-button.pending {
    background-color: green !important;
    color: white !important;
    animation: blink 1s infinite;
  }

  /* ---------------------------
     DARK MODE Overrides
  --------------------------- */
  :global(body.dark-mode) .keyboard-container {
    background-color: #333;
  }
  :global(body.dark-mode) .key {
    background-color: #444;
    color: white;
    border-color: #777;
  }
  :global(body.dark-mode) .key.purchased {
    background-color: green !important;
    color: white !important;
  }
  :global(body.dark-mode) .key.incorrect {
    background-color: red !important;
    color: white !important;
  }
  :global(body.dark-mode) .key.pending {
    background-color: blue !important;
    color: white !important;
    animation: blink 1s infinite;
  }
  :global(body.dark-mode) .enter-button.pending,
  :global(body.dark-mode) .enter-button.submit-ready {
    background-color: green !important;
    color: white !important;
    animation: blink 1s infinite;
  }
  :global(body:not(.dark-mode)) .enter-button.submit-ready {
    background-color: green !important;
    color: white !important;
    animation: blink 1s infinite;
  }

  /* Blinking animation */
  @keyframes blink {
    0% { opacity: 1; }
    50% { opacity: 0.5; }
    100% { opacity: 1; }
  }

  :global(body:not(.dark-mode)) .key .letter {
    transition: none !important;
  }
</style>
