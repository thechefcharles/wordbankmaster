<script>
  import { gameStore } from '$lib/stores/GameStore.js';
  import { onDestroy, createEventDispatcher } from 'svelte';

  // ==========================
  // 📤 Setup Event Dispatcher
  // ==========================
  const dispatch = createEventDispatcher();

  // ==========================
  // 🧠 Format the Phrase
  // ==========================
  $: phrase = $gameStore.phrase || "";
  let maxLettersPerRow = 12;

  function getFormattedPhrase(phrase) {
    const words = phrase.split(" ");
    const formattedRows = [];
    let currentRow = "";

    for (const word of words) {
      if (currentRow.length + word.length + (currentRow ? 1 : 0) > maxLettersPerRow) {
        if (currentRow) formattedRows.push(currentRow + "-");
        currentRow = word;
      } else {
        currentRow += (currentRow ? " " : "") + word;
      }
    }

    if (currentRow) formattedRows.push(currentRow);
    return formattedRows;
  }

  $: formattedPhrase = getFormattedPhrase(phrase);

  // ==========================
  // 💢 Handle Shake Animations
  // ==========================
  let shakeIndexes = new Set();
  let lastProcessedShakes = [];

  function triggerShake(indexes) {
    shakeIndexes = new Set(indexes);
    setTimeout(() => {
      shakeIndexes.clear();
      gameStore.update(state => ({ ...state, shakenLetters: [] }));
    }, 1000);
  }

  $: if ($gameStore.shakenLetters?.length > 0) {
    if (JSON.stringify($gameStore.shakenLetters) !== JSON.stringify(lastProcessedShakes)) {
      triggerShake([...$gameStore.shakenLetters]);
      lastProcessedShakes = [...$gameStore.shakenLetters];
    }
  }

  // ==========================
  // 🔢 Global Index Helper
  // ==========================
  function getGlobalIndex(wordIndex, letterIndex) {
    const words = $gameStore.currentPhrase.split(' ');
    let offset = 0;
    for (let i = 0; i < wordIndex; i++) {
      offset += words[i].length + 1;
    }
    return offset + letterIndex;
  }

  // ==========================
  // 🧠 Reveal Animation (Loss)
  // ==========================
  let revealInterval;
  let revealed = [];

  $: if ($gameStore.gameState === 'lost') {
    if (revealed.length === 0) {
      const fullPhrase = $gameStore.currentPhrase;
      let i = 0;

      revealInterval = setInterval(() => {
        revealed[i] = fullPhrase[i];
        revealed = [...revealed];
        i++;

        if (i >= fullPhrase.length) {
          clearInterval(revealInterval);
          dispatch('revealComplete'); // ✅ Modal shows after phrase fills
        }
      }, 300);
    }
  } else {
    revealed = [];
    clearInterval(revealInterval);
  }

  // ==========================
  // 🎉 Dispatch on Win
  // ==========================
  $: if ($gameStore.gameState === 'won') {
    setTimeout(() => {
      dispatch('revealComplete');
    }, 500); // Optional short delay after "Winner!" banner/confetti
  }

  onDestroy(() => {
    clearInterval(revealInterval);
  });

  // ==========================
  // 🎯 Guess Mode Active Slot
  // ==========================
  $: activeGuessIndex =
    $gameStore.gameState === 'guess_mode'
      ? (() => {
          const phrase = $gameStore.currentPhrase;
          const editableIndices = [];

          for (let i = 0; i < phrase.length; i++) {
            if (phrase[i] === ' ') continue;
            if ($gameStore.purchasedLetters[i] === phrase[i]) continue;
            editableIndices.push(i);
          }

          if (editableIndices.length === 0) return -1;

          for (const idx of editableIndices) {
            if (!$gameStore.guessedLetters[idx]) return idx;
          }

          return editableIndices[editableIndices.length - 1];
        })()
      : -1;
</script>

<!-- Display formatted phrase lines (for non-interactive preview) -->
<div class="phrase-display">
  {#each formattedPhrase as line}
    <div class="phrase-line">{line}</div>
  {/each}
</div>

<!-- Render phrase based on current game state -->
{#if $gameStore.gameState === 'lost'}
  <!-- Lost Mode: Gradually reveal the full phrase -->
  <div class="phrase-container">
    {#each $gameStore.currentPhrase.split(' ') as word, wIndex}
      <div class="word">
        {#each word.split('') as letter, cIndex}
          <span class="letter-box">
            {revealed[getGlobalIndex(wIndex, cIndex)] ? revealed[getGlobalIndex(wIndex, cIndex)] : "_"}
          </span>
        {/each}
      </div>
    {/each}
  </div>
{:else if $gameStore.gameState === 'guess_mode'}
  <!-- Guess Mode: Show purchased letters and input guesses -->
  <div class="phrase-container">
    {#each $gameStore.currentPhrase.split(' ') as word, wIndex}
      <div class="word">
        {#each word.split('') as letter, cIndex}
          {#if $gameStore.purchasedLetters[getGlobalIndex(wIndex, cIndex)] === letter}
            <span class="letter-box locked {shakeIndexes.has(getGlobalIndex(wIndex, cIndex)) ? 'shake' : ''}">
              {letter}
            </span>
          {:else}
            <span class="letter-box {getGlobalIndex(wIndex, cIndex) === activeGuessIndex ? 'active' : ''}">
              {$gameStore.guessedLetters[getGlobalIndex(wIndex, cIndex)] || ""}
            </span>
          {/if}
        {/each}
      </div>
    {/each}
  </div>
{:else}
  <!-- Default Mode: Display only purchased letters with potential shake animation -->
  <div class="phrase-container">
    {#each $gameStore.currentPhrase.split(' ') as word, wIndex}
      <div class="word">
        {#each word.split('') as letter, cIndex}
          <span class="letter-box {shakeIndexes.has(getGlobalIndex(wIndex, cIndex)) ? 'shake' : ''}">
            {$gameStore.purchasedLetters[getGlobalIndex(wIndex, cIndex)] || ""}
          </span>
        {/each}
      </div>
    {/each}
  </div>
{/if}

<style>
  /* ---------------------------
     Shake Animation for Letters
  --------------------------- */
  @keyframes shake {
    0%   { transform: translateX(0) scale(1); }
    10%  { transform: translateX(-6px) scale(1.1); }
    20%  { transform: translateX(6px) scale(1.2); }
    30%  { transform: translateX(-5px) scale(1.1); }
    40%  { transform: translateX(5px) scale(1.2); }
    50%  { transform: translateX(-4px) scale(1.1); }
    60%  { transform: translateX(4px) scale(1.2); }
    70%  { transform: translateX(-3px) scale(1.1); }
    80%  { transform: translateX(3px) scale(1.1); }
    90%  { transform: translateX(-2px) scale(1); }
    100% { transform: translateX(0) scale(1); }
  }
  .shake {
    animation: shake 2s ease-in-out;
  }

  /* ---------------------------
     Layout for Phrase Display
  --------------------------- */
  .phrase-container {
    display: flex;
    grid-template-columns: repeat(auto-fit, minmax(1fr, 1fr)); /* Responsive columns */
    flex-wrap: wrap;
    width: 100%; /* Full viewport width */
    max-width: 100vw; /* Ensure it never exceeds viewport */
    padding: 0; /* Remove any padding */
    margin: 0 0; /* Remove extra margins */
    gap: 1px; /* Minimize space between boxes */
    justify-content: center;
    align-items: center;
    box-sizing: border-box;
    overflow-x: hidden;
    text-align: center;
    margin-top: 40px;
  }
  .word {
    display: flex;
    gap: 0px;
    flex-wrap: wrap;
    justify-content: center;
    align-items: center;
    margin-right: 15px;
    text-align: center;
  }
  .letter-box {
    width: 50px;
    height: 50px;
    padding: 0px;
    flex-grow: 1;
    max-width: 50px; /* Prevents it from getting too big */
    height: auto; /* Adjust height automatically */
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
    border: 2px solid #453d3d;
    background-color: #fff;
    font-size: 24px;
    font-weight: bold;
    border-radius: 5px;
    box-shadow: 3px 3px 5px rgba(0, 0, 0, 0.3);
    word-break: break-word;
    overflow-wrap: break-word;
    color: black;
    background: linear-gradient(145deg, #dfe6e9, #ffffff);

  }
  .letter-box.locked {
    color: black !important;
    font-weight: bold;
  }
  .letter-box.active {
    border: 3px solid #41ae29 !important;  /* Same green as main guess button */
    color: black !important;
}

  html, body {
    margin: 0;
    padding: 0;
    width: 100vw;
    overflow-x: hidden;
}


  /* ---------------------------
     Guess Mode Styling
  --------------------------- */
  :global(body.guess-mode) .phrase-container {
    animation: blinkingBorder 1.5s infinite;
  }
  @keyframes blinkingBorder {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
  }

  /* ---------------------------
     Responsive Adjustments
  --------------------------- */
  @media (max-width: 480px) {
    .letter-box {
      width: 28px;
      height: 50px;
      font-size: 25px;
    }
  }

  /* ---------------------------
     Formatted Phrase Preview
  --------------------------- */
  .phrase-display {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 5px;
    margin-bottom: 10px;
    font-size: 1.5rem;
    font-weight: bold;
    text-transform: uppercase;
    justify-content: center;  /* Centers horizontally */
  align-items: center;      /* Centers vertically (if needed) */
  text-align: center;       /* Ensures text stays centered */
  }
  .phrase-line {
    hyphens: auto;
    -webkit-hyphens: auto;
    -moz-hyphens: auto;
    word-break: break-word;
  }
</style>
