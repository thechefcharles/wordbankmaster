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

  const letterCosts = {
    Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
    A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
    Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
  };

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

  // Reactive: Determine if every editable slot is filled.
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
   * handleKeyDown(event):
   * - "Enter": In guess mode, only submits if guessComplete; otherwise, confirms purchase.
   * - "Delete"/"Backspace": In guess mode, deletes a guess.
   * - "Space": Toggles guess mode.
   * - A–Z: Processes letter keys.
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

<!-- Render the keyboard keys -->
<div class="keyboard-container">
  <div class="keyboard">
    {#each Object.keys(letterCosts) as letter}
      <button
        on:click={(e) => { handleLetterClick(letter); e.currentTarget.blur(); }}
        class="{
          ($gameStore.selectedPurchase &&
           $gameStore.selectedPurchase.type === 'letter' &&
           $gameStore.selectedPurchase.value === letter &&
           $gameStore.gameState === 'purchase_pending')
            ? 'pending'
            : ($gameStore.lockedLetters && $gameStore.lockedLetters[letter])
              ? 'purchased'
              : $gameStore.incorrectLetters.includes(letter)
                ? 'incorrect'
                : ''
        }"
      >
        <div class="letter">{letter}</div>
        <div class="price">${letterCosts[letter]}</div>
      </button>
    {/each}
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
  }
  .keyboard {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    justify-content: center;
  }
  button {
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
</style>
