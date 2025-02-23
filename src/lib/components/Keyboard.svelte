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

  $: glowKeys = Object.keys(letterCosts).filter(letter =>
  // ✅ In default mode, highlight purchasable keys
  ($gameStore.gameState !== "guess_mode" &&
    letterCosts[letter] <= $gameStore.bankroll &&  // Can afford
    !$gameStore.lockedLetters?.[letter] &&         // Not green
    !$gameStore.incorrectLetters.includes(letter)) // Not red

  || 

  // ✅ In guess mode, highlight enterable keys
  ($gameStore.gameState === "guess_mode" &&
    !$gameStore.lockedLetters?.[letter]) // Anything that isn't locked is enterable
);


  // 🔹 Identify all keys that are still available for purchase
$: purchasableKeys = Object.keys(letterCosts).filter(letter =>
  !$gameStore.lockedLetters?.[letter] &&  // ✅ Not already purchased
  !$gameStore.incorrectLetters.includes(letter) &&  // ✅ Not incorrect
  letterCosts[letter] <= $gameStore.bankroll  // ✅ Can be afforded
);

$: blurredKeys = Object.keys(letterCosts).filter(letter => 
  // 🔹 In default mode, blur incorrect (red), purchased (green), and unaffordable letters
  ($gameStore.gameState !== "guess_mode" &&
    (letterCosts[letter] > $gameStore.bankroll ||  // Blurs unaffordable letters
    $gameStore.lockedLetters?.[letter] ||          // Blurs purchased (green) letters
    $gameStore.incorrectLetters.includes(letter))  // Blurs incorrect (red) letters
  )

  ||

  // 🔹 In guess mode, ONLY blur red (incorrect) & green (purchased) letters
  ($gameStore.gameState === "guess_mode" &&
    ($gameStore.lockedLetters?.[letter] || $gameStore.incorrectLetters.includes(letter))
  )
);

$: disabledKeys = Object.keys(letterCosts).filter(letter => 
  // 🔹 If NOT in guess mode, disable unaffordable, incorrect (red), and purchased (green) letters
  ($gameStore.gameState !== "guess_mode" &&
    (letterCosts[letter] > $gameStore.bankroll || 
     $gameStore.lockedLetters?.[letter] || 
     $gameStore.incorrectLetters.includes(letter)) 
  )

  ||

  // 🔹 If IN guess mode, only disable red & green letters (everything else should be selectable)
  ($gameStore.gameState === "guess_mode" &&
    ($gameStore.lockedLetters?.[letter] || $gameStore.incorrectLetters.includes(letter))
  )
);


  /**
   * handleLetterClick
   * Depending on the game state, either inputs a guess letter or selects a letter for purchase.
   *
   * @param {string} letter - The letter clicked.
   */
   function handleLetterClick(letter) {
  if ($gameStore.gameState === 'guess_mode') {
    // 🔹 Allow guessing ANY letter (even if unaffordable)
    inputGuessLetter(letter);
  } else if (!blurredKeys.includes(letter)) {
    // 🔹 Only allow purchasing if the letter is NOT blurred
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
      {glowKeys.includes(letter) ? 'glow' : ''}
       {blurredKeys.includes(letter) ? 'blurred' : ''}
      {disabledKeys.includes(letter) && $gameStore.gameState !== 'guess_mode' ? 'disabled' : ''} 
      {purchasableKeys.includes(letter) ? 'purchasable' : ''}  /* 🔹 Highlight purchasable keys */
      { $gameStore.lockedLetters?.[letter] ? 'purchased' : '' }
      { $gameStore.incorrectLetters.includes(letter) ? 'incorrect' : '' }
      { $gameStore.selectedPurchase?.type === 'letter' &&
        $gameStore.selectedPurchase.value === letter &&
        $gameStore.gameState === 'purchase_pending' ? 'pending' : '' }"
    on:click={() => handleLetterClick(letter)}
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
        class="key
                {glowKeys.includes(letter) ? 'glow' : ''} 
                {blurredKeys.includes(letter) ? 'blurred' : ''}
                {disabledKeys.includes(letter) && $gameStore.gameState !== 'guess_mode' ? 'disabled' : ''} 
                {purchasableKeys.includes(letter) ? 'purchasable' : ''}  /* 🔹 Highlight purchasable keys */
                { $gameStore.lockedLetters?.[letter] ? 'purchased' : '' }
                {$gameStore.incorrectLetters.includes(letter) ? 'incorrect' : ''}
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
        class="key
                 {glowKeys.includes(letter) ? 'glow' : ''} 
                 {blurredKeys.includes(letter) ? 'blurred' : ''}
                {disabledKeys.includes(letter) && $gameStore.gameState !== 'guess_mode' ? 'disabled' : ''} 
                {purchasableKeys.includes(letter) ? 'purchasable' : ''}  /* 🔹 Highlight purchasable keys */
                { $gameStore.lockedLetters?.[letter] ? 'purchased' : '' }
                {$gameStore.incorrectLetters.includes(letter) ? 'incorrect' : ''}
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
  .key.incorrect,
  .key.disabled {
    filter: blur(.7px);  /* 🔹 Blur effect */
    opacity: 0.6;       /* 🔹 Make slightly faded */
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

/* 🔹 Blur correctly purchased (green) letters on the keyboard in guess mode */
body.guess-mode .key.purchased {
    filter: blur(.7px); /* 🔹 Add blur effect */
    opacity: 0.6; /* 🔹 Make slightly faded */
    pointer-events: none; /* 🔹 Prevent clicking */
    transition: filter 0.3s ease, opacity 0.3s ease;
}

/* 🔹 Blur letters if unaffordable or restricted in guess mode */
.key.blurred {
    filter: blur(.7px);  /* 🔹 Apply blur effect */
    opacity: 0.6;       /* 🔹 Make them slightly faded */
    pointer-events: none; /* 🔹 Prevent clicking */
    transition: filter 0.3s ease, opacity 0.3s ease;
}

/* 🔹 In guess mode: Unblur all selectable letters */
body.guess-mode .key:not(.purchased):not(.incorrect) {
    filter: none !important;
    opacity: 1 !important;
    pointer-events: all !important;
}

/* 🔹 In guess mode: Ensure incorrect & purchased letters remain blurred */
body.guess-mode .key.purchased,
body.guess-mode .key.incorrect {
    filter: blur(1.5px); /* Keep them blurred */
    opacity: 0.7;
    pointer-events: none;
    transition: filter 0.3s ease, opacity 0.3s ease;
}

/* 🔹 Ensure non-blurred keys are normal */
.key:not(.blurred) {
    filter: none;
    opacity: 1;
    pointer-events: all;
}

/* 🔹 Prevent unwanted blurring outside guess mode */
body:not(.guess-mode) .key.purchased,
body:not(.guess-mode) .key.incorrect {
    filter: none !important;
    opacity: 1 !important;
    pointer-events: all !important;
}

/* 🔹 In guess mode, blur red (incorrect) and green (purchased) letters */
body.guess-mode .key.purchased,
body.guess-mode .key.incorrect {
    filter: blur(.7px);
    opacity: 0.6;
    pointer-events: none;
    transition: filter 0.3s ease, opacity 0.3s ease;
}

/* 🔹 In guess mode, unaffordable letters should become CLEAR (unblurred) */
body.guess-mode .key.blurred {
    filter: none !important;
    opacity: 1 !important;
    pointer-events: all !important;
}

/* 🔹 Subtle white glow effect for purchasable keys */
.key.purchasable {
    background-color: rgba(255, 255, 255, 0.1); /* Very light white tint */
    box-shadow: 0 0 6px 2px rgba(255, 255, 255, 0.4); /* Soft outer glow */
    animation: glowPulse 1.5s infinite alternate; /* Slower, subtle pulsing */
    transition: box-shadow 0.3s ease, background-color 0.3s ease;
}

/* 🔹 Slight increase in glow on hover */
.key.purchasable:hover {
    background-color: rgba(255, 255, 255, 0.2);
    box-shadow: 0 0 8px 3px rgba(255, 255, 255, 0.5);
}

/* 🔹 Soft pulsing glow animation */
@keyframes glowPulse {
    0% {
        box-shadow: 0 0 6px 2px rgba(255, 255, 255, 0.4);
    }
    100% {
        box-shadow: 0 0 10px 4px rgba(255, 255, 255, 0.5);
    }
}

/* 🔹 Subtle white glow for purchasable/enterable keys */
.key.glow {
    background-color: rgba(255, 255, 255, 0.05); /* Very light white tint */
    box-shadow: 0 0 5px 1px rgba(255, 255, 255, 0.3); /* Softer glow */
    animation: softPulse 1.5s infinite alternate ease-in-out; /* Slower and minimal */
    transition: box-shadow 0.3s ease, background-color 0.3s ease;
}

/* 🔹 Gentle increase on hover */
.key.glow:hover {
    background-color: rgba(255, 255, 255, 0.1);
    box-shadow: 0 0 7px 2px rgba(255, 255, 255, 0.4);
}

/* 🔹 Soft pulsing effect */
@keyframes softPulse {
    0% {
        box-shadow: 0 0 5px 1px rgba(255, 255, 255, 0.3);
    }
    100% {
        box-shadow: 0 0 8px 2px rgba(255, 255, 255, 0.4);
    }
}



</style>
