<script>
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
  

  // Reactive declarations based on the global gameStore
  $: showHintCost = $gameStore.selectedPurchase?.type === 'hint' && $gameStore.gameState === 'purchase_pending';
  $: showGuessCost = $gameStore.selectedPurchase?.type === 'extra_guess' && $gameStore.gameState === 'purchase_pending';
  $: noGuessesLeft = $gameStore.guessesRemaining === 0;
  $: guessModeActive = $gameStore.gameState === 'guess_mode';
  $: bankroll = $gameStore.bankroll;
  $: fundsLow = bankroll < 150;
  $: hintPending = $gameStore.selectedPurchase?.type === 'hint' &&
                   $gameStore.gameState === 'purchase_pending';
  $: guessPending = $gameStore.selectedPurchase?.type === 'extra_guess' &&
                   $gameStore.gameState === 'purchase_pending';
                   

  // Toggle Hint Selection
  function toggleHintPurchase() {
    gameStore.update(state => {
      if (state.selectedPurchase?.type === "hint") {
        // Deselect Hint
        showHintCost = false;
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      // Select Hint
      showHintCost = true;
      return { ...state, selectedPurchase: { type: "hint" }, gameState: "purchase_pending" };
    });
  }

  // Toggle Extra Guess Selection
  function toggleGuessPurchase() {
    gameStore.update(state => {
      if (state.selectedPurchase?.type === "extra_guess") {
        // Deselect Guess
        showGuessCost = false;
        return { ...state, selectedPurchase: null, gameState: "default" };
      }
      // Select Guess
      showGuessCost = true;
      return { ...state, selectedPurchase: { type: "extra_guess" }, gameState: "purchase_pending" };
    });
  }

  // Confirm the selected purchase
  function confirmPurchase() {
    gameStore.update(state => {
      if (!state.selectedPurchase) return state;

      const purchase = state.selectedPurchase;
      let newState = { ...state, selectedPurchase: null, gameState: "default" };

      if (purchase.type === "hint" && state.bankroll >= 150) {
        newState.bankroll -= 150;
        selectHint();
        showHintCost = false;
      }

      if (purchase.type === "extra_guess" && state.bankroll >= 150) {
        newState.bankroll -= 150;
        newState.guessesRemaining += 1;
        selectExtraGuess();
        showGuessCost = false;
      }

      return newState;
    });
  }

  // Toggle dark mode and store preference
  function toggleDarkMode() {
    darkMode = !darkMode;
    document.body.classList.toggle('dark-mode', darkMode);
    localStorage.setItem('darkMode', darkMode);
  }

  // On component mount, load dark mode preference and add Enter key listener
  onMount(() => {
    darkMode = localStorage.getItem('darkMode') === 'true';
    document.body.classList.toggle('dark-mode', darkMode);

    const onKeyDown = (event) => {
      if (event.key === 'Enter') confirmPurchase();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  });

</script>

<!-- Render content based on whether guess mode is active -->
{#if guessModeActive}
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
  <!-- Hint Button + Cost Indicator -->
  <div class="button-container">
    {#if showHintCost}
      <div class="cost-indicator">-$150</div>
    {/if}
    <button 
      class="hint-button"
      class:disabled-red={fundsLow}
      class:pending={hintPending}
      on:click={toggleHintPurchase}
      disabled={fundsLow}
      aria-label="Buy a hint for $150"
    >
      Hint
    </button>
  </div>

  <!-- Enter Guess Mode Button -->
  <button
    class="guess-phrase-button"
    class:exit-mode={guessModeActive}
    on:click={enterGuessMode}
    disabled={noGuessesLeft}
    aria-label={guessModeActive ? "Exit Guess Mode" : `Enter Guess Mode (${ $gameStore.guessesRemaining })`}
  >
    {guessModeActive ? "Exit Guess Mode" : `Enter Guess Mode (${$gameStore.guessesRemaining})`}
  </button>

  <!-- Buy Extra Guess Button + Cost Indicator -->
  <div class="button-container">
    {#if showGuessCost}
      <div class="cost-indicator">-$150</div>
    {/if}
    <button 
      class="buy-guess-button"
      class:no-guesses={noGuessesLeft}
      class:pending={guessPending}
      on:click={toggleGuessPurchase}
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
/* ===========================
     Cost Indicator
=========================== */
/* ===========================
     Cost Indicator
=========================== */
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
    opacity: 1;
}

@keyframes fadeOut {
    0% { opacity: 1; transform: translateY(0); }
    50% { opacity: 0.8; transform: translateY(-5px); }
    100% { opacity: 0; transform: translateY(-10px); }
}
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
    padding: 8px 12px;
    border: 2px solid transparent;
    border-radius: 5px;
    cursor: pointer;
    text-align: center;
    transition: background-color 0.3s, border 0.3s;
    box-sizing: border-box;
}

/* ===========================
     Guess Controls Container
     (Ensures even button spacing)
  =========================== */
.guess-controls {
    display: flex;
    justify-content: space-between; /* Evenly distribute buttons */
    align-items: center;
    width: 100%;
    max-width: 400px; /* Ensures buttons don't get too wide */
    margin: 10px auto; /* Centers the button group */
    gap: 8px; /* Ensures even spacing between buttons */
}

/* ===========================
     Unified Control Buttons
     (Hint, Enter, Buy)
  =========================== */
  .hint-button,
.buy-guess-button {
  /* Ensure buttons take equal width but override to force a circular shape */
  width: 40px;               /* Increase size for a more round look */
  height: 40px;
  border-radius: 50%;        /* Makes it a perfect circle */
  border: none;
  cursor: pointer;
  color: #fff;
  font-weight: bold;
  text-align: center;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 10px;           /* Adjust font size as needed */
  text-transform: uppercase;
  transition: transform 0.2s ease, box-shadow 0.2s ease;
  box-sizing: border-box;
}

/* Both buttons use a blue arcade style */
.hint-button,
.buy-guess-button {
  background: radial-gradient(circle at 30% 30%, #4488ff, #0055bb 80%);
  box-shadow: 0 4px 0 #003366, 0 6px 20px rgba(0, 0, 0, 0.4);
}

/* Hover effect: slight pop-up */
.hint-button:hover,
.buy-guess-button:hover {
  transform: translateY(-2px);
}

/* Active effect: button pressed down */
.hint-button:active,
.buy-guess-button:active {
  transform: translateY(2px);
}
/* Adjust for smaller screens */
@media (max-width: 400px) {
    .guess-controls {
        max-width: 100%; /* Full width on very small screens */
    }
    .hint-button,
    .buy-guess-button,
    .guess-phrase-button {
        min-width: 90px; /* Slightly smaller buttons */
        height: 36px;
        font-size: 10px;
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
