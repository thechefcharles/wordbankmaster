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

  // ✅ Apply Dark Mode from localStorage
  function applyDarkMode() {
    document.body.classList.toggle('dark-mode', darkMode);
  }

  // ✅ Toggle Dark Mode & Save Preference
  function toggleDarkMode() {
    darkMode = !darkMode;
    localStorage.setItem('darkMode', darkMode);
    applyDarkMode(); // Apply instantly
  }

  // ✅ Initialize on Mount
  onMount(() => {
    if (browser) {
      darkMode = localStorage.getItem('darkMode') === 'true';
      applyDarkMode();
    }
    fetchRandomGame(); // Load new game on mount

    // 🔥 Remove button focus on click/touch/mousedown
    document.addEventListener('click', removeButtonFocus, true);
    document.addEventListener('mousedown', removeButtonFocus, true);
    document.addEventListener('touchstart', removeButtonFocus, true);
  });

  // ✅ Function to Remove Button Focus
  function removeButtonFocus(event) {
    if (event.target.tagName === 'BUTTON') {
      event.target.blur();
    }
  }




// 🔄 Reactive subscriptions from the game store
$: currentGame = $gameStore;
$: bankroll = currentGame.bankroll || 0;
$: digits = String(bankroll).split('');

// 🔄 When in the browser, update the body class for guess mode
$: if (browser) {
  document.body.classList.toggle('guess-mode', currentGame.gameState === 'guess_mode');
}

</script>

<!-- 🔹 Buttons Positioned in Opposite Corners -->
<div class="top-buttons">
  <!-- ❓ How to Play -->
  <button class="icon-button subtle-button" on:click={() => showHowToPlay = true}>
    ❓
  </button>

  <!-- 🌙 Dark Mode Toggle -->
  <button class="icon-button subtle-button" on:click={toggleDarkMode}>
    {darkMode ? "☀️" : "🌙"}
  </button>
</div>

<!-- 📜 How to Play Modal -->
{#if showHowToPlay}
  <div class="modal-overlay">
    <div class="modal-content">
      <button class="close-btn" on:click={() => showHowToPlay = false}>❌</button>

      <h2>📜 How to Play</h2>
      <p>💰 Start with $1000. Use it wisely to buy letters, get hints, and guess the phrase!</p>

      <h3>🎯 Goal</h3>
      <p>Solve the phrase before running out of money!</p>

      <h3>🕹️ Gameplay</h3>
      <ul>
        <li>🔤 <b>Buy Letters:</b> Click/tap letters to purchase.</li>
        <li>⏎ <b>Confirm:</b> Press Enter to submit purchases or guesses.</li>
        <li>🔄 <b>Guess Mode:</b> Press Space to toggle Guess Mode.</li>
        <li>💡 <b>Hint ($150):</b> Reveals a random letter.</li>
        <li>🎟️ <b>Extra Guess ($150):</b> Buy another shot.</li>
      </ul>

      <p><b>Think smart, spend wisely, and guess like a pro! 🚀</b></p>
    </div>
  </div>
{/if}

<main>
  <!-- Logo -->
  <div class="logo-container">
    <img src="/1.png" alt="WordBank Logo" class="wordbank-logo" />
  </div>

  <!-- Category Display -->
  <p class="category">{currentGame.category} 🌍</p>

  <!-- Phrase Display Section -->
  <section class="phrase-section">
    <PhraseDisplay />
  </section>

<!-- New Fixed Container -->
<div class="bankroll-game-buttons-container">
  <!-- Bankroll Display -->
  <section class="stats-section">
    <div class="bankroll-container">
      <div class="bankroll-box">
        <span class="currency">$</span>
        {#each digits as d}
          <FlipDigit digit={+d} />
        {/each}
      </div>
    </div>
  </section>

  <!-- Game Buttons Section -->
  <section class="buttons-section">
    <GameButtons />
  </section>
</div>


  <!-- Keyboard Section -->
  <section class="keyboard-section">
    <Keyboard />
  </section>

  <!-- Win/Loss Banner -->
  {#if currentGame.gameState === "won"}
    <div class="banner win">Winner!</div>
  {:else if currentGame.gameState === "lost"}
    <div class="banner lose">Bankrupt!</div>
  {/if}


  <!-- Hidden Reset Button (for debugging/testing) -->
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
    font-size: .8rem;
    margin-top: -120px;
    margin-bottom: -20px;
    font-weight: bold;
  }


  


  /* Section styling */
  .phrase-section,
  .stats-section,
  .keyboard-section,
  .buttons-section {
    width: 100%;
    padding: 0px;
  }

  /* Reset button hidden */
  .reset-button.hidden {
    display: none;
  }

  /* Bankroll container and box styling */
  .bankroll-box {
    padding: 10px 15px;
    font-size: 1.8rem; /* Slightly larger for emphasis */
    font-family: 'Orbitron', sans-serif; /* Futuristic arcade font */
    color: #fff;
    background: linear-gradient(180deg, #d1cdcd, #858484); 
    border: 3px solid rgba(255, 255, 255, 0.4); /* Subtle glowing border */
    border-radius: 12px;
    text-align: center;
    box-shadow: 
        inset 2px 2px 6px rgba(255, 255, 255, 0.2),  /* Inner highlight */
        3px 3px 8px rgba(0, 0, 0, 0.8),             /* Outer shadow */
        5px 5px 12px rgba(0, 0, 0, 0.5);            /* Soft depth shadow */    display: inline-flex;
    justify-content: center;
    align-items: center;
    letter-spacing: 1.5px; /* Spaced-out numbers */
    backdrop-filter: blur(5px); /* Slight blur for a cool effect */
    transition: transform 0.3s ease-in-out, box-shadow 0.3s ease-in-out;
    position: relative;
    top: 30px;
}

/* 💰 Animated Glow Effect */
.bankroll-box:hover {
    transform: scale(1.05); /* Slight hover effect */
    box-shadow: 0 0 25px rgba(251, 251, 251, 0.8), 0 0 1rgba(158, 158, 158, 0.7)0.7) inset;
}

/* 💰 Cool Inner Glow */
.bankroll-box::before {
    content: "";
    position: absolute;
    width: 100%;
    height: 100%;
    top: 0;
    left: 0;
    border-radius: 12px;
    box-shadow: 0 0 12px rgba(251, 251, 251, 0.5) inset;
    opacity: 0.5;
    transition: opacity 0.3s ease-in-out;
}

/* ✨ Subtle Animated Border Effect */
@keyframes bankrollGlow {
    0% { box-shadow: 0 0 8px rgba(245, 246, 245, 0.5); }
    50% { box-shadow: 0 0 12px rgba(242, 243, 242, 0.7); }
    100% { box-shadow: 0 0 8px rgba(239, 241, 239, 0.5); }
}
.bankroll-box {
    animation: bankrollGlow 2.5s infinite alternate ease-in-out;
}

/* 💲 Currency Symbol */
.currency {
    font-size: 1.5rem;
    margin-right: 6px;
    font-weight: bold;
    color: rgba(255, 255, 255, 0.8);
    text-shadow: 0 0 5px rgba(255, 255, 255, 0.5);
}

  .bankroll-container {
  position: absolute;
  bottom: 130px; /* Moves bankroll down */
  left: 50%;
  transform: translateX(-50%);
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
    margin-top: -10px;
    margin-bottom: 0;
  }


  .bankroll-game-buttons-container {
  position: fixed;
  bottom: 160px; /* Adjust this so it sits above the keyboard */
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  flex-direction: column; /* Stack bankroll and buttons vertically */
  align-items: center;
  gap: 10px;
  padding: 12px 18px;
  border-radius: 10px;
  z-index: 1000; /* Ensure it stays above other elements */
}



  /* Global overrides for touch and overflow */
  :global(html, body) {
    overflow-x: hidden;
    touch-action: manipulation;
  }

  /* Win Banner Animations */
  @keyframes winPulse {
    0%, 100% { transform: scale(1) rotate(0deg); text-shadow: 0px 0px 10px green; }
    25% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px limegreen; }
    50% { transform: scale(1.5) rotate(-3deg); text-shadow: 0px 0px 30px limegreen; }
    75% { transform: scale(1.2) rotate(3deg); text-shadow: 0px 0px 20px green; }
  }
  @keyframes winFlash {
    0% { opacity: 1; }
    50% { opacity: 0.2; }
    100% { opacity: 1; }
  }
  .banner.win {
    font-size: 2rem;
    font-weight: 600;
    color: limegreen;
    text-transform: uppercase;
    background: linear-gradient(45deg, green, limegreen);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    text-align: center;
    padding: 20px;
    border: 5px solid limegreen;
    border-radius: 10px;
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
    font-size: 2rem;
    font-weight: 600;
    color: red;
    text-transform: uppercase;
    background: linear-gradient(45deg, red, black);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    text-align: center;
    padding: 20px;
    border: 5px solid red;
    border-radius: 10px;
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
  background: inherit !important;
}

  /* 🔄 Ensure focus never persists */
  button:focus-visible {
  outline: none !important;
  }
/* 🔹 Top Buttons Styling */
.top-buttons {
    position: fixed;
    top: 12px;
    left: 12px;
    right: 12px;
    display: flex;
    justify-content: space-between;
    z-index: 1000;
  }

  .icon-button {
    background: transparent;
    border: none;
    font-size: 20px;
    cursor: pointer;
    color: rgba(255, 255, 255, 0.75);
    transition: color 0.3s ease, transform 0.2s ease, opacity 0.3s ease;
  }

  .subtle-button {
    opacity: 0.5;
  }

  .subtle-button:hover {
    opacity: 1;
    transform: scale(1.15);
  }

 /* 📜 Modal Overlay */
 .modal-overlay {
    position: fixed; /* Keeps it in place */
    top: 0;
    left: 0;
    width: 100vw;
    height: 100vh;
    background: rgba(0, 0, 0, 0.85); /* Dark overlay to block visibility */
    display: flex;
    justify-content: center;
    align-items: center;
    z-index: 9999; /* Make sure it's the highest */
    backdrop-filter: blur(5px); /* Optional: adds a cool blur effect */
}
  /* 📜 Modal Content - Adjusts for Light & Dark Mode */
  .modal-content {
    background: white; /* Default Light Mode Background */
    padding: 20px;
    border-radius: 10px;
    width: 90%;
    max-width: 400px;
    text-align: center;
    box-shadow: 0 4px 10px rgba(0, 0, 0, 0.2);
    animation: slideIn 0.3s ease-out;
    border: 3px solid #007bff; /* Blue border for better visibility */
    color: black; /* Default text color */
    position: relative;
  }

  /* 🌙 Dark Mode Overrides */
  :global(body.dark-mode) .modal-content {
    background: linear-gradient(135deg, #222, #333);
    border: 3px solid limegreen;
    color: white;
    box-shadow: 0 4px 10px rgba(0, 255, 0, 0.3);
  }


  .close-btn:hover {
    background: darkred;
  }

  /* 📜 Title */
  .modal-title {
    font-size: 24px;
    font-weight: bold;
    color: #007bff; /* Blue for visibility in light mode */
    text-transform: uppercase;
    text-shadow: 0 0 5px rgba(0, 0, 0, 0.2);
  }

  /* 🔹 Intro Text */
  .intro-text {
    font-size: 16px;
    color: #333;
    margin-bottom: 10px;
  }

  /* 🕹️ List */
  .modal-list {
    list-style-type: none;
    padding: 0;
    text-align: left;
  }

  .modal-list li {
    font-size: 16px;
    background: rgba(0, 0, 0, 0.05);
    padding: 8px;
    margin-bottom: 5px;
    border-radius: 5px;
    text-shadow: none;
  }

  /* 🌙 Dark Mode Overrides for List */
  :global(body.dark-mode) .modal-list li {
    background: rgba(255, 255, 255, 0.1);
  }

  /* 🚀 Footer */
  .modal-footer {
    font-size: 14px;
    font-weight: bold;
    color: black;
    padding: 10px;
    text-shadow: none;
  }

  /* 🌙 Dark Mode Overrides for Footer */
  :global(body.dark-mode) .modal-footer {
    color: white;
    text-shadow: 0 0 5px rgba(255, 255, 255, 0.4);
  }

  /* 🎬 Animations */
  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes slideIn {
    from { transform: translateY(-20px); }
    to { transform: translateY(0); }
  }
  </style>
