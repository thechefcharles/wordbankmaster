<script>
  import { gameStore } from '$lib/stores/GameStore.js';
  import { onDestroy } from 'svelte';

  // ----------------------------
  // PHRASE FORMATTING
  // ----------------------------

  // Reactive: current phrase from game store
  $: phrase = $gameStore.phrase || "";
  // Maximum characters per row (for hyphenation/line breaks)
  let maxLettersPerRow = 10;

  /**
   * getFormattedPhrase
   * Splits the phrase into rows with hyphenation if needed.
   *
   * @param {string} phrase - The current phrase.
   * @returns {string[]} Array of formatted rows.
   */
  function getFormattedPhrase(phrase) {
    const words = phrase.split(" ");
    const formattedRows = [];
    let currentRow = "";

    for (const word of words) {
      // +1 for space between words
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

  // Reactive: derive formatted phrase for display
  $: formattedPhrase = getFormattedPhrase(phrase);

  // ----------------------------
  // SHAKE ANIMATION HANDLING
  // ----------------------------
  let shakeIndexes = new Set();
  let lastProcessedShakes = [];

  /**
   * triggerShake
   * Activates the shake animation for specified letter indexes.
   *
   * @param {number[]} indexes - Array of letter indexes to shake.
   */
  function triggerShake(indexes) {
    shakeIndexes = new Set(indexes);
    setTimeout(() => {
      shakeIndexes.clear();
      // Reset shakenLetters in the store after animation completes
      gameStore.update(state => ({ ...state, shakenLetters: [] }));
    }, 1000);
  }

  // Watch for changes in shakenLetters from the store
  $: if ($gameStore.shakenLetters?.length > 0) {
    if (JSON.stringify($gameStore.shakenLetters) !== JSON.stringify(lastProcessedShakes)) {
      triggerShake([...$gameStore.shakenLetters]);
      lastProcessedShakes = [...$gameStore.shakenLetters];
    }
  }

  // ----------------------------
  // GLOBAL INDEX CALCULATION
  // ----------------------------
  /**
   * getGlobalIndex
   * Converts (wordIndex, letterIndex) into a global index within the phrase.
   *
   * @param {number} wordIndex - Index of the word.
   * @param {number} letterIndex - Index of the letter within the word.
   * @returns {number} Global index in the full phrase.
   */
  function getGlobalIndex(wordIndex, letterIndex) {
    const words = $gameStore.currentPhrase.split(' ');
    let offset = 0;
    for (let i = 0; i < wordIndex; i++) {
      offset += words[i].length + 1; // include space
    }
    return offset + letterIndex;
  }

  // ----------------------------
  // PHRASE REVEAL (LOSS MODE)
  // ----------------------------
  let revealInterval;
  let revealed = [];

  // Reactive: if game is lost, gradually reveal the entire phrase letter by letter
  $: if ($gameStore.gameState === 'lost') {
    if (revealed.length === 0) {
      const fullPhrase = $gameStore.currentPhrase;
      let i = 0;
      revealInterval = setInterval(() => {
        revealed[i] = fullPhrase[i];
        // Force reactivity by creating a new array
        revealed = [...revealed];
        i++;
        if (i >= fullPhrase.length) clearInterval(revealInterval);
      }, 300);
    }
  } else {
    // Reset reveal state when not lost
    revealed = [];
    clearInterval(revealInterval);
  }

  // Clean up interval on component destruction
  onDestroy(() => {
    clearInterval(revealInterval);
  });

  // ----------------------------
  // ACTIVE GUESS SLOT CALCULATION
  // ----------------------------
  /**
   * Determine the next editable index for guess mode.
   * Returns the first index that hasn't been guessed, or the last one if all are filled.
   */
  $: activeGuessIndex =
    $gameStore.gameState === 'guess_mode'
      ? (() => {
          const fullPhrase = $gameStore.currentPhrase;
          const editableIndices = [];
          for (let i = 0; i < fullPhrase.length; i++) {
            if (fullPhrase[i] === ' ') continue;
            if ($gameStore.purchasedLetters[i] === fullPhrase[i]) continue;
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
    animation: shake 1s ease-in-out;
  }

  /* ---------------------------
     Layout for Phrase Display
  --------------------------- */
  .phrase-container {
    display: flex;
    flex-wrap: wrap;
    flex-direction: row;
    width: auto; /* Full viewport width */
    max-width: 100%; /* Ensure it never exceeds viewport */
    max-height: fit-content;
    padding: 0px 0px; /* 🔹 Adjust padding */
    margin: 0px 0px; /* Remove extra margins */
    gap: 20px; /* Minimize space between boxes */
    justify-content: center;
    align-items: center;
    box-sizing: border-box;
    overflow: visible;
    text-align: center;
    line-height: 1px;
    margin-top: 30px;
    margin-bottom: 2px;
    height: 200px;
    
  }
  .word {
    display: flex;
    gap: 2px;
    flex-wrap: wrap;
    justify-content: center;
    align-items: center;
    margin-right: 0px;
    margin-left: 0px;
    margin-bottom: -15px;
    text-align: center;
  }
  .letter-box {
    width: 50px;
    height: 50px;
    padding: 0px;
    flex-grow: 1;
    max-width: 50px; /* Prevents it from getting too big */
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
    border: 3px solid #453d3d;
    background-color: #fff;
    font-size: 24px;
    font-weight: bold;
    border-radius: 5px;
    box-shadow: 3px 3px 5px rgba(0, 0, 0, 0.3);
    word-break: break-word;
    overflow-wrap: break-word;
    color: black;
    background: linear-gradient(145deg, #dfe6e9, #ffffff);
    box-shadow: inset -2px -2px 5px rgba(255, 255, 255, 0.8),
                inset 2px 2px 5px rgba(0, 0, 0, 0.3);

  }

  
  .letter-box.locked {
    color: black !important;
    font-weight: bold;
  }
  .letter-box.active {
    border: 3px solid orange !important;
    color: black !important;
  }

   /* ---------------------------
     Responsive Adjustments
  --------------------------- */
  @media (max-width: 480px) {
    .letter-box {
      width: 25px;
      height: 50px;
      font-size: 25px;
    }
  }

  html, body {
    margin: 0;
    padding: 0;
    width: 100vw;
    height: 100vh; /* Prevents any extra scrolling */
    overflow: hidden; /* Remove unwanted scrolling */
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
}


  /* ---------------------------
     Guess Mode Styling
  --------------------------- */
  :global(body.guess-mode) .phrase-container {
    border-radius: 28px; /* 🔹 Rounded edges */
    padding: 0px 0px; /* 🔹 Added slight padding for better alignment */
    margin: 0 0; /* 🔹 Prevents unnecessary vertical movement */
    max-width: 100%; /* 🔹 Adjust width to fit content */
    max-height: fit-content;
    display: flex;
    justify-content: center;
    align-items: center;
    flex-wrap: wrap;
    animation: blinkingBorder 1.5s infinite; /* 🔹 Optional blinking effect */
    height: 400px;
  }
  @keyframes blinkingBorder {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
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
  }
  .phrase-line {
    hyphens: auto;
    -webkit-hyphens: auto;
    -moz-hyphens: auto;
    word-break: break-word;
  }
</style>
