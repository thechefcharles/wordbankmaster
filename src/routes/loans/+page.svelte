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

	$: inDebt = !!b?.in_the_red;
</script>

<svelte:head><title>WordBank — Loans</title></svelte:head>

<main class="loans-page">
	<PageNav back="/" />

	<!-- 🦈 Shark hero — placeholder art now; animation pass lands here later -->
	<div class="shark-hero" class:owe={inDebt}>
		<div class="shark-art" aria-hidden="true">🦈</div>
		<h1 class="shark-title">Loan Shark</h1>
		<p class="shark-sub">
			{#if inDebt}
				The Shark's circling. Interest compounds every day it's out — pay it down before it bites.
			{:else}
				Need Cash fast? Borrow on the spot. Interest compounds daily and the more you take, the
				steeper the rate — so borrow smart and pay it back quick.
			{/if}
		</p>
	</div>

	{#if loading}
		<p class="loading">Loading…</p>
	{:else if b}
		<LoanPanel bank={b} expanded on:changed={load} />

		<!-- How the Shark charges -->
		<div class="rate-card">
			<div class="rc-head">Daily interest — the more you borrow, the higher the rate</div>
			<div class="rc-rows">
				<div class="rc-row"><span>Up to 25% of your limit</span><b>5% / day</b></div>
				<div class="rc-row"><span>Up to 50%</span><b>8% / day</b></div>
				<div class="rc-row"><span>Up to 75%</span><b class="hot">12% / day</b></div>
				<div class="rc-row"><span>Above 75%</span><b class="hot">15% / day</b></div>
			</div>
			<p class="rc-note">
				Compounds daily · never grows past <b>2.5×</b> what you borrowed · half of every payout auto-pays
				it down.
			</p>
		</div>
	{/if}
</main>

<style>
	.loans-page {
		max-width: 460px;
		margin: 0 auto;
		padding: 12px 16px 40px;
	}
	.shark-hero {
		text-align: center;
		padding: 8px 6px 18px;
	}
	.shark-art {
		font-size: 4.6rem;
		line-height: 1;
		filter: drop-shadow(0 8px 22px rgba(56, 189, 248, 0.4));
		animation: sharkBob 3.4s ease-in-out infinite;
	}
	.shark-hero.owe .shark-art {
		filter: drop-shadow(0 8px 22px rgba(248, 113, 113, 0.5));
	}
	@keyframes sharkBob {
		0%,
		100% {
			transform: translateY(0) rotate(-2deg);
		}
		50% {
			transform: translateY(-8px) rotate(2deg);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.shark-art {
			animation: none;
		}
	}
	.shark-title {
		font-family: var(--font-display);
		font-weight: 800;
		font-size: 1.7rem;
		margin: 8px 0 4px;
		color: var(--text, #f4f6fb);
	}
	.shark-sub {
		font-size: 0.9rem;
		line-height: 1.5;
		color: var(--text-muted, #aeb8c6);
		max-width: 340px;
		margin: 0 auto;
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
	.rc-note {
		font-size: 0.74rem;
		line-height: 1.45;
		color: var(--text-faint, #8a93a3);
		margin: 10px 0 0;
	}
	.rc-note b {
		color: var(--text-muted, #aeb8c6);
	}
</style>
