<script>
  import { onMount } from 'svelte';
  import { gameStore, selectHint, selectExtraGuess, enterGuessMode } from '$lib/stores/GameStore.js';
  import { get } from 'svelte/store';

  let showHowToPlay = false;
  let darkMode = false;

   // Reactive variable to check if guesses are zero
   $: noGuessesLeft = $gameStore.guessesRemaining === 0;

  // Reactive variable for displaying the banner
  $: guessModeActive = $gameStore.gameState === "guess_mode";

  // Subscribe reactively to gameStore using $gameStore.
  $: bankroll = $gameStore.bankroll;
  $: fundsLow = bankroll < 150; // If bankroll is below $150

  onMount(() => {
    if (typeof window !== 'undefined') {
      darkMode = localStorage.getItem('darkMode') === 'true';
      document.body.classList.toggle('dark-mode', darkMode);
    }
  });

  function toggleDarkMode() {
    darkMode = !darkMode;
    document.body.classList.toggle('dark-mode', darkMode);
    localStorage.setItem('darkMode', darkMode ? 'true' : 'false');
  }
</script>

<!-- Guess Mode Banner (Only shows in guess mode) -->
{#if guessModeActive}
  <div class="guess-mode-banner">
    Guess Mode Activated! Fill every box with a letter to submit.<br>Correct guesses will remain!
  </div>
{:else}
  <!-- Buy Guess and Hint Buttons (Only show when NOT in Guess Mode) -->
  <div class="guess-hint-buttons">
    <button
      class="buy-guess-button {fundsLow ? 'disabled red' : ''}"
      disabled={fundsLow}
      on:click={() => { if (!fundsLow) selectExtraGuess(); }}
    >
      Buy Guess ($150)
    </button>

    <button
      class="hint-button {fundsLow ? 'disabled red' : ''}"
      disabled={fundsLow}
      on:click={() => { if (!fundsLow) selectHint(); }}
    >
      Hint ($150)
    </button>
  </div>
{/if}

<!-- New Guess Entire Phrase Container -->
<div class="guess-phrase-container">
  <button 
  class="guess-phrase-button {noGuessesLeft ? 'no-guesses' : ''}" 
  on:click={enterGuessMode} 
  disabled={noGuessesLeft}
>
  Guess Entire Phrase
</button>
<div class="guesses-box {noGuessesLeft ? 'no-guesses' : ''}">
  {$gameStore.guessesRemaining}
</div>
</div>

<!-- Top Buttons -->
<div class="top-buttons">
  <button class="how-to-play-button" on:click={() => showHowToPlay = true}>
    How to Play
  </button>
  <button class="dark-mode-button" on:click={toggleDarkMode}>
    {darkMode ? "🌙" : "☀️"}
  </button>
</div>

<!-- "How to Play" Modal -->
{#if showHowToPlay}
  <div class="modal-overlay" on:click={() => (showHowToPlay = false)} role="dialog" aria-modal="true">
    <div class="modal-content" on:click|stopPropagation>
      <h2>📜 How to Play</h2>
      <p>💰 <b>You start with $1000.</b> Use it wisely to <b>buy letters, get hints, and guess the phrase!</b></p>
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
      <button class="close-btn" on:click={() => (showHowToPlay = false)}>Close</button>
    </div>
  </div>
{/if}

<style>
  /* Remove focus outline */
  button:focus {
    outline: none;
  }

  /* Top Buttons */
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

  /* Buy Guess & Hint Buttons */
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
    margin-top: 30px;
  }

  /* New Guess Entire Phrase Container */
  .guess-phrase-container {
    display: flex;
    align-items: center;
    justify-content: center;
    margin-top: 30px;
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
    margin-top: 0px
  }

  /* 🔴 Make button red when guesses are zero */
.guess-phrase-button.no-guesses {
  background-color: red !important;
}

  /* 🔹 Ensure it stays orange even when clicked */
.guess-phrase-button:active,
.guess-phrase-button:focus,
.guess-phrase-button:visited {
  background-color: orange !important;
  color: white !important;
  outline: none;
  box-shadow: none;
}

  .guess-phrase-button:hover {
    background-color: darkorange;
  }
/* Default Guesses Remaining Box */
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

/* Change to red when no guesses left */
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

/* Fade-in animation */
@keyframes fadeIn {
  from { opacity: 0; transform: scale(0.95); }
  to { opacity: 1; transform: scale(1); }
}

/* Default Guess Entire Phrase Button */
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

/* Change to red when no guesses left */
.guess-phrase-button.no-guesses {
  background-color: red !important;
  cursor: not-allowed;
  opacity: 0.7;
}

/* Optional: Add hover effect */
.guess-phrase-button.no-guesses:hover {
  background-color: darkred !important;
}


  /* Modal Styles */
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

  /* Dark Mode Styles */
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

  /* 🔥 Ensure it stays red in dark mode */
:global(body.dark-mode) .guess-phrase-button.no-guesses {
  background-color: red !important;
  color: white !important;
}

  /* Remove default focus outline and shadow for all relevant buttons */
.buy-guess-button:focus,
.hint-button:focus,
.guess-phrase-button:focus,
.enter-button:focus,
.key:focus {
  outline: none;
  box-shadow: none;
}

/* Ensure Buy Guess & Hint buttons retain their blue color when focused */
.buy-guess-button:focus,
.hint-button:focus {
  background-color: #007bff !important;
  color: white !important;
}

/* Ensure the Guess Entire Phrase button stays orange when focused */
.guess-phrase-button:focus {
  background-color: orange !important;
  color: white !important;
}

</style>
