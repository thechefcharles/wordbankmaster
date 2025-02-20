<script>
  // Import Svelte utilities and functions from your store
  import { onMount } from 'svelte';
  import {
    gameStore,
    selectHint,
    selectExtraGuess,
    enterGuessMode,
    deleteGuessLetter
  } from '$lib/stores/GameStore.js';

  // Local UI state variables
  let showHowToPlay = false;
  let darkMode = false;
  let guessPending = false; // True when the user has selected the extra guess purchase

  // Reactive declarations based on the global gameStore
  $: noGuessesLeft = $gameStore.guessesRemaining === 0;
  $: guessModeActive = $gameStore.gameState === 'guess_mode';
  $: bankroll = $gameStore.bankroll;
  $: fundsLow = bankroll < 150;
  $: hintPending = $gameStore.selectedPurchase?.type === 'hint' &&
                   $gameStore.gameState === 'purchase_pending';

  // On component mount, load dark mode preference and add an Enter key listener
  onMount(() => {
    // Load dark mode from localStorage; default to dark mode if not set
    const storedMode = localStorage.getItem('darkMode');
    darkMode = storedMode === null ? true : storedMode === 'true';
    // Ensure the <body> has (or not) the dark-mode class
    if (darkMode) {
      document.body.classList.add('dark-mode');
    } else {
      document.body.classList.remove('dark-mode');
    }
    // Add Enter key listener to confirm purchase
    const onKeyDown = (event) => {
      if (event.key === 'Enter') {
        confirmPurchase();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  });

  // Toggle dark mode and store preference
  function toggleDarkMode() {
    darkMode = !darkMode;
    if (darkMode) {
      document.body.classList.add('dark-mode');
    } else {
      document.body.classList.remove('dark-mode');
    }
    localStorage.setItem('darkMode', darkMode ? 'true' : 'false');
  }

  // Toggle the extra guess purchase pending state.
  // This updates both local (guessPending) and global (extraGuessPending via gameState) state.
  function toggleGuessPurchase() {
  if ($gameStore.gameState === "purchase_pending") {
    // If it's already pending, cancel the purchase
    gameStore.update(state => ({
      ...state,
      gameState: "default",
      selectedPurchase: null,
      extraGuessPending: false
    }));
    guessPending = false;
  } else {
    // Start extra guess purchase
    gameStore.update(state => ({
      ...state,
      gameState: "purchase_pending",
      selectedPurchase: { type: "extra_guess" },
      extraGuessPending: true
    }));
    guessPending = true;
  }
}

  // Confirm the extra guess purchase (deduct money and add a guess)
  function confirmPurchase() {
  if ($gameStore.selectedPurchase?.type === "extra_guess") {
    gameStore.update(state => ({
      ...state,
      bankroll: state.bankroll - 150,
      guessesRemaining: state.guessesRemaining + 1,
      gameState: "default",
      selectedPurchase: null,
      extraGuessPending: false
    }));
    guessPending = false;
  }
}
</script>

<!-- Render content based on whether guess mode is active -->
{#if guessModeActive}
  <!-- Guess mode banner appears when in guess mode -->
  <div class="guess-mode-banner">
    Fill every phrase box to submit.<br />
    Correct guesses will remain!
  </div>
{/if}

<!-- Display message feedback if needed -->
{#if $gameStore.message}
  <div class="message-box">{$gameStore.message}</div>
{/if}

<!-- Row for Hint, Enter Guess Mode, and Buy Guess Buttons -->
<div class="guess-controls">
  <!-- Hint Button (Left) -->
  <button 
    class="hint-button {fundsLow ? 'disabled red' : ''} {hintPending ? 'pending' : ''}"
    on:click={() => !fundsLow && selectHint()}
    disabled={fundsLow}
  >
    Hint
  </button>

  <!-- Enter Guess Mode Button (Centered) -->
  <button
    class="guess-phrase-button {guessModeActive ? 'exit-mode' : ''}"
    on:click={enterGuessMode}
    disabled={noGuessesLeft}
  >
    {guessModeActive
      ? "Exit Guess Mode"
      : `Enter Guess Mode (${$gameStore.guessesRemaining})`}
  </button>

  <!-- Buy Extra Guess Button (Right) -->
  <button 
    class="buy-guess-button {noGuessesLeft ? 'no-guesses' : ''} {guessPending ? 'pending' : ''}"
    on:click={toggleGuessPurchase}
  >
    Buy Guess
  </button>
</div>

<!-- Delete button only appears in guess mode -->
{#if guessModeActive}
  <button 
    class="key delete"
    on:click={deleteGuessLetter}
  >
     Delete
  </button>
{/if}

<!-- Top Buttons: "How to Play" and Dark Mode Toggle -->
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
  <div class="modal-overlay" on:click={() => (showHowToPlay = false)} role="dialog" aria-modal="true">
    <div class="modal-content" on:click|stopPropagation>
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
      <button class="close-btn" on:click={() => (showHowToPlay = false)}>
        Close
      </button>
    </div>
  </div>
{/if}

<style>
  /* ===========================
     Global Reset & Utility
  =========================== */
  button:focus {
    outline: none;
  }
  :global(html, body) {
    overflow-x: hidden;
    touch-action: manipulation;
  }

  /* ===========================
     Top Buttons & Modal Styles
  =========================== */
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

  /* ===========================
     Base Button Styles
  =========================== */
  .button-base {
    font-size: 12px;
    font-weight: bold;
    padding: 6px 12px;
    border: 2px solid transparent;
    border-radius: 5px;
    cursor: pointer;
    text-align: center;
    transition: background-color 0.3s, border 0.3s;
    box-sizing: border-box;
  }

  /* ===========================
     Unified Control Buttons
     (Hint, Enter, Buy)
  =========================== */
  .hint-button,
.buy-guess-button,
.guess-phrase-button {
    flex: 1;  /* Ensures buttons evenly distribute space */
    min-width: 90px;  /* Prevents buttons from getting too small */
    max-width: 150px; /* Ensures buttons stay in a reasonable range */
    height: 38px;  /* Standard height */
    font-size: 12px; /* Adjust for smaller screens */
    font-weight: bold;
    border: 2px solid transparent;
    border-radius: 5px;
    cursor: pointer;
    text-align: center;
    transition: background-color 0.3s, border 0.3s;
    box-sizing: border-box;
}

@media (max-width: 400px) {
    .guess-phrase-container {
        flex-wrap: nowrap;  /* Prevents stacking unless absolutely necessary */
        gap: 4px;  /* Reduces gap to save space */
    }
    .hint-button,
    .buy-guess-button,
    .guess-phrase-button {
        min-width: 80px; /* Allow even smaller buttons */
        max-width: 120px;
        font-size: 10px;
        height: 34px;
    }
}

  /* Hint & Buy Guess: Same Color */
  .hint-button,
  .buy-guess-button {
    background-color: blue;
    color: white;
  }
  .hint-button:hover,
  .buy-guess-button:hover {
    background-color: darkblue;
  }

  /* Enter Guess Mode: Orange */
  .guess-phrase-button {
    background-color: orange;
    color: white;
    flex-shrink: 0; /* Prevents shrinking if text changes */
  }
  .guess-phrase-button:hover {
    background-color: darkorange;
  }

  /* Disabled & Pending States */
  .disabled.red {
    background-color: red !important;
    cursor: not-allowed;
    opacity: 0.7;
  }
  .pending {
    animation: blink 1s infinite;
  }
  @keyframes blink {
    0%   { opacity: 1; }
    50%  { opacity: 0.5; }
    100% { opacity: 1; }
  }

  /* DELETE BUTTON - Styled like the Hint Button but Red */
.key.delete {
  display: block; /* Ensure it takes full width if needed */
    margin: 10px auto 0; /* Centers it horizontally below the button */
    background-color: red;
    color: white;
    font-size: 10px;
    font-weight: bold;
    padding: 8px 12px;
    border: 2px solid darkred; 
    border-radius: 5px;
    cursor: pointer;
    text-align: center; 
    width: 100px; /* Matches button width */
    height: 30px;
    transition: background-color 0.3s, border 0.3s;}

/* DELETE BUTTON - Hover */
.key.delete:hover {
    background-color: darkred; /* Darker red on hover */
    border-color: #8B0000; /* Deep red border */
}

/* DELETE BUTTON - Click Effect */
.key.delete:active {
    background-color: rgb(139, 0, 0); /* Darkest red when clicked */
    border-color: black;
    transform: scale(0.95); /* Slight shrink effect */
}

/* DISABLED STATE - Faded Red */
.key.delete:disabled {
    background-color: #ff9999;
    border-color: #cc6666;
    cursor: not-allowed;
    opacity: 0.6;
}

/* ===========================
   Phrase Container (Ensures Phrases Take Fixed Space)
=========================== */
.guess-phrase-container {
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 4px; /* Keeps spacing small */
    width: 100%;
    max-width: 800px; /* Prevents excessive width on large screens */
    padding: 10px 0;
}

/* ===========================
   Dynamic Guess Phrase Boxes
=========================== */
.guess-phrase {
    flex-grow: 1; /* Allows even distribution */
    flex-basis: calc(100% / var(--phrase-length)); /* Dynamically adjust width */
    min-width: 30px; /* Prevents boxes from getting too small */
    max-width: 60px; /* Ensures they don’t grow too big */
    height: 60px; /* Keeps consistent height */
    font-size: clamp(1.4rem, 3vw, 2.2rem); /* Adjusts text size dynamically */
    text-align: center;
    border: 3px solid black;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 5px;
    transition: all 0.2s ease-in-out;
}

/* ===========================
   Smaller Screens (Ensure Boxes Fit)
=========================== */
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

  /* ===========================
     Message & Banner
  =========================== */
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
    0%   { opacity: 1; }
    80%  { opacity: 1; }
    100% { opacity: 0; }
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
    to   { opacity: 1; transform: scale(1); }
  }

  /* ===========================
     Layout: Top Section, Logo, Category & Bankroll
  =========================== */
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
    font-size: 1.4rem;
    margin-top: -100px;
    margin-bottom: 0;
    font-weight: bold;
  }
  .bankroll-container {
    display: flex;
    justify-content: center;
    align-items: center;
    width: 100%;
    margin: 0 auto;
    margin-top: 30px;
  }
  .bankroll-box {
    padding: 6px 14px;
    font-size: 1.7rem;
    font-weight: bold;
    color: white;
    background-color: rgb(103, 208, 103);
    border-radius: 1px;
    text-align: center;
    display: inline-block;
    width: fit-content;
    margin: 0 auto;
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
    margin-top: -80px;
    margin-bottom: 0;
  }

  /* ===========================
     Modal Styles
  =========================== */
  .modal-overlay {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(0,0,0,0.5);
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
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
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

  /* ===========================
     Dark Mode Overrides
  =========================== */
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

  
</style>
