<script>
  import { onMount } from 'svelte';
  import { gameStore, selectHint, selectExtraGuess } from '$lib/stores/GameStore.js';
  import { get } from 'svelte/store';

  let showHowToPlay = false;
  let darkMode = false;

  // Subscribe to gameStore for bankroll tracking
  $: bankroll = get(gameStore).bankroll;
  // fundsLow becomes true when the bankroll is less than $150
  $: fundsLow = $gameStore.bankroll < 150;
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

<div class="guess-hint-buttons">
  <!-- Buy Guess Button -->
  <button
  class="buy-guess-button {fundsLow ? 'disabled red' : ''}"
  disabled={fundsLow}
  on:click={() => { if (!fundsLow) selectExtraGuess(); }}
>
  Buy Guess ($150)
</button>

  <!-- Hint Button -->
  <button
    class="hint-button {fundsLow ? 'disabled red' : ''}"
    disabled={fundsLow}
    on:click={() => { if (!fundsLow) selectHint(); }}
  >
    Hint ($150)
  </button>
</div>

<!-- Move How to Play and Dark Mode to the Top -->
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

  /* 🔼 Top Button Container */
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

  /* 📜 How to Play Button */
  .how-to-play-button {
    background-color: #f0f0f0;
    border: 1px solid #ccc;
    padding: 6px 10px;
    font-size: 12px;
    border-radius: 5px;
    cursor: pointer;
    transition: background-color 0.3s;
    margin-left: 10px;
    margin-top: 5px;
  }

  .how-to-play-button:hover {
    background-color: #e0e0e0;
  }

  /* ☀️ Dark Mode Toggle */
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

  /* 💡 Hint & Buy Guess Buttons */
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

  .hint-button:hover,
  .buy-guess-button:hover {
    background-color: #0056b3;
  }

  /* 🔴 Disabled Buttons (when insufficient funds) */
  .hint-button.disabled,
  .buy-guess-button.disabled {
    background-color: red !important;
    cursor: not-allowed;
    opacity: 0.7;
  }

  /* 🟥 Extra red styling if needed */
  .red {
    background-color: red !important;
  }

  /* 📜 Modal Overlay */
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

  /* 📜 Modal Content */
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

  /* ❌ Close Button */
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

  /* 🌙 Dark Mode Styles */
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
</style>
