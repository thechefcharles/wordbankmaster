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

  let selectedKeys = new Set();

  // Define letter costs locally
  const letterCosts = {
    Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
    A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
    Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
  };

  // Rows for QWERTY layout
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
      if (phrase[i] === ' ') continue;
      if ($gameStore.purchasedLetters[i] === phrase[i]) continue;
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
    document.activeElement.blur();
  }

  onMount(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  });

  function toggleKeySelection(letter) {
    if (selectedKeys.has(letter)) {
      selectedKeys.delete(letter);
    } else {
      selectedKeys.add(letter);
    }
  }
</script>

<!-- QWERTY Keyboard Layout -->
<div class="keyboard-container">
  <!-- Row 1: Q-P + Delete -->
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
  </div>

  <!-- Row 2: A-L -->
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

  <!-- Row 3: Z-M + Enter -->
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
    <button
    class="key enter-button { $gameStore.gameState === 'purchase_pending' ? 'submit-ready' : '' }"
    on:click={() => {
      if ($gameStore.gameState === 'purchase_pending') {
        confirmPurchase();
      } else if ($gameStore.gameState === 'guess_mode') {
        if (guessComplete) submitGuess();
        else console.log("Not all guess slots are filled.");
      } else {
        // fallback behavior if needed
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

  .keyboard-row {
    display: flex;
    flex-wrap: nowrap;
    gap: 2px;
    justify-content: center;
  }

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
    background-color: #ff6666;
    color: white;
  }
  
  .enter-button {
    width: 70px;
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
  }
  .enter-button.pending {
  animation: blink 1s infinite;
}

@keyframes blink {
  0% { opacity: 1; }
  50% { opacity: 0.5; }
  100% { opacity: 1; }
}

.enter-button.submit-ready {
  background-color: green !important;
  color: white !important;
  animation: blink 1s infinite;
}

@keyframes blink {
  0% { opacity: 1; }
  50% { opacity: 0.5; }
  100% { opacity: 1; }
}

/* Optionally, if you need a dark mode override: */
:global(body.dark-mode) .enter-button.submit-ready {
  background-color: green !important;
  color: white !important;
  animation: blink 1s infinite;
}


/* If needed, override in dark mode */
:global(body.dark-mode) .enter-button.pending {
  animation: blink 1s infinite;
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
  animation: blink 1s infinite;
}

@keyframes blink {
  0% { opacity: 1; }
  50% { opacity: 0.5; }
  100% { opacity: 1; }
}
  button.incorrect {
    background-color: red;
    color: white;
    cursor: default;
  }
  
  button:hover:not(.purchased, .pending, .incorrect) {
    background-color: lightgray;
  }
  
  .submit-ready {
    background-color: green !important;
    color: white !important;
  }
  

/* Apply blinking effect to any element with the .selected class */
.selected {
  animation: blink 1s infinite;
}

  
/* DARK MODE Overrides for the keyboard container and keys */
:global(body.dark-mode) .keyboard-container {
  background-color: #333;
}

:global(body.dark-mode) .key {
  background-color: #444;
  color: white;
  border-color: #777;
}

/* Specific overrides for state classes in dark mode */
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

@keyframes blink {
  0%   { opacity: 1; }
  50%  { opacity: 0.5; }
  100% { opacity: 1; }
}


/* Continue with existing overrides */
:global(body.dark-mode) .key.delete {
  background-color: #cc6666;
  color: white;
}

:global(body.dark-mode) .letter {
  color: white;
}

:global(body.dark-mode) .price {
  color: #ccc;
}

:global(body.dark-mode) .selected {
  animation: blink 1s infinite;
}

</style>
