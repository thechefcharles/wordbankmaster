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

  // Local UI state variables
  let showHowToPlay = false;
  let darkMode = false;

  // Reactive declarations based on the global gameStore
  $: showHintCost = $gameStore.selectedPurchase?.type === 'hint' && $gameStore.gameState === 'purchase_pending';
  $: showGuessCost = $gameStore.selectedPurchase?.type === 'extra_guess' && $gameStore.gameState === 'purchase_pending';
  $: noGuessesLeft = $gameStore.guessesRemaining === 0;
  $: guessModeActive = $gameStore.gameState === 'guess_mode';
  $: bankroll = $gameStore.bankroll;
  $: fundsLow = bankroll < 150;
  $: hintPending = $gameStore.selectedPurchase?.type === 'hint' && $gameStore.gameState === 'purchase_pending';
  $: guessPending = $gameStore.selectedPurchase?.type === 'extra_guess' && $gameStore.gameState === 'purchase_pending';

  // Determine if any purchase is pending
  $: purchasePending = !!$gameStore.selectedPurchase;

  // Determine if all guess slots are filled in guess mode
  $: guessComplete = guessModeActive && (() => {
    const phrase = $gameStore.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if ($gameStore.purchasedLetters[i] === phrase[i]) continue;
      if (!$gameStore.guessedLetters[i]) return false;
    }
    return true;
  })();

  // Dynamic label for the main action button:
  // - If a purchase is pending, show "Confirm Purchase"
  // - Else if in guess mode:
  //    • if complete, show "Submit Guess"
  //    • else, show "Exit Guess Mode"
  // - Otherwise, show "Guess (x)" where x is the remaining guesses.
  $: buttonLabel = purchasePending
    ? "Confirm Purchase"
    : guessModeActive
      ? (guessComplete ? "Submit Guess" : "Exit Guess Mode")
      : `Guess (${$gameStore.guessesRemaining})`;

  // Main button click handler (acts as Enter/Submit/Exit/Confirm)
  function handleMainButtonClick() {
  if (purchasePending) {
    // Confirm the purchase and ensure the game does NOT enter guess mode
    confirmPurchase();
    return; // Exit early so it doesn't fall through to guess mode
  }

  if (guessModeActive) {
    if (guessComplete) {
      // Submit the guess if all slots are filled
      submitGuess();
    } else {
      // Exit guess mode if incomplete
      gameStore.update(state => ({ ...state, gameState: "default", guessedLetters: {} }));
    }
    return;
  }

  // If no purchase is pending and not already in guess mode, enter guess mode
  if (!purchasePending && !guessModeActive) {
    enterGuessMode();
  }
}

  // Toggle Hint Selection (with forced blur)
  function toggleHintPurchase() {
    gameStore.update(state => {
      if (state.selectedPurchase?.type === "hint") {
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      return { ...state, selectedPurchase: { type: "hint" }, gameState: "purchase_pending" };
    });
    setTimeout(() => document.activeElement.blur(), 0);
  }

  // Toggle Extra Guess Selection (with forced blur)
  function toggleGuessPurchase() {
    gameStore.update(state => {
      if (state.selectedPurchase?.type === "extra_guess") {
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      return { ...state, selectedPurchase: { type: "extra_guess" }, gameState: "purchase_pending" };
    });
    setTimeout(() => document.activeElement.blur(), 0);
  }

  // Toggle dark mode and store preference
  function toggleDarkMode() {
    darkMode = !darkMode;
    document.body.classList.toggle('dark-mode', darkMode);
    localStorage.setItem('darkMode', darkMode);
  }

  // Set up key listener on mount (Enter key triggers the main action)
  onMount(() => {
  darkMode = localStorage.getItem('darkMode') === 'true';
  document.body.classList.toggle('dark-mode', darkMode);

  const onKeyDown = (event) => {
    if (event.key === 'Enter') {
      event.preventDefault(); // Prevent accidental form submission or unwanted behavior

      // Ensure Enter key mimics the onscreen button behavior
      gameStore.update(state => {
        if (state.selectedPurchase) {
          confirmPurchase();
          return { ...state, gameState: "default" }; // Ensure we do NOT enter guess mode
        }

        if (state.gameState === "guess_mode") {
          return state.guessedLetters && Object.keys(state.guessedLetters).length > 0
            ? submitGuess()
            : { ...state, gameState: "default", guessedLetters: {} };
        }

        // If not in purchase or guess mode, enter guess mode
        return { ...state, gameState: "guess_mode", guessedLetters: {} };
      });
    }
  };

  window.addEventListener('keydown', onKeyDown);
  return () => window.removeEventListener('keydown', onKeyDown);
});
</script>

<!-- If in guess mode, display a banner -->
{#if guessModeActive}
  <div class="guess-mode-banner">
    Fill every phrase box to submit.<br />
    Correct guesses will remain!
  </div>
{/if}

<!-- Display any feedback message -->
{#if $gameStore.message}
  <div class="message-box">{$gameStore.message}</div>
{/if}

<!-- Render the purchase controls -->
<div class="guess-controls">
  <!-- Hint Button + Cost Indicator -->
  <div class="button-container">
    {#if showHintCost}
      <div class="cost-indicator">-$150</div>
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

<!-- Dynamic Main Action Button -->
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

  <!-- Buy Extra Guess Button + Cost Indicator -->
  <div class="button-container">
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

<!-- Top Buttons: "How to Play" and Dark Mode Toggle -->
<div class="top-buttons">
  <button class="how-to-play-button" on:click={() => (showHowToPlay = true)} aria-label="How to Play Instructions">
    How to Play
  </button>
  <button class="dark-mode-button" on:click={toggleDarkMode} aria-label="Toggle Dark Mode">
    {darkMode ? "☀️" : "🌙"}
  </button>
</div>

<!-- "How to Play" Modal -->
{#if showHowToPlay}
  <div class="modal-overlay" role="dialog" aria-modal="true">
    <div class="modal-content">
      <h2>📜 How to Play</h2>
      <p>
        💰 <b>You start with $1000.</b> Use it wisely to <b>buy letters, get hints, and guess the phrase!</b>
      </p>
      <h3>🎯 Goal</h3>
      <p>Solve the phrase <b>before running out of money!</b></p>
      <h3>🕹️ Gameplay</h3>
      <ul>
        <li>🔤 Click/tap letters to buy them.</li>
        <li>⏎ Press Enter to confirm purchases or submit a guess.</li>
        <li>🔄 Press Space to toggle Guess Mode.</li>
        <li>💡 Hints ($150) – Reveal a random letter.</li>
        <li>🎟️ Extra Guess ($150) – Buy another shot.</li>
      </ul>
      <p><b>Think smart, spend wisely, and guess like a pro!</b> 🚀</p>
      <button class="close-btn" on:click={() => (showHowToPlay = false)} aria-label="Close How to Play">
        Close
      </button>
    </div>
  </div>
{/if}

<style>
  /* ---------------------------
     Cost Indicator
  --------------------------- */
  .button-container {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .cost-indicator {
    position: absolute;
    top: -20px;
    color: red;
    font-size: 16px;
    font-weight: bold;
  }
  @keyframes fadeOut {
    0% { opacity: 1; transform: translateY(0); }
    50% { opacity: 0.8; transform: translateY(-5px); }
    100% { opacity: 0; transform: translateY(-10px); }
  }

  /* ---------------------------
     Global Reset & Utility
  --------------------------- */
  button:focus {
    outline: none;
  }
  :global(html, body) {
    overflow-x: hidden;
    touch-action: manipulation;
  }

  /* ---------------------------
     Top Buttons & Modal Styles
  --------------------------- */
  .top-buttons {
    position: absolute;
    top: 5px;
    left: 5px;
    right: 5px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 10px;
  }
  .how-to-play-button {
    background-color: #f0f0f0;
    border: 1px solid #ccc;
    padding: 4px 8px;
    font-size: 10px;
    border-radius: 1px;
    cursor: pointer;
    transition: background-color 0.3s;
    margin: 0;
  }
  .how-to-play-button:hover {
    background-color: #e0e0e0;
  }
  .dark-mode-button {
    background: none;
    border: none;
    font-size: 20px;
    cursor: pointer;
    padding: 5px;
    margin: 0;
  }
  .modal-overlay {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    justify-content: center;
    align-items: center;
    z-index: 1000;
  }
  .modal-content {
    background: white;
    padding: 20px;
    border-radius: 8px;
    width: 80%;
    max-width: 400px;
    text-align: center;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
  }
  .close-btn {
    margin-top: 10px;
    padding: 10px 20px;
    border: none;
    background: red;
    color: white;
    cursor: pointer;
    border-radius: 5px;
    transition: background-color 0.3s;
  }
  .close-btn:hover {
    background: darkred;
  }

  /* ---------------------------
     Guess Controls & Unified Button Styles
  --------------------------- */
  .guess-controls {
    display: flex;
    justify-content: space-between;
    align-items: center;
    width: 100%;
    max-width: 400px;
    margin: 10px auto;
    gap: 8px;
  }
  /* Main Action Button */
  .guess-phrase-button {
    background-color: orange;
    color: white;
    padding: 10px 20px;
    border: none;
    border-radius: 5px;
    font-size: 14px;
    font-weight: bold;
    cursor: pointer;
    text-transform: uppercase;
    transition: background-color 0.3s, transform 0.2s;
    box-sizing: border-box;
  }
  .guess-phrase-button:hover {
    background-color: darkorange;
  }
  .guess-phrase-button:active {
    transform: scale(0.98);
  }
  /* When a purchase is pending, turn the main action button green and blink */
  .guess-phrase-button.pending {
    background-color: green !important;
    color: white !important;
    animation: blinkGreen 1s infinite;
  }
  @keyframes blinkGreen {
    0% { background-color: green; }
    50% { background-color: #00cc00; }
    100% { background-color: green; }
  }

  /* Hint & Buy Guess Buttons (Circular) */
  .hint-button,
  .buy-guess-button {
    width: 25px;
    height: 25px;
    border-radius: 50%;
    border: none;
    cursor: pointer;
    color: #fff;
    font-weight: bold;
    text-align: center;
    margin-left: 20px;
    margin-right: 20px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 6px;
    text-transform: uppercase;
    transition: transform 0.2s ease, box-shadow 0.2s ease;
    box-sizing: border-box;
  }
  .hint-button,
  .buy-guess-button {
    background: radial-gradient(circle at 30% 30%, #4488ff, #0055bb 80%);
    box-shadow: 0 4px 0 #003366, 0 6px 20px rgba(0, 0, 0, 0.4);
  }
  .hint-button:hover,
  .buy-guess-button:hover {
    transform: translateY(-2px);
  }
  .hint-button:active,
  .buy-guess-button:active {
    transform: translateY(2px);
  }
  .disabled-red, .disabled-purchase {
    opacity: 0.5;
    filter: blur(1px);
    pointer-events: none;
  }

  /* ---------------------------
     Dark Mode Overrides
  --------------------------- */
  :global(body.dark-mode) .hint-button,
  :global(body.dark-mode) .buy-guess-button {
    background-color: #007bff !important;
    color: white !important;
    border: none !important;
  }
  :global(body.dark-mode) .guess-phrase-button {
    background-color: orange !important;
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
    animation: none !important;
    background-color: inherit !important;
  }
  .buy-guess-button:focus,
  .hint-button:focus,
  .guess-phrase-button:focus {
    outline: none;
    box-shadow: none;
  }
  .buy-guess-button:focus,
  .hint-button:focus {
    background-color: #007bff !important;
    color: white !important;
  }
  .guess-phrase-button:focus {
    background-color: orange !important;
    color: white !important;
  }
  :global(body:not(.dark-mode)) .key .letter,
  :global(body:not(.dark-mode)) .key .letter.selected,
  :global(body:not(.dark-mode)) .key .letter.pending {
    color: #000 !important;
  }

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

  /* Key Styles */
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
     Phrase Container & Boxes
  --------------------------- */
  .guess-phrase-container {
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 4px;
    width: 100%;
    max-width: 800px;
    padding: 10px 0;
  }
  .guess-phrase {
    flex-grow: 1;
    flex-basis: calc(100% / var(--phrase-length));
    min-width: 30px;
    max-width: 60px;
    height: 60px;
    font-size: clamp(1.4rem, 3vw, 2.2rem);
    text-align: center;
    border: 3px solid black;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 5px;
    transition: all 0.2s ease-in-out;
  }
  @media (max-width: 500px) {
    .guess-phrase {
      min-width: 25px;
      max-width: 45px;
      height: 50px;
      font-size: 1.2rem;
    }
  }
  @media (max-width: 400px) {
    .guess-phrase {
      min-width: 22px;
      max-width: 40px;
      height: 45px;
      font-size: 1rem;
    }
  }

  /* ---------------------------
     Message & Banner
  --------------------------- */
  .message-box {
    margin-top: 10px;
    background: red;
    color: white;
    padding: 10px 20px;
    font-weight: bold;
    border-radius: 5px;
    text-align: center;
    animation: fadeOut 2s ease-in-out;
  }
  @keyframes fadeOut {
    0% { opacity: 1; transform: translateY(0); }
    50% { opacity: 0.8; transform: translateY(-5px); }
    100% { opacity: 0; transform: translateY(-10px); }
  }
  .guess-mode-banner {
    background-color: rgba(255, 8, 8, 0.641);
    color: white;
    font-size: 0.6rem;
    font-weight: bold;
    text-align: center;
    padding: 10px;
    border-radius: 5px;
    margin: 0 auto 10px;
    display: flex;
    justify-content: center;
    align-items: center;
    width: 80%;
    max-width: 600px;
    min-width: 300px;
    animation: fadeIn 0.3s ease-in-out;
  }
  @keyframes fadeIn {
    from { opacity: 0; transform: scale(0.95); }
    to { opacity: 1; transform: scale(1); }
  }

  /* ---------------------------
     Layout: Top Section, Logo, Category & Bankroll
  --------------------------- */
  main {
    max-width: 600px;
    margin: 0 auto;
    text-align: center;
    font-family: sans-serif;
    padding: 10px;
    display: flex;
    flex-direction: column;
    align-items: center;
    position: relative;
  }
  .category {
    font-size: 1.2rem;
    margin-top: -150px;
    margin-bottom: 0;
    font-weight: bold;
  }
  .bankroll-container {
    display: flex;
    justify-content: center;
    align-items: center;
    width: 100%;
    margin: 10px auto 0;
  }
  .bankroll-box {
    padding: 5px 10px;
    font-size: 1.5rem;
    font-family: 'Orbitron', sans-serif;
    color: #fff;
    background: linear-gradient(45deg, #2e7d32, #66bb6a);
    border: 3px solid #1b5e20;
    border-radius: 8px;
    text-align: center;
    box-shadow: inset 0 0 10px rgba(0, 0, 0, 0.5);
    display: inline-flex;
    justify-content: center;
    align-items: center;
  }
  .currency {
    margin-right: 4px;
  }
  .wordbank-logo {
    width: 380px;
    height: auto;
    display: block;
    margin-bottom: -60px;
    margin-top: -50px;
    padding-bottom: 0;
  }
  .logo-container {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-top: -50px;
    margin-bottom: 0;
  }
</style>
