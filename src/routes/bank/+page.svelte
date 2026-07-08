<script>
	import { onMount } from 'svelte';
	import PageNav from '$lib/components/PageNav.svelte';
	import { getBank, getProfileDetail, getCreditDetail } from '$lib/stores/statsStore.js';
	import AccountCard from '$lib/components/AccountCard.svelte';
	import CreditGauge from '$lib/components/CreditGauge.svelte';
	import LoanPanel from '$lib/components/LoanPanel.svelte';
	import { reasonLabel } from '$lib/bankReasons.js';
	import { track } from '$lib/analytics.js';

	/** @type {{ bank:number, net_worth:number, loan:number, loan_cap:number, in_the_red:boolean, ledger:any[], credit_score:number, credit_tier:string, credit_delta:number }|null} */
	let b = null;
	/** @type {any} */
	let prof = null;
	/** @type {any} */
	let cd = null;
	let loading = true;

	async function load() {
		b = await getBank(500);
	}
	onMount(async () => {
		track('bank_view');
		try {
			const [p, c] = await Promise.all([getProfileDetail(), getCreditDetail(), load()]);
			prof = p;
			cd = c;
		} finally {
			loading = false;
		}
	});

	const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();
	const dateOnly = (/** @type {string} */ at) =>
		at ? new Date(at).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : '';

	// Ledger filters: by statement period (month/year), by type, and sort by date/amount.
	// Custom dropdowns so the menu opens downward over the ledger.
	let typeFilter = 'all';
	let periodFilter = 'all'; // 'all' | 'YYYY-MM'
	let sortBy = 'newest';
	/** @type {null|'type'|'period'|'sort'} */
	let openMenu = null;
	const SORTS = [
		{ k: 'newest', label: 'Newest' },
		{ k: 'oldest', label: 'Oldest' },
		{ k: 'largest', label: 'Largest' },
		{ k: 'smallest', label: 'Smallest' }
	];
	const monthKey = (/** @type {string} */ at) => {
		const d = new Date(at);
		return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
	};
	$: sortLabel = SORTS.find((s) => s.k === sortBy)?.label ?? 'Newest';
	$: ledgerTypes = b ? [...new Set(b.ledger.map((/** @type {any} */ e) => e.reason))] : [];
	// Distinct statement periods present in the ledger, newest first: [[key, label], …]
	$: periods = b
		? [
				...new Map(
					b.ledger.map((/** @type {any} */ e) => [
						monthKey(e.at),
						new Date(e.at).toLocaleDateString(undefined, { month: 'long', year: 'numeric' })
					])
				).entries()
			].sort((a, b) => b[0].localeCompare(a[0]))
		: [];
	$: periodLabel =
		periodFilter === 'all'
			? 'All dates'
			: (periods.find((p) => p[0] === periodFilter)?.[1] ?? 'All dates');
	$: shownLedger = (b ? [...b.ledger] : [])
		.filter((/** @type {any} */ e) => typeFilter === 'all' || e.reason === typeFilter)
		.filter((/** @type {any} */ e) => periodFilter === 'all' || monthKey(e.at) === periodFilter)
		.sort((/** @type {any} */ x, /** @type {any} */ y) => {
			if (sortBy === 'oldest') return new Date(x.at).getTime() - new Date(y.at).getTime();
			if (sortBy === 'largest') return Math.abs(y.delta) - Math.abs(x.delta);
			if (sortBy === 'smallest') return Math.abs(x.delta) - Math.abs(y.delta);
			return new Date(y.at).getTime() - new Date(x.at).getTime();
		});
</script>

<svelte:head><title>WordBank — My Account</title></svelte:head>

<main class="bank-page">
	<PageNav />
	<h1 class="bank-title">My Account</h1>

	{#if loading}
		<p class="loading">Loading…</p>
	{:else if b}
		<!-- 💳 Account card hero — balance + identity -->
		<div class="ac-hero">
			<AccountCard
				holder={prof?.username ?? ''}
				account={prof?.account_number ?? ''}
				member={prof?.member_no ?? null}
				balance={b.bank}
				tier={b.credit_tier ?? 'Good'}
			/>
		</div>

		<!-- 💳 Credit score -->
		<section class="credit-sec">
			<h2 class="hist-title">Credit Score</h2>
			<CreditGauge
				score={b.credit_score ?? 650}
				tier={b.credit_tier ?? 'Good'}
				delta={b.credit_delta ?? 0}
				detail={cd}
			/>
		</section>

		<!-- 💸 Loan Shark -->
		<LoanPanel bank={b} on:changed={load} />

		<!-- Ledger -->
		<div class="led-head">
			<h2 class="hist-title">Statement</h2>
			{#if b.ledger.length}
				<div class="led-filters">
					<div class="led-dd">
						<button
							class="led-sel"
							onclick={() => (openMenu = openMenu === 'period' ? null : 'period')}
							>{periodLabel} <span class="dd-cv">▾</span></button
						>
						{#if openMenu === 'period'}
							<div class="led-menu">
								<button
									class:on={periodFilter === 'all'}
									onclick={() => {
										periodFilter = 'all';
										openMenu = null;
									}}>All dates</button
								>
								{#each periods as p}<button
										class:on={periodFilter === p[0]}
										onclick={() => {
											periodFilter = p[0];
											openMenu = null;
										}}>{p[1]}</button
									>{/each}
							</div>
						{/if}
					</div>
					<div class="led-dd">
						<button class="led-sel" onclick={() => (openMenu = openMenu === 'type' ? null : 'type')}
							>{typeFilter === 'all' ? 'All types' : reasonLabel(typeFilter)}
							<span class="dd-cv">▾</span></button
						>
						{#if openMenu === 'type'}
							<div class="led-menu">
								<button
									class:on={typeFilter === 'all'}
									onclick={() => {
										typeFilter = 'all';
										openMenu = null;
									}}>All types</button
								>
								{#each ledgerTypes as t}<button
										class:on={typeFilter === t}
										onclick={() => {
											typeFilter = t;
											openMenu = null;
										}}>{reasonLabel(t)}</button
									>{/each}
							</div>
						{/if}
					</div>
					<div class="led-dd">
						<button class="led-sel" onclick={() => (openMenu = openMenu === 'sort' ? null : 'sort')}
							>{sortLabel} <span class="dd-cv">▾</span></button
						>
						{#if openMenu === 'sort'}
							<div class="led-menu">
								{#each SORTS as s}<button
										class:on={sortBy === s.k}
										onclick={() => {
											sortBy = s.k;
											openMenu = null;
										}}>{s.label}</button
									>{/each}
							</div>
						{/if}
					</div>
				</div>
			{/if}
		</div>
		{#if openMenu}<button
				class="led-backdrop"
				onclick={() => (openMenu = null)}
				aria-label="Close"
				tabindex="-1"
			></button>{/if}
		{#if b.ledger.length === 0}
			<p class="empty">
				No transactions yet. Win the Daily, show up for attendance, or climb the Cash Game to grow
				your Cash.
			</p>
		{:else if shownLedger.length === 0}
			<p class="empty">No transactions for these filters.</p>
		{:else}
			<div class="ledger scroll">
				{#each shownLedger as e}
					<div class="led-row">
						<span class="led-date">{dateOnly(e.at)}</span>
						<span class="led-reason">{reasonLabel(e.reason)}</span>
						<span class="led-delta" class:pos={e.delta > 0} class:neg={e.delta < 0}
							>{e.delta > 0 ? '+' : '−'}{fmt(Math.abs(e.delta))}</span
						>
					</div>
				{/each}
			</div>
		{/if}
	{/if}
</main>

<style>
	.bank-page {
		max-width: 480px;
		margin: 0 auto;
		padding: 1.5rem 1rem 3rem;
	}
	.bank-title {
		font-family: var(--font-display);
		font-size: 1.5rem;
		margin: 4px 0 16px;
		text-align: center;
	}
	.loading {
		color: var(--text-muted);
		padding: 2rem;
		text-align: center;
	}

	.ac-hero {
		margin-bottom: 14px;
	}
	.credit-sec {
		margin: 4px 0 16px;
	}
	.credit-sec .hist-title {
		text-align: center;
		margin-bottom: 8px;
	}

	.led-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		margin: 1.4rem 0 0.6rem;
		flex-wrap: wrap;
	}
	.hist-title {
		font-family: var(--font-display);
		font-size: 1rem;
		margin: 0;
	}
	.led-filters {
		display: flex;
		gap: 6px;
	}
	.led-dd {
		position: relative;
	}
	.led-sel {
		display: flex;
		align-items: center;
		gap: 5px;
		padding: 6px 10px;
		border-radius: 9px;
		border: 1px solid var(--border);
		background: var(--surface);
		color: var(--text);
		font-size: 0.74rem;
		font-weight: 600;
		cursor: pointer;
		white-space: nowrap;
	}
	.led-sel:hover {
		border-color: var(--brand-2);
	}
	.dd-cv {
		color: var(--text-faint);
		font-size: 0.7rem;
	}
	.led-backdrop {
		position: fixed;
		inset: 0;
		z-index: 25;
		background: transparent;
		border: none;
		cursor: default;
	}
	.led-menu {
		position: absolute;
		top: calc(100% + 4px);
		right: 0;
		z-index: 30;
		min-width: 150px;
		max-height: 260px;
		overflow-y: auto;
		display: flex;
		flex-direction: column;
		padding: 5px;
		border-radius: 12px;
		background: var(--surface-strong, rgba(20, 26, 38, 0.98));
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		box-shadow: 0 16px 40px rgba(0, 0, 0, 0.55);
	}
	.led-menu button {
		text-align: left;
		padding: 8px 10px;
		border-radius: 8px;
		border: none;
		background: none;
		color: var(--text);
		cursor: pointer;
		font-size: 0.82rem;
		white-space: nowrap;
	}
	.led-menu button:hover {
		background: rgba(255, 255, 255, 0.06);
	}
	.led-menu button.on {
		color: var(--brand-2);
		font-weight: 700;
	}
	.empty {
		color: var(--text-muted);
		font-size: 0.9rem;
		text-align: center;
		padding: 1rem 0;
	}
	.ledger {
		display: flex;
		flex-direction: column;
		gap: 1px;
		background: var(--border);
		border-radius: 12px;
		overflow: hidden;
	}
	.ledger.scroll {
		max-height: 300px;
		overflow-y: auto;
	}
	.led-row {
		display: grid;
		grid-template-columns: auto 1fr auto;
		align-items: center;
		gap: 10px;
		padding: 0.5rem 0.8rem;
		background: var(--surface);
	}
	.led-date {
		font-size: 0.72rem;
		color: var(--text-faint);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.led-reason {
		color: var(--text);
		font-size: 0.86rem;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.led-delta {
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 0.88rem;
		white-space: nowrap;
	}
	.led-delta.pos {
		color: var(--brand-2);
	}
	.led-delta.neg {
		color: #fb7185;
	}
</style>
