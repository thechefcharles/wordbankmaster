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

  // Define the keyboard rows.
  const row1 = ['Q','W','E','R','T','Y','U','I','O','P'];
  const row2 = ['A','S','D','F','G','H','J','K','L'];
  const row3 = ['Z','X','C','V','B','N','M'];

  // Helper: Returns an array of editable indices (non‑space and not locked).
  function getEditableIndices(state) {
    const indices = [];
    const phrase = state.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if (state.purchasedLetters[i] === phrase[i]) continue;
      indices.push(i);
    }
    return indices;
  }

  /**
   * handleLetterClick(letter):
   * - In guess mode: calls inputGuessLetter(letter)
   * - Otherwise: calls selectLetter(letter) for purchase.
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

  // Reactive: Determine if every editable slot is filled with a guess.
  $: guessComplete = $gameStore.gameState === 'guess_mode' && (() => {
    const phrase = $gameStore.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if ($gameStore.purchasedLetters[i] === phrase[i]) continue;
      if (!$gameStore.guessedLetters[i]) return false;
    }
    return true;
  })();

  /**
   * handleKeyDown(event): Handles keyboard events.
   */
  function handleKeyDown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      if ($gameStore.gameState === 'guess_mode') {
        if (guessComplete) {
          submitGuess();
        } else {
          console.log("Not all guess slots are filled.");
        }
      } else {
        confirmPurchase();
      }
      document.activeElement.blur();
    } else if (event.key === "Delete" || event.key === "Backspace") {
      event.preventDefault();
      if ($gameStore.gameState === 'guess_mode') {
        deleteGuessLetter();
      }
      document.activeElement.blur();
    } else if (event.key === " " || event.code === "Space") {
      event.preventDefault();
      enterGuessMode();
      document.activeElement.blur();
    } else {
      const key = event.key.toUpperCase();
      if (/^[A-Z]$/.test(key)) {
        event.preventDefault();
        handleLetterClick(key);
        document.activeElement.blur();
      }
    }
  }

  onMount(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  });
</script>

<!-- Keyboard Layout -->
<div class="keyboard-container">
  <!-- Row 1: Keys Q-P plus Delete -->
  <div class="keyboard-row">
    {#each row1 as letter}
      <button on:click={() => { handleLetterClick(letter); }} class="key { $gameStore.selectedPurchase &&
          $gameStore.selectedPurchase.type === 'letter' &&
          $gameStore.selectedPurchase.value === letter &&
          $gameStore.gameState === 'purchase_pending'
            ? 'pending'
            : ($gameStore.lockedLetters && $gameStore.lockedLetters[letter])
              ? 'purchased'
              : $gameStore.incorrectLetters.includes(letter)
                ? 'incorrect'
                : '' }">
        <div class="letter">{letter}</div>
        <div class="price">${letterCosts[letter]}</div>
      </button>
    {/each}
    <button class="key delete" on:click={() => { deleteGuessLetter(); }}>
      <div class="letter">Del</div>
    </button>
  </div>

  <!-- Row 2: Keys A-L -->
  <div class="keyboard-row">
    {#each row2 as letter}
      <button on:click={() => { handleLetterClick(letter); }} class="key { $gameStore.selectedPurchase &&
          $gameStore.selectedPurchase.type === 'letter' &&
          $gameStore.selectedPurchase.value === letter &&
          $gameStore.gameState === 'purchase_pending'
            ? 'pending'
            : ($gameStore.lockedLetters && $gameStore.lockedLetters[letter])
              ? 'purchased'
              : $gameStore.incorrectLetters.includes(letter)
                ? 'incorrect'
                : '' }">
        <div class="letter">{letter}</div>
        <div class="price">${letterCosts[letter]}</div>
      </button>
    {/each}
  </div>

  <!-- Row 3: "Guess" button, then keys Z-M, then "Enter" button -->
  <div class="keyboard-row">
    <!-- Guess button (left of row3) -->
    <button class="key guess-button { $gameStore.gameState === 'guess_mode' ? 'active-guess' : '' }" on:click={() => enterGuessMode()}>
      <div class="letter">Guess</div>
    </button>
    {#each row3 as letter}
      <button on:click={() => { handleLetterClick(letter); }} class="key { $gameStore.selectedPurchase &&
          $gameStore.selectedPurchase.type === 'letter' &&
          $gameStore.selectedPurchase.value === letter &&
          $gameStore.gameState === 'purchase_pending'
            ? 'pending'
            : ($gameStore.lockedLetters && $gameStore.lockedLetters[letter])
              ? 'purchased'
              : $gameStore.incorrectLetters.includes(letter)
                ? 'incorrect'
                : '' }">
        <div class="letter">{letter}</div>
        <div class="price">${letterCosts[letter]}</div>
      </button>
    {/each}
    <!-- Enter button (right of row3) -->
    <button class="key enter-button { ($gameStore.gameState === 'guess_mode' && guessComplete) || $gameStore.gameState === 'purchase_pending' ? 'submit-ready' : '' }" on:click={() => {
      if ($gameStore.gameState === 'guess_mode') {
        if (guessComplete) {
          submitGuess();
        } else {
          console.log("Not all guess slots are filled.");
        }
      } else {
        confirmPurchase();
      }
    }}>
      <div class="letter">Enter</div>
    </button>
  </div>
</div>

<style>
  button:focus {
    outline: none;
  }
  .keyboard-container {
    background-color: #f9f9f9;
    padding: 10px;
    border-radius: 4px;
    margin-bottom: 20px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    justify-content: center;
  }
  .keyboard-row {
    display: flex;
    flex-wrap: nowrap;
    gap: 8px;
    justify-content: center;
  }
  .key {
    width: 50px;
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
    background-color: #ff6666;
    color: white;
  }
  .guess-button, .enter-button {
    background-color: #ddd;
    min-width: 60px; /* Adjust if needed for the text */
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
</style>
