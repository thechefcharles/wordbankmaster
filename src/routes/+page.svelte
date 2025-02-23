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
  

  // On mount: add dark mode (could be updated later based on user settings) 
onMount(() => {
  // 🌙 Ensure dark mode is applied on page load
  document.body.classList.add('dark-mode');

  // 🎯 Fetch a new puzzle on load
  fetchRandomGame();

  // 🔥 Remove focus from buttons when clicked
  document.addEventListener('click', (event) => {
    if (event.target.tagName === 'BUTTON') {
      event.target.blur();
    }
  });
});

onMount(() => {
  document.addEventListener('mousedown', (event) => {
    if (event.target.tagName === 'BUTTON') {
      event.target.blur();
    }
  });

  document.addEventListener('touchstart', (event) => {
    if (event.target.tagName === 'BUTTON') {
      event.target.blur();
    }
  });
});



// 🔄 Reactive subscriptions from the game store
$: currentGame = $gameStore;
$: bankroll = currentGame.bankroll || 0;
$: digits = String(bankroll).split('');

// 🔄 When in the browser, update the body class for guess mode
$: if (browser) {
  document.body.classList.toggle('guess-mode', currentGame.gameState === 'guess_mode');
}
</script>

<main>
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

  <!-- Game Buttons Section -->
  <section class="buttons-section">
    <GameButtons />
  </section>

  <!-- Hidden Reset Button (for debugging/testing) -->
  <button class="reset-button hidden" on:click={fetchRandomGame}>
    Reset Game
  </button>
</main>

<style>
  @import url('https://fonts.googleapis.com/css2?family=VT323&display=swap');

  /* Main container styling */
  main {
    max-width: 600px;
    margin: 0 auto;
    text-align: center;
    font-family: 'VT323', sans-serif;
    padding: 10px;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  /* Category text styling */
  .category {
    font-size: 1.2rem;
    margin-top: -150px;
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
    margin-top: 50px;
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
  }
  .logo-container {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-top: -50px;
    margin-bottom: 0;
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
    font-size: 3rem;
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
    font-size: 3rem;
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
}

/* 🔄 Prevent persistent focus from animations */
input,
textarea,
button,
select {
  -webkit-user-select: none;
  -webkit-touch-callout: none;
}

</style>
