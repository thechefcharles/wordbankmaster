<script>
  import { onMount } from 'svelte';
  import {
    gameStore,
    selectHint,
    selectExtraGuess,
    enterGuessMode
  } from '$lib/stores/GameStore.js';

  let showHowToPlay = false;
  let darkMode = false;

  // Reactive: are we out of guesses?
  $: noGuessesLeft = $gameStore.guessesRemaining === 0;

  // Reactive: is guess mode active?
  $: guessModeActive = $gameStore.gameState === 'guess_mode';

  // Reactive: current bankroll & whether it's below $150
  $: bankroll = $gameStore.bankroll;
  $: fundsLow = bankroll < 150;

  // Reactive variables to check if the Buy Guess or Hint button is pending purchase.
  $: buyGuessPending = $gameStore.selectedPurchase?.type === 'extra_guess' &&
                        $gameStore.gameState === 'purchase_pending';
  $: hintPending = $gameStore.selectedPurchase?.type === 'hint' &&
                   $gameStore.gameState === 'purchase_pending';

  // Track selected items locally (if needed for additional blinking, etc.)
  let selectedItems = new Set();

  function toggleSelection(item) {
    if (selectedItems.has(item)) {
      selectedItems.delete(item);
    } else {
      selectedItems.add(item);
    }
  }

  // On mount, load dark mode from localStorage
  onMount(() => {
    const storedMode = localStorage.getItem('darkMode');
    if (storedMode === null) {
      darkMode = true; // default to dark mode if no preference
    } else {
      darkMode = (storedMode === 'true');
    }
    document.body.classList.toggle('dark-mode', darkMode);
  });

  function toggleDarkMode() {
    darkMode = !darkMode;
    document.body.classList.toggle('dark-mode', darkMode);
    localStorage.setItem('dark-mode', darkMode ? 'true' : 'false');
  }
</script>

<!-- If in guess mode, show banner; otherwise, show Buy Guess & Hint buttons -->
{#if guessModeActive}
  <div class="guess-mode-banner">
    Guess Mode Activated! Fill every box with a letter to submit.<br />
    Correct guesses will remain!
  </div>
{:else}
  <div class="guess-hint-buttons">
    <button
      class="buy-guess-button {fundsLow ? 'disabled red' : ''} {buyGuessPending ? 'pending' : ''}"
      disabled={fundsLow}
      on:click={() => { if (!fundsLow) selectExtraGuess(); }}
    >
      Buy Guess ($150)
    </button>

    <button
      class="hint-button {fundsLow ? 'disabled red' : ''} {hintPending ? 'pending' : ''}"
      disabled={fundsLow}
      on:click={() => { if (!fundsLow) selectHint(); }}
    >
      Hint ($150)
    </button>
  </div>
{/if}

<!-- Guess Mode Button + Guesses Remaining -->
<div class="guess-phrase-container">
  <button
    class="guess-phrase-button {noGuessesLeft ? 'no-guesses' : ''}"
    on:click={enterGuessMode}
    disabled={noGuessesLeft}
  >
    Guess Mode
  </button>
  <div class="guesses-box {noGuessesLeft ? 'no-guesses' : ''}">
    {$gameStore.guessesRemaining}
  </div>
</div>

<!-- Top Buttons: "How to Play" & Dark Mode Toggle -->
<div class="top-buttons">
  <button class="how-to-play-button" on:click={() => (showHowToPlay = true)}>
    How to Play
  </button>
  <button class="dark-mode-button" on:click={toggleDarkMode}>
    {darkMode ? "☀️" : "🌙"}
  </button>
</div>

<!-- "How to Play" Modal -->
{#if showHowToPlay}
  <div
    class="modal-overlay"
    on:click={() => (showHowToPlay = false)}
    role="dialog"
    aria-modal="true"
  >
    <div class="modal-content" on:click|stopPropagation>
      <h2>📜 How to Play</h2>
      <p>
        💰 <b>You start with $1000.</b> Use it wisely to
        <b>buy letters, get hints, and guess the phrase!</b>
      </p>
      <h3>🎯 Goal</h3>
      <p>
        Solve the phrase <b>before running out of money!</b>
      </p>
      <h3>🕹️ Gameplay</h3>
      <ul>
        <li>🔤 Click/tap letters to buy them.</li>
        <li>⏎ Press Enter to confirm purchases or submit a guess.</li>
        <li>🔄 Press Space to toggle Guess Mode.</li>
        <li>💡 Hints ($150) – Reveal a random letter.</li>
        <li>🎟️ Extra Guess ($150) – Buy another shot.</li>
      </ul>
      <p><b>Think smart, spend wisely, and guess like a pro!</b> 🚀</p>
      <button class="close-btn" on:click={() => (showHowToPlay = false)}>
        Close
      </button>
    </div>
  </div>
{/if}

<style>
  /* Remove focus outlines */
  button:focus {
    outline: none;
  }

  /* Top buttons container */
  .top-buttons {
    display: flex;
    justify-content: space-between;
    width: 100%;
    padding: 10px;
    position: absolute;
    top: 5px;
    left: 0;
    right: 0;
  }

  /* "How to Play" button */
  .how-to-play-button {
    background-color: #f0f0f0;
    border: 1px solid #ccc;
    padding: 4px 8px;
    font-size: 10px;
    border-radius: 1px;
    cursor: pointer;
    transition: background-color 0.3s;
    margin-left: 10px;
    margin-top: 5px;
  }
  .how-to-play-button:hover {
    background-color: #e0e0e0;
  }

  /* Dark Mode toggle button */
  .dark-mode-button {
    background: none;
    border: none;
    font-size: 20px;
    cursor: pointer;
    padding: 5px;
    margin-right: 10px;
    position: relative;
    right: 5px;
  }

  /* Guess & Hint buttons */
  .guess-hint-buttons {
    display: flex;
    justify-content: center;
    gap: 20px;
    margin-top: 30px;
  }
  .hint-button,
  .buy-guess-button {
    background-color: #007bff;
    color: white;
    padding: 8px 12px;
    border-radius: 5px;
    border: none;
    cursor: pointer;
    font-size: 14px;
    width: 140px;
    text-align: center;
    transition: background-color 0.3s;
  }

  /* When fundsLow => 'disabled red' */
  .disabled.red {
    background-color: red !important;
    cursor: not-allowed;
    opacity: 0.7;
  }

  /* Blinking effect for pending buttons */
  .buy-guess-button.pending,
  .hint-button.pending {
    animation: blink 1s infinite;
  }

  @keyframes blink {
    0% { opacity: 1; }
    50% { opacity: 0.5; }
    100% { opacity: 1; }
  }

  /* Guess-phrase container */
  .guess-phrase-container {
    display: flex;
    align-items: center;
    justify-content: center;
    margin-top: 30px;
  }

  /* Default guess-phrase button styling */
  .guess-phrase-button {
    background-color: orange;
    color: white;
    padding: 8px 12px;
    border: none;
    border-radius: 5px;
    cursor: pointer;
    font-size: 14px;
    transition: background-color 0.3s;
    margin-top: 0;
  }
  .guess-phrase-button:hover {
    background-color: darkorange;
  }
  /* If no guesses left => red */
  .guess-phrase-button.no-guesses {
    background-color: red !important;
    cursor: not-allowed;
    opacity: 0.7;
  }

  /* Guesses box */
  .guesses-box {
    background-color: orange;
    color: white;
    padding: 8px 12px;
    border-radius: 5px;
    font-size: 16px;
    margin-left: 10px;
    min-width: 40px;
    text-align: center;
    font-weight: bold;
  }
  .guesses-box.no-guesses {
    background-color: rgba(255, 0, 0, 0.647) !important;
  }

  /* Guess Mode Banner */
  .guess-mode-banner {
    background-color: rgba(255, 8, 8, 0.641);
    color: white;
    font-weight: bold;
    text-align: center;
    padding: 10px;
    border-radius: 5px;
    margin-top: 10px;
    width: 100%;
    max-width: 400px;
    animation: fadeIn 0.3s ease-in-out;
  }
  @keyframes fadeIn {
    from {
      opacity: 0;
      transform: scale(0.95);
    }
    to {
      opacity: 1;
      transform: scale(1);
    }
  }

  /* Modal overlay */
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
  .modal-content h2 {
    margin-bottom: 10px;
  }
  .modal-content ul {
    text-align: left;
    padding-left: 20px;
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

  /* Dark Mode overrides */
  :global(body.dark-mode) {
    background: #222;
    color: white;
  }
  :global(body.dark-mode) .modal-content {
    background: #333;
    color: white;
  }
  :global(body.dark-mode) button {
    background: #444;
    color: white;
    border: 1px solid #777;
  }
  :global(body.dark-mode) .utility-buttons button {
    background: #555;
    border-color: #777;
  }
  :global(body.dark-mode) .utility-buttons button:hover {
    background: #666;
  }
  :global(body.dark-mode) .hint-button,
  :global(body.dark-mode) .buy-guess-button {
    background-color: #007bff !important;
    color: white !important;
  }
  :global(body.dark-mode) .guess-phrase-button {
    background-color: orange !important;
    color: white !important;
  }
  :global(body.dark-mode) .guess-phrase-button.no-guesses {
    background-color: red !important;
    color: white !important;
  }
  :global(body.dark-mode) .disabled.red {
    background-color: red !important;
    color: white !important;
    border-color: #777;
  }

  /* Focus states for these local buttons */
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
