// Pure Free Play game engine — no stores, no network, no DOM. Mirrors the online
// buy-a-letter / guess / score loop, but in points. Answer is held in-state to resolve
// reveals/guesses; toBoard() never exposes it until solved.
import { LETTER_COSTS } from '../letterCosts.js';

/** @param {string} phrase */
function distinctLetters(phrase) {
	return [...new Set(phrase.replace(/[^A-Z]/g, '').split(''))];
}

/** @param {{id:string,phrase:string,category:string,clue:string}} puzzle
 * @returns {{puzzleId:string,phrase:string,category:string,clue:string,budget:number,spent:number,revealed:number[],incorrect:string[],status:'active'|'won'}} */
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

/** @param {ReturnType<typeof newGame>} state @param {string} rawLetter
 * @returns {ReturnType<typeof newGame>} */
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

/** @param {ReturnType<typeof newGame>} state @param {Record<number,string>} filled
 * @returns {ReturnType<typeof newGame>} */
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

/** @param {ReturnType<typeof newGame>} state
 * @returns {number} */
export function scoreOnSolve(state) {
	return state.status === 'won' ? Math.max(0, state.budget - state.spent) : 0;
}

/** @param {ReturnType<typeof newGame>} state
 * @returns {{word_lengths:number[],revealed:Record<string,string>,incorrect_letters:string[],locked_letters:any[],bankroll:number,guesses_remaining:number,category:string,subcategory:string,clue:string,state:'active'|'won',phrase?:string,live:{remaining:number}}} */
export function toBoard(state) {
	const wordLengths = state.phrase.split(' ').map((w) => w.length);
	/** @type {Record<string,string>} */
	const revealed = {};
	for (const i of state.revealed) revealed[i] = state.phrase[i];
	// A letter is "locked" (fully owned) once every one of its positions is revealed — the
	// keyboard greys those so you can't try to re-buy an already-owned letter. Matches the
	// server's _daily_board rule (GROUP BY letter HAVING all-positions-revealed).
	const revealedSet = new Set(state.revealed);
	const lockedLetters = [
		...new Set(state.phrase.replace(/[^A-Z]/g, '').split(''))
	]
		.filter((ch) => {
			for (let i = 0; i < state.phrase.length; i++) {
				if (state.phrase[i] === ch && !revealedSet.has(i)) return false;
			}
			return true;
		})
		.sort();
	const budgetLeft = Math.max(0, state.budget - state.spent);
	return {
		word_lengths: wordLengths,
		revealed,
		incorrect_letters: state.incorrect,
		locked_letters: lockedLetters,
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
