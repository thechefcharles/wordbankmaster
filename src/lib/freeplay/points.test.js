import { test } from 'node:test';
import assert from 'node:assert/strict';
import { bankMatchPoints, loadPoints, recordSolve } from './points.js';

/** @param {Record<string, string>} init */
function mem(init = {}) {
	/** @type {Record<string, string>} */
	const m = { ...init };
	return { getItem: (/** @type {string} */ k) => (k in m ? m[k] : null), setItem: (/** @type {string} */ k, /** @type {string} */ v) => (m[k] = String(v)), _m: m };
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

test('bankMatchPoints adds a match score to the Free Play total once', () => {
	const s = mem();
	const r = bankMatchPoints(s, 'match-1', 250);
	assert.equal(r.total, 250);
	assert.equal(loadPoints(s).total, 250);
});

test('bankMatchPoints is a no-op the second time for the same match id', () => {
	const s = mem();
	bankMatchPoints(s, 'match-1', 250);
	const again = bankMatchPoints(s, 'match-1', 250); // re-observed completed board
	assert.equal(again, null);
	assert.equal(loadPoints(s).total, 250); // not 500
});

test('bankMatchPoints ignores a nullish match id', () => {
	const s = mem();
	assert.equal(bankMatchPoints(s, null, 100), null);
	assert.equal(loadPoints(s).total, 0);
});
