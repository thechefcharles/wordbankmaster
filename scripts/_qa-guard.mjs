// Shared guard for QA/screenshot scripts that create throwaway accounts.
//
// WHY: these scripts sign up fresh test users (qa…@example.com etc). WordBank has ONE
// database and it IS production — there is no separate dev/staging DB. So a stray
// `BASE=https://wordbanksvelte.vercel.app node scripts/qa-e2e.mjs` silently pollutes the
// real DB with test accounts (this is exactly how ~130 junk users got in). This guard
// makes hitting any non-local target a deliberate, explicit act.
//
// Usage in a script:
//   import { qaBase } from './_qa-guard.mjs';
//   const BASE = qaBase('http://localhost:5174');   // was: process.env.BASE || '...'

const LOCAL = /^https?:\/\/(localhost|127\.0\.0\.1|0\.0\.0\.0)(:\d+)?/i;

/**
 * Resolve BASE and refuse to run against a remote (production) target unless the operator
 * explicitly sets QA_ALLOW_PROD=1. Prevents accidental prod pollution.
 * @param {string} fallback local default, e.g. 'http://localhost:5174'
 * @returns {string}
 */
export function qaBase(fallback) {
	const base = process.env.BASE || fallback;
	if (!LOCAL.test(base) && process.env.QA_ALLOW_PROD !== '1') {
		console.error(
			`\n⛔ Refusing to run QA against a non-local target: ${base}\n` +
				`   This creates throwaway accounts, and WordBank's only DB is production.\n` +
				`   If you REALLY mean to, re-run with QA_ALLOW_PROD=1 — and clean up after.\n`
		);
		process.exit(1);
	}
	return base;
}
