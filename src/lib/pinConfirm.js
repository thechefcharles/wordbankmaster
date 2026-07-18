// One-off PIN gate for sensitive Cash commitments (shop purchases, entering a wagered
// challenge). This is the ONLY place the PIN is used — there is no app-lock / sign-in PIN.
//
// requirePin() resolves when confirmed, rejects on cancel. Lazy setup: the FIRST time a
// user hits a money action with no PIN yet, it opens a "create your PIN" flow instead of a
// verify — they set it in-context, then the action proceeds. After that it's a quick verify.
import { writable, get } from 'svelte/store';
import { hasPinFor, rememberedName } from '$lib/pin.js';
import { user, userProfile } from '$lib/stores/userStore.js';
import { supabase } from '$lib/supabaseClient';

/** @type {import('svelte/store').Writable<null | {mode:'verify'|'create', reason:string, details?:{label:string,value:string}[], uid:string, name:string|null, resolve:(v:boolean)=>void, reject:(e:any)=>void}>} */
export const pinConfirm = writable(null);

/**
 * Gate a money action behind the PIN.
 * @param {string} reason short label shown above the pad (e.g. "Buy the letter E")
 * @param {{label:string,value:string}[]} [details] line items (e.g. challenge stakes)
 * @returns {Promise<boolean>} resolves true when confirmed/created; rejects on cancel
 */
export async function requirePin(reason = 'Confirm', details) {
	// Resolve the uid from the store, or the session (so it works on any route).
	let uid = get(user)?.id;
	if (!uid) {
		try {
			const { data } = await supabase.auth.getSession();
			uid = data?.session?.user?.id;
		} catch {
			/* ignore */
		}
	}
	if (!uid) return true; // can't identify the user → don't block the action
	const mode = hasPinFor(uid) ? 'verify' : 'create';
	const uname = get(userProfile)?.username;
	const name = rememberedName() || (typeof uname === 'string' ? uname : null);
	return await new Promise((resolve, reject) => {
		pinConfirm.set({ mode, reason, details, uid, name, resolve, reject });
	});
}
