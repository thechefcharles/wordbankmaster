<script>
  import { gameStore } from '$lib/stores/GameStore.js';
  import { onDestroy } from 'svelte';

  // Helper: Computes the global index (across the full phrase)
  function getGlobalIndex(wordIndex, letterIndex) {
    const words = $gameStore.currentPhrase.split(' ');
    let offset = 0;
    for (let i = 0; i < wordIndex; i++) {
      // Add word length plus one for the space
      offset += words[i].length + 1;
    }
    return offset + letterIndex;
  }

  // Reactive: Compute the active guess index (for guess mode)
  $: activeGuessIndex = $gameStore.gameState === 'guess_mode'
    ? (() => {
        const phrase = $gameStore.currentPhrase;
        let indices = [];
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

  // --- New Code for Letter-By-Letter Reveal on Loss ---
  let interval;
  // 'revealed' will hold the letters as they are revealed
  let revealed = [];

  // When game state becomes "lost", start an interval to reveal letters one by one.
  $: if ($gameStore.gameState === 'lost') {
    if (revealed.length === 0) {
      const phrase = $gameStore.currentPhrase;
      let i = 0;
      interval = setInterval(() => {
        revealed[i] = phrase[i];
        // Trigger reactivity by creating a new array reference.
        revealed = [...revealed];
        i++;
        if (i >= phrase.length) {
          clearInterval(interval);
        }
      }, 300); // Adjust speed (ms) as desired.
    }
  } else {
    // Reset if game is not lost.
    revealed = [];
    clearInterval(interval);
  }

  onDestroy(() => {
    clearInterval(interval);
  });
</script>

{#if $gameStore.gameState === 'lost'}
  <!-- Lost Mode: Use the same word/letter layout -->
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
{:else if $gameStore.gameState === 'guess_mode'}
  <!-- Guess Mode: Existing display code -->
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
  <!-- Default Mode: Existing display code -->
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
    flex-direction: row;
    flex-wrap: wrap;
    justify-content: center;
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
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
  }
  .letter-box.active {
    border-color: orange;
  }
  .letter-box.locked {
    background-color: #eee;
  }
  /* Style for letter animation in lost mode */
  .phrase-container .letter {
    font-size: 32px;
    font-weight: bold;
    padding: 0 5px;
    transition: opacity 0.3s ease-in;
  }
</style>
