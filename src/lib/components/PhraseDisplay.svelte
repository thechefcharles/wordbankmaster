<script>
  import { gameStore } from '$lib/stores/GameStore.js';

  // Helper: Returns an array of editable indices (non‑space and not locked).
  function getEditableIndices(state) {
    const indices = [];
    const phrase = state.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if (state.purchasedLetters[i] === phrase[i]) continue;
      indices.push(i);
    }
    return indices;
  }

  // Reactive: Determine the active guess index.
  $: activeGuessIndex = $gameStore.gameState === 'guess_mode' ? (() => {
    const editable = getEditableIndices($gameStore);
    if (editable.length === 0) return -1;
    for (const idx of editable) {
      if (!$gameStore.guessedLetters[idx]) return idx;
    }
    // If every editable index has a guess, return the last one.
    return editable[editable.length - 1];
  })() : -1;

  // Helper: Computes the global index for a letter in the phrase.
  // Accounts for spaces between words.
  function getGlobalIndex(wordIndex, letterIndex) {
    const words = $gameStore.currentPhrase.split(' ');
    let offset = 0;
    for (let i = 0; i < wordIndex; i++) {
      offset += words[i].length + 1;
    }
    return offset + letterIndex;
  }
</script>

{#if $gameStore.gameState === 'guess_mode'}
  <!-- Guess Mode: Display guessed letters (or empty slots) with active highlighting -->
  <div class="phrase-container">
    {#each $gameStore.currentPhrase.split(' ') as word, wIndex}
      <div class="word">
        {#each word.split('') as letter, cIndex}
          {#if $gameStore.purchasedLetters[getGlobalIndex(wIndex, cIndex)] === letter}
            <span class="letter-box locked">{letter}</span>
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
  <!-- Default Mode: Show only the correctly purchased (locked) letters -->
  <div class="phrase-container">
    {#each $gameStore.currentPhrase.split(' ') as word, wIndex}
      <div class="word">
        {#each word.split('') as letter, cIndex}
          <span class="letter-box">
            { $gameStore.purchasedLetters[getGlobalIndex(wIndex, cIndex)] || "" }
          </span>
        {/each}
      </div>
    {/each}
  </div>
{/if}

<style>
  .phrase-container {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    margin: 20px 0;
  }
  .word {
    display: flex;
    gap: 8px;
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
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  }
  .letter-box.active {
    border-color: orange;
  }
  .letter-box.locked {
    background-color: #eee;
  }
  button:focus {
    outline: none;
  }
</style>
