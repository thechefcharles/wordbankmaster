<script>
	import { gameStore, confirmPurchase, submitGuess } from '$lib/stores/GameStore.js';
	import { fx } from '$lib/sound.js';

	// 🧠 Reactive state (server-authoritative). v3: unlimited guesses, no Reveal button.
	$: guessModeActive = $gameStore.gameState === 'guess_mode';
	$: purchasePending = !!$gameStore.selectedPurchase;
	$: gameOver = $gameStore.gameState === 'won' || $gameStore.gameState === 'lost';
	$: buttonsDisabled = gameOver;

	// ✅ Detect full phrase input
	$: guessComplete =
		guessModeActive &&
		(() => {
			const phrase = $gameStore.currentPhrase;
			for (let i = 0; i < phrase.length; i++) {
				if (phrase[i] === ' ') continue;
				if ($gameStore.purchasedLetters[i] === phrase[i]) continue;
				if (!$gameStore.guessedLetters[i]) return false;
			}
			return true;
		})();

	// 🔁 Button display modes
	$: dualButtonMode = purchasePending || (guessModeActive && guessComplete);
	$: guessCancelOnlyMode = guessModeActive && !guessComplete;

	// 🏷️ Main button label
	$: buttonLabel = purchasePending
		? 'Confirm'
		: guessModeActive
			? guessComplete
				? 'Submit'
				: 'Cancel'
			: 'Solve';

	// 🎨 Button classes
	$: buttonClass = [
		'guess-phrase-button',
		guessModeActive && !guessComplete ? 'exit-mode' : '',
		guessComplete ? 'guess-complete' : ''
	].join(' ');

	// 🎯 Main button logic
	function handleMainButtonClick() {
		fx('tap');
		if (purchasePending) {
			confirmPurchase();
			return;
		}
		if (guessModeActive && guessComplete) {
			submitGuess();
			return;
		}
		// Enter guess mode — guesses are unlimited (v3).
		gameStore.update((state) => ({
			...state,
			gameState: 'guess_mode',
			selectedPurchase: null,
			guessedLetters: {}
		}));
	}
</script>

{#if $gameStore.message}
	<div class="message-box">{$gameStore.message}</div>
{/if}

<div class="main-button-wrapper">
	<!-- Optional left accessory (e.g. Cash Game vault). Absolutely positioned so Solve stays centered. -->
	<slot name="left" />
	{#if dualButtonMode}
		<div class="dual-button-container">
			<button
				class="cancel-button"
				on:click={() => {
					gameStore.update((state) => ({
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

			<button class="confirm-button" on:click={handleMainButtonClick} disabled={buttonsDisabled}>
				{purchasePending ? 'Confirm' : 'Submit'}
			</button>
		</div>
	{:else if guessCancelOnlyMode}
		<div class="solve-button-container">
			<button
				class="guess-phrase-button exit-mode"
				on:click={() => {
					gameStore.update((state) => ({
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
			<button class={buttonClass} on:click={handleMainButtonClick} disabled={buttonsDisabled}>
				{buttonLabel}
			</button>
		</div>
	{/if}
</div>

<style>
	@keyframes solvePulse {
		0%,
		100% {
			box-shadow: var(--glow-brand);
		}
		50% {
			box-shadow:
				0 0 0 1px rgba(253, 224, 71, 0.4),
				0 8px 36px rgba(251, 191, 36, 0.5);
		}
	}

	.message-box {
		position: fixed;
		bottom: calc(env(safe-area-inset-bottom, 0px) + 232px);
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
		/* Sit above the keyboard, which is lifted by the safe-area inset — match it so
     the button never overlaps the top key row on phones with a home indicator. */
		bottom: calc(env(safe-area-inset-bottom, 0px) + 188px);
		left: 50%;
		transform: translateX(-50%);
		display: flex;
		align-items: center;
		gap: 12px;
		z-index: 999;
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
		color: #3a2a00;
		border-radius: 14px;
		border: none;
		box-shadow: var(--glow-brand);
		transition:
			transform 0.16s var(--ease-spring),
			filter 0.2s,
			box-shadow 0.2s;
	}

	.guess-phrase-button:hover {
		transform: translateY(-2px);
		filter: brightness(1.05);
	}

	.guess-phrase-button:active {
		transform: scale(0.97);
	}

	.guess-phrase-button.guess-complete {
		animation: solvePulse 1.1s infinite;
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
		transition:
			transform 0.16s var(--ease-spring),
			filter 0.2s;
	}

	/* Confirm */
	.confirm-button {
		background: var(--brand-grad);
		color: #3a2a00;
		border: none;
		box-shadow: var(--glow-brand);
		animation: solvePulse 1.1s infinite;
	}
	.confirm-button:hover {
		filter: brightness(1.05);
		transform: translateY(-2px);
	}
	.confirm-button:active {
		transform: scale(0.97);
	}

	/* Cancel */
	.cancel-button {
		background: var(--surface-2);
		color: var(--text);
		border: 1px solid var(--border-strong);
	}
	.cancel-button:hover {
		transform: translateY(-1px);
		background: rgba(251, 90, 90, 0.16);
		border-color: rgba(251, 90, 90, 0.4);
	}
	.cancel-button:active {
		transform: scale(0.97);
	}
	.guess-phrase-button:disabled,
	.confirm-button:disabled,
	.cancel-button:disabled {
		opacity: 0.4;
		filter: grayscale(100%);
		cursor: not-allowed;
		box-shadow: none;
		background: #888 !important;
		color: #eee;
		border: 2px solid #666;
	}
</style>
