// Native push notifications (iOS via Capacitor + APNs).
//
// Native-only — every export is a safe no-op on the web, so nothing changes in a browser.
//
// PERMISSION POLICY (important): iOS gives you exactly ONE system prompt, ever. If the user
// denies it, you cannot ask again — they'd have to dig into Settings. So we never prompt on
// launch. `initPush()` only registers silently when permission is ALREADY granted;
// `requestPushPermission()` is the one that prompts, and it's called from a deliberate,
// high-intent moment (the primer after a first challenge, or the Settings toggle).
import { Capacitor } from '@capacitor/core';
import { browser } from '$app/environment';
import { supabase } from '$lib/supabaseClient.js';
import { goto } from '$app/navigation';

const isNative = () => browser && Capacitor?.isNativePlatform?.() === true;

/** Lazily import so the web bundle never touches the native plugin. */
async function plugin() {
	const { PushNotifications } = await import('@capacitor/push-notifications');
	return PushNotifications;
}

let wired = false;

/** Save the APNs device token server-side (RPC keys on auth.uid()).
 * @param {string} token */
async function saveToken(token) {
	try {
		// env defaults to 'sandbox'; the Edge Function self-heals to 'production' on
		// BadDeviceToken, so dev builds and TestFlight both work without client detection.
		await supabase.rpc('register_device_token', {
			p_token: token,
			p_platform: 'ios',
			p_env: 'sandbox'
		});
	} catch (e) {
		console.warn('[push] token save failed', e);
	}
}

/** Route a tapped notification to the right screen using the existing data conventions.
 * @param {Record<string, any>|undefined} data @returns {string|null} */
function routeFor(data) {
	if (!data) return null;
	if (data.match_id) return '/?match=' + data.match_id;
	if (data.group_id) return '/?group=' + data.group_id;
	if (data.route === 'friends') return '/?friends=1';
	return null;
}

/** Attach listeners once (registration + tap handling). */
async function wireListeners() {
	if (wired) return;
	wired = true;
	const PushNotifications = await plugin();

	await PushNotifications.addListener('registration', (t) => {
		if (t?.value) saveToken(t.value);
	});
	await PushNotifications.addListener('registrationError', (err) => {
		console.warn('[push] registration error', err);
	});
	// Tapped a notification -> deep link.
	await PushNotifications.addListener('pushNotificationActionPerformed', (action) => {
		const dest = routeFor(action?.notification?.data);
		if (dest) goto(dest);
	});
}

/**
 * Call on login. Registers ONLY if permission is already granted — never prompts.
 * @returns {Promise<'granted'|'denied'|'prompt'|'prompt-with-rationale'|'unsupported'>}
 */
export async function initPush() {
	if (!isNative()) return 'unsupported';
	try {
		const PushNotifications = await plugin();
		const perm = await PushNotifications.checkPermissions();
		if (perm.receive !== 'granted') return perm.receive; // 'prompt' | 'denied'
		await wireListeners();
		await PushNotifications.register();
		return 'granted';
	} catch (e) {
		console.warn('[push] init failed', e);
		return 'unsupported';
	}
}

/**
 * THE one-shot prompt. Call from the primer / Settings toggle only.
 * @returns {Promise<boolean>} true if granted
 */
export async function requestPushPermission() {
	if (!isNative()) return false;
	try {
		const PushNotifications = await plugin();
		const res = await PushNotifications.requestPermissions();
		if (res.receive !== 'granted') return false;
		await wireListeners();
		await PushNotifications.register();
		return true;
	} catch (e) {
		console.warn('[push] permission request failed', e);
		return false;
	}
}

/** Current permission state, for rendering the Settings toggle.
 * TEMP DIAGNOSTIC: returns a descriptive reason instead of swallowing failures, so we can
 * see WHY the toggle hides. Reverted once the root cause is known.
 * @returns {Promise<string>} */
export async function pushStatus() {
	if (!browser) return 'nobrowser';
	try {
		const nat = Capacitor?.isNativePlatform?.();
		const plat = Capacitor?.getPlatform?.();
		if (nat !== true) return 'notnative(' + String(nat) + '/' + String(plat) + ')';
		const PushNotifications = await plugin();
		if (!PushNotifications) return 'noplugin';
		const r = await PushNotifications.checkPermissions();
		return String(r?.receive ?? 'noreceive');
	} catch (/** @type {any} */ e) {
		return 'err:' + String((e && e.message) || e).slice(0, 45);
	}
}

/** Clear the app-icon badge (call when the notifications inbox is opened). */
export async function clearBadge() {
	if (!isNative()) return;
	try {
		const PushNotifications = await plugin();
		await PushNotifications.removeAllDeliveredNotifications();
	} catch {
		/* no-op */
	}
}

/** Drop this device's token on sign-out so a logged-out phone stops receiving pushes. */
export async function unregisterPush() {
	if (!isNative()) return;
	try {
		const PushNotifications = await plugin();
		const perm = await PushNotifications.checkPermissions();
		if (perm.receive !== 'granted') return;
		// Best-effort: we can't read the token back, so rely on the server pruning 410s.
		await PushNotifications.removeAllDeliveredNotifications();
	} catch {
		/* no-op */
	}
}
