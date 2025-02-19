<script>
  import { onMount } from 'svelte';
  import {
    gameStore,
    selectLetter,
    inputGuessLetter,
    confirmPurchase,
    submitGuess,
    deleteGuessLetter,
    enterGuessMode,
    letterCosts
  } from '$lib/stores/GameStore.js';

  // QWERTY rows
  const row1 = ['Q','W','E','R','T','Y','U','I','O','P'];
  const row2 = ['A','S','D','F','G','H','J','K','L'];
  const row3 = ['Z','X','C','V','B','N','M'];

  // Click logic depends on gameState (guess vs purchase)
  function handleLetterClick(letter) {
    if ($gameStore.gameState === 'guess_mode') {
      inputGuessLetter(letter);
    } else {
      selectLetter(letter);
    }
  }

  // Check if all guess slots are filled
  $: guessComplete = $gameStore.gameState === 'guess_mode' && (() => {
    const phrase = $gameStore.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if ($gameStore.purchasedLetters[i] === phrase[i]) continue;
      if (!$gameStore.guessedLetters[i]) return false;
    }
    return true;
  })();

  // Keyboard events
  function handleKeyDown(event) {
    if (event.key === 'Enter') {
      event.preventDefault();
      if ($gameStore.gameState === 'guess_mode') {
        if (guessComplete) submitGuess();
        else console.log("Not all guess slots are filled.");
      } else {
        confirmPurchase();
      }
    } 
    else if (event.key === 'Delete' || event.key === 'Backspace') {
      event.preventDefault();
      if ($gameStore.gameState === 'guess_mode') {
        deleteGuessLetter();
      }
    } 
    else if (event.key === ' ' || event.code === 'Space') {
      event.preventDefault();
      enterGuessMode();
    } 
    else {
      // If it's an A-Z letter
      const key = event.key.toUpperCase();
      if (/^[A-Z]$/.test(key)) {
        event.preventDefault();
        handleLetterClick(key);
      }
    }
    // remove focus
    document.activeElement.blur();
  }

  onMount(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  });
</script>

<!-- Keyboard Layout -->
<div class="keyboard-container">
  <!-- Row 1: Q-P + Del -->
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
    <button class="key delete" on:click={deleteGuessLetter}>
      <div class="letter">Del</div>
    </button>
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
    width: 140px;
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

  /* Button states */
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
  .submit-ready {
    background-color: green !important;
    color: white !important;
  }

  @media (max-width: 480px) {
    .key {
      width: 40px;
      height: 40px;
      font-size: 12px;
    }
    .enter-button {
      min-width: 50px;
    }
  }

  /* Dark mode overrides */
  :global(body.dark-mode) .keyboard-container {
    background-color: #333;
  }

  :global(body.dark-mode) .key {
    background-color: #444;
    color: white;
    border-color: #777;
  }

  :global(body.dark-mode) .key.delete {
    background-color: #cc6666;
  }

  :global(body.dark-mode) .letter {
    color: white;
  }

  :global(body.dark-mode) .price {
    color: #ccc;
  }

  :global(body.dark-mode) button.purchased {
    background-color: #228b22; 
  }

  :global(body.dark-mode) button.incorrect {
    background-color: #990000;
  }

  :global(body.dark-mode) button.pending {
    background-color: #5555aa !important;
  }

  :global(body.dark-mode) button:hover:not(.purchased, .pending, .incorrect) {
    background-color: #666;
  }

  .enter-button:focus {
    background-color: green !important;
    color: white !important;
  }
  .key:focus {
    background-color: white !important;
    color: inherit !important;
  }
</style>
