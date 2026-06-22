// src/lib/stores/GameStore.js

import { writable, get } from 'svelte/store';
import confetti from 'canvas-confetti';
import { fx } from '$lib/sound.js';
import { dailyStart, dailyBuyLetter, dailyReveal, dailySubmitGuess, getDailyModifier, getDailyClue, getArcadeClue } from '$lib/stores/statsStore.js';
import { arcadeStart, arcadeBuyLetter, arcadeReveal, arcadeSubmitGuess, arcadeNext, arcadeUsePowerup, arcadeCashout } from '$lib/stores/statsStore.js';
import { freeplayStart, freeplayNext, freeplayBuyLetter, freeplayReveal, freeplaySubmitGuess, getFreeplayClue } from '$lib/stores/statsStore.js';
import { createChallenge, acceptChallenge, getChallengeBoard, challengeBuyLetter, challengeReveal, challengeSubmitGuess, challengeCheck } from '$lib/stores/statsStore.js';
import { makeupStart, makeupBuyLetter, makeupReveal, makeupSubmitGuess } from '$lib/stores/statsStore.js';
import { climbStart, climbBuyLetter, climbReveal, climbSubmitGuess, climbNext, climbLeave, getPowerups, buyPowerup, climbUsePowerup } from '$lib/stores/statsStore.js';
import { createMatch, acceptMatch, matchStart, matchBuyLetter, matchReveal, matchSubmitGuess, matchCheck } from '$lib/stores/statsStore.js';
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
 *   arcadeRun?: any,
 *   arcadeCashedOut?: boolean,
 *   modifier?: string | null,
 *   clue?: string | null,
 *   challengeInfo?: any,
 *   makeupDate?: string | null,
 *   dailyResult?: any,
 *   climbInfo?: any,
 *   matchInfo?: any,
 *   cashToast?: { amount:number, label:string } | null,
 *   dailyLive?: { spent:number, clean:boolean, no_vowels:boolean, first_try:boolean, reward:number, net:number } | null
 * }} GameState
 */

/* ================================
   Constants & Store Initialization
=================================== */

// Letter purchase costs
/** @type {Record<string, number>} */
export const LETTER_COSTS = {
  Q: 30, W: 50, E: 140, R: 120, T: 120, Y: 60, U: 80, I: 110, O: 90, P: 80,
  A: 130, S: 120, D: 80, F: 60, G: 70, H: 70, J: 30, K: 50, L: 80,
  Z: 40, X: 40, C: 80, V: 50, B: 60, N: 100, M: 70
};

/** @type {import('svelte/store').Writable<GameState>} */
export const gameStore = writable(/** @type {GameState} */ ({
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
  gameMode: 'daily', // 'daily' | 'arcade'
  freeReveals: 0, // owned Free Reveal power-ups (daily)
  arcadeRun: null, // arcade gauntlet run state { state, banked, multiplier, position, total, furthest, last_gain }
  arcadeCashedOut: false, // true when the last arcade run ended via "Bank it" (vs bust)
  modifier: null, // today's shared Daily Modifier id (daily only)
  clue: null, // witty one-line hint for the current puzzle
  challengeInfo: null, // { mode, started_at, limit_seconds, play_state, score } for the active challenge
  makeupDate: null, // YYYY-MM-DD of the make-up day being played (makeup mode only)
  climbInfo: null, // { bounty, heat, attempts, spent, position, stuck, last_gain, state } (climb mode)
  matchInfo: null, // { position, pack_size, total_score, last_score, done, status } (challenge match)
  cashToast: null, // { amount, label } — transient Cash-earned toast (attendance / free-play reward)
  dailyLive: null // { spent, clean, no_vowels, first_try, reward, net } — live Daily HUD metrics
}));

/* ================================
   Utility Functions
=================================== */

/**
 * launchConfetti
 * Triggers a celebratory confetti animation.
 */
function launchConfetti() {
  const colors = ['#34d399', '#a3e635', '#fcd34d', '#ffffff'];
  /** @param {number} particleCount @param {object} opts */
  const fire = (particleCount, opts) => confetti({ particleCount, colors, disableForReducedMotion: true, ...opts });
  fire(90, { spread: 75, startVelocity: 55, origin: { y: 0.62 } });
  fire(55, { spread: 110, decay: 0.92, scalar: 1.25, origin: { y: 0.6 } });
  setTimeout(() => fire(65, { spread: 120, startVelocity: 48, angle: 60, origin: { x: 0.15, y: 0.65 } }), 160);
  setTimeout(() => fire(65, { spread: 120, startVelocity: 48, angle: 120, origin: { x: 0.85, y: 0.65 } }), 300);
}

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
 * boardToState — shared masked-board → gameStore partial (used by daily + arcade).
 * @param {any} board @param {GameState} prev
 */
function boardToState(board, prev) {
  /** @type {number[]} */
  const wordLengths = board.word_lengths || [];
  const chars = wordLengths.map((/** @type {number} */ len) => '#'.repeat(len)).join(' ').split('');
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
  const currentPhrase = finished && board.phrase ? String(board.phrase).toUpperCase() : chars.join('');
  /** @type {Record<string, boolean>} */
  const lockedLetters = {};
  (board.locked_letters || []).forEach((/** @type {string} */ l) => { lockedLetters[l] = true; });
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
  gameStore.set(/** @type {GameState} */ ({
    ...prev, ...boardToState(board, prev),
    gameMode: 'daily',
    gameState: finished ? board.state : 'default',
    dailyResult: board.daily_result ?? prev.dailyResult ?? null,
    dailyLive: board.live ?? prev.dailyLive ?? null
  }));
  if (board.state === 'won') { setTimeout(() => launchConfetti(), 300); fx('win'); }
  else if (finished) fx('bust');
  else playMoveCue(prev, board);
  // analytics: fire once, on the transition into a finished daily
  if (finished && prev.gameState !== 'won' && prev.gameState !== 'lost') {
    track('daily_result', { won: board.state === 'won', bankroll: board.bankroll ?? 0 });
  }
}

/**
 * reconcileArcadeBoard — arcade gauntlet { board, run } → gameStore.
 * @param {any} resp
 */
function reconcileArcadeBoard(resp) {
  if (!resp || !resp.board) return;
  const prev = get(gameStore);
  const board = resp.board;
  const run = resp.run || {};
  // Rolling-survival outcome: solved -> won (continue), over -> lost (run ends).
  let gs = 'default';
  if (run.state === 'solved') gs = 'won';
  else if (run.state === 'over') gs = 'lost';
  gameStore.set(/** @type {GameState} */ ({
    ...prev, ...boardToState(board, prev),
    gameMode: 'arcade',
    gameState: gs,
    arcadeRun: run,
    arcadeCashedOut: false,
    freeReveals: 0,
    modifier: null
  }));
  if (run.state === 'solved') {
    setTimeout(() => launchConfetti(), 300);
    fx('win');
    if ((run.last_gain || 0) > 0) setTimeout(() => fx('multiplier'), 240);
    if (prev.gameState !== 'won') track('arcade_solve', { position: run.position ?? 0, payout: run.last_gain ?? 0, earned: run.last_earn ?? null });
  } else if (run.state === 'over') {
    fx('bust');
    if (prev.gameState !== 'lost') track('arcade_over', { peak: run.banked ?? 0, solved: run.furthest ?? 0 });
  } else {
    playMoveCue(prev, board);
  }
}

/** confirmPurchaseArcade — commit a letter/reveal on the current gauntlet puzzle. @param {GameState} state */
async function confirmPurchaseArcade(state) {
  const purchase = state.selectedPurchase;
  if (!purchase || dailyInFlight) return;
  dailyInFlight = true;
  try {
    let resp = null;
    if (purchase.type === 'letter') resp = await arcadeBuyLetter(purchase.value ?? '');
    else if (purchase.type === 'hint') resp = await arcadeReveal();
    if (resp) reconcileArcadeBoard(resp);
    else gameStore.update(s => ({ ...s, selectedPurchase: null, gameState: 'default' }));
  } finally {
    dailyInFlight = false;
  }
}

/** submitGuessArcade — submit a guess on the current gauntlet puzzle. @param {GameState} state */
async function submitGuessArcade(state) {
  if (state.gameState !== 'guess_mode' || dailyInFlight) return;
  /** @type {Record<string, string>} */
  const guess = {};
  for (const [k, v] of Object.entries(state.guessedLetters || {})) guess[k] = /** @type {string} */ (v);
  if (Object.keys(guess).length === 0) return;
  dailyInFlight = true;
  try {
    const resp = await arcadeSubmitGuess(guess);
    if (resp) reconcileArcadeBoard(resp);
  } finally {
    dailyInFlight = false;
  }
}

/** Refresh the clue for the current arcade puzzle (changes each rung). */
async function refreshArcadeClue() {
  try {
    const clue = await getArcadeClue();
    gameStore.update(s => ({ ...s, clue }));
  } catch { /* non-fatal */ }
}

/** Start or resume today's arcade gauntlet. */
export async function fetchArcadeGame() {
  try {
    track('arcade_start');
    const resp = await arcadeStart();
    if (!resp) { console.error('❌ arcade_start returned nothing'); return false; }
    reconcileArcadeBoard(resp);
    await refreshArcadeClue();
    return true;
  } catch (err) {
    console.error('❌ Error starting arcade:', err instanceof Error ? err.message : String(err));
    return false;
  }
}

/** Advance to the next puzzle after a solve, or retry after a bust. */
export async function arcadeContinue() {
  if (dailyInFlight) return;
  dailyInFlight = true;
  try {
    const resp = await arcadeNext();
    if (resp) { reconcileArcadeBoard(resp); await refreshArcadeClue(); }
  } finally {
    dailyInFlight = false;
  }
}

/* ===== Free Play (unranked, category-picked, endless) ===== */

/** @param {any} board */
function reconcileFreeplayBoard(board) {
  if (!board) return;
  const prev = get(gameStore);
  const finished = board.state !== 'active';
  gameStore.set(/** @type {GameState} */ ({
    ...prev, ...boardToState(board, prev),
    gameMode: 'freeplay',
    gameState: finished ? board.state : 'default',
    modifier: null, arcadeRun: null
  }));
  if (board.state === 'won') {
    setTimeout(() => launchConfetti(), 300); fx('win');
    const rw = /** @type {any} */ (board).freeplay_reward;
    if (rw > 0) gameStore.update(s => ({ ...s, cashToast: { amount: rw, label: 'Free Play reward' } }));
  }
  else if (finished) fx('bust');
  else playMoveCue(prev, board);
}

async function refreshFreeplayClue() {
  try {
    const clue = await getFreeplayClue();
    gameStore.update(s => ({ ...s, clue }));
  } catch { /* non-fatal */ }
}

/** Start Free Play in a category (random puzzle from it). @param {string} category */
export async function fetchFreeplayGame(category) {
  try {
    track('freeplay_start', { category });
    const board = await freeplayStart(category);
    if (!board) { console.error('❌ freeplay_start returned nothing'); return false; }
    reconcileFreeplayBoard(board);
    await refreshFreeplayClue();
    return true;
  } catch (err) {
    console.error('❌ Error starting free play:', err instanceof Error ? err.message : String(err));
    return false;
  }
}

/** Next free-play puzzle in the same category. */
export async function freeplayContinue() {
  if (dailyInFlight) return;
  dailyInFlight = true;
  try {
    const board = await freeplayNext();
    if (board) { reconcileFreeplayBoard(board); await refreshFreeplayClue(); }
  } finally {
    dailyInFlight = false;
  }
}

/** @param {GameState} state */
async function confirmPurchaseFreeplay(state) {
  const purchase = state.selectedPurchase;
  if (!purchase || dailyInFlight) return;
  dailyInFlight = true;
  try {
    let board = null;
    if (purchase.type === 'letter') board = await freeplayBuyLetter(purchase.value ?? '');
    else if (purchase.type === 'hint') board = await freeplayReveal();
    if (board) reconcileFreeplayBoard(board);
    else gameStore.update(s => ({ ...s, selectedPurchase: null, gameState: 'default' }));
  } finally {
    dailyInFlight = false;
  }
}

/** @param {GameState} state */
async function submitGuessFreeplay(state) {
  if (state.gameState !== 'guess_mode' || dailyInFlight) return;
  /** @type {Record<string, string>} */
  const guess = {};
  for (const [k, v] of Object.entries(state.guessedLetters || {})) guess[k] = /** @type {string} */ (v);
  if (Object.keys(guess).length === 0) return;
  dailyInFlight = true;
  try {
    const board = await freeplaySubmitGuess(guess);
    if (board) reconcileFreeplayBoard(board);
  } finally {
    dailyInFlight = false;
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
  gameStore.set(/** @type {GameState} */ ({
    ...prev, ...boardToState(board, prev),
    gameMode: 'challenge',
    gameState: finished ? board.state : 'default',
    modifier: null, arcadeRun: null,
    challengeInfo: board.challenge ?? prev.challengeInfo ?? null
  }));
  if (board.state === 'won') { setTimeout(() => launchConfetti(), 300); fx('win'); }
  else if (finished) fx('bust');
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
  if (resp?.ok) { track('challenge_create', { wager, mode }); return enterChallenge(resp) ? resp : { ok: false, reason: 'board' }; }
  return resp;
}

/** Accept an incoming challenge and drop into play. @param {string} id */
export async function acceptAndPlayChallenge(id) {
  const resp = await acceptChallenge(id);
  if (resp?.ok) { track('challenge_accept'); return enterChallenge(resp) ? resp : { ok: false, reason: 'board' }; }
  return resp;
}

/** Resume a challenge I've already started. @param {string} id */
export async function resumeChallenge(id) {
  const board = await getChallengeBoard(id);
  if (board) { activeChallengeId = id; reconcileChallengeBoard(board); return true; }
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
    if (purchase.type === 'letter') board = await challengeBuyLetter(activeChallengeId, purchase.value ?? '');
    else if (purchase.type === 'hint') board = await challengeReveal(activeChallengeId);
    if (board) reconcileChallengeBoard(board);
    else gameStore.update(s => ({ ...s, selectedPurchase: null, gameState: 'default' }));
  } finally {
    dailyInFlight = false;
  }
}

/** @param {GameState} state */
async function submitGuessChallenge(state) {
  if (state.gameState !== 'guess_mode' || dailyInFlight || !activeChallengeId) return;
  /** @type {Record<string, string>} */
  const guess = {};
  for (const [k, v] of Object.entries(state.guessedLetters || {})) guess[k] = /** @type {string} */ (v);
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
  gameStore.set(/** @type {GameState} */ ({
    ...prev, ...boardToState(board, prev),
    gameMode: 'makeup',
    gameState: finished ? board.state : 'default',
    modifier: null, arcadeRun: null,
    makeupDate: board.makeup?.date ?? prev.makeupDate ?? activeMakeupDate
  }));
  if (board.state === 'won') { setTimeout(() => launchConfetti(), 300); fx('win'); }
  else if (finished) fx('bust');
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
    if (purchase.type === 'letter') board = await makeupBuyLetter(activeMakeupDate, purchase.value ?? '');
    else if (purchase.type === 'hint') board = await makeupReveal(activeMakeupDate);
    if (board) reconcileMakeupBoard(board);
    else gameStore.update(s => ({ ...s, selectedPurchase: null, gameState: 'default' }));
  } finally {
    dailyInFlight = false;
  }
}

/** @param {GameState} state */
async function submitGuessMakeup(state) {
  if (state.gameState !== 'guess_mode' || dailyInFlight || !activeMakeupDate) return;
  /** @type {Record<string, string>} */
  const guess = {};
  for (const [k, v] of Object.entries(state.guessedLetters || {})) guess[k] = /** @type {string} */ (v);
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
/** @param {any} board */
function reconcileClimbBoard(board) {
  if (!board) return;
  const prev = get(gameStore);
  const climb = board.climb || {};
  // 'solved' shows a win beat (then climbAdvance); 'complete' = reached the top.
  const solved = climb.state === 'solved';
  gameStore.set(/** @type {GameState} */ ({
    ...prev, ...boardToState(board, prev),
    gameMode: 'climb',
    gameState: solved ? 'won' : 'default',
    modifier: null, arcadeRun: null,
    climbInfo: climb
  }));
  if (solved) { setTimeout(() => launchConfetti(), 250); fx('win'); }
  else playMoveCue(prev, board);
}

/** Start or resume the Climb. @returns {Promise<boolean>} */
export async function fetchClimbGame() {
  try {
    track('climb_start');
    const board = await climbStart();
    if (!board) return false;
    reconcileClimbBoard(board);
    return true;
  } catch (err) {
    console.error('❌ Error starting climb:', err instanceof Error ? err.message : String(err));
    return false;
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
    else gameStore.update(s => ({ ...s, selectedPurchase: null, gameState: 'default' }));
  } finally {
    dailyInFlight = false;
  }
}

/** @param {GameState} state */
async function submitGuessClimb(state) {
  if (state.gameState !== 'guess_mode' || dailyInFlight) return;
  /** @type {Record<string, string>} */
  const guess = {};
  for (const [k, v] of Object.entries(state.guessedLetters || {})) guess[k] = /** @type {string} */ (v);
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
    if (board) reconcileClimbBoard(board);
  } finally {
    dailyInFlight = false;
  }
}

/** Leave the Cash Game (clears heat; position + Cash persist). */
export async function climbLeaveGame() {
  try { await climbLeave(); } catch { /* non-fatal */ }
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
  gameStore.set(/** @type {GameState} */ ({
    ...prev, ...(done ? {} : boardToState(board, prev)),
    gameMode: 'match',
    gameState: done ? 'won' : 'default',
    modifier: null, arcadeRun: null,
    clue: done ? prev.clue : (board.clue ?? null),
    matchInfo: match
  }));
  if (done) { setTimeout(() => launchConfetti(), 250); fx('win'); }
  else if ((match.last_score ?? 0) > 0 && (match.position ?? 1) > (prev.matchInfo?.position ?? 0)) { fx('win'); }
  else playMoveCue(prev, board);
}

/** Create a match and drop into play. @param {any} opts @returns {Promise<any>} */
export async function startMatch(opts) {
  const resp = await createMatch(opts);
  if (resp?.ok && resp.match) {
    track('match_create', { wager: opts.wager ?? 0, pack: opts.pack_size ?? 1 });
    const id = resp.match.id;
    activeMatchId = id;
    const board = await matchStart(id);
    if (board) reconcileMatchBoard(board);
  }
  return resp;
}

/** Accept (escrow) an invited match and start playing. @param {string} id @returns {Promise<boolean>} */
export async function acceptAndPlayMatch(id) {
  const resp = await acceptMatch(id);
  if (!resp?.ok) return false;
  track('match_accept');
  activeMatchId = id;
  const board = await matchStart(id);
  if (board) reconcileMatchBoard(board);
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
  if (board) { reconcileMatchBoard(board); return true; }
  return false;
}

/** @param {GameState} state */
async function confirmPurchaseMatch(state) {
  const purchase = state.selectedPurchase;
  if (!purchase || dailyInFlight || !activeMatchId) return;
  dailyInFlight = true;
  try {
    let board = null;
    if (purchase.type === 'letter') board = await matchBuyLetter(activeMatchId, purchase.value ?? '');
    else if (purchase.type === 'hint') board = await matchReveal(activeMatchId);
    if (board) reconcileMatchBoard(board);
    else gameStore.update(s => ({ ...s, selectedPurchase: null, gameState: 'default' }));
  } finally {
    dailyInFlight = false;
  }
}

/** @param {GameState} state */
async function submitGuessMatch(state) {
  if (state.gameState !== 'guess_mode' || dailyInFlight || !activeMatchId) return;
  /** @type {Record<string, string>} */
  const guess = {};
  for (const [k, v] of Object.entries(state.guessedLetters || {})) guess[k] = /** @type {string} */ (v);
  if (Object.keys(guess).length === 0) return;
  dailyInFlight = true;
  try {
    const board = await matchSubmitGuess(activeMatchId, guess);
    if (board) reconcileMatchBoard(board);
  } finally {
    dailyInFlight = false;
  }
}

/** Spend an earned power-up during the current arcade run. @param {string} powerup */
export async function useArcadePowerup(powerup) {
  if (dailyInFlight) return;
  dailyInFlight = true;
  try {
    const resp = await arcadeUsePowerup(powerup);
    if (resp) reconcileArcadeBoard(resp);
  } finally {
    dailyInFlight = false;
  }
}

/** Cash out the current arcade run's winnings into your Bank (ends the run). */
export async function arcadeCashOut() {
  if (dailyInFlight) return;
  dailyInFlight = true;
  try {
    const resp = await arcadeCashout();
    if (resp) {
      reconcileArcadeBoard(resp);
      // reconcile cleared the flag; mark this as a cash-out so the modal differs from a bust
      gameStore.update(s => ({ ...s, arcadeCashedOut: true }));
      fx('multiplier');
    }
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
      gameStore.update(s => ({ ...s, selectedPurchase: null, gameState: 'default' }));
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
  for (const [k, v] of Object.entries(state.guessedLetters || {})) guess[k] = /** @type {string} */ (v);
  if (Object.keys(guess).length === 0) return;

  dailyInFlight = true;
  try {
    const board = await dailySubmitGuess(guess);
    if (board) reconcileDailyBoard(board);
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
  gameStore.update(/** @param {GameState} state */ (state) => {
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
      return { ...state, selectedPurchase: null, gameState: "default" };
    }
    // Prevent selection if letter is locked or marked incorrect
    if ((state.lockedLetters && state.lockedLetters[letter]) ||
        state.incorrectLetters.includes(letter)) {
      console.log(`Letter ${letter} is fully locked or marked incorrect.`);
      return state;
    }
    console.log(`Selecting letter: ${letter}`);
    return {
      ...state,
      gameState: "purchase_pending",
      selectedPurchase: { type: 'letter', value: letter }
    };
  });
}

/**
 * selectHint
 * Toggles hint selection for purchase.
 */
export function selectHint() {
  gameStore.update(state => {
    if (state.selectedPurchase && state.selectedPurchase.type === 'hint') {
      console.log("Deselecting hint");
      return { ...state, selectedPurchase: null, gameState: "default" };
    }
    console.log("Selecting hint");
    return {
      ...state,
      gameState: "purchase_pending",
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
  else if (current.gameMode === 'arcade') confirmPurchaseArcade(current);
  else if (current.gameMode === 'freeplay') confirmPurchaseFreeplay(current);
  else if (current.gameMode === 'challenge') confirmPurchaseChallenge(current);
  else if (current.gameMode === 'makeup') confirmPurchaseMakeup(current);
  else if (current.gameMode === 'climb') confirmPurchaseClimb(current);
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
  gameStore.update(state => {
    if (state.gameState === 'guess_mode') {
      console.log("Exiting guess mode.");
      return { ...state, gameState: "default", guessedLetters: {} };
    }
    console.log("Entering guess mode.");
    return { ...state, gameState: "guess_mode", selectedPurchase: null, guessedLetters: {} };
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
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
    if (state.lockedLetters && state.lockedLetters[letter]) {
      console.log("Letter already fully locked; ignoring input in guess mode.");
      return state;
    }
    const editableIndices = getEditableIndices(state);
    if (editableIndices.length === 0) return state;

    // Find the first empty slot; if all filled, overwrite the last slot.
    let activeIndex = editableIndices.find(idx => !Object.hasOwn(state.guessedLetters, idx));
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
  gameStore.update(state => {
    if (state.gameState !== "guess_mode") return state;
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
 * Routes the full guess to the server (daily or arcade), which validates and scores.
 */
export function submitGuess() {
  // All modes are server-authoritative: the server validates + scores.
  const current = get(gameStore);
  if (current.gameMode === 'daily') submitGuessDaily(current);
  else if (current.gameMode === 'arcade') submitGuessArcade(current);
  else if (current.gameMode === 'freeplay') submitGuessFreeplay(current);
  else if (current.gameMode === 'challenge') submitGuessChallenge(current);
  else if (current.gameMode === 'makeup') submitGuessMakeup(current);
  else if (current.gameMode === 'climb') submitGuessClimb(current);
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
export async function fetchDailyGame() {
  try {
    track('daily_start');
    const board = await dailyStart();
    if (!board) {
      console.error('❌ daily_start returned no board');
      return false;
    }
    reconcileDailyBoard(board);
    // Attendance reward (paid once on the first open of the day) → transient toast.
    const ab = /** @type {any} */ (board);
    if (ab.attendance != null && ab.attendance > 0) {
      gameStore.update(s => ({ ...s, cashToast: { amount: ab.attendance, label: `Day ${ab.attendance_day} streak · for showing up` } }));
    }
    // Today's shared modifier (same for everyone) — drives the banner + key pricing.
    try {
      const [mod, clue] = await Promise.all([getDailyModifier(), getDailyClue()]);
      gameStore.update(s => ({ ...s, modifier: mod, clue }));
    } catch { /* non-fatal */ }
    console.log('✅ Daily session started/resumed');
    return true;
  } catch (err) {
    console.error('❌ Error starting daily game:', err instanceof Error ? err.message : String(err));
    return false;
  }
}