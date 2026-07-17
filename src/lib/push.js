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
import { PushNotifications } from '@capacitor/push-notifications';
import { browser } from '$app/environment';
import { supabase } from '$lib/supabaseClient.js';
import { goto } from '$app/navigation';

const isNative = () => browser && Capacitor?.isNativePlatform?.() === true;

// NOTE: import this plugin STATICALLY, exactly like @capacitor/haptics.
// A dynamic import() here hangs forever inside the iOS WKWebView: Vite wraps it in
// __vitePreload, which injects <link rel="modulepreload"> elements and awaits their
// load/error events — and WKWebView fires neither, so the promise never settles and
// push silently does nothing. The module is ~100 bytes and is inert on the web (it
// only calls registerPlugin), so there is nothing to lazy-load anyway.

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
 * Never throws and never hangs: a native call that fails resolves to 'prompt' so the
 * toggle stays visible and tappable rather than silently vanishing.
 * @returns {Promise<'granted'|'denied'|'prompt'|'prompt-with-rationale'|'unsupported'>} */
export async function pushStatus() {
	if (!isNative()) return 'unsupported';
	try {
		const r = await PushNotifications.checkPermissions();
		return r?.receive ?? 'prompt';
	} catch (e) {
		console.warn('[push] checkPermissions failed', e);
		return 'prompt';
	}
}

/**
 * Record this user's IANA timezone so retention pushes land at a sane LOCAL hour
 * (and respect quiet hours) instead of firing at 3am. Best-effort and fire-and-forget:
 * a failure here must never affect app start.
 *
 * Not native-only — a web user's timezone is just as valid, and they may install the
 * app later. Cached in localStorage so we issue at most one write per device per zone;
 * travel/DST changes the zone string, which re-syncs on the next launch.
 */
export async function syncTimezone() {
	if (!browser) return;
	try {
		const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
		if (!tz) return;
		if (localStorage.getItem('wb_tz') === tz) return;
		const { data } = await supabase.rpc('set_timezone', { p_tz: tz });
		if (data?.ok) localStorage.setItem('wb_tz', tz);
	} catch (e) {
		console.warn('[push] timezone sync failed', e);
	}
}

/** Clear the app-icon badge (call when the notifications inbox is opened). */
export async function clearBadge() {
	if (!isNative()) return;
	try {
		await PushNotifications.removeAllDeliveredNotifications();
	} catch {
		/* no-op */
	}
}

/** Drop this device's token on sign-out so a logged-out phone stops receiving pushes. */
export async function unregisterPush() {
	if (!isNative()) return;
	try {
		const perm = await PushNotifications.checkPermissions();
		if (perm.receive !== 'granted') return;
		// Best-effort: we can't read the token back, so rely on the server pruning 410s.
		await PushNotifications.removeAllDeliveredNotifications();
	} catch {
		/* no-op */
	}
}
