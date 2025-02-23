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

  // ----------------------------
  // LOCAL UI STATE
  // ----------------------------
  let showHowToPlay = false;
  let darkMode = false;

  // ----------------------------
  // REACTIVE DERIVATIONS FROM GAME STORE
  // ----------------------------
  // Purchase-related flags
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

  // Dynamic label for the main action button based on state:
  // - If a purchase is pending → "Confirm Purchase"
  // - Else if in guess mode:
  //    • If complete → "Submit Guess"
  //    • Else → "Exit Guess Mode"
  // - Otherwise → "Guess (x)" where x is the number of remaining guesses.
  $: buttonLabel = purchasePending
    ? "Confirm Purchase"
    : guessModeActive
      ? (guessComplete ? "Submit Guess" : "Exit Guess Mode")
      : `Guess (${$gameStore.guessesRemaining})`;

  // ----------------------------
  // EVENT HANDLERS
  // ----------------------------

  /**
   * handleMainButtonClick
   * Main action button handler:
   * - If a purchase is pending, confirms it.
   * - In guess mode, submits the guess if complete or exits guess mode.
   * - Otherwise, enters guess mode.
   */
  function handleMainButtonClick() {
    if (purchasePending) {
      confirmPurchase();
      return;
    }

    if (guessModeActive) {
      if (guessComplete) {
        submitGuess();
      } else {
        // Exit guess mode if the guess is incomplete
        gameStore.update(state => ({ ...state, gameState: "default", guessedLetters: {} }));
      }
      return;
    }

    // If not in guess mode and no purchase pending, enter guess mode
    if (!purchasePending && !guessModeActive) {
      enterGuessMode();
    }
  }

  /**
   * toggleHintPurchase
   * Toggles hint purchase selection.
   */
  function toggleHintPurchase() {
    gameStore.update(state => {
      if (state.selectedPurchase?.type === "hint") {
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      return { ...state, selectedPurchase: { type: "hint" }, gameState: "purchase_pending" };
    });
    setTimeout(() => document.activeElement.blur(), 0);
  }

  /**
   * toggleGuessPurchase
   * Toggles extra guess purchase selection.
   */
  function toggleGuessPurchase() {
    gameStore.update(state => {
      if (state.selectedPurchase?.type === "extra_guess") {
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      return { ...state, selectedPurchase: { type: "extra_guess" }, gameState: "purchase_pending" };
    });
    setTimeout(() => document.activeElement.blur(), 0);
  }

  /**
   * toggleDarkMode
   * Toggles dark mode for the UI and saves preference in localStorage.
   */
  function toggleDarkMode() {
    darkMode = !darkMode;
    document.body.classList.toggle('dark-mode', darkMode);
    localStorage.setItem('darkMode', darkMode);
  }

  // ----------------------------
  // GLOBAL KEY LISTENER (for Enter key)
  // ----------------------------
  onMount(() => {
    // Initialize dark mode based on stored preference
    darkMode = localStorage.getItem('darkMode') === 'true';
    document.body.classList.toggle('dark-mode', darkMode);

    const onKeyDown = (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        // Do nothing if a purchase is pending (forcing explicit button click)
        if ($gameStore.selectedPurchase) return;

        if ($gameStore.gameState === "guess_mode") {
          if (guessComplete) {
            submitGuess();
          } else {
            gameStore.update(state => ({ ...state, gameState: "default", guessedLetters: {} }));
          }
        } else {
          // If not in purchase or guess mode, enter guess mode
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
{#if guessModeActive}
  <div class="guess-mode-banner">
    Fill every phrase box to submit.<br />
    Correct guesses will remain!
  </div>
{/if}

{#if $gameStore.message}
  <div class="message-box">{$gameStore.message}</div>
{/if}

<div class="guess-controls">
  <!-- Hint Purchase Button -->
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

  <!-- Main Action Button -->
  <button
    class="guess-phrase-button"
    class:pending={purchasePending}
    class:confirm-purchase={purchasePending}
    class:exit-mode={guessModeActive && !guessComplete}
    class:guess-complete={guessComplete}
    on:click={handleMainButtonClick}
    disabled={noGuessesLeft && !purchasePending}
    aria-label={buttonLabel}
  >
    {buttonLabel}
  </button>

  <!-- Extra Guess Purchase Button -->
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

<!-- Top Controls -->
<div class="top-buttons">
  <button class="how-to-play-button" on:click={() => (showHowToPlay = true)} aria-label="How to Play Instructions">
    How to Play
  </button>
  <button class="dark-mode-button" on:click={toggleDarkMode} aria-label="Toggle Dark Mode">
    {darkMode ? "☀️" : "🌙"}
  </button>
</div>

<!-- How To Play Modal -->
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
     Cost Indicator Styles
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
     Global Reset & Utility Styles
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
     Guess Controls & Main Button Styles
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
  .guess-phrase-button {
    background-color: orange;
    color: white;
    padding: 12px 30px;
    min-width: 180px;
    min-height: 60px; /* Set a wider minimum width */
    border: none;
    border-radius: 5px;
    font-size: 14px;
    font-weight: bold;
    cursor: pointer;
    text-transform: uppercase;
    transition: background-color 0.3s, transform 0.2s;
    box-sizing: border-box;
    margin-top: 30px;
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
  @keyframes blinkGreen {
    0% { background-color: green; }
    50% { background-color: #00cc00; }
    100% { background-color: green; }
  }

  /* ---------------------------
     Hint & Extra Guess Button Styles
  --------------------------- */
  .hint-button,
  .buy-guess-button {
    width: 35px;
    height: 35px;
    border-radius: 50%;
    border: none;
    cursor: pointer;
    color: #fff;
    font-weight: bold;
    text-align: center;
    margin: 0 20px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 8px;
    text-transform: uppercase;
    transition: transform 0.2s ease, box-shadow 0.2s ease;
    box-sizing: border-box;
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
  animation: blinkGreen 1s infinite; /* or none if you prefer */
  background-color: green !important; /* or another dark-mode-friendly color */
  color: #fff !important; /* ensure the text is still visible */
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
</style>
