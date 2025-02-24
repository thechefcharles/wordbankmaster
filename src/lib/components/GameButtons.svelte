<script>
  import { onMount } from 'svelte';
  import {
    gameStore,
    selectHint,
    selectExtraGuess,
    enterGuessMode,
    deleteGuessLetter,
    confirmPurchase,
    submitGuess
  } from '$lib/stores/GameStore.js';


  // Reactive derivations from the game store
  $: purchasePending = !!$gameStore.selectedPurchase;
  $: hintPending =
    $gameStore.selectedPurchase?.type === 'hint' &&
    $gameStore.gameState === 'purchase_pending';
  $: guessPending =
    $gameStore.selectedPurchase?.type === 'extra_guess' &&
    $gameStore.gameState === 'purchase_pending';
  $: showHintCost = hintPending;
  $: showGuessCost = guessPending;

  // Game status flags
  $: noGuessesLeft = $gameStore.guessesRemaining === 0;
  $: guessModeActive = $gameStore.gameState === 'guess_mode';
  $: bankroll = $gameStore.bankroll;
  $: fundsLow = bankroll < 150;

  // Check if all guess slots are filled in guess mode
  $: guessComplete = guessModeActive && (() => {
    const phrase = $gameStore.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if ($gameStore.purchasedLetters[i] === phrase[i]) continue;
      if (!$gameStore.guessedLetters[i]) return false;
    }
    return true;
  })();

  // Dynamic label for the main action button
  $: buttonLabel = purchasePending
    ? "Confirm Purchase"
    : guessModeActive
      ? (guessComplete ? "Submit Guess" : "Exit Guess Mode")
      : `Guess (${$gameStore.guessesRemaining})`;

  // ----------------------------
  // EVENT HANDLERS
  // ----------------------------
  function handleMainButtonClick() {
    if (purchasePending) {
      confirmPurchase();
      return;
    }
    if (guessModeActive) {
      if (guessComplete) {
        submitGuess();
      } else {
        gameStore.update(state => ({ ...state, gameState: "default", guessedLetters: {} }));
      }
      return;
    }
    if (!purchasePending && !guessModeActive) {
      enterGuessMode();
    }
  }

  function toggleHintPurchase() {
    gameStore.update(state => {
      if (state.selectedPurchase?.type === "hint") {
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      return { ...state, selectedPurchase: { type: "hint" }, gameState: "purchase_pending" };
    });
    setTimeout(() => document.activeElement.blur(), 0);
  }

  function toggleGuessPurchase() {
    gameStore.update(state => {
      if (state.selectedPurchase?.type === "extra_guess") {
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      return { ...state, selectedPurchase: { type: "extra_guess" }, gameState: "purchase_pending" };
    });
    setTimeout(() => document.activeElement.blur(), 0);
  }

  function toggleDarkMode() {
    darkMode = !darkMode;
    document.body.classList.toggle('dark-mode', darkMode);
    localStorage.setItem('darkMode', darkMode);
  }

  // ----------------------------
  // GLOBAL KEY LISTENER
  // ----------------------------
  onMount(() => {
    darkMode = localStorage.getItem('darkMode') === 'true';
    document.body.classList.toggle('dark-mode', darkMode);

    const onKeyDown = (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        if ($gameStore.selectedPurchase) return; // Do nothing if a purchase is pending
        if ($gameStore.gameState === "guess_mode") {
          if (guessComplete) {
            submitGuess();
          } else {
            gameStore.update(state => ({ ...state, gameState: "default", guessedLetters: {} }));
          }
        } else {
          enterGuessMode();
        }
      }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  });
</script>

<!-- ----------------------------
     UI RENDERING
----------------------------- -->

{#if $gameStore.message}
  <div class="message-box">{$gameStore.message}</div>
{/if}

<div class="buttons-container">
  <!-- Hint Button -->
  <div class="hint-button-container">
    {#if showHintCost}
      <div class="cost-indicator">(-$150)</div>
    {/if}
    <button 
      class="hint-button {fundsLow ? 'disabled-purchase' : ''} {hintPending ? 'pending' : ''}"
      on:click={toggleHintPurchase}
      disabled={fundsLow}
      aria-label="Buy a hint for $150"
    >
      Hint
    </button>
  </div>

<!-- Main Guess Button -->
<div class="main-guess-button-container">
  <button
    class="guess-phrase-button 
      {purchasePending ? 'pending' : ''} 
      {guessModeActive && !guessComplete ? 'exit-mode' : ''} 
      {guessComplete ? 'guess-complete' : ''}"
    on:click={handleMainButtonClick}
    disabled={noGuessesLeft && !purchasePending}
    aria-label={buttonLabel}
  >
    {buttonLabel}
  </button>
</div>

  <!-- Extra Guess Button -->
  <div class="extra-guess-button-container">
    {#if showGuessCost}
      <div class="cost-indicator">-$150</div>
    {/if}
    <button 
      class="buy-guess-button {fundsLow ? 'disabled-purchase' : ''} {guessPending ? 'pending' : ''}"
      on:click={toggleGuessPurchase}
      disabled={fundsLow}
      aria-label="Buy an extra guess for $150"
    >
      Buy Guess
    </button>
  </div>
</div>


<style>
  @import url('https://fonts.googleapis.com/css2?family=VT323&display=swap');

  /* Overall container for independent button control */
  .buttons-container {
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 20px;
    margin: 20px 0;
  }

  /* Each button container is independent */
  .hint-button-container,
  .main-guess-button-container,
  .extra-guess-button-container {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .cost-indicator {
    position: absolute;
    top: -30px;
    font-size: 16px;
    font-weight: bold;
    font-family: 'VT323', sans-serif; /* Arcade-style font */
    color: red;
    white-space: nowrap; /* 🔹 Prevents text from breaking into a new line */
    display: inline-block; /* 🔹 Forces it to stay as a single unit */
    text-align: center; /* Centers the text */
  }

  /* ---------------------------
     Hint Button Styles
  --------------------------- */
  .hint-button {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    border: none;
    cursor: pointer;
    margin-top: -10px;
    color: #fff;
    font-weight: bold;
    text-align: center;
    align-items: center;
    display: flex;
    justify-content: center;
    font-size: 10px;
    font-family: 'VT323', sans-serif; /* Arcade-style font */
    text-transform: uppercase;
    transition: transform 0.2s ease, box-shadow 0.2s ease;
    box-sizing: border-box;
    background: radial-gradient(circle at 30% 30%, #4488ff, #0055bb 80%);
    box-shadow: 0 0 4px #0055bb, 0 0 8px #4488ff, 0 0 12px rgba(0, 85, 187, 0.9);
    border: 3px solid #0033aa;
  }
  .hint-button:hover {
    transform: translateY(-2px);
  }
  .hint-button:active {
    transform: translateY(2px);
  }
  .hint-button.pending {
    animation: tightArcadeGlow 0.3s infinite alternate ease-in-out;
  }

  /* ---------------------------
     Extra Guess Button Styles
  --------------------------- */
  .buy-guess-button {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    margin-top: -10px;
    border: none;
    cursor: pointer;
    color: #fff;
    font-weight: bold;
    text-align: center;
    font-size: 10px;
    font-family: 'VT323', sans-serif; /* Arcade-style font */
    text-transform: uppercase;
    transition: transform 0.2s ease, box-shadow 0.2s ease;
    box-sizing: border-box;
    background: radial-gradient(circle at 30% 30%, #4488ff, #0055bb 80%);
    box-shadow: 0 0 4px #0055bb, 0 0 8px #4488ff, 0 0 12px rgba(0, 85, 187, 0.9);
    border: 3px solid #0033aa;
    display: flex;
    justify-content: center;
    align-items: center;
  }
  .buy-guess-button:hover {
    transform: translateY(-2px);
  }
  .buy-guess-button:active {
    transform: translateY(2px);
  }
  .buy-guess-button.pending {
    animation: tightArcadeGlow 0.3s infinite alternate ease-in-out;
  }

  /* ---------------------------
     Main Guess Button Styles
  --------------------------- */
  .guess-phrase-button {
    background: linear-gradient(180deg, #ff9800, #e65100); /* Gradient for depth */    color: white;
    padding: 6px 15px;
    width: 230px;
    min-height: 40px;
    border: none;
    border-radius: 8px;
    font-size: 25px;
    margin-top: -10px;
    font-family: 'VT323', sans-serif; /* Arcade-style font */
    font-weight: bold;
    cursor: pointer;
    text-transform: uppercase;
    transition: background-color 0.3s, transform 0.2s;
    box-sizing: border-box;
    /* 🔹 3D Border and Shadow */
    border: 3px solid #ff6f00;
    box-shadow:
      inset 2px 2px 5px rgba(255, 255, 255, 0.3), /* 🔹 Inner highlight */
      3px 3px 8px rgba(0, 0, 0, 0.6), /* 🔹 Outer shadow */
      5px 5px 12px rgba(0, 0, 0, 0.4); /* 🔹 Soft depth shadow */
  }

  /* 🔹 Hover Effect - Slight Lift */
  .guess-phrase-button:hover {
    transform: translateY(-2px);
    background: linear-gradient(180deg, #ffa726, #ef6c00);
    box-shadow:
      inset 2px 2px 6px rgba(255, 255, 255, 0.5), /* 🔹 Stronger inner glow */
      3px 3px 10px rgba(0, 0, 0, 0.8),
      6px 6px 16px rgba(0, 0, 0, 0.5);
  }

  /* 🔹 Pressed Effect - Button Looks "Pressed In" */
  .guess-phrase-button:active {
    transform: translateY(2px);
    background: linear-gradient(180deg, #e65100, #bf360c);
    box-shadow:
      inset -2px -2px 6px rgba(0, 0, 0, 0.6), /* 🔹 Darker inner shadow */
      1px 1px 4px rgba(0, 0, 0, 0.5);
      
  }

  /* 🔹 Blinking Green Animation for Pending */
  .guess-phrase-button.pending {
  background: linear-gradient(180deg, #28a745, #218838) !important;
  color: white !important;
  border: 3px solid #1e7e34 !important;
  animation: blinkGreen 1s infinite;
}

  .guess-phrase-button:hover {
    background-color: darkorange;
  }
  .guess-phrase-button:active {
    transform: scale(0.98);
    
  }
  .guess-phrase-button.pending {
    background-color: green !important;
    color: white !important;
    animation: blinkGreen 1s infinite;
  }

  .guess-phrase-button.guess-complete {
  background: #28a745 !important;
  color: white !important;
  border: 3px solid #1e7e34 !important;
  animation: blinkGreen 1s infinite alternate !important;
}
  

  /* ---------------------------
     Animations
  --------------------------- */
  @keyframes tightArcadeGlow {
  0% {
    box-shadow:
      0 0 3px #66aaff,
      0 0 5px #3388ff,
      0 0 7px rgba(195, 199, 205, 0.5);
    border: 1px solid #b8bdc6;
  }
  100% {
    box-shadow:
      0 0 4px #4488ff,
      0 0 7px #0055bb,
      0 0 9px rgba(0, 85, 187, 0.7);
    border: 1px solid #a4abb4;
  }
}

/* Apply the updated animation to the hint button when pending */
.hint-button.pending {
  animation: tightArcadeGlow 0.3s infinite alternate ease-in-out;
}
  @keyframes blinkGreen {
    0% { background-color: green; }
    50% { background-color: #00cc00; }
    100% { background-color: green; }
  }

  /* ---------------------------
     Disabled / Purchase States
  --------------------------- */
  .disabled-purchase {
    opacity: 0.7;
    filter: blur(.8px);
    pointer-events: none;
  }

  /* ---------------------------
     Dark Mode Overrides
  --------------------------- */
  :global(body.dark-mode) .hint-button,
  :global(body.dark-mode) .buy-guess-button {
    background-color: #007bff !important;
    border: 3px solid #ff8f00;
    box-shadow:
      inset 2px 2px 6px rgba(255, 255, 255, 0.2),
      3px 3px 10px rgba(0, 0, 0, 0.7),
      6px 6px 16px rgba(0, 0, 0, 0.5);
    color: white !important;
    border: none !important;
  }
  /* 🔹 Dark Mode Hover Effect */
  :global(body.dark-mode) .guess-phrase-button:hover {
    transform: translateY(-2px);
    background: linear-gradient(180deg, #ffcc80, #ff9800);
    box-shadow:
      inset 2px 2px 5px rgba(255, 255, 255, 0.3),
      3px 3px 14px rgba(0, 0, 0, 0.9),
      6px 6px 18px rgba(0, 0, 0, 0.6);
  }

  /* 🔹 Dark Mode Pressed Effect */
  :global(body.dark-mode) .guess-phrase-button:active {
    transform: translateY(2px);
    background: linear-gradient(180deg, #e65100, #bf360c);
    box-shadow:
      inset -2px -2px 6px rgba(0, 0, 0, 0.8),
      1px 1px 5px rgba(0, 0, 0, 0.6);
  }
  :global(body.dark-mode) .guess-phrase-button {
    background: linear-gradient(180deg, #ffa726, #e65100);
    color: white !important;
    border: none !important;
  }
  :global(body.dark-mode) button,
  :global(body.dark-mode) .key {
    background-color: inherit !important;
    color: inherit !important;
    box-shadow: none !important;
  }
  :global(body.dark-mode) button.pending,
  :global(body.dark-mode) .key.pending {
    animation: blinkGreen 1s infinite;
    background-color: green !important;
    color: #fff !important;
  }
  :global(body.dark-mode) .hint-button,
  :global(body.dark-mode) .buy-guess-button {
    background: radial-gradient(circle at 30% 30%, #66aaff, #3388ff 80%) !important;
    box-shadow: 0 0 6px #3388ff, 0 0 10px #66aaff, 0 0 14px rgba(0, 170, 255, 0.9) !important;
    border: 3px solid #66aaff !important;
  }
  :global(body.dark-mode) .hint-button.pending,
  :global(body.dark-mode) .buy-guess-button.pending {
    animation: tightArcadeGlowDark 0.3s infinite alternate ease-in-out !important;
  }
  @keyframes tightArcadeGlowDark {
    0% {
      box-shadow: 0 0 6px #aaffff, 0 0 10px #66ffff, 0 0 14px rgba(0, 170, 255, 0.8);
      border: 3px solid #66ffff !important;
    }
    100% {
      box-shadow: 0 0 8px #66aaff, 0 0 14px #3388ff, 0 0 18px rgba(0, 170, 255, 0.9);
      border: 3px solid #aaffff !important;
    }
  }

  /* 🔹 Exit Guess Mode Button Turns Red */
.guess-phrase-button.exit-mode {
    background: linear-gradient(180deg, #ff4444, #cc0000); /* Red gradient */
    color: white !important;
    border: 3px solid darkred !important;
    transition: background-color 0.3s ease, transform 0.2s ease;
}

/* 🔹 Press Effect */
.guess-phrase-button.exit-mode:active {
    background: linear-gradient(180deg, #cc0000, #990000);
    transform: scale(0.95);
}

  
</style>
