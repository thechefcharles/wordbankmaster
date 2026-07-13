<script>
	import { onMount } from 'svelte';
	import PageNav from '$lib/components/PageNav.svelte';
	import { getBank, getCreditDetail } from '$lib/stores/statsStore.js';
	import CreditGauge from '$lib/components/CreditGauge.svelte';
	import LoanPanel from '$lib/components/LoanPanel.svelte';
	import { reasonLabel } from '$lib/bankReasons.js';
	import { cardName, TIER_LADDER } from '$lib/creditTiers.js';
	import Icon from '$lib/components/Icon.svelte';
	import { track } from '$lib/analytics.js';

	// Info modals: the credit-tier ladder (which score unlocks which card) and the
	// "how loans work" explainer.
	let showTiers = false;
	let showLoanHelp = false;

	/** @type {{ bank:number, net_worth:number, loan:number, loan_cap:number, in_the_red:boolean, ledger:any[], credit_score:number, credit_tier:string, credit_delta:number }|null} */
	let b = null;
	/** @type {any} */
	let cd = null;
	let loading = true;

	async function load() {
		b = await getBank(500);
	}
	onMount(async () => {
		track('bank_view');
		try {
			[cd] = await Promise.all([getCreditDetail(), load()]);
		} finally {
			loading = false;
		}
	});

	const fmt = (/** @type {number} */ n) => '$' + Math.round(n ?? 0).toLocaleString();
	// Signed money: renders a leading minus outside the $ (−$51, not $-51).
	const fmtSigned = (/** @type {number} */ n) => {
		const v = Math.round(n ?? 0);
		return (v < 0 ? '−$' : '$') + Math.abs(v).toLocaleString();
	};
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
		<!-- 💰 Available Balance — clean line, no card -->
		<div class="bal-line">
			<span class="bal-cap">Available Balance</span>
			<span class="bal-amt">
				<img class="bal-coin" src="/logo-coin.png" alt="" width="28" height="28" />
				{fmt(b.bank)}
			</span>
			{#if Number(b.loan ?? 0) > 0}
				<span class="bal-net" class:neg={Number(b.net_worth ?? 0) < 0}
					>Net worth {fmtSigned(b.net_worth)}</span
				>
			{/if}
		</div>

		<!-- 💳 Credit score — the hero -->
		<section class="credit-sec">
			<CreditGauge
				score={b.credit_score ?? 650}
				tier={b.credit_tier ?? 'Good'}
				delta={b.credit_delta ?? 0}
				detail={cd}
				hero
			/>
			<button
				class="credit-card-name"
				onclick={() => (showTiers = true)}
				title="See what each card tier needs"
			>
				WordBank {cardName(b.credit_tier ?? 'Good')}
				<Icon name="info" size={13} />
			</button>
		</section>

		<!-- 💸 Loan Shark -->
		<LoanPanel bank={b} on:changed={load} />
		<button class="loan-help-link" onclick={() => (showLoanHelp = true)}>
			<Icon name="info" size={13} /> How loans work
		</button>

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

<!-- 💳 Credit tier ladder — which score unlocks which card, and how it affects loans. -->
{#if showTiers}
	<div
		class="bk-modal-overlay"
		role="button"
		tabindex="0"
		aria-label="Close"
		onclick={() => (showTiers = false)}
		onkeydown={(e) => (e.key === 'Escape' || e.key === 'Enter') && (showTiers = false)}
	>
		<!-- svelte-ignore a11y_no_noninteractive_element_interactions a11y_click_events_have_key_events -->
		<div
			class="bk-modal"
			role="dialog"
			aria-modal="true"
			aria-label="Card tiers"
			onclick={(e) => e.stopPropagation()}
		>
			<div class="bk-modal-head">
				<h2>Card tiers</h2>
				<button class="bk-modal-x" onclick={() => (showTiers = false)} aria-label="Close"
					><Icon name="close" size={16} /></button
				>
			</div>
			<p class="bk-modal-intro">
				Your credit score (300–850) sets your card. A better card raises your loan limit and lowers
				your interest.
			</p>
			<div class="tier-list">
				{#each TIER_LADDER as t}
					<div class="tier-row" class:current={t.tier === (b?.credit_tier ?? 'Good')}>
						<div class="tier-l">
							<span class="tier-card">WordBank {t.card}</span>
							<span class="tier-range">{t.range}</span>
						</div>
						<span class="tier-effect">{t.effect}</span>
						{#if t.tier === (b?.credit_tier ?? 'Good')}<span class="tier-you">You</span>{/if}
					</div>
				{/each}
			</div>
		</div>
	</div>
{/if}

<!-- 🦈 How loans work — limit, interest, upfront fee, repayment. -->
{#if showLoanHelp}
	<div
		class="bk-modal-overlay"
		role="button"
		tabindex="0"
		aria-label="Close"
		onclick={() => (showLoanHelp = false)}
		onkeydown={(e) => (e.key === 'Escape' || e.key === 'Enter') && (showLoanHelp = false)}
	>
		<!-- svelte-ignore a11y_no_noninteractive_element_interactions a11y_click_events_have_key_events -->
		<div
			class="bk-modal"
			role="dialog"
			aria-modal="true"
			aria-label="How loans work"
			onclick={(e) => e.stopPropagation()}
		>
			<div class="bk-modal-head">
				<h2>How loans work</h2>
				<button class="bk-modal-x" onclick={() => (showLoanHelp = false)} aria-label="Close"
					><Icon name="close" size={16} /></button
				>
			</div>
			<div class="help-list">
				<div class="help-item">
					<h3>How much you can borrow</h3>
					<p>
						Your limit is set by your card tier — better credit means a higher cap (see Card tiers).
						The base grows as you rank up in Cash Game.
					</p>
				</div>
				<div class="help-item">
					<h3>Your interest rate</h3>
					<p>
						Charged per day and it compounds. The base rate rises with how much of your limit you
						borrow: up to 25% of your limit is 5%/day, up to 50% is 8%/day, up to 75% is 12%/day,
						above that 15%/day. Your card tier then adjusts it — Reserve −3%, Plus +3%, Freedom +6%.
					</p>
				</div>
				<div class="help-item">
					<h3>The upfront fee</h3>
					<p>
						Borrowing costs an immediate fee — one day of interest, or 10% of the loan, whichever is
						larger. It's added to what you owe the moment you borrow.
					</p>
				</div>
				<div class="help-item">
					<h3>Paying it back</h3>
					<p>
						Repay any amount, any time. While you owe, the Store is locked and half of every payout
						auto-repays your loan. What you owe keeps growing daily until it's clear, capped at 2.5×
						what you borrowed.
					</p>
				</div>
			</div>
		</div>
	</div>
{/if}

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

	.bal-line {
		text-align: center;
		margin: 2px 0 18px;
	}
	.bal-cap {
		display: block;
		font-size: 0.72rem;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--text-muted);
	}
	.bal-amt {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		font-size: 2rem;
		line-height: 1.1;
		font-variant-numeric: tabular-nums;
		color: var(--text);
	}
	.bal-coin {
		width: 28px;
		height: 28px;
		object-fit: contain;
		filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.4));
	}
	/* True net worth (Available − loan) — shown under the balance only when in debt. */
	.bal-net {
		display: block;
		margin-top: 4px;
		font-family: var(--font-display, sans-serif);
		font-weight: 700;
		font-size: 0.98rem;
		font-variant-numeric: tabular-nums;
		color: #7ee0a8;
	}
	.bal-net.neg {
		color: #fb7185;
	}
	.credit-sec {
		margin: 4px 0 18px;
		text-align: center;
	}
	.credit-card-name {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		margin-top: 8px;
		padding: 4px 10px;
		border-radius: 999px;
		cursor: pointer;
		background: none;
		border: 1px solid var(--border);
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		font-size: 0.9rem;
		letter-spacing: 0.02em;
		color: var(--brand-2, #fde047);
		transition: border-color 0.15s;
	}
	.credit-card-name:hover {
		border-color: var(--brand-2, #fde047);
	}
	/* "How loans work" link under the loan panel. */
	.loan-help-link {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		margin: -4px auto 18px;
		padding: 4px 8px;
		background: none;
		border: none;
		cursor: pointer;
		color: var(--text-muted);
		font-size: 0.8rem;
		font-weight: 600;
	}
	.loan-help-link:hover {
		color: var(--text);
	}
	/* Info modals (card tiers + how loans work) */
	.bk-modal-overlay {
		position: fixed;
		inset: 0;
		z-index: 4000;
		display: grid;
		place-items: center;
		padding: 22px;
		background: rgba(4, 8, 14, 0.72);
		backdrop-filter: blur(6px);
	}
	.bk-modal {
		width: 100%;
		max-width: 380px;
		max-height: 82vh;
		overflow-y: auto;
		padding: 20px 20px 22px;
		border-radius: 18px;
		text-align: left;
		background: var(--surface-strong, rgba(20, 26, 38, 0.98));
		border: 1px solid var(--border-strong, rgba(255, 255, 255, 0.16));
		box-shadow: 0 20px 50px rgba(0, 0, 0, 0.5);
	}
	.bk-modal-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: 6px;
	}
	.bk-modal-head h2 {
		margin: 0;
		font-family: var(--font-display, sans-serif);
		font-size: 1.2rem;
		font-weight: 800;
	}
	.bk-modal-x {
		display: grid;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: 10px;
		background: var(--surface);
		border: 1px solid var(--border);
		color: var(--text-muted);
		cursor: pointer;
	}
	.bk-modal-intro {
		margin: 0 0 14px;
		font-size: 0.84rem;
		line-height: 1.45;
		color: var(--text-muted);
	}
	.tier-list {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.tier-row {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 10px 12px;
		border-radius: 12px;
		background: var(--surface);
		border: 1px solid var(--border);
	}
	.tier-row.current {
		border-color: var(--brand-2, #fde047);
		background: rgba(253, 224, 71, 0.08);
	}
	.tier-l {
		display: flex;
		flex-direction: column;
		gap: 1px;
		flex: none;
		min-width: 108px;
	}
	.tier-card {
		font-family: var(--font-display, sans-serif);
		font-weight: 800;
		font-size: 0.86rem;
		color: var(--brand-2, #fde047);
	}
	.tier-range {
		font-size: 0.72rem;
		color: var(--text-faint);
		font-variant-numeric: tabular-nums;
	}
	.tier-effect {
		flex: 1;
		font-size: 0.76rem;
		line-height: 1.35;
		color: var(--text-muted);
	}
	.tier-you {
		flex: none;
		align-self: flex-start;
		font-size: 0.6rem;
		font-weight: 800;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: #2a1005;
		background: var(--brand-2, #fde047);
		padding: 2px 6px;
		border-radius: 999px;
	}
	.help-list {
		display: flex;
		flex-direction: column;
		gap: 14px;
		margin-top: 8px;
	}
	.help-item h3 {
		margin: 0 0 3px;
		font-family: var(--font-display, sans-serif);
		font-size: 0.92rem;
		font-weight: 800;
		color: var(--text);
	}
	.help-item p {
		margin: 0;
		font-size: 0.82rem;
		line-height: 1.5;
		color: var(--text-muted);
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
