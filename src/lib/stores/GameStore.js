// src/lib/stores/GameStore.js

import { writable, get } from 'svelte/store';
import confetti from 'canvas-confetti';
import { fx } from '$lib/sound.js';
import { dailyStart, dailyBuyLetter, dailyReveal, dailySubmitGuess, getUserPowerups, dailyUseFreeReveal } from '$lib/stores/statsStore.js';
import { arcadeStart, arcadeBuyLetter, arcadeReveal, arcadeSubmitGuess, arcadeNext } from '$lib/stores/statsStore.js';

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
 *   arcadeRun?: any
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
  arcadeRun: null // arcade gauntlet run state { state, banked, multiplier, position, total, furthest, last_gain }
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
    gameState: finished ? board.state : 'default'
  }));
  if (board.state === 'won') { setTimeout(() => launchConfetti(), 300); fx('win'); }
  else if (finished) fx('bust');
  else playMoveCue(prev, board);
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
  // Per-puzzle outcome drives gameState: solved/complete -> won, busted -> lost.
  let gs = 'default';
  if (run.state === 'solved' || run.state === 'complete') gs = 'won';
  else if (run.state === 'busted') gs = 'lost';
  gameStore.set(/** @type {GameState} */ ({
    ...prev, ...boardToState(board, prev),
    gameMode: 'arcade',
    gameState: gs,
    arcadeRun: run,
    freeReveals: 0
  }));
  if (run.state === 'solved' || run.state === 'complete') {
    setTimeout(() => launchConfetti(), 300);
    fx('win');
    if ((run.last_gain || 0) > 0) setTimeout(() => fx('multiplier'), 240);
  } else if (run.state === 'busted') {
    fx('bust');
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

/** Start or resume today's arcade gauntlet. */
export async function fetchArcadeGame() {
  try {
    const resp = await arcadeStart();
    if (!resp) { console.error('❌ arcade_start returned nothing'); return false; }
    reconcileArcadeBoard(resp);
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
    if (resp) reconcileArcadeBoard(resp);
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
    let usedFree = false;
    if (purchase.type === 'letter') {
      board = await dailyBuyLetter(purchase.value ?? '');
    } else if (purchase.type === 'hint') {
      // Reveal uses a Free Reveal power-up if you own one; otherwise it costs $150.
      if ((state.freeReveals || 0) > 0) { board = await dailyUseFreeReveal(); usedFree = true; }
      else board = await dailyReveal();
    }

    if (board) {
      reconcileDailyBoard(board);
      if (usedFree) gameStore.update(s => ({ ...s, freeReveals: Math.max(0, (s.freeReveals || 0) - 1) }));
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
  // Daily & arcade are both server-authoritative: commit via RPC and reconcile.
  const current = get(gameStore);
  if (current.gameMode === 'daily') confirmPurchaseDaily(current);
  else if (current.gameMode === 'arcade') confirmPurchaseArcade(current);
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
  // Daily & arcade are both server-authoritative: the server validates + scores.
  const current = get(gameStore);
  if (current.gameMode === 'daily') submitGuessDaily(current);
  else if (current.gameMode === 'arcade') submitGuessArcade(current);
}
/* ================================
   Puzzle Fetch Functions
=================================== */

/**
 * fetchDailyGame - Starts or resumes today's server-authoritative daily session.
 * The phrase is held server-side; the client only ever receives a masked board.
 * No localStorage: the server is the source of truth (and prevents replays).
 */
/**
 * @param {string[]} [powerups] - pre-game power-ups to activate (applied only on a fresh session)
 */
export async function fetchDailyGame(powerups = []) {
  try {
    const board = await dailyStart(powerups);
    if (!board) {
      console.error('❌ daily_start returned no board');
      return false;
    }
    reconcileDailyBoard(board);
    // Load Free Reveal inventory for the in-game button.
    try {
      const pus = await getUserPowerups();
      const fr = pus.find(p => p.powerup === 'free_reveal')?.count ?? 0;
      gameStore.update(s => ({ ...s, freeReveals: fr }));
    } catch { /* non-fatal */ }
    console.log('✅ Daily session started/resumed');
    return true;
  } catch (err) {
    console.error('❌ Error starting daily game:', err instanceof Error ? err.message : String(err));
    return false;
  }
}