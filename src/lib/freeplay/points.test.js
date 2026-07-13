import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadPoints, recordSolve } from './points.js';

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
