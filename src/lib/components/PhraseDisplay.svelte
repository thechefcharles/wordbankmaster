<script>
  import { gameStore } from '$lib/stores/GameStore.js';
  import { onDestroy } from 'svelte';

  // Local set to store indexes that should currently shake
  let shakeIndexes = new Set();
  // Local copy of the last shaken indexes we’ve already processed
  let lastProcessedShakes = [];

  // Function to trigger shake animation on given indexes.
  // Once triggered, those indexes will shake for 1 second.
  function triggerShake(indexes) {
    shakeIndexes = new Set(indexes);
    setTimeout(() => {
      // We clear the local animation, but we do NOT clear the store's shakenLetters.
      shakeIndexes.clear();
    }, 1000);
  }

  // Only trigger shake when new indexes are added (and we’re not in guess mode).
  $: if (
    $gameStore.shakenLetters?.length > 0 &&
    $gameStore.gameState !== 'guess_mode'
  ) {
    // Compare with our local lastProcessedShakes.
    if (JSON.stringify($gameStore.shakenLetters) !== JSON.stringify(lastProcessedShakes)) {
      triggerShake([...$gameStore.shakenLetters]);
      // Update our record so that the same indexes won’t re-trigger.
      lastProcessedShakes = [...$gameStore.shakenLetters];
    }
  }

  // Helper: Computes the global index (across the full phrase)
  function getGlobalIndex(wordIndex, letterIndex) {
    const words = $gameStore.currentPhrase.split(' ');
    let offset = 0;
    for (let i = 0; i < wordIndex; i++) {
      offset += words[i].length + 1; // account for space
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

  // For lost mode: reveal letters gradually
  let interval;
  let revealed = [];
  $: if ($gameStore.gameState === 'lost') {
    if (revealed.length === 0) {
      const phrase = $gameStore.currentPhrase;
      let i = 0;
      interval = setInterval(() => {
        revealed[i] = phrase[i];
        // Trigger reactivity by reassigning a copy of the array
        revealed = [...revealed];
        i++;
        if (i >= phrase.length) clearInterval(interval);
      }, 300);
    }
  } else {
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
            {revealed[getGlobalIndex(wIndex, cIndex)] ? revealed[getGlobalIndex(wIndex, cIndex)] : "_"}
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
          <span class="letter-box {shakeIndexes.has(getGlobalIndex(wIndex, cIndex)) ? 'shake' : ''}">
            {$gameStore.purchasedLetters[getGlobalIndex(wIndex, cIndex)] || ""}
          </span>
        {/each}
      </div>
    {/each}
  </div>
{/if}

<style>
  /* Enhanced Shake Animation with Pop-Out Effect */
  @keyframes shake {
    0% { transform: translateX(0) scale(1); }
    10% { transform: translateX(-6px) scale(1.1); }
    20% { transform: translateX(6px) scale(1.2); }
    30% { transform: translateX(-5px) scale(1.1); }
    40% { transform: translateX(5px) scale(1.2); }
    50% { transform: translateX(-4px) scale(1.1); }
    60% { transform: translateX(4px) scale(1.2); }
    70% { transform: translateX(-3px) scale(1.1); }
    80% { transform: translateX(3px) scale(1.1); }
    90% { transform: translateX(-2px) scale(1); }
    100% { transform: translateX(0) scale(1); }
  }

  /* Apply shake animation */
  .shake {
    animation: shake 1s ease-in-out;
  }

  /* Container for the phrase */
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
  }

  /* Highlight active guess letter */
  .letter-box.active {
    border-color: orange;
  }

  /* Locked (purchased) letters */
  .letter-box.locked {
    background-color: #eee;
  }

  /* Shrink boxes on smaller screens */
  @media (max-width: 480px) {
    .letter-box {
      width: 30px;
      height: 30px;
      font-size: 18px;
    }
  }
</style>
