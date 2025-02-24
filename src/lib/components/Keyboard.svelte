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

  // Define letter costs for display purposes (mirrors GameStore constants)
  const letterCosts = {
    Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
    A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
    Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
  };

  // Define rows for a QWERTY layout
  const row1 = ['Q','W','E','R','T','Y','U','I','O','P'];
  const row2 = ['A','S','D','F','G','H','J','K','L'];
  const row3 = ['Z','X','C','V','B','N','M'];
  

  $: disabledKeys = Object.keys(letterCosts).filter(letter => 
    letterCosts[letter] > $gameStore.bankroll || 
    $gameStore.incorrectLetters.includes(letter)  // 🔹 Keep incorrect letters blurred
);


  /**
   * handleLetterClick
   * Depending on the game state, either inputs a guess letter or selects a letter for purchase.
   *
   * @param {string} letter - The letter clicked.
   */
  function handleLetterClick(letter) {
    if ($gameStore.gameState === 'guess_mode') {
      inputGuessLetter(letter);
    } else {
      selectLetter(letter);
    }
  }

  /**
   * Global keyboard handler for Enter, Backspace/Delete, Space, and letter keys.
   *
   * Prevents default browser behavior and maps keys to game actions.
   */
  function handleKeyDown(event) {
    event.preventDefault();
    const key = event.key.toUpperCase();

    gameStore.update(state => {
      // ENTER: Confirm purchase or submit guess/enter guess mode
      if (event.key === 'Enter') {
        if (state.selectedPurchase) {
          confirmPurchase();
          return { ...state, gameState: "default" };
        }
        if (state.gameState === "guess_mode") {
          // If guess is complete, submit; otherwise, exit guess mode.
          return state.guessedLetters &&
            Object.keys(state.guessedLetters).length === state.currentPhrase.replace(/\s/g, '').length
              ? submitGuess()
              : { ...state, gameState: "default", guessedLetters: {} };
        }
        // If not in guess mode, enter guess mode.
        if (!state.selectedPurchase && state.gameState !== "guess_mode") {
          return { ...state, gameState: "guess_mode", guessedLetters: {} };
        }
        return state;
      }

      // BACKSPACE / DELETE: Remove last guessed letter in guess mode
      if (event.key === 'Backspace' || event.key === 'Delete') {
        if (state.gameState === "guess_mode") {
          deleteGuessLetter();
        }
        return state;
      }

      // SPACEBAR: Toggle guess mode
      if (event.key === ' ' || event.code === 'Space') {
        enterGuessMode();
        return state;
      }

      // Letter keys: Either input as guess or select for purchase.
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

    // Remove focus from active element after key press to avoid unwanted focus styling
    document.activeElement.blur();
  }

  // Set up a global keydown listener on mount.
  onMount(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  });
</script>

<!-- Keyboard layout rendering -->
<div class="keyboard-container">
  <!-- Row 1: Q - P -->
  <div class="keyboard-row">
    {#each row1 as letter}
      <button
      class="key 
      {disabledKeys.includes(letter) && $gameStore.gameState !== 'guess_mode' ? 'disabled' : ''} 
      {($gameStore.selectedPurchase?.type === 'letter' && 
        $gameStore.selectedPurchase.value === letter && 
        $gameStore.gameState === 'purchase_pending') ? 'pending' : ''}
      {($gameStore.lockedLetters?.[letter]) ? 'purchased' : ''}
      {($gameStore.incorrectLetters.includes(letter)) ? 'incorrect' : ''}"        on:click={() => handleLetterClick(letter)}
      >
        <div class="letter">{letter}</div>
        <div class="price">${letterCosts[letter]}</div>
      </button>
    {/each}
  </div>

  <!-- Row 2: A - L -->
  <div class="keyboard-row">
    {#each row2 as letter}
      <button
        class="key {disabledKeys.includes(letter) && $gameStore.gameState !== 'guess_mode' ? 'disabled' : ''} 
                { $gameStore.selectedPurchase?.type === 'letter' &&
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

  <!-- Row 3: Z - M (Plus Delete Button in Guess Mode) -->
  <div class="keyboard-row">
    {#each row3 as letter}
      <button
        class="key {disabledKeys.includes(letter) && $gameStore.gameState !== 'guess_mode' ? 'disabled' : ''} 
                { $gameStore.selectedPurchase?.type === 'letter' &&
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
    padding-bottom: 200px; /* Ensure space for the keyboard */
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
    filter: blur(.8px); /* Apply a subtle blur */
    opacity: 0.7; /* Make slightly faded */
    pointer-events: none; /* Prevent clicking */
    transition: filter 0.3s ease, opacity 0.3s ease;
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
    filter: blur(.8px); /* Apply a subtle blur */
    opacity: 0.7; /* Make slightly faded */
    pointer-events: none; /* Prevent clicking */
    transition: filter 0.3s ease, opacity 0.3s ease;
  }

  /* Blinking animation for pending keys */
  @keyframes blink {
    0% { opacity: 1; }
    50% { opacity: 0.5; }
    100% { opacity: 1; }
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

  /* 🔹 Apply blur effect to unaffordable letters */
  .key.disabled {
    filter: blur(.8px);  /* 🔹 Blur effect */
    opacity: 0.5;       /* 🔹 Make slightly faded */
    pointer-events: none; /* 🔹 Prevent clicking */
    transition: filter 0.3s ease, opacity 0.3s ease;
}

/* 🔹 Remove blur when in guess mode */
body.guess-mode .key.incorrect,
body.guess-mode .key.disabled {
    filter: none !important;
    opacity: 1 !important;
    pointer-events: all;
}
/* 🔹 Light up keys that are NOT purchased, incorrect, or disabled */
.key:not(.purchased):not(.incorrect):not(.disabled) {
    box-shadow: 0px 0px 8px rgba(0, 255, 180, 0.6); /* Initial blue-green glow */
    animation: subtleGlow 2s infinite alternate ease-in-out;
}

/* 🔹 Smooth Blue-Green Glow Animation */
@keyframes subtleGlow {
    0% { box-shadow: 0px 0px 6px rgba(0, 150, 255, 0.5); } /* Soft blue */
    50% { box-shadow: 0px 0px 10px rgba(0, 255, 180, 0.6); } /* Mix between blue & green */
    100% { box-shadow: 0px 0px 8px rgba(0, 255, 120, 0.5); } /* Soft green */
}

</style>
