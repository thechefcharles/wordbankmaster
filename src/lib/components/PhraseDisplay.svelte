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
    width: 42px;
    min-width: 42px;
    height: 48px;
    min-height: 48px;
    padding: 0;
    flex-shrink: 0; /* Prevent collapse when empty */
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
    border: 1px solid var(--border);
    background: var(--surface);
    font-family: var(--font-display);
    font-size: 22px;
    font-weight: 700;
    border-radius: 11px;
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.05),
      0 2px 8px rgba(0, 0, 0, 0.3);
    color: var(--text);
    backdrop-filter: blur(8px);
    box-sizing: border-box;
    transition: transform 0.2s var(--ease-spring), border-color 0.2s, background 0.2s, box-shadow 0.2s;
  }
  .letter-box.locked {
    color: #06210f;
    background: var(--brand-grad);
    border-color: transparent;
    box-shadow: 0 4px 16px rgba(52, 211, 153, 0.35);
  }
  .letter-box.active {
    border: 2px solid var(--brand-2);
    box-shadow: 0 0 0 4px rgba(163, 230, 53, 0.16), 0 0 18px rgba(163, 230, 53, 0.25);
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
      width: 36px;
      min-width: 36px;
      height: 42px;
      min-height: 42px;
      font-size: 19px;
      border-radius: 9px;
    }
    .phrase-container {
      margin: 16px 0 10px 0;
    }
  }
</style>
