<script>
	// Compact challenge standing: just your rank vs FINISHED rivals (never the exact
	// spend to beat) + a lead celebration. The money (left to spend + bar) lives in the
	// top bankroll bar now. Hidden until at least one rival has finished.
	import { fx } from '$lib/sound.js';
	import Icon from '$lib/components/Icon.svelte';

	/** @type {{ field_size:number, finished:number, rank:number, state:'lead'|'behind'|'tied'|'first_to_play', provisional?:boolean } | null} */
	export let standing = null;

	/** @type {string|undefined} */
	let prevState;
	function onStanding(/** @type {any} */ s) {
		if (s && s.state === 'lead' && prevState && prevState !== 'lead') fx('lead');
		prevState = s?.state;
	}
	$: onStanding(standing);

	const ord = (/** @type {number} */ n) => {
		const s = ['th', 'st', 'nd', 'rd'],
			v = n % 100;
		return n + (s[(v - 20) % 10] || s[v] || s[0]);
	};
	$: ranked = !!standing && standing.state !== 'first_to_play';
</script>

{#if ranked && standing}
	{#key standing.state}
		<div class="standing {standing.state}">
			<span class="rank"
				>{#if standing.rank >= 1 && standing.rank <= 3}<span class="rk-{standing.rank}"
						><Icon name="medal" size={15} /></span
					>{/if}
				{ord(standing.rank)} of {standing.field_size}{#if standing.provisional}<span class="sofar"
						>so far</span
					>{/if}</span
			>
			{#if standing.state === 'lead'}<span class="lead-badge"
					><Icon name="check" size={13} /> In the lead</span
				>{/if}
		</div>
	{/key}
{/if}

<style>
	.standing {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 10px;
		max-width: 360px;
		margin: 0 auto 6px;
		padding: 6px 14px;
		border-radius: 11px;
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		background: var(--surface, rgba(255, 255, 255, 0.05));
		font-family: var(--font-display, sans-serif);
		font-weight: 700;
		font-size: 0.9rem;
		color: var(--text, #fff);
		animation: stPop 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
	}
	@keyframes stPop {
		from {
			transform: scale(0.96);
			opacity: 0.5;
		}
		to {
			transform: scale(1);
			opacity: 1;
		}
	}
	.rk-1 {
		color: #fbbf24;
	}
	.rk-2 {
		color: #cbd5e1;
	}
	.rk-3 {
		color: #d19a66;
	}
	.sofar {
		margin-left: 6px;
		font-family: var(--font-ui, sans-serif);
		font-weight: 600;
		font-size: 0.62rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--text-faint, #8090a0);
	}
	.lead-badge {
		font-size: 0.78rem;
		font-weight: 700;
		color: #7ee0a8;
	}
	.standing.lead {
		border-color: rgba(126, 224, 168, 0.5);
		background: linear-gradient(135deg, rgba(126, 224, 168, 0.13), rgba(126, 224, 168, 0.04));
	}
	.standing.behind {
		border-color: rgba(251, 191, 36, 0.45);
	}
</style>
