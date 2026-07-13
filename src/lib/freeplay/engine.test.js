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
	// A is fully revealed (both positions) → locked so the keyboard greys it; T/H aren't.
	assert.deepEqual(b.locked_letters, ['A']);
});

test('toBoard locks a letter only when ALL its positions are revealed', () => {
	// "AHA" has A at 0 and 2; revealing just index 0 must NOT lock A.
	let s = newGame({ id: 'y', phrase: 'AHA', category: 'C', clue: 'k' });
	s = { ...s, revealed: [0] };
	assert.deepEqual(toBoard(s).locked_letters, []);
	s = { ...s, revealed: [0, 2] };
	assert.deepEqual(toBoard(s).locked_letters, ['A']);
});
