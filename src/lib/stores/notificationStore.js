// Global notification service: polls the server, exposes the unread count + list,
// and surfaces brand-new items as transient toasts (visible from any screen).
import { writable } from 'svelte/store';
import { getNotifications, markNotificationsRead } from '$lib/stores/statsStore.js';
import { supabase } from '$lib/supabaseClient';

/** @type {import('svelte/store').Writable<any[]>} */
export const notifications = writable([]);
export const unreadCount = writable(0);
/** @type {import('svelte/store').Writable<{id:string,title:string,body:string,data:any}[]>} */
export const toasts = writable([]);

/** Bumped when something (e.g. a tapped toast) wants a Community tab opened. */
export const inboxRequest = writable(0);
/** Which Community tab the next inboxRequest should land on. */
export const inboxTarget = writable(/** @type {'challenges'|'activity'|'people'} */ ('challenges'));
/** @param {'challenges'|'activity'|'people'} [target] */
export function requestInbox(target = 'challenges') {
	inboxTarget.set(target);
	inboxRequest.update((n) => n + 1);
}

const POLL_MS = 45000;
/** @type {ReturnType<typeof setInterval>|undefined} */
let pollTimer;
/** @type {Set<string>} */
let knownIds = new Set();
let started = false;
let primed = false; // first poll seeds knownIds without toasting history
/** @type {(() => void)|undefined} */
let onVis;
/** @type {any} */
let channel;

async function poll() {
	const res = await getNotifications();
	const items = res.items ?? [];
	notifications.set(items);
	unreadCount.set(res.unread_count ?? 0);
	if (primed) {
		// newest first; toast anything new + still unread, oldest-of-the-new first
		const fresh = items.filter((n) => !knownIds.has(n.id) && !n.read).reverse();
		for (const n of fresh) pushToast(n);
	}
	for (const n of items) knownIds.add(n.id);
	primed = true;
}

/** @param {any} n */
function pushToast(n) {
	toasts.update((t) => [
		...t,
		{ id: n.id, title: n.title, body: n.body, data: n.data, type: n.type }
	]);
	setTimeout(() => dismissToast(n.id), 6000);
}
/** @param {string} id */
export function dismissToast(id) {
	toasts.update((t) => t.filter((x) => x.id !== id));
}

/** @param {string} [uid] subscribe to this user's notifications for instant updates */
export function startNotifications(uid) {
	if (started || typeof window === 'undefined') return;
	started = true;
	poll();
	pollTimer = setInterval(poll, POLL_MS);
	onVis = () => {
		if (!document.hidden) poll();
	};
	document.addEventListener('visibilitychange', onVis);
	// Realtime: a new challenge / friend request shows up instantly (not just on poll).
	if (uid) {
		channel = supabase
			.channel(`notifs:${uid}`)
			.on(
				'postgres_changes',
				{ event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${uid}` },
				() => poll()
			)
			.subscribe();
	}
}

export function stopNotifications() {
	started = false;
	primed = false;
	knownIds = new Set();
	notifications.set([]);
	unreadCount.set(0);
	toasts.set([]);
	if (pollTimer) clearInterval(pollTimer);
	pollTimer = undefined;
	if (onVis && typeof document !== 'undefined')
		document.removeEventListener('visibilitychange', onVis);
	if (channel) {
		supabase.removeChannel(channel);
		channel = undefined;
	}
}

/** Force an immediate refresh (e.g. after acting on a challenge). */
export async function refreshNotifications() {
	if (started) await poll();
}

export async function markAllNotificationsRead() {
	await markNotificationsRead();
	unreadCount.set(0);
	notifications.update((list) => list.map((n) => ({ ...n, read: true })));
}

/** Optimistically clear the badge for notifications matching a predicate, then sync. */
function clearLocal(/** @type {(n:any)=>boolean} */ match) {
	notifications.update((list) => {
		let cleared = 0;
		const next = list.map((n) => {
			if (!n.read && match(n)) {
				cleared++;
				return { ...n, read: true };
			}
			return n;
		});
		if (cleared) unreadCount.update((c) => Math.max(0, c - cleared));
		return next;
	});
}
/** Clear the notification(s) for one challenge — e.g. after accepting it from the banner. */
export async function markChallengeNotifRead(/** @type {string} */ matchId) {
	if (!matchId) return;
	clearLocal((n) => n?.data?.match_id === matchId);
	await markNotificationsRead(matchId, null);
	if (started) await poll();
}
/** Clear the friend-request notification from one person — e.g. accepting from the banner. */
export async function markFriendNotifRead(/** @type {string} */ fromId) {
	if (!fromId) return;
	clearLocal((n) => n?.data?.from_id === fromId);
	await markNotificationsRead(null, fromId);
	if (started) await poll();
}
/** Permanently dismiss (delete) one notification. @param {string} id */
export async function dismissNotification(id) {
	if (!id) return;
	notifications.update((list) => {
		const n = list.find((x) => x.id === id);
		if (n && !n.read) unreadCount.update((c) => Math.max(0, c - 1));
		return list.filter((x) => x.id !== id);
	});
	try {
		await supabase.rpc('dismiss_notification', { p_id: id });
	} catch {
		/* best-effort */
	}
}
