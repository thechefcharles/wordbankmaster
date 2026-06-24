// One-off PIN confirmation for sensitive Cash commitments (shop purchases,
// entering a wagered challenge). Distinct from the app-lock: this gates a single
// action, then returns control. requirePin() resolves when verified, rejects on
// cancel, and is a no-op (resolves) if no device PIN is set.
import { writable, get } from 'svelte/store';
import { hasPinFor } from '$lib/pin.js';
import { user } from '$lib/stores/userStore.js';
import { supabase } from '$lib/supabaseClient';

/** @type {import('svelte/store').Writable<null | {reason:string, details?:{label:string,value:string}[], uid:string, resolve:(v:boolean)=>void, reject:(e:any)=>void}>} */
export const pinConfirm = writable(null);

/** @param {string} reason @param {{label:string,value:string}[]} [details] line items (e.g. challenge stakes) shown above the pad @returns {Promise<boolean>} */
export async function requirePin(reason = 'Confirm', details) {
  // Resolve the uid from the store, or the session (so it works on any route).
  let uid = get(user)?.id;
  if (!uid) { try { const { data } = await supabase.auth.getSession(); uid = data?.session?.user?.id; } catch { /* ignore */ } }
  if (!uid || !hasPinFor(uid)) return true; // nothing to confirm
  return await new Promise((resolve, reject) => {
    pinConfirm.set({ reason, details, uid, resolve, reject });
  });
}
