<script lang="ts">
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import {
    gameStore,
    selectLetter,
    inputGuessLetter,
    confirmPurchase,
    submitGuess,
    deleteGuessLetter,
    enterGuessMode
  } from '$lib/stores/GameStore.js';
  import { fx } from '$lib/sound.js';

  type LetterCosts = Record<string, number>;
  const letterCosts: LetterCosts = {
    Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
    A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
    Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
  };

  const row1: string[] = ['Q','W','E','R','T','Y','U','I','O','P'];
  const row2: string[] = ['A','S','D','F','G','H','J','K','L'];
  const row3: string[] = ['Z','X','C','V','B','N','M'];

  // Effective per-letter prices after active discount / vowel_vision (server matches this):
  // daily uses the shared modifier; arcade uses the run's armed power-ups.
  $: effCosts = (() => {
    let discount = false, vowelHalf = false;
    if ($gameStore.gameMode === 'daily') {
      const m = $gameStore.modifier;
      discount = m === 'discount'; vowelHalf = m === 'vowel_vision';
    } else if ($gameStore.gameMode === 'arcade') {
      const a: string[] = ($gameStore.arcadeRun && $gameStore.arcadeRun.active) || [];
      discount = a.includes('discount'); vowelHalf = a.includes('vowel_vision');
    }
    const out: Record<string, number> = {};
    for (const k of Object.keys(letterCosts)) {
      let c = letterCosts[k];
      if (discount) c = Math.ceil(c * 0.75);
      if (vowelHalf && 'AEIOU'.includes(k)) c = Math.ceil(c * 0.5);
      out[k] = c;
    }
    return out;
  })();

  type SelectedPurchase = { type: string; value?: string } | null;
  type LockedLetters = Record<string, unknown>;
  let selectedPurchase: SelectedPurchase = null;
  let lockedLetters: LockedLetters = {};
  let incorrectLetters: string[] = [];
  $: selectedPurchase = $gameStore.selectedPurchase as SelectedPurchase;
  $: lockedLetters = ($gameStore.lockedLetters || {}) as LockedLetters;
  $: incorrectLetters = ($gameStore.incorrectLetters || []) as string[];

  // 🔹 Disable unaffordable or incorrect keys (uses modifier-adjusted prices)
  $: disabledKeys = Object.keys(letterCosts).filter((letter: string) =>
    (effCosts[letter] ?? 0) > $gameStore.bankroll ||
    incorrectLetters.includes(letter)
  );

  /**
   * 🔹 Letter click logic for both guess mode and purchase mode.
   */
  function handleLetterClick(letter: string): void {
    fx('select');
    if ($gameStore.gameState === 'guess_mode') {
      inputGuessLetter(letter);
    } else {
      selectLetter(letter);
    }
  }

  /**
   * 🔹 Global key handling: letters, Enter (submit), ESC (cancel), Backspace, Space.
   */
  function handleKeyDown(event: KeyboardEvent): void {
    const state = get(gameStore);
    const gameOver = state.gameState === 'won' || state.gameState === 'lost';
    const key = event.key.toUpperCase();

    // ESC – Cancel: exit guess mode, clear purchase, hide wager
    if (event.key === 'Escape') {
      event.preventDefault();
      if (state.gameState === 'guess_mode') {
        enterGuessMode();
      } else if (state.selectedPurchase) {
        gameStore.update(s => ({ ...s, selectedPurchase: null, gameState: 'default' }));
      }
      const active = document.activeElement;
      if (active && active instanceof HTMLElement) active.blur();
      return;
    }

    if (gameOver) return; // Don't handle letters/Enter when game is over

    // Enter – Submit guess, confirm purchase, or enter guess mode
    if (event.key === 'Enter') {
      event.preventDefault();
      if (state.selectedPurchase) {
        confirmPurchase();
      } else if (state.gameState === 'guess_mode') {
        submitGuess();
      } else if (!state.selectedPurchase && state.gameState !== 'guess_mode') {
        gameStore.update(s => ({ ...s, gameState: 'guess_mode', selectedPurchase: null, guessedLetters: {} }));
      }
      const active = document.activeElement;
      if (active && active instanceof HTMLElement) active.blur();
      return;
    }

    // Backspace / Delete – Remove last guess letter
    if (event.key === 'Backspace' || event.key === 'Delete') {
      if (state.gameState === 'guess_mode') {
        event.preventDefault();
        deleteGuessLetter();
      }
      return;
    }

    // Space – Toggle guess mode
    if (event.key === ' ' || event.code === 'Space') {
      event.preventDefault();
      enterGuessMode();
      const active = document.activeElement;
      if (active && active instanceof HTMLElement) active.blur();
      return;
    }

    // A–Z – Select letter (purchase or guess)
    if (/^[A-Z]$/.test(key)) {
      event.preventDefault();
      fx('select');
      if (state.gameState === 'guess_mode') {
        inputGuessLetter(key);
      } else {
        selectLetter(key);
      }
      const active = document.activeElement;
      if (active && active instanceof HTMLElement) active.blur();
    }
  }

  onMount(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  });
</script>

<!-- Keyboard layout rendering -->
<div class="keyboard-container">
  <!-- Row 1: Q - P -->
  <div class="keyboard-row">
    {#each row1 as letter}
      <button
      tabindex="-1"
      class="key 
      {disabledKeys.includes(letter) && $gameStore.gameState !== 'guess_mode' ? 'disabled' : ''} 
      {(selectedPurchase?.type === 'letter' && 
        selectedPurchase.value === letter && 
        $gameStore.gameState === 'purchase_pending') ? 'pending' : ''}
      {lockedLetters[letter] ? 'purchased' : ''}
      {incorrectLetters.includes(letter) ? 'incorrect' : ''}"
        on:click={() => handleLetterClick(letter)}
      >
        <div class="letter">{letter}</div>
        <div class="price">${effCosts[letter] ?? 0}</div>
      </button>
    {/each}
  </div>

  <!-- Row 2: A - L -->
  <div class="keyboard-row">
    {#each row2 as letter}
      <button
      tabindex="-1"
        class="key {disabledKeys.includes(letter) && $gameStore.gameState !== 'guess_mode' ? 'disabled' : ''} 
                { selectedPurchase?.type === 'letter' &&
                  selectedPurchase.value === letter &&
                  $gameStore.gameState === 'purchase_pending'
                    ? 'pending'
                    : lockedLetters[letter]
                      ? 'purchased'
                      : incorrectLetters.includes(letter)
                        ? 'incorrect'
                        : ''
                }"
        on:click={() => handleLetterClick(letter)}
      >
        <div class="letter">{letter}</div>
        <div class="price">${effCosts[letter] ?? 0}</div>
      </button>
    {/each}
  </div>

  <!-- Row 3: Z - M (Plus Delete Button in Guess Mode) -->
  <div class="keyboard-row">
    {#each row3 as letter}
      <button
      tabindex="-1"
        class="key {disabledKeys.includes(letter) && $gameStore.gameState !== 'guess_mode' ? 'disabled' : ''} 
                { selectedPurchase?.type === 'letter' &&
                  selectedPurchase.value === letter &&
                  $gameStore.gameState === 'purchase_pending'
                    ? 'pending'
                    : lockedLetters[letter]
                      ? 'purchased'
                      : incorrectLetters.includes(letter)
                        ? 'incorrect'
                        : ''
                }"
        on:click={() => handleLetterClick(letter)}
      >
        <div class="letter">{letter}</div>
        <div class="price">${effCosts[letter] ?? 0}</div>
      </button>
    {/each}

    {#if $gameStore.gameState === 'guess_mode'}
      <button 
      tabindex="-1"
      class="key delete" on:click={deleteGuessLetter}>
        <div class="letter">Del</div>
      </button>
    {/if}
  </div>
</div>

<style>
  /* ---------------------------
     Keyboard Container & Layout
  --------------------------- */
  .keyboard-container {
    position: fixed;
    bottom: 0;
    left: 50%;
    transform: translateX(-50%);
    width: 100%;
    max-width: 600px;
    box-shadow: none !important; /* ❌ Removes any shadow */
    background: transparent !important; /* ❌ Ensures no background issue */
    padding: 6px;
    display: flex;
    flex-direction: column;
    gap: 3px;
    z-index: 1000;
  }
  .keyboard-row {
    display: flex;
    justify-content: center;
    gap: 2px;
    flex-wrap: nowrap;
  }
  :global(body) {
    padding-bottom: 132px; /* Space for keyboard */
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  /* ---------------------------
     Key Styles
  --------------------------- */
  .key {
    width: 56px;
    height: 46px;
    border: 1px solid var(--border);
    background: var(--surface);
    color: var(--text);
    border-radius: 10px;
    cursor: pointer;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 1px;
    padding: 2px;
    box-sizing: border-box;
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    transition: transform 0.12s var(--ease-spring), background 0.15s, border-color 0.15s;
  }
  .key:hover:not(.purchased):not(.incorrect):not(.disabled) {
    background: var(--surface-2);
    border-color: var(--border-strong);
    transform: translateY(-1px);
  }
  .key:active { transform: scale(0.94); }

  .key.delete {
    background: rgba(251, 90, 90, 0.15);
    color: #ffb4b4 !important;
    border-color: rgba(251, 90, 90, 0.4) !important;
  }
  @keyframes blink {
  0% { opacity: 1; }
  50% { opacity: 0; }
  100% { opacity: 1; }
}

  /* ---------------------------
     Letter & Price Styling
  --------------------------- */
  .letter {
    line-height: 1;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 15px;
  }
  .price {
    line-height: 1;
    font-size: 9px;
    color: var(--text-faint);
    font-variant-numeric: tabular-nums;
  }

  /* ---------------------------
     Key State Styles
  --------------------------- */
  .purchased {
    background: linear-gradient(135deg, rgba(52, 211, 153, 0.30), rgba(163, 230, 53, 0.18)) !important;
    color: var(--brand-2) !important;
    border-color: rgba(163, 230, 53, 0.4) !important;
    cursor: default;
    pointer-events: none;
  }
  .purchased .price { color: rgba(163, 230, 53, 0.65); }
  .pending {
    background: var(--brand-grad) !important;
    color: #06210f !important;
    border-color: transparent !important;
    box-shadow: var(--glow-brand);
    animation: keyPulse 1s infinite;
  }
  .pending .price { color: rgba(6, 33, 15, 0.7); }
  @keyframes keyPulse { 0%, 100% { filter: brightness(1); } 50% { filter: brightness(1.12); } }
  .incorrect {
    background: rgba(255, 255, 255, 0.02) !important;
    color: var(--text-faint) !important;
    border-color: var(--border) !important;
    cursor: default;
    opacity: 0.5;
    pointer-events: none;
  }

  /* Blinking animation for pending keys */
  @keyframes blink {
    0% { opacity: 1; }
    50% { opacity: 0.5; }
    100% { opacity: 1; }
  }

  /* Unaffordable letters: dim, not blurred */
  .key.disabled {
    opacity: 0.4;
    pointer-events: none;
    transition: opacity 0.3s ease;
  }

  /* In guess mode, all letters are tappable */
  :global(body.guess-mode) .key.incorrect,
  :global(body.guess-mode) .key.disabled {
    opacity: 1 !important;
    pointer-events: all;
  }
</style>
