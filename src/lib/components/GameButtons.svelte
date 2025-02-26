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

  let darkMode = false; // ✅ Ensure it's declared

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
    ? "Confirm"
    : guessModeActive
      ? (guessComplete ? "Submit" : "Cancel")
      : "Solve";
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
        gameStore.update(state => ({ ...state, gameState: "default", guessedLetters: {},
        selectedPurchase: null, 
      }));
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
  
  <!-- 🔹 Hint Button (Glows Only When Selected) -->
  <div class="hint-button-container">
    {#if showHintCost}
      <div class="cost-indicator">$150</div>
    {/if}
    <button 
      class="hint-button {fundsLow ? 'disabled-purchase' : ''} {hintPending ? 'glow' : ''}"
      on:click={toggleHintPurchase}
      disabled={fundsLow}
      aria-label="Buy a hint for $150"
    >
      Bank Letter
    </button>
  </div>

  <!-- 🔹 Solve Button (Blurs When No Guesses & Not in Purchase Mode) -->
  <div class="main-guess-button-container">
    <button
      class="guess-phrase-button 
        {purchasePending ? 'pending' : ''} 
        {guessModeActive && !guessComplete ? 'exit-mode' : ''} 
        {guessComplete ? 'guess-complete' : ''} 
        {noGuessesLeft && !purchasePending ? 'disabled-purchase' : ''}"
      on:click={handleMainButtonClick}
      disabled={noGuessesLeft && !purchasePending}
      aria-label={buttonLabel}
    >
      {buttonLabel}
    </button>
  </div>

  <!-- 🔹 Extra Guess Button (Always Visible, Blurred When Guesses > 0) -->
  <div class="extra-guess-button-container">
    {#if showGuessCost}
      <div class="cost-indicator">$150</div>
    {/if}
    <button 
      class="buy-guess-button 
        {fundsLow || !noGuessesLeft ? 'disabled-purchase' : ''} 
        {guessPending ? 'glow' : ''}"
      on:click={toggleGuessPurchase}
      disabled={fundsLow || !noGuessesLeft}
      aria-label="Buy an extra guess for $150"
    >
      +1
    </button>
  </div>

</div>


<style>
  @import url('https://fonts.googleapis.com/css2?family=VT323&display=swap');

  /* ---------------------------
     Additional New Effects
  --------------------------- */

/* 🔹 Intense Green Glow Effect (Applies Only When Button is Selected for Purchase) */
@keyframes softGlow {
  0% { box-shadow: 0 0 8px #ffffff, 0 0 16px #318020, 0 0 24px #207b09; }
  50% { box-shadow: 0 0 12px #ffffff, 0 0 20px #46a230, 0 0 28px #14860a; }
  100% { box-shadow: 0 0 8px #ffffff, 0 0 16px #46a230, 0 0 24px #46a230; }
}

/* 🔹 Apply Intense Green Glow Animation When Selected */
.hint-button.glow,
.buy-guess-button.glow {
  animation: softGlow 0.3s infinite alternate ease-in-out; /* Faster flicker */
  border: 3px outset #0d3e01 !important;
}

  /* 🔹 Disabled Purchase (Blurred Out) */
  .disabled-purchase {
    opacity: 0.5;
    filter: blur(1px);
    pointer-events: none;
  }

  /* ---------------------------
     Overall Layout & Container Styles
  --------------------------- */
  .buttons-container {
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 20px;
    margin: 20px 0;
  }

  .hint-button-container,
  .main-guess-button-container,
  .extra-guess-button-container {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  @keyframes blinkColor {
    0% { color: red; opacity: 1; } 
    50% { color: white; opacity: 0.5; } 
    100% { color: red; opacity: 1; } 
  }

  .cost-indicator {
    position: absolute;
    top: 100px;
    font-size: 20px;
    font-weight: bold;
    font-family: 'VT323', sans-serif; /* Arcade-style font */
    color: red;
    white-space: nowrap;
    display: inline-block;
    text-align: center;
    animation: blinkColor 1s infinite;
  }

  /* ---------------------------
     Hint Button Styles
  --------------------------- */
  .hint-button {
    width: 50px;
    height: 50px;
    border-radius: 50%;
    cursor: pointer;
    margin-top: 130px;
    margin-right: 0px;
    color: #fff;
    font-weight: bold;
    text-align: center;
    align-items: center;
    display: flex;
    justify-content: center;
    font-size: 10px;
    font-family: 'VT323', sans-serif;
    text-transform: uppercase;
    transition: transform 0.2s ease, box-shadow 0.2s ease;
    box-sizing: border-box;
    background: radial-gradient(circle at 30% 30%, #4488ff, #0055bb 80%);
  }
  .hint-button:hover {
    transform: translateY(-2px);
  }
  .hint-button:active {
    transform: translateY(2px);
  }

  /* ---------------------------
     Extra Guess Button Styles
  --------------------------- */
  .buy-guess-button {
    width: 50px;
    height: 50px;
    border-radius: 50%;
    margin-top: 130px;
    margin-left: 0px;
    cursor: pointer;
    color: #fff;
    font-weight: bold;
    text-align: center;
    font-size: 20px;
    font-family: 'VT323', sans-serif;
    text-transform: uppercase;
    transition: transform 0.2s ease, box-shadow 0.2s ease;
    box-sizing: border-box;
    background: radial-gradient(circle at 30% 30%, #4488ff, #0055bb 80%);
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

  /* 🔹 Intense Blinking Animation for Buy Guess Button */
  @keyframes intenseBlink {
    0% { opacity: 1; box-shadow: 0 0 8px #ffffff, 0 0 16px #ff3333; }
    50% { opacity: 0.4; box-shadow: 0 0 4px #ffffff, 0 0 8px #ff6666; }
    100% { opacity: 1; box-shadow: 0 0 8px #ffffff, 0 0 16px #ff3333; }
  }

  /* ---------------------------
     Main Guess Button Styles
  --------------------------- */
  .guess-phrase-button {
    background: linear-gradient(180deg, #46a230, #318020);   
    color: white;
    padding: 6px 15px;
    width: 230px;
    min-height: 50px;
    border-radius: 8px;
    font-size: 25px;
    margin-top: 130px;
    font-family: 'VT323', sans-serif;
    font-weight: bold;
    cursor: pointer;
    text-transform: uppercase;
    transition: background-color 0.3s, transform 0.2s;
    box-sizing: border-box;
    border: 3px solid #2e9417 !important;
    box-shadow:
      inset 2px 2px 5px rgba(255, 255, 255, 0.3),
      3px 3px 8px rgba(0, 0, 0, 0.6),
      5px 5px 12px rgba(0, 0, 0, 0.4);
  }
  .guess-phrase-button:not(.exit-mode) {
    background: linear-gradient(180deg, #46a230, #318020) !important;
  }
  .guess-phrase-button.disabled-blur {
    opacity: 0.5;
    filter: blur(1px);
    pointer-events: none;
    cursor: not-allowed;
  }
  .guess-phrase-button:hover {
    transform: translateY(-2px);
    background: linear-gradient(180deg, #6b82f0, #4b63d2);
    box-shadow:
      inset 2px 2px 6px rgba(255, 255, 255, 0.3),
      3px 3px 8px rgba(0, 0, 0, 0.6),
      5px 5px 12px rgba(0, 0, 0, 0.4);
  }
  .guess-phrase-button:active {
    transform: translateY(2px);
    background: linear-gradient(180deg, #3a52c4, #2a41a5);
    box-shadow:
      inset -2px -2px 6px rgba(0, 0, 0, 0.6),
      1px 1px 4px rgba(0, 0, 0, 0.5);
  }
  .guess-phrase-button.pending {
    background: linear-gradient(180deg, #2e7d32, #1b5e20) !important;
    color: white !important;
    border: 3px solid #144d17 !important;
    animation: blinkDarkGreen 1s infinite alternate ease-in-out;
  }
  .guess-phrase-button:hover {
    background-color: darkorange;
  }
  .guess-phrase-button:active {
    transform: scale(0.98);
  }
  @keyframes blinkDarkGreen {
    0% { background-color: #2e7d32; }
    50% { background-color: #1b5e20; }
    100% { background-color: #2e7d32; }
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

  @keyframes blinkGreen {
    0% { background-color: green; }
    50% { background-color: #00cc00; }
    100% { background-color: green; }
  }

  /* ---------------------------
     Dark Mode Overrides
  --------------------------- */
  :global(body.dark-mode) .guess-phrase-button {
    background: linear-gradient(180deg, #46a230, #318020);
  }
  :global(body.dark-mode) .hint-button,
  :global(body.dark-mode) .buy-guess-button {
    background: radial-gradient(circle at 30% 30%, #66aaff, #3388ff 80%) !important;
    border: 3px solid #66aaff !important;
  }

  .guess-phrase-button.exit-mode {
    background: linear-gradient(180deg, #ff2222, #aa0000);
    color: white !important;
    border: 3px solid darkred !important;
    transition: background-color 0.3s ease, transform 0.2s ease;
    animation: glowRed 1.5s infinite alternate ease-in-out;
  }
  .guess-phrase-button.exit-mode:active {
    background: linear-gradient(180deg, #cc0000, #990000);
    transform: scale(0.95);
  }
  :global(body.dark-mode) .guess-phrase-button.exit-mode {
    background: linear-gradient(180deg, #ff2222, #aa0000) !important;
    border: 3px solid #880000 !important;
  }
  :global(body.dark-mode) .guess-phrase-button.guess-complete {
    background: linear-gradient(180deg, #28a745, #218838) !important;
    animation: glowGreen 1.5s infinite alternate ease-in-out;
    border: 3px solid #1e7e34 !important;
  }
</style>
