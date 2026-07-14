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

const K_BANKED = 'freeplay:bankedMatches';

/** @param {{getItem:(k:string)=>string|null}} storage @returns {string[]} */
function readBanked(storage) {
	try {
		const a = JSON.parse(storage.getItem(K_BANKED) ?? '[]');
		return Array.isArray(a) ? a : [];
	} catch {
		return [];
	}
}

/** Bank a friendly match's final score into the device Free Play total — ONCE per match id.
 * Returns the new totals, or null if this match was already banked or matchId is nullish.
 * @param {{getItem:(k:string)=>string|null,setItem:(k:string,v:string)=>void}} storage
 * @param {string|null|undefined} matchId @param {number} score */
export function bankMatchPoints(storage, matchId, score) {
	if (matchId == null) return null;
	const id = String(matchId);
	const banked = readBanked(storage);
	if (banked.includes(id)) return null;
	banked.push(id);
	storage.setItem(K_BANKED, JSON.stringify(banked));
	return recordSolve(storage, score);
}
