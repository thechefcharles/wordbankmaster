// Device-local PIN unlock (approach A): the real credential stays email+password.
// The PIN is a fast, on-device privacy lock layered on top of a persistent session.
// We store only a SHA-256 hash (salted with the user id) in localStorage — never
// the raw PIN — plus the remembered username and a wrong-attempt counter.
import { writable } from 'svelte/store';
import { browser } from '$app/environment';

const HASH_KEY = 'wb_pin_hash';
const USER_KEY = 'wb_pin_user'; // user id this device's PIN belongs to
const NAME_KEY = 'wb_pin_name'; // remembered @username for the lock screen
const FAILS_KEY = 'wb_pin_fails';

export const MAX_PIN_FAILS = 5;
export const PIN_LENGTH = 4;

/** True while the app is PIN-locked (session valid but awaiting the PIN). */
export const pinLocked = writable(false);

/** @param {string} pin @param {string} uid */
async function hashPin(pin, uid) {
	const data = new TextEncoder().encode(`wb:${uid}:${pin}`);
	const buf = await crypto.subtle.digest('SHA-256', data);
	return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Is a PIN set on THIS device for this user? @param {string} uid */
export function hasPinFor(uid) {
	return !!(browser && localStorage.getItem(HASH_KEY) && localStorage.getItem(USER_KEY) === uid);
}

/** Remembered username for the lock screen (this device). */
export function rememberedName() {
	return browser ? localStorage.getItem(NAME_KEY) : null;
}

/** Store a new PIN for this device+user. @param {string} uid @param {string|null} name @param {string} pin */
export async function setPin(uid, name, pin) {
	if (!browser) return;
	localStorage.setItem(HASH_KEY, await hashPin(pin, uid));
	localStorage.setItem(USER_KEY, uid);
	if (name) localStorage.setItem(NAME_KEY, name);
	localStorage.removeItem(FAILS_KEY);
}

/** Verify an entered PIN; tracks failures. @param {string} uid @param {string} pin */
export async function verifyPin(uid, pin) {
	if (!browser) return false;
	const ok = (await hashPin(pin, uid)) === localStorage.getItem(HASH_KEY);
	if (ok) localStorage.removeItem(FAILS_KEY);
	else localStorage.setItem(FAILS_KEY, String(pinFails() + 1));
	return ok;
}

export function pinFails() {
	return browser ? Number(localStorage.getItem(FAILS_KEY) || 0) : 0;
}
export function tooManyFails() {
	return pinFails() >= MAX_PIN_FAILS;
}

// Session unlock flag (sessionStorage): survives in-app navigation + refresh, but
// is cleared when the app/tab is closed. So the PIN is asked on a cold open — not
// every time you return to the menu.
const UNLOCKED_KEY = 'wb_unlocked';
export function markUnlocked() {
	if (browser) sessionStorage.setItem(UNLOCKED_KEY, '1');
}
export function sessionIsUnlocked() {
	return !!(browser && sessionStorage.getItem(UNLOCKED_KEY) === '1');
}
/** Force a re-lock this session (e.g. before a purchase). */
export function relock() {
	if (browser) sessionStorage.removeItem(UNLOCKED_KEY);
	pinLocked.set(true);
}

// "Skip for now" choice — persisted per device+user so the set-PIN screen doesn't
// nag on every cold open. Cleared when a PIN is actually set or on logout.
const SKIP_KEY = 'wb_pin_skipped';
/** @param {string} uid */
export function markPinSkipped(uid) {
	if (browser) localStorage.setItem(SKIP_KEY, uid);
}
/** @param {string} uid */
export function pinSkipped(uid) {
	return !!(browser && localStorage.getItem(SKIP_KEY) === uid);
}
export function clearPinSkipped() {
	if (browser) localStorage.removeItem(SKIP_KEY);
}

/** Forget the PIN (forgot-PIN / logout). Keeps the remembered name unless full=true. */
export function clearPin(full = false) {
	if (!browser) return;
	localStorage.removeItem(HASH_KEY);
	localStorage.removeItem(USER_KEY);
	localStorage.removeItem(FAILS_KEY);
	sessionStorage.removeItem(UNLOCKED_KEY);
	if (full) localStorage.removeItem(NAME_KEY);
}
