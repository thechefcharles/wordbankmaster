# Free Play Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a free, unlimited, points-only practice mode ("Free Play") that reuses the existing game UI, runs entirely on the client (zero server/RPC calls), and is walled off from all money systems.

**Architecture:** A pure client-side engine produces the *same "board" object shape the server RPCs return*, so it flows through the existing `boardToState` → `gameStore` → board/keyboard UI pipeline untouched. Free Play is a new `gameMode: 'freeplay'`; the existing `confirmPurchase()`/`submitGuess()` seams (which already branch by mode) get a freeplay branch that calls the engine instead of an RPC. Lifetime points live in `localStorage`. No auth, no Supabase, no Cash.

**Tech Stack:** SvelteKit 2.16, Svelte (mixed runes + `on:`/`$:`), plain-JS pure engine, Node's built-in `node:test` runner (no new deps).

## Global Constraints

- **No money, ever.** Free Play reads/writes no Cash, credit, loan, bank, or any Supabase table. Points are a device-local cosmetic score only.
- **Zero server calls during Free Play.** All gameplay is synchronous client-side; no `supabase.*`, no `fetch`.
- **Placeholder puzzles are ORIGINAL** — none may be copied from `daily_puzzles` (avoids leaking money-mode answers, since the client holds the phrase).
- **Name is "Free Play"** in all UI copy for now (renamed to "Airplane Mode" only when true-offline ships later).
- **Engine + its tests use RELATIVE imports** (`./x.js`, `../x.js`), never `$lib` aliases, so `node --test` can run them outside Vite.
- **v1 scope:** local points + best run only. No badges, no leaderboard, no heat/streak, no online sync, no "bust"/loss state.
- Gates before every commit that touches `.svelte`/`.ts`: `npx prettier --write <files>` → `npm run check` (baseline: 0 errors, 1 pre-existing a11y warning) → `npm run build`.

---

## File Structure

- `src/lib/letterCosts.js` — **new.** The `{ letter: cost }` map extracted from `GameStore.js` so the engine can import it without pulling in the Svelte store. `GameStore.js` re-imports it (DRY).
- `src/lib/freeplay/puzzles.js` — **new.** ~18 original placeholder puzzles `{ id, phrase, category, clue }`.
- `src/lib/freeplay/engine.js` — **new.** Pure functions: `newGame`, `buyLetter`, `applyGuess`, `toBoard`, `scoreOnSolve`. No I/O.
- `src/lib/freeplay/engine.test.js` — **new.** `node:test` unit tests for the engine.
- `src/lib/freeplay/points.js` — **new.** Device-local lifetime points + best, storage-injectable for tests.
- `src/lib/freeplay/points.test.js` — **new.** `node:test` unit tests for points.
- `src/lib/stores/GameStore.js` — **modify.** Add `freeplay` branch to `confirmPurchase`/`submitGuess`; add `reconcileFreeplayBoard`, `confirmPurchaseFreeplay`, `submitGuessFreeplay`, `startFreePlay`, `freePlayNext`.
- `src/lib/components/Keyboard.svelte` — **modify.** Add `freeplay` branch to `affordPool`.
- `src/routes/+page.svelte` — **modify.** Free Play card in the Play sub-menu; a "Keep playing free →" link on the Cash Game out-of-money banner; a points/next-puzzle affordance on the game screen when `gameMode === 'freeplay'`.

---

## Task 1: Extract the letter-cost map to a shared module

**Files:**
- Create: `src/lib/letterCosts.js`
- Modify: `src/lib/stores/GameStore.js:106-131` (the `export const LETTER_COSTS = {…}` block)

**Interfaces:**
- Produces: `export const LETTER_COSTS: Record<string, number>` (26 uppercase letters → cost), imported by the engine and by `GameStore.js`.

- [ ] **Step 1: Create the shared module** with the exact same values currently in `GameStore.js`:

```js
// src/lib/letterCosts.js
// Buy-a-letter prices, shared by the online modes (via GameStore) and the Free Play
// engine. MUST stay identical to the server's letter_cost() function.
/** @type {Record<string, number>} */
export const LETTER_COSTS = {
	Q: 20, W: 40, E: 100, R: 90, T: 90, Y: 50, U: 60, I: 80, O: 70, P: 60,
	A: 100, S: 90, D: 60, F: 50, G: 50, H: 50, J: 20, K: 40, L: 60,
	Z: 30, X: 30, C: 60, V: 40, B: 50, N: 80, M: 50
};
```

- [ ] **Step 2: Re-export from GameStore** so nothing else breaks. Replace the inline `export const LETTER_COSTS = {…}` block in `src/lib/stores/GameStore.js` with:

```js
import { LETTER_COSTS } from '$lib/letterCosts.js';
export { LETTER_COSTS };
```

(Place the `import` with the other imports at the top of the file; delete the old inline object.)

- [ ] **Step 3: Verify no breakage**

Run: `npx prettier --write src/lib/letterCosts.js src/lib/stores/GameStore.js && npm run check && npm run build`
Expected: 0 errors, 1 warning; build succeeds.

- [ ] **Step 4: Commit**

```bash
git add src/lib/letterCosts.js src/lib/stores/GameStore.js
git commit -m "refactor: extract LETTER_COSTS to a shared module for Free Play reuse"
```

---

## Task 2: Placeholder puzzle pool

**Files:**
- Create: `src/lib/freeplay/puzzles.js`

**Interfaces:**
- Produces: `export const FREEPLAY_PUZZLES: { id:string, phrase:string, category:string, clue:string }[]` — original phrases, uppercase A–Z + spaces only.

- [ ] **Step 1: Create ~18 original placeholder puzzles.** Phrases must be original (not from `daily_puzzles`), UPPERCASE, letters and single spaces only.

```js
// src/lib/freeplay/puzzles.js
// Placeholder Free Play puzzles — ORIGINAL, not drawn from any money-mode pool, because
// the client holds the answer. Swap for a dedicated practice pool later.
/** @type {{ id:string, phrase:string, category:string, clue:string }[]} */
export const FREEPLAY_PUZZLES = [
	{ id: 'fp1', phrase: 'MORNING COFFEE RUN', category: 'Everyday', clue: 'A daily caffeine errand.' },
	{ id: 'fp2', phrase: 'RAINY DAY BLUES', category: 'Moods', clue: 'How a grey sky can feel.' },
	{ id: 'fp3', phrase: 'LOST TV REMOTE', category: 'Household', clue: 'Always in the couch cushions.' },
	{ id: 'fp4', phrase: 'WEEKEND ROAD TRIP', category: 'Travel', clue: 'Two days, one full tank.' },
	{ id: 'fp5', phrase: 'FRESH MOUNTAIN AIR', category: 'Nature', clue: 'What hikers chase.' },
	{ id: 'fp6', phrase: 'MIDNIGHT SNACK ATTACK', category: 'Food', clue: 'The fridge at 2am.' },
	{ id: 'fp7', phrase: 'FIRST DAY JITTERS', category: 'Feelings', clue: 'New job nerves.' },
	{ id: 'fp8', phrase: 'SUNDAY MORNING PANCAKES', category: 'Food', clue: 'A lazy breakfast stack.' },
	{ id: 'fp9', phrase: 'TANGLED HEADPHONE CORD', category: 'Annoyances', clue: 'A pocket knot.' },
	{ id: 'fp10', phrase: 'CITY LIGHTS AT NIGHT', category: 'Scenery', clue: 'A skyline after dark.' },
	{ id: 'fp11', phrase: 'WARM SUMMER BREEZE', category: 'Nature', clue: 'A gentle July gust.' },
	{ id: 'fp12', phrase: 'BURNT TOAST SMELL', category: 'Household', clue: 'Breakfast gone wrong.' },
	{ id: 'fp13', phrase: 'CROWDED TRAIN PLATFORM', category: 'Commute', clue: 'Rush hour scene.' },
	{ id: 'fp14', phrase: 'BRAND NEW SNEAKERS', category: 'Style', clue: 'Fresh out of the box.' },
	{ id: 'fp15', phrase: 'QUIET LIBRARY CORNER', category: 'Places', clue: 'Where you whisper.' },
	{ id: 'fp16', phrase: 'FROZEN WINTER POND', category: 'Nature', clue: 'Skaters welcome.' },
	{ id: 'fp17', phrase: 'FADED CONCERT TICKET', category: 'Keepsakes', clue: 'A ticket-stub memory.' },
	{ id: 'fp18', phrase: 'LATE NIGHT PODCAST', category: 'Media', clue: 'Voices before sleep.' }
];
```

- [ ] **Step 2: Sanity-check the data** with a throwaway node check:

Run: `node -e "import('./src/lib/freeplay/puzzles.js').then(m=>{const bad=m.FREEPLAY_PUZZLES.filter(p=>!/^[A-Z ]+$/.test(p.phrase));console.log('count',m.FREEPLAY_PUZZLES.length,'bad',bad.length);process.exit(bad.length?1:0)})"`
Expected: `count 18 bad 0`

- [ ] **Step 3: Commit**

```bash
git add src/lib/freeplay/puzzles.js
git commit -m "feat(freeplay): original placeholder puzzle pool"
```

---

## Task 3: The Free Play engine (pure, TDD)

**Files:**
- Create: `src/lib/freeplay/engine.js`
- Test: `src/lib/freeplay/engine.test.js`

**Interfaces:**
- Consumes: `LETTER_COSTS` from `../letterCosts.js` (Task 1).
- Produces:
  - `newGame(puzzle: {id,phrase,category,clue}) => State`
  - `buyLetter(state: State, letter: string) => State` (no-op-returns-same-state on unaffordable/repeat/finished)
  - `applyGuess(state: State, filled: Record<number,string>) => State` (marks `won` only on a full correct fill; otherwise unchanged)
  - `scoreOnSolve(state: State) => number` (`budget - spent` when `won`, else `0`)
  - `toBoard(state: State) => Board` — the server-shaped object `boardToState` consumes
  - `State = { puzzleId, phrase, category, clue, budget, spent, revealed:number[], incorrect:string[], status:'active'|'won' }`
  - `Board = { word_lengths, revealed:Record<string,string>, incorrect_letters, locked_letters:[], bankroll, guesses_remaining, category, subcategory:'', clue, state:'active'|'won', phrase?, live:{remaining:number} }`

- [ ] **Step 1: Write the failing tests**

```js
// src/lib/freeplay/engine.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { newGame, buyLetter, applyGuess, scoreOnSolve, toBoard } from './engine.js';

const P = { id: 'x', phrase: 'CAT HAT', category: 'C', clue: 'k' };

test('newGame sets a budget from distinct-letter costs with headroom', () => {
	const s = newGame(P);
	// distinct letters C,A,T,H → 60+100+90+50 = 300; budget = round(1.2*300/10)*10 = 360
	assert.equal(s.budget, 360);
	assert.equal(s.spent, 0);
	assert.equal(s.status, 'active');
	assert.deepEqual(s.revealed, []);
});

test('buyLetter reveals all positions of a present letter and charges it', () => {
	let s = newGame(P); // "CAT HAT", A at indices 1 and 5 (space at 3)
	s = buyLetter(s, 'A');
	assert.deepEqual(s.revealed, [1, 5]);
	assert.equal(s.spent, 100); // A costs 100
	assert.deepEqual(s.incorrect, []);
});

test('buyLetter on an absent letter charges and marks incorrect', () => {
	let s = newGame(P);
	s = buyLetter(s, 'Z'); // not in phrase, costs 30
	assert.equal(s.spent, 30);
	assert.deepEqual(s.incorrect, ['Z']);
	assert.deepEqual(s.revealed, []);
});

test('buyLetter is a no-op when unaffordable or already tried', () => {
	let s = newGame(P);
	s = { ...s, spent: s.budget - 10 }; // only $10 left
	const before = s;
	s = buyLetter(s, 'E'); // E costs 100 > 10 → no-op
	assert.deepEqual(s, before);
	let s2 = buyLetter(newGame(P), 'A');
	assert.deepEqual(buyLetter(s2, 'A'), s2); // repeat → no-op
});

test('applyGuess wins only on a full correct fill', () => {
	let s = newGame(P);
	// wrong fill leaves it active
	s = applyGuess(s, { 0: 'X', 1: 'A', 2: 'T', 4: 'H', 5: 'A', 6: 'T' });
	assert.equal(s.status, 'active');
	// correct fill of every blank → won
	s = applyGuess(s, { 0: 'C', 1: 'A', 2: 'T', 4: 'H', 5: 'A', 6: 'T' });
	assert.equal(s.status, 'won');
});

test('scoreOnSolve is budget-spent on win, 0 otherwise', () => {
	let s = newGame(P);
	assert.equal(scoreOnSolve(s), 0);
	s = buyLetter(s, 'A'); // spent 100
	s = applyGuess(s, { 0: 'C', 1: 'A', 2: 'T', 4: 'H', 5: 'A', 6: 'T' });
	assert.equal(s.status, 'won');
	assert.equal(scoreOnSolve(s), 360 - 100);
});

test('toBoard emits the server-shaped board', () => {
	let s = buyLetter(newGame(P), 'A');
	const b = toBoard(s);
	assert.deepEqual(b.word_lengths, [3, 3]);
	assert.deepEqual(b.revealed, { 1: 'A', 5: 'A' });
	assert.equal(b.bankroll, 360 - 100);
	assert.equal(b.live.remaining, 360 - 100);
	assert.equal(b.state, 'active');
	assert.equal(b.phrase, undefined); // hidden until won
});
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `node --test src/lib/freeplay/engine.test.js`
Expected: FAIL — `Cannot find module './engine.js'` / functions undefined.

- [ ] **Step 3: Implement the engine**

```js
// src/lib/freeplay/engine.js
// Pure Free Play game engine — no stores, no network, no DOM. Mirrors the online
// buy-a-letter / guess / score loop, but in points. Answer is held in-state to resolve
// reveals/guesses; toBoard() never exposes it until solved.
import { LETTER_COSTS } from '../letterCosts.js';

/** @param {string} phrase */
function distinctLetters(phrase) {
	return [...new Set(phrase.replace(/[^A-Z]/g, '').split(''))];
}

/** @param {{id:string,phrase:string,category:string,clue:string}} puzzle */
export function newGame(puzzle) {
	const phrase = puzzle.phrase.toUpperCase();
	const base = distinctLetters(phrase).reduce((sum, c) => sum + (LETTER_COSTS[c] || 0), 0);
	// 1.2× headroom so a skilled solver keeps some; rounded to the nearest $10.
	const budget = Math.round((1.2 * base) / 10) * 10;
	return {
		puzzleId: puzzle.id,
		phrase,
		category: puzzle.category,
		clue: puzzle.clue,
		budget,
		spent: 0,
		/** @type {number[]} */ revealed: [],
		/** @type {string[]} */ incorrect: [],
		/** @type {'active'|'won'} */ status: 'active'
	};
}

/** @param {ReturnType<typeof newGame>} state @param {string} rawLetter */
export function buyLetter(state, rawLetter) {
	if (state.status !== 'active') return state;
	const letter = rawLetter.toUpperCase();
	const cost = LETTER_COSTS[letter];
	if (cost == null) return state; // invalid letter
	if (state.incorrect.includes(letter)) return state; // already tried, wrong
	const positions = [];
	for (let i = 0; i < state.phrase.length; i++) if (state.phrase[i] === letter) positions.push(i);
	if (positions.length && positions.every((i) => state.revealed.includes(i))) return state; // already revealed
	if (state.budget - state.spent < cost) return state; // unaffordable
	if (positions.length === 0) {
		return { ...state, spent: state.spent + cost, incorrect: [...state.incorrect, letter] };
	}
	const revealed = [...new Set([...state.revealed, ...positions])].sort((a, b) => a - b);
	return { ...state, spent: state.spent + cost, revealed };
}

/** @param {ReturnType<typeof newGame>} state @param {Record<number,string>} filled */
export function applyGuess(state, filled) {
	if (state.status !== 'active') return state;
	for (let i = 0; i < state.phrase.length; i++) {
		if (state.phrase[i] === ' ') continue;
		const ch = (filled[i] ?? (state.revealed.includes(i) ? state.phrase[i] : '')).toUpperCase();
		if (ch !== state.phrase[i]) return state; // any mismatch → not solved (no penalty)
	}
	// every non-space position matches → win; reveal all
	const all = [];
	for (let i = 0; i < state.phrase.length; i++) if (state.phrase[i] !== ' ') all.push(i);
	return { ...state, revealed: all, status: 'won' };
}

/** @param {ReturnType<typeof newGame>} state */
export function scoreOnSolve(state) {
	return state.status === 'won' ? Math.max(0, state.budget - state.spent) : 0;
}

/** @param {ReturnType<typeof newGame>} state */
export function toBoard(state) {
	const wordLengths = state.phrase.split(' ').map((w) => w.length);
	/** @type {Record<string,string>} */
	const revealed = {};
	for (const i of state.revealed) revealed[i] = state.phrase[i];
	const budgetLeft = Math.max(0, state.budget - state.spent);
	return {
		word_lengths: wordLengths,
		revealed,
		incorrect_letters: state.incorrect,
		locked_letters: [],
		bankroll: budgetLeft,
		guesses_remaining: 99,
		category: state.category,
		subcategory: '',
		clue: state.clue,
		state: state.status,
		...(state.status === 'won' ? { phrase: state.phrase } : {}),
		live: { remaining: budgetLeft }
	};
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `node --test src/lib/freeplay/engine.test.js`
Expected: PASS — all 7 tests ok.

- [ ] **Step 5: Commit**

```bash
git add src/lib/freeplay/engine.js src/lib/freeplay/engine.test.js
git commit -m "feat(freeplay): pure points engine with unit tests"
```

---

## Task 4: Device-local points store (TDD)

**Files:**
- Create: `src/lib/freeplay/points.js`
- Test: `src/lib/freeplay/points.test.js`

**Interfaces:**
- Produces:
  - `loadPoints(storage) => { total:number, best:number }` — reads namespaced keys, defaulting to 0/0 on missing/corrupt.
  - `recordSolve(storage, runScore:number) => { total:number, best:number }` — adds `runScore` to total, bumps `best` if larger, persists, returns the new totals.
  - `storage` is any object with `getItem(k)`/`setItem(k,v)` (real `localStorage` in the app, an in-memory mock in tests).

- [ ] **Step 1: Write the failing tests**

```js
// src/lib/freeplay/points.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadPoints, recordSolve } from './points.js';

function mem(init = {}) {
	const m = { ...init };
	return { getItem: (k) => (k in m ? m[k] : null), setItem: (k, v) => (m[k] = String(v)), _m: m };
}

test('loadPoints defaults to zero when empty', () => {
	assert.deepEqual(loadPoints(mem()), { total: 0, best: 0 });
});

test('loadPoints tolerates corrupt values', () => {
	assert.deepEqual(loadPoints(mem({ 'freeplay:total': 'xyz', 'freeplay:best': '' })), { total: 0, best: 0 });
});

test('recordSolve accumulates total and tracks best', () => {
	const s = mem();
	assert.deepEqual(recordSolve(s, 200), { total: 200, best: 200 });
	assert.deepEqual(recordSolve(s, 120), { total: 320, best: 200 }); // best unchanged
	assert.deepEqual(recordSolve(s, 500), { total: 820, best: 500 }); // new best
	assert.deepEqual(loadPoints(s), { total: 820, best: 500 }); // persisted
});
```

- [ ] **Step 2: Run to confirm failure**

Run: `node --test src/lib/freeplay/points.test.js`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```js
// src/lib/freeplay/points.js
// Device-local Free Play score. No accounts, no server — just this device's running
// total + best single run, under a "freeplay:" localStorage namespace.
const K_TOTAL = 'freeplay:total';
const K_BEST = 'freeplay:best';

/** @param {{getItem:(k:string)=>string|null}} storage @param {string} key */
function readInt(storage, key) {
	const n = parseInt(storage.getItem(key) ?? '', 10);
	return Number.isFinite(n) && n >= 0 ? n : 0;
}

/** @param {{getItem:(k:string)=>string|null}} storage */
export function loadPoints(storage) {
	return { total: readInt(storage, K_TOTAL), best: readInt(storage, K_BEST) };
}

/** @param {{getItem:(k:string)=>string|null,setItem:(k:string,v:string)=>void}} storage @param {number} runScore */
export function recordSolve(storage, runScore) {
	const gained = Math.max(0, Math.round(runScore) || 0);
	const { total, best } = loadPoints(storage);
	const next = { total: total + gained, best: Math.max(best, gained) };
	storage.setItem(K_TOTAL, String(next.total));
	storage.setItem(K_BEST, String(next.best));
	return next;
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `node --test src/lib/freeplay/points.test.js`
Expected: PASS — 3 tests ok.

- [ ] **Step 5: Commit**

```bash
git add src/lib/freeplay/points.js src/lib/freeplay/points.test.js
git commit -m "feat(freeplay): device-local points store with unit tests"
```

---

## Task 5: Wire the engine into GameStore (freeplay mode)

**Files:**
- Modify: `src/lib/stores/GameStore.js` (add functions; add branches in `confirmPurchase` at ~line 1001 and `submitGuess` at ~line 1102)

**Interfaces:**
- Consumes: `newGame`, `buyLetter`, `applyGuess`, `scoreOnSolve`, `toBoard` from `$lib/freeplay/engine.js`; `FREEPLAY_PUZZLES` from `$lib/freeplay/puzzles.js`; `loadPoints`, `recordSolve` from `$lib/freeplay/points.js`; existing `boardToState`, `gameStore`, `fx`, `browser`.
- Produces (exports used by `+page.svelte`):
  - `startFreePlay(): void` — begins a run (or a fresh puzzle), sets `gameMode:'freeplay'`.
  - `freePlayNext(): void` — loads the next random puzzle.
  - `freePlayPoints(): { total:number, best:number }` — current device totals (for the HUD).
  - Internal: `reconcileFreeplayBoard`, `confirmPurchaseFreeplay`, `submitGuessFreeplay`, plus a module-local `freeplayState` holding the current engine `State`.

- [ ] **Step 1: Add imports** near the other imports at the top of `GameStore.js`:

```js
import { newGame, buyLetter, applyGuess, scoreOnSolve, toBoard } from '$lib/freeplay/engine.js';
import { FREEPLAY_PUZZLES } from '$lib/freeplay/puzzles.js';
import { loadPoints, recordSolve } from '$lib/freeplay/points.js';
```

- [ ] **Step 2: Add the freeplay controller block** (place it just after `reconcileMakeupBoard`, alongside the other reconcile functions):

```js
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
	gameStore.set(
		/** @type {GameState} */ ({
			...prev,
			...boardToState(board, prev),
			gameMode: 'freeplay',
			gameState: won ? 'won' : 'default',
			clue: board.clue ?? null,
			dailyLive: board.live,
			// freeplay never uses these money/daily fields:
			climbInfo: null,
			dailyResult: null,
			modifier: null,
			dailyMustGuess: false
		})
	);
	if (won) {
		const gained = scoreOnSolve(freeplayState);
		recordSolve(fpStorage(), gained);
		fx('win');
	} else {
		playMoveCue(prev, board);
	}
}

/** Begin Free Play (fresh random puzzle). */
export function startFreePlay() {
	freePlayNext();
}

/** Load the next random Free Play puzzle. */
export function freePlayNext() {
	const puzzle = FREEPLAY_PUZZLES[Math.floor(Math.random() * FREEPLAY_PUZZLES.length)];
	freeplayState = newGame(puzzle);
	reconcileFreeplayBoard();
}

/** @param {GameState} current */
function confirmPurchaseFreeplay(current) {
	const sel = current.selectedPurchase;
	if (!freeplayState || !sel || sel.type !== 'letter') return;
	freeplayState = buyLetter(freeplayState, sel.value);
	reconcileFreeplayBoard();
}

/** @param {GameState} current */
function submitGuessFreeplay(current) {
	if (!freeplayState) return;
	/** @type {Record<number,string>} */
	const filled = {};
	for (const [k, v] of Object.entries(current.guessedLetters || {})) filled[Number(k)] = String(v);
	freeplayState = applyGuess(freeplayState, filled);
	gameStore.update((s) => ({ ...s, gameState: 'default', guessedLetters: {} }));
	reconcileFreeplayBoard();
}
```

> **Note for the implementer:** confirm the exact shape of `selectedPurchase` and `guessedLetters` by reading `selectLetter` (~line 930) and `inputGuessLetter` (~line 1051). `selectedPurchase` is `{ type:'letter', value:<LETTER> }`; `guessedLetters` is `Record<indexString, letter>` keyed by global phrase index. The code above matches those; adjust the field reads if the local shapes differ.

- [ ] **Step 3: Add the freeplay branch to the two seams.**

In `confirmPurchase()` (~line 1001) add as the final branch:

```js
	else if (current.gameMode === 'freeplay') confirmPurchaseFreeplay(current);
```

In `submitGuess()` (~line 1102) add as the final branch:

```js
	else if (current.gameMode === 'freeplay') submitGuessFreeplay(current);
```

- [ ] **Step 4: Verify build**

Run: `npx prettier --write src/lib/stores/GameStore.js && npm run check && npm run build`
Expected: 0 errors, 1 warning; build succeeds.

- [ ] **Step 5: Commit**

```bash
git add src/lib/stores/GameStore.js
git commit -m "feat(freeplay): drive the engine through gameStore (freeplay mode)"
```

---

## Task 6: Keyboard affordability for freeplay

**Files:**
- Modify: `src/lib/components/Keyboard.svelte:117-122` (the `$: affordPool = …` block)

**Interfaces:**
- Consumes: `$gameStore.dailyLive.remaining` (set by `reconcileFreeplayBoard` in Task 5).

- [ ] **Step 1: Add the freeplay branch** so unaffordable letters grey out against the points budget. Change:

```js
	$: affordPool =
		$gameStore.gameMode === 'climb'
			? Number($gameStore.climbInfo?.balance ?? $gameStore.climbInfo?.budget_left ?? 0)
			: $gameStore.gameMode === 'daily'
				? Number($gameStore.dailyLive?.remaining ?? $gameStore.bankroll ?? 0)
				: Number($gameStore.bankroll ?? 0);
```

to:

```js
	$: affordPool =
		$gameStore.gameMode === 'climb'
			? Number($gameStore.climbInfo?.balance ?? $gameStore.climbInfo?.budget_left ?? 0)
			: $gameStore.gameMode === 'daily' || $gameStore.gameMode === 'freeplay'
				? Number($gameStore.dailyLive?.remaining ?? $gameStore.bankroll ?? 0)
				: Number($gameStore.bankroll ?? 0);
```

- [ ] **Step 2: Verify**

Run: `npx prettier --write src/lib/components/Keyboard.svelte && npm run check`
Expected: 0 errors, 1 warning.

- [ ] **Step 3: Commit**

```bash
git add src/lib/components/Keyboard.svelte
git commit -m "feat(freeplay): grey out unaffordable keys against the points budget"
```

---

## Task 7: Entry points + Free Play HUD in the game screen

**Files:**
- Modify: `src/routes/+page.svelte` — (a) import the freeplay actions; (b) a Free Play card in the `menuView === 'play'` sub-view (next to the Daily `menu-card` at ~line 3458); (c) a "Keep playing free →" link on the Cash Game out-of-money banner (near the `dc-title`/`dc-sub` block, ~line 4377); (d) a small points header + "Next puzzle" button shown only when `gameMode === 'freeplay'`.

**Interfaces:**
- Consumes: `startFreePlay`, `freePlayNext`, `freePlayPoints` from `$lib/stores/GameStore.js`.

- [ ] **Step 1: Import the actions** in the `<script>` of `+page.svelte` (with the other GameStore imports):

```js
	import { startFreePlay, freePlayNext, freePlayPoints } from '$lib/stores/GameStore.js';
```

- [ ] **Step 2: Add a reactive points holder + a launcher** in the `<script>`:

```js
	// Free Play: device-local points, refreshed whenever the mode is active.
	let fpPoints = { total: 0, best: 0 };
	$: if ($gameStore.gameMode === 'freeplay' && $gameStore.gameState) fpPoints = freePlayPoints();
	function handleFreePlay() {
		fx('tap');
		startFreePlay();
		showMainMenu = false;
		hasInitialized = true;
	}
```

- [ ] **Step 3: Add the Free Play card** to the Play sub-view. Immediately after the closing `</button>` of the Daily `menu-card` (the block starting at `<button class="menu-card has-streaks"` ~line 3458), insert:

```svelte
					<button class="menu-card fp-card" style="--i: 3" on:click={handleFreePlay}>
						<span class="mc-title">Free Play</span>
						<span class="mc-right"><span class="daily-chip">Points · Free</span></span>
						<span class="mc-sub">Practice puzzles, no money. Best: {freePlayPoints().best}</span>
					</button>
```

(If `.mc-sub` isn't a class the Daily card uses, drop that line — the plan's requirement is a card that calls `handleFreePlay`; reuse whatever `menu-card` sub-elements already exist.)

- [ ] **Step 4: Add the broke-state link.** In the Cash Game out-of-money banner (the `{:else if dangerMode}` block containing `<span class="dc-title">…OUT OF MONEY</span>` ~line 4377), add below the existing `dc-sub`:

```svelte
					<button class="dc-freeplay" on:click={handleFreePlay}>Keep playing free →</button>
```

with this style added to the `<style>` block:

```css
	.dc-freeplay {
		margin-top: 8px;
		background: none;
		border: none;
		color: var(--brand-2, #fde047);
		font-weight: 700;
		font-size: 0.85rem;
		cursor: pointer;
		text-decoration: underline;
	}
```

- [ ] **Step 5: Add the Free Play header** (points + Next) shown only in freeplay. Place it just inside the game-screen container, guarded by the mode. Find where the in-game mode pill/header renders for climb/daily and add a sibling:

```svelte
			{#if $gameStore.gameMode === 'freeplay'}
				<div class="fp-hud">
					<span class="fp-pts">★ {fpPoints.total} pts</span>
					<button
						class="fp-next"
						on:click={() => {
							fx('tap');
							freePlayNext();
						}}>{$gameStore.gameState === 'won' ? 'Next puzzle →' : 'Skip →'}</button
					>
				</div>
			{/if}
```

with styles:

```css
	.fp-hud {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 10px;
		margin: 6px auto 4px;
		max-width: 340px;
	}
	.fp-pts {
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		color: var(--brand-2, #fde047);
	}
	.fp-next {
		background: none;
		border: 1px solid var(--border);
		border-radius: 999px;
		padding: 4px 12px;
		color: var(--text);
		font-weight: 700;
		cursor: pointer;
	}
```

- [ ] **Step 6: Gates**

Run: `npx prettier --write src/routes/+page.svelte && npm run check && npm run build`
Expected: 0 errors, 1 warning; build succeeds.

- [ ] **Step 7: Manual smoke test** (dev server running):

Run through: Play → Free Play → a puzzle loads with a points budget; buying an affordable letter reveals it and drops the budget; unaffordable keys are greyed; guessing the phrase wins, shows the reveal, credits points (★ total rises), and "Next puzzle →" loads a new one. Confirm the DevTools Network tab shows **no Supabase requests** during play.

- [ ] **Step 8: Commit**

```bash
git add src/routes/+page.svelte
git commit -m "feat(freeplay): Free Play card, broke-state link, and in-game points HUD"
```

---

## Task 8: End-to-end verification with a Playwright harness

**Files:**
- Create (temporary, delete after): `scripts/qa-freeplay.mjs`

- [ ] **Step 1: Write a harness** that signs up, opens Play → Free Play, buys a letter, and asserts (a) a `.menu-card` / board renders, (b) the points budget on the board decreases after a buy, and (c) **zero** requests to `*.supabase.co` fire between entering Free Play and finishing a buy (capture via `page.on('request')`). Model it on `scripts/qa-*.mjs` patterns (fresh Chromium context, sign-up flow, `button.play-cta` then the Free Play card).

- [ ] **Step 2: Run it**

Run: `node scripts/qa-freeplay.mjs`
Expected: board renders, budget decreases on buy, `supabase requests during freeplay: 0`.

- [ ] **Step 3: Clean up + commit** (harness is throwaway; do not commit it — matches the repo convention that `qa-*.mjs` probes are temporary):

```bash
rm -f scripts/qa-freeplay.mjs
```

(No commit — this task only verifies. If any assertion fails, fix the offending task and re-run.)

---

## Self-Review

**Spec coverage:**
- Offline-ready client engine → Task 3 (pure, no I/O). ✓
- Points budget → buy letters → keep unspent → score → Tasks 3 (`scoreOnSolve`) + 5 (`recordSolve`). ✓
- Endless, no bust → engine has only `active`/`won`; `freePlayNext`/Skip always available (Task 7). ✓
- Device-local points, no leaderboard/heat/cash → Task 4 + Global Constraints. ✓
- Reuse the polished game UI → Tasks 5–7 drive the existing board/keyboard/reveal via `boardToState`. ✓
- Own (placeholder, original) puzzles, no money-mode leak → Task 2 + constraint. ✓
- Entry from Play menu + broke state → Task 7. ✓
- Zero server calls → Task 5 (engine is client-side) + Task 8 assertion. ✓
- Named "Free Play" → all copy in Task 7. ✓

**Deferred (explicitly out of scope, not gaps):** offline app-shell (Capacitor local bundle / service worker), Airplane rename, badges, leaderboard, online points sync, dedicated real puzzle pool.

**Type consistency:** the engine `State` and `Board` shapes in Task 3 match what `reconcileFreeplayBoard`/`toBoard` produce and what `boardToState` (Task 5 context) consumes (`word_lengths`, `revealed`, `incorrect_letters`, `locked_letters`, `bankroll`, `guesses_remaining`, `category`, `subcategory`, `state`, `phrase?`, `live.remaining`). `selectedPurchase.{type,value}` and `guessedLetters` keyed by index are used consistently in Task 5.

**Placeholder scan:** no TBD/TODO; every code step contains complete code. The two "confirm the exact shape by reading X" notes point at real line numbers for a value the implementer must eyeball, not missing logic.
