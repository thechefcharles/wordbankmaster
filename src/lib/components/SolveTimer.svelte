<script>
	import { onDestroy, createEventDispatcher } from 'svelte';
	import { fmtSecs } from '$lib/time.js';

	/** @type {number|null} */ export let openedAt = null; // server-stamped epoch ms (anchor)
	/** @type {number|null} */ export let bestSeconds = null; // PB ghost, seconds (count-up only)
	export let active = false; // running only while the puzzle is unsolved + on-screen
	export let solved = false; // freeze + relabel once solved (count-up only)
	export let revealOffsetMs = 1800; // don't charge the player for the opening reveal (count-up only)
	// 🕐 Countdown mode: when set, render `countdownSeconds - elapsed` (a live challenge clock)
	// instead of the default count-up. No reveal offset — this must track the server's
	// `now() - anchor` exactly, since the server folds on the same math (_match_tick).
	/** @type {number|null} */ export let countdownSeconds = null;
	export let dangerAt = 10; // seconds remaining that trip the "danger" bindable + styling
	// Bindable outputs (countdown mode) — let a parent drive its own danger treatment.
	/** @type {number|null} */ export let remaining = null;
	export let danger = false;

	const dispatch = createEventDispatcher();

	let now = Date.now();
	/** @type {ReturnType<typeof setInterval>|undefined} */ let timer;
	/** @type {number|null} */ let frozen = null; // captured once at solve (count-up only)

	$: if (active && openedAt && !timer) {
		now = Date.now();
		timer = setInterval(() => (now = Date.now()), 1000);
	} else if ((!active || !openedAt) && timer) {
		clearInterval(timer);
		timer = undefined;
	}
	onDestroy(() => timer && clearInterval(timer));

	// Elapsed = now − server open − reveal offset. Anchored to the server, so leaving the
	// screen / quitting can't reset or pause it — it just keeps running.
	$: live = openedAt ? Math.max(0, Math.round((now - openedAt - revealOffsetMs) / 1000)) : 0;
	// Capture the final time exactly once at the solve transition; clear if a new day resets it.
	$: if (solved && openedAt && frozen === null)
		frozen = Math.max(0, Math.round((Date.now() - openedAt - revealOffsetMs) / 1000));
	$: if (!solved) frozen = null;
	$: shown = solved && frozen != null ? frozen : live;

	/** @param {number} sec */
	function mmss(sec) {
		return `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
	}

	// 🕐 Countdown: remaining seconds since `openedAt`, floored at 0. Reset the "fired once"
	// expiry guard whenever the anchor actually changes (a new puzzle/match clock started).
	/** @type {number|null} */ let lastAnchor = null;
	let expiredFired = false;
	$: if (openedAt !== lastAnchor) {
		lastAnchor = openedAt;
		expiredFired = false;
	}
	$: remaining =
		countdownSeconds != null && openedAt
			? Math.max(0, countdownSeconds - Math.floor((now - openedAt) / 1000))
			: null;
	$: danger = remaining != null && remaining <= dangerAt;
	// Fire once per anchor when the clock actually runs out, while still live — the caller
	// pokes the server (a fold/guess round-trip) so the authoritative tick resolves it.
	$: if (active && countdownSeconds != null && remaining === 0 && !expiredFired) {
		expiredFired = true;
		dispatch('expire');
	}
</script>

{#if countdownSeconds != null}
	{#if openedAt}
		<div class="solve-timer countdown" class:danger aria-label="Time remaining">
			<span class="st-val">{mmss(remaining ?? 0)}</span>
		</div>
	{/if}
{:else if openedAt}
	<div class="solve-timer" class:done={solved} aria-label="Solve time">
		{#if solved}<span class="st-lbl">Solved in</span>{/if}
		<span class="st-val">{mmss(shown)}</span>
		{#if bestSeconds != null}<span class="st-pb">PB {fmtSecs(bestSeconds)}</span>{/if}
	</div>
{/if}

<style>
	.solve-timer {
		display: inline-flex;
		align-items: baseline;
		gap: 8px;
		font-family: var(--font-ui);
		font-variant-numeric: tabular-nums;
		color: var(--text-faint, #8090a0);
		font-size: 0.8rem;
		letter-spacing: 0.04em;
	}
	.st-lbl {
		font-size: 0.68rem;
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}
	.st-val {
		font-weight: 700;
		color: var(--text-muted, #b0bcca);
	}
	.solve-timer.done .st-val {
		color: var(--brand-2, #7ee0a8);
	}
	.st-pb {
		font-size: 0.68rem;
		opacity: 0.7;
	}
	.solve-timer.countdown .st-val {
		font-size: 0.86rem;
	}
	.solve-timer.countdown.danger .st-val {
		color: var(--danger, #ff5d6c);
		animation: countdown-pulse 1s ease-in-out infinite;
	}
	@keyframes countdown-pulse {
		0%,
		100% {
			opacity: 1;
		}
		50% {
			opacity: 0.55;
		}
	}
</style>
