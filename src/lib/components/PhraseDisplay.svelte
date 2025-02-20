<script>
  import { gameStore } from '$lib/stores/GameStore.js';
  import { onDestroy } from 'svelte';
  import { derived } from "svelte/store";

  

  // Track the phrase and word breaks
  $: phrase = $gameStore.phrase || "";  
  let maxLettersPerRow = 10; // Adjust based on your design

  // Function to format phrase with hyphens
  function formatPhrase(phrase) {
    let words = phrase.split(" "); // Split into words
    let formattedPhrase = [];
    let currentRow = "";
    
    for (let word of words) {
      if (currentRow.length + word.length + 1 > maxLettersPerRow) {
        // If adding the word exceeds the row limit, insert a hyphen
        if (currentRow.length > 0) {
          formattedPhrase.push(currentRow + "-");
        }
        currentRow = word; // Start new row
      } else {
        // Append the word to the current row
        currentRow += (currentRow.length > 0 ? " " : "") + word;
      }
    }

    // Push the last row
    if (currentRow) formattedPhrase.push(currentRow);

    return formattedPhrase;
  }

  // Derive formatted phrase for display
  $: displayedPhrase = formatPhrase(phrase);

  // ----------------------------
  // Local State for Shake Animation
  // ----------------------------
  let shakeIndexes = new Set();
  let lastProcessedShakes = [];

  // Watch for new shaken letters in the store.
  // When new indices are detected, trigger the shake effect.
  $: if ($gameStore.shakenLetters?.length > 0) {
    if (JSON.stringify($gameStore.shakenLetters) !== JSON.stringify(lastProcessedShakes)) {
      triggerShake([...$gameStore.shakenLetters]);
      lastProcessedShakes = [...$gameStore.shakenLetters];
    }
  }

  // Trigger shake animation on given letter indexes.
  // After 1 second, clear the shake effect and reset shakenLetters in the store.
  function triggerShake(indexes) {
    shakeIndexes = new Set(indexes);
    setTimeout(() => {
      shakeIndexes.clear();
      gameStore.update(state => ({
        ...state,
        shakenLetters: []
      }));
    }, 1000);
  }

  // ----------------------------
  // Helper: Global Index Calculation
  // ----------------------------
  // Converts a (wordIndex, letterIndex) into a global index in the phrase.
  function getGlobalIndex(wordIndex, letterIndex) {
    const words = $gameStore.currentPhrase.split(' ');
    let offset = 0;
    for (let i = 0; i < wordIndex; i++) {
      // Each word length plus one for the space
      offset += words[i].length + 1;
    }
    return offset + letterIndex;
  }

  // ----------------------------
  // Animate Phrase Reveal When Game is Lost
  // ----------------------------
  let interval;
  let revealed = [];

  // When game state is "lost", gradually reveal each letter.
  $: if ($gameStore.gameState === 'lost') {
    if (revealed.length === 0) {
      const phrase = $gameStore.currentPhrase;
      let i = 0;
      interval = setInterval(() => {
        revealed[i] = phrase[i];
        // Force reactivity
        revealed = [...revealed];
        i++;
        if (i >= phrase.length) clearInterval(interval);
      }, 300);
    }
  } else {
    // Reset when not lost
    revealed = [];
    clearInterval(interval);
  }

  // Clean up the interval on component destruction.
  onDestroy(() => {
    clearInterval(interval);
  });

  // ----------------------------
  // Active Guess Index in Guess Mode
  // ----------------------------
  // Compute the next editable index for guess mode.
  $: activeGuessIndex = (
    $gameStore.gameState === 'guess_mode'
      ? (() => {
          const phrase = $gameStore.currentPhrase;
          const indices = [];
          for (let i = 0; i < phrase.length; i++) {
            if (phrase[i] === ' ') continue;
            if ($gameStore.purchasedLetters[i] === phrase[i]) continue;
            indices.push(i);
          }
          if (indices.length === 0) return -1;
          // Return the first index that hasn't been guessed yet,
          // or the last one if all are filled.
          for (const idx of indices) {
            if (!$gameStore.guessedLetters[idx]) return idx;
          }
          return indices[indices.length - 1];
        })()
      : -1
  );
</script>

<!-- Render the formatted phrase -->
<div class="phrase-display">
  {#each displayedPhrase as line}
    <div class="phrase-line">{line}</div>
  {/each}
</div>



<!--
  Render the phrase differently based on game state:
  - LOST MODE: Reveal entire phrase gradually.
  - GUESS MODE: Display purchased letters; empty slots show user guesses.
  - DEFAULT MODE: Display current purchased letters, with shake animation if needed.
-->
{#if $gameStore.gameState === 'lost'}
  <!-- Lost Mode: Reveal the entire phrase -->
  <div class="phrase-container">
    {#each $gameStore.currentPhrase.split(' ') as word, wIndex}
      <div class="word">
        {#each word.split('') as letter, cIndex}
          <span class="letter-box">
            {revealed[getGlobalIndex(wIndex, cIndex)] 
              ? revealed[getGlobalIndex(wIndex, cIndex)] 
              : "_"}
          </span>
        {/each}
      </div>
    {/each}
  </div>
{:else if $gameStore.gameState === 'guess_mode'}
  <!-- Guess Mode: Show purchased letters and guess inputs -->
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
  <!-- Default Mode: Display purchased letters with shake animation if applicable -->
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
     Layout for the Phrase Display
  --------------------------- */
  .phrase-container {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 10px;
    margin: 10px 0;
    max-width: 100%;
    box-sizing: border-box;
    overflow-x: hidden;
  }
  .word {
    display: flex;
    gap: 2px;
    flex-wrap: wrap;
    justify-content: center;
    margin-right: 15px;
  }
  .letter-box {
    width: 50px;
    height: 50px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 2px solid #333;
    background-color: #fff;
    font-size: 24px;
    font-weight: bold;
    border-radius: 5px;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    word-break: break-word;
    overflow-wrap: break-word;
    color: black;
  }
  .letter-box.locked {
    /* Locked letters (correctly purchased) */
    color: black !important;
    font-weight: bold;
  }
  .letter-box.active {
    /* Active guess slot styling */
    border: 3px solid orange !important;
    color: black !important;
  }

  /* ---------------------------
     Guess Mode Blinking Border 
  --------------------------- */
  :global(body.guess-mode) .phrase-container {
    border: 5px solid orange !important;
    background-color: rgba(255, 165, 0, 0.2);
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
      width: 30px;
      height: 30px;
      font-size: 18px;
    }
  }

  .phrase-line {
  display: flex;
  justify-content: center;
  gap: 5px;
  font-size: 1.5rem;
  font-weight: bold;
  text-transform: uppercase;
}

.phrase-line::after {
  content: "";
  display: inline-block;
  width: 0;
}

.phrase-line:last-child::after {
  content: ""; /* Ensures no hyphen at the end of the last row */
}

.phrase-line {
  hyphens: auto;
  -webkit-hyphens: auto;
  -moz-hyphens: auto;
  word-break: break-word;
  /* ...other styles... */
}


</style>
