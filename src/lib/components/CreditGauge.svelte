<script>
	// 💳 Credit score gauge — 300–850 arc dial + tier + delta, tap for breakdown.
	export let score = 650;
	export let tier = 'Good';
	export let delta = 0;
	/** @type {any} */ export let detail = null;

	let open = false;
	const MIN = 300,
		MAX = 850;
	const R = 80,
		C = 2 * Math.PI * R,
		SWEEP = 0.75; // 3/4 circle
	$: pct = Math.max(0, Math.min(1, (score - MIN) / (MAX - MIN)));
	$: dash = pct * C * SWEEP;
	$: tierColor =
		tier === 'Excellent'
			? '#34d399'
			: tier === 'Good'
				? '#fbbf24'
				: tier === 'Fair'
					? '#f59e0b'
					: tier === 'Poor'
						? '#fb7185'
						: '#ef4444';
	$: comps = detail?.components
		? [
				detail.components.utilization,
				detail.components.solvency,
				detail.components.repayment,
				detail.components.restraint,
				detail.components.consistency
			].filter(Boolean)
		: [];
</script>

<div class="cg">
	<button class="cg-face" on:click={() => (open = !open)} aria-expanded={open}>
		<svg viewBox="0 0 200 200" class="cg-svg">
			<circle
				class="cg-track"
				cx="100"
				cy="100"
				r="80"
				stroke-dasharray="{C * 0.75} {C}"
				transform="rotate(135 100 100)"
			/>
			<circle
				class="cg-fill"
				cx="100"
				cy="100"
				r="80"
				stroke={tierColor}
				stroke-dasharray="{dash} {C}"
				transform="rotate(135 100 100)"
			/>
		</svg>
		<div class="cg-center">
			<span class="cg-score">{score}</span>
			<span class="cg-tier" style="color:{tierColor}">{tier}</span>
			{#if delta !== 0}
				<span class="cg-delta" class:pos={delta > 0} class:neg={delta < 0}
					>{delta > 0 ? '▲' : '▼'} {Math.abs(delta)}</span
				>
			{/if}
		</div>
	</button>
	{#if open && comps.length}
		<div class="cg-breakdown">
			{#each comps as c}
				<div class="cg-row">
					<span class="cg-rlabel">{c.label}</span>
					<span class="cg-bar"
						><span
							class="cg-barfill"
							style="width:{Math.round((c.value ?? 0) * 100)}%; background:{tierColor}"
						></span></span
					>
					<span class="cg-rhint">{c.hint}</span>
				</div>
			{/each}
		</div>
	{/if}
</div>

<style>
	.cg {
		width: 100%;
	}
	.cg-face {
		position: relative;
		width: 200px;
		max-width: 60%;
		margin: 0 auto;
		display: block;
		background: none;
		border: none;
		cursor: pointer;
		padding: 0;
	}
	.cg-svg {
		width: 100%;
		height: auto;
		display: block;
	}
	.cg-track {
		fill: none;
		stroke: var(--border, rgba(255, 255, 255, 0.1));
		stroke-width: 14;
		stroke-linecap: round;
	}
	.cg-fill {
		fill: none;
		stroke-width: 14;
		stroke-linecap: round;
		transition: stroke-dasharray 0.6s var(--ease-spring, ease);
	}
	.cg-center {
		position: absolute;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 2px;
	}
	.cg-score {
		font-family: var(--font-display, sans-serif);
		font-size: 2rem;
		font-weight: 800;
	}
	.cg-tier {
		font-size: 0.8rem;
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
	}
	.cg-delta {
		font-size: 0.72rem;
		font-weight: 700;
	}
	.cg-delta.pos {
		color: #34d399;
	}
	.cg-delta.neg {
		color: #fb7185;
	}
	.cg-breakdown {
		display: flex;
		flex-direction: column;
		gap: 8px;
		margin-top: 10px;
	}
	.cg-row {
		display: grid;
		grid-template-columns: 84px 1fr;
		grid-template-rows: auto auto;
		gap: 2px 8px;
		align-items: center;
	}
	.cg-rlabel {
		font-size: 0.78rem;
		font-weight: 700;
		color: var(--text);
	}
	.cg-bar {
		height: 7px;
		border-radius: 999px;
		background: var(--border, rgba(255, 255, 255, 0.1));
		overflow: hidden;
	}
	.cg-barfill {
		display: block;
		height: 100%;
		border-radius: 999px;
	}
	.cg-rhint {
		grid-column: 1 / -1;
		font-size: 0.72rem;
		color: var(--text-muted);
	}
</style>
