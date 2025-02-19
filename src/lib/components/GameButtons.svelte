<script>
  import { onMount } from 'svelte';
  import {
    gameStore,
    selectHint,
    selectExtraGuess,
    enterGuessMode,
    deleteGuessLetter
  } from '$lib/stores/GameStore.js';

  let showHowToPlay = false;
  let darkMode = false;
  let guessPending = false;

  // Reactive: are we out of guesses?
  $: noGuessesLeft = $gameStore.guessesRemaining === 0;

  // Reactive: is guess mode active?
  $: guessModeActive = $gameStore.gameState === 'guess_mode';

  // Reactive: current bankroll & whether it's below $150
  $: bankroll = $gameStore.bankroll;
  $: fundsLow = bankroll < 150;

  // Reactive variables for pending states (for hint purchase)
  $: hintPending = $gameStore.selectedPurchase?.type === 'hint' &&
                   $gameStore.gameState === 'purchase_pending';

  // On mount, load dark mode from localStorage and set up event listener
  onMount(() => {
    const storedMode = localStorage.getItem('darkMode');
    darkMode = storedMode === null ? true : storedMode === 'true';

    if (darkMode) {
        document.body.classList.add('dark-mode');
    } else {
        document.body.classList.remove('dark-mode');
    }

    const onKeyDown = (event) => {
        if (event.key === 'Enter') {
            confirmPurchase();
        }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => {
        window.removeEventListener('keydown', onKeyDown);
    };
});

  function toggleDarkMode() {
    darkMode = !darkMode;
    if (darkMode) {
    document.body.classList.add('dark-mode');
} else {
    document.body.classList.remove('dark-mode');
}

    localStorage.setItem('darkMode', darkMode ? 'true' : 'false');
  }

  function toggleGuessPurchase() {
  guessPending = !guessPending;
  gameStore.update(state => ({
    ...state,
    gameState: guessPending ? "purchase_pending" : "default",
    extraGuessPending: guessPending
  }));
}

  function confirmPurchase() {
    if (guessPending) {
      selectExtraGuess(); // This deducts $150 and adds a guess
      guessPending = false;
    }
  }
 // (Optional) Add Enter key listener (client-side only)
 onMount(() => {
    const handleKeyDown = (event) => {
      if (event.key === 'Enter') {
        confirmPurchase();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  });
</script>

{#if guessModeActive}
  <!-- In guess mode, display the guess mode banner -->
  <div class="guess-mode-banner">
    Guess Mode Activated! Fill every box with a letter to submit.<br />
    Correct guesses will remain!
  </div>
{:else}
  <!-- When not in guess mode, show the Hint button (Buy Guess is now merged with the guesses box) -->
  <div class="guess-hint-buttons">
    <button
      class="hint-button {fundsLow ? 'disabled red' : ''} {hintPending ? 'pending' : ''}"
      disabled={fundsLow}
      on:click={() => { if (!fundsLow) selectHint(); }}
    >
      Hint ($150)
    </button>
  </div>
  {#if $gameStore.message}
    <!-- Display the message banner right below the Guess & Hint buttons -->
    <div class="message-box">{$gameStore.message}</div>
  {/if}
{/if}

<!-- Guess Mode Button, Guesses Remaining (which now functions as Buy Guess), and Delete Button -->
<div class="guess-phrase-container">
  <button
  class="guess-phrase-button {guessModeActive ? 'exit-mode' : ''}"
  on:click={enterGuessMode}
  disabled={noGuessesLeft}
>
  {guessModeActive ? "Exit Guess Mode" : "Enter Guess Mode"}
</button>
<div 
  class="guesses-box {noGuessesLeft ? 'no-guesses' : ''} {guessPending ? 'pending' : ''}"
  on:click={toggleGuessPurchase}
>
  {$gameStore.guessesRemaining}
  {#if guessPending}
    <span class="plus-one">+1</span>
  {/if}
</div>
  {#if guessPending}
    <span class="cost-display">(-$150)</span>
  {/if}
  {#if guessModeActive}
    <!-- Delete button appears only in guess mode -->
    <button class="delete-guess-button" on:click={deleteGuessLetter}>
      ❌ Delete
    </button>
  {/if}
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
  /* ---------------------------
     Guess & Hint Buttons
  --------------------------- */
  .guess-hint-buttons {
    display: flex;
    justify-content: center;
    gap: 20px;
    margin-top: 10px;
  }
  .hint-button,
  .buy-guess-button { /* Note: buy-guess-button is no longer displayed */
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
  .disabled.red {
    background-color: red !important;
    cursor: not-allowed;
    opacity: 0.7;
  }
  .buy-guess-button.pending,
  .hint-button.pending {
    animation: blink 1s infinite;
  }
  @keyframes blink {
    0% { opacity: 1; }
    50% { opacity: 0.5; }
    100% { opacity: 1; }
  }

  /* ---------------------------
     Guess Mode & Extra Guess Functionality
  --------------------------- */
  .guess-phrase-container {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    margin-top: 10%;
  }
  .guess-phrase-button {
    background-color: orange;
    color: white;
    padding: 8px 12px;
    border: none;
    border-radius: 5px;
    cursor: pointer;
    font-size: 14px;
    transition: background-color 0.3s;
  }
  .guess-phrase-button:hover {
    background-color: darkorange;
  }
  .guess-phrase-button.no-guesses {
    background-color: red !important;
    cursor: not-allowed;
    opacity: 0.7;
  }
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
    cursor: pointer;
    transition: background-color 0.3s;
  }
  .guesses-box:hover {
    background-color: darkorange;
  }
  .guesses-box.pending {
  background-color: orange !important;
  animation: blink 1s infinite;
}
  .cost-display {
  color: red;
  font-weight: bold;
  margin-left: 10px;
  font-size: 1.2rem;
}

.plus-one {
  color: green;
  font-weight: bold;
  font-size: 1rem;
  margin-left: 5px;
}
  .delete-guess-button {
    background-color: #ff6666;
    color: white;
    padding: 8px 12px;
    border: none;
    border-radius: 5px;
    cursor: pointer;
    font-size: 14px;
    transition: background-color 0.3s;
    margin-top: 10px;
  }
  .delete-guess-button:hover {
    background-color: #cc3333;
  }
  :global(body:not(.guess-mode)) .delete-guess-button {
    display: none;
  }

  :global(body:not(.dark-mode)) .key .letter,
:global(body:not(.dark-mode)) .key .letter.selected,
:global(body:not(.dark-mode)) .key .letter.pending {
  color: #000 !important;
}


  /* ---------------------------
     Message Box
  --------------------------- */
  .message-box {
    margin-top: 10px;
    background: red;
    color: white;
    padding: 0px 10px;
    font-weight: bold;
    border-radius: 5px;
    text-align: center;
    animation: fadeOut 2s ease-in-out;
  }
  @keyframes fadeOut {
    0% { opacity: 1; }
    80% { opacity: 1; }
    100% { opacity: 0; }
  }

  /* ---------------------------
     Guess Mode Banner
  --------------------------- */
  .guess-mode-banner {
    background-color: rgba(255, 8, 8, 0.641);
    color: white;
    font-weight: bold;
    text-align: center; 
    padding: 5px;
    border-radius: 3px;
    margin-top: -10px;
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

  /* ---------------------------
     Top Section, Logo & Category
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
  /* Remove extra margins: */
  margin: 0;
}

.dark-mode-button {
  background: none;
  border: none;
  font-size: 20px;
  cursor: pointer;
  padding: 5px;
  /* Remove extra margins: */
  margin: 0;
}

  .category {
    font-size: 1.4rem;
    margin-top: -140px;
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
    padding: 10px 20px;
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
    margin-bottom: -50px;
    margin-top: -30px;
    padding-bottom: 0;
  }
  .logo-container {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-top: -50px;
    margin-bottom: 0;
  }

  /* ---------------------------
     Modal Styles
  --------------------------- */
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

  /* ---------------------------
     Dark Mode Overrides
  --------------------------- */
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
