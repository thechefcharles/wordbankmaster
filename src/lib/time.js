/** Human solve time: null → "—", <60s → "12s", else "1m 05s". @param {any} s */
export function fmtSecs(s) {
	if (s == null) return '—';
	const n = Math.round(Number(s));
	return n < 60 ? `${n}s` : `${Math.floor(n / 60)}m ${String(n % 60).padStart(2, '0')}s`;
}
