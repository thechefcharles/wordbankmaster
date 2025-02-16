<script>
  import { gameStore } from '$lib/stores/GameStore.js';

  // Compute the active guess index in guess mode
  $: activeGuessIndex = (() => {
    if ($gameStore.gameState !== 'guess_mode') return -1;
    const editableIndices = [];
    for (let i = 0; i < $gameStore.currentPhrase.length; i++) {
      if ($gameStore.currentPhrase[i] === ' ') continue;
      if ($gameStore.purchasedLetters[i] === $gameStore.currentPhrase[i]) continue;
      editableIndices.push(i);
    }
    if (editableIndices.length === 0) return -1;
    // Return the first index that hasn't been guessed
    for (const idx of editableIndices) {
      if (!$gameStore.guessedLetters[idx]) return idx;
    }
    // Otherwise, return the last one
    return editableIndices[editableIndices.length - 1];
  })();

  /**
   * getGlobalIndex(wordIndex, letterIndex):
   * Computes the global index for a letter at (wordIndex, letterIndex)
   * by summing the lengths of all previous words + 1 space for each.
   */
  function getGlobalIndex(wordIndex, letterIndex) {
    const words = $gameStore.currentPhrase.split(' ');
    let offset = 0;
    for (let w = 0; w < wordIndex; w++) {
      offset += words[w].length + 1; // length of that word + 1 space
    }
    return offset + letterIndex;
  }
</script>

{#if $gameStore.gameState === 'guess_mode'}
  <!-- GUESS MODE: show guessed letters or locked letters per index -->
  <div class="phrase-container">
    {#each $gameStore.currentPhrase.split(' ') as word, wIndex}
      <div class="word">
        {#each word.split('') as letter, cIndex}
          {#if $gameStore.purchasedLetters[getGlobalIndex(wIndex, cIndex)] === letter}
            <!-- If purchasedLetters at that index is correct, show locked -->
            <span class="letter-box locked">
              {letter}
            </span>
          {:else}
            <!-- Otherwise, display guessed letter if any -->
            <span
              class="letter-box {getGlobalIndex(wIndex, cIndex) === activeGuessIndex ? 'active' : ''}"
            >
              {$gameStore.guessedLetters[getGlobalIndex(wIndex, cIndex)] || ""}
            </span>
          {/if}
        {/each}
      </div>
    {/each}
  </div>
{:else}
  <!-- DEFAULT MODE: Show only locked (purchased) letters -->
  <div class="phrase-container">
    {#each $gameStore.currentPhrase.split(' ') as word, wIndex}
      <div class="word">
        {#each word.split('') as letter, cIndex}
          <span class="letter-box">
            {
              $gameStore.purchasedLetters[getGlobalIndex(wIndex, cIndex)]
                ? $gameStore.purchasedLetters[getGlobalIndex(wIndex, cIndex)]
                : ""
            }
          </span>
        {/each}
      </div>
    {/each}
  </div>
{/if}

<style>
  /* Container that holds all words (stacked vertically) */
  .phrase-container {
    display: flex;
    flex-direction: column;
    align-items: center;  /* center each row */
    gap: 10px;            /* spacing between rows (words) */
    margin: 20px 0;
  }

  /* Each word is rendered as a row of letter-boxes */
  .word {
    display: flex;
    gap: 8px; /* spacing between letters in a word */
  }

  /* Each letter box is bigger, with subtle styling */
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
    border-radius: 5px;   /* slightly rounded corners */
    box-shadow: 0 2px 4px rgba(0,0,0,0.1); /* subtle shadow */
  }

  /* Highlight the active guess slot in guess mode */
  .letter-box.active {
    border-color: orange;
  }

  /* If a letter is locked/purchased, give it a subtle background */
  .letter-box.locked {
    background-color: #eee;
  }
</style>
