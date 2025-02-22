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

  // Define letter costs (mirrors GameStore constants)
  const letterCosts = {
    Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
    A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
    Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
  };

  // QWERTY layout rows
  const row1 = ['Q','W','E','R','T','Y','U','I','O','P'];
  const row2 = ['A','S','D','F','G','H','J','K','L'];
  const row3 = ['Z','X','C','V','B','N','M'];

  /**
   * handleLetterClick
   * In guess_mode: inputs a guess letter.
   * Otherwise: toggles the letter selection for purchase.
   */
  function handleLetterClick(letter, event) {
    gameStore.update(state => {
      if (state.gameState === 'guess_mode') {
        inputGuessLetter(letter);
      } else {
        // If already selected, deselect it and return to default
        if (
          state.selectedPurchase &&
          state.selectedPurchase.type === 'letter' &&
          state.selectedPurchase.value === letter
        ) {
          console.log(`Deselecting letter: ${letter}`);
          return { ...state, selectedPurchase: null, gameState: "default" };
        }
        // Otherwise, select the letter for purchase
        console.log(`Selecting letter: ${letter}`);
        return {
          ...state,
          gameState: "purchase_pending",
          selectedPurchase: { type: 'letter', value: letter }
        };
      }
      return state;
    });
    // Remove focus from the clicked button to avoid lingering focus styles
    event.target.blur();
  }

  /**
   * handleKeyDown
   * Maps key presses to game actions.
   */
  function handleKeyDown(event) {
    event.preventDefault();
    const key = event.key.toUpperCase();

    gameStore.update(state => {
      if (event.key === 'Enter') {
        if (state.selectedPurchase) {
          confirmPurchase();
          return { ...state, gameState: "default" };
        }
        if (state.gameState === "guess_mode") {
          return state.guessedLetters &&
                 Object.keys(state.guessedLetters).length === state.currentPhrase.replace(/\s/g, '').length
                 ? submitGuess()
                 : { ...state, gameState: "default", guessedLetters: {} };
        }
        if (!state.selectedPurchase && state.gameState !== "guess_mode") {
          return { ...state, gameState: "guess_mode", guessedLetters: {} };
        }
        return state;
      }
      if (event.key === 'Backspace' || event.key === 'Delete') {
        if (state.gameState === "guess_mode") {
          deleteGuessLetter();
        }
        return state;
      }
      if (event.key === ' ' || event.code === 'Space') {
        enterGuessMode();
        return state;
      }
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
    document.activeElement.blur();
  }

  // Set up global listeners
  onMount(() => {
    window.addEventListener('keydown', handleKeyDown);

    // Remove focus from any button when clicking outside a key
    const removeFocus = (event) => {
      if (!event.target.classList.contains('key')) {
        document.activeElement.blur();
      }
    };
    document.addEventListener('click', removeFocus);

    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      document.removeEventListener('click', removeFocus);
    };
  });
</script>

<!-- Keyboard Layout Rendering -->
<div class="keyboard-container { $gameStore.gameState === 'guess_mode' ? 'guess-mode' : '' }">
  <!-- Row 1 -->
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
                : $gameStore.bankroll < letterCosts[letter]
                  ? 'disabled-letter'
                  : ''
        }"
        on:click={(event) => handleLetterClick(letter, event)}
        disabled={$gameStore.bankroll < letterCosts[letter] ? true : undefined}
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

  <!-- Row 2 -->
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
                : $gameStore.bankroll < letterCosts[letter]
                  ? 'disabled-letter'
                  : ''
        }"
        on:click={(event) => handleLetterClick(letter, event)}
        disabled={$gameStore.bankroll < letterCosts[letter] ? true : undefined}
      >
        <div class="letter">{letter}</div>
        <div class="price">${letterCosts[letter]}</div>
      </button>
    {/each}
  </div>

  <!-- Row 3 -->
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
                : $gameStore.bankroll < letterCosts[letter]
                  ? 'disabled-letter'
                  : ''
        }"
        on:click={(event) => handleLetterClick(letter, event)}
        disabled={$gameStore.bankroll < letterCosts[letter] ? true : undefined}
      >
        <div class="letter">{letter}</div>
        <div class="price">${letterCosts[letter]}</div>
      </button>
    {/each}
  </div>
</div>

<style>
  /* ---------------------------
     Keyboard Container & Layout
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
  .key.delete {
    background-color: red;
    color: white;
    border: 2px solid darkred;
  }
  :global(body.dark-mode) .key.delete {
    background-color: red;
    color: white;
    border: 2px solid darkred;
  }

  /* ---------------------------
     Letter & Price Styling
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
  .purchased {
    background-color: green;
    color: white;
    cursor: default;
  }
  .pending {
    background-color: blue !important;
    color: white !important;
    animation: blink 1s infinite;
  }
  .incorrect {
    background-color: red;
    color: white;
    cursor: default;
  }
  @keyframes blink {
    0% { opacity: 1; }
    50% { opacity: 0.5; }
    100% { opacity: 1; }
  }

  /* Default state for non-pending keys */
  .key:not(.pending) {
    background-color: white !important;
    color: black !important;
  }

  /* Remove iOS/Android tap highlight */
  button, .key, a, [role="button"] {
    -webkit-tap-highlight-color: transparent;
  }

  /* Override focus/active for non-pending keys */
  .key:not(.pending):focus,
  .key:not(.pending):active {
    outline: none !important;
    box-shadow: none !important;
    background-color: inherit !important;
    color: inherit !important;
  }

  /* Ensure that a focused pending key stays blue */
  .key.pending:focus,
  .key.pending:active {
    background-color: blue !important;
    color: white !important;
    animation: blink 1s infinite;
    outline: none !important;
    box-shadow: none !important;
  }

  /* ---------------------------
     Dark Mode Overrides
  --------------------------- */
  :global(body.dark-mode) .keyboard-container {
    background-color: #333;
  }
  :global(body.dark-mode) .key {
    background-color: #444;
    color: white;
    border-color: #777;
  }
  :global(body.dark-mode) .purchased {
    background-color: green !important;
    color: white !important;
  }
  :global(body.dark-mode) .incorrect {
    background-color: red !important;
    color: white !important;
  }
  :global(body.dark-mode) .pending {
    background-color: blue !important;
    color: white !important;
    animation: blink 1s infinite;
  }

  .disabled-letter {
    opacity: 0.5;
    filter: blur(2px);
    pointer-events: none;
    user-select: none;
    transition: filter 0.2s ease, opacity 0.2s ease;
  }
  :global(body) .guess-mode .disabled-letter {
    filter: none;
    opacity: 1;
    pointer-events: auto;
  }
  /* Default for non-pending keys in light mode */
.key:not(.pending) {
  background-color: white !important;
  color: black !important;
}

/* Default for non-pending keys in dark mode */
:global(body.dark-mode) .key:not(.pending) {
  background-color: #444 !important;
  color: white !important;
}

</style>
