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
  // Mirror of server public.letter_cost() (economy v3.2: −25%, cheapest $20).
  const letterCosts: LetterCosts = {
    Q: 20, W: 40, E: 100, R: 90, T: 90, Y: 50, U: 60, I: 80, O: 70, P: 60,
    A: 100, S: 90, D: 60, F: 50, G: 50, H: 50, J: 20, K: 40, L: 60,
    Z: 30, X: 30, C: 60, V: 40, B: 50, N: 80, M: 50
  };

  const row1: string[] = ['Q','W','E','R','T','Y','U','I','O','P'];
  const row2: string[] = ['A','S','D','F','G','H','J','K','L'];
  const row3: string[] = ['Z','X','C','V','B','N','M'];

  // Braille (Unicode patterns) for each letter — the tactile dots on ATM-style keys.
  const BRAILLE: Record<string, string> = {
    A:'⠁',B:'⠃',C:'⠉',D:'⠙',E:'⠑',F:'⠋',G:'⠛',H:'⠓',I:'⠊',J:'⠚',K:'⠅',L:'⠇',M:'⠍',
    N:'⠝',O:'⠕',P:'⠏',Q:'⠟',R:'⠗',S:'⠎',T:'⠞',U:'⠥',V:'⠧',W:'⠺',X:'⠭',Y:'⠽',Z:'⠵'
  };

  // Effective per-letter prices after active discount / vowel_vision (server matches this):
  // daily uses the shared modifier.
  // Free Play: letters are free (the cost is your limited reveal budget).
  $: isFreeplay = $gameStore.gameMode === 'freeplay';
  $: effCosts = (() => {
    if ($gameStore.gameMode === 'freeplay') { const out: Record<string, number> = {}; for (const k of Object.keys(letterCosts)) out[k] = 0; return out; }
    let discount = false, vowelHalf = false;
    if ($gameStore.gameMode === 'daily') {
      const m = $gameStore.modifier;
      discount = m === 'discount'; vowelHalf = m === 'vowel_vision';
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

  // 🔹 Disable keys. Free Play: all disabled when out of reveals, else only wrong letters.
  //    Other modes: unaffordable or incorrect keys (modifier-adjusted prices).
  $: disabledKeys = isFreeplay
    ? ((($gameStore as any).revealsRemaining ?? 0) <= 0
        ? Object.keys(letterCosts)
        : Object.keys(letterCosts).filter((letter: string) => incorrectLetters.includes(letter)))
    : Object.keys(letterCosts).filter((letter: string) =>
        (effCosts[letter] ?? 0) > $gameStore.bankroll || incorrectLetters.includes(letter));

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
    // Don't hijack typing in a text field (chat, username, search, wager…).
    // Without this the game eats every keystroke — preventDefault stops the
    // character and blur() closes the field, so e.g. chat won't accept input.
    const el = document.activeElement as HTMLElement | null;
    if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable)) return;

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
        <span class="braille">{BRAILLE[letter]}</span>
        <div class="letter">{letter}</div>
        {#if !isFreeplay}<div class="price">${effCosts[letter] ?? 0}</div>{/if}
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
        <span class="braille">{BRAILLE[letter]}</span>
        <div class="letter">{letter}</div>
        {#if !isFreeplay}<div class="price">${effCosts[letter] ?? 0}</div>{/if}
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
        <span class="braille">{BRAILLE[letter]}</span>
        <div class="letter">{letter}</div>
        {#if !isFreeplay}<div class="price">${effCosts[letter] ?? 0}</div>{/if}
      </button>
    {/each}

    {#if $gameStore.gameState === 'guess_mode'}
      <button
      tabindex="-1"
      class="key delete" on:click={deleteGuessLetter}>
        <div class="letter">⌫</div>
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
    bottom: calc(env(safe-area-inset-bottom, 0px) + 9px); /* lifted off the bottom edge */
    left: 50%;
    transform: translateX(-50%);
    width: 100%;
    max-width: 600px;
    box-shadow: none !important;
    background: transparent !important;
    padding: 6px 8px; /* side padding so edge keys never clip */
    display: flex;
    flex-direction: column;
    gap: 5px;
    z-index: 1000;
  }
  .keyboard-row {
    display: flex;
    justify-content: center;
    gap: 5px;
    flex-wrap: nowrap;
  }
  :global(body) {
    padding-bottom: 176px; /* Space for the lifted keyboard */
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  /* ---------------------------
     Key Styles — silver ATM keys
  --------------------------- */
  .key {
    flex: 1 1 0;
    min-width: 0;
    height: 47px;
    border: 1px solid rgba(251, 191, 36, 0.32);
    background: linear-gradient(160deg, #1c1f28, #0c0e13);
    color: #f4e7c6;
    border-radius: 8px;
    cursor: pointer;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 1px;
    padding: 2px;
    position: relative;
    box-sizing: border-box;
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.06),
      inset 0 0 10px rgba(251, 191, 36, 0.06),
      0 2px 0 rgba(0, 0, 0, 0.6),
      0 4px 8px rgba(0, 0, 0, 0.5);
    transition: transform 0.1s var(--ease-spring), box-shadow 0.12s, border-color 0.15s;
  }
  .key:hover:not(.purchased):not(.incorrect):not(.disabled) {
    border-color: rgba(251, 191, 36, 0.6);
    box-shadow: inset 0 0 14px rgba(251, 191, 36, 0.12), 0 2px 0 rgba(0,0,0,0.6), 0 4px 10px rgba(0,0,0,0.5);
    transform: translateY(-1px);
  }
  .key:active,
  .key:focus-visible {
    transform: translateY(1px) scale(0.97);
    border-color: #fde047 !important;
    outline: none;
    box-shadow:
      0 0 0 2px rgba(253, 224, 71, 1),
      0 0 16px rgba(251, 191, 36, 0.95),
      0 0 34px rgba(251, 191, 36, 0.65) !important;
  }

  /* braille pips, top-left of each key */
  .braille {
    position: absolute;
    top: 3px;
    left: 5px;
    font-size: 8px;
    line-height: 1;
    color: rgba(251, 191, 36, 0.4);
  }

  /* Delete: gold-accent futuristic key (guess mode), wider so it can't be missed */
  .key.delete {
    flex: 1.5 1 0;
    background: linear-gradient(160deg, #2c2410, #16110a) !important;
    color: #fde047 !important;
    border-color: rgba(251, 191, 36, 0.6) !important;
    box-shadow:
      inset 0 0 12px rgba(251, 191, 36, 0.18),
      0 2px 0 rgba(0, 0, 0, 0.6),
      0 4px 8px rgba(0, 0, 0, 0.5) !important;
  }
  .key.delete .letter { font-size: 19px; color: #fde047; }
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
    font-family: 'Orbitron', var(--font-display);
    font-weight: 700;
    font-size: 15px;
    letter-spacing: 0.02em;
    color: inherit; /* so purchased/incorrect state colors on .key apply */
  }
  .price {
    line-height: 1;
    font-size: 8.5px;
    color: rgba(251, 191, 36, 0.55);
    font-variant-numeric: tabular-nums;
  }

  /* ---------------------------
     Key State Styles
  --------------------------- */
  .purchased {
    background: linear-gradient(135deg, rgba(251, 191, 36, 0.30), rgba(253, 224, 71, 0.18)) !important;
    color: var(--brand-2) !important;
    border-color: rgba(253, 224, 71, 0.4) !important;
    cursor: default;
    pointer-events: none;
  }
  .purchased .price { color: rgba(253, 224, 71, 0.65); }
  .pending {
    background: var(--brand-grad) !important;
    color: #3a2a00 !important;
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
