<script>
	import { onMount } from 'svelte';
	import PageNav from '$lib/components/PageNav.svelte';
	import LoanPanel from '$lib/components/LoanPanel.svelte';
	import { getBank } from '$lib/stores/statsStore.js';
	import { track } from '$lib/analytics.js';

	/** @type {any} */
	let b = null;
	let loading = true;

	async function load() {
		b = await getBank(1);
	}
	onMount(async () => {
		track('loans_view');
		try {
			await load();
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head><title>WordBank — Loans</title></svelte:head>

<main class="loans-page">
	<PageNav back="/" />

	<div class="loan-hero">
		<h1 class="loan-title">Loans</h1>
	</div>

	{#if loading}
		<p class="loading">Loading…</p>
	{:else if b}
		<LoanPanel bank={b} expanded on:changed={load} />

		<div class="rate-card">
			<div class="rc-head">Daily interest by amount</div>
			<div class="rc-rows">
				<div class="rc-row"><span>Up to 25% of your limit</span><b>5% / day</b></div>
				<div class="rc-row"><span>Up to 50%</span><b>8% / day</b></div>
				<div class="rc-row"><span>Up to 75%</span><b class="hot">12% / day</b></div>
				<div class="rc-row"><span>Above 75%</span><b class="hot">15% / day</b></div>
			</div>
		</div>
	{/if}
</main>

<style>
	.loans-page {
		max-width: 460px;
		margin: 0 auto;
		padding: 12px 16px 40px;
	}
	.loan-hero {
		text-align: center;
		padding: 6px 6px 16px;
	}
	.loan-title {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.7rem;
		margin: 0 0 4px;
		color: var(--text, #f4f6fb);
	}
	.loading {
		text-align: center;
		color: var(--text-muted);
		padding: 24px;
	}
	.rate-card {
		margin-top: 16px;
		border-radius: 16px;
		padding: 14px 16px;
		border: 1px solid var(--border, rgba(255, 255, 255, 0.1));
		background: var(--surface, rgba(255, 255, 255, 0.05));
	}
	.rc-head {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.82rem;
		color: var(--text, #f4f6fb);
		margin-bottom: 10px;
	}
	.rc-rows {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.rc-row {
		display: flex;
		justify-content: space-between;
		font-size: 0.84rem;
		color: var(--text-muted, #aeb8c6);
	}
	.rc-row b {
		font-family: var(--font-display);
		color: var(--text, #f4f6fb);
		font-variant-numeric: tabular-nums;
	}
	.rc-row b.hot {
		color: #fb7185;
	}
</style>
