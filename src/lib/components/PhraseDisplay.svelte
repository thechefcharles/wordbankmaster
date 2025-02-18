<script>
  import { gameStore } from '$lib/stores/GameStore.js';
  import { onDestroy } from 'svelte';

  // Helper: Computes the global index (across the full phrase)
  function getGlobalIndex(wordIndex, letterIndex) {
    const words = $gameStore.currentPhrase.split(' ');
    let offset = 0;
    for (let i = 0; i < wordIndex; i++) {
      offset += words[i].length + 1; // space
    }
    return offset + letterIndex;
  }

  // Reactive: active guess index for guess mode
  $: activeGuessIndex = $gameStore.gameState === 'guess_mode'
    ? (() => {
        const phrase = $gameStore.currentPhrase;
        const indices = [];
        for (let i = 0; i < phrase.length; i++) {
          if (phrase[i] === ' ') continue;
          if ($gameStore.purchasedLetters[i] === phrase[i]) continue;
          indices.push(i);
        }
        if (indices.length === 0) return -1;
        for (const idx of indices) {
          if (!$gameStore.guessedLetters[idx]) return idx;
        }
        return indices[indices.length - 1];
      })()
    : -1;

  // Letter-by-letter reveal on loss
  let interval;
  let revealed = []; // array to store revealed letters

  $: if ($gameStore.gameState === 'lost') {
    if (revealed.length === 0) {
      const phrase = $gameStore.currentPhrase;
      let i = 0;
      interval = setInterval(() => {
        revealed[i] = phrase[i];
        revealed = [...revealed]; // trigger reactivity
        i++;
        if (i >= phrase.length) {
          clearInterval(interval);
        }
      }, 300); // reveal speed
    }
  } else {
    // reset if not lost
    revealed = [];
    clearInterval(interval);
  }

  onDestroy(() => {
    clearInterval(interval);
  });
</script>

<!-- LOST MODE -->
{#if $gameStore.gameState === 'lost'}
  <div class="phrase-container">
    {#each $gameStore.currentPhrase.split(' ') as word, wIndex}
      <div class="word">
        {#each word.split('') as letter, cIndex}
          <span class="letter-box">
            { revealed[getGlobalIndex(wIndex, cIndex)]
              ? revealed[getGlobalIndex(wIndex, cIndex)]
              : "_" }
          </span>
        {/each}
      </div>
    {/each}
  </div>

<!-- GUESS MODE -->
{:else if ($gameStore.gameState === 'guess_mode')}
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

<!-- DEFAULT MODE -->
{:else}
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
  /* Container that holds all words/letters */
  .phrase-container {
    display: flex;
    flex-direction: row;
    flex-wrap: wrap;      /* allow line wraps */
    justify-content: center;
    gap: 10px;
    margin: 20px 0;
    max-width: 100%;      /* never exceed screen width */
    box-sizing: border-box; 
    overflow-x: hidden;   /* hide any accidental overflow */
  }

  .word {
  display: flex;
  gap: 2px; /* Adjusts spacing between letters within a word */
  flex-wrap: wrap; /* Allows words to break into new lines */
  justify-content: center;
  max-width: 100%;
  margin-right: 4px; /* Adds space between words */
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
  word-break: break-word; /* Break long words instead of shrinking */
  overflow-wrap: break-word; /* Ensures break works in all browsers */
}
  /* highlight letter in guess mode */
  .letter-box.active {
    border-color: orange;
  }

  /* purchased letters */
  .letter-box.locked {
    background-color: #eee;
  }

  /* letter animation in lost mode */
  .phrase-container .letter {
    font-size: 32px;
    font-weight: bold;
    padding: 0 5px;
    transition: opacity 0.3s ease-in;
  }

  /* Shrink boxes on smaller screens (e.g. iPhone SE) */
  @media (max-width: 480px) {
    .letter-box {
      width: 30px;
      height: 30px;
      font-size: 18px;
    }
  }
</style>
