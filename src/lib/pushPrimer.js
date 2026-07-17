// Push permission primer.
//
// WHY THIS EXISTS: iOS gives an app exactly ONE system permission prompt, ever. If the user
// taps "Don't Allow" it cannot be re-asked — they'd have to find it in iOS Settings. So we
// never fire the system prompt cold. We show our own explanation first, at a moment when the
// answer obviously matters, and only call the real prompt if they say yes here. A "not now"
// costs us nothing and can be asked again later; a "Don't Allow" is permanent.
//
// TIMING: armed when a challenge is created/accepted (the high-intent moment), but shown at
// the next natural pause — those actions drop the player straight into a puzzle, and a modal
// over live gameplay is the worst possible time to ask for anything.
import { writable } from 'svelte/store';
import { browser } from '$app/environment';
import { pushStatus, requestPushPermission } from '$lib/push.js';

const ARMED_KEY = 'wb_push_armed'; // a challenge happened; ask at the next pause
const ASKED_KEY = 'wb_push_asked'; // we've shown the primer — don't nag

/** True while the primer modal should be on screen. */
export const showPushPrimer = writable(false);

/** @param {string} k @returns {boolean} */
function flag(k) {
	try {
		return browser && localStorage.getItem(k) === '1';
	} catch {
		return false;
	}
}
/** @param {string} k @param {boolean} v */
function setFlag(k, v) {
	try {
		if (!browser) return;
		if (v) localStorage.setItem(k, '1');
		else localStorage.removeItem(k);
	} catch {
		/* private mode / storage disabled — primer just won't persist */
	}
}

/** Called on challenge create/accept. Cheap and synchronous: only records intent. */
export function armPushPrimer() {
	if (!browser || flag(ASKED_KEY)) return;
	setFlag(ARMED_KEY, true);
}

/**
 * Called at a natural pause (returning to the menu). Shows the primer only if a challenge
 * armed it and iOS would actually prompt — 'granted'/'denied' both mean the one prompt is
 * already spent, so there is nothing to ask for.
 */
export async function maybeShowPushPrimer() {
	if (!browser || !flag(ARMED_KEY) || flag(ASKED_KEY)) return;
	const st = await pushStatus();
	if (st !== 'prompt' && st !== 'prompt-with-rationale') {
		setFlag(ARMED_KEY, false); // nothing to ask; don't re-check every menu visit
		return;
	}
	showPushPrimer.set(true);
}

/**
 * Resolve the primer. `accepted` fires the real (one and only) iOS prompt.
 * @param {boolean} accepted @returns {Promise<boolean>} true if permission ended up granted
 */
export async function resolvePushPrimer(accepted) {
	showPushPrimer.set(false);
	setFlag(ARMED_KEY, false);
	setFlag(ASKED_KEY, true); // asked once either way — never nag
	if (!accepted) return false;
	return await requestPushPermission();
}
