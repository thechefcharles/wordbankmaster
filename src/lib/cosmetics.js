// Resolves equipped-cosmetic IDs into display values.
//
// The server stores/returns the equipped cosmetic's ID (e.g. 'title_on_fire', 'color_gold'),
// NOT the display text or hex. This loads the small cosmetics catalog once and maps an id to
// { label, value, kind } so the UI can show the title label ('🔥 On Fire') and apply the
// name-colour hex ('#fbbf24'). Without this, equipped titles/colours render as raw ids or
// nothing at all.
import { writable, get } from 'svelte/store';
import { browser } from '$app/environment';
import { supabase } from '$lib/supabaseClient.js';

/** @type {import('svelte/store').Writable<Record<string,{label:string,value:string,kind:string}>>} */
export const cosmeticsMap = writable({});

let loaded = false;
/** @type {Promise<any>|null} */
let loading = null;

export async function loadCosmetics() {
	if (loaded) return;
	if (loading) return loading;
	loading = (async () => {
		try {
			const { data } = await supabase.from('cosmetics').select('id,label,value,kind');
			/** @type {Record<string,{label:string,value:string,kind:string}>} */
			const map = {};
			for (const c of data ?? []) map[c.id] = { label: c.label, value: c.value, kind: c.kind };
			cosmeticsMap.set(map);
			loaded = true;
		} catch {
			/* best-effort; UI falls back to raw values */
		}
	})();
	return loading;
}

if (browser) loadCosmetics();

/** Title display label for an equipped-title id. Falls back to the raw value if it's not an id.
 * @param {Record<string,{label:string,value:string,kind:string}>} map @param {string|null|undefined} id */
export function titleLabel(map, id) {
	if (!id) return '';
	return map[id]?.label ?? id; // already-resolved text passes through unchanged
}

/** Name-colour hex for an equipped-colour id. Falls back to a raw hex if given one.
 * @param {Record<string,{label:string,value:string,kind:string}>} map @param {string|null|undefined} id */
export function colorHex(map, id) {
	if (!id) return '';
	const c = map[id];
	if (c?.kind === 'color') return c.value || '';
	return typeof id === 'string' && id.startsWith('#') ? id : '';
}
