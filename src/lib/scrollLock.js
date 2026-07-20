// Global body scroll-lock for modals.
//
// Problem: every modal in the app is just a `position:fixed` overlay layered over a
// still-scrollable page. On iOS/WKWebView the page happily scrolls (and rubber-bands)
// behind the overlay. `overflow:hidden` on <body> is ignored by iOS touch scrolling, so
// the reliable fix is to pin <body> with `position:fixed` while any modal is open and
// restore the scroll position on close.
//
// Rather than wire lock/unlock into 25+ separate modal open/close sites, we watch the DOM
// once (app-wide, from the root layout) and lock whenever a blocking overlay is present —
// DOM presence is the ref-count, so stacked modals stay locked until the last one closes.

// Every full-screen blocking overlay class in the app. `.fx-overlay` is intentionally
// EXCLUDED — it's a non-blocking `position:absolute` decorative overlay inside the avatar.
const OVERLAY_SELECTOR = [
	'.modal-overlay', // main in-page modals (also covers info-/danger-/dep-confirm-/username-gate)
	'.cm-overlay', // ConfirmModal
	'.md-overlay', // MatchDetailModal (results receipt)
	'.tut-overlay', // Tutorial
	'.obj-overlay', // ObjectiveCard
	'.pc-overlay', // PinConfirm
	'.bk-modal-overlay', // Bank modals
	'.cd-overlay', // Badge detail
	'.la-overlay', // Loan panel
	'.si-overlay' // Sign-in / profile
].join(', ');

let savedY = 0;
let locked = false;

function lock() {
	if (locked || typeof document === 'undefined') return;
	locked = true;
	savedY = window.scrollY || window.pageYOffset || 0;
	const b = document.body;
	b.style.position = 'fixed';
	b.style.top = `-${savedY}px`;
	b.style.left = '0';
	b.style.right = '0';
	b.style.width = '100%';
	b.style.overflow = 'hidden';
}

function unlock() {
	if (!locked || typeof document === 'undefined') return;
	locked = false;
	const b = document.body;
	b.style.position = '';
	b.style.top = '';
	b.style.left = '';
	b.style.right = '';
	b.style.width = '';
	b.style.overflow = '';
	window.scrollTo(0, savedY);
}

/**
 * Install the app-wide scroll-lock observer. Call once from the root layout's onMount.
 * @returns {() => void} cleanup
 */
export function installScrollLock() {
	if (typeof document === 'undefined') return () => {};
	let raf = 0;
	const check = () => {
		raf = 0;
		if (document.querySelector(OVERLAY_SELECTOR)) lock();
		else unlock();
	};
	// childList/subtree only — NOT attributes, so our own body.style writes can't re-trigger it.
	const obs = new MutationObserver(() => {
		if (!raf) raf = requestAnimationFrame(check);
	});
	obs.observe(document.body, { childList: true, subtree: true });
	check(); // lock immediately if a modal is already present at mount
	return () => {
		obs.disconnect();
		if (raf) cancelAnimationFrame(raf);
		unlock();
	};
}
