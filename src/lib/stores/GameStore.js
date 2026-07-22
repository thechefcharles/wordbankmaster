// src/lib/stores/GameStore.js

import { writable, get } from 'svelte/store';
import { browser } from '$app/environment';
import { fx } from '$lib/sound.js';
import { armPushPrimer } from '$lib/pushPrimer.js';
import { LETTER_COSTS } from '$lib/letterCosts.js';
import { MODIFIERS } from '$lib/powerups.js';
import {
	dailyStart,
	dailyUseTwist,
	dailyUseBoost,
	dailyBuyLetter,
	dailyReveal,
	dailySubmitGuess,
	dailyFold as dailyFoldRpc,
	getDailyClue
} from '$lib/stores/statsStore.js';
import {
	makeupStart,
	makeupBuyLetter,
	makeupReveal,
	makeupSubmitGuess
} from '$lib/stores/statsStore.js';
import {
	climbStart,
	cashgameStart,
	cashgameCashout,
	climbBuyLetter,
	climbReveal,
	climbSubmitGuess,
	climbNext,
	climbLeave,
	climbForfeit,
	climbDoubleOrNothing,
	climbUsePowerup,
	getClimbClue
} from '$lib/stores/statsStore.js';
import {
	createMatch,
	acceptMatch,
	matchStart,
	matchBuyLetter,
	matchReveal,
	matchSubmitGuess,
	matchNext as matchNextRpc,
	matchFold as matchFoldRpc,
	matchCheck,
	matchUsePowerup,
	matchSabotage
} from '$lib/stores/statsStore.js';
import { track } from '$lib/analytics.js';
import { newGame, buyLetter, applyGuess, scoreOnSolve, toBoard } from '$lib/freeplay/engine.js';
import { FREEPLAY_PUZZLES } from '$lib/freeplay/puzzles.js';
import { loadPoints, recordSolve, bankMatchPoints } from '$lib/freeplay/points.js';

/* ================================
   Types (JSDoc for checkJs)
=================================== */
/**
 * @typedef {{ type: string, value?: string }} SelectedPurchase
 * @typedef {{ [key: string]: unknown }} LockedLetters
 * @typedef {{ [key: number]: string }} GuessedLetters
 */

/**
 * @typedef {{
 *   bankroll: number,
 *   wagerAmount: number,
 *   guessesRemaining: number,
 *   category: string,
 *   currentPhrase: string,
 *   gameState: string,
 *   purchasedLetters: string[],
 *   guessedLetters: GuessedLetters,
 *   lockedLetters: LockedLetters,
 *   incorrectLetters: string[],
 *   selectedPurchase: SelectedPurchase | null,
 *   shakenLetters: number[],
 *   message: string,
 *   subcategory: string,
 *   gameMode: string,
 *   freeReveals?: number,
 *   modifier?: string | null,
 *   bountyMult?: number,
 *   twistUsed?: boolean,
 *   wrongGuesses?: number,
 *   dailyMustGuess?: boolean,
 *   fpLastGain?: number,
 *   clue?: string | null,
 *   makeupDate?: string | null,
 *   dailyResult?: any,
 *   climbInfo?: any,
 *   matchInfo?: any,
 *   cashToast?: { amount:number, label:string } | null,
 *   dailyLive?: { remaining:number, mult:number, winnings:number } | null,
 *   dailyIntro?: number,
 *   dailyIntroGo?: number,
 *   dailyIntroPlayed?: number,
 *   dailyOpenedAt?: number|null,
 *   dailyBestSeconds?: number|null,
 *   wrongTick?: number,
 *   twistCue?: { id:number, text:string } | null
 * }} GameState
 */

/* ================================
   Constants & Store Initialization
=================================== */

// Letter purchase costs (mirror of server public.letter_cost())
export { LETTER_COSTS };

/** @type {import('svelte/store').Writable<GameState>} */
export const gameStore = writable(
	/** @type {GameState} */ ({
		bankroll: 1000,
		wagerAmount: 1,
		guessesRemaining: 3,
		category: '',
		currentPhrase: '',
		gameState: 'default', // States: "default", "purchase_pending", "guess_mode", "won", "lost"
		purchasedLetters: [],
		guessedLetters: {},
		lockedLetters: {},
		incorrectLetters: [],
		selectedPurchase: null,
		shakenLetters: [],
		message: '',
		subcategory: '',
		gameMode: 'daily', // 'daily' | 'climb' | 'match' | 'makeup' | 'freeplay'
		freeReveals: 0, // owned Free Reveal power-ups (daily)
		modifier: null, // today's Daily Twist power-up id (daily only)
		twistUsed: false, // have you used today's Twist? (unused → ×1.5 bounty)
		bountyMult: 1, // bounty multiplier (1.0 once Twist used, else 1.5)
		wrongGuesses: 0, // wrong phrase guesses this Daily — FREE now (tracked for stats only)
		dailyMustGuess: false, // Daily out-of-budget wall → last-guess danger treatment
		clue: null, // witty one-line hint for the current puzzle
		makeupDate: null, // YYYY-MM-DD of the make-up day being played (makeup mode only)
		climbInfo: null, // { bounty, heat, spent, position, final_guess, cheapest, wrong_penalty, last_gain, state } (climb mode)
		matchInfo: null, // { position, pack_size, total_score, last_score, done, status } (challenge match)
		cashToast: null, // { amount, label } — transient Cash-earned toast (attendance / free-play reward)
		dailyLive: null, // { remaining, mult, winnings } — live Daily V2 HUD (Prize left → what you'd bank)
		dailyIntro: 0, // bumps on a FRESH daily open → ARMS the opening reveal (pending)
		dailyIntroGo: 0, // bumps once the board is actually visible → PLAYS the opening reveal
		dailyIntroPlayed: 0, // the dailyIntro token that has already played (persists across remounts)
		dailyOpenedAt: null, // epoch ms the server stamped for today's Daily (solve-timer anchor)
		dailyBestSeconds: null, // player's fastest valid Daily solve, seconds (PB ghost)
		wrongTick: 0, // bumps on a non-busting wrong whole-phrase guess → UI flashes a distinct "✗ Wrong" cue
		twistCue: null // { id, text } — transient "the Twist just did X" toast (Daily), cleared by the UI
	})
);

/* ================================
   Utility Functions
=================================== */

/**
 * launchConfetti — disabled. Confetti wins were removed across all modes; the
 * slot-machine reveal + win banners are the celebration. Kept as a no-op so the
 * existing call sites stay harmless.
 */
function launchConfetti() {}

/* ================================
   Server-authoritative DAILY adapter

   For daily mode the puzzle answer never reaches the client. These helpers call
   the server RPCs and reconcile the existing gameStore shape from the masked
   board they return, so the UI (PhraseDisplay/Keyboard/GameButtons) is unchanged.
   The local currentPhrase is a MASK: real letters at revealed positions, '#' at
   unrevealed letter positions, real spaces between words.
=================================== */

// Guards against double-submits while a daily RPC is in flight.
let dailyInFlight = false;

/**
 * reconcileDailyBoard
 * Rebuild gameStore from a server board view. The answer is only present once
 * the game is finished (board.phrase), so during play currentPhrase stays masked.
 *
 * @param {any} board - board JSON returned by a daily_* RPC
 */
/**
 * boardToState — shared masked-board → gameStore partial.
 * @param {any} board @param {GameState} prev
 */
function boardToState(board, prev) {
	/** @type {number[]} */
	const wordLengths = board.word_lengths || [];
	const chars = wordLengths
		.map((/** @type {number} */ len) => '#'.repeat(len))
		.join(' ')
		.split('');
	/** @type {Record<string, string>} */
	const revealed = board.revealed || {};
	/** @type {string[]} */
	const purchased = [];
	/** @type {number[]} */
	const newlyRevealed = [];
	for (const [k, v] of Object.entries(revealed)) {
		const i = Number(k);
		chars[i] = /** @type {string} */ (v);
		purchased[i] = /** @type {string} */ (v);
		if (prev.purchasedLetters?.[i] !== v) newlyRevealed.push(i);
	}
	const finished = board.state !== 'active';
	const currentPhrase =
		finished && board.phrase ? String(board.phrase).toUpperCase() : chars.join('');
	/** @type {Record<string, boolean>} */
	const lockedLetters = {};
	(board.locked_letters || []).forEach((/** @type {string} */ l) => {
		lockedLetters[l] = true;
	});
	return {
		bankroll: board.bankroll,
		guessesRemaining: board.guesses_remaining,
		category: board.category ?? prev.category,
		subcategory: board.subcategory ?? '',
		currentPhrase,
		purchasedLetters: purchased,
		guessedLetters: {},
		lockedLetters,
		incorrectLetters: board.incorrect_letters || [],
		selectedPurchase: null,
		shakenLetters: newlyRevealed,
		wagerAmount: 0,
		message: ''
	};
}

/**
 * In-play audio/haptic cue from comparing the previous board to the new one.
 * (Win/bust cues are fired by the callers.)
 * @param {GameState} prev @param {any} board
 */
function playMoveCue(prev, board) {
	const revealed = board.revealed || {};
	let newReveals = 0;
	for (const [k, v] of Object.entries(revealed)) {
		if (prev.purchasedLetters?.[Number(k)] !== v) newReveals++;
	}
	const incGrew = (board.incorrect_letters || []).length > (prev.incorrectLetters || []).length;
	if (newReveals >= 2) fx('reveal');
	else if (newReveals > 0) fx('correct');
	else if (incGrew) fx('wrong');
}

/** @param {any} board */
function reconcileDailyBoard(board) {
	if (!board) return;
	const prev = get(gameStore);
	const finished = board.state !== 'active';
	gameStore.set(
		/** @type {GameState} */ ({
			...prev,
			...boardToState(board, prev),
			gameMode: 'daily',
			gameState: finished ? board.state : 'default',
			dailyResult: board.daily_result ?? prev.dailyResult ?? null,
			dailyLive: board.live ?? prev.dailyLive ?? null,
			// Daily Twist: the available modifier id + whether you've used it + bounty multiplier.
			modifier: board.modifier !== undefined ? board.modifier : prev.modifier,
			twistUsed: board.twist_used !== undefined ? board.twist_used : (prev.twistUsed ?? false),
			bountyMult: board.bounty_mult !== undefined ? board.bounty_mult : (prev.bountyMult ?? 1),
			wrongGuesses:
				board.wrong_guesses !== undefined ? board.wrong_guesses : (prev.wrongGuesses ?? 0),
			// Daily out-of-budget wall: bankroll < cheapest buyable letter on an active board.
			dailyMustGuess:
				board.must_guess !== undefined ? !!board.must_guess : (prev.dailyMustGuess ?? false),
			// Solve-timer anchor (server opened_at, ms) + PB ghost. Keep prior value when a
			// board refresh omits them, so buying letters mid-solve doesn't clear the timer.
			dailyOpenedAt: board.opened_at ?? prev.dailyOpenedAt ?? null,
			dailyBestSeconds: board.best_solve_seconds ?? prev.dailyBestSeconds ?? null
		})
	);
	// Only celebrate a FRESH solve: a board carrying daily_result (set by the solve),
	// not when re-opening an already-completed daily (which comes back 'won' with no result).
	if (board.state === 'won') {
		if (board.daily_result) {
			fx('win');
		}
	} // no confetti — the slot-machine reveal is the celebration
	else if (finished) fx('bust');
	else playMoveCue(prev, board);
	// analytics: fire once, only on the actual solve transition
	if (board.daily_result && prev.gameState !== 'won' && prev.gameState !== 'lost') {
		track('daily_result', { won: true, bankroll: board.bankroll ?? 0 });
	}
}

/* ===== Make-up daily (play a past missed day; no streak/Bank, badges only) ===== */
/** @type {string|null} */
let activeMakeupDate = null;

/** @param {any} board */
function reconcileMakeupBoard(board) {
	if (!board) return;
	const prev = get(gameStore);
	const finished = board.state !== 'active';
	gameStore.set(
		/** @type {GameState} */ ({
			...prev,
			...boardToState(board, prev),
			gameMode: 'makeup',
			gameState: finished ? board.state : 'default',
			modifier: null,
			clue: board.clue ?? prev.clue ?? null,
			makeupDate: board.makeup?.date ?? prev.makeupDate ?? activeMakeupDate
		})
	);
	if (board.state === 'won') {
		setTimeout(() => launchConfetti(), 300);
		fx('win');
	} else if (finished) fx('bust');
	else playMoveCue(prev, board);
	if (finished && prev.gameState !== 'won' && prev.gameState !== 'lost') {
		track('makeup_result', { won: board.state === 'won', date: board.makeup?.date });
	}
}

/** Begin (or resume) a make-up for a past date. @param {string} date YYYY-MM-DD */
export async function enterMakeup(date) {
	track('makeup_start', { date });
	const board = await makeupStart(date);
	if (!board) return false;
	activeMakeupDate = date;
	if (typeof localStorage !== 'undefined') {
		localStorage.setItem('gameMode', 'makeup');
		localStorage.setItem('makeupDate', date);
	}
	reconcileMakeupBoard(board);
	return true;
}

/** Re-enter the make-up game on the home route (deep link / refresh). */
export async function fetchMakeupGame() {
	try {
		if (!activeMakeupDate && typeof localStorage !== 'undefined') {
			activeMakeupDate = localStorage.getItem('makeupDate');
		}
		if (!activeMakeupDate) return false;
		const board = await makeupStart(activeMakeupDate);
		if (!board) return false;
		reconcileMakeupBoard(board);
		return true;
	} catch (err) {
		console.error('❌ Error starting make-up:', err instanceof Error ? err.message : String(err));
		return false;
	}
}

/** @param {GameState} state */
async function confirmPurchaseMakeup(state) {
	const purchase = state.selectedPurchase;
	if (!purchase || dailyInFlight || !activeMakeupDate) return;
	dailyInFlight = true;
	try {
		let board = null;
		if (purchase.type === 'letter')
			board = await makeupBuyLetter(activeMakeupDate, purchase.value ?? '');
		else if (purchase.type === 'hint') board = await makeupReveal(activeMakeupDate);
		if (board) reconcileMakeupBoard(board);
		else gameStore.update((s) => ({ ...s, selectedPurchase: null, gameState: 'default' }));
	} finally {
		dailyInFlight = false;
	}
}

/** @param {GameState} state */
async function submitGuessMakeup(state) {
	if (state.gameState !== 'guess_mode' || dailyInFlight || !activeMakeupDate) return;
	/** @type {Record<string, string>} */
	const guess = {};
	for (const [k, v] of Object.entries(state.guessedLetters || {}))
		guess[k] = /** @type {string} */ (v);
	if (Object.keys(guess).length === 0) return;
	dailyInFlight = true;
	try {
		const board = await makeupSubmitGuess(activeMakeupDate, guess);
		if (board) reconcileMakeupBoard(board);
	} finally {
		dailyInFlight = false;
	}
}

/* ===== Free Play (offline-ready, points-only, no server) ===== */
/** @type {ReturnType<typeof newGame>|null} */
let freeplayState = null;

/** localStorage-or-null; safe on SSR. */
function fpStorage() {
	return browser ? window.localStorage : { getItem: () => null, setItem: () => {} };
}

/** Read this device's Free Play totals. */
export function freePlayPoints() {
	return loadPoints(fpStorage());
}

/** Map the engine board into gameStore, reusing the shared boardToState mapper. */
function reconcileFreeplayBoard() {
	if (!freeplayState) return;
	const board = toBoard(freeplayState);
	const prev = get(gameStore);
	const won = board.state === 'won';
	const lost = board.state === 'lost';
	const justWon = won && prev.gameState !== 'won';
	const justLost = lost && prev.gameState !== 'lost';
	// ★ banked this solve (kept = budget − spent). Held on the state so the win flourish
	// can show "+★X banked" without recomputing; preserved while the won board lingers.
	const gained = justWon ? scoreOnSolve(freeplayState) : won ? (prev.fpLastGain ?? 0) : 0;
	gameStore.set(
		/** @type {GameState} */ ({
			...prev,
			...boardToState(board, prev),
			gameMode: 'freeplay',
			gameState: won ? 'won' : lost ? 'lost' : 'default',
			clue: board.clue ?? null,
			dailyLive: board.live,
			fpLastGain: gained,
			// Out-of-points "last guess" wall — reuses the Daily must-guess flag + danger screen.
			dailyMustGuess: !!board.must_guess,
			// freeplay never uses these money/daily fields:
			climbInfo: null,
			matchInfo: null,
			dailyResult: null,
			modifier: null
		})
	);
	if (justWon) {
		recordSolve(fpStorage(), gained);
		fx('win');
	} else if (justLost) {
		fx('bust');
	} else if (!won && !lost) {
		playMoveCue(prev, board);
	}
	// Persist for continuous resume — but ONLY once the player has engaged (bought a letter;
	// spent > 0). Merely viewing a fresh puzzle never commits it, so a glance-and-back-out
	// gives a fresh puzzle next time. A finished puzzle clears itself.
	if (won || lost) clearFreeplay();
	else if ((freeplayState?.spent ?? 0) > 0) saveFreeplay();
}

// Free Play persists so it RESUMES continuously (leaving to the menu never restarts it).
// It lives in its own localStorage key — Free Play is client-only and is never a "saved game"
// or an "active game", so this never trips the store's can't-buy-during-a-game gate (you
// can't use items in Free Play anyway).
const FP_KEY = 'wb_freeplay_game';
function saveFreeplay() {
	if (!browser || !freeplayState) return;
	try {
		window.localStorage.setItem(FP_KEY, JSON.stringify(freeplayState));
	} catch {
		/* storage blocked — just won't resume */
	}
}
function clearFreeplay() {
	if (!browser) return;
	try {
		window.localStorage.removeItem(FP_KEY);
	} catch {
		/* ignore */
	}
}
/** Load a resumable Free Play puzzle: in-progress AND actually engaged (a letter bought).
 * @returns {ReturnType<typeof newGame>|null} */
function loadFreeplay() {
	if (!browser) return null;
	try {
		const raw = window.localStorage.getItem(FP_KEY);
		if (!raw) return null;
		const s = JSON.parse(raw);
		if (s && s.status === 'active' && (s.spent ?? 0) > 0) return s;
	} catch {
		/* ignore */
	}
	return null;
}

/** Enter Free Play. Silently resumes an engaged-with puzzle; otherwise a fresh one.
 *  No "Resume" prompt — it just picks up where you left off. */
export function startFreePlay() {
	const saved = loadFreeplay();
	if (saved) {
		freeplayState = saved;
		reconcileFreeplayBoard();
	} else {
		freePlayNext();
	}
}

/** Load the next random Free Play puzzle (fresh + uncommitted until a letter is bought). */
export function freePlayNext() {
	clearFreeplay();
	const puzzle = FREEPLAY_PUZZLES[Math.floor(Math.random() * FREEPLAY_PUZZLES.length)];
	freeplayState = newGame(puzzle);
	reconcileFreeplayBoard();
}

/** @param {GameState} current */
function confirmPurchaseFreeplay(current) {
	if (current.gameState === 'won') return;
	const sel = current.selectedPurchase;
	if (!freeplayState || !sel || sel.type !== 'letter') return;
	freeplayState = buyLetter(freeplayState, sel.value ?? '');
	reconcileFreeplayBoard();
}

/** @param {GameState} current */
function submitGuessFreeplay(current) {
	if (current.gameState === 'won') return;
	if (!freeplayState) return;
	/** @type {Record<number,string>} */
	const filled = {};
	for (const [k, v] of Object.entries(current.guessedLetters || {})) filled[Number(k)] = String(v);
	freeplayState = applyGuess(freeplayState, filled);
	gameStore.update((s) => ({ ...s, gameState: 'default', guessedLetters: {} }));
	reconcileFreeplayBoard();
}

/* ===== Cash Game / the Climb (real-Cash, fluid, par/bounty + heat) ===== */
/** Refresh the clue for the current climb puzzle (changes each rung). */
async function refreshClimbClue() {
	try {
		const clue = await getClimbClue();
		gameStore.update((s) => ({ ...s, clue }));
	} catch {
		/* non-fatal */
	}
}

/** @param {any} board @param {boolean} [wrong] a wrong-but-still-playing guess (bump the "✗ Wrong" cue) */
function reconcileClimbBoard(board, wrong = false) {
	if (!board) return;
	const prev = get(gameStore);
	const climb = board.climb || {};
	// 'solved' shows a win beat (then climbAdvance); 'busted' ends the run (you lost the buy-in).
	const solved = climb.state === 'solved';
	const busted = climb.state === 'busted' || climb.busted === true;
	gameStore.set(
		/** @type {GameState} */ ({
			...prev,
			...boardToState(board, prev),
			gameMode: 'climb',
			gameState: busted ? 'lost' : solved ? 'won' : 'default',
			modifier: null,
			climbInfo: climb,
			// Bump in the SAME update as the budget drop so the floater is labeled correctly.
			wrongTick: wrong ? (prev.wrongTick || 0) + 1 : (prev.wrongTick ?? 0)
		})
	);
	// No confetti — the slot-machine reveal (box-by-box win pop) is the celebration, like Daily.
	if (busted) fx('bust');
	else if (solved) {
		fx('win');
	} else if (board.shielded) {
		// 🛡️ Heat Shield turned a would-be bust into a fresh puzzle (Payout + interest kept).
		fx('multiplier');
		flashTwistCue('Heat Shield · saved your run!');
	} else playMoveCue(prev, board);
}

/** Arm the dramatic opening reveal for a FRESH (untouched) climb puzzle. */
function maybeArmClimbIntro() {
	const s = get(gameStore);
	const hasProgress = (s.purchasedLetters || []).some(Boolean) || (s.climbInfo?.spent ?? 0) > 0;
	if (!hasProgress && s.gameState === 'default') {
		gameStore.update((st) => ({ ...st, dailyIntro: (st.dailyIntro || 0) + 1 }));
	}
}

/** Arm the dramatic opening reveal for a FRESH challenge puzzle (per-puzzle progress is
 *  empty). The no-progress gate means a mid-puzzle RESUME never replays the reveal. */
function maybeArmMatchIntro() {
	const s = get(gameStore);
	const hasProgress =
		(s.purchasedLetters || []).some(Boolean) || (s.incorrectLetters || []).length > 0;
	if (!hasProgress && s.gameState === 'default') {
		gameStore.update((st) => ({ ...st, dailyIntro: (st.dailyIntro || 0) + 1 }));
	}
}

/** Resume an in-progress Cash Game run. Returns 'needs_tier' when there's no live run
 *  (the caller then shows the tier-select), true if a run was restored, false on error. */
export async function fetchClimbGame() {
	try {
		const board = await climbStart();
		if (!board) return false;
		if (board.needs_tier) return 'needs_tier';
		reconcileClimbBoard(board);
		// Resume = no dramatic reveal (you've already seen this puzzle). The reveal is armed
		// only on genuine new puzzles — startCashGame, climbAdvance, free-skip, Heat-Shield jump.
		await refreshClimbClue();
		return true;
	} catch (err) {
		console.error('❌ Error resuming Cash Game:', err instanceof Error ? err.message : String(err));
		return false;
	}
}

/** Buy in at a tier and start a fresh run. @param {string} tier @returns {Promise<any>} */
export async function startCashGame(tier) {
	try {
		track('cashgame_start', { tier });
		const resp = await cashgameStart(tier);
		if (!resp?.ok) return resp || { ok: false };
		reconcileClimbBoard(resp);
		maybeArmClimbIntro();
		await refreshClimbClue();
		return resp;
	} catch (err) {
		console.error('❌ Error starting Cash Game:', err instanceof Error ? err.message : String(err));
		return { ok: false };
	}
}

/** Cash out the current run → bank the bankroll, end the run. @returns {Promise<any>} */
export async function cashOutClimb() {
	if (dailyInFlight) return { ok: false };
	dailyInFlight = true;
	try {
		const resp = await cashgameCashout();
		if (resp?.ok) {
			fx('multiplier');
			// Surface a cash-out result the UI can celebrate, then clear the run.
			gameStore.update((s) => ({
				...s,
				gameState: 'won',
				climbInfo: { ...(s.climbInfo || {}), state: 'cashed_out', cashout: resp }
			}));
		}
		return resp || { ok: false };
	} finally {
		dailyInFlight = false;
	}
}

/** @param {GameState} state */
async function confirmPurchaseClimb(state) {
	const purchase = state.selectedPurchase;
	if (!purchase || dailyInFlight) return;
	dailyInFlight = true;
	try {
		let board = null;
		if (purchase.type === 'letter') board = await climbBuyLetter(purchase.value ?? '');
		else if (purchase.type === 'hint') board = await climbReveal();
		if (board) reconcileClimbBoard(board);
		else gameStore.update((s) => ({ ...s, selectedPurchase: null, gameState: 'default' }));
	} finally {
		dailyInFlight = false;
	}
}

/** @param {GameState} state */
async function submitGuessClimb(state) {
	if (state.gameState !== 'guess_mode' || dailyInFlight) return;
	/** @type {Record<string, string>} */
	const guess = {};
	for (const [k, v] of Object.entries(state.guessedLetters || {}))
		guess[k] = /** @type {string} */ (v);
	if (Object.keys(guess).length === 0) return;
	dailyInFlight = true;
	try {
		const prevSpent = get(gameStore).climbInfo?.spent ?? 0;
		const board = await climbSubmitGuess(guess);
		if (board) {
			// A wrong guess that DOESN'T bust now drains budget and keeps the run alive
			// (server: cashgame wrong-guess penalty). Detect it so the UI shows a distinct
			// "✗ Wrong" cue instead of a silent letter-buy-style −$X drop.
			const c = board.climb || {};
			const stillPlaying = c.state !== 'solved' && c.state !== 'busted' && c.busted !== true;
			const wrong = stillPlaying && (c.spent ?? 0) > prevSpent;
			reconcileClimbBoard(board, wrong);
			if (wrong) fx('wrong');
			// 🛡️ Heat Shield jumped you to a fresh puzzle — arm its reveal + pull the new clue.
			if (board.shielded) {
				maybeArmClimbIntro();
				await refreshClimbClue();
			}
		}
	} finally {
		dailyInFlight = false;
	}
}

/** Advance to the next climb puzzle after a solve. */
export async function climbAdvance() {
	if (dailyInFlight) return;
	dailyInFlight = true;
	try {
		const board = await climbNext();
		if (board) {
			reconcileClimbBoard(board);
			maybeArmClimbIntro();
			await refreshClimbClue();
		}
	} finally {
		dailyInFlight = false;
	}
}

/** ⏭️ Free Skip power-up — swap the current puzzle for a fresh one mid-run, keeping
 *  your Interest, secured pile, and run. Arms the dramatic reveal like a fresh puzzle. */
export async function climbFreeSkip() {
	if (dailyInFlight) return;
	dailyInFlight = true;
	try {
		const board = await climbUsePowerup('free_skip');
		if (board) {
			reconcileClimbBoard(board);
			maybeArmClimbIntro();
			await refreshClimbClue();
		}
	} finally {
		dailyInFlight = false;
	}
}

/** Voluntarily give up the current Cash Game run — a clean bust (same as a wrong
 *  guess: wipes the pot, reveals the answer). Shows the VOID receipt. */
export async function climbForfeitRun() {
	const board = await climbForfeit();
	if (board) reconcileClimbBoard(board);
	return board;
}

/** Leave the Cash Game (clears heat; position + Cash persist). */
export async function climbLeaveGame() {
	try {
		await climbLeave();
	} catch {
		/* non-fatal */
	}
}

/** Arm Double-or-Nothing on the current Cash Game puzzle (heat ≥ ×1.5).
 *  Solve → payout doubles; get stuck → $0 and you forfeit your spend. You can't skip once armed. */
export async function climbArmDoubleOrNothing() {
	if (dailyInFlight) return;
	dailyInFlight = true;
	try {
		const board = await climbDoubleOrNothing();
		if (board) reconcileClimbBoard(board);
	} finally {
		dailyInFlight = false;
	}
}

/** Equip a power-up in the Climb (v3: charges Cash on use, counts as spend). @param {string} id */
export async function climbPowerup(id) {
	if (dailyInFlight) return;
	dailyInFlight = true;
	try {
		const board = await climbUsePowerup(id);
		if (board) reconcileClimbBoard(board);
	} finally {
		dailyInFlight = false;
	}
}

/* ===== Challenge Builder match play (pack of puzzles vs friends/group) ===== */
/** @type {string|null} */
let activeMatchId = null;

/** @param {any} board */
function reconcileMatchBoard(board) {
	if (!board) return;
	const prev = get(gameStore);
	const match = board.match || {};
	const done = match.done === true;
	gameStore.set(
		/** @type {GameState} */ ({
			...prev,
			...(done ? {} : boardToState(board, prev)),
			gameMode: 'match',
			gameState: done ? 'won' : 'default',
			modifier: null,
			clue: done ? prev.clue : (board.clue ?? null),
			matchInfo: {
				...match,
				id: activeMatchId,
				standing: board.standing ?? null,
				friendly: (match.wager ?? 0) === 0
			}
		})
	);
	// Between-puzzle receipt: a non-final solve now pauses in `awaiting_next` (gated modes)
	// instead of auto-advancing. Detect the fresh solve vs. an auto-advance (match-clock/legacy).
	const awaiting = match.awaiting_next === true;
	const wasAwaiting = prev.matchInfo?.awaiting_next === true;
	const freshSolveGated = awaiting && !wasAwaiting; // just solved → now showing the receipt
	const advancedAuto =
		!awaiting &&
		!wasAwaiting &&
		prev.matchInfo &&
		(match.last_score ?? 0) > 0 &&
		(match.position ?? 1) > (prev.matchInfo.position ?? 0); // match-clock / legacy auto-advance
	if (done) {
		setTimeout(() => launchConfetti(), 250);
		fx('win');
		// Friendly (wager 0) banks its ★ into the device Free Play total — once per match.
		if ((match.wager ?? 0) === 0) {
			bankMatchPoints(fpStorage(), activeMatchId, match.total_score ?? 0);
		}
	} else if (freshSolveGated || advancedAuto) {
		// Celebrate EACH solved puzzle. On auto-advance the next puzzle is already loaded,
		// so arm its opening reveal; on the gated receipt we wait for the Next tap.
		setTimeout(() => launchConfetti(), 250);
		fx('win');
		if (advancedAuto) maybeArmMatchIntro();
	} else if (!awaiting && wasAwaiting) {
		// Tapped "Next puzzle" → the new puzzle is loaded → give it the dramatic opening reveal.
		maybeArmMatchIntro();
	} else playMoveCue(prev, board);
}

/** Advance to the next puzzle from the between-puzzle receipt. */
export async function advanceMatch() {
	if (dailyInFlight || !activeMatchId) return;
	dailyInFlight = true;
	try {
		const board = await matchNextRpc(activeMatchId);
		if (board) reconcileMatchBoard(board);
		return board;
	} finally {
		dailyInFlight = false;
	}
}

/** Create a match and drop into play. @param {any} opts @returns {Promise<any>} */
export async function startMatch(opts) {
	const resp = await createMatch(opts);
	if (resp?.ok && resp.match) {
		track('match_create', { wager: opts.wager ?? 0, pack: opts.pack_size ?? 1 });
		armPushPrimer(); // ask about notifications at the next pause, not over the puzzle
		const id = resp.match.id;
		activeMatchId = id;
		const board = await matchStart(id);
		if (board) {
			reconcileMatchBoard(board);
			maybeArmMatchIntro();
		}
	}
	return resp;
}

/** Use an owned power-up in the active match (if items allowed). @param {string} powerupId */
export async function matchPowerup(powerupId) {
	if (dailyInFlight || !activeMatchId) return;
	dailyInFlight = true;
	try {
		const board = await matchUsePowerup(activeMatchId, powerupId);
		if (board) reconcileMatchBoard(board);
		return board;
	} finally {
		dailyInFlight = false;
	}
}

/** Sabotage an opponent in the active match. @param {string} targetId @param {string} powerupId */
export async function matchSabotageOpponent(targetId, powerupId) {
	if (dailyInFlight || !activeMatchId) return;
	dailyInFlight = true;
	try {
		const board = await matchSabotage(activeMatchId, targetId, powerupId);
		if (board) reconcileMatchBoard(board);
		return board;
	} finally {
		dailyInFlight = false;
	}
}

/** Accept (escrow) an invited match and start playing. @param {string} id @param {boolean} [reduced] stake only what you have @returns {Promise<boolean>} */
export async function acceptAndPlayMatch(id, reduced = false) {
	const resp = await acceptMatch(id, reduced);
	if (!resp?.ok) return false;
	track('match_accept');
	armPushPrimer(); // ask about notifications at the next pause, not over the puzzle
	activeMatchId = id;
	const board = await matchStart(id);
	if (board) {
		reconcileMatchBoard(board);
		maybeArmMatchIntro();
	}
	return true;
}

/** Force the server to lock a timed match's score when the clock expires. */
export async function matchTimeoutCheck() {
	if (!activeMatchId) return;
	const board = await matchCheck(activeMatchId);
	if (board) reconcileMatchBoard(board);
}

/** Light live refresh — re-pull only the match meta (my_debuffs, standing, opponents'
 *  scores) without touching local input (guess mode / pending purchase). Called on
 *  realtime participant changes so a sabotage debuff or an opponent's score shows instantly. */
export async function refreshMatchMeta() {
	if (!activeMatchId) return;
	const board = await matchCheck(activeMatchId);
	if (!board) return;
	const match = board.match || {};
	gameStore.update((s) =>
		s.gameMode === 'match'
			? {
					...s,
					matchInfo: {
						...match,
						id: activeMatchId,
						standing: board.standing ?? null,
						friendly: (match.wager ?? 0) === 0
					}
				}
			: s
	);
}

/** Resume a match I'm already in. @param {string} id @returns {Promise<boolean>} */
export async function resumeMatch(id) {
	activeMatchId = id;
	const board = await matchStart(id);
	if (board) {
		reconcileMatchBoard(board);
		return true;
	} // resume = no dramatic reveal (you've seen this puzzle)
	return false;
}

/** @param {GameState} state */
async function confirmPurchaseMatch(state) {
	const purchase = state.selectedPurchase;
	if (!purchase || dailyInFlight || !activeMatchId) return;
	dailyInFlight = true;
	try {
		let board = null;
		if (purchase.type === 'letter')
			board = await matchBuyLetter(activeMatchId, purchase.value ?? '');
		else if (purchase.type === 'hint') board = await matchReveal(activeMatchId);
		if (board) reconcileMatchBoard(board);
		else gameStore.update((s) => ({ ...s, selectedPurchase: null, gameState: 'default' }));
	} finally {
		dailyInFlight = false;
	}
}

/** @param {GameState} state */
async function submitGuessMatch(state) {
	if (state.gameState !== 'guess_mode' || dailyInFlight || !activeMatchId) return;
	/** @type {Record<string, string>} */
	const guess = {};
	for (const [k, v] of Object.entries(state.guessedLetters || {}))
		guess[k] = /** @type {string} */ (v);
	if (Object.keys(guess).length === 0) return;
	dailyInFlight = true;
	try {
		const board = await matchSubmitGuess(activeMatchId, guess);
		if (board) reconcileMatchBoard(board);
	} finally {
		dailyInFlight = false;
	}
}

let _twistCueId = 0;
/** Flash a transient "the Twist just did X" toast (Daily). @param {string} text */
function flashTwistCue(text) {
	if (!text) return;
	gameStore.update((s) => ({ ...s, twistCue: { id: ++_twistCueId, text } }));
}

/**
 * Explain a Daily Twist the moment it affects a letter buy: the Insured free wrong
 * letter, or a pricing Twist's saving (discount/flat/vowel-vision/consonant-sale).
 * @param {string} letter @param {number} prevBankroll @param {number} prevWrong @param {string|null|undefined} mod
 */
function detectDailyBuyCue(letter, prevBankroll, prevWrong, mod) {
	if (!mod) return;
	const info = MODIFIERS[mod];
	if (!info) return;
	const s = get(gameStore);
	const charged = Math.max(0, prevBankroll - (s.bankroll ?? 0));
	const wasWrong = (s.incorrectLetters || []).length > prevWrong;
	const base = LETTER_COSTS[letter] || 0;
	// Insured: the first wrong letter is free.
	if (mod === 'insured' && wasWrong && charged === 0) {
		flashTwistCue(`${info.name} · first wrong letter free`);
		return;
	}
	// Pricing Twists: only when the Twist actually made this letter cheaper.
	const pricing = ['discount', 'flat_rate', 'vowel_vision', 'consonant_sale'];
	if (pricing.includes(mod) && charged > 0 && base > charged) {
		flashTwistCue(`${info.name} · saved $${(base - charged).toLocaleString()}`);
	}
}

/**
 * confirmPurchaseDaily
 * Commit a pending letter/hint/extra-guess purchase via the server.
 * @param {GameState} state
 */
async function confirmPurchaseDaily(state) {
	const purchase = state.selectedPurchase;
	if (!purchase || dailyInFlight) return;
	const letter = purchase.type === 'letter' ? String(purchase.value ?? '').toUpperCase() : null;
	const prevBankroll = state.bankroll ?? 0;
	const prevWrong = (state.incorrectLetters || []).length;
	const mod = state.modifier;
	dailyInFlight = true;
	try {
		let board = null;
		if (purchase.type === 'letter') {
			board = await dailyBuyLetter(purchase.value ?? '');
		} else if (purchase.type === 'hint') {
			// Daily has no personal power-ups — Reveal always costs $150 (fair for all).
			board = await dailyReveal();
		}

		if (board) {
			reconcileDailyBoard(board);
			if (letter) detectDailyBuyCue(letter, prevBankroll, prevWrong, mod);
		} else {
			gameStore.update((s) => ({ ...s, selectedPurchase: null, gameState: 'default' }));
		}
	} finally {
		dailyInFlight = false;
	}
}

/**
 * submitGuessDaily
 * Send the filled blanks to the server, which reveals correct letters and
 * decides win/loss. Daily wager is 0, so bankroll is unaffected by a guess.
 * @param {GameState} state
 */
async function submitGuessDaily(state) {
	if (state.gameState !== 'guess_mode' || dailyInFlight) return;
	/** @type {Record<string, string>} */
	const guess = {};
	for (const [k, v] of Object.entries(state.guessedLetters || {}))
		guess[k] = /** @type {string} */ (v);
	if (Object.keys(guess).length === 0) return;

	dailyInFlight = true;
	try {
		const board = await dailySubmitGuess(guess);
		if (board) reconcileDailyBoard(board);
	} finally {
		dailyInFlight = false;
	}
}

/** Fold (give up) today's Daily — marks it lost, reveals the answer. */
export async function dailyFold() {
	if (dailyInFlight) return;
	dailyInFlight = true;
	try {
		const board = await dailyFoldRpc();
		if (board) reconcileDailyBoard(board);
	} finally {
		dailyInFlight = false;
	}
}

/** Fold (forfeit) the current Challenge puzzle — advances without a solve. */
export async function matchFold() {
	if (!activeMatchId || dailyInFlight) return;
	dailyInFlight = true;
	try {
		const board = await matchFoldRpc(activeMatchId);
		if (board) reconcileMatchBoard(board);
	} finally {
		dailyInFlight = false;
	}
}

/* ================================
   Purchase Mode Functions
=================================== */

/**
 * selectLetter
 * Selects or deselects a letter for purchase.
 *
 * @param {string} letter - The letter to select.
 */
export function selectLetter(letter) {
	gameStore.update(
		/** @param {GameState} state */ (state) => {
			// Cash Game scales letter cost by the tier stake multiplier, and spends the ONE shared
			// balance (banked run money + this puzzle's budget); server matches both.
			const isClimb = state.gameMode === 'climb';
			const climbMult = isClimb ? Number(state.climbInfo?.stake ?? 1) || 1 : 1;
			// 🏧 Overdrive armed → the next letter is free (any letter), even with an empty budget.
			const overdrive = isClimb && (state.climbInfo?.equipped ?? []).includes('overdrive');
			const cost = overdrive ? 0 : (LETTER_COSTS[letter] || 0) * climbMult;
			const affordPool = isClimb
				? Number(state.climbInfo?.budget_left ?? 0)
				: state.bankroll;
			if (affordPool < cost) {
				console.log(`Insufficient funds to purchase letter ${letter}`);
				return state;
			}
			// Deselect if already selected
			if (
				state.selectedPurchase &&
				state.selectedPurchase.type === 'letter' &&
				state.selectedPurchase.value === letter
			) {
				console.log(`Deselecting letter: ${letter}`);
				return { ...state, selectedPurchase: null, gameState: 'default' };
			}
			// Prevent selection if letter is locked or marked incorrect
			if (
				(state.lockedLetters && state.lockedLetters[letter]) ||
				state.incorrectLetters.includes(letter)
			) {
				console.log(`Letter ${letter} is fully locked or marked incorrect.`);
				return state;
			}
			console.log(`Selecting letter: ${letter}`);
			return {
				...state,
				gameState: 'purchase_pending',
				selectedPurchase: { type: 'letter', value: letter }
			};
		}
	);
}

/**
 * selectHint
 * Toggles hint selection for purchase.
 */
export function selectHint() {
	gameStore.update((state) => {
		if (state.selectedPurchase && state.selectedPurchase.type === 'hint') {
			console.log('Deselecting hint');
			return { ...state, selectedPurchase: null, gameState: 'default' };
		}
		console.log('Selecting hint');
		return {
			...state,
			gameState: 'purchase_pending',
			selectedPurchase: { type: 'hint' }
		};
	});
}

// src/lib/stores/GameStore.js

// src/lib/stores/GameStore.js

/**
 * confirmPurchase
 * Handles purchase of a letter or hint and updates game state.
 */
export function confirmPurchase() {
	// All modes are server-authoritative: commit via RPC and reconcile.
	const current = get(gameStore);
	if (current.gameMode === 'daily') confirmPurchaseDaily(current);
	else if (current.gameMode === 'makeup') confirmPurchaseMakeup(current);
	else if (current.gameMode === 'climb') confirmPurchaseClimb(current);
	else if (current.gameMode === 'match') confirmPurchaseMatch(current);
	else if (current.gameMode === 'freeplay') confirmPurchaseFreeplay(current);
}
/* ================================
   Guess Mode Functions
=============================================== */

/**
 * enterGuessMode
 * Toggles between default mode and guess mode.
 */
export function enterGuessMode() {
	gameStore.update((state) => {
		if (state.gameState === 'guess_mode') {
			console.log('Exiting guess mode.');
			return { ...state, gameState: 'default', guessedLetters: {} };
		}
		console.log('Entering guess mode.');
		return { ...state, gameState: 'guess_mode', selectedPurchase: null, guessedLetters: {} };
	});
}

/**
 * getEditableIndices
 * Returns indices in the phrase that are editable (non-space and not already purchased).
 *
 * @param {GameState} state - The current game state.
 * @returns {number[]} Array of editable indices.
 */
function getEditableIndices(state) {
	const indices = [];
	for (let i = 0; i < state.currentPhrase.length; i++) {
		if (state.currentPhrase[i] === ' ') continue;
		if (state.purchasedLetters[i] === state.currentPhrase[i]) continue;
		indices.push(i);
	}
	return indices;
}

/**
 * inputGuessLetter
 * Inserts a guessed letter into the next available slot.
 *
 * @param {string} letter - The guessed letter.
 */
export function inputGuessLetter(letter) {
	gameStore.update((state) => {
		if (state.gameState !== 'guess_mode') return state;
		if (state.lockedLetters && state.lockedLetters[letter]) {
			console.log('Letter already fully locked; ignoring input in guess mode.');
			return state;
		}
		const editableIndices = getEditableIndices(state);
		if (editableIndices.length === 0) return state;

		// Find the first empty slot; if all filled, overwrite the last slot.
		let activeIndex = editableIndices.find((idx) => !Object.hasOwn(state.guessedLetters, idx));
		if (activeIndex === undefined) {
			activeIndex = editableIndices[editableIndices.length - 1];
		}
		const newGuessed = { ...state.guessedLetters, [activeIndex]: letter };
		console.log(`Input letter ${letter} at index ${activeIndex}.`, newGuessed);
		return { ...state, guessedLetters: newGuessed };
	});
}

/**
 * deleteGuessLetter
 * Removes the last entered guessed letter.
 */
export function deleteGuessLetter() {
	gameStore.update((state) => {
		if (state.gameState !== 'guess_mode') return state;
		const editableIndices = getEditableIndices(state);
		if (editableIndices.length === 0) return state;

		// Remove the last filled slot
		let activeIndex = null;
		for (let i = editableIndices.length - 1; i >= 0; i--) {
			if (state.guessedLetters[editableIndices[i]]) {
				activeIndex = editableIndices[i];
				break;
			}
		}
		if (activeIndex === null) return state;
		const newGuessed = { ...state.guessedLetters };
		delete newGuessed[activeIndex];
		console.log(`Deleted letter at index ${activeIndex}.`, newGuessed);
		return { ...state, guessedLetters: newGuessed };
	});
}

/**
 * submitGuess
 * Routes the full guess to the server, which validates and scores.
 */
export function submitGuess() {
	// All modes are server-authoritative: the server validates + scores.
	const current = get(gameStore);
	if (current.gameMode === 'daily') submitGuessDaily(current);
	else if (current.gameMode === 'makeup') submitGuessMakeup(current);
	else if (current.gameMode === 'climb') submitGuessClimb(current);
	else if (current.gameMode === 'match') submitGuessMatch(current);
	else if (current.gameMode === 'freeplay') submitGuessFreeplay(current);
}
/* ================================
   Puzzle Fetch Functions
=================================== */

/**
 * fetchDailyGame - Starts or resumes today's server-authoritative daily session.
 * The phrase is held server-side; the client only ever receives a masked board.
 * No localStorage: the server is the source of truth (and prevents replays).
 * The day's shared modifier is applied server-side at start (no client power-ups).
 */
/** Use today's Daily Twist power-up (applies effect, bounty → ×1.0). */
export async function useDailyTwist() {
	try {
		const board = await dailyUseTwist();
		if (board) {
			reconcileDailyBoard(board);
			return true;
		}
		return false;
	} catch (err) {
		console.error('❌ Error using daily twist:', err instanceof Error ? err.message : String(err));
		return false;
	}
}

/** Spend an owned Interest Boost on today's Daily (bumps the deposit multiplier). */
/** @param {string} id */
export async function useDailyBoost(id) {
	try {
		const board = await dailyUseBoost(id);
		if (board) {
			reconcileDailyBoard(board);
			return true;
		}
		return false;
	} catch (err) {
		console.error('❌ Error using daily boost:', err instanceof Error ? err.message : String(err));
		return false;
	}
}

export async function fetchDailyGame() {
	try {
		track('daily_start');
		const board = await dailyStart([]);
		if (!board) {
			console.error('❌ daily_start returned no board');
			return false;
		}
		reconcileDailyBoard(board); // sets modifier / twistActive / bountyMult from the board
		// Attendance reward (paid once on the first open of the day) → transient toast.
		const ab = /** @type {any} */ (board);
		if (ab.attendance != null && ab.attendance > 0) {
			gameStore.update((s) => ({
				...s,
				cashToast: {
					amount: ab.attendance,
					label: `Day ${ab.attendance_day} streak · for showing up`
				}
			}));
		}
		// 🎰 Fresh open (first time today, board still active) → play the opening reveal.
		if (ab.state === 'active' && ab.attendance != null && ab.attendance > 0) {
			gameStore.update((s) => ({ ...s, dailyIntro: (s.dailyIntro || 0) + 1 }));
			// Auto-reveal Twists (head_start / free_vowel) pre-fill letters at open — explain why.
			// The UI holds this until the board is interactive (past the intro / How-to-win card).
			const mod = ab.modifier;
			if (mod === 'head_start' || mod === 'free_vowel') {
				const info = MODIFIERS[mod];
				if (info) flashTwistCue(`${info.name} · ${info.blurb.toLowerCase()}`);
			}
		}
		try {
			const clue = await getDailyClue();
			gameStore.update((s) => ({ ...s, clue }));
		} catch {
			/* non-fatal */
		}
		console.log('✅ Daily session started/resumed');
		return true;
	} catch (err) {
		console.error(
			'❌ Error starting daily game:',
			err instanceof Error ? err.message : String(err)
		);
		return false;
	}
}
