<!-- +page.svelte -->
<svelte:head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
  <link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@700&display=swap" rel="stylesheet" />
</svelte:head>

<script>
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';
  import PhraseDisplay from '$lib/components/PhraseDisplay.svelte';
  import Keyboard from '$lib/components/Keyboard.svelte';
  import GameButtons from '$lib/components/GameButtons.svelte';
  import FlipDigit from '$lib/components/FlipDigit.svelte';
  import { gameStore, fetchRandomGame } from '$lib/stores/GameStore.js';

  let showHowToPlay = false;
  let darkMode = false;

  function toggleDarkMode() {
    darkMode = !darkMode;
    document.body.classList.toggle('dark-mode', darkMode);
    localStorage.setItem('darkMode', darkMode ? "true" : "false"); // Store as string
  }

  onMount(() => {
    // ✅ Load dark mode from localStorage (convert to boolean)
    const storedDarkMode = localStorage.getItem('darkMode') === "true";
    darkMode = storedDarkMode; // Update reactive variable
    document.body.classList.toggle('dark-mode', darkMode); // Apply correct mode

    // 🎯 Fetch a new puzzle after ensuring dark mode is set
    fetchRandomGame();

    // 🔥 Remove focus from buttons when clicked
    document.addEventListener("mousedown", (event) => {
      if (event.target.tagName === "BUTTON") {
        event.preventDefault();
        event.target.blur();
      }
    });

    // 🚫 Prevent Tab key from focusing elements
    document.addEventListener("keydown", (event) => {
      if (event.key === "Tab") event.preventDefault();
    });
  });

  // 🔄 Reactive subscriptions from the game store
  $: currentGame = $gameStore;
  $: bankroll = currentGame.bankroll || 0;
  $: digits = String(bankroll).split('');

  // 🔄 Ensure body class updates based on game state
  $: if (browser) {
    document.body.classList.toggle("guess-mode", currentGame.gameState === "guess_mode");
  }
</script>

<main>
  <!-- Top Buttons (How to Play & Dark Mode) -->
  <div class="top-buttons">
    <button class="how-to-play-button" on:click={() => showHowToPlay = true} aria-label="How to Play Instructions">
      ❓
    </button>
    <button class="dark-mode-button" on:click={toggleDarkMode} aria-label="Toggle Dark Mode">
      {darkMode ? "☀️" : "🌙"}
    </button>
  </div>

  <!-- Modal -->
  {#if showHowToPlay}
    <div class="modal-overlay" role="dialog" aria-modal="true">
      <div class="modal-content">
        <h2 class="modal-title">📜 How to Play WordBank 🏆</h2>
        <ul class="modal-list">
          <li>🔤 <strong>Buy Letters</strong> to uncover parts of the phrase!</li>
          <li>💡 <strong>Use Hints</strong> to reveal a random letter!</li>
          <li>🎟️ <strong>Buy Extra Guesses</strong> when you're running out!</li>
          <li>⏎ <strong>Submit a Guess</strong> if you think you know the phrase!</li>
          <li>💰 <strong>Stack Your Bankroll</strong> for future games!</li>
        </ul>
        <p class="modal-footer">
          <b>Think smart, spend wisely, and build your Bankroll for the next round! 🚀</b>
        </p>
        <button class="close-btn" on:click={() => showHowToPlay = false} aria-label="Close How to Play">
          ❌ Close
        </button>
      </div>
    </div>
  {/if}

  <!-- Logo -->
  <div class="logo-container">
    <img src="/WordBank.png" alt="WordBank Logo" class="wordbank-logo" />
  </div>

  <!-- Category Display -->
  <p class="category">{currentGame.category} 🌍</p>

  <!-- Phrase Display Section -->
  <section class="phrase-section">
    <PhraseDisplay />
  </section>

  <!-- Win/Loss Banner -->
  {#if currentGame.gameState === "won"}
    <div class="banner win">Winner!</div>
  {:else if currentGame.gameState === "lost"}
    <div class="banner lose">Bankrupt!</div>
  {/if}

  <!-- ✅ This section groups the bankroll display and guess button together -->
  <div class="bankroll-guess-wrapper">
    <!-- ✅ Fixed Bankroll Display Above the Guess Button -->
    <div class="bankroll-box">
      <span class="currency">$</span>
      {#each digits as d}
        <FlipDigit digit={+d} />
      {/each}
    </div>

    <!-- ✅ Guess Button Below Bankroll Display -->
    <div class="guess-button-container">
      <GameButtons />
    </div>
  </div>

  <!-- ✅ Keep the Keyboard at the Bottom -->
  <div class="keyboard-container">
    <Keyboard />
  </div>

  <button class="reset-button hidden" on:click={fetchRandomGame}>
    Reset Game
  </button>
</main>

<style>
  @import url('https://fonts.googleapis.com/css2?family=VT323&display=swap');
  @import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@500;700&display=swap');
  @import url('https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;700&display=swap');
  @import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700&display=swap');




  /* Main container styling */
  main {
    max-width: 600px;
    margin: 0 auto;
    text-align: center;
    font-family: 'Orbitron', sans-serif;
    padding: 8px;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  /* Category text styling */
  .category {
    font-size: 1.0rem;
    margin-top: -120px;
    margin-bottom: 0;
    font-weight: bold;
  }

  /* Section styling */
  .phrase-section,
  .stats-section,
  .keyboard-section,
  .buttons-section {
    width: 100%;
    padding: 5px;
  }

  /* Reset button hidden */
  .reset-button.hidden {
    display: none;
  }

  /* Bankroll container and box styling */
  .bankroll-box {
    padding: 2px 5px;
    font-size: 1.4rem; /* Slightly larger for arcade feel */
    font-family: 'VT323', sans-serif; /* Arcade-style font */
    color: #fff;
    background: linear-gradient(45deg, #2e7d32, #66bb6a);
    border: 3px solid #1b5e20;
    border-radius: 4px;
    text-align: center;
    box-shadow: inset 0 0 10px rgba(0, 0, 0, 0.5);
    display: inline-flex;
    justify-content: center;
    align-items: center;
    letter-spacing: 1px; /* Adds a slight retro spacing */
    margin-top: 60px;
    height: 40px;
    width: 120px;
  }  
  .currency {
    margin-right: 4px;
  }

  /* Logo styling */
  .wordbank-logo {
    width: 380px;
    height: auto;
    display: block;
    margin: -50px auto -60px;
    padding-bottom: 0;
    align-self: center;
  }
  .logo-container {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-top: -20px;
    margin-bottom: 0;
  }

  /* Global overrides for touch and overflow */
  :global(html, body) {
    overflow-x: hidden;
    touch-action: manipulation;
  }

  /* Win Banner Animations */
/* Adjusted Win Banner Animations */
@keyframes winPulse {
    0%, 100% { transform: scale(1) rotate(0deg); text-shadow: 0px 0px 5px green; }
    25% { transform: scale(1.1) rotate(2deg); text-shadow: 0px 0px 10px limegreen; }
    50% { transform: scale(1.25) rotate(-2deg); text-shadow: 0px 0px 15px limegreen; }
    75% { transform: scale(1.1) rotate(2deg); text-shadow: 0px 0px 10px green; }
}
@keyframes winFlash {
    0% { opacity: 1; }
    50% { opacity: 0.4; }
    100% { opacity: 1; }
}

.banner.win {
    font-size: 1.5rem;  /* 🔹 Reduce font size from 3rem to 1.5rem */
    font-weight: 600;
    color: limegreen;
    text-transform: uppercase;
    background: linear-gradient(45deg, green, limegreen);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    text-align: center;
    padding: 10px;  /* 🔹 Reduce padding from 20px to 10px */
    border: 2.5px solid limegreen;  /* 🔹 Reduce border thickness from 5px to 2.5px */
    border-radius: 5px;  /* 🔹 Reduce border radius for a smaller look */
    animation: winPulse 1.5s infinite, winFlash 0.5s infinite;
}

  /* Game Over Banner Animations */
  @keyframes gameOverPulse {
    0%, 100% { transform: scale(1) rotate(0deg); text-shadow: 0px 0px 10px red; }
    25% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px red; }
    50% { transform: scale(1.5) rotate(-3deg); text-shadow: 0px 0px 30px red; }
    75% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px red; }
  }
  @keyframes gameOverFlash {
    0% { opacity: 1; }
    50% { opacity: 0.2; }
    100% { opacity: 1; }
  }
  .banner.lose {
    font-size: 1.5rem;
    font-weight: 600;
    color: red;
    text-transform: uppercase;
    background: linear-gradient(45deg, red, black);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    text-align: center;
    padding: 10px;
    border: 2.5px solid red;
    border-radius: 5px;
    animation: gameOverPulse 1.5s infinite, gameOverFlash 0.5s infinite;
  }

  /* Dark mode overrides */
  :global(body.dark-mode) {
    background: #222;
    color: white;
  }
  button:focus,
button:active {
  outline: none !important;
  box-shadow: none !important;
}

/* 🔄 Fix for Chrome/Safari Mobile Persistent Highlight */
button:focus-visible {
  outline: none !important;
}
/* Remove button focus on all browsers */
/* 🔄 Remove focus outlines and fix unwanted highlights */
button:focus,
button:active {
  outline: none !important;
  box-shadow: none !important;
  background: inherit !important;
}

/* 🔄 Ensure focus never persists */
button:focus-visible {
  outline: none !important;
}

/* 🔄 Disable Safari/Chrome tap highlights */
button {
  -webkit-tap-highlight-color: transparent;
  user-select: none;
  -webkit-user-select: none;
  -moz-user-select: none;
  -ms-user-select: none;
  outline: none !important;
    box-shadow: none !important;
    border: none;
}

button:focus {
    outline: none !important;
    box-shadow: none !important;
  }

   /* Prevent focus for mouse clicks and keyboard navigation */
   button:focus-visible {
    outline: none !important;
  }

  button::-moz-focus-inner {
    border: 0;
  }


/* 🔄 Prevent persistent focus from animations */
input,
textarea,
button,
select {
  -webkit-user-select: none;
  -webkit-touch-callout: none;
}
/* ✅ This wraps the keyboard & guess button, keeping them at the bottom */
.keyboard-button-wrapper {
    position: fixed;
    bottom: 0;
    left: 50%;
    transform: translateX(-50%);
    width: 100%;
    max-width: 600px;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding-bottom: 10px; /* Space at the bottom for usability */
}

/* ✅ Keeps the Guess Phrase button at a fixed distance above the keyboard */
.guess-button-container {
    margin-bottom: 170px; /* Adjust this value for more or less space above the keyboard */
}

/* ✅ Prevents the keyboard from shifting */
.keyboard-section {
    position: relative;
    width: 100%;
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
  z-index: 1000;
}

.how-to-play-button, .dark-mode-button {
  background: none;
  border: none;
  font-size: 24px;
  cursor: pointer;
  padding: 5px;
}

.how-to-play-button {
  color: white;
}

.dark-mode-button {
  color: yellow;
}

/* Modal Styling */
/* ✅ How to Play Modal */
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background: rgba(0, 0, 0, 0.7); /* Darkened background */
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 1000;
  animation: fadeIn 0.3s ease-in-out;
}

/* ✅ Centered Modal Box */
.modal-content {
  background: linear-gradient(180deg, #222, #333);
  padding: 20px;
  border-radius: 10px;
  width: 90%;
  max-width: 400px;
  text-align: center;
  box-shadow: 0 4px 10px rgba(0, 0, 0, 0.3);
  animation: slideIn 0.3s ease-out;
  border: 3px solid limegreen;
}

/* ✅ Title with Neon Effect */
.modal-title {
  font-size: 24px;
  color: limegreen;
  font-family: 'Orbitron', sans-serif;
  text-transform: uppercase;
  text-shadow: 0 0 8px limegreen, 0 0 15px rgba(0, 255, 0, 0.7);
  margin-bottom: 10px;
}

/* ✅ Instructions List */
.modal-list {
  list-style-type: none;
  padding: 0;
  text-align: left;
}

.modal-list li {
  font-size: 16px;
  font-family: 'VT323', sans-serif;
  background: rgba(255, 255, 255, 0.1);
  padding: 8px;
  margin-bottom: 5px;
  border-radius: 5px;
  text-shadow: 0px 0px 5px rgba(255, 255, 255, 0.4);
}

/* ✅ Footer Message */
.modal-footer {
  font-size: 14px;
  font-weight: bold;
  color: #fff;
  padding: 10px;
  text-shadow: 0 0 5px rgba(255, 255, 255, 0.4);
}

/* ✅ Close Button */
.close-btn {
  margin-top: 10px;
  padding: 10px 20px;
  border: none;
  background: red;
  color: white;
  font-size: 16px;
  font-weight: bold;
  cursor: pointer;
  border-radius: 8px;
  transition: background 0.3s;
  text-shadow: 0px 0px 5px rgba(255, 255, 255, 0.4);
}

.close-btn:hover {
  background: darkred;
}

/* ✅ Animations */
@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}

@keyframes slideIn {
  from { transform: translateY(-20px); }
  to { transform: translateY(0); }
}

/* ✅ This keeps the bankroll display & guess button together */
.bankroll-guess-wrapper {
    position: fixed;
    bottom: 0px;  /* Adjust this to fine-tune distance from the keyboard */
    left: 50%;
    transform: translateX(-50%);
    width: 100%;
    max-width: 600px;
    display: flex;
    flex-direction: column;
    align-items: center;
    z-index: 1000;
}

/* ✅ Styling for Bankroll Box */
.bankroll-box {
    padding: 2px 10px;
    font-size: 1.4rem;
    font-family: 'VT323', sans-serif;
    color: white;
    background: linear-gradient(45deg, #2e7d32, #66bb6a);
    border: 3px solid #1b5e20;
    border-radius: 8px;
    text-align: center;
    display: inline-flex;
    justify-content: center;
    align-items: center;
    letter-spacing: 1px;
    margin-bottom: 0px; /* Keeps space between bankroll & button */
}

/* ✅ Keeps the Guess Phrase button right below the bankroll */
.guess-button-container {
    width: 100%;
    display: flex;
    justify-content: center;
}

/* ✅ Keep the Keyboard at the Bottom */
.keyboard-container {
    position: fixed;
    bottom: 0;
    left: 50%;
    transform: translateX(-50%);
    width: 100%;
    max-width: 600px;
    display: flex;
    justify-content: center;
    padding-bottom: 10px;
}


</style>
