<script>
  import { gameStore } from '$lib/stores/GameStore.js';
  import { onDestroy, createEventDispatcher } from 'svelte';
  import { getGlobalIndex } from '$lib/helpers/gameUtils.js';
  import { fx } from '$lib/sound.js';

  const dispatch = createEventDispatcher();

  // 🎰 Daily opening reveal: each empty space lands one-by-one (shake + money signs
  // + green plus + a landing thunk), then +page counts the bounty up in green. Driven
  // by gameStore.dailyIntro, which bumps once on a fresh daily open.
  const INTRO_STEP = 0.34; // seconds between box landings (slow, dramatic)
  let introActive = false;
  let introToken = 0;
  /** @type {ReturnType<typeof setTimeout>[]} */
  let introTimers = [];
  /** @param {number} gi */
  const introDelay = (gi) => Math.min(gi, 16) * INTRO_STEP;

  $: maybeStartIntro($gameStore.dailyIntroGo);
  /** @param {number|undefined} tok */
  function maybeStartIntro(tok) {
    if (!tok || tok === introToken) return;
    introToken = tok;
    runIntro();
  }
  function runIntro() {
    const phrase = $gameStore.currentPhrase || '';
    /** @type {number[]} */
    const idxs = [];
    for (let i = 0; i < phrase.length; i++) if (phrase[i] !== ' ') idxs.push(i);
    if (!idxs.length) return;
    introTimers.forEach(clearTimeout);
    introTimers = [];
    introActive = true;
    let lastDelay = 0;
    for (const gi of idxs) {
      const d = introDelay(gi);
      lastDelay = Math.max(lastDelay, d);
      introTimers.push(setTimeout(() => fx('land'), d * 1000 + 30));
    }
    // Climax: the spaces "add up × the multiplier" into the green bounty.
    introTimers.push(setTimeout(() => { fx('multiplier'); dispatch('introDone'); }, lastDelay * 1000 + 420));
    introTimers.push(setTimeout(() => { introActive = false; }, lastDelay * 1000 + 1900));
  }

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

  // 🎰 Win: dramatic box-by-box reveal (each tile pops with green money). Hold the
  // result modal until the slot-machine sequence finishes.
  let wonFired = false;
  $: if ($gameStore.gameState === 'won') {
    if (!wonFired) {
      wonFired = true;
      const n = ($gameStore.currentPhrase || '').replace(/ /g, '').length;
      setTimeout(() => dispatch('revealComplete'), Math.min(n, 14) * 95 + 750);
    }
  } else {
    wonFired = false;
  }

  onDestroy(() => { clearInterval(revealInterval); introTimers.forEach(clearTimeout); });

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
            {@const gi = getGlobalIndex(wIndex, cIndex, $gameStore.currentPhrase)}
            {@const won = $gameStore.gameState === 'won'}
            {@const intro = introActive && !won}
            <span class="letter-box {shakeIndexes.has(gi) ? 'shake' : ''} {won ? 'win' : ''} {intro ? 'intro' : ''}"
              style={won ? `animation-delay:${Math.min(gi, 14) * 0.095}s` : intro ? `animation-delay:${introDelay(gi)}s` : ''}>
              {$gameStore.purchasedLetters[gi] || ""}
              {#if won}
                <span class="coin c1" style="animation-delay:{Math.min(gi, 14) * 0.095}s">$</span>
                <span class="coin c2" style="animation-delay:{Math.min(gi, 14) * 0.095 + 0.07}s">$</span>
                <span class="coin c3" style="animation-delay:{Math.min(gi, 14) * 0.095 + 0.04}s">$</span>
                <span class="plus" style="animation-delay:{Math.min(gi, 14) * 0.095 + 0.13}s">+</span>
              {:else if intro}
                <span class="coin c1" style="animation-delay:{introDelay(gi) + 0.18}s">$</span>
                <span class="coin c2" style="animation-delay:{introDelay(gi) + 0.25}s">$</span>
                <span class="coin c3" style="animation-delay:{introDelay(gi) + 0.22}s">$</span>
                <span class="plus" style="animation-delay:{introDelay(gi) + 0.28}s">+</span>
              {/if}
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

  /* 🎰 Daily opening reveal: each empty space drops in, rattles, and lands hard */
  .letter-box.intro {
    animation: introPop 0.92s cubic-bezier(0.34, 1.56, 0.64, 1) backwards;
    z-index: 1;
  }
  @keyframes introPop {
    0%   { opacity: 0; transform: translateY(-40px) scale(0.3) rotate(-10deg); }
    24%  { opacity: 1; transform: translateY(6px) scale(1.24) rotate(6deg);
           border-color: #4ade80; box-shadow: 0 0 0 3px rgba(74,222,128,0.55), 0 0 24px rgba(74,222,128,0.65); }
    40%  { transform: translateY(0) scale(0.92) rotate(-4deg); }
    54%  { transform: translateY(0) scale(1.08) rotate(3deg); }
    68%  { transform: translateY(0) scale(0.97) rotate(-1.5deg);
           box-shadow: 0 0 0 2px rgba(74,222,128,0.4), 0 0 16px rgba(74,222,128,0.45); }
    100% { opacity: 1; transform: translateY(0) scale(1) rotate(0deg); }
  }

  /* 🎰 Win reveal: each tile pops with green money, staggered left→right */
  .letter-box.win {
    animation: winPop 0.55s cubic-bezier(0.34, 1.56, 0.64, 1) backwards;
    z-index: 1;
  }
  @keyframes winPop {
    0%   { transform: scale(1); }
    30%  { transform: scale(1.28) rotate(-5deg); border-color: #4ade80;
           box-shadow: 0 0 0 3px rgba(74,222,128,0.5), 0 0 22px rgba(74,222,128,0.6); color: #bbf7d0; }
    60%  { transform: scale(1.12) rotate(4deg); }
    100% { transform: scale(1); }
  }
  .coin, .plus { position: absolute; pointer-events: none; left: 50%; font-family: 'Orbitron', var(--font-display);
    font-weight: 800; color: #4ade80; text-shadow: 0 0 8px rgba(74,222,128,0.7); opacity: 0; }
  .coin { top: 6px; font-size: 0.9rem; animation: coinSpray 0.75s ease-out backwards; }
  .c1 { --dx: -22px; } .c2 { --dx: 20px; } .c3 { --dx: 2px; }
  @keyframes coinSpray {
    0%   { opacity: 0; transform: translate(-50%, 0) scale(0.4); }
    20%  { opacity: 1; transform: translate(-50%, -6px) scale(1.1); }
    100% { opacity: 0; transform: translate(calc(-50% + var(--dx, 0px)), 32px) scale(0.85); }
  }
  .plus { top: -8px; font-size: 1.4rem; animation: plusPop 0.55s ease-out backwards; }
  @keyframes plusPop {
    0%   { opacity: 0; transform: translate(-50%, 6px) scale(0.4); }
    40%  { opacity: 1; transform: translate(-50%, -12px) scale(1.25); }
    100% { opacity: 0; transform: translate(-50%, -24px) scale(1); }
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
    perspective: 800px;
  }
  .letter-box.active {
    animation: activePulse 1.4s ease-in-out infinite;
  }
  @keyframes activePulse {
    0%, 100% { box-shadow: 0 0 0 4px rgba(253, 224, 71,0.14), 0 0 14px rgba(253, 224, 71,0.2); }
    50%      { box-shadow: 0 0 0 5px rgba(253, 224, 71,0.26), 0 0 22px rgba(253, 224, 71,0.4); }
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
    position: relative;
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
    border: 1px solid rgba(74, 222, 128, 0.32);
    background: var(--surface);
    font-family: var(--font-display);
    font-size: 22px;
    font-weight: 700;
    border-radius: 11px;
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.05),
      0 2px 8px rgba(0, 0, 0, 0.3),
      0 0 9px rgba(74, 222, 128, 0.16);
    color: var(--text);
    backdrop-filter: blur(8px);
    box-sizing: border-box;
    transition: transform 0.2s var(--ease-spring), border-color 0.2s, background 0.2s, box-shadow 0.2s;
  }
  .letter-box.locked {
    color: #3a2a00;
    background: var(--brand-grad);
    border-color: transparent;
    box-shadow: 0 4px 16px rgba(251, 191, 36, 0.35);
    animation: tileReveal 0.55s var(--ease-spring) both;
  }
  @keyframes tileReveal {
    0%   { transform: perspective(600px) rotateX(-90deg); box-shadow: 0 0 0 rgba(251, 191, 36,0); }
    55%  { transform: perspective(600px) rotateX(0deg) scale(1.14); box-shadow: 0 0 26px rgba(253, 224, 71,0.7); }
    100% { transform: perspective(600px) rotateX(0deg) scale(1); }
  }
  .letter-box.active {
    border: 2px solid var(--brand-2);
    box-shadow: 0 0 0 4px rgba(253, 224, 71, 0.16), 0 0 18px rgba(253, 224, 71, 0.25);
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
