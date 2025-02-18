<script>
  import { onMount } from 'svelte';
  import { selectHint, selectExtraGuess } from '$lib/stores/GameStore.js';

  let showHowToPlay = false;
  let darkMode = false;

  onMount(() => {
    // Load user preference on the client side
    if (typeof window !== 'undefined') {
      darkMode = localStorage.getItem('darkMode') === 'true';
      document.body.classList.toggle('dark-mode', darkMode);
    }
  });

  function toggleDarkMode() {
    darkMode = !darkMode;
    // Apply or remove the 'dark-mode' class on <body>
    document.body.classList.toggle('dark-mode', darkMode);
    // Save preference to localStorage
    localStorage.setItem('darkMode', darkMode ? 'true' : 'false');
  }
</script>

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
      <p>
        💰 <b>You start with $1000.</b> Use it wisely to
        <b>buy letters, get hints, and guess the phrase!</b>
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
      <button class="close-btn" on:click={() => (showHowToPlay = false)}>Close</button>
    </div>
  </div>
{/if}

<style>
button:focus {
  outline: none;
}

/* 🔼 Move How to Play & Dark Mode to the Top */
.top-buttons {
  display: flex;
  justify-content: space-between;
  width: 100%;
  padding: 10px;
  position: absolute;
  top: 5px; /* Move it closer to the top */
  left: 0;
  right: 0;
}

/* 📜 How to Play Button (Top Left, No Overlap) */
.how-to-play-button {
  background-color: #f0f0f0;
  border: 1px solid #ccc;
  padding: 6px 10px; /* Make button smaller */
  font-size: 12px; /* Reduce font size */
  border-radius: 5px;
  cursor: pointer;
  transition: 0.3s;
  margin-left: 10px; /* Add space from the left */
  margin-top: 5px; /* Move down slightly */
}

/* ☀️ Dark Mode Button (Top Right, Shift Left) */
.dark-mode-button {
  background: none;
  border: none;
  font-size: 20px;
  cursor: pointer;
  padding: 5px;
  margin-right: 10px; /* Shift it left */
  position: relative;
  right: 5px; /* Fine-tune placement */
}

/* 💡 Hint Button (Right) */
.hint-button {
  background-color: #007bff;
  color: white;
  padding: 8px 12px;
  border-radius: 4px;
  border: none;
  cursor: pointer;
  font-size: 14px;
  flex: 1; /* 🔹 Ensures it takes equal space */
  max-width: 140px; /* 🔹 Limits width */
  text-align: center;
}

/* 📜 How to Play Modal */
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
  transition: 0.3s;
}

.close-btn:hover {
  background: darkred;
}

/* 🌙 Dark Mode */
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
