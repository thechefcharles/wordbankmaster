<script>
  import { createEventDispatcher, onMount } from 'svelte';
  import { gameStore, confirmPurchase, submitGuess } from '$lib/stores/GameStore.js';

  export let wagerUIVisible;
  export let sliderWagerAmount;

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
  $: purchasePending = !!$gameStore.selectedPurchase;
  $: hintPending = $gameStore.selectedPurchase?.type === 'hint' && $gameStore.gameState === 'purchase_pending';
  $: showHintCost = hintPending;
  $: fundsLow = bankroll < 150;
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

  // 🔁 Button display modes
  $: dualButtonMode = purchasePending
    || (wagerUIVisible && sliderWagerAmount > 0 && !guessModeActive)
    || (guessModeActive && guessComplete);

  $: guessCancelOnlyMode = guessModeActive && !guessComplete;

  // 🏷️ Main button label
  $: buttonLabel = purchasePending
    ? 'Confirm'
    : guessModeActive
      ? (guessComplete ? 'Submit' : 'Cancel')
      : (!canConfirmWager && wagerUIVisible ? 'Cancel' : 'Solve');

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
    >
      Bank Letter
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
  top: -25px;
  font-size: 20px;
  font-family: 'VT323', sans-serif;
  color: red;
  animation: blinkColor 1s infinite;
}

/* ---------------------------
   Button Wrapper Layout
--------------------------- */
.main-button-wrapper {
  position: fixed;
  bottom: 180px;
  left: 50%;
  transform: translateX(calc(-50% - 33px)); /* 25px for hint + 8px margin */
    display: flex;
  align-items: center;
  gap: 16px;
  z-index: 999;
}

/* ---------------------------
   Hint Button
--------------------------- */
.hint-button-container {
  position: relative;
}
.hint-button {
  width: 50px;
  height: 50px;
  border-radius: 50%;
  background: radial-gradient(circle at 30% 30%, #4488ff, #0055bb 80%);
  color: #fff;
  font-family: 'VT323', sans-serif;
  font-size: 10px;
  font-weight: bold;
  text-transform: uppercase;
  border: none;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: transform 0.2s ease;
  cursor: pointer;
}
.hint-button:hover { transform: translateY(-2px); }
.hint-button:active { transform: translateY(2px); }
.hint-button.glow { animation: softGlow 0.3s infinite alternate ease-in-out; border: 3px outset #0d3e01 !important; }

/* ---------------------------
   Solve / Submit / Cancel Button
--------------------------- */
.solve-button-container,
.dual-button-container {
  width: 230px;
  height: 40px;
  display: flex;
  justify-content: center;
  align-items: center;
}

/* Solve Button */
.guess-phrase-button {
  width: 100%;
  height: 100%;
  font-family: 'VT323', sans-serif;
  font-size: 25px;
  font-weight: bold;
  text-transform: uppercase;
  background: linear-gradient(180deg, #46a230, #318020); /* Always green */
  color: white;
  border-radius: 8px;
  border: 3px solid #2e9417; /* Green border */
  box-shadow: inset 2px 2px 5px rgba(255,255,255,0.3), 3px 3px 8px rgba(0,0,0,0.6);
  transition: background-color 0.3s, transform 0.2s;
}

.guess-phrase-button:hover {
  transform: translateY(-2px);
  background: linear-gradient(180deg, #46a230, #318020); /* Keep it green on hover */
}

.guess-phrase-button:active {
  transform: translateY(2px);
  background: linear-gradient(180deg, #46a230, #318020); /* Keep it green when active */
}

.guess-phrase-button.pending {
  animation: blinkDarkGreen 1s infinite;
}

.guess-phrase-button.guess-complete {
  animation: blinkGreen 1s infinite;
}

.guess-phrase-button.exit-mode {
  background: linear-gradient(180deg, #ff2222, #aa0000); /* Red for exit mode */
  border: 3px solid darkred;
}

.guess-phrase-button.exit-mode:active {
  background: linear-gradient(180deg, #cc0000, #990000);
  transform: scale(0.95);
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
  font-family: 'VT323', monospace;
  font-size: 22px;
  flex: 1;
  height: 40px;
  border-radius: 8px;
  transition: transform 0.2s ease;
  cursor: pointer;
}

/* Confirm */
.confirm-button {
  background: linear-gradient(180deg, #28a745, #218838);
  color: white;
  border: 3px solid #1e7e34;
  animation: pulseGlow 1s infinite;
}
.confirm-button:hover {
  background: linear-gradient(180deg, #45c362, #2f9f4a);
  transform: translateY(-2px);
}

/* Cancel */
.cancel-button {
  background: linear-gradient(180deg, #aa0000, #660000);
  color: white;
  border: 2px solid darkred;
}
.cancel-button:hover {
  transform: scale(1.08);
}

/* ---------------------------
   Dark Mode
--------------------------- */
:global(body.dark-mode) .guess-phrase-button {
  background: linear-gradient(180deg, #46a230, #318020);
}
:global(body.dark-mode) .hint-button {
  background: radial-gradient(circle at 30% 30%, #66aaff, #3388ff 80%) !important;
  border: 3px solid #66aaff !important;
}
:global(body.dark-mode) .guess-phrase-button.exit-mode {
  background: linear-gradient(180deg, #ff2222, #aa0000) !important;
  border: 3px solid #880000 !important;
}
:global(body.dark-mode) .guess-phrase-button.guess-complete {
  background: linear-gradient(180deg, #28a745, #218838) !important;
  border: 3px solid #1e7e34 !important;
}
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
