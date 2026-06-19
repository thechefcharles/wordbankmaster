<script>
  import { gameStore } from '$lib/stores/GameStore.js';
  import { onDestroy, createEventDispatcher } from 'svelte';
  import { getGlobalIndex } from '$lib/helpers/gameUtils.js';

  const dispatch = createEventDispatcher();

  // 📤 Reactive State Setup

  // 💢 Shake Animation
  let shakeIndexes = new Set();
  /** @type {number[]} */
  let lastProcessedShakes = [];

  /** @param {number[]} indexes */
  function triggerShake(indexes) {
    shakeIndexes = new Set(indexes);
    setTimeout(() => {
      shakeIndexes.clear();
      gameStore.update(state => ({ ...state, shakenLetters: [] }));
    }, 1000);
  }

  $: if ($gameStore.shakenLetters?.length > 0 &&
         JSON.stringify($gameStore.shakenLetters) !== JSON.stringify(lastProcessedShakes)) {
    triggerShake([...$gameStore.shakenLetters]);
    lastProcessedShakes = [...$gameStore.shakenLetters];
  }

  // 🧠 Reveal Animation (Loss)
  /** @type {ReturnType<typeof setInterval> | undefined} */
  let revealInterval;
  /** @type {string[]} */
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
          dispatch('revealComplete');
        }
      }, 300);
    }
  } else {
    revealed = [];
    clearInterval(revealInterval);
  }

  $: if ($gameStore.gameState === 'won') {
    setTimeout(() => {
      dispatch('revealComplete');
    }, 500);
  }

  onDestroy(() => clearInterval(revealInterval));

  // 🎯 Active Guess Slot Logic
  $: activeGuessIndex = $gameStore.gameState === 'guess_mode'
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


<!-- Render Game Phrase -->
<div class="phrase-container">
  {#each $gameStore.currentPhrase.split(' ') as word, wIndex}
    <div class="word">
      {#each word.split('') as letter, cIndex}
        {#key `${wIndex}-${cIndex}`}
          {#if $gameStore.gameState === 'lost'}
            <span class="letter-box">
              {revealed[getGlobalIndex(wIndex, cIndex, $gameStore.currentPhrase)] || "_"}
            </span>

          {:else if $gameStore.gameState === 'guess_mode'}
            {#if $gameStore.purchasedLetters[getGlobalIndex(wIndex, cIndex, $gameStore.currentPhrase)] === letter}
              <span class="letter-box locked {shakeIndexes.has(getGlobalIndex(wIndex, cIndex, $gameStore.currentPhrase)) ? 'shake' : ''}">
                {letter}
              </span>
            {:else}
              <span class="letter-box {getGlobalIndex(wIndex, cIndex, $gameStore.currentPhrase) === activeGuessIndex ? 'active' : ''}">
                {$gameStore.guessedLetters[getGlobalIndex(wIndex, cIndex, $gameStore.currentPhrase)] || ""}
              </span>
            {/if}

          {:else}
            <span class="letter-box {shakeIndexes.has(getGlobalIndex(wIndex, cIndex, $gameStore.currentPhrase)) ? 'shake' : ''}">
              {$gameStore.purchasedLetters[getGlobalIndex(wIndex, cIndex, $gameStore.currentPhrase)] || ""}
            </span>
          {/if}
        {/key}
      {/each}
    </div>
  {/each}
</div>
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
    flex-wrap: wrap;
    width: 100%;
    max-width: 100vw;
    padding: 0;
    margin: 22px 0 12px 0;
    gap: 1px;
    justify-content: center;
    align-items: center;
    box-sizing: border-box;
    overflow-x: hidden;
    text-align: center;
  }
  .word {
    display: flex;
    gap: 0px;
    flex-wrap: wrap;
    justify-content: center;
    align-items: center;
    margin-right: 10px;
    text-align: center;
  }
  .letter-box {
    width: 40px;
    min-width: 40px;
    height: 44px;
    min-height: 44px;
    padding: 0;
    flex-shrink: 0; /* Prevent collapse when empty */
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
    border: 2px solid #453d3d;
    background: linear-gradient(145deg, #dfe6e9, #ffffff);
    font-size: 20px;
    font-weight: bold;
    border-radius: 6px;
    box-shadow:
      inset 1px 1px 3px rgba(255, 255, 255, 0.8),
      1px 1px 3px rgba(0, 0, 0, 0.2),
      0 0 0 1px rgba(0, 0, 0, 0.05);
    color: black;
    box-sizing: border-box;
  }
  .letter-box.locked {
    color: black !important;
    font-weight: bold;
  }
  .letter-box.active {
    border: 3px solid #41ae29 !important;  /* Same green as main guess button */
    color: black !important;
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
      width: 32px;
      min-width: 32px;
      height: 36px;
      min-height: 36px;
      font-size: 16px;
    }
    .phrase-container {
      margin: 16px 0 10px 0;
    }
  }
</style>
