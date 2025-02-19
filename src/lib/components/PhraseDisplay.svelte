<script>
  import { gameStore } from '$lib/stores/GameStore.js';
  import { onDestroy } from 'svelte';

  // Local set of indexes that should shake
  let shakeIndexes = new Set();

  // Track last processed shakes so we only trigger new ones
  let lastProcessedShakes = [];

  // Watch store for new shakenLetters if not in guess mode
  $: if (
    $gameStore.shakenLetters?.length > 0 &&
    $gameStore.gameState !== 'guess_mode'
  ) {
    // Compare with last processed
    if (JSON.stringify($gameStore.shakenLetters) !== JSON.stringify(lastProcessedShakes)) {
      triggerShake([...$gameStore.shakenLetters]);
      lastProcessedShakes = [...$gameStore.shakenLetters];
    }
  }

  function triggerShake(indexes) {
    shakeIndexes = new Set(indexes);
    setTimeout(() => {
      shakeIndexes.clear();
    }, 1000);
  }

  // Helper to compute global index across the full phrase
  function getGlobalIndex(wordIndex, letterIndex) {
    const words = $gameStore.currentPhrase.split(' ');
    let offset = 0;
    for (let i = 0; i < wordIndex; i++) {
      offset += words[i].length + 1; // +1 for the space
    }
    return offset + letterIndex;
  }

  // Animate reveal if lost
  let interval;
  let revealed = [];

  $: if ($gameStore.gameState === 'lost') {
    if (revealed.length === 0) {
      const phrase = $gameStore.currentPhrase;
      let i = 0;
      interval = setInterval(() => {
        revealed[i] = phrase[i];
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

  // For guess mode, track the currently "active" guess index
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
          for (const idx of indices) {
            if (!$gameStore.guessedLetters[idx]) return idx;
          }
          return indices[indices.length - 1];
        })()
      : -1
  );
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
            <span
              class="letter-box
                {getGlobalIndex(wIndex, cIndex) === activeGuessIndex ? 'active' : ''}"
            >
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
          <span
            class="letter-box {shakeIndexes.has(getGlobalIndex(wIndex, cIndex)) ? 'shake' : ''}"
          >
            {$gameStore.purchasedLetters[getGlobalIndex(wIndex, cIndex)] || ""}
          </span>
        {/each}
      </div>
    {/each}
  </div>
{/if}

<style>
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

  .letter-box.locked {
    color: black !important;
    font-weight: bold;
  }
  .letter-box.active {
    border: 3px solid orange !important;
    color: black !important;
  }
  .letter-box {
    color: black !important;
  }

  /* Glow effect for guess mode container */
  :global(body.guess-mode) .phrase-container {
    border: 6px solid orange !important;
    background-color: rgba(255, 165, 0, 0.2);
    animation: glowEffect 1.5s infinite alternate;
  }

  /* Smaller boxes on tiny screens */
  @media (max-width: 480px) {
    .letter-box {
      width: 30px;
      height: 30px;
      font-size: 18px;
    }
  }
</style>
