<script>
	import { onDestroy } from 'svelte';
	import { fmtSecs } from '$lib/time.js';

	/** @type {number|null} */ export let openedAt = null; // server-stamped epoch ms
	/** @type {number|null} */ export let bestSeconds = null; // PB ghost, seconds
	export let active = false; // running only while the puzzle is unsolved + on-screen
	export let solved = false; // freeze + relabel once solved
	export let revealOffsetMs = 1800; // don't charge the player for the opening reveal

	let now = Date.now();
	/** @type {ReturnType<typeof setInterval>|undefined} */ let timer;
	/** @type {number|null} */ let frozen = null; // captured once at solve

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
	$: mmss = `${Math.floor(shown / 60)}:${String(shown % 60).padStart(2, '0')}`;
</script>

{#if openedAt}
	<div class="solve-timer" class:done={solved} aria-label="Solve time">
		{#if solved}<span class="st-lbl">Solved in</span>{/if}
		<span class="st-val">{mmss}</span>
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
</style>
