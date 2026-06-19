<script>
  import { createEventDispatcher, onMount } from 'svelte';
  import { gameStore, confirmPurchase, submitGuess } from '$lib/stores/GameStore.js';

  /** @type {boolean} */
  export let wagerUIVisible = false;
  /** @type {number} */
  export let sliderWagerAmount = 0;

  const dispatch = createEventDispatcher();

  onMount(() => {
    window.addEventListener('hideWagerSlider', () => {
      dispatch('setWagerUIVisible', false);
      dispatch('setSliderWagerAmount', 0);
    });
  });

  // 🧠 Reactive state
  $: bankroll = $gameStore.bankroll;
  $: guessModeActive = $gameStore.gameState === 'guess_mode';
  $: isDailyMode = $gameStore.gameMode === 'daily';
  $: purchasePending = !!$gameStore.selectedPurchase;
  $: hintPending = $gameStore.selectedPurchase?.type === 'hint' && $gameStore.gameState === 'purchase_pending';
  $: showHintCost = hintPending;
  $: guessesRemaining = $gameStore.guessesRemaining ?? 3;
  $: fundsLow = bankroll < 150;
  $: noGuessesLeft = guessesRemaining <= 0;
  $: canConfirmWager = sliderWagerAmount > 0;
  $: gameOver = $gameStore.gameState === 'won' || $gameStore.gameState === 'lost';
  $: buttonsDisabled = gameOver;

  // ✅ Detect full phrase input
  $: guessComplete = guessModeActive && (() => {
    const phrase = $gameStore.currentPhrase;
    for (let i = 0; i < phrase.length; i++) {
      if (phrase[i] === ' ') continue;
      if ($gameStore.purchasedLetters[i] === phrase[i]) continue;
      if (!$gameStore.guessedLetters[i]) return false;
    }
    return true;
  })();

  // 🔁 Button display modes (daily: no wager, go straight to guess)
  $: dualButtonMode = purchasePending
    || (!isDailyMode && wagerUIVisible && sliderWagerAmount > 0 && !guessModeActive)
    || (guessModeActive && guessComplete);

  $: guessCancelOnlyMode = guessModeActive && !guessComplete;

  // 🏷️ Main button label
  $: buttonLabel = purchasePending
    ? 'Confirm'
    : guessModeActive
      ? (guessComplete ? 'Submit' : 'Cancel')
      : (isDailyMode ? 'Solve' : (!canConfirmWager && wagerUIVisible ? 'Cancel' : 'Solve'));

  // 🎨 Button classes
  $: buttonClass = [
    'guess-phrase-button',
    guessModeActive && !guessComplete ? 'exit-mode' : '',
    guessComplete ? 'guess-complete' : '',
    !canConfirmWager && wagerUIVisible ? 'exit-mode' : ''
  ].join(' ');

  // 🎯 Main button logic
  function handleMainButtonClick() {
    if (purchasePending) {
      confirmPurchase();
      return;
    }

    if (guessModeActive && guessComplete) {
      submitGuess();
      dispatch('setWagerUIVisible', false);
      dispatch('setSliderWagerAmount', 0);
      return;
    }

    if (isDailyMode) {
      if (noGuessesLeft) {
        gameStore.update(s => ({ ...s, message: 'Out of guesses — buy letters to finish the phrase' }));
        return;
      }
      gameStore.update(state => ({
        ...state,
        gameState: 'guess_mode',
        wagerAmount: 1,
        selectedPurchase: null,
        guessedLetters: {}
      }));
      return;
    }

    if (!wagerUIVisible) {
      dispatch('setWagerUIVisible', true);
      dispatch('setSliderWagerAmount', 0);
      return;
    }

    if (!canConfirmWager) {
      dispatch('setWagerUIVisible', false);
      dispatch('setSliderWagerAmount', 0);
      return;
    }

    if (noGuessesLeft) {
      gameStore.update(s => ({ ...s, message: 'Out of guesses — buy letters to finish the phrase' }));
      return;
    }

    gameStore.update(state => ({
      ...state,
      gameState: 'guess_mode',
      wagerAmount: sliderWagerAmount,
      selectedPurchase: null,
      guessedLetters: {}
    }));
  }

  function toggleHintPurchase() {
    dispatch('setWagerUIVisible', false);
    dispatch('setSliderWagerAmount', 0);

    gameStore.update(state => {
      if (state.selectedPurchase?.type === 'hint') {
        return { ...state, selectedPurchase: null, gameState: 'default' };
      }
      return { ...state, selectedPurchase: { type: 'hint' }, gameState: 'purchase_pending' };
    });
  }

</script>

{#if $gameStore.message}
  <div class="message-box">{$gameStore.message}</div>
{/if}

<div class="main-button-wrapper">
  <div class="hint-button-container">
    {#if showHintCost}
      <div class="cost-indicator">
        $150
      </div>
    {/if}
    <button
      class="hint-button {fundsLow ? 'disabled-purchase' : ''} {hintPending ? 'glow' : ''}"
      on:click={toggleHintPurchase}
      disabled={fundsLow || buttonsDisabled}
      title="Reveal the most useful letter ($150)"
    >
      Reveal
    </button>
  </div>

  {#if dualButtonMode}
    <div class="dual-button-container">
      <button
        class="cancel-button"
        on:click={() => {
          dispatch('setWagerUIVisible', false);
          dispatch('setSliderWagerAmount', 0);
          gameStore.update(state => ({
            ...state,
            guessedLetters: {},
            selectedPurchase: null,
            gameState: 'default'
          }));
        }}
        disabled={buttonsDisabled}
      >
        Cancel
      </button>

      <button
        class="confirm-button"
        on:click={handleMainButtonClick}
        disabled={buttonsDisabled}
      >
        {purchasePending ? 'Confirm' : 'Submit'}
      </button>
    </div>

  {:else if guessCancelOnlyMode}
    <div class="solve-button-container">
      <button
        class="guess-phrase-button exit-mode"
        on:click={() => {
          dispatch('setWagerUIVisible', false);
          dispatch('setSliderWagerAmount', 0);
          gameStore.update(state => ({
            ...state,
            guessedLetters: {},
            gameState: 'default'
          }));
        }}
        disabled={buttonsDisabled}
      >
        Cancel
      </button>
    </div>

  {:else}
    <div class="solve-button-container">
      <button
        class={buttonClass}
        on:click={handleMainButtonClick}
        disabled={buttonsDisabled}
      >
        {buttonLabel}
      </button>
    </div>
  {/if}

  <div class="guesses-button-container">
    <div class="guesses-display" title="Solve attempts remaining">
      Tries<br /><span class="guesses-count">{guessesRemaining}</span>
    </div>
  </div>
</div>
<style>
@import url('https://fonts.googleapis.com/css2?family=VT323&display=swap');

/* ---------------------------
   Animations
--------------------------- */
@keyframes softGlow {
  0% { box-shadow: 0 0 8px #fff, 0 0 16px #318020, 0 0 24px #207b09; }
  50% { box-shadow: 0 0 12px #fff, 0 0 20px #46a230, 0 0 28px #14860a; }
  100% { box-shadow: 0 0 8px #fff, 0 0 16px #46a230, 0 0 24px #46a230; }
}
@keyframes blinkColor {
  0%, 100% { color: red; opacity: 1; }
  50% { color: white; opacity: 0.5; }
}
@keyframes blinkDarkGreen {
  0%, 100% { background-color: #2e7d32; }
  50% { background-color: #1b5e20; }
}
@keyframes blinkGreen {
  0%, 100% { background-color: green; }
  50% { background-color: #00cc00; }
}
@keyframes pulseGlow {
  0%, 100% { transform: scale(1); box-shadow: 0 0 8px rgba(0, 255, 0, 0.5); }
  50% { transform: scale(1.05); box-shadow: 0 0 16px rgba(0, 255, 0, 0.9); }
}

/* ---------------------------
   Utility
--------------------------- */
.disabled-purchase {
  opacity: 0.5;
  filter: blur(1px);
  pointer-events: none;
}
.cost-indicator {
  position: absolute;
  top: -30px;
  left: 50%;
  transform: translateX(-50%);
  font-family: var(--font-display);
  font-weight: 700;
  font-size: 13px;
  color: #fcd34d;
  background: rgba(251, 191, 36, 0.12);
  border: 1px solid rgba(251, 191, 36, 0.35);
  padding: 3px 9px;
  border-radius: 999px;
  white-space: nowrap;
}

.message-box {
  position: fixed;
  bottom: 232px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 1002;
  font-family: var(--font-ui);
  font-weight: 600;
  font-size: 0.85rem;
  color: var(--text);
  background: var(--surface-strong);
  border: 1px solid var(--border-strong);
  padding: 9px 16px;
  border-radius: 999px;
  box-shadow: var(--shadow-md);
  backdrop-filter: blur(12px);
  white-space: nowrap;
}

/* ---------------------------
   Button Wrapper Layout
--------------------------- */
.main-button-wrapper {
  position: fixed;
  bottom: 174px; /* clears the 156px-tall keyboard + gap */
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: 12px;
  z-index: 999;
}

/* ---------------------------
   Hint Button
--------------------------- */
.hint-button-container {
  position: relative;
}
.hint-button {
  width: 54px;
  height: 46px;
  border-radius: 13px;
  background: var(--surface);
  border: 1px solid var(--border);
  color: var(--text);
  font-family: var(--font-ui);
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.02em;
  line-height: 1.15;
  display: flex;
  align-items: center;
  justify-content: center;
  backdrop-filter: blur(10px);
  transition: transform 0.16s var(--ease-spring), background 0.2s, border-color 0.2s;
  cursor: pointer;
}
.hint-button:hover { transform: translateY(-2px); background: var(--surface-2); border-color: var(--border-strong); }
.hint-button:active { transform: scale(0.96); }
.hint-button.glow { border-color: rgba(163, 230, 53, 0.5) !important; box-shadow: var(--glow-brand); }

/* ---------------------------
   Guesses Button (blue, right of Solve)
--------------------------- */
.guesses-button-container {
  position: relative;
}
.guesses-button {
  width: 54px;
  height: 46px;
  border-radius: 13px;
  background: var(--surface);
  color: var(--text);
  font-family: var(--font-ui);
  font-size: 8px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  border: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  line-height: 1.1;
  backdrop-filter: blur(10px);
  transition: transform 0.16s var(--ease-spring), background 0.2s, border-color 0.2s;
  cursor: pointer;
}
.guesses-display {
  width: 54px;
  height: 46px;
  border-radius: 13px;
  background: var(--surface);
  color: var(--text-muted);
  font-family: var(--font-ui);
  font-size: 8px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  border: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  line-height: 1.1;
  backdrop-filter: blur(10px);
}
.guesses-count {
  font-family: var(--font-display);
  font-size: 18px;
  font-weight: 700;
  color: var(--brand-2);
  display: block;
}
.guesses-button:hover { transform: translateY(-2px); background: var(--surface-2); border-color: var(--border-strong); }
.guesses-button:active { transform: scale(0.96); }
.guesses-button.glow {
  box-shadow: var(--glow-brand);
  border-color: rgba(163, 230, 53, 0.5);
}

/* ---------------------------
   Solve / Submit / Cancel Button
--------------------------- */
.solve-button-container,
.dual-button-container {
  width: 200px;
  height: 46px;
  display: flex;
  justify-content: center;
  align-items: center;
}

/* Solve Button */
.guess-phrase-button {
  width: 100%;
  height: 100%;
  font-family: var(--font-display);
  font-size: 18px;
  font-weight: 700;
  letter-spacing: 0.02em;
  text-transform: uppercase;
  background: var(--brand-grad);
  color: #06210f;
  border-radius: 14px;
  border: none;
  box-shadow: var(--glow-brand);
  transition: transform 0.16s var(--ease-spring), filter 0.2s, box-shadow 0.2s;
}

.guess-phrase-button:hover {
  transform: translateY(-2px);
  filter: brightness(1.05);
}

.guess-phrase-button:active {
  transform: scale(0.97);
}

.guess-phrase-button.pending,
.guess-phrase-button.guess-complete {
  animation: solvePulse 1.1s infinite;
}
@keyframes solvePulse {
  0%, 100% { box-shadow: var(--glow-brand); }
  50% { box-shadow: 0 0 0 1px rgba(163, 230, 53, 0.4), 0 8px 36px rgba(52, 211, 153, 0.5); }
}

.guess-phrase-button.exit-mode {
  background: linear-gradient(135deg, #fb5a5a, #c81e1e);
  color: #fff;
  border: none;
  box-shadow: 0 8px 24px rgba(200, 30, 30, 0.35);
}

.guess-phrase-button.exit-mode:active {
  transform: scale(0.96);
}

/* Dark mode adjustments */
:global(body.dark-mode) .guess-phrase-button {
  background: linear-gradient(180deg, #46a230, #318020); /* Keep it green in dark mode */
}

/* ---------------------------
   Confirm / Cancel Buttons
--------------------------- */
.dual-button-container {
  gap: 10px;
}
.confirm-button,
.cancel-button {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: 16px;
  flex: 1;
  height: 46px;
  border-radius: 14px;
  cursor: pointer;
  transition: transform 0.16s var(--ease-spring), filter 0.2s;
}

/* Confirm */
.confirm-button {
  background: var(--brand-grad);
  color: #06210f;
  border: none;
  box-shadow: var(--glow-brand);
  animation: solvePulse 1.1s infinite;
}
.confirm-button:hover {
  filter: brightness(1.05);
  transform: translateY(-2px);
}
.confirm-button:active { transform: scale(0.97); }

/* Cancel */
.cancel-button {
  background: var(--surface-2);
  color: var(--text);
  border: 1px solid var(--border-strong);
}
.cancel-button:hover { transform: translateY(-1px); background: rgba(251, 90, 90, 0.16); border-color: rgba(251, 90, 90, 0.4); }
.cancel-button:active { transform: scale(0.97); }
.guess-phrase-button:disabled,
.confirm-button:disabled,
.cancel-button:disabled {
  opacity: 0.4;
  filter: grayscale(100%);
  cursor: not-allowed;
  box-shadow: none;
  background: #888 !important; /* Optional: solid gray background */
  color: #eee;
  border: 2px solid #666;
}

</style>
