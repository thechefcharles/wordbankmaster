// src/lib/stores/GameStore.js

import { writable, get } from 'svelte/store';
import { fx } from '$lib/sound.js';
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
	createChallenge,
	acceptChallenge,
	getChallengeBoard,
	challengeBuyLetter,
	challengeReveal,
	challengeSubmitGuess,
	challengeCheck
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
	climbSkip,
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
	matchFold as matchFoldRpc,
	matchCheck,
	matchUsePowerup,
	matchSabotage
} from '$lib/stores/statsStore.js';
import {
	blitzStart,
	blitzBuyLetter,
	blitzSubmitGuess,
	blitzSkip,
	blitzEnd
} from '$lib/stores/statsStore.js';
import { track } from '$lib/analytics.js';

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
 *   clue?: string | null,
 *   challengeInfo?: any,
 *   makeupDate?: string | null,
 *   dailyResult?: any,
 *   climbInfo?: any,
 *   blitzInfo?: any,
 *   matchInfo?: any,
 *   cashToast?: { amount:number, label:string } | null,
 *   dailyLive?: { remaining:number, mult:number, winnings:number } | null,
 *   dailyIntro?: number,
 *   dailyIntroGo?: number,
 *   dailyIntroPlayed?: number
 * }} GameState
 */

/* ================================
   Constants & Store Initialization
=================================== */

// Letter purchase costs
/** @type {Record<string, number>} */
// Mirror of server public.letter_cost() (economy v3.2: −25%, cheapest $20).
export const LETTER_COSTS = {
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
		gameMode: 'daily', // 'daily' | 'climb' | 'challenge' | 'match' | 'makeup'
		freeReveals: 0, // owned Free Reveal power-ups (daily)
		modifier: null, // today's Daily Twist power-up id (daily only)
		twistUsed: false, // have you used today's Twist? (unused → ×1.5 bounty)
		bountyMult: 1, // bounty multiplier (1.0 once Twist used, else 1.5)
		wrongGuesses: 0, // wrong phrase guesses this Daily (each −0.2× mult, floor 1.0)
		clue: null, // witty one-line hint for the current puzzle
		challengeInfo: null, // { mode, started_at, limit_seconds, play_state, score } for the active challenge
		makeupDate: null, // YYYY-MM-DD of the make-up day being played (makeup mode only)
		climbInfo: null, // { bounty, heat, spent, position, bust_risk, wrong_penalty, last_gain, state } (climb mode)
		blitzInfo: null, // { remaining_ms, combo, solved, winnings, tier, buy_in, base, state } (blitz mode)
		matchInfo: null, // { position, pack_size, total_score, last_score, done, status } (challenge match)
		cashToast: null, // { amount, label } — transient Cash-earned toast (attendance / free-play reward)
		dailyLive: null, // { remaining, mult, winnings } — live Daily V2 HUD (Prize left → what you'd bank)
		dailyIntro: 0, // bumps on a FRESH daily open → ARMS the opening reveal (pending)
		dailyIntroGo: 0, // bumps once the board is actually visible → PLAYS the opening reveal
		dailyIntroPlayed: 0 // the dailyIntro token that has already played (persists across remounts)
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
				board.wrong_guesses !== undefined ? board.wrong_guesses : (prev.wrongGuesses ?? 0)
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

/* ===== Challenges (friend wager; same puzzle, score = leftover bankroll) ===== */
/** @type {string|null} */
let activeChallengeId = null;

/** @param {any} board */
function reconcileChallengeBoard(board) {
	if (!board) return;
	const prev = get(gameStore);
	const finished = board.state !== 'active';
	gameStore.set(
		/** @type {GameState} */ ({
			...prev,
			...boardToState(board, prev),
			gameMode: 'challenge',
			gameState: finished ? board.state : 'default',
			modifier: null,
			challengeInfo: board.challenge ?? prev.challengeInfo ?? null
		})
	);
	if (board.state === 'won') {
		setTimeout(() => launchConfetti(), 300);
		fx('win');
	} else if (finished) fx('bust');
	else playMoveCue(prev, board);
}

/** Start playing a challenge created/accepted elsewhere. @param {any} resp @returns {boolean} */
export function enterChallenge(resp) {
	if (!resp?.ok || !resp.board) return false;
	activeChallengeId = resp.challenge_id;
	reconcileChallengeBoard(resp.board);
	return true;
}

/** Create a challenge and drop into play. @param {string} code @param {string} category @param {number} wager @param {string} [mode] */
export async function startChallenge(code, category, wager, mode = 'score') {
	const resp = await createChallenge(code, category, wager, mode);
	if (resp?.ok) {
		track('challenge_create', { wager, mode });
		return enterChallenge(resp) ? resp : { ok: false, reason: 'board' };
	}
	return resp;
}

/** Accept an incoming challenge and drop into play. @param {string} id */
export async function acceptAndPlayChallenge(id) {
	const resp = await acceptChallenge(id);
	if (resp?.ok) {
		track('challenge_accept');
		return enterChallenge(resp) ? resp : { ok: false, reason: 'board' };
	}
	return resp;
}

/** Resume a challenge I've already started. @param {string} id */
export async function resumeChallenge(id) {
	const board = await getChallengeBoard(id);
	if (board) {
		activeChallengeId = id;
		reconcileChallengeBoard(board);
		return true;
	}
	return false;
}

/** Pressure mode: force the server to settle the active play when the clock expires. */
export async function challengeTimeoutCheck() {
	if (!activeChallengeId) return;
	const board = await challengeCheck(activeChallengeId);
	if (board) reconcileChallengeBoard(board);
}

/** @param {GameState} state */
async function confirmPurchaseChallenge(state) {
	const purchase = state.selectedPurchase;
	if (!purchase || dailyInFlight || !activeChallengeId) return;
	dailyInFlight = true;
	try {
		let board = null;
		if (purchase.type === 'letter')
			board = await challengeBuyLetter(activeChallengeId, purchase.value ?? '');
		else if (purchase.type === 'hint') board = await challengeReveal(activeChallengeId);
		if (board) reconcileChallengeBoard(board);
		else gameStore.update((s) => ({ ...s, selectedPurchase: null, gameState: 'default' }));
	} finally {
		dailyInFlight = false;
	}
}

/** @param {GameState} state */
async function submitGuessChallenge(state) {
	if (state.gameState !== 'guess_mode' || dailyInFlight || !activeChallengeId) return;
	/** @type {Record<string, string>} */
	const guess = {};
	for (const [k, v] of Object.entries(state.guessedLetters || {}))
		guess[k] = /** @type {string} */ (v);
	if (Object.keys(guess).length === 0) return;
	dailyInFlight = true;
	try {
		const board = await challengeSubmitGuess(activeChallengeId, guess);
		if (board) reconcileChallengeBoard(board);
	} finally {
		dailyInFlight = false;
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

/** @param {any} board */
function reconcileClimbBoard(board) {
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
			climbInfo: climb
		})
	);
	// No confetti — the slot-machine reveal (box-by-box win pop) is the celebration, like Daily.
	if (busted) fx('bust');
	else if (solved) {
		fx('win');
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
		maybeArmClimbIntro();
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
		const board = await climbSubmitGuess(guess);
		if (board) reconcileClimbBoard(board);
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

/** Leave the Cash Game (clears heat; position + Cash persist). */
export async function climbLeaveGame() {
	try {
		await climbLeave();
	} catch {
		/* non-fatal */
	}
}

/** Skip the current Cash Game puzzle for a fresh one (resets heat to ×1.0). */
export async function climbSkipPuzzle() {
	if (dailyInFlight) return;
	dailyInFlight = true;
	try {
		const board = await climbSkip();
		if (board) {
			reconcileClimbBoard(board);
			maybeArmClimbIntro();
			await refreshClimbClue();
		}
	} finally {
		dailyInFlight = false;
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

/* ===== Blitz (timed speed run) ===== */
/** @param {any} resp */
function reconcileBlitzBoard(resp) {
	if (!resp) return;
	const prev = get(gameStore);
	const blitz = resp.blitz || {};
	const ended = blitz.state === 'ended';
	if (ended) {
		gameStore.update((s) => ({ ...s, gameMode: 'blitz', gameState: 'lost', blitzInfo: blitz }));
		fx('bust');
		return;
	}
	gameStore.set(
		/** @type {GameState} */ ({
			...prev,
			...boardToState(resp, prev),
			gameMode: 'blitz',
			gameState: 'default',
			modifier: null,
			blitzInfo: blitz
		})
	);
	playMoveCue(prev, resp);
}

/** Buy in at a tier and start a timed run. @param {string} tier @returns {Promise<any>} */
export async function startBlitz(tier) {
	try {
		track('blitz_start', { tier });
		const resp = await blitzStart(tier);
		if (!resp?.ok) return resp || { ok: false };
		reconcileBlitzBoard(resp);
		return resp;
	} catch (err) {
		console.error('❌ Error starting Blitz:', err instanceof Error ? err.message : String(err));
		return { ok: false };
	}
}

/** @param {GameState} state */
async function confirmPurchaseBlitz(state) {
	const purchase = state.selectedPurchase;
	if (!purchase || dailyInFlight) return;
	dailyInFlight = true;
	try {
		let resp = null;
		if (purchase.type === 'letter') resp = await blitzBuyLetter(purchase.value ?? '');
		if (resp) reconcileBlitzBoard(resp);
		else gameStore.update((s) => ({ ...s, selectedPurchase: null, gameState: 'default' }));
	} finally {
		dailyInFlight = false;
	}
}

/** @param {GameState} state */
async function submitGuessBlitz(state) {
	if (state.gameState !== 'guess_mode' || dailyInFlight) return;
	/** @type {Record<string, string>} */
	const guess = {};
	for (const [k, v] of Object.entries(state.guessedLetters || {}))
		guess[k] = /** @type {string} */ (v);
	if (Object.keys(guess).length === 0) return;
	dailyInFlight = true;
	try {
		const resp = await blitzSubmitGuess(guess);
		if (resp) reconcileBlitzBoard(resp);
	} finally {
		dailyInFlight = false;
	}
}

/** Skip the current Blitz puzzle (combo resets, −3s). */
export async function blitzSkipPuzzle() {
	if (dailyInFlight) return;
	dailyInFlight = true;
	try {
		const resp = await blitzSkip();
		if (resp) reconcileBlitzBoard(resp);
	} finally {
		dailyInFlight = false;
	}
}

/** End the run when the clock hits 0 → bank winnings, show the result. */
export async function endBlitz() {
	try {
		const resp = await blitzEnd();
		reconcileBlitzBoard(resp);
		return resp?.blitz ?? null;
	} catch (err) {
		console.error('❌ Error ending Blitz:', err instanceof Error ? err.message : String(err));
		return null;
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
			matchInfo: { ...match, id: activeMatchId, standing: board.standing ?? null }
		})
	);
	if (done) {
		setTimeout(() => launchConfetti(), 250);
		fx('win');
	}
	// Celebrate EACH solved puzzle — but only on an in-session advance (prev.matchInfo
	// exists), so opening/resuming a match never fires the winner fireworks.
	else if (
		prev.matchInfo &&
		(match.last_score ?? 0) > 0 &&
		(match.position ?? 1) > (prev.matchInfo.position ?? 0)
	) {
		setTimeout(() => launchConfetti(), 250);
		fx('win');
		maybeArmMatchIntro(); // next puzzle in the pack gets the dramatic opening reveal
	} else playMoveCue(prev, board);
}

/** Create a match and drop into play. @param {any} opts @returns {Promise<any>} */
export async function startMatch(opts) {
	const resp = await createMatch(opts);
	if (resp?.ok && resp.match) {
		track('match_create', { wager: opts.wager ?? 0, pack: opts.pack_size ?? 1 });
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
	} finally {
		dailyInFlight = false;
	}
}

/** Accept (escrow) an invited match and start playing. @param {string} id @param {boolean} [reduced] stake only what you have @returns {Promise<boolean>} */
export async function acceptAndPlayMatch(id, reduced = false) {
	const resp = await acceptMatch(id, reduced);
	if (!resp?.ok) return false;
	track('match_accept');
	activeMatchId = id;
	const board = await matchStart(id);
	if (board) {
		reconcileMatchBoard(board);
		maybeArmMatchIntro();
	}
	return true;
}

/** Blitz: force the server to lock the score when the clock expires. */
export async function matchTimeoutCheck() {
	if (!activeMatchId) return;
	const board = await matchCheck(activeMatchId);
	if (board) reconcileMatchBoard(board);
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

/**
 * confirmPurchaseDaily
 * Commit a pending letter/hint/extra-guess purchase via the server.
 * @param {GameState} state
 */
async function confirmPurchaseDaily(state) {
	const purchase = state.selectedPurchase;
	if (!purchase || dailyInFlight) return;
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
			const cost = LETTER_COSTS[letter] || 0;
			if (state.bankroll < cost) {
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
	else if (current.gameMode === 'challenge') confirmPurchaseChallenge(current);
	else if (current.gameMode === 'makeup') confirmPurchaseMakeup(current);
	else if (current.gameMode === 'climb') confirmPurchaseClimb(current);
	else if (current.gameMode === 'blitz') confirmPurchaseBlitz(current);
	else if (current.gameMode === 'match') confirmPurchaseMatch(current);
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
	else if (current.gameMode === 'challenge') submitGuessChallenge(current);
	else if (current.gameMode === 'makeup') submitGuessMakeup(current);
	else if (current.gameMode === 'climb') submitGuessClimb(current);
	else if (current.gameMode === 'blitz') submitGuessBlitz(current);
	else if (current.gameMode === 'match') submitGuessMatch(current);
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

/** Spend an owned Bounty Boost on today's Daily (bumps the bounty multiplier). */
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
