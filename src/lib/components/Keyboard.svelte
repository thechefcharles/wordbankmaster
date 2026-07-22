<script lang="ts">
	import { onMount } from 'svelte';
	import { get } from 'svelte/store';
	import Icon from '$lib/components/Icon.svelte';
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
		Q: 20,
		W: 40,
		E: 100,
		R: 90,
		T: 90,
		Y: 50,
		U: 60,
		I: 80,
		O: 70,
		P: 60,
		A: 100,
		S: 90,
		D: 60,
		F: 50,
		G: 50,
		H: 50,
		J: 20,
		K: 40,
		L: 60,
		Z: 30,
		X: 30,
		C: 60,
		V: 40,
		B: 50,
		N: 80,
		M: 50
	};

	const row1: string[] = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'];
	const row2: string[] = ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'];
	const row3: string[] = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];

	// Braille (Unicode patterns) for each letter — the tactile dots on ATM-style keys.
	const BRAILLE: Record<string, string> = {
		A: '⠁',
		B: '⠃',
		C: '⠉',
		D: '⠙',
		E: '⠑',
		F: '⠋',
		G: '⠛',
		H: '⠓',
		I: '⠊',
		J: '⠚',
		K: '⠅',
		L: '⠇',
		M: '⠍',
		N: '⠝',
		O: '⠕',
		P: '⠏',
		Q: '⠟',
		R: '⠗',
		S: '⠎',
		T: '⠞',
		U: '⠥',
		V: '⠧',
		W: '⠺',
		X: '⠭',
		Y: '⠽',
		Z: '⠵'
	};

	// Cash Game scales every letter by the tier's stake multiplier (Micro ×1 … Gold ×20);
	// 1 everywhere else. Server (climb_buy_letter) charges the same.
	$: climbMult =
		$gameStore.gameMode === 'climb' ? Number($gameStore.climbInfo?.stake ?? 1) || 1 : 1;
	// Match (1v1 challenge) sabotage/power-up state — cost stack mirrors server
	// match_buy_letter exactly: half_off (×0.5) → tax (×1.5) → vowel_block (×3 on
	// vowels) → toll (×3 on all, one-shot "next letter" surcharge). CEIL after the
	// ×0.5 and ×1.5 steps, same as the server's CEIL(v_cost * 0.5)::int etc.
	// Half Off now lasts 3 letter buys (half_off_left counter), not the whole puzzle — show the
	// discount only while it has charges left, in both Cash Game and matches.
	$: matchHalfOff =
		$gameStore.gameMode === 'match' && Number($gameStore.matchInfo?.half_off_left ?? 0) > 0;
	$: climbHalfOff =
		$gameStore.gameMode === 'climb' && Number($gameStore.climbInfo?.half_off_left ?? 0) > 0;
	$: matchDebuffs =
		$gameStore.gameMode === 'match' ? ($gameStore.matchInfo?.my_debuffs ?? []) : [];
	$: matchTax = matchDebuffs.includes('tax');
	$: matchVowelBlock = matchDebuffs.includes('vowel_block');
	$: matchToll = matchDebuffs.includes('toll');

	// Effective per-letter prices after active discount / vowel_vision / tier stake / match
	// sabotage (server matches): daily uses the shared modifier, match applies the debuff/
	// power-up stack above.
	$: effCosts = (() => {
		// Daily Twist that changes pricing — mirror the server buy (supabase-daily-v2.sql):
		// a mutually-exclusive IF/ELSIF chain. flat_rate=$50, discount=−25%, vowel_vision=vowels
		// −50%, consonant_sale=consonants −25%.
		const dailyMod = $gameStore.gameMode === 'daily' ? $gameStore.modifier : null;
		const out: Record<string, number> = {};
		for (const k of Object.keys(letterCosts)) {
			let c = letterCosts[k];
			const isVowel = 'AEIOU'.includes(k);
			if (dailyMod === 'flat_rate') c = 50;
			else if (dailyMod === 'discount') c = Math.ceil(c * 0.75);
			else if (dailyMod === 'vowel_vision' && isVowel) c = Math.ceil(c * 0.5);
			else if (dailyMod === 'consonant_sale' && !isVowel) c = Math.ceil(c * 0.75);
			c = c * climbMult;
			if (climbHalfOff) c = Math.ceil(c * 0.5);
			if ($gameStore.gameMode === 'match') {
				if (matchHalfOff) c = Math.ceil(c * 0.5);
				if (matchTax) c = Math.ceil(c * 1.5);
				if (matchVowelBlock && 'AEIOU'.includes(k)) c = c * 3;
				if (matchToll) c = c * 3;
			}
			out[k] = c;
		}
		return out;
	})();
	// A key is "taxed" (sabotage/tax inflated it above its plain base price) — flag it with
	// a visual tint/▲ so the price shown is never a surprise vs. what the server charges.
	$: taxedKeys =
		$gameStore.gameMode === 'match'
			? Object.keys(letterCosts).filter(
					(k) => (effCosts[k] ?? 0) > letterCosts[k] * climbMult
				)
			: [];

	type SelectedPurchase = { type: string; value?: string } | null;
	type LockedLetters = Record<string, unknown>;
	let selectedPurchase: SelectedPurchase = null;
	let lockedLetters: LockedLetters = {};
	let incorrectLetters: string[] = [];
	$: selectedPurchase = $gameStore.selectedPurchase as SelectedPurchase;
	$: lockedLetters = ($gameStore.lockedLetters || {}) as LockedLetters;
	$: incorrectLetters = ($gameStore.incorrectLetters || []) as string[];

	// The pool letters are bought from the mode's own budget — NOT $gameStore.bankroll, which
	// doubles as the user's Cash bank and can be stale mid-game. Cash Game → per-puzzle budget;
	// Daily → the Prize budget the HUD shows (dailyLive.remaining, matches the server charge).
	$: affordPool =
		$gameStore.gameMode === 'climb'
			? // Single shared balance: letters spend from banked run money + this puzzle's budget.
				Number($gameStore.climbInfo?.budget_left ?? 0)
			: $gameStore.gameMode === 'daily' || $gameStore.gameMode === 'freeplay'
				? Number($gameStore.dailyLive?.remaining ?? $gameStore.bankroll ?? 0)
				: Number($gameStore.bankroll ?? 0);
	// Free Play spends points, not Cash — mark letter prices with the ★ unit, not $.
	$: priceMark =
		$gameStore.gameMode === 'freeplay' || $gameStore.matchInfo?.friendly ? '★' : '$';
	// 🔹 Disable keys that are unaffordable or already marked incorrect (modifier-adjusted prices).
	$: disabledKeys = Object.keys(letterCosts).filter(
		(letter: string) => (effCosts[letter] ?? 0) > affordPool || incorrectLetters.includes(letter)
	);
	// 🟢 Keys you CAN still buy right now: price within budget, not already bought/wrong. Gets a
	// green price (matching the green budget number) so the buyable set reads at a glance —
	// only meaningful in purchase mode (guess mode types any letter for free).
	$: affordableKeys =
		$gameStore.gameState !== 'guess_mode'
			? Object.keys(letterCosts).filter(
					(letter: string) =>
						(effCosts[letter] ?? 0) <= affordPool &&
						!lockedLetters[letter] &&
						!incorrectLetters.includes(letter)
				)
			: [];

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
				gameStore.update((s) => ({ ...s, selectedPurchase: null, gameState: 'default' }));
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
				gameStore.update((s) => ({
					...s,
					gameState: 'guess_mode',
					selectedPurchase: null,
					guessedLetters: {}
				}));
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
      {affordableKeys.includes(letter) ? 'affordable' : ''}
      {selectedPurchase?.type === 'letter' &&
				selectedPurchase.value === letter &&
				$gameStore.gameState === 'purchase_pending'
					? 'pending'
					: ''}
      {lockedLetters[letter] ? 'purchased' : ''}
      {incorrectLetters.includes(letter) ? 'incorrect' : ''}
      {taxedKeys.includes(letter) ? 'taxed' : ''}"
				on:click={() => handleLetterClick(letter)}
			>
				<span class="braille">{BRAILLE[letter]}</span>
				<div class="letter">{letter}</div>
				<div class="price">
					{#if taxedKeys.includes(letter)}<span class="tax-mark">▲</span>{/if}{priceMark}{effCosts[
						letter
					] ?? 0}
				</div>
			</button>
		{/each}
	</div>

	<!-- Row 2: A - L -->
	<div class="keyboard-row">
		{#each row2 as letter}
			<button
				tabindex="-1"
				class="key {disabledKeys.includes(letter) && $gameStore.gameState !== 'guess_mode'
					? 'disabled'
					: ''}
                {affordableKeys.includes(letter) ? 'affordable' : ''}
                {selectedPurchase?.type === 'letter' &&
				selectedPurchase.value === letter &&
				$gameStore.gameState === 'purchase_pending'
					? 'pending'
					: lockedLetters[letter]
						? 'purchased'
						: incorrectLetters.includes(letter)
							? 'incorrect'
							: ''}
                {taxedKeys.includes(letter) ? 'taxed' : ''}"
				on:click={() => handleLetterClick(letter)}
			>
				<span class="braille">{BRAILLE[letter]}</span>
				<div class="letter">{letter}</div>
				<div class="price">
					{#if taxedKeys.includes(letter)}<span class="tax-mark">▲</span>{/if}{priceMark}{effCosts[
						letter
					] ?? 0}
				</div>
			</button>
		{/each}
	</div>

	<!-- Row 3: Z - M (Plus Delete Button in Guess Mode) -->
	<div class="keyboard-row">
		{#each row3 as letter}
			<button
				tabindex="-1"
				class="key {disabledKeys.includes(letter) && $gameStore.gameState !== 'guess_mode'
					? 'disabled'
					: ''}
                {affordableKeys.includes(letter) ? 'affordable' : ''}
                {selectedPurchase?.type === 'letter' &&
				selectedPurchase.value === letter &&
				$gameStore.gameState === 'purchase_pending'
					? 'pending'
					: lockedLetters[letter]
						? 'purchased'
						: incorrectLetters.includes(letter)
							? 'incorrect'
							: ''}
                {taxedKeys.includes(letter) ? 'taxed' : ''}"
				on:click={() => handleLetterClick(letter)}
			>
				<span class="braille">{BRAILLE[letter]}</span>
				<div class="letter">{letter}</div>
				<div class="price">
					{#if taxedKeys.includes(letter)}<span class="tax-mark">▲</span>{/if}{priceMark}{effCosts[
						letter
					] ?? 0}
				</div>
			</button>
		{/each}

		{#if $gameStore.gameState === 'guess_mode'}
			<button tabindex="-1" class="key delete" on:click={deleteGuessLetter}>
				<div class="letter"><Icon name="backspace" size={20} /></div>
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
		/* Lift off the bottom edge, clearing the home indicator. env(safe-area-inset-bottom)
		   reads 0 here because the app intentionally omits viewport-fit=cover (it broke native
		   tap coordinates), so env() can't be relied on. We floor the offset at 22px so the
		   bottom row is never clipped on phones with a home indicator, and still honor a real
		   --safe-area-inset-bottom var if a numeric-inset plugin later provides one. */
		bottom: calc(max(var(--safe-area-inset-bottom, 0px), 22px) + 8px);
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
		padding-bottom: 192px; /* Space for the lifted keyboard (raised for the home-indicator gap) */
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
		/* Snappy, reliable taps on mobile — no double-tap-zoom delay, no long-press select. */
		touch-action: manipulation;
		-webkit-tap-highlight-color: transparent;
		user-select: none;
		-webkit-user-select: none;
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
		transition:
			transform 0.1s var(--ease-spring),
			box-shadow 0.12s,
			border-color 0.15s;
	}
	.key:hover:not(.purchased):not(.incorrect):not(.disabled) {
		border-color: rgba(251, 191, 36, 0.6);
		box-shadow:
			inset 0 0 14px rgba(251, 191, 36, 0.12),
			0 2px 0 rgba(0, 0, 0, 0.6),
			0 4px 10px rgba(0, 0, 0, 0.5);
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
	.key.delete .letter {
		font-size: 19px;
		color: #fde047;
	}
	@keyframes blink {
		0% {
			opacity: 1;
		}
		50% {
			opacity: 0;
		}
		100% {
			opacity: 1;
		}
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
		background: linear-gradient(
			135deg,
			rgba(251, 191, 36, 0.3),
			rgba(253, 224, 71, 0.18)
		) !important;
		color: var(--brand-2) !important;
		border-color: rgba(253, 224, 71, 0.4) !important;
		cursor: default;
		pointer-events: none;
	}
	.purchased .price {
		color: rgba(253, 224, 71, 0.65);
	}
	.pending {
		background: var(--brand-grad) !important;
		color: #3a2a00 !important;
		border-color: transparent !important;
		box-shadow: var(--glow-brand);
		animation: keyPulse 1s infinite;
	}
	.pending .price {
		color: rgba(6, 33, 15, 0.7);
	}
	@keyframes keyPulse {
		0%,
		100% {
			filter: brightness(1);
		}
		50% {
			filter: brightness(1.12);
		}
	}
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
		0% {
			opacity: 1;
		}
		50% {
			opacity: 0.5;
		}
		100% {
			opacity: 1;
		}
	}

	/* Can't afford it (or wrong): clearly recede — dim + desaturate + grey the price, so the
	   buyable keys stand out by contrast. */
	.key.disabled {
		opacity: 0.32;
		filter: grayscale(0.7);
		pointer-events: none;
		transition:
			opacity 0.25s ease,
			filter 0.25s ease;
	}
	.key.disabled .price {
		color: var(--text-faint, #5d6b80);
	}
	/* 🟢 Can still buy it: green price (matches the green budget number) + a faint green edge,
	   so the affordable set reads at a glance without checking each price. */
	.key.affordable:not(.purchased):not(.pending) .price {
		color: #4ade80;
	}
	.key.affordable:not(.purchased):not(.pending):not(.taxed) {
		border-color: rgba(74, 222, 128, 0.45);
	}

	/* Match sabotage surcharge (tax/vowel_block/toll): a warm red tint + ▲ marker so an
	   inflated price is never mistaken for the plain base price. */
	.key.taxed:not(.purchased):not(.incorrect) {
		border-color: rgba(248, 113, 113, 0.55);
		box-shadow:
			inset 0 0 10px rgba(248, 113, 113, 0.14),
			0 2px 0 rgba(0, 0, 0, 0.6),
			0 4px 8px rgba(0, 0, 0, 0.5);
	}
	.key.taxed:not(.purchased):not(.incorrect) .price {
		color: rgba(248, 113, 113, 0.85);
	}
	.tax-mark {
		font-size: 7px;
		margin-right: 1px;
		color: rgba(248, 113, 113, 0.9);
	}

	/* In guess mode, all letters are tappable */
	:global(body.guess-mode) .key.incorrect,
	:global(body.guess-mode) .key.disabled {
		opacity: 1 !important;
		pointer-events: all;
	}
</style>
