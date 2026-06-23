// Global notification service: polls the server, exposes the unread count + list,
// and surfaces brand-new items as transient toasts (visible from any screen).
import { writable } from 'svelte/store';
import { getNotifications, markNotificationsRead } from '$lib/stores/statsStore.js';

/** @type {import('svelte/store').Writable<any[]>} */
export const notifications = writable([]);
export const unreadCount = writable(0);
/** @type {import('svelte/store').Writable<{id:string,title:string,body:string,data:any}[]>} */
export const toasts = writable([]);

/** Bumped when something (e.g. a tapped challenge toast) wants the home Challenges inbox opened. */
export const inboxRequest = writable(0);
export function requestInbox() { inboxRequest.update((n) => n + 1); }

const POLL_MS = 45000;
/** @type {ReturnType<typeof setInterval>|undefined} */
let pollTimer;
/** @type {Set<string>} */
let knownIds = new Set();
let started = false;
let primed = false; // first poll seeds knownIds without toasting history
/** @type {(() => void)|undefined} */
let onVis;

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
  toasts.update((t) => [...t, { id: n.id, title: n.title, body: n.body, data: n.data }]);
  setTimeout(() => dismissToast(n.id), 6000);
}
/** @param {string} id */
export function dismissToast(id) {
  toasts.update((t) => t.filter((x) => x.id !== id));
}

export function startNotifications() {
  if (started || typeof window === 'undefined') return;
  started = true;
  poll();
  pollTimer = setInterval(poll, POLL_MS);
  onVis = () => { if (!document.hidden) poll(); };
  document.addEventListener('visibilitychange', onVis);
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
  if (onVis && typeof document !== 'undefined') document.removeEventListener('visibilitychange', onVis);
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
